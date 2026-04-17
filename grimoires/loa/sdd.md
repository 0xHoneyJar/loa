# Software Design Document — Opus 4.7 Top-Review Migration

**Cycle**: 082
**Status**: DRAFT
**Date**: 2026-04-17
**Branch**: `feat/opus-4-7-migration`
**Supersedes**: none (new cycle)
**PRD**: `grimoires/loa/prd.md`

---

## 1. Executive Summary

Migrate the Loa framework's canonical Opus top-review model from `claude-opus-4-6` to `claude-opus-4-7`. The migration is **additive-then-switch**: register 4.7 alongside 4.6, update aliases and orchestrator constants to target 4.7, and retain 4.6 as a pinnable registry entry + backward-compat alias. Zero schema changes, zero pricing change, zero ledger-format impact. Single PR, atomic revert.

## 2. Constraints

- **Four-map invariant** (`.claude/scripts/model-adapter.sh.legacy`): `MODEL_PROVIDERS`, `MODEL_IDS`, `COST_INPUT`, `COST_OUTPUT`. `validate_model_registry()` (L160) iterates `MODEL_IDS` keys and asserts each is present in the other three maps; sourcing the adapter runs the validator via `validate_model_registry || exit 2` (L183). Any key added to one map must appear in all four.
- **System Zone discipline**: only paths enumerated in PRD §12 are in scope.
- **Shell strict-mode compatibility** (`.claude/rules/shell-conventions.md`): use `var=$((var + 1))` if any counters are touched; heredoc delimiters quoted for YAML/JSON content.
- **Pricing parity** (PRD §11): 4.7 input/output = $5/$25 per Mtok, identical to 4.6.
- **No TypeScript/Python runtime changes**: TS resources read from config; Python adapter reads from `model-config.yaml`. Only constants and fixtures shift.

## 3. High-Level Design

```
┌─────────────────────────────────────────────────────────────┐
│ .claude/defaults/model-config.yaml (source of truth)        │
│ ├─ providers.anthropic.models                               │
│ │   ├─ claude-opus-4-7:   ← NEW canonical                   │
│ │   └─ claude-opus-4-6:   ← retained as pinnable            │
│ └─ aliases.opus: "anthropic:claude-opus-4-7"  ← RETARGETED  │
└────────────────┬────────────────────────────────────────────┘
                 │ sourced/read by:
   ┌─────────────┼──────────────────────────┐
   ▼             ▼                          ▼
┌──────────┐  ┌───────────────┐    ┌───────────────────────┐
│ bash     │  │ Python        │    │ TypeScript            │
│ adapters │  │ adapters/     │    │ bridgebuilder/        │
│ (.sh,    │  │ /adapters     │    │ resources/config.ts   │
│ .legacy) │  │ loads yaml    │    │ reads config + fixtures│
└──────────┘  └───────────────┘    └───────────────────────┘
   │               │                       │
   └───────────────┴───────────────────────┘
                   │
                   ▼
       ┌───────────────────────────────┐
       │ Downstream consumers:         │
       │ • flatline-orchestrator.sh    │
       │ • red-team-model-adapter.sh   │
       │ • flatline-readiness.sh       │
       │ • /run-bridge, /simstim, etc. │
       └───────────────────────────────┘
```

Changes propagate from the YAML source of truth outward. Bash adapters duplicate the registry (the four-map pattern) for performance; they must be hand-synced.

## 4. Component-Level Changes

### 4.1 `.claude/defaults/model-config.yaml`

**Add** under `providers.anthropic.models`:

```yaml
claude-opus-4-7:
  capabilities: [chat, tools, function_calling, thinking_traces]
  context_window: 200000
  token_param: max_tokens
  pricing:
    input_per_mtok: 5000
    output_per_mtok: 25000
```

**Retain** the `claude-opus-4-6` block unchanged (pinnable fallback per PRD §13).

**Update** `aliases.opus`:

