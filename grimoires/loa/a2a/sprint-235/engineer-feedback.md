All good

# Sprint 1 Review Feedback — round 2

**Reviewer:** Senior Tech Lead Reviewer Agent (Fable 5.1 lead acting as gate; independent input: cross-model dissent, three passes)
**Date:** 2026-09-17
**Sprint Reference:** grimoires/loa/sprint.md (Sprint 1, global sprint-235)
**Implementation Report:** grimoires/loa/a2a/sprint-235/reviewer.md
**Previous round:** round 1 (2026-09-17) — CHANGES_REQUIRED, 0 critical / 5 high / 9 medium / 9 low, all accepted by the implementer.

---

## Overall Assessment

Scope of this round: the fix commits after `19ffd850` — `0f8c1df6` adapter, `fcc31c5e` ledger, `77f9180f` gates, `16b88d56` tooling, `632d0961` repo map, `12b6067e` readers (round-2 dissent DISS-001), `e14b3e7c` prototype-safe budget lookup, `44e1feab` live workflow manual-only (audit dissent), `f740be39` KF-004 row — read as a diff (211 KB) and re-read in place at every citation the report carries; the full sprint diff (80be4b0f..HEAD, 918 KB, 118 files) was re-walked for the files the fixes touched.

Every round-1 finding is closed by a code or test change I could point at, each with a test that is red on the pre-fix commit (`scratchpad/red-proof-r1.sh`: 16 pytest failures, 6 bats, 1 Bridgebuilder suite on `19ffd850`; the round-2 reader test, the DISS-001 bats case and the prototype-safe case fail on `632d0961`). The adapter suite is 2190/0 (2174 before the round), the bats verification set 142/142 including `test_golden_path.bats`, drift gates OK, hygiene tripwire OK, AC-verification gate pass (7 criteria). The fences named in the operator prompt are untouched (`git diff 80be4b0f..HEAD -- .claude/hooks .claude/scripts/{implement-gate,zone-write-guard,block-destructive-bash,audit-envelope}.sh .claude/settings.json` is empty).

**Cross-model dissent, round 2** (`adversarial-review.sh --type review`, gpt-5.5-pro via codex-headless, round-1 feedback + twelve lead concerns as context, on the fix diff):
- pass 1 — **DISS-001 BLOCKING**: `rollup.default_ledger_path()` swallowed the resolver's `ConfigError` and silently read `.run/cost-ledger.jsonl`, so a refused path became a report over another file. Accepted and fixed (`12b6067e`: the reader raises, the rollup CLI exits 2, `cost-report.sh` resolves its default after argument parsing and exits 2 on a refusal; an explicit `--ledger` never consults the resolver; the literal fallback survives only for an unavailable Python substrate).
- pass 2 (after `12b6067e`, `e14b3e7c`) — `clean`, 0 findings, `verdict_quality: APPROVED`.
- pass 3 (after `44e1feab`) — `clean`, 0 findings, `verdict_quality: APPROVED`, no truncation waiver. Rejected-payload sidecar for the review type: empty.

**Verdict:** APPROVED

---

## Previous Feedback Status

