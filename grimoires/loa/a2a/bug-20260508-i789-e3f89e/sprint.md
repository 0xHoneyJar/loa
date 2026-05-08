# Sprint Plan: Bug Fix — Coupled model-stability rollback restoration (#787 + #789)

**Type**: bugfix
**Bug ID**: 20260508-i789-e3f89e
**Source**: /bug (triage)
**Sprint**: sprint-bug-143
**Source issues**: #787 (closes), #789 (closes; partial — capability-class registry deferred to cycle-099 #710)
**Rolled-back commit being reversed**: cd4abc1f
**Branch**: feat/cycle-100-sprint-3-regressions-differential (existing — no new branch)

---

## sprint-bug-143: Restore latest reasoning-class triad across BB / Flatline / adversarial-review

### Sprint Goal
Restore the cycle-099-blessed latest reasoning-class triad (`gpt-5.5-pro` + `gemini-3.1-pro-preview` + `claude-opus-4-7`) as the default for Bridgebuilder, `/flatline-review`, `/review-sprint` adversarial dissent, and `/audit-sprint` adversarial dissent — without recurrence of the silent-degradation failure modes that forced the 2026-05-08 rollback (commit cd4abc1f).

Three coupled defects must be closed in one PR (Phases A+B+C+D+E) so AC #4 ("config restored") and AC #5 ("regressions covered") hold jointly.

