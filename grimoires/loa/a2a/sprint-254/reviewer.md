# Sprint 254 (cycle-128 Sprint 3): implementation report

**Sprint:** sprint-3 (global 254), epic bd-9oyc. **Branch:** `feature/cycle-128-decision-surfaces`. **Lead:** Claude Fable 5.1; implementers F (FR-6 glossaries), G (FR-7 seams and red-before-green) and H (docs and the E2E report) on Opus 5.5. **Parts:** reviewer-f.md, reviewer-g.md, reviewer-h.md; E2E: e2e.md (with e2e-lead-evidence.md folded in). **Commits:** efacf754 (implementation), 3b0f8bf3 (review round r254-1 and docs).

## Executive Summary

Sprint 3 completes the decision surfaces with a shared vocabulary and two verifiable test-discipline checks, then documents the cycle and validates every PRD goal. A framework glossary (`.claude/loa/GLOSSARY.md`, 33 entries) is mounted into every project and a root `GLOSSARY.md` sets the project-glossary convention; `tools/check-glossary-terms.sh` fails CI when an identifier-shaped backticked kernel term has no entry, alias or allowlisted reason, and `validate-artifact.sh --type glossary` keeps the glossaries in the agreed shape (one-line entries, two sentences, 300 characters, capped and related aliases). Sprint plans dated from 2026-10-13 declare their `### Seams Under Test` and the validator enforces it; `red-test-check.sh` proves a `/bug` fix's test failed before the fix and passes after it in detached worktrees, with decoy, not-a-red and timeout verdicts; the micro-sprint template requires the separate red commit and the review skill cites the check. The CHANGELOG is one release note for sprints 252 to 254 with a Migration section, the references list every new surface, REPO-MAP and the checksums are regenerated, and e2e.md records G-1 to G-7 with commands, artefacts and results.

## AC Verification