```yaml
aliases:
  opus: "anthropic:claude-opus-4-7"   # was: claude-opus-4-6
```

### 4.2 `.claude/scripts/model-adapter.sh.legacy`

**File header comment** (L15-16): update description to "Claude Opus 4.7 (current)" and retain 4.6 listing.

**`MODEL_PROVIDERS`** (L72+): add `["claude-opus-4-7"]="anthropic"`. Retain `claude-opus-4.6` and `claude-opus-4-6` keys pointing at `anthropic`.

**`MODEL_IDS`** (L92+): add `["claude-opus-4-7"]="claude-opus-4-7"`. Retarget all opus aliases to resolve to 4.7:

```bash
["opus"]="claude-opus-4-7"
["claude-opus-4.7"]="claude-opus-4-7"
["claude-opus-4-7"]="claude-opus-4-7"
["claude-opus-4.6"]="claude-opus-4-7"               # Backward-compat retarget
["claude-opus-4-6"]="claude-opus-4-7"               # Backward-compat retarget
["claude-opus-4.5"]="claude-opus-4-7"               # Legacy retarget
# ... 4.1 / 4.0 in both forms, retargeted to 4-7
```

**Pinned-history escape hatch**: operators who need to call the exact `claude-opus-4-6` endpoint bypass the alias layer by passing the full provider-prefixed form (`anthropic:claude-opus-4-6`) to `model-invoke` (the Python runtime reads config directly, not the bash alias map). Documented in the model-adapter usage block.

**Canonical naming policy (Flatline SDD IMP-004, accepted)**: both dotted (`claude-opus-4.7`) and hyphenated (`claude-opus-4-7`) forms are accepted as alias keys for compatibility with prior-style configs. The **canonical form** is hyphenated (`claude-opus-4-7`) — this matches the actual Anthropic API model-ID convention, is what appears in the response `model` field, and is what `MODEL_IDS` resolves to. All new code, documentation, and config should prefer the hyphenated form; the dotted form is kept for backward-compat only. Tests assert that both forms resolve to the same canonical ID.

**`COST_INPUT`** (L114+): add `["claude-opus-4-7"]="0.005"`. Retain 4.6 entry.

**`COST_OUTPUT`** (L134+): add `["claude-opus-4-7"]="0.025"`. Retain 4.6 entry.

**Validator check**: sourcing the file after edits must exit 0. Automated via new bats assertion in `tests/unit/model-adapter-aliases.bats`.

### 4.3 `.claude/scripts/model-adapter.sh` (shim)

**`MODEL_TO_ALIAS`** (L99-117): same retarget as 4.2 — swap the resolution target from `anthropic:claude-opus-4-6` to `anthropic:claude-opus-4-7` for `opus` and all legacy aliases. Add new keys `claude-opus-4.7` and `claude-opus-4-7` pointing at `anthropic:claude-opus-4-7`.

**Usage block** (L174): update description to name 4.7 as current.

### 4.4 `.claude/scripts/flatline-orchestrator.sh`

**Default primary model** (L264): unchanged label `'opus'` (alias resolves to 4.7 via adapter). No code change.

**`VALID_FLATLINE_MODELS`** (L302): add `claude-opus-4.7` and `claude-opus-4-7` to the list. Retain `claude-opus-4.6` (pinned invocations should validate).

**`MODEL_TO_ALIAS`** (L375-376): swap from `anthropic:claude-opus-4-6` to `anthropic:claude-opus-4-7`. Add `claude-opus-4.7` / `claude-opus-4-7` keys.

Other opus references (L900-1069) are file-path labels (`opus-review.json`, `opus-skeptic.json`) — no code change, labels remain generic.

### 4.5 `.claude/scripts/flatline-readiness.sh`

**Case pattern** (L84): `opus|claude-*|anthropic-*)` already matches 4.7 — no change needed.

**Default primary** (L133): unchanged (`opus` alias resolves to 4.7).

