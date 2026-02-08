# Sprint 2 (Global: sprint-65) — Implementation Report

## Sprint Goal
Default Adapters: Implement all 6 adapter types for the local one-shot use case. After this sprint, the skill can be invoked end-to-end locally.

## Task Summary

| Task | Title | Status | GPT Review | Files |
|------|-------|--------|------------|-------|
| 2.1 | GitHubCLIAdapter | DONE | APPROVED (iter 3, auto) | adapters/github-cli.ts |
| 2.2 | AnthropicAdapter | DONE | APPROVED (iter 2) | adapters/anthropic.ts |
| 2.3 | PatternSanitizer | DONE | APPROVED (iter 2) | adapters/sanitizer.ts |
| 2.4 | NodeHasher/ConsoleLogger/NoOpContextStore | DONE | Skipped (trivial) | 3 adapter files |
| 2.5 | Adapter factory and barrel | DONE | Skipped (wiring) | adapters/index.ts |
| 2.6 | Adapter unit tests | DONE | Skipped (tests) | 5 test files |

## Files Created

### Adapters (`resources/adapters/`)
- `github-cli.ts` — GitHubCLIAdapter implementing IGitProvider + IReviewPoster via `gh` CLI with `child_process.execFile`, endpoint allowlist (Layer 6), 30s timeout, `--paginate` on all list endpoints
- `anthropic.ts` — AnthropicAdapter implementing ILLMProvider via native `fetch()` to Anthropic Messages API, AbortController timeout (120s), exponential backoff with retry-after precedence (numeric + HTTP-date), 3 retries max
- `sanitizer.ts` — PatternSanitizer implementing IOutputSanitizer with 7 pattern categories (ghp_, ghs_, github_pat_, sk-ant-, sk-, AKIA, xox[bprs]-, BEGIN...END PRIVATE KEY) + Shannon entropy detection (>40 chars, >4.5 bits/char)
- `node-hasher.ts` — NodeHasher implementing IHasher via `crypto.createHash('sha256')`, async wrapper per port contract
- `console-logger.ts` — ConsoleLogger implementing ILogger with structured JSON output, secret redaction via DEFAULT_REDACT_PATTERNS, `console.error` for error level
- `noop-context.ts` — NoOpContextStore implementing IContextStore with all no-ops (load→void, getLastHash→null, setLastHash→void, claimReview→true, finalizeReview→void)
- `index.ts` — `createLocalAdapters(config, anthropicApiKey)` factory + barrel re-exports; GitHubCLIAdapter serves as both `git` and `poster` (dual-interface)

### Tests (`resources/__tests__/`)
- `sanitizer.test.ts` — 12 tests: all 7 pattern categories, high-entropy detection, >40 boundary, clean passthrough, multiple occurrences, custom patterns
- `node-hasher.test.ts` — 5 tests: empty string vector, known vector ("hello"), consistency, different inputs, hex format validation
- `console-logger.test.ts` — 6 tests: structured JSON output, data inclusion, GitHub PAT redaction, data value redaction, error level routing, all log levels
- `github-cli.test.ts` — 9 tests: marker detection (exact match, different SHA, partial prefix), marker format, response mapping (PR, files, binary, reviews), endpoint allowlist (6 valid + 5 invalid)
- `anthropic.test.ts` — 11 tests: request format, headers, response parsing (text content, token counts, missing content, missing usage), constructor validation, retry-after parsing (numeric, ceiling, invalid), backoff calculation

## GPT Review Findings Resolved

### github-cli.ts (3 issues fixed, 2 false positives)
1. **No endpoint allowlist** → Added `ALLOWED_API_ENDPOINTS` regex array + `assertAllowedArgs()` guard called before every `gh` invocation. SDD Layer 6 requirement.
2. **`--show-token` leaks token** → Changed `gh auth status --show-token` to `gh auth status` (without `--show-token`).
3. **Preflight null safety** → Added optional chaining: `resources?.core?.remaining ?? 0` instead of unsafe casts.
4. _(False positive)_ GPT flagged preflight 0-fallback as bug — correct design: 0 triggers "low remaining" warning per SDD.
5. _(False positive)_ GPT flagged exact marker match as too strict — correct per SDD: exact `<!-- bridgebuilder-review: {headSha} -->` match is the spec.

