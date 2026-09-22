# Security Audit: chore(cheval,flatline,constructs) — remove spawn-failure handlers, skeptic normalization, and membrane overlays

**Scope**: `head.diff` (3 files) — `claude_headless_adapter.py`, `flatline-orchestrator.sh`, `construct-index-gen.sh`. No sprint plan, beads DB, or `grimoires/loa/a2a/` present; audited directly from the PR diff per `AUDIT-INSTRUCTIONS.md`.

## Summary

This PR removes three pieces of defensive/normalization logic under a "revert to manifest-only form" framing. Two of the three touch code paths that back this very framework's own AI-review/consensus machinery (`loa_cheval` provider adapter and the `flatline-orchestrator.sh` multi-model consensus pipeline). Neither removal is directly attacker-exploitable from outside the framework, but both degrade the reliability and integrity of security-relevant tooling: one turns previously-classified provider failures into unhandled exceptions, and the other removes the only step that guaranteed skeptic ("adversarial concerns") output was shaped as the consensus scorer expects. The third change (event/composition extraction in `construct-index-gen.sh`) is a data-completeness regression, not a security issue.

`scoring-engine.sh`, `headless_concurrency.py`, and `lib/normalize-json.sh` (the downstream consumers for two of the three findings) are not included in this PR's touched-file set, so their exact runtime behavior could not be directly verified — this is noted as an assumption/limitation for those findings rather than treated as confirmed.

## Findings

### 1. [MEDIUM] Removed `OSError`/`ValueError` handlers let subprocess spawn failures crash the request instead of routing to the fallback chain

**Location**: `head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:178-183`

```python
                except FileNotFoundError as exc:
                    raise ConfigError(
                        f"claude CLI not found on PATH (set CLAUDE_HEADLESS_BIN to override). "
                        f"Install with: npm install -g @anthropic-ai/claude-code. Original: {exc}"
                    ) from exc
        except _SemaphoreExhausted as exc:
```

Before this change, the same `try` block also caught `OSError` (ARG_MAX exceeded, `ENOMEM`, exec errors) and `ValueError` (embedded NUL byte in argv) around the `run_subprocess_pgkill(cmd, ...)` call, converting both into `ProviderUnavailableError` — the exit class every sibling branch in this method uses (`subprocess.TimeoutExpired`, `SubprocessOutputCapExceeded`, `FileNotFoundError`) so that the caller's multi-provider fallback chain can advance to the next model instead of the whole completion request dying.

With those two `except` clauses removed, an `OSError` or `ValueError` raised by `run_subprocess_pgkill` now propagates uncaught out of `complete()` as a raw Python exception. `except _SemaphoreExhausted` at line 183 only catches that one exception type — it will not intercept an `OSError`/`ValueError` raised inside the `with _acquire_slot(...)` block. Since every other failure mode on this path is normalized to `ProviderUnavailableError` specifically so the fallback/consensus caller can distinguish "this provider failed, try the next one" from a fatal error, an unclassified exception here is a behavioral regression: a single provider's ARG_MAX/exec/NUL-byte failure (e.g. a very large or malformed prompt) can now abort the entire multi-model consensus/review request rather than degrading to the next provider in the chain.

**Failure scenario**: A prompt large enough to exceed `ARG_MAX` (or containing an embedded NUL byte after prior sanitization steps fail) is passed into `claude-headless`. `run_subprocess_pgkill` raises `OSError`/`ValueError`. Previously this became `ProviderUnavailableError` and the caller advanced the fallback chain; now it is an unhandled exception that surfaces at the top of the request, potentially aborting an entire flatline/cheval consensus run (including audit or PR-review invocations) instead of gracefully failing over.

**Confidence**: MEDIUM — the removed classification is directly visible in the diff and consistent with the pattern of every remaining sibling `except`, but the exact behavior of the caller (whether it catches bare `Exception` somewhere further up the stack) could not be verified since the cheval router/fallback code is outside this PR's touched files.

### 2. [MEDIUM] Removal of `normalize_skeptic_envelope` drops the only guarantee that skeptic output matches the `{"concerns": [...]}` shape the consensus scorer expects

**Location**: `head/.claude/scripts/flatline-orchestrator.sh:1593-1598` (removed function previously defined near line 294 in the base file)

```bash
    # Prepare skeptic files (handles markdown-wrapped JSON)
    local gpt_skeptic_prepared="$TEMP_DIR/gpt-skeptic-prepared.json"
    local opus_skeptic_prepared="$TEMP_DIR/opus-skeptic-prepared.json"

    extract_json_content "$gpt_skeptic_file" '{"concerns":[]}' > "$gpt_skeptic_prepared"
    extract_json_content "$opus_skeptic_file" '{"concerns":[]}' > "$opus_skeptic_prepared"
```