**JSON output**: `models.primary` remains `"opus"` (alias label, per PRD §9 success metric). If a test fixture asserts the canonical model ID in a downstream field, update that test (see 4.10).

### 4.6 `.claude/scripts/red-team-model-adapter.sh`

**Alias map** (L49-50): retarget `opus` and `claude-opus-4.6` to `anthropic:claude-opus-4-7`. Add `claude-opus-4.7`, `claude-opus-4-7` keys.

Usage block (L75): update "Model: opus|gpt|kimi|qwen" if description naming changes.

### 4.7 `.claude/data/model-permissions.yaml`

**Add** `anthropic:claude-opus-4-7:` permission block mirroring the 4.6 block at L145-147. Retain 4.6 block (pinnable).

**Consumer** (Bridgebuilder LOW-001, accepted): this file is consumed by the trust-scope system — see `.claude/adapters/tests/test_trust_scopes.py` for the assertions that load and validate the permission blocks. Pre-implementation task T-PRE must verify the consumer still parses the file correctly with the new block present.

**Explicit field enumeration (Flatline SDD IMP-007, accepted)**: do NOT rely on "same as 4.6" placeholder comments. The new block must duplicate every field present in the 4.6 block verbatim, including:

- `trust_scope:` (e.g., `review`, `generation`, `native_runtime` — whichever 4.6 declares)
- `tool_permissions:` (bash, file read/write, etc. — full list)
- `network:` (allowed provider hostnames)
- `budget_class:` (cost-tier tag)
- any optional fields (`notes:`, `deprecated:`, etc.)

Placeholder comments invite test failures when the trust-scope loader fails to find a required key. The sprint task T-PERMS must grep the 4.6 block, enumerate every key, and confirm the 4.7 block has a value for each.

Example structure:

```yaml
anthropic:claude-opus-4-7:
  # Full permission block — NOT a placeholder. Mirror every field from 4.6 verbatim.
  trust_scope: [review, generation]          # from 4.6
  tool_permissions: [...]                    # from 4.6
  network: [api.anthropic.com]               # from 4.6
  budget_class: premium                      # from 4.6
  # ... every other field present in the 4.6 block
```

### 4.8 `.claude/scripts/flatline-orchestrator.sh` — model adapter shim section

Already covered in 4.4.

### 4.9 Bridgebuilder TypeScript Resources

**`resources/config.ts`**: locate model-ID constant (likely `OPUS_MODEL` or similar). Change literal value to `'claude-opus-4-7'`. If the config reads from YAML at runtime, verify via test that the resolution picks up 4.7 from the retargeted alias.

**`resources/core/truncation.ts`**: if 4.6 appears in a capability/context-window heuristic, update reference (context window identical — no behavior change).

**`resources/personas/security.md`**: if persona text names 4.6 as "the primary review model", update to 4.7. Do not rewrite historical persona descriptions of model behavior.

**Build verification (Bridgebuilder HIGH-001, accepted)**: If the bridgebuilder resources are compiled/bundled into a `dist/` directory, `npm run build` (or equivalent) must run after source updates, and the grep-sweep gate (SKP-004) must include any build artifacts. If resources are read as .ts at runtime (no build step), document that explicitly in sprint task T-5 so the verification step can be a no-op rather than an assumed-false.

**`resources/__tests__/*.test.ts`** (6 test files touching 4.6):
- `config.test.ts`: update expected model constant to `claude-opus-4-7`
- `adapter-factory.test.ts`: update model-to-adapter mapping fixture
- `multi-model-config.test.ts`: update opus slot expectations
- `rating.test.ts`: update any hardcoded model-ID in rating tests
- `persona.test.ts`: update persona-to-model binding
- `cross-repo-render.test.ts`: update any rendered-model expectations
- `progressive-truncation.test.ts`: update model-ID if referenced

### 4.10 Python Adapters