| Round-1 item | Status | Verified at |
|---|---|---|
| H1 persona-less `--system` payload unmarked (PRD FR-4) | Fixed | `.claude/adapters/cheval.py:219` marks the whole payload when no persona; `test_anthropic_cache_control.py:74` (marked), `:84` (real Bridgebuilder prefix under `--agent reviewing-code` ⇒ exactly one breakpoint); live scaffold builds through the production path `tests/replay/test_cycle124_live_floor.py:149`; SDD §2.2 + SDD-R1-1; `context-engineering.md` Bridgebuilder row. Callers checked: BB `cheval-delegate.ts:148` (stable prefix), `model-adapter.sh:581/586` (`--context`/`--prompt` carry the dissent instructions, the diff travels in `--input`), `flatline-orchestrator.sh:992` (agents with personas — context stays the second, unmarked message). No caller marks a per-call payload. |
| H2 `max_tokens` stop flag never fired for Fable | Fixed | `cheval.py:737` `_entry_thinking_class`; the second clause (`temperature_supported: false` without the flag) matches exactly `claude-fable-5-1` / `claude-fable-5` in the live catalog — no false positive; `test_anthropic_cache_control.py:307` (three cases), `:332` (plain stop not flagged) |
| H3 `--effort` dropped on the claude-headless hop | Fixed | `claude_headless_adapter.py:255`; `test_claude_headless_adapter.py:231` (argv capture, outranks metadata and model-config; `_ALLOWED_EFFORTS` still filters) |
| H4 audit cross-check fail-open shapes; review trailer unvalidated on the audit path | Fixed | `golden-path.sh:117` strict last-trailer parse (`invalid` denies), `:184` review gate on the audit path; `golden-path-c8-verdict-trailer.bats:319`, `:338`, `:354`. Two-trailer files: `verdict-derive.sh` rejects them (multiple trailers) before `_gp_trailer_int` is consulted — still closed. |
| H5 ledger resolver accepted directories / `/dev/null`; CWD-relative config path | Fixed | `metering/ledger.py:49` (`S_ISREG` on `lstat`, project-root anchoring via the same walk as the MODELINV twin; env stays CWD-relative, documented); `test_ledger_isolation.py:90`, `:116`, `:160`. A FIFO or socket fails `S_ISREG` too. |
| M1 every 404 chain-walked | Fixed | `anthropic_adapter.py:61` `_is_model_not_found`; `test_anthropic_404_chain_walkable.py:103` |
| M2 stale `_load_persona` stubs, CWD-dependent matrix | Fixed | `_load_persona_parts` stubbed in `test_input_size_consumers.py:113` and the four siblings; matrix green from the repo root and from `.claude/adapters` |
| M3 isolation test asserted the mechanism | Fixed | `test_ledger_isolation.py:219` (invariant: neither ledger under the repo `.run/`) |
| M4 headless `Usage.cache_*` unasserted | Fixed | `test_claude_headless_adapter.py:358` |
| M5 AC-4.2 mixed fixture missing | Fixed | `tests/fixtures/metering/mixed-cost-ledger.jsonl`; `cycle-124-cache-telemetry.bats:170` (rollup), `:184` (cost-report), `:194` (economy roll-up over the mixed-writer MODELINV fixture); the three post-cache rows' costs recomputed against the live catalog rates with `calculate_total_cost` — all three match |
| M6 readers resolved their default outside the merged config | Fixed (+ DISS-001) | `rollup.py:44`, `cost-report.sh:36` + `:93`; `cheval-cost-rollup.bats:74`, `:101`; `test_ledger_isolation.py:66` |
| M7 ceiling probe semantics | Fixed | `tools/ceiling-probe.py:44` (`message_stop` = OK, 1024 tokens, `stop_reason` recorded) — live-only tool, reviewed by reading |
| M8 `FLATLINE_SCORE_MAX_TOKENS=4000` | Fixed | `flatline-orchestrator.sh:128` = 16000; `cycle-124-dispatch-budgets.bats:82` |
| M9 regen bats unguarded | Fixed | skips without the toolchain; `regen-model-artifacts.sh:55` exit 3; `cycle-124-anthropic-catalog.bats:129`, `:170`. No CI workflow calls the regen script directly (grep), so exit 3 has no unhandled caller. |
| L1 temperature warning on every call | Fixed | once per model per process, INFO after (`anthropic_adapter.py:178`); `test_anthropic_thinking.py:174` |
| L2 legacy-wire claim over-stated | Fixed | scoped in the report; `test_anthropic_thinking.py:132` (per family, live catalog) |
| L3 effort totality test unfalsifiable | Fixed | `_EFFORT_FULL_PREFIXES` (`anthropic_adapter.py:58`); `test_anthropic_effort_families.py:115` |
| L4 AC-3.4 read the yaml | Fixed | `test_anthropic_catalog_floor.py:225` (loader `resolve(role='review', …)`) |
| L5 catalog RED figure from a draft | Fixed | report RED-first line restated (collection error on 80be4b0f) |
| L6 hygiene rule anchored on `/tmp/` | Fixed | `check-ledger-hygiene.sh:158`; tripwire suite green |
| L7 `progressiveTruncate` clamped unknown ids | Fixed | `truncation.ts` known-id clamp + own-key lookup (`:674`, round-2 concern 10); `progressive-truncation.test.ts:307`, `:314`; dist rebuilt, drift gates OK |
| L8 regen precheck | Fixed | see M9 |
| L9 explicit `--max-tokens` clamp on every provider | Accepted as-is | disclosed in the report and to be disclosed in the PR body; a value above a fallback hop's cap would otherwise 400 on the rescue hop |
| DISS-001 (round-2 dissent) reader swallowed `ConfigError` | Fixed | `12b6067e`; passes 2 and 3 clean |
| AUD-D1 (audit dissent, sidecar) live workflow handed the key to PR-controlled code on `pull_request` | Fixed | `44e1feab` `workflow_dispatch`-only + `environment: live-floor`; `cycle-124-live-scaffold.bats` c124-1.8-5; residual (a dispatched run executes the candidate branch's tests) accepted with the environment-protection precondition recorded in the workflow header and the report |

---

## Critical Issues (Must Fix Before Approval)

None.

## Non-Critical Improvements (Recommended)

None outstanding for this sprint. Follow-up beads (not Sprint 1 changes, recorded in the report): pre-flight exit 7 vs legacy-wall exit 12 for one refusal class; the 120 s orchestrator/BB default timeouts against 16K answers at ~44 tok/s; `MODE_TO_AGENT["dissent"]` naming a non-existent skill directory (PRD Q6); KF-004 recurred twice this sprint (the dissenter omits `id`) — Sprint 2's structured outputs are the fix.

## Incomplete Tasks

None. AC-1.3 and AC-4.3 remain committed skip-clean live scaffolds per the sprint plan (`live-floor-check.yml`, dispatched by the operator, is the draft PR's merge precondition).

## Acceptance Criteria Check

| Criterion (sprint.md) | Status | Evidence |
|---|---|---|
| AC-6.1 … AC-6.4 | Pass | `ledger.py:49` resolver (symlink, non-regular, parent, anchoring), `:206` `O_NOFOLLOW`; conftests; `test_ledger_isolation.py:66/90/116/160/219/234`; tripwire + rotation archives |
| AC-3.1 … AC-3.6 | Pass | catalog bats c124-1.3-1…14; `test_anthropic_catalog_floor.py:225`; AC-3.5 matrix `test_input_size_consumers.py:173` + `input-size-consumers.bats`; CI grafts |
| AC-2.1 … AC-2.6 | Pass | `base.py:168`, `cheval.py:712`, headless `:255`; `test_max_tokens_defaults.py`, `test_chain_walk_audit_envelope.py:548`, `test_anthropic_effort_families.py:89/115`, `cycle-124-effort-flag.bats`, `cycle-124-dispatch-budgets.bats` |
| AC-1.1, AC-1.2 (+ AC-1.3 scaffold) | Pass | `anthropic_adapter.py:191`; `test_anthropic_thinking.py:96/132/174/273`; `cheval.py:737` + `test_anthropic_cache_control.py:307/332` |
| AC-4.1, AC-4.2, AC-4.4 (+ AC-4.3 scaffold) | Pass | `cheval.py:219`, `anthropic_adapter.py:529`; `test_anthropic_cache_control.py:74/84/104/255`; headless `:358`; mixed fixture through three consumers; readers `rollup.py:44` / `cost-report.sh:36`; `test_cycle124_live_floor.py:149` |
| AC-5.1, AC-5.2 | Pass | `golden-path.sh:94/117/184`; `golden-path-c8-verdict-trailer.bats` 27 cases; doc-lock cases |
| Adapter pytest ≥ 1937 / drift gates / REPO-MAP / KF rows | Pass | 2190 passed; `regen-model-artifacts.sh --check` OK; REPO-MAP regenerated in `632d0961` and `e14b3e7c`; KF-002 / KF-006 / KF-004 rows |

## Documentation Verification

CHANGELOG `[Unreleased]` carries the round-1/round-2 entry; SDD §2.2 corrected with §10 rows SDD-R1-1..3; `context-engineering.md` cache table has the Bridgebuilder row; NOTES Decision Log records the round-1, round-2 and audit-dissent decisions; the report's Commits table lists every SHA.

## Next Steps

1. `/audit-sprint sprint-1` (in flight: four read-only audit slices + the audit dissent).
2. On approval: COMPLETED marker, ledger status, beads, Sprint 2.

## Addendum — audit-phase commits (2026-09-18)

The audit added `12b6067e`, `e14b3e7c`, `44e1feab`, `7665775b`, `f740be39`, `2b43baf4`, `1991390f`, `4670b22f`, `087fc39e` after this approval was first written. Each was re-read by the reviewer (the fix table in `reviewer.md` lists file:line and pin per item) and the fix diff `19ffd850..087fc39e` (345 KB) was dissented a fourth time: `clean`, 0 findings, `verdict_quality: APPROVED`, review sidecar empty. The adapter suite is 2203/0 after these commits; the bats verification set and drift gates are green. The approval stands over the final tree.

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-09-17T22:20:00Z"} -->
