# Bug Triage: Coupled model-stability rollback restoration (#787 + #789)

## Metadata
- **schema_version**: 1
- **bug_id**: 20260508-i789-e3f89e
- **classification**: regression / silent-degradation
- **severity**: high
- **eligibility_score**: 7
- **eligibility_reasoning**: Repro steps verified live in cycle-100 sprint-2 BB iter-1 (+2); failing observed test/assertion: `Empty response content × 3 retries` (+2); stack-trace file:line refs verified to exist on disk — `dist/adapters/openai.js:17`, `dist/adapters/index.js:17`, `dist/main.js:387`, `model-adapter.sh.legacy:566-570` (+1); production incident error logs from BB iter-1 quoted in #789 + #787 (+1); regression cited from cycle-099 PR #754 BB E2E green pin at `gpt-5.5-pro 153s` on smaller diff (+1). No disqualifiers — restoring previously-working behavior, not new feature work; touches adapter timeouts, probe gate, jq parser, config restoration only. Rolled-back commit `cd4abc1f` is the explicit baseline this work reverses.
- **test_type**: unit (TS adapter unit tests + bash bats parity tests)
- **risk_level**: high — model adapters are load-bearing across BB / Flatline / `/review-sprint` / `/audit-sprint`; touching auth/credential-adjacent code paths
- **created**: 2026-05-08
- **source_issues**: #787, #789
- **rolled-back commit**: cd4abc1f (cycle-100 sprint-2 BB iter-1)

## Reproduction

### Steps