Every acceptance criterion of `grimoires/loa/sprint.md` § Sprint 3, verbatim.

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | `check-glossary-terms.sh` exits 0 on the kernel and 1 when a term is removed from the glossary (bats) | ✓ Met | `tools/check-glossary-terms.sh:1` (exit contract in the header); live run: 16 kernel tokens kept, 5 aliases, 11 allowlisted, 0 missing, PASS exit 0; a copy without the run-mode `_Aliases_:` line fails on `RUNNING`, `HALTED`, `JACKED_OUT` (`CLAUDE.loa.md:104`) with exit 1; `tests/unit/glossary-terms.bats` GT-1, GT-2, GT-3 |
| 2 | `.claude/loa/GLOSSARY.md` validates; every backticked framework term in `CLAUDE.loa.md` resolves (exclusion heuristic applied; allowlist ≤ 30) | ✓ Met | `.claude/loa/GLOSSARY.md:1` validates (`validate-artifact.sh --type glossary` exit 0, no WARN; GV-1); `.claude/data/glossary-allowlist.txt:1` holds 11 of 30 entries with reasons (GT-18); every kept kernel token resolves (GT-13, `--json` ok with zero misses); the heuristic is the shape at `tools/check-glossary-terms.sh:7` |
| 3 | Sprint validator fails on a missing Seams block for a plan dated on or after 2026-10-13 and still passes the archived cycle-127 plan and undated fixtures | ✓ Met (with a stated caveat) | `.claude/scripts/validate-artifact.sh` `validate_sprint_seams` (`SEAMS_REQUIRED_FROM="2026-10-13"`); `tests/unit/sprint-seams.bats` SEAMS-1/3 (failures named per sprint), SEAMS-4/5 (older and undated plans WARN), SEAMS-8 (this plan passes), SEAMS-9 (the archived cycle-127 plan gains only a WARN from the rule). Caveat: that archived plan exits 1 on two required-section rules older than this sprint (`### Risks & Mitigation`, `### Success Metrics`), recorded in e2e.md G-6 |
| 4 | `red-test-check.sh` bats: red+green passes; a decoy passing at both commits exits 3; a missing test file or collection error at the red commit exits 4; a timeout yields `TIMEOUT`; a fixture whose test imports an external dependency passes through the bootstrap; `git worktree list` is clean after every case; the red output is printed | ✓ Met | `.claude/scripts/red-test-check.sh:1` (verdict table in the header); `tests/unit/red-test-check.bats` RTC-1 (VERIFIED, red output printed), RTC-2 (DECOY 3), RTC-3/4/5/6 (NOT_A_RED 4), RTC-8/9 (TIMEOUT 5, with and without `timeout` on PATH), RTC-10 (dependency link), `assert_clean` after every case, RTC-16 (interrupted run); the lead's throwaway run: VERIFIED exit 0, decoy exit 3, one worktree left (the main tree) |
| 5 | `micro-sprint.md` Task 1 requires the separate red commit; `reviewing-code` names the script | ✓ Met | `.claude/skills/bug-triaging/resources/templates/micro-sprint.md` Task 1 ("Committed alone … `Red commit: <sha>`") and Task 2 (the fix does not weaken the test); `.claude/skills/reviewing-code/SKILL.md` Phase 2 (`red-test-check.sh --red <Red commit from reviewer.md> -- <test command>`); RTC-17 pins both |
| 6 | CHANGELOG, README, hooks-reference, REPO-MAP updated; `repo-map` checksum consistent | ✓ Met | `CHANGELOG.md:8` (one `[Unreleased]` note for sprints 252–254 with a Migration section); `README.md` "Unreleased — decision surfaces" block; `.claude/loa/reference/hooks-reference.md` "Decision surfaces (cycle-128)" table; `.claude/loa/reference/scripts-reference.md` "Decision Surfaces (cycle-128)" rows; `grimoires/loa/REPO-MAP.md` + `.checksum` regenerated over the final code (`repo-map-gen.sh --validate` exit 0); `.claude/checksums.json` refreshed for tracked files |
| 7 | Task 3.E2E: every goal G-1…G-7 validated with documented evidence in a report table (goal, command run, artifact path, pass/fail) under `grimoires/loa/a2a/sprint-254/e2e.md`; G-3 scores a transcript other than the Sprint 1 fixture | ✓ Met | `grimoires/loa/a2a/sprint-254/e2e.md:7` (goal table, G-1…G-7 PASS with commands and artefacts); G-3 on `grimoires/loa/a2a/sprint-254/e2e-transcript-rounds.md:1` (3 rounds, 6 questions, average 2.5, PASS); G-7 live harness stream `grimoires/loa/a2a/sprint-254/harness-stream.json` (hidden command refused, control ran) |
| 8 | Existing `validate-artifact`, `reviewing-code` and CI suites stay green (backward compatibility) | ✓ Met | 741/741 across 22 suites on the final tree (`~/.cache/loa/cycle-128/s3-final-bats.log`: validate-artifact, validate-ac-verification, prompt-budget, skill-capabilities, agents-md-gen, repo-map-gen, user-invoked-commands, block-destructive-bash, run-mode-ice, the Sprint 1 and 2 suites); `tools/check-prompt-budget.sh` exit 0; `.claude/scripts/validate-skill-capabilities.sh` 37/37; `evals/fixtures/sync-fixtures.sh --check` current |
| 9 | Each goal validated with documented evidence | ✓ Met | `grimoires/loa/a2a/sprint-254/e2e.md:7` goal table: G-1…G-7 each with the validation action, the command run, the artifact path and PASS; `grimoires/loa/a2a/sprint-254/e2e-lead-evidence.md:1` (the lead's rows folded in) |
| 10 | Integration points verified (ledger → INDEX → SessionStart; map → `/plan-and-analyze` context; spike → `DEC` row) | ✓ Met | `grimoires/loa/a2a/sprint-254/e2e.md:29` "Integration points" table: ledger → INDEX → SessionStart (`## decisions (91)` section, `loa-decisions-surface.bats` 8/8, `grimoire-index.bats` 13/13); map → `/plan-and-analyze` context (`charting-decisions.bats` 52/52 incl. the hand-off snapshot and the consumed close); spike → `DEC` row (`spike-validator.bats` 16/16, the D-5.9 unlock cases in `block-destructive-bash.bats`) |
| 11 | No goal marked as "not achieved" without explicit justification | ✓ Met | `grimoires/loa/a2a/sprint-254/e2e.md:37` ("No goal is marked not achieved"); the one caveat (the archived cycle-127 plan's pre-existing failures under G-6) is justified in its row |

## Tasks Completed

- Task 3.1 (bd-hafl): sizing run (16 kernel tokens: 5 framework aliases, 11 code identifiers, 0 misses), `.claude/loa/GLOSSARY.md` (33 entries), root `GLOSSARY.md`, `validate-artifact.sh --type glossary`.
- Task 3.2 (bd-28ud): `tools/check-glossary-terms.sh`, `.claude/data/glossary-allowlist.txt`, `.github/workflows/check-glossary-terms.yml` with two controls, planning-skill sentences, `riding-codebase` read, `reviewing-code` checklist row, mount manifest lines.
- Task 3.3 (bd-twdf): `sprint-template.md` Seams block, `validate_sprint_seams` (Date-gated), `planning-sprints` seams round, `reviewing-code` Phase 2 seam check.
- Task 3.4 (bd-0b6s): `.claude/scripts/red-test-check.sh`, `micro-sprint.md` two-commit rule, `reviewing-code` grant and citation.
- Task 3.5 (bd-e9m8): `glossary-terms.bats` (31 cases after r254-1), `glossary-validator.bats` (24), `red-test-check.bats` (18), `sprint-seams.bats` (10), fixtures under `tests/fixtures/glossary/` and `tests/fixtures/sprint-seams/`.
- Task 3.6 (bd-6j3l): CHANGELOG reconciliation and Migration notes, README, hooks-reference, scripts-reference, protocols-summary, REPO-MAP and checksums, evals fixture sync, SDD §10 DEC backfill.
- Task 3.E2E (bd-0icm): e2e.md with the lead's evidence (G-3 transcript, G-7 harness stream, G-5 and G-6 runs) folded in.

## Testing Summary

741 ok, 0 failed across 22 suites on the final tree (3b0f8bf3). Static: prompt budgets 16,124 / 16,223 / 16,226 of 16,384 for the three trimmed skills; skill capabilities 37/37; AGENTS.md 51 commands; swallowed-jq and raw-sha256sum lints OK; `md-fence.awk` parses; `bash -n` on every changed script; shell-compat greps clean; `check-glossary-terms.sh` PASS live; both glossaries, the sprint plan (Seams rule plus the live question-bead cross-check), the PRD and the SDD validate.

## Verification Steps

```
bash tools/check-glossary-terms.sh --report
bash .claude/scripts/validate-artifact.sh --type glossary --file .claude/loa/GLOSSARY.md
bash .claude/scripts/validate-artifact.sh --type sprint --file grimoires/loa/sprint.md
bats tests/unit/glossary-terms.bats tests/unit/glossary-validator.bats tests/unit/red-test-check.bats tests/unit/sprint-seams.bats
bash .claude/scripts/repo-map-gen.sh --validate
bash tools/check-round-independence.sh grimoires/loa/a2a/sprint-254/e2e-transcript-rounds.md --json
```

## Known Limitations

- The glossary gate sees backticked tokens only; the kernel's prose uses of framework terms are not checked (design, SDD D-6.2; the checker's advisory WARN says so).
- The archived cycle-127 plan fails two required-section rules older than this sprint; the Seams rule adds only a WARN there.
- `.claude/checksums.json` was refreshed for tracked files only; the generator would also hash untracked local files.

## Decisions taken beyond the SDD (lead)

Seeded as proposed ledger rows DEC-0092…DEC-0122 from the implementers' `[ASSUMPTION decision]` lines (reviewer-f.md 10, reviewer-g.md 15, reviewer-h.md 6); the lead's own: the three skills were trimmed to at least 150 bytes of headroom rather than left at the edge; REPO-MAP and checksums were regenerated by the lead after the review-round patches so the generated files match the committed code.
