All good

# Sprint 2 Review Feedback — round 1

**Reviewer:** Senior Tech Lead Reviewer Agent (Fable 5.1 lead acting as gate; independent input: cross-model dissent, four passes)
**Date:** 2026-09-20
**Sprint Reference:** grimoires/loa/sprint.md (Sprint 2, global sprint-236)
**Implementation Report:** grimoires/loa/a2a/sprint-236/reviewer.md

---

## Overall Assessment

Scope: `087fc39e..012d0c5e` — 78 files, +2764/−326: the five wire schemas and their parity lint, `CompletionRequest.output_schema` with capability-gated Anthropic emission and derived `schema_enforced`, the claude-headless `--json-schema` path with `structured_output` and a one-shot unenforced retry on a CLI-side schema rejection, `cheval --json-schema` (regular file, object root, ≤ 64 KB, canonical hash) threaded to every hop with MODELINV/CLI-JSON telemetry, the dissent's enforced strict-parse branch with the flag-less repair loop on unenforced voices and an unconditional DEGRADED on rejection, Flatline schema plumbing and strict qualification, the synthetic fixture corpus, the isolated OpenAI `text.format` hunk, plus the framework fixes that surfaced on the way (ledger-lib string-sprint guard, indirect-spawner ledger isolation, the late Sprint 1 slice-C gate hardening).

Every `## AC Verification` citation in the report was opened and holds (`validate-ac-verification.sh --sprint-id sprint-2` passes; the lines were re-derived after the last commit). Every behaviour change arrived with a test that is red on the pre-change commit (`scratchpad/red-proof-s2{a,b,c}.sh`: 29 failed + 8 errors, 24 bats, 7 bats respectively) except the pure evidence pins, which the report labels as such. The adapter suite is 2256/0; the Sprint 2 bats set 75/75; the gate suites (golden-path 30, verdict-derive 54, `test_golden_path` 47, consumer inventory 12) green; every other adversarial-review (149) and Flatline (202) case unchanged; `check-no-swallowed-jq.sh`, `regen-model-artifacts.sh --check` and `check-ledger-hygiene.sh` OK. The fences named in the operator prompt are untouched in this range.