**#789a (BB OpenAI timeout)**:
1. Restore `.loa.config.yaml::bridgebuilder.multi_model.models[reviewer#1].model_id` to `gpt-5.5-pro`.
2. Run `/run-bridge` against any PR with a >= 90k-token diff (e.g., a multi-sprint stacked PR like cycle-100 sprint-2 PR #788).
3. Observe: `[multi-model:openai] Review failed — "OpenAI API request timed out" (>900s)`. Tri-model BB silently degrades to single-model (Anthropic only).

**#789b (Google preview probe)**:
1. Restore `.loa.config.yaml::bridgebuilder.multi_model.models[reviewer#2].model_id` to `gemini-3.1-pro-preview`.
2. Run `/run-bridge` during a window where the preview tier is unstable (observed 2026-05-07 + 2026-05-08).
3. Observe: `[multi-model:google] Review failed — "Google API network error"` early in the call. No invoke-time probe rejection; degrades silently.

**#787 (legacy bash adapter parsing)**:
```bash
.claude/scripts/adversarial-review.sh \
  --type review \
  --sprint-id sprint-test \
  --diff-file <(git diff HEAD~1 HEAD) \
  --context-file /dev/null \
  --model gpt-5.5-pro \
  --json
```
Output: `[model-adapter] Empty response content` × 3 retries → `ERROR: API call failed with exit code 5`.

### Expected Behavior
- BB tri-model run on a 95k-token diff completes with all 3 providers returning consensus output.
- Google preview model failures surface as a config-time WARN/error, not a silent single-model degrade.
- `gpt-5.5-pro` adversarial dissent through legacy bash adapter returns parsed content from the `/v1/responses` shape.
- `.loa.config.yaml` references the latest cycle-099-blessed reasoning-class triad without rollback comments.

### Actual Behavior
- OpenAI adapter aborts at 300s (`adapters/index.ts:44-45` cap) on long diffs even though `gpt-5.5-pro` reasoning-class needs 900s+; raises `LLMProviderError("TIMEOUT", "OpenAI API request timed out")`.
- Google reachability is logged at startup only (`main.ts:387` provider-key-availability log line); transient invoke-time failures cascade into the per-call adapter without graceful fallback.
- `model-adapter.sh.legacy:565-570` jq filter handles `chat.completions` and `output[].content[].text` for non-reasoning responses-API shapes, but reasoning-class `/v1/responses` returns a divergent shape (containing reasoning items) that neither selector matches → returns empty.
- `.loa.config.yaml` has rollback comments at lines 182-201 (BB tri-model) and 252-264 (flatline_protocol code_review/security_audit) pinning to last-known-good non-reasoning models.

### Environment
- Repo: 0xHoneyJar/loa, branch `feat/cycle-100-sprint-3-regressions-differential`
- Affected since: cycle-099 sprint-2E model-registry consolidation rolled out the latest reasoning-class triad as defaults (~2026-05-06).
- Symptom-active commit: cd4abc1f (rollback commit).
- Test runners on hand: `npm test` (Node `--test`) for BB TS adapters; `bats` for shell adapter; both detected.

## Analysis

### Suspected Files

| File | Line(s) | Confidence | Reason |
|------|---------|------------|--------|
| `.claude/skills/bridgebuilder-review/resources/adapters/openai.ts` | 25 (`DEFAULT_TIMEOUT_MS = 120_000`), 66, 122, 187 | high | Source of the compiled `dist/adapters/openai.js:17` constant cited in #789a; this is the per-call timeout the AbortController fires on. |
| `.claude/skills/bridgebuilder-review/resources/adapters/index.ts` | 44-45 (`config.maxInputTokens > 100_000 ? 300_000 : ...`) | high | The 300_000ms cap that #789a calls out — the local-adapter factory clamps every adapter (incl. OpenAI) at 5min even for >100k tokens. |
| `.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts` | 134 (`timeoutMs: config.maxInputTokens > 100_000 ? 300_000 : 120_000`) | high | Parallel cap in the multi-model branch — same 300_000ms ceiling; needs the same per-provider / per-model lift for reasoning-class. |
| `.claude/skills/bridgebuilder-review/resources/main.ts` | ~458-465 (multi-model key-status log) | high | The "0 missing (mode: graceful)" log line referenced by #789b at `dist/main.js:387` — only logs key availability, no invoke-time probe. |
| `.claude/skills/bridgebuilder-review/resources/adapters/google.ts` | 11 (`DEFAULT_TIMEOUT_MS`), 34 | medium | Sibling adapter; if probe gate is implemented per-adapter the Google path is the test target. |
| `.claude/scripts/model-adapter.sh.legacy` | 562-570 (jq filter chain in the openai branch of `extract_content`) | high | Exact lines cited by #787; jq selectors `.choices[0].message.content` and `(.output[] | select(.type == "message") | .content[] | select(.type == "output_text") | .text)` miss the reasoning-class shape. |
| `.loa.config.yaml` | 182-201, 252-264 | high | Rollback configs with `# was gpt-5.5-pro` / `# was gemini-3.1-pro-preview` comments — must be restored to latest triad after fixes land. AC #4. |
| `.claude/scripts/model-health-probe.sh` | 1-1696 (existing probe utility) | medium | If we wire an invoke-time probe call into BB main, this script (1696 LOC) is the natural composition target. |

### Related Tests

| Test File | Coverage |
|-----------|----------|
| `.claude/skills/bridgebuilder-review/resources/__tests__/openai.test.ts` | Existing 49-test suite for OpenAI adapter (already pins `/v1/responses` URL, blocked-response, multi-shape). Add: timeout-respects-config + reasoning-class-shape parses non-empty. |
| `.claude/skills/bridgebuilder-review/resources/__tests__/google.test.ts` | Existing Google adapter tests. Add: invoke-time probe rejects when health-probe returns DEGRADED/UNAVAILABLE. |
| `.claude/skills/bridgebuilder-review/resources/__tests__/multi-model.test.ts` | Multi-model pipeline tests. Add: graceful degradation surfaces as warn-in-log + non-zero exit when configured strict; per-provider timeout overrides honored. |
| `tests/unit/model-adapter-aliases.bats` | Existing aliases parity. New sibling `tests/unit/model-adapter-responses-api-shapes.bats` to assert non-empty content for each fixture. |
| `tests/unit/model-health-probe.bats` | Existing probe coverage at `provider-responses` fixture path. Add: probe-on-invoke vs probe-at-config differentiation. |
| `tests/fixtures/responses-api-shapes/` | DOES NOT EXIST yet (per #787 acceptance). MUST be created with one canonical sample per model class (codex / pro / reasoning). |

### Test Target
A combined regression suite covering the three coupled failure modes:

1. **TS unit (BB adapters)**: OpenAI adapter accepts an optional `timeoutMs` derived from `endpoint_family + thinking_traces` capability flags (or a `bridgebuilder.multi_model.timeout_seconds` config knob); pin a test that drives a 30min timeout on a reasoning-class model and 5min on a non-reasoning model.
2. **TS unit (BB main)**: Multi-model pipeline performs an invoke-time probe per provider before the parallel review fans out; on probe-DEGRADED for Google preview, the model is excluded with a config-time WARN line, not a runtime ABORT.
3. **bats parity**: Captured `gpt-5.5-pro /v1/responses` reasoning-class fixture parses to non-empty content via the patched jq filter chain at `model-adapter.sh.legacy:565-570`. Negative-control: existing `chat.completions` and non-reasoning `output[].content[].text` shapes still parse non-empty (no regression).
4. **Config invariant**: A bats/lint test that asserts `.loa.config.yaml::bridgebuilder.multi_model.models` and `flatline_protocol.code_review.model` + `.security_audit.model` reference the latest cycle-099-blessed identifiers (no `# was` rollback comments). Acts as the AC #4 gate.

### Constraints

- **NEVER write outside `/implement`** — this triage produces the handoff contract; the actual fix lands via `/implement sprint-bug-143`.
- **Test-first**: failing tests for each of the three failure modes MUST land before the production fix, per Phase-3 G-5.
- **Fixture-capture is operator-mediated**: the reasoning-class `/v1/responses` payload fixture (#787 AC item 1) requires a real `gpt-5.5-pro` invocation with credential present — capture during implement via `LOA_DEBUG_MODEL_RESOLUTION=1` or curl-tee, redact PII (`Authorization`, `org-id`), and check in.
- **System-Zone touchpoint**: the BB skill (`.claude/skills/bridgebuilder-review/`) is in System Zone. The bug-fix is authorized at cycle-100 sprint-3 level (regressions-differential branch); System-Zone writes are in scope per the cycle's PRD framing.
- **Rollback safety**: AC #4 requires removing rollback config comments; verify the new defaults produce a green BB E2E run BEFORE removing the rollback comments (mirrors cycle-099 PR #754 BB E2E pin pattern).
- **No silent degradation, ever**: The whole point of the fix is detecting + surfacing degradation. Tests MUST assert log-output contains `WARN`/`ERROR` markers when degradation occurs, not just the absence of crashes.
- **Endpoint-validator wrap**: any new probe HTTP calls MUST go through `endpoint_validator__guarded_curl` per cycle-099 sprint-1E.c.3.a/b/c invariants; raw `curl` is blocked by `tools/check-no-raw-curl.sh`.

## Fix Strategy

The three failures share one root cause class: **runtime model-availability and shape-divergence are unobservable until they manifest mid-call, and the failure modes degrade silently rather than surface.** The fix bundles three defensive primitives that, together, restore the latest-triad configuration without sacrificing reliability.

### Phase A: BB OpenAI per-model timeout (resolves #789a)
1. Add a `timeoutMs` derivation helper that reads `endpoint_family` and `capabilities` from `model-resolver.generated.ts` (already imported) — when `endpoint_family === "responses" && capabilities.includes("thinking_traces")`, return 1800_000 (30min); else honor the existing tiered ladder (120/180/300).
2. Apply the helper in BOTH `adapters/index.ts:44-45` (single-model path) AND `core/multi-model-pipeline.ts:134` (parallel path).
3. Optionally surface a `bridgebuilder.multi_model.timeout_seconds` config override (zod-validated) for operator escape-hatch, but the auto-derived path is the default.
4. Pin TS unit test that mocks an OpenAI adapter with `gpt-5.5-pro` resolution and asserts the constructed adapter has `timeoutMs === 1_800_000`.

### Phase B: invoke-time probe gate for Google preview (resolves #789b)
1. Extend `validateApiKeys` in `core/multi-model-pipeline.ts` to also call a one-shot health probe (re-using `.claude/scripts/model-health-probe.sh` via subprocess, OR a TS-native `probeProvider(provider, modelId)` that issues a minimal HEAD/ping) per resolved model.
2. On probe-FAIL, emit a `[multi-model] WARN: provider X model Y failed invoke-time probe — excluding from this run` log line and drop the entry from `keyStatus.valid` for THIS invocation only (no config mutation).
3. Pin TS unit test that injects a probe-mock returning DEGRADED for the Google entry and asserts: (a) the adapter is excluded, (b) the WARN line is logged, (c) non-Google adapters still execute.
4. Maintain `api_key_mode: graceful` semantics — probe failure is a degrade, not a hard-stop, unless `api_key_mode: strict` is set (then it raises, mirroring missing-key behavior at line 114).

### Phase C: legacy bash adapter responses-API parsing (resolves #787)
1. Capture a real `gpt-5.5-pro /v1/responses` payload during implement; redact `Authorization`, `organization`, `org-id`, request IDs; check in to `tests/fixtures/responses-api-shapes/gpt-5.5-pro-reasoning.json`. Capture sibling fixtures: `gpt-5.3-codex.json` (non-reasoning responses-API), `gpt-4-chat.json` (chat-completions). All three are needed for negative-control coverage.
2. Inspect the captured shape — almost certainly the response contains `output[].type === "reasoning"` items in addition to `output[].type === "message"`, OR the message item has a different content type (e.g., `output_text` vs the existing selector). Extend the jq filter at `model-adapter.sh.legacy:565-570`:
   ```bash
   content=$(echo "$response" | jq -r '
       .choices[0].message.content //
       (.output[] | select(.type == "message") | .content[] | select(.type == "output_text") | .text) //
       # NEW: reasoning-class shape — capture .output[] | type == "message" content with broader content-type allowance
       (.output[] | select(.type == "message") | .content[] | select(.type | test("text$")) | .text) //
       # NEW: fall through to first text-bearing item across all outputs
       [.output[]?.content[]? | select(.type? | test("text$")) | .text] | join("\n") //
       empty
   ')
   ```
   Exact filter form depends on the captured fixture — the implement task picks the minimal filter that parses ALL three fixtures non-empty.
3. Pin a bats parity test at `tests/unit/model-adapter-responses-api-shapes.bats` that loads each fixture and asserts non-empty `extract_content` output. Use `_python_assert` heredoc-safety pattern from cycle-099 sprint-1E for cross-platform repro.

### Phase D: config restoration (resolves AC #4)
1. After Phases A+B+C land + green: restore `.loa.config.yaml::bridgebuilder.multi_model.models` reviewer #1 to `gpt-5.5-pro`, reviewer #2 to `gemini-3.1-pro-preview`. Restore `flatline_protocol.code_review.model` and `.security_audit.model` to `gpt-5.5-pro`.
2. Remove the `2026-05-08:` rollback comment blocks at lines 182-201 + 252-264 (preserve a single-line audit reference: `# Restored after #787+#789 fix — see cycle-100 sprint-bug-143`).
3. Add a config-invariant bats test that grep-fails if `# was gpt-5.5-pro` or `# was gemini-3.1-pro-preview` substrings re-appear in `.loa.config.yaml` (regression gate against future quiet-rollbacks).

### Phase E: end-to-end verification (resolves AC #1)
1. Re-run the cycle-100 sprint-3 BB on the latest triad against the same kind of large diff that triggered the rollback (a >=90k-token PR). Capture log output as a verification artifact at `grimoires/loa/a2a/bug-20260508-i789-e3f89e/e2e-evidence.log`.
2. Verdict gate: `multi-model` log line shows `3 provider(s) available, 0 missing` AND all three `[multi-model:*] Complete` log lines present AND `consensus.high_consensus >= 1`.

### Why these are coupled
All three failure modes share a single observed-effect surface ("BB / adversarial review degraded silently to single-model") and the same triggering event (cycle-099 sprint-2E rollout of the reasoning-class triad as defaults). Splitting them into three sprints would (a) duplicate the BB E2E verification cost three times, (b) leave a partial-fix window where one of three rolls back unaesthetically, and (c) miss the joint-config invariant — all three must be restored together for AC #4 to hold. One sprint, one PR, one E2E green pin.

### Out of scope (explicitly deferred)
- **Capability-class registry pattern** (#789 long-term: `top-reasoning-openai`, `top-google-stable`, etc.) — designed in cycle-099 #710 north-star, NOT in this micro-sprint. Today's fix is the immediate-pragmatic floor.
- **`hounfour.flatline_routing: true` flip** (cycle-099 sprint-4 plan) — would retire `model-adapter.sh.legacy` entirely and obviate Phase C. If sprint-4 lands first, Phase C becomes a no-op verification ("does the flip already fix it?"). Triage assumes sprint-4 has not landed; if it has by implement-time, document the no-op and skip Phase C tests.

### Fix Hints

Structured hints for multi-model handoff (each hint targets one file change):

| File | Action | Target | Constraint |
|------|--------|--------|------------|
| `.claude/skills/bridgebuilder-review/resources/adapters/openai.ts` | refactor | constructor `timeoutMs` default | derive from resolved-model `endpoint_family + thinking_traces` capability; preserve constructor injection signature for tests |
| `.claude/skills/bridgebuilder-review/resources/adapters/index.ts` | refactor | `timeoutMs` derivation at line 44-45 | replace fixed-ladder with helper call; same helper used by multi-model-pipeline |
| `.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts` | refactor | inline `timeoutMs` at line 134 + add invoke-time probe loop | preserve `api_key_mode: graceful` semantics; emit WARN log on probe-fail |
| `.claude/skills/bridgebuilder-review/resources/main.ts` | add | invoke-time probe wiring before key-status log | log line format must remain greppable (existing tests pin "providers available") |
| `.claude/scripts/model-adapter.sh.legacy` | fix | jq filter at lines 565-570 in openai branch | add reasoning-class shape selector; ALL existing fixtures must still parse non-empty |
| `tests/fixtures/responses-api-shapes/` | add | three fixtures: reasoning, codex, chat | redact `Authorization`, `org-id`, request IDs; pin in bats parity test |
| `tests/unit/model-adapter-responses-api-shapes.bats` | add | one test per fixture asserting non-empty content | use `_python_assert` heredoc-safety pattern from cycle-099 sprint-1E |
| `.claude/skills/bridgebuilder-review/resources/__tests__/openai.test.ts` | add | timeout-respects-resolved-capability test | mock model-resolver to return reasoning-class capability; assert constructed timeoutMs === 1_800_000 |
| `.claude/skills/bridgebuilder-review/resources/__tests__/multi-model.test.ts` | add | invoke-time probe gate test | inject probe-mock; assert WARN-on-fail + adapter exclusion + non-fail-providers still run |
| `.loa.config.yaml` | encode | restore latest triad in `bridgebuilder.multi_model.models` + `flatline_protocol.{code_review,security_audit}.model` | only after Phases A+B+C green; preserve single-line audit comment |
| `tests/unit/loa-config-no-rollback-comments.bats` | add | grep-gate against `# was gpt-5.5-pro` and `# was gemini-3.1-pro-preview` substrings | regression gate against future quiet-rollbacks |
| `grimoires/loa/a2a/bug-20260508-i789-e3f89e/e2e-evidence.log` | add | BB E2E run capturing `3 provider(s) available, 0 missing` + 3× `Complete` + consensus | verification artifact for AC #1 |