**`.claude/adapters/tests/fixtures/anthropic_*.json`** (3 files):
- `anthropic_response.json`: change `model` field from `claude-opus-4-6` to `claude-opus-4-7`
- `anthropic_thinking_response.json`: same
- `anthropic_tool_use_response.json`: same

**`.claude/adapters/tests/test_*.py`** (6 test files with 4.6 refs):
- `test_config.py`: update expected default-opus ID
- `test_providers.py`: update model-to-provider map expectations
- `test_pricing.py`: add pricing assertion for 4.7 (same values as 4.6 — acceptable parity)
- `test_chains.py`: update any hardcoded opus ID
- `test_multi_adapter.py`: update opus slot
- `test_routing.py`: update routing test expectations
- `test_flatline_routing.py`: update primary-opus expectations
- `test_trust_scopes.py`: update any permission-scope test referencing 4.6

### 4.11 Documentation

**`.claude/protocols/flatline-protocol.md`**: update model-list section to name Opus 4.7 as primary. Retain any historical discussion of 4.5/4.6 rollouts — this is a living protocol doc, not an append-only log.

**`.claude/loa/reference/flatline-reference.md`**: same treatment.

**`.claude/loa/reference/context-engineering.md`**: if it discusses model capabilities tied to 4.6, update to 4.7. Context window identical (200K), thinking-traces parity assumed per Anthropic announcement.

**`.claude/templates/flatline-dissent.md.template`**: if the template interpolates a specific model ID, update; if generic alias `opus`, no change.

**`.claude/evals/flatline-3model.sh`**: update any hardcoded primary model.

**`.claude/schemas/README.md`**: update any model-ID example.

**`docs/CONFIG_REFERENCE.md`**: update the model-config section.

**`docs/integration/runtime-contract.md`**: update opus model reference.

**`.loa.config.yaml.example`**: update the example (commented-out overrides may reference 4.6).

**`evals/README.md`**: update model-usage doc.

**`README.md`**: update any top-level mention of the primary review model.

**`BUTTERFREEZONE.md`**: update if it names the primary review model.

**`CHANGELOG.md`**: new entry under Unreleased — see FR-9 in PRD.

**`.claude/skills/*/SKILL.md`** (6 files with 4.6 refs):
- `red-teaming/SKILL.md`: update attacker/defender opus reference
- `run-bridge/SKILL.md`: update enriched-review reference
- `run-mode/SKILL.md`: update advisor reference in cost section
- `simstim-workflow/SKILL.md`: update "External providers called: Claude Opus 4.6" → 4.7
- `spiraling/SKILL.md`: update cost matrix model name
- `bridgebuilder-review/SKILL.md`: update primary-review reference

**`.claude/skills/autonomous-agent/resources/operator-detection.md`**: update if 4.6 is named as the advisor.

### 4.12 BATS Test Updates

**`tests/unit/model-adapter-aliases.bats`**:
- Rename/augment existing "opus alias resolves to 4.6" tests → "opus alias resolves to 4.7"
- Add: "claude-opus-4.6 alias still resolves to a valid model (4.7)"
- Add: "four-map invariant holds for claude-opus-4-7" (sources adapter, greps all four arrays)

**`tests/unit/flatline-model-validation.bats`**:
- Update primary-model validation expectations to include `claude-opus-4-7`
- Retain `claude-opus-4.6` validity (still in `VALID_FLATLINE_MODELS`)

**`tests/unit/flatline-readiness.bats`**:
- Update model-label assertions (`primary` still reports `opus`, but any canonical-ID assertion shifts to 4.7)

## 5. Implementation Sequencing (per PRD §15)

Commit-level sequencing within the single migration PR:

