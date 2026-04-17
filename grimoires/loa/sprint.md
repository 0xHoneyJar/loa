# Sprint Plan — Cycle-082: Opus 4.7 Top-Review Migration

**Cycle**: 082
**Branch**: `feat/opus-4-7-migration`
**Date**: 2026-04-17
**Author**: janitooor (via /simstim)
**PRD**: `grimoires/loa/prd.md`
**SDD**: `grimoires/loa/sdd.md`

---

## Sprint Goal

Migrate Loa's top-review / advisor / primary-adversary Opus role from 4.6 to 4.7 across all review-critical subsystems (Flatline, Bridgebuilder, red-team adapter, bash/Python/TS adapters, docs). Preserve 4.6 as a pinnable fallback and backward-compat alias. Single PR, full review + audit cycle, green CI.

## Sprint Strategy

- **One sprint, multiple tasks** — migration is cohesive and single-PR by design (per SDD §5 commit sequencing and PRD §16 SKP-005 override).
- **Beads task IDs** resolved at implementation time via `br create`.
- **Task ordering**: T-PRE (gate) → T-1 (additive registry) → T-2 (adapter maps additive) → T-3 (alias switch) → T-4 (flatline subsystem) → T-5 (bridgebuilder TS) → T-6 (Python adapters) → T-7 (doc sweep) → T-CROSS (cross-runtime contract) → T-GREP (acceptance gate script) → T-SMOKE (live-model-ID gate).
- **Circuit breaker**: if T-PRE compat check fails, halt and return to DISCOVERY. If T-3 alias switch breaks any downstream test, split into per-subsystem commits.

---

## Sprint 1: Opus 4.7 Top-Review Migration

## Task Breakdown

### T-PRE: Pre-Migration Compatibility Check

**Type**: blocking gate
**Acceptance**: PRD §14 matrix validated — all 8 dimensions pass.