### anthropic.ts (3 issues fixed)
1. **Double delay on retry** → Original applied exponential backoff at loop start AND retry-after after 429. Fixed: `retryAfterMs` state variable — server retry-after takes precedence over exponential backoff.
2. **Missing parseRetryAfter()** → Added helper supporting both numeric seconds and HTTP-date format, with ceiling cap at 60s.
3. **HTTP-date format not supported** → Same fix as #2.

### sanitizer.ts (3 issues fixed)
1. **Private key header only** → Pattern only matched `-----BEGIN ... PRIVATE KEY-----`. Fixed to match full block: `-----BEGIN [A-Z ]+ PRIVATE KEY-----[\s\S]*?-----END [A-Z ]+ PRIVATE KEY-----`.
2. **Extra patterns missing global flag** → Added enforcement: `const flags = pattern.flags.includes("g") ? pattern.flags : pattern.flags + "g"`.
3. **High-entropy >=40 vs >40** → Spec says ">40 chars". Changed `HIGH_ENTROPY_MIN_LENGTH` from 40 to 41, regex from `{40,}` to `{41,}`.

## Self-Fixes (Pre-GPT)

### github-cli.ts
- **Dead `payload` variable** → Initial version had `const payload = JSON.stringify(...)` that was never used alongside conflicting `--input -` and `-f` flags. Removed payload and `--input -`, using only `--raw-field` and `-f` flags.

## Test Results

```
ℹ tests 43
ℹ suites 14
ℹ pass 43
ℹ fail 0
```

All 43 tests pass across 5 test files: PatternSanitizer (12), NodeHasher (5), ConsoleLogger (6), GitHubCLIAdapter (9), AnthropicAdapter (11).

### Test Fix History
- `anthropic.test.ts` text join mismatch: test data had extra `\n\n` prefix causing triple newline on join. Fixed test data and expected string.

## Architecture Compliance

- **Hexagonal boundary**: All adapters depend only on port interfaces. No cross-adapter imports.
- **Zero npm dependencies**: All adapters use only Node built-ins (`node:crypto`, `node:child_process`, native `fetch`).
- **Token isolation**: GitHub tokens handled by `gh` CLI, never in adapter code. Anthropic key as `x-api-key` header only.
- **Endpoint allowlist**: GitHubCLIAdapter enforces Layer 6 hardcoded regex allowlist — prevents unauthorized API calls.
- **ESM conventions**: All imports use `.js` extensions for NodeNext resolution.
- **No secrets**: No hardcoded tokens, keys, or credentials.
- **Dual-interface pattern**: GitHubCLIAdapter implements both IGitProvider and IReviewPoster, wired as both `git` and `poster` in factory.

## Known Deviations from SDD

1. **GitHubCLIAdapter also implements IReviewPoster** — SDD describes them as separate adapters, but both use `gh` CLI so combining avoids duplicating the execFile wrapper. Factory exposes the same instance for both roles.
2. **ConsoleLogger uses DEFAULT_REDACT_PATTERNS constant** instead of accepting patterns as constructor param — keeps the API simple; custom patterns can be added via subclass.
3. **createLocalAdapters() takes explicit `anthropicApiKey` param** instead of reading from `process.env` internally — allows testing without env pollution.

## Beads Task Status

All 6 tasks closed:
- bd-2bp (2.1 GitHubCLIAdapter)
- bd-31m (2.2 AnthropicAdapter)
- bd-3by (2.3 PatternSanitizer)
- bd-2ru (2.4 NodeHasher/ConsoleLogger/NoOpContextStore)
- bd-1dm (2.5 Adapter factory and barrel)
- bd-1bg (2.6 Adapter unit tests)