**Cross-model dissent** (`adversarial-review.sh --type review`, gpt-5.5-pro via codex-headless, with the reviewer's twelve concern notes): pass 1 returned **DISS-001 BLOCKING** — FR7-10 asserted "no sidecar row" on a sidecar shared across fixtures, so the assertion depended on loop order and on the per-invocation truncation. Accepted and fixed (`037dee75`: one sprint dir, hence one sidecar, per fixture and per parse path). Passes 2–4 (after `037dee75`, after the late-audit fixes, on the final diff): `clean`, 0 findings, `verdict_quality: APPROVED`, rejected-payload sidecar empty. Note for the record: the dissenter runs unenforced on this host (codex-headless), so its own envelope shows `parse_path: normalized` — exactly what this sprint measured.

**Independent panel**: two trios of read-only reviewer subagents were dispatched (adapters / shell / evidence lenses). Both died on the account's session cap or ran past 45 minutes without delivering; they were stopped. Their absence is recorded here rather than papered over — the review below is the lead's own reading plus the dissent, not a panel.

**Verdict:** APPROVED

---

## Reviewer's concern notes — answered

| # | Concern (from `review-concerns.md`) | Finding |
|---|---|---|
| 1 | telemetry truth on a chain walk | `cheval.py` records `schema_enforced` from the FINAL hop's result metadata and emits it only when a schema was requested; a non-capable fallback answers `false`, the hash still travels (a schema was requested). Absent-vs-false is preserved (`test_cheval_json_schema_flag.py` envelope true/false/absent). |
| 2 | headless retry | requires `returncode != 0` AND the CLI's own "not a valid JSON Schema" text; the CLI validates the schema before dispatch, so the rejected attempt spends no model tokens; other failures are not retried (`test_claude_headless_json_schema.py`). |
| 3 | `_read_output_schema` | regular-file check added (`fb7bf705`): a FIFO/directory is `INVALID_INPUT`; messages carry the path only. |
| 4 | OpenAI strict mode and the `anyOf [type, null]` nullable form | body-capture pinned; the authored subset is closed objects, all-required, enums, `anyOf` nullables — OpenAI documents `anyOf` support under strict mode but its published examples use type arrays; the live check of the isolated hunk is an operator step (no OpenAI HTTP credential here either). Observation, not a defect: the hunk is droppable by design. |
| 5 | enforced branch with valid-but-not-object JSON | `.findings // empty` routes to `malformed_response`, never `clean` (`neg-bare-array` fixture on both paths). |
| 6 | repair loop unconditional | one round-trip per rejected finding on unenforced voices, failure stays fail-safe (rejected + sidecar); cost is bounded by the number of rejected findings; retirement keyed to the measured ratio (follow-up bead). |
| 7 | `WIRE_*` under `SCRIPT_DIR` | production entry points exec the orchestrator; the bats harness sets `SCRIPT_DIR` explicitly; CM-5 pins that the three files exist. |
| 8 | ledger-lib guarded update | `select(type == "object")` in the `|=` path is a real update (verified with jq on a mixed fixture); `exists` and the update use the same guard. |
| 9 | `tool_choice required` callers | none in cheval, the scripts or Bridgebuilder; no config surface sets it. |
| 10 | W3 forbids `format` although the SDD text allowed string `format` | none of the five schemas uses it; forbidding is the stricter, provider-safe choice — SDD §2.3 wording should be brought in line (LOW, doc). |
| 11 | per-test ledger dirs in the fixed suites | `BATS_TEST_TMPDIR` is per test by bats semantics; DS-1 flags any future indirect spawner. |
| 12 | `awk` capture of `call_model` in the harness | the first column-0 `}` after `call_model()` is the function's own end (223 lines, both `--json-schema` mentions inside). |

## Critical Issues (Must Fix Before Approval)

None.

## Non-Critical Improvements (Recommended)

- **LOW** — SDD §2.3 says string `format` is allowed in the wire subset; the lint forbids it (nothing uses it). Align the SDD sentence (or relax W3 the day a schema needs `format`).
- **LOW** — the OpenAI strict-mode acceptance of the `anyOf [type, null]` nullable form is asserted by body tests only; if the operator ever enables an OpenAI HTTP dissenter, run one call with `dissent-review.wire.json` before relying on it (the hunk is isolated and droppable).
- Follow-up beads (not Sprint 2 changes): codex/gemini headless `--output-schema` forwarding; stamping mock dispatches in the MODELINV envelope so the hygiene scanner can see them; repair-loop retirement keyed to the ratio.

## Previous Feedback Status

No previous `engineer-feedback.md` for this sprint. The Sprint 1 audit's late slice-C findings that landed in this range are closed (see the report's "Late Sprint 1 audit findings" table and the Sprint 1 audit addendum).

## Incomplete Tasks

None. Tasks 2.1–2.6 complete; the live Anthropic-HTTP leg of the schema shape (`output_config.format`) remains the operator's `live-floor-check.yml` dispatch, which now sends the real `dissent-review.wire.json`.

## Acceptance Criteria Check

| Criterion (sprint.md) | Status | Evidence |
|---|---|---|
| AC-7.1 … AC-7.5 as written in the PRD | Pass | `anthropic_adapter.py:253/644/649`, `types.py:31`, `test_anthropic_output_schema.py`, `test_tool_choice_no_forced_modes.py`; corpus `tests/fixtures/structured-outputs/*` through FR7-10 and CQ-E5; `check-no-swallowed-jq.sh` OK; `repair_loop` grep → 0; `cheval.py:223/2204/2319/2429/2611`, `modelinv.py:502`, `model-adapter.sh:304/433/556`, `claude_headless_adapter.py:93/147/249/369`; `wire-schemas-api-safe.bats` W1–W5; `openai_adapter.py:67/163/435` |
| `check-no-swallowed-jq.sh` green; quorum bats green (extended) | Pass | OK; `flatline-content-qualified-quorum.bats` 11/11 |
| MODELINV rows from one Flatline run and one dissent show `schema_enforced: true` on `claude-headless`; ratio recorded | Pass | report §Measurement: claude-headless 3/3 true, codex-headless 2/2 false; archive `.run/archive/model-invoke-20260918T231348Z.jsonl` |