**Implementation** (tightened per Flatline Sprint IMP-002 — explicit mapping to PRD §14's 8 dimensions):

1. Write `.claude/scripts/tests/opus-4-7-compat-check.sh`. Each sub-check maps to one PRD §14 dimension:

   | # | PRD §14 Dimension | Sub-check (what the script does) | Pass criterion |
   |---|-------------------|----------------------------------|----------------|
   | 1 | Endpoint | POST to `https://api.anthropic.com/v1/messages` | 2xx response (not 404/405) |
   | 2 | Token parameter | Request with `max_tokens: 100` | Response returned, no 400 on parameter |
   | 3 | Context window | Request with ~150K-token payload | Response returned (not 413/too-long error) |
   | 4 | Basic capabilities (chat) | Plain single-turn text completion | `content[].type == "text"`, non-empty text |
   | 5 | Tool use | Request declaring a mock `calculator` tool + user message asking 2+2 | Response includes `content[].type == "tool_use"` block |
   | 6 | Thinking traces | Request with `thinking: {type: "enabled", budget_tokens: 1024}` | Response includes both `thinking` and `text` blocks |
   | 7 | Error handling | Deliberately-malformed request (bad `max_tokens` type) | Response is `{"type":"error","error":{"type":"invalid_request_error",...}}` |
   | 8 | Response schema | Parse response through existing Python adapter | Adapter returns without schema validation errors; `response.model` equals `"claude-opus-4-7"` |

2. Each sub-check logs `PASS: dimension-N` or `FAIL: dimension-N (reason)` to stdout.
3. Script exit 0 iff all 8 sub-checks pass; non-zero with the list of failed dimensions otherwise.
4. Run script; capture output to `/tmp/opus-4-7-compat-evidence.txt`.
5. If ALL checks pass, proceed to T-1. If ANY fail, halt implementation and escalate.

**Verification**: `opus-4-7-compat-check.sh` exit 0; evidence file attached to PR body.

### T-1: Register claude-opus-4-7 in model-config.yaml (additive)

**Type**: additive — 4.6 remains canonical after this task
**Files**: `.claude/defaults/model-config.yaml`, `.claude/data/model-permissions.yaml`

**Implementation**:
1. Under `providers.anthropic.models` add `claude-opus-4-7` block per SDD §4.1 (pricing $5/$25 per Mtok in micro-USD).
2. In `.claude/data/model-permissions.yaml`, add `anthropic:claude-opus-4-7:` block mirroring the 4.6 block per SDD §4.7 (explicit field enumeration, no placeholder comments).
3. Do NOT change the `aliases.opus:` value yet.

**Verification**: `yq '.providers.anthropic.models."claude-opus-4-7".pricing' .claude/defaults/model-config.yaml` returns the correct values; `.claude/data/model-permissions.yaml` parses as valid YAML with the new block present. All existing tests remain green.

**Commit**: `feat(models): register claude-opus-4-7 in defaults (additive)`

### T-2: Add 4.7 entries to all four bash maps (additive)

**Type**: additive — aliases still resolve to 4.6 after this task
**Files**: `.claude/scripts/model-adapter.sh.legacy`

**Implementation**:
1. Add `["claude-opus-4-7"]="anthropic"` to `MODEL_PROVIDERS`.
2. Add `["claude-opus-4-7"]="claude-opus-4-7"` to `MODEL_IDS`.
3. Add `["claude-opus-4-7"]="0.005"` to `COST_INPUT`.
4. Add `["claude-opus-4-7"]="0.025"` to `COST_OUTPUT`.
5. Source the file in a subshell to confirm `validate_model_registry` still exits 0.

**Verification**: `bash -c 'source .claude/scripts/model-adapter.sh.legacy && echo OK'` prints `OK` and exits 0. Existing bats tests green.

**Commit**: `feat(adapter): add claude-opus-4-7 to all four bash maps (additive)`

### T-3: Retarget opus alias and legacy Opus aliases to 4.7

**Type**: switch point
**Files**: `.claude/defaults/model-config.yaml`, `.claude/scripts/model-adapter.sh.legacy`, `.claude/scripts/model-adapter.sh`, `.claude/scripts/red-team-model-adapter.sh`, `.loa.config.yaml.example`

**Implementation**:
1. `.claude/defaults/model-config.yaml`: change `aliases.opus:` value from `anthropic:claude-opus-4-6` to `anthropic:claude-opus-4-7`.
2. `.claude/scripts/model-adapter.sh.legacy`:
   - In `MODEL_IDS`: retarget `opus`, `claude-opus-4.6`, `claude-opus-4-6`, `claude-opus-4.5`, `claude-opus-4-5`, `claude-opus-4.1`, `claude-opus-4-1`, `claude-opus-4.0`, `claude-opus-4-0` all to `claude-opus-4-7`.
   - Add new keys `claude-opus-4.7`, `claude-opus-4-7` resolving to `claude-opus-4-7`.
   - Update file header comment (L15-16) to reflect 4.7 as current.
3. `.claude/scripts/model-adapter.sh` (`MODEL_TO_ALIAS`): same retarget pattern — all resolve to `anthropic:claude-opus-4-7`. Update usage block (L174) to name 4.7.
4. `.claude/scripts/red-team-model-adapter.sh` (alias map L49-50): same retarget.
5. `.loa.config.yaml.example`: update any commented-out example mentioning 4.6 as the primary model.

**Verification**:
- `bash -c 'source .claude/scripts/model-adapter.sh.legacy && echo "${MODEL_IDS[opus]}"'` prints `claude-opus-4-7`.
- `bash -c 'source .claude/scripts/model-adapter.sh.legacy && echo "${MODEL_IDS[claude-opus-4-6]}"'` prints `claude-opus-4-7` (backward-compat alias).
- Updated bats test `tests/unit/model-adapter-aliases.bats` passes.

**Commit**: `feat(adapter): retarget opus alias + legacy-version aliases to claude-opus-4-7`

### T-4: Flatline subsystem migration

**Files**: `.claude/scripts/flatline-orchestrator.sh`, `.claude/scripts/flatline-readiness.sh`, `.claude/protocols/flatline-protocol.md`, `.claude/loa/reference/flatline-reference.md`, `.claude/templates/flatline-dissent.md.template`, `.claude/evals/flatline-3model.sh`

**Implementation**:
1. `flatline-orchestrator.sh`:
   - `VALID_FLATLINE_MODELS` (L302): add `claude-opus-4.7`, `claude-opus-4-7`.
   - `MODEL_TO_ALIAS` (L375-376): retarget opus aliases to `anthropic:claude-opus-4-7`.
   - Default primary (L264) remains `opus` — alias resolves via adapter.
2. `flatline-readiness.sh` (L84, L133): case pattern already generic; update any hardcoded comment/default.
3. `flatline-protocol.md`, `flatline-reference.md`: update "Opus 4.6" mentions to "Opus 4.7" in current-state prose; keep historical rollout discussion.
4. `flatline-dissent.md.template`: if hardcoded 4.6, update.
5. `.claude/evals/flatline-3model.sh`: update default primary model invocation.

**Verification**: `.claude/scripts/flatline-readiness.sh --json` exits 0 with `primary: opus`. Bats suites `flatline-model-validation.bats` and `flatline-readiness.bats` green.

**Commit**: `feat(flatline): switch primary to claude-opus-4-7 across orchestrator + protocol + readiness`

### T-5: Bridgebuilder TypeScript resources

**Files**: `.claude/skills/bridgebuilder-review/resources/config.ts`, `core/truncation.ts`, `personas/security.md`, all 7 `__tests__/*.test.ts`

**Implementation**:
1. `config.ts`: update the opus-model constant to `'claude-opus-4-7'`.
2. `core/truncation.ts`: update any 4.6 reference.
3. `personas/security.md`: update any primary-model naming.
4. Each `__tests__/*.test.ts` (7 files): update expected model constants / fixture values.
5. **Build verification (Bridgebuilder HIGH-001)**: if `package.json` has a build script, run it and verify no `dist/` artifacts contain stale `claude-opus-4-6` strings. If no build step, document in commit message.

**Verification**: `cd .claude/skills/bridgebuilder-review/resources && npm test` passes all test files.

**Commit**: `feat(bridgebuilder): point TypeScript resources at claude-opus-4-7`

### T-6: Python adapter fixtures and tests

**Files**: 3 fixtures (`anthropic_response.json`, `anthropic_thinking_response.json`, `anthropic_tool_use_response.json`) + 8 test files (`test_config`, `test_providers`, `test_pricing`, `test_chains`, `test_multi_adapter`, `test_routing`, `test_flatline_routing`, `test_trust_scopes`)

**Implementation**:
1. Fixtures: update `model` field in all 3 JSON files from `claude-opus-4-6` to `claude-opus-4-7`.
2. Tests: update expected model assertions. Add pricing assertion in `test_pricing.py` confirming 4.7 at `0.005`/`0.025`.
3. `test_trust_scopes.py`: verify the new permission block loads and validates.

**Verification**: `pytest .claude/adapters/tests/` all green.

**Commit**: `feat(adapters): update Python fixtures and tests for claude-opus-4-7`

### T-7: Documentation + SKILL.md sweep

**Files**: `CHANGELOG.md`, `README.md`, `BUTTERFREEZONE.md`, `docs/CONFIG_REFERENCE.md`, `docs/integration/runtime-contract.md`, `evals/README.md`, `.claude/loa/reference/context-engineering.md`, `.claude/schemas/README.md`, `.claude/skills/*/SKILL.md` (6 files), `.claude/skills/autonomous-agent/resources/operator-detection.md`.

**Implementation**:
1. For each file, replace current-state "Opus 4.6" / "claude-opus-4.6" mentions with 4.7 where the model is named as the active top-review model. Preserve historical / dated references.
2. **CHANGELOG entry** (per PRD FR-9) under Unreleased:
   - Header: "Opus 4.7 promoted to top-review default"
   - Bullets: pricing parity confirmed, 4.6 backward-compat alias retained, legacy-version alias retarget flag (operators relying on `claude-opus-4.5` etc. must pin canonical model ID for historical baselines)
3. `BUTTERFREEZONE.md`: if it names the primary review model, update.

**Verification**: T-GREP passes.

**Commit**: `docs: sweep SKILL.md + README + CHANGELOG for Opus 4.7`

### T-TESTS: BATS test updates

**Files**: `tests/unit/model-adapter-aliases.bats`, `tests/unit/flatline-model-validation.bats`, `tests/unit/flatline-readiness.bats`

**Implementation**:
1. `model-adapter-aliases.bats`:
   - Update "opus alias resolves to 4.6" test → "opus alias resolves to 4.7".
   - Add: "claude-opus-4.6 alias backward-compat still resolves to a live model".
   - Add: "four-map invariant holds for claude-opus-4-7".
   - Add: "both dotted and hyphenated canonical forms resolve identically" (per SDD §4.2 naming policy).
   - **Add (per Flatline Sprint IMP-003 / IMP-010) — positive 4.6 fallback verification**: tests must prove the "kill switch" path described in PRD §13 actually works. The established alias pattern (PR #207) retargets all legacy IDs in the bash layer; the escape hatch lives in Python/YAML:
     - **YAML assertion** (registry retention): `yq '.providers.anthropic.models."claude-opus-4-6".pricing.input_per_mtok' .claude/defaults/model-config.yaml` returns `5000` post-migration. Ensures the pinnable 4.6 entry is not deleted.
     - **Python-adapter assertion** (end-to-end escape hatch): new test in `.claude/adapters/tests/test_fallback_resolution.py` — invoke adapter with `anthropic:claude-opus-4-6` provider-prefixed form and assert the resolved config block is the 4.6 entry (not 4.7). This is the operator's concrete rollback path from PRD §13.
     - **Bash alias assertion** (current behavior documented): existing test "claude-opus-4.6 alias backward-compat still resolves to a live model" stays — asserts that the bash retarget does NOT break (resolves to 4.7, which is live). This documents the established pattern rather than contradicting it.

   **Behavior boundary** (documented in CHANGELOG per PRD FR-9): to pin 4.6 exactly, operators must use the Python/YAML path (`anthropic:claude-opus-4-6`) in their `.loa.config.yaml`, not the bash alias layer. The bash layer is optimized for "give me current opus"; the YAML layer is the authoritative registry.
2. `flatline-model-validation.bats`: add `claude-opus-4.7` / `claude-opus-4-7` to valid-models assertions.
3. `flatline-readiness.bats`: if any test asserts a canonical-ID downstream, update to 4.7.

**Verification**: `bats tests/unit/model-adapter-aliases.bats tests/unit/flatline-model-validation.bats tests/unit/flatline-readiness.bats` green.

**Commit**: bundled with T-3 and T-4 as appropriate.

### T-CROSS: Cross-runtime alias contract test (Flatline SDD SKP-004)

**File**: `.claude/scripts/tests/cross-runtime-alias-contract.sh` (new)

**Implementation** (amended per Flatline Sprint IMP-008 + SKP-004):

**Step 0 — Shared normalization spec** (new file): `.claude/scripts/tests/alias-normalization-spec.md`. One document that defines:
- Canonical resolution order (alias map → canonical ID → provider:ID)
- Case sensitivity (keys are lowercase, exact match; no fuzzy resolution)
- Whitespace handling (trimmed)
- Provider-prefix semantics (`anthropic:X` is pre-resolved; skips alias map)
- Expected resolution boundary: bash/Python/TS may diverge ONLY on legacy canonical IDs (e.g., `claude-opus-4-6` — bash retargets, Python/YAML preserves). Those divergences are EXPECTED and documented, not bugs.

**Step 1 — Wrapper implementations, tested independently**:
- `bash-resolve.sh <alias>` (new): sources model-adapter.sh.legacy, resolves, prints provider:model or errors with exit 2.
- `python-resolve.py <alias>` (new): calls Python adapter, prints provider:model or errors. If adapter doesn't expose a CLI helper, add one (single-function wrapper).
- `ts-resolve.mjs <alias>` (new): imports bridgebuilder config, resolves, prints provider:model. Uses `node --experimental-vm-modules` if ts-node not available; otherwise relies on compiled dist.
- **Each wrapper has its own 3-test smoke suite** under `.claude/scripts/tests/wrapper-smoke/` that runs FIRST in CI. Cross-runtime contract test is skipped with a clear message if any wrapper smoke fails. This prevents false-failures caused by wrapper brittleness.

**Step 2 — Contract test** (`.claude/scripts/tests/cross-runtime-alias-contract.sh`): per SDD §11a:
1. For each alias in the test matrix (`opus`, `claude-opus-4-7`, `claude-opus-4.7`):
   - Call each wrapper and capture output
   - Assert all three return `anthropic:claude-opus-4-7`
2. For "expected-divergence" aliases (`claude-opus-4-6`, `claude-opus-4.6`):
   - Call each wrapper, record output
   - Assert against the documented-divergence spec (bash = `anthropic:claude-opus-4-7` via retarget; Python = `anthropic:claude-opus-4-6` via YAML; TS = whichever is documented as canonical for its adapter path)
3. Exit 0 iff all aliases resolve per spec; non-zero with divergence details otherwise.

**Prerequisite / skip policy (IMP-008)**:
- If any wrapper smoke test fails, the contract test is SKIPPED (not failed) and CI logs a `WARNING: wrapper-smoke failed, contract test skipped — fix wrappers before re-running`. This prevents noisy CI failures caused by environment drift in the wrappers.
- If the migration proceeds past wrapper-smoke-skip for more than 24 hours, `@janitooor` is notified via CHANGELOG TODO entry.

**Verification**: wrapper-smoke passes → contract test exits 0 after all other tasks complete.

**Commit**: `test(adapters): cross-runtime alias resolution contract`

### T-GREP: Acceptance-gate grep script (Flatline SDD IMP-003 strengthened)

**File**: `.claude/scripts/tests/opus-4-6-residuals.sh` (new)

**Implementation**: per PRD FR-8 strengthened spec:
1. Run `rg` against the enumerated paths and patterns.
2. Filter matches: accept alias-map entries, CHANGELOG entries, explicit historical-pinning comments.
3. Flag unacceptable matches: default-model assignments, runtime code paths, usage/help strings.
4. Exit 0 iff only acceptable matches remain.

**Verification**: script exits 0 at PR-open time.

**Commit**: `test(gates): post-migration 4.6-residual scanner`

### T-SMOKE: Live-model-ID smoke gate (PRD R-7, SDD §7)

**Evidence**: captured in PR body, not a script.

**Implementation**:
1. Run `.claude/scripts/flatline-orchestrator.sh --doc grimoires/loa/sdd.md --phase sdd --json > /tmp/post-migration-smoke.json`.
2. Verify: `grep -c 'claude-opus-4-7' /tmp/post-migration-smoke.json > 0`; `grep -c 'claude-opus-4-6' in opus-slot fields == 0`.
3. Attach evidence excerpt to PR body.

**Verification**: PR body includes the smoke-test model-ID excerpt.

---

## Acceptance Criteria (Sprint-Level)

1. T-PRE compat check exits 0 with all 8 dimensions passing; evidence in PR.
2. All commits green on CI; no test suite red.
3. T-CROSS cross-runtime contract test exits 0.
4. T-GREP acceptance-gate scanner exits 0.
5. T-SMOKE live-model-ID evidence attached to PR body.
6. PR opened as draft against `main`, with `@janitooor` as review request.
7. PR body references PRD §16 + SDD §13 disposition tables.
8. CHANGELOG entry present under Unreleased.
9. Vision entries vision-010, vision-011, vision-012 committed as part of the PR.

## Estimated Complexity

**Small/Medium**. 48 files touched but no cross-cutting logic changes. The challenging parts are:
- T-5 (TS test suite) — depends on exact constant naming in `config.ts`
- T-6 (Python tests) — 3 fixtures + 8 test files require careful simultaneous edit
- T-CROSS — requires a working Python + TypeScript resolution CLI; may need wrappers

**Risk areas**:
- Vendor API: mitigated by T-PRE
- TS build artifacts: mitigated by T-5 build verification
- Documentation drift: mitigated by T-GREP
- Cross-runtime divergence: mitigated by T-CROSS

## Dependencies

- Green baseline on `main` at branch point (confirmed)
- `ANTHROPIC_API_KEY` with 4.7 access (T-PRE will detect if missing)
- Beads healthy for task lifecycle tracking (`br list`)

## Flatline Sprint Review Dispositions (audit trail)

Sprint reviewed via Flatline Protocol 2026-04-17. 5 HIGH_CONSENSUS (auto-integrated), 1 DISPUTED (merged with IMP-003), 4 BLOCKERS (3 repeat-of-prior-decisions overridden, 1 accepted):

| ID | Severity | Disposition | Action |
|----|----------|-------------|--------|
| IMP-001 | HIGH_CONSENSUS | Auto-integrate | PRD §13 rollback authority added (@janitooor sole authority) |
| IMP-002 | HIGH_CONSENSUS | Auto-integrate | T-PRE scenarios tightened to explicit 8-dimension mapping |
| IMP-003 + IMP-010 | HIGH_CONSENSUS + DISPUTED | Auto-integrate (merged) | T-TESTS amended: YAML assertion + Python adapter end-to-end test; bash behavior documented |
| IMP-008 | HIGH_CONSENSUS | Auto-integrate | T-CROSS prerequisite/skip policy added; wrappers tested independently first |
| IMP-009 | HIGH_CONSENSUS | Auto-integrate (no-op) | Already strengthened in PRD FR-8 amendment |
| SPR-SKP-001 | CRITICAL | Override | Repeat of SDD SKP-005; solo-maintainer 8-commit rationale stands |
| SPR-SKP-002 | HIGH | Override | Repeat of SDD SKP-001; streaming + rate-limit explicitly OOS per PRD §14 |
| SPR-SKP-003 | CRITICAL | Override | Third raise of same reproducibility issue; PRD/SDD escape hatch stands |
| SPR-SKP-004 | HIGH | Accept | T-CROSS shared normalization spec + independent wrapper smoke tests added |

Full rationale preserved in `.run/simstim-state.json` `blocker_decisions[]`.

## Out-of-Scope

- Formal quality-benchmark harness (deferred to vision-010)
- Auto-generated bash adapter maps from YAML (deferred to vision-011)
- Role-based alias renaming (deferred to vision-012)
- Any non-Opus model migration
- Any changes to executor/cheap alias targets