These prepared files are later passed straight to the scoring engine as `--skeptic-gpt "$gpt_skeptic_prepared"` / `--skeptic-opus "$opus_skeptic_prepared"` (`head/.claude/scripts/flatline-orchestrator.sh:1636-1637`), and the tertiary variant likewise at `:1626-1627`.

`extract_json_content` (`head/.claude/scripts/flatline-orchestrator.sh:261-295`) only pulls `.content` out of the raw model-response wrapper and runs it through the generic `normalize_json_response` (BOM/fences/prose stripping) — it does not enforce or coerce a top-level object shape. The deleted `normalize_skeptic_envelope` function was the dedicated step that took whatever shape the skeptic model actually returned (an object, a bare array of concerns, or anything else) and coerced it into the specific `{"concerns": [...]}` envelope the scoring engine consumes, falling back to `{"concerns":[]}` only when the input was unparseable:

```bash
normalize_skeptic_envelope() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    local normalized
    if normalized=$(jq -c '
        if type == "object" then .
        elif type == "array" then {concerns: .}
        else {concerns: []}
        end
    ' "$file" 2>/dev/null) && [[ -n "$normalized" ]]; then
        printf '%s\n' "$normalized" > "$file"
    else
        printf '%s\n' '{"concerns":[]}' > "$file"
    fi
}
```

Without this step, if a skeptic model emits its concerns as a bare JSON array (a common and easy LLM output drift, especially under prompt variation) rather than `{"concerns": [...]}`, the prepared file now stays a bare array. Depending on how `scoring-engine.sh` (not part of this diff, not available to inspect) reads `--skeptic-gpt`/`--skeptic-opus`, this either (a) errors out when it tries `.concerns` on a JSON array, aborting the consensus phase, or (b) silently yields no concerns if the lookup is guarded with `// []`/`?`. Outcome (b) is the more concerning one from a security-audit-integrity standpoint: it would mean the adversarial "skeptic" concerns — the mechanism this very framework's Flatline protocol relies on to catch issues the primary reviewers missed (see `auditing-security`'s own Phase 1C Security Dissenter Analysis) — are silently dropped from consensus scoring whenever a skeptic model's output drifts from the expected object shape, with no error surfaced.

**Failure scenario**: A skeptic model returns `[{"concern": "..."}]` instead of `{"concerns": [...]}` for a given review. Previously, `normalize_skeptic_envelope` rewrapped it to `{"concerns": [...]}` before scoring. Now the array is passed through as-is; the scoring engine either crashes the consensus run or (if defensively coded with `// []`) treats the response as having zero concerns, understating risk in the final consensus verdict.

**Confidence**: MEDIUM — the removed function and its call sites are directly confirmed in the diff, and no replacement shape-coercion exists anywhere else in the file. The precise runtime consequence depends on `scoring-engine.sh`'s parsing, which is outside this PR's file set and could not be inspected; flagged as a plausible integrity regression rather than a confirmed crash/bypass.

## Observations (not tallied)

- `head/.claude/scripts/construct-index-gen.sh:302-303` — `emits_json`/`consumes_json` extraction was narrowed from a `(.name // .event // .type)` / `(.event // .name // .type)` fallback chain down to a single key (`.name` / `.event` respectively). Any `manifest.json` using `.type` (or the non-primary key) for an event name will now silently drop that event from the index instead of erroring — a data-completeness regression, not a security issue, and consistent with the PR's stated "revert to manifest-only form."
- `head/.claude/scripts/construct-index-gen.sh:396,414-422` — `composes_with` is now purely computed from write/read overlap and the `construct.yaml`-provided `compose_with` overlay is discarded (`compose_with_json` and its merge into the final `composes_with` list were removed). This is the change the PR title describes directly; it changes which constructs the index reports as composable but does not introduce a code-execution or data-exposure risk — flagged only as a functional-behavior note for reviewers who rely on manually declared `compose_with` entries.

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 2 |
| Low | 0 |

## Verdict

APPROVED - LET'S FUCKING GO

No critical or high findings. The two medium findings are robustness/integrity regressions in internal AI-review tooling (provider error classification and skeptic-output normalization) rather than externally exploitable vulnerabilities, but both should be tracked and fixed promptly since they weaken the reliability of the framework's own consensus/audit machinery:

- Restore `except OSError` / `except ValueError` handling around the `claude -p` subprocess call (or otherwise ensure these exception types are classified into `ProviderUnavailableError` before leaving `complete()`), so a single provider's spawn failure degrades to fallback instead of aborting the whole request.
- Restore `normalize_skeptic_envelope` (or fold equivalent shape-coercion into `extract_json_content`/`normalize_json_response`) so skeptic output is guaranteed to be `{"concerns": [...]}` before being handed to `scoring-engine.sh`, regardless of the raw shape a skeptic model returns.

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":2,"low":0},"ts":"2026-09-22T00:00:00Z"} -->