## Documentation Verification

CHANGELOG `[Unreleased]` carries the Sprint 2 Added/Fixed entries; `multi-model-reference.md` documents `--json-schema`, the enforcement rule and the ratio one-liner; the KF-004 row records the mitigation and the measured ratio; NOTES Decision Log records the enum-parity, `$schema`, `stop_reason`, repair-loop, measurement, isolation and ledger-lib decisions plus the late slice-C input. One SDD wording mismatch noted above (LOW).

## Next Steps

1. `/audit-sprint sprint-2`.
2. On approval: COMPLETED marker, ledger 236, beads, Sprint 3 (arm-A baseline first).

## Addendum — the independent panel delivered late (2026-09-21)

The read-only reviewer trios recorded above as "died on the cap" delivered their reports on
2026-09-19 (after this file was written and the sprint closed). Every finding was re-verified by
the lead and closed in Sprint 3 as late Sprint 2 input; none is open at the time of this addendum.

| Lens | Sev | Finding | Disposition |
|---|---|---|---|
| shell | MEDIUM | loose trailer detection case-sensitive: a lowercase marker fell through to the legacy prose heuristic in golden-path and read as legacy in verdict-derive | fixed `a1337ed4` (`grep -i` detection; canon unchanged) + 3 bats |
| shell | MEDIUM | `ledger-lib.sh` `get_ledger_status` walked `.sprints \| last` unguarded (aborted on a /bug active cycle) | fixed `a1337ed4` + bats |
| shell | MEDIUM | repair loop unbounded on the unenforced branch (one live call per rejected finding) | fixed `a1337ed4`: 5 per run, `repair_budget_exhausted` in metadata + bats |
| shell | LOW ×4 | enforced parse accepted a multi-object stream; missing wire schema silently unenforced; repair workdir outside the trapped workdir; canon whitespace tightening unpinned | all fixed/pinned `a1337ed4` |
| adapters | MEDIUM | OpenAI truncation (`metadata.truncated`) never surfaced as `stop_reason: max_tokens`, so the dissent lost its "raise the budget" hint | fixed (cheval `_effective_stop_reason`) + tests |
| adapters | LOW ×5 | headless rejection matcher unanchored over stdout; `--help` probe per process (documented, follow-up); `--json-schema ""` read as no schema; `tool_choice` comment/Bedrock divergence; `_int_rate` dropped whole-number floats silently | fixed except the probe cache (follow-up bead) |
| evidence | HIGH | the measurement block (report + KF-004 row) misreported codex-headless as 2/2; the archive shows 10/10 unenforced | corrected in both places from the archive |
| evidence | HIGH (prose) | AC-7.3 grep claim "0 hits" while one comment still matched | comment reworded; RL-2 now runs the AC grep verbatim `a1337ed4` |
| evidence | MEDIUM ×3 | Flatline qualification ignored `stop_reason`; Anthropic body tests used a synthetic entry, not the AC-7.1 ids; per-hop schema forwarding asserted on hop 0 only | `enforced_truncated` + CQ-E6 (`a1337ed4`); live-catalog body test; two-hop test |
| evidence | LOW ×4 | permuted line labels; enforced-valid fixtures never validated against the wire schemas; archive seal breaks the recorded one-liner; "fail loudly" stub could not fail | relabelled; `test_structured_outputs_fixtures_wire_valid.py`; runbook + report note; canary in the stub |

Counts at verdict time are unchanged: the two LOW residuals noted above (SDD §2.3 wording; OpenAI strict `anyOf` live check) remain the only open items.

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":2},"sprint_id":"sprint-2","ts":"2026-09-21T01:20:00Z"} -->