| # | Commit | Files | Rationale |
|---|--------|-------|-----------|
| 1 | `feat(models): register claude-opus-4-7 in defaults (additive)` | `.claude/defaults/model-config.yaml`, `.claude/data/model-permissions.yaml` | Additive; 4.6 remains canonical. No tests broken. |
| 2 | `feat(adapter): add 4.7 entries to all four bash maps` | `.claude/scripts/model-adapter.sh.legacy` | Additive; `validate_model_registry` passes. |
| 3 | `feat(adapter): retarget opus aliases to 4.7` | `.claude/scripts/model-adapter.sh.legacy`, `model-adapter.sh`, `red-team-model-adapter.sh`, `.loa.config.yaml.example`, `model-config.yaml` (aliases.opus) | Switch point. BATS tests updated in same commit. |
| 4 | `feat(flatline): add 4.7 to VALID_FLATLINE_MODELS + update protocol docs` | `flatline-orchestrator.sh`, `flatline-readiness.sh`, `flatline-protocol.md`, `flatline-reference.md`, `flatline-dissent.md.template`, `evals/flatline-3model.sh` | Subsystem-level switch. Flatline bats updated here. |
| 5 | `feat(bridgebuilder): point TS resources at 4.7` | `resources/config.ts`, `core/truncation.ts`, `personas/security.md`, all 7 `__tests__/*.test.ts` | TS subsystem switch; `npm test` green after this commit. |
| 6 | `feat(adapters): update Python fixtures and tests for 4.7` | 3 JSON fixtures, 8 `test_*.py` files | Python subsystem switch; pytest green after this commit. |
| 7 | `docs(*): sweep SKILL.md + README + CHANGELOG for 4.7` | All doc files in FR-7 | Cosmetic; no runtime impact. |
| 8 | `test(e2e): post-migration live-model-ID smoke gate evidence` | `grimoires/loa/a2a/flatline/sdd-review.json` (dogfood output) | Produces acceptance-gate evidence for PR body. |

Each commit leaves repo in a working state; bisection-friendly.

## 6. Test Strategy

**Existing tests** (must continue to pass):
- All bats suites in `tests/unit/`
- All Python tests in `.claude/adapters/tests/`
- All TS tests in `.claude/skills/bridgebuilder-review/resources/__tests__/`

**New/updated tests**:
- Bats: four-map invariant for 4.7, 4.6 alias backward-compat
- Bats: flatline-readiness reports `models.primary="opus"` and canonical-ID in downstream resolution is 4.7
- TS: `config.test.ts` locks `claude-opus-4-7` as the default opus constant
- Python: `test_pricing.py` asserts 4.7 at $5/$25 (parity with 4.6)

**Acceptance-gate tests** (PRD §9, §10):
- **Grep-sweep gate (SKP-004)**: CI step or pre-merge script that greps for `claude-opus-4-6|opus-4\.6|opus 4\.6` under non-historical paths and fails if matches are not in alias/CHANGELOG/comment context. Implementable as a new `.github/workflows/` step or a pre-merge check in `post-pr-orchestrator.sh`.
- **Live-model-ID gate (SKP-005)**: post-migration Flatline smoke test — run `.claude/scripts/flatline-orchestrator.sh --doc grimoires/loa/sdd.md --phase sdd --json` and verify `claude-opus-4-7` appears in the emitted output's opus-slot fields.

## 7. Observability & Rollback

**Observability**: no new telemetry. Cost-ledger entries (`grimoires/loa/a2a/cost-ledger.jsonl`) will naturally carry `model=claude-opus-4-7` after migration; operators can query to verify.

**Rollback** (from PRD §13):
- Full rollback: `git revert <merge-sha>` — atomic.
- Operator override: pin `anthropic:claude-opus-4-6` via `.loa.config.yaml` (registry entry retained).
- Degraded mode: existing Flatline `anthropic: [openai]` fallback is unchanged.

## 8. Risks & Open Questions