### Deliverables
- [ ] Failing tests reproducing each of the three failure modes (#789a OpenAI timeout, #789b Google preview probe, #787 legacy adapter parsing)
- [ ] Phase A: BB OpenAI per-call timeout auto-derived from `endpoint_family + thinking_traces` capability flags
- [ ] Phase B: invoke-time probe gate in `core/multi-model-pipeline.ts` that excludes degraded providers with WARN log
- [ ] Phase C: extended jq filter chain at `model-adapter.sh.legacy:565-570` parses reasoning-class `/v1/responses` shapes non-empty
- [ ] Phase C fixtures: `tests/fixtures/responses-api-shapes/{reasoning,codex,chat}.json` with PII-redacted captures
- [ ] Phase D: `.loa.config.yaml` restored to latest triad; rollback comments removed; single audit-line preserved
- [ ] Phase E: BB E2E verification log at `grimoires/loa/a2a/bug-20260508-i789-e3f89e/e2e-evidence.log`
- [ ] All existing tests pass (no regressions in 49-test BB OpenAI suite, model-health-probe.bats, model-adapter-aliases.bats)
- [ ] Triage analysis document (delivered as part of /bug)

### Technical Tasks

#### Task 1: Capture reasoning-class /v1/responses fixture [G-5]
- Run a real `gpt-5.5-pro` invocation via `model-invoke --model gpt-5.5-pro` with a small prompt; capture full JSON response via `LOA_DEBUG_MODEL_RESOLUTION=1` or a curl tee
- Redact `Authorization`, `organization`, `org-id`, request IDs, and any user-text from the captured payload
- Capture sibling fixtures: `gpt-5.3-codex` (non-reasoning responses-API), a chat-completions sample (e.g., `gpt-5.5` non-pro)
- Store at `tests/fixtures/responses-api-shapes/{reasoning,codex,chat}.json`

**Acceptance Criteria**:
- Three fixtures present, valid JSON, no PII regex matches (`Authorization`, `Bearer`, `sk-`, `org-`)
- Fixture filenames documented in `tests/fixtures/responses-api-shapes/README.md`
- Each fixture is one captured response, not a synthesized hypothetical

#### Task 2: Write failing test — bash adapter parses reasoning shape [G-5]
- Create `tests/unit/model-adapter-responses-api-shapes.bats`
- Three test cases, one per fixture, each asserting non-empty `extract_content` output
- Use `_python_assert` heredoc-safety helper pattern from cycle-099 sprint-1E
- Verify all three FAIL with current `model-adapter.sh.legacy:565-570` filter (reasoning case fails empty; codex + chat already pass)

**Acceptance Criteria**:
- Test file at `tests/unit/model-adapter-responses-api-shapes.bats` with 3+ tests
- Reasoning-class test fails with current code (proves the bug)
- Codex + chat tests pass with current code (proves no regression in baseline)
- Test names self-describe: `test_extract_content_reasoning_class_returns_non_empty`, etc.

#### Task 3: Write failing test — BB OpenAI timeout for reasoning-class [G-5]
- Add to `.claude/skills/bridgebuilder-review/resources/__tests__/openai.test.ts`
- Mock model-resolver to return `endpoint_family: responses`, `capabilities: [..., thinking_traces]` for `gpt-5.5-pro`
- Assert: `OpenAIAdapter` constructed via factory has `timeoutMs >= 1_800_000` (30min)
- Negative-control: non-reasoning model resolves to `timeoutMs <= 300_000`

**Acceptance Criteria**:
- Two new tests in openai.test.ts (positive + negative-control)
- Both fail with current code (timeoutMs is currently capped at 300_000 regardless of capability)
- Test framing matches existing 49-test patterns in the same file

#### Task 4: Write failing test — invoke-time probe gate [G-5]
- Add to `.claude/skills/bridgebuilder-review/resources/__tests__/multi-model.test.ts`
- Inject a probe-mock that returns `DEGRADED` for the Google adapter, healthy for others
- Assert: pipeline emits `[multi-model] WARN: ... google ... excluding from this run` log line
- Assert: Google adapter is dropped from `modelAdapters`
- Assert: Anthropic + OpenAI adapters still run normally
- `api_key_mode: strict` variant: probe-fail raises (mirrors line 114 missing-key behavior)

**Acceptance Criteria**:
- Three test cases in multi-model.test.ts (graceful exclude, strict raise, no-probe-fail-no-warn)
- All three fail with current code (no probe gate exists)
- Tests use the existing `validateApiKeys` mocking pattern from the file

#### Task 5: Implement Phase A — BB OpenAI timeout derivation [G-1, G-2]
- Add `deriveTimeoutMs(modelMeta)` helper to `resources/adapters/index.ts` (or co-locate in `core/multi-model-pipeline.ts`)
- Helper reads from `lib/model-resolver.generated.ts` via existing import
- When `endpoint_family === "responses" && capabilities.includes("thinking_traces")`: return `1_800_000`; else honor existing 120/180/300 ladder
- Apply at `adapters/index.ts:44-45` AND `core/multi-model-pipeline.ts:134`
- Optional: surface `bridgebuilder.multi_model.timeout_seconds` config knob (zod) as operator escape-hatch
- Verify Task 3 tests now pass

**Acceptance Criteria**:
- Both call-sites use the same helper (no copy-paste)
- Task 3 tests pass; full BB test suite passes (`npm test` in skill dir)
- No regression in single-model timeout tiers (assert via existing tier tests)

#### Task 6: Implement Phase B — invoke-time probe gate [G-1, G-2]
- Add `probeProvider(provider, modelId, apiKey)` in `core/multi-model-pipeline.ts` — composes existing `model-health-probe.sh` via subprocess OR issues a minimal HEAD/ping (decision deferred to implement; subprocess composition is simpler and lower-risk)
- Call probe in the `for entry of keyStatus.valid` loop (lines 118-141); on probe-fail, log WARN and `continue` to skip this adapter
- For `api_key_mode: strict` mode: probe-fail raises `Error("Strict mode: provider X failed invoke-time probe")` mirroring line 114
- Use `endpoint_validator__guarded_curl` for any new HTTP calls (raw `curl` blocked by `tools/check-no-raw-curl.sh`)
- Verify Task 4 tests now pass

**Acceptance Criteria**:
- Task 4 tests pass; full multi-model test suite passes
- Probe never blocks on absent provider keys (validateApiKeys runs first)
- WARN log line is greppable: `[multi-model] WARN: ... probe ... excluding`

#### Task 7: Implement Phase C — legacy adapter jq filter extension [G-1, G-2]
- Inspect captured fixture from Task 1 to identify the divergent shape
- Extend jq filter at `model-adapter.sh.legacy:565-570` with the minimal additional selector needed; do NOT regress existing selectors
- If reasoning-class shape contains a `text`-suffixed content type that the existing selector misses, broaden via `select(.type | test("text$"))`; if it requires a wholly different path, add a fall-through selector
- Verify Task 2 tests now pass; verify `tests/unit/model-adapter-aliases.bats` still passes (no regression)

**Acceptance Criteria**:
- Task 2 tests pass for ALL three fixtures
- All pre-existing model-adapter tests pass
- jq filter is documented inline with a one-line comment explaining the reasoning-class shape

#### Task 8: Implement Phase D — config restoration [G-1, G-2]
- Edit `.loa.config.yaml::bridgebuilder.multi_model.models`:
  - reviewer #1: `gpt-5.3-codex` → `gpt-5.5-pro`
  - reviewer #2: `gemini-2.5-pro` → `gemini-3.1-pro-preview`
- Edit `.loa.config.yaml::flatline_protocol.code_review.model` and `.security_audit.model`: `claude-opus-4-7` → `gpt-5.5-pro`
- Remove the multi-line rollback comment blocks at ~lines 182-201 + 252-264
- Replace with one-line audit reference: `# Restored after #787+#789 fix — see grimoires/loa/a2a/bug-20260508-i789-e3f89e`
- Add `tests/unit/loa-config-no-rollback-comments.bats` with grep-gates against `# was gpt-5.5-pro`, `# was gemini-3.1-pro-preview`, `# rolled back` substrings — failing if found

**Acceptance Criteria**:
- `.loa.config.yaml` references the latest triad
- New regression-gate bats test passes
- Diff is minimal (only the model_id swaps + comment compression)

#### Task 9: Phase E — BB E2E verification [G-3]
- Run `/run-bridge` (or `bridgebuilder` CLI directly) against any PR with a >=90k-token diff. The cycle-100 sprint-3 PR currently in-flight is a natural target.
- Capture full log to `grimoires/loa/a2a/bug-20260508-i789-e3f89e/e2e-evidence.log`
- Verdict assertions on captured log:
  - Contains: `Multi-model: 3 provider(s) available, 0 missing`
  - Contains: 3× `[multi-model:*] Complete` log lines (one per provider)
  - Contains: consensus block with `high_consensus >= 1` OR explicit `disputed` count (any non-zero consensus signal proves all three providers contributed findings)
  - Does NOT contain: `Review failed`, `timed out`, `network error`

**Acceptance Criteria**:
- E2E evidence log committed to bug directory
- All four verdict assertions hold on the captured log
- If a transient API failure occurs unrelated to the three failure modes (e.g., rate limit), retry once and capture the second run

#### Task 10: Update NOTES.md with closure cross-ref [G-3]
- Append to `grimoires/loa/NOTES.md` under a new dated entry: `## 2026-05-XX flatline_protocol code_review/security_audit model rollback closure (#787+#789)`
- Reference the merged PR + this triage doc + the E2E evidence log
- Mark the prior 2026-05-08 rollback entry with a closure cross-ref

**Acceptance Criteria**:
- NOTES.md entry written; previous rollback entry annotated
- Cross-references resolve (PR URL valid, triage path valid, evidence log path valid)

### Acceptance Criteria (sprint-level)
- [ ] AC #1: `gpt-5.5-pro` BB review of >=95k-token diff completes within timeout (proof: e2e-evidence.log)
- [ ] AC #2: Google preview probe rejects/falls back automatically when `gemini-3.1-pro-preview` is unreachable (proof: Task 4 tests + WARN log)
- [ ] AC #3: `gpt-5.5-pro` adversarial dissent through legacy bash adapter returns parsed content, not "Empty response content" (proof: Task 2 tests + e2e-evidence)
- [ ] AC #4: `.loa.config.yaml` `flatline_protocol.code_review.model` + `.security_audit.model` + BB `multi_model.models` restored to latest cycle-099-blessed triad (proof: Task 8 + grep-gate)
- [ ] AC #5: Existing tests pass; new regression tests cover the three failure modes (proof: full bats + npm test green)

### Triage Reference
See: grimoires/loa/a2a/bug-20260508-i789-e3f89e/triage.md
