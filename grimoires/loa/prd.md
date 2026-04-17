# Product Requirements Document — Opus 4.7 Top-Review Migration

**Cycle**: 082 (Opus 4.7 Migration)
**Status**: DRAFT
**Author**: janitooor (via /simstim on claude-opus-4-7)
**Date**: 2026-04-17
**Branch**: `feat/opus-4-7-migration`
**Prior cycle preserved**: `wip/review-pipeline-hardening` @ `5d00df1`

---

## 1. Summary

Migrate the Loa framework's **top-review / advisor / primary-adversary** role from Claude Opus 4.6 to Claude Opus 4.7 across all review-critical subsystems (Flatline Protocol, Bridgebuilder, red-team adapter, spiral advisor, and documentation). Preserve Opus 4.6 as a backward-compatible alias so pinned configs and experiments continue to resolve.

Pricing for Opus 4.7 was verified against anthropic.com on 2026-04-17: **$5/Mtok input, $25/Mtok output** — identical to 4.6. No pricing uncertainty blocks this cycle.

## 2. Goals

| ID   | Goal |
|------|------|
| G-1  | Default `opus` alias resolves to `claude-opus-4-7` across all adapters (bash, Python, TypeScript, YAML config) |
| G-2  | Flatline primary/advisor model is `claude-opus-4-7` in orchestrator + protocol docs + readiness checks |
| G-3  | Bridgebuilder enriched-review model constants point to `claude-opus-4-7` |
| G-4  | Red-team adapter's attacker/defender opus role uses `claude-opus-4-7` |
| G-5  | Pinned `claude-opus-4-6` continues to resolve (backward-compat alias retained in all 4 bash maps + YAML aliases) |
| G-6  | All test suites (bats + Python + TS) pass after migration; no skipped review-critical tests |
| G-7  | Documentation (README, CHANGELOG, CONFIG_REFERENCE, SKILL.md files, runtime-contract) reflects 4.7 as current top-review model |

## 3. Non-Goals

- Migrating the **executor** default (Sonnet 4.6 remains the spiral-harness executor per `feedback_advisor_benchmark`)
- Migrating the **cheap** alias (continues to point at `sonnet-4-6`)
- Introducing Opus 4.7 as a new role (jam-reviewer, deep-thinker, etc.) — scope is limited to retargeting the existing top-review/advisor role
- Removing legacy Opus aliases (`4.5`, `4.1`, `4.0`) — they remain, retargeted to 4.7 per the established alias pattern
- Bumping model-ID format (keep `claude-opus-4-7`, not dated suffix like `-20260xxx`)
- **Quantitative review-quality benchmark harness (deferred per SKP-001)** — building a formal benchmark suite with pass-rate deltas and regression thresholds to validate 4.7 vs. 4.6 review quality is its own cycle. Captured as vision entry `opus-quality-benchmark` for future work. This cycle's quality validation is the dogfood Flatline run per NFR-4.

## 4. Users & Stakeholders

| Role | Interest |
|------|----------|
| Loa operators running `/simstim`, `/flatline-review`, `/run-bridge` | Transparent upgrade — their primary review gets 4.7 quality automatically |
| Contributors with pinned `claude-opus-4-6` in local `.loa.config.yaml` overrides | Backward-compat alias means no forced config change |
| Construct pack authors targeting `opus` alias | Inherit 4.7 top-review automatically |
| Operators tracking review cost (`cost-ledger.jsonl`) | Pricing unchanged — no budget impact |

## 5. Functional Requirements

### FR-1: Model Registry Updates (System Zone, authorized this cycle)

Add `claude-opus-4-7` as the canonical Anthropic Opus entry in:

- **`.claude/defaults/model-config.yaml`** — under `providers.anthropic.models`, pricing `input_per_mtok: 5000`, `output_per_mtok: 25000`
- **`.claude/scripts/model-adapter.sh`** — add to all 4 associative arrays (`MODEL_PROVIDERS`, `MODEL_IDS`, `COST_INPUT`, `COST_OUTPUT`); invariant enforced by `validate_model_registry()` at source time
- **`.claude/scripts/model-adapter.sh.legacy`** — mirror the canonical adapter
- **`.claude/data/model-permissions.yaml`** — add `anthropic:claude-opus-4-7` permission block (mirroring 4.6's)

### FR-2: Alias Retarget

Retarget `opus` alias → `claude-opus-4-7` in:

- `.claude/defaults/model-config.yaml` (`aliases.opus`)
- `.claude/scripts/model-adapter.sh` (and `.legacy`)
- `.claude/scripts/red-team-model-adapter.sh`

Add backward-compat aliases to all 4 bash maps (lookup invariant):

- `claude-opus-4.6` → `anthropic:claude-opus-4-7`
- `claude-opus-4-6` → `anthropic:claude-opus-4-7`

Retarget older-version aliases (4.5, 4.1, 4.0 in both dotted and hyphenated forms) to point at `claude-opus-4-7`.

### FR-3: Flatline Protocol

- `.claude/scripts/flatline-orchestrator.sh` — default primary model → `claude-opus-4-7`
- `.claude/scripts/flatline-readiness.sh` — `primary` model label reports `opus` (unchanged alias, resolves to 4.7)
- `.claude/protocols/flatline-protocol.md` — protocol doc updates 4.6 refs to 4.7
- `.claude/loa/reference/flatline-reference.md` — reference doc updated
- `.claude/templates/flatline-dissent.md.template` — if model ID is rendered, update
- `.claude/evals/flatline-3model.sh` — eval invocation updated

### FR-4: Bridgebuilder

- `.claude/skills/bridgebuilder-review/resources/config.ts` — model constant → `claude-opus-4-7`
- `.claude/skills/bridgebuilder-review/resources/core/truncation.ts` — any hardcoded model ID updated
- `.claude/skills/bridgebuilder-review/resources/personas/security.md` — if model ID mentioned
- `.claude/skills/bridgebuilder-review/resources/__tests__/*.test.ts` — fixtures/expected values updated to 4.7

### FR-5: Red Team

- `.claude/scripts/red-team-model-adapter.sh` — attacker/defender opus role → 4.7

### FR-6: Python Adapter

- `.claude/adapters/tests/fixtures/anthropic_*.json` — `model` field in response fixtures → `claude-opus-4-7`
- `.claude/adapters/tests/test_*.py` — expected model assertions updated

### FR-7: Documentation & SKILL.md

Update the following SKILL.md / reference files to reflect Opus 4.7 as the current top-review / advisor model wherever 4.6 is currently named as such:

- `.claude/skills/red-teaming/SKILL.md`
- `.claude/skills/run-bridge/SKILL.md`
- `.claude/skills/run-mode/SKILL.md`
- `.claude/skills/simstim-workflow/SKILL.md`
- `.claude/skills/spiraling/SKILL.md`
- `.claude/skills/bridgebuilder-review/SKILL.md`
- `.claude/skills/autonomous-agent/resources/operator-detection.md`
- `.claude/loa/reference/context-engineering.md`
- `.claude/schemas/README.md`
- `docs/CONFIG_REFERENCE.md`
- `docs/integration/runtime-contract.md`
- `.loa.config.yaml.example`
- `evals/README.md`
- `README.md`
- `BUTTERFREEZONE.md` (if it names the primary review model)

**Do NOT** rewrite historical/research documents:
- `grimoires/loa/reports/spiral-harness-benchmark-report.md` — historical record
- `grimoires/pub/research/anthropic-updates-2026-03-17.md` — dated research
- `CHANGELOG.md` — historical entries preserved; new entry added for this migration

### FR-8: Test Suites & Post-Migration Gates

All of the following must pass after migration:

- `tests/unit/model-adapter-aliases.bats` — updated to assert 4.7 canonical + 4.6 alias
- `tests/unit/flatline-model-validation.bats` — primary model validation expects 4.7
- `tests/unit/flatline-readiness.bats` — readiness output asserts 4.7
- `.claude/adapters/tests/test_*.py` — all Python tests green
- `.claude/skills/bridgebuilder-review/resources/__tests__/*.test.ts` — all TS tests green

**Post-migration acceptance gates** (SKP-004, SKP-005 — accepted Flatline findings):

- **Grep sweep (SKP-004, strengthened per Flatline SDD IMP-003)**:
  - **Patterns**: `claude-opus-4-6`, `claude-opus-4\.6`, `opus-4\.6`, `opus 4\.6`, `Opus 4\.6`, `Claude Opus 4\.6`
  - **Paths included**: `.claude/scripts/`, `.claude/skills/`, `.claude/adapters/`, `.claude/defaults/`, `.claude/data/`, `.claude/protocols/`, `.claude/loa/`, `.claude/templates/`, `.claude/schemas/`, `.claude/evals/`, `docs/`, `evals/`, `README.md`, `BUTTERFREEZONE.md`, `.loa.config.yaml.example`, `CHANGELOG.md`
  - **Paths excluded** (historical record, no edit): `grimoires/loa/reports/`, `grimoires/pub/research/`, `grimoires/loa/visions/` (prior vision entries may reference 4.6), and git history itself
  - **Acceptable match contexts**: backward-compat alias map entries (`claude-opus-4-6 → claude-opus-4-7`), CHANGELOG entries (historical + this migration's retarget note), alias-documentation comments, explicit "pinned historical model" mentions in SDD §4.2
  - **Unacceptable match contexts**: default-model assignments, runtime model-selection code paths, test expectations, usage/help strings that name "Opus 4.6" as the primary review model
  - **Owner**: migration author — responsible for triaging every match before PR open
  - **Tooling**: implemented as a pre-merge bash script committed to the repo (task T-GREP in sprint plan); script exit 0 iff matches are only in acceptable contexts.
- **Live-model-ID gate (SKP-005)**: after migration, run `.claude/scripts/flatline-orchestrator.sh --doc grimoires/loa/sdd.md --phase sdd --json` and verify the emitted model references in the Phase 1 output correspond to `claude-opus-4-7` for the opus slots. Recorded as evidence in the PR body.

### FR-9: CHANGELOG Entry

New entry under Unreleased (or next version) documenting:
- Opus 4.7 as top-review default
- Backward-compat alias for 4.6
- Pricing confirmed identical
- **Legacy alias retarget flag (IMP-005 / SKP-003)**: explicit note that `claude-opus-4.5`, `claude-opus-4.1`, `claude-opus-4.0` aliases (and hyphenated variants) now resolve to 4.7. Operators relying on a specific legacy model for historical benchmarks must pin the canonical model ID directly (`anthropic:claude-opus-4-6` or earlier) via `.loa.config.yaml` — aliases are backward-compat convenience, not a reproducibility guarantee.

## 6. Non-Functional Requirements

| ID    | Requirement |
|-------|-------------|
| NFR-1 | **Zero pricing drift**: cost ledger entries for runs using `opus` alias remain accurate (pricing identical to 4.6) |
| NFR-2 | **Four-map invariant**: `validate_model_registry()` must pass without errors after migration (catches cross-PR map inconsistencies at startup, per PR #202 precedent) |
| NFR-3 | **Backward-compat honored**: any config, script, or test referencing `claude-opus-4-6` continues to resolve to a live model (4.7) via alias |
| NFR-4 | **No gross review-quality regression**: dogfood verification — run a live Flatline review on this cycle's SDD with 4.7 as primary and confirm the output is substantively similar in quality (non-zero findings, coherent scoring, no degraded-mode fallback). Formal quantitative benchmark (SKP-001) deferred to a separate cycle; see Section 10 (Non-Goals) and vision registry entry `opus-quality-benchmark`. |
| NFR-5 | **System Zone discipline**: all `.claude/` writes enumerated here; no ad-hoc additions during implementation |

## 7. Risks

| ID   | Risk | Mitigation |
|------|------|------------|
| R-1  | Missing one of the 4 bash maps → silent lookup fallthrough | `validate_model_registry()` runs on adapter source; bats tests assert all 4 keys present |
| R-2  | TypeScript fixture drift (bridgebuilder tests) vs. runtime config | Tests run in CI; test_config.test.ts locks the constants |
| R-3  | SKILL.md references drift (reviewer mentions 4.6 while config says 4.7) | Grep sweep in acceptance criteria: `rg 'opus-4.6|opus 4\.6' .claude/skills/` returns only historical/research contexts |
| R-4  | Forgotten Python fixture files → test_flatline_routing failures | Sprint task enumerates all 3 fixtures explicitly |
| R-5  | Legacy alias removal inadvertently breaks a pinned override | Keep all legacy aliases; only retarget them |
| R-6  | Pricing data staleness (today 2026-04-17, verified today) | Confirmed on anthropic.com directly for this cycle; re-check before next pricing-related cycle |
| R-7  | Opus 4.7 API endpoint/ID mismatch in live calls | **Concrete pre-merge gate**: run `.claude/scripts/flatline-orchestrator.sh --doc grimoires/loa/sdd.md --phase sdd --json > /tmp/post-migration-smoke.json`, then confirm `claude-opus-4-7` appears in the opus slots (grep or jq) of the emitted output. Evidence attached to PR body. |

## 8. Dependencies

- Verified Anthropic API availability of `claude-opus-4-7` (confirmed — this very conversation runs on it per system prompt)
- `validate_model_registry()` function (present since PR #202)
- `ajv` for schema validation (already in CI)
- Beads installed for sprint task lifecycle

## 9. Success Metrics

- All tests green on the migration branch
- Flatline readiness reports `primary: opus` (unchanged label, resolves to 4.7) with exit code 0
- **Live-model-ID gate (SKP-005)**: post-migration Flatline run on this cycle's SDD records `claude-opus-4-7` in the opus slots of the emitted JSON output
- **Grep-sweep gate (SKP-004)**: `rg 'claude-opus-4-6|opus-4\.6' .claude/ docs/ README.md .loa.config.yaml.example evals/README.md BUTTERFREEZONE.md` returns only alias-layer / CHANGELOG / historical-comment matches
- `validate_model_registry()` exits 0 when adapter is sourced (four-map invariant passes)
- Single merged PR, full implement→review→audit cycle completed
- No post-merge rollback required
- CHANGELOG entry merged with retarget-flag note

## 10. Scope Fence

**In scope**: the 48 files surfaced by `rg 'claude-opus-4-6|opus-4\.6|opus 4\.6'` at cycle start, filtered for review-critical role references (not historical records).

**Out of scope**: anything else. Explicitly excluded:
- Historical reports and research docs
- Dated research files
- Any model other than Opus (Sonnet, Gemini, GPT unchanged)
- Any role other than top-review/advisor (executor, cheap, etc.)

## 11. Pricing Verification (NFR-1 evidence)

| Source | Date checked | Input $/Mtok | Output $/Mtok |
|--------|-------------|-------------|--------------|
| anthropic.com/claude/opus | 2026-04-17 | $5.00 | $25.00 |
| docs.anthropic.com/en/docs/about-claude/pricing | 2026-04-17 | $5.00 | $25.00 |

Current 4.6 entry in `.claude/defaults/model-config.yaml`: `input_per_mtok: 5000`, `output_per_mtok: 25000` (micro-USD). **Identical** → no ledger adjustment needed.

## 12. System Zone Write Authorization

This PRD constitutes explicit cycle-level authorization for writes to the following System Zone paths during implementation, per `.claude/rules/zone-system.md`:

```
.claude/defaults/model-config.yaml
.claude/scripts/model-adapter.sh
.claude/scripts/model-adapter.sh.legacy
.claude/scripts/flatline-orchestrator.sh
.claude/scripts/flatline-readiness.sh
.claude/scripts/red-team-model-adapter.sh
.claude/evals/flatline-3model.sh
.claude/protocols/flatline-protocol.md
.claude/loa/reference/flatline-reference.md
.claude/loa/reference/context-engineering.md
.claude/templates/flatline-dissent.md.template
.claude/data/model-permissions.yaml
.claude/schemas/README.md
.claude/skills/*/SKILL.md  (enumerated in FR-7)
.claude/skills/bridgebuilder-review/resources/**  (enumerated in FR-4)
.claude/skills/autonomous-agent/resources/operator-detection.md
.claude/adapters/tests/**  (enumerated in FR-6)
tests/unit/model-adapter-aliases.bats
tests/unit/flatline-model-validation.bats
tests/unit/flatline-readiness.bats
```

All other System Zone paths are out of scope.

## 13. Rollback Procedure (SKP-002 override)

If post-merge telemetry or a user report indicates a review-quality regression or live-call failure attributable to Opus 4.7:

### Rollback authority (Flatline Sprint IMP-001, accepted)

**Who decides**: `@janitooor` (primary maintainer) is the sole rollback authority. Contributors observing a trigger condition file a `/bug` report or open an issue; the maintainer executes the revert.

### Triggers for rollback (Flatline SDD IMP-001, accepted)

Rollback should be initiated when ANY of the following is observed within 24 hours of merge:

- A Flatline review fails to produce output (exit code ≠ 0 on the Anthropic slot) — signals live-call breakage
- A Flatline review returns `degraded: true` with `degraded_model=opus*` (4.7 endpoint unavailable) for >30 minutes
- Cost ledger shows a >2× pricing delta from the migration baseline (vendor pricing drift)
- An operator reports demonstrably lower review quality (missed findings the old model caught) on ≥2 comparable documents

### Full rollback (maintainer action)

```
git revert <merge-commit-sha>
git push origin main
```

The migration is a single PR with no dependent state mutations (no DB migrations, no persisted model-output schemas, no ledger-format changes — pricing is byte-identical to 4.6). Revert is atomic.

**Verification after revert**:
1. `.claude/scripts/flatline-readiness.sh --json` returns `status: READY`
2. `.claude/scripts/flatline-orchestrator.sh --doc <any recent doc> --phase prd --json` completes without degraded fallback
3. Grep confirms `opus` alias points at `anthropic:claude-opus-4-6` in all three adapters

**Retention**: keep the reverted commit visible in history (no force-push, no delete); the post-mortem reference lives in CHANGELOG and in the PR body.

### Operator-level override (no maintainer action required)

Any operator can pin 4.6 in their local `.loa.config.yaml` before the revert ships:

```yaml
hounfour:
  providers:
    anthropic:
      models:
        claude-opus-4-6:
          # entry retained in defaults; referenceable directly
  aliases:
    opus: "anthropic:claude-opus-4-6"
```

The 4.6 registry entry is retained in `.claude/defaults/model-config.yaml` as a supported pinnable fallback (not just an alias target). This is the "kill switch" requested by SKP-002: a one-file, no-framework-change path back to 4.6.

### Degraded-mode fallback

Existing Flatline routing fallback (`anthropic: [openai]`) handles provider outages independently of model choice and is unaffected by this migration.

## 14. Pre-Migration Compatibility Check (IMP-004, strengthened per Flatline SDD SKP-001)

Before any implementation code is written, verify 4.7 API/behavioral parity with 4.6 on the dimensions the Loa framework depends on:

| Dimension | Check | Evidence |
|-----------|-------|----------|
| Context window | Confirm 200K input tokens still supported | `curl -s https://api.anthropic.com/v1/messages` with 150K-token payload succeeds |
| Token parameter name | Confirm `max_tokens` still accepted (not renamed) | Single-turn request with `max_tokens: 100` returns content |
| Basic capabilities (chat) | Plain completion works | Single-turn text response |
| Tool use | `tool_use` / `tool_result` round-trip works on 4.7 | Single tool-call test (mock calculator) echoes `tool_use` block |
| Thinking traces | `thinking` parameter with budget still accepted | Request with `thinking: {type: "enabled", budget_tokens: 1024}` returns both `thinking` and `text` blocks |
| Error handling | Standard 4xx/5xx response envelopes unchanged | Deliberately-malformed request returns `{"type":"error","error":{...}}` same as 4.6 |
| Endpoint | Same `/v1/messages` endpoint (no new path) | Reuse existing adapter's endpoint URL |
| Response schema | `model` field echoed; `content[].text` and `stop_reason` structures unchanged | Parse response with existing Python adapter — no schema errors |

**Out of scope for this cycle** (per SDD SKP-001 accepted partial): streaming differential behavior and rate-limit behavior differences between 4.6 and 4.7. Loa's synchronous Flatline path does not exercise streaming; rate-limit behavior is endpoint-level, not model-level. Re-raise as a concern if/when streaming usage lands.

Executable as a pre-implementation smoke script (Task T-PRE in sprint plan). If any check fails, halt implementation and return to DISCOVERY.

## 15. Implementation Sequencing (IMP-003)

To minimize CI churn and partial-state risk across a 48-file, multi-language migration, implementation proceeds in this atomic order within a single PR:

1. **Registry add** (4.7 canonical entries) — additive, non-breaking. Adapter tests still pass (4.6 remains canonical).
2. **Alias retarget** — swap `opus` alias and legacy aliases to resolve to 4.7. Adapter tests re-run; all four bash maps validated.
3. **Subsystem switches** (Flatline orchestrator, bridgebuilder config.ts, red-team adapter, Python adapter, TS fixtures) — per-subsystem, each commit leaves the system in a working state.
4. **Test fixture updates** (bats + Python + TS) — final commit green.
5. **Documentation sweep** (SKILL.md files, docs/, README, BUTTERFREEZONE, CHANGELOG) — last, cosmetic.

Each step commits independently to aid bisection if post-merge issues arise.

## 16. Flatline Review Dispositions (audit trail)

Flatline PRD review, 2026-04-17: 5 HIGH_CONSENSUS auto-integrated, 5 BLOCKERS resolved:

| ID      | Severity | Disposition | Rationale (summary) |
|---------|----------|-------------|---------------------|
| SKP-001 | CRITICAL | Defer → vision | Formal benchmark harness deferred; dogfood Flatline + revert-cheapness is proportionate |
| SKP-002 | CRITICAL | Override + §13 | Git-revert + registry-pinnable 4.6 = kill switch for a framework repo |
| SKP-003 | HIGH     | Override + FR-9 | Established pattern (PR #207); canonical IDs remain available for historical pinning |
| SKP-004 | HIGH     | Accept + FR-8 gate | Post-migration grep sweep added to acceptance |
| SKP-005 | HIGH     | Accept + R-7/§9 gate | Concrete live-model-ID Flatline smoke added to acceptance |

Full rationale text preserved in `.run/simstim-state.json` `blocker_decisions[]`.