| ID | Risk | Mitigation | Owner |
|----|------|------------|-------|
| R-1 | TS config resolution happens at build time; if bridgebuilder is published as a pack with stale constants, bridge reviews may use 4.6 | `npm run build` of bridgebuilder resources in CI; commit-7 sweep catches stale refs | janitooor |
| R-2 | A SKILL.md doc drift is easy to miss across 6 files | Post-migration grep gate (SKP-004 acceptance) catches stragglers | janitooor |
| R-3 | Python adapter fixtures depend on exact-match model field for mock responses — if any test uses `assertIn` loosely, a stray 4.6 ref could slip through | Enumerate all 3 fixtures explicitly in sprint task; pytest -v smoke run shows canonical model in every routing test | janitooor |
| R-4 | `validate_model_registry()` catches missing keys in the 4 maps — but does NOT assert alias-target consistency (e.g., `opus` alias points to a key that actually exists in `MODEL_IDS`) | Augment validator with alias-target check in Task T-6 (optional; defer if bats tests cover it) | Deferred |
| R-5 | Vendor-side: if `claude-opus-4-7` endpoint has unannounced parameter differences (`max_tokens` renamed, streaming format change), live calls will fail in CI | PRD §14 pre-migration compat check runs as Task T-PRE before implementation begins | janitooor |

## 9. Non-Functional Validation

- **Pricing parity**: no `cost-ledger.jsonl` schema change; pricing values byte-identical.
- **Performance**: no change to call latency (same endpoint).
- **Security**: no change to secret handling; `ANTHROPIC_API_KEY` continues to authorize both 4.6 and 4.7.
- **Backward compatibility**: NFR-3 validated by bats tests (`claude-opus-4-6` alias resolves to a live model).

## 10. Acceptance Criteria (mirrored to sprint tasks)

1. `.claude/defaults/model-config.yaml` has canonical `claude-opus-4-7` block + retained 4.6 block + `aliases.opus` retargeted.
2. `.claude/scripts/model-adapter.sh.legacy` four-map invariant passes when sourced; contains 4.7 entries and retargeted aliases.
3. `.claude/scripts/model-adapter.sh`, `flatline-orchestrator.sh`, `red-team-model-adapter.sh` alias maps retargeted.
4. `.claude/data/model-permissions.yaml` contains 4.7 permission block.
5. Bridgebuilder TS resources (`config.ts`, `truncation.ts`, `personas/security.md`) and all 7 `__tests__/*.test.ts` updated; `npm test` green in that directory.
6. Python adapter fixtures (3) and test files (8) updated; `pytest .claude/adapters/tests/` green.
7. BATS tests updated (3 suites); `bats tests/unit/` green.
8. Documentation sweep (15+ SKILL.md + docs/ + README + CHANGELOG + BUTTERFREEZONE + example config) complete.
9. Grep-sweep gate passes (SKP-004).
10. Live-model-ID gate passes: post-migration Flatline run on this SDD shows 4.7 in opus slots (SKP-005).
11. Vision entry `vision-010` committed (already done in Phase 2).
12. CHANGELOG entry under Unreleased describes migration + alias-retarget flag + pricing parity.
13. Single PR against `main`, draft mode, HITL review requested from `@janitooor`.

## 11. Out-of-Scope (explicit)

- Formal review-quality benchmark harness (deferred to `vision-010`).
- Retiring older Opus IDs (`4.5`, `4.1`, `4.0`) from the alias map — they remain, retargeted.
- Changes to Sonnet, Gemini, or GPT model entries.
- Changes to executor default (spiral harness continues to use Sonnet 4.6).
- Changes to `hounfour.metering.budget.*` defaults — pricing parity means no budget re-tune needed.

## 11a. Cross-Runtime Contract Test (Flatline SDD SKP-004, accepted)

A new sprint task **T-CROSS** creates `.claude/scripts/tests/cross-runtime-alias-contract.sh` that:

1. Feeds the canonical alias set (`opus`, `claude-opus-4-7`, `claude-opus-4.7`, `claude-opus-4-6`, `claude-opus-4.6`) through each of the three resolution paths:
   - **Bash**: `source .claude/scripts/model-adapter.sh.legacy && echo "${MODEL_IDS[$alias]}"`
   - **Python**: invoke `.claude/adapters/resolve_alias.py --alias $alias --format provider_id` (if no such CLI exists, write a 5-line wrapper for this test)
   - **TypeScript**: `node -e "import('./dist/config.js').then(c=>console.log(c.resolveAlias('$alias')))"` (if TS compiles to dist) or equivalent ts-node invocation
2. Asserts all three return the same canonical `anthropic:claude-opus-4-N` string for each alias.
3. Runs in CI as part of the pre-merge acceptance gate (not inside unit test suites — this is an integration contract).

Exit code 0 iff all aliases resolve identically across all three runtimes.

This closes the single gap the Flatline skeptic raised (SKP-004): unit tests within each runtime can pass while a cross-runtime divergence slips through.

## 12. Bridgebuilder Review Dispositions (audit trail)

SDD reviewed 2026-04-17 via /simstim Phase 3.5, 7 findings produced, operator-accepted dispositions below:

| ID | Severity | Disposition | Action |
|----|----------|-------------|--------|
| PRAISE-001 | PRAISE | Acknowledge | No change — commit-sequencing validated |
| PRAISE-002 | PRAISE | Acknowledge | No change — R-4 disclosure validated |
| REFRAME-001 | REFRAME | Defer → vision-011 | Vision captured (auto-generate bash adapter maps from YAML) |
| HIGH-001 | HIGH | Accept | SDD §4.9 amended with build-verification requirement |
| MEDIUM-001 | MEDIUM | Accept | Pre-PR belt-and-suspenders grep over help/usage strings added to sprint T-PRE / post-migration gate |
| LOW-001 | LOW | Accept | SDD §4.7 amended to name trust-scope consumer |
| SPECULATION-001 | SPECULATION | Defer → vision-012 | Vision captured (role-based alias naming — `top-review-anthropic`) |

Full findings: `.run/bridge-reviews/design-review-simstim-20260417-4a16c55f.md`.

## 13. Flatline SDD Review Dispositions (audit trail)

SDD reviewed via Flatline Protocol 2026-04-17. 3-model consensus (Opus + GPT-5.3-codex + Gemini 2.5 Pro), 5 HIGH_CONSENSUS (auto-integrated), 1 DISPUTED, 5 BLOCKERS (operator-resolved):

| ID | Severity | Disposition | Action |
|----|----------|-------------|--------|
| IMP-001 | HIGH_CONSENSUS | Auto-integrate | PRD §13 strengthened with rollback triggers + verification |
| IMP-002 | HIGH_CONSENSUS | Auto-integrate | PRD §14 expanded with concrete compat-check matrix |
| IMP-003 | HIGH_CONSENSUS | Auto-integrate | PRD FR-8 grep-sweep spec strengthened with paths/patterns/contexts |
| IMP-004 | HIGH_CONSENSUS | Auto-integrate | SDD §4.2 canonical naming policy added (hyphenated canonical) |
| IMP-007 | HIGH_CONSENSUS | Auto-integrate | SDD §4.7 permission block enumeration (no placeholder) |
| IMP-010 | DISPUTED | Accept (merged with SKP-004) | Cross-runtime contract test covers the Python/bash divergence concern |
| SDD-SKP-001 | CRITICAL | Accept partial | §14 matrix expanded (tools, thinking traces, error handling); streaming + rate-limit explicitly out of scope |
| SDD-SKP-002 | CRITICAL | Override | Same issue as vision-011 (bash-map generation from YAML) — dedicated future cycle |
| SDD-SKP-003 | HIGH | Override | Repeat of PRD SKP-003; SDD §4.2 escape hatch addresses |
| SDD-SKP-004 | HIGH | Accept | §11a added — new sprint task T-CROSS for cross-runtime contract test |
| SDD-SKP-005 | HIGH | Override | Solo maintainer; 8-commit bisection + validator + grep gate = equivalent safety |

Full rationale preserved in `.run/simstim-state.json` `blocker_decisions[]`.
