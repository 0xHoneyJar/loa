# Sprint 253 (cycle-128 Sprint 2): implementation report

**Sprint:** sprint-2 (global 253), epic bd-nmej. **Branch:** `feature/cycle-128-decision-surfaces`. **Lead:** Claude Fable 5.1; implementers D (chart) and E (lints and spikes) on Opus 5.5 in linked worktrees; patches applied by the lead with `git apply --3way --index`. Part reports: `reviewer-d.md`, `reviewer-e.md`.

## Executive Summary

Sprint 2 adds the decision map and the prototype discipline on top of the Sprint 1 ledger. `/chart` and the `charting-decisions` skill chart a multi-cycle effort as a `map` epic of `question` beads with a tracked four-section map doc, work one ticket per session, hand off to `/plan-and-analyze` as priority-1 context and close; every write step is a `chart-ticket.sh` subcommand that is idempotent by ledger `source` and bead `external_ref`, and `chart-guard.sh` refuses the whole command unless the context is interactive. Decision tickets cannot reach the build path: the bead helpers refuse them, work selection drops them, and the sprint validator flags any that carry a `sprint:` label. The spike discipline is mechanical in ICE and the Bash fence, with a report template and validator type, and `interview.unattended_prototype` governs unattended runs. The integration checkpoint at sprint start confirmed the Sprint 1 ledger commands on the live file (73 proposed rows, validator exit 0).

## AC Verification

Every acceptance criterion of `grimoires/loa/sprint.md` § Sprint 2, verbatim.

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | A fixture one-cycle idea stops at the no-fog check without creating beads | ✓ Met | `.claude/skills/charting-decisions/SKILL.md:97` (the stop precedes every write step); `.claude/scripts/chart-ticket.sh:284` (`remaining_hint`); `tests/unit/charting-decisions.bats` (no-fog and unattended-refusal cases) |
| 2 | A fixture map creates the epic, children, labels and edges under `br --dry-run` and the map doc validates | ✓ Met | `.claude/scripts/chart-ticket.sh:159` / `:199` / `:242` with `--dry-run` (`br create --dry-run` + `would:` lines); map validation `.claude/scripts/validate-artifact.sh:1021`; `tests/unit/charting-decisions.bats` dry-run cases; `tests/unit/validate-artifact.bats` map cases |
| 3 | A `question` bead with a `sprint:` label or under a sprint epic is rejected by the lint (bats) | ✓ Met | `.claude/scripts/beads/create-sprint-task.sh:86` (type refusal) and the `map`-epic refusal; `.claude/scripts/validate-artifact.sh:298`; `tests/unit/charting-lint.bats` |
| 4 | `golden-path.sh` returns `charting` with a charting map, `discovery` without one, `discovery` after `/chart close`, and `discovery` with exit 0 when `br` is absent (bats with a `br` stub) | ✓ Met | `.claude/scripts/golden-path.sh:77` (`golden_charting_maps`, file-based) and `:105`; `tests/unit/golden-path-charting.bats` incl. the `br`-absent PATH-stub case |
| 5 | Resolving a fixture `question` bead writes a `DEC` row via `decide` with evidence, closes the bead and appends to the map doc; `/plan-and-analyze` Phase 0 with a handed-off fixture map loads the map doc and its `DEC` rows as priority-1 context (bats) | ✓ Met | `.claude/scripts/chart-ticket.sh:291` (decide → comment → close → doc line), `:351` (snapshot `grimoires/loa/context/chart-<slug>.md`); `.claude/commands/plan-and-analyze.md` priority-1 snapshot entry; `tests/unit/charting-decisions.bats` resolve/handoff cases with the `br` stub |
| 6 | `get-ready-work.sh` omits a `question` bead even when it carries a `sprint:` label or sits under a sprint epic (bats) | ✓ Met | `.claude/scripts/beads/get-ready-work.sh:3` (types enumerated; `--include-questions`); `tests/unit/charting-lint.bats` exclusion cases |
| 7 | Existing `golden-path`, `run-mode-ice` and `validate-artifact` suites stay green (backward compatibility) | ✓ Met | golden-path (incl. `tests/integration/test_golden_path.bats` 47/47 per D), run-mode-ice 136-line suite incl. the old `merge` call shape, validate-artifact 51+ cases: 462/462 across the combined 19-suite set |
| 8 | `validate-artifact --type spike` passes the template and fails on a missing verdict | ✓ Met | `.claude/scripts/validate-artifact.sh:1159`; `grimoires/loa/spikes/TEMPLATE.md` validates (exit 0, one WARN on the placeholder DEC id); `tests/unit/spike-validator.bats` (empty Verdict fails) |
| 9 | Fence corpus: `spike/x` push allowed; merging `spike/x` into another branch refused; `main` merged into `spike/x` allowed; `gh pr create --head spike/x` refused; cherry-pick from a `spike/*` ref listed under Misses (bats) | ✓ Met | `.claude/hooks/safety/block-destructive-bash.sh:819` (rule SP-1), `.claude/scripts/run-mode-ice.sh:129`; `tests/fixtures/fence-corpus/corpus.jsonl` (+22 rows), `tests/unit/block-destructive-bash.bats`, `tests/unit/run-mode-ice.bats` (push allowed, merge into another branch refused, main into spike allowed, PR refused, cherry-pick blocked) |
| 10 | The charting skill's frontmatter passes `validate-skill-capabilities.sh`; `check-prompt-budget.sh` green | ✓ Met | `.claude/skills/charting-decisions/SKILL.md:1-40` frontmatter; `validate-skill-capabilities.sh` 37/37 skills, 0 errors; `tools/check-prompt-budget.sh` exit 0, charting-decisions 9,670 B with no charged resource |
| 11 | The planning skills carry the prototype sentence (≤ 2 lines each) with budgets green | ✓ Met | `.claude/skills/discovering-requirements/SKILL.md:77`, `.claude/skills/designing-architecture/SKILL.md:205`, `.claude/skills/planning-sprints/SKILL.md:202`; budgets 15,701 / 15,407 / 16,360 B (planning-sprints freed room by moving its integration-context list to REFERENCE.md) |

## Tasks Completed

- Task 2.1 (bd-tqm6): `/chart` command, `charting-decisions` skill (9,670 B) with `resources/REFERENCE.md` and `templates/map.md`, `chart-guard.sh`, `chart-ticket.sh`, `chart-unblock-probe.sh`, the `chart-researcher` agent and its `agent-types.yaml` row, `grimoires/loa/maps/README.md`, the research-snapshot `.gitignore` negation.
- Task 2.2 (bd-kz6i): `create-sprint-task.sh` and `get-ready-work.sh` refusals, `/implement` selection line, `validate-artifact.sh --type map`, the sprint beads cross-check.
- Task 2.3 (bd-axbc): `golden-path.sh` `charting` phase and `golden_resolve_open_map`, `/plan` and `/plan-and-analyze` routing and hand-off consumption.
- Task 2.4 (bd-qwfm): `chart-frontier.sh`.
- Task 2.5 (bd-6dma): `spikes/TEMPLATE.md`, `--type spike`, ICE `is-spike`/`merge [source]`/PR refusal, fence SP-1 (+22 corpus rows), `interview.unattended_prototype`, the prototype sentence in three planning skills, REFERENCE "High-Risk Early".
- Task 2.6 (bd-01pk): lead verification below.

## Technical Highlights

- Write order per ticket is ledger row (`open`) → bead (`--external-ref` = row) → map doc; a re-run finds both and creates only what is missing. Rows carry `source: map:<slug>/<ticket>` (SDD A22), so `list --source-epic` recovers a map's decisions.
- The chart is interactive by mechanism, not prose: `chart-guard.sh` runs first and refuses on the ledger writer's context verdict (fail-closed when unreadable).
- Phase detection is file-based (`**Status**:` line), so `/plan` works where `br` is absent or locked; the doc wins over the epic when they disagree (validator WARN).
- The unblock probe runs the command in a detached worktree and fails the ticket if the main tree's porcelain status (incl. ignored, matching) changed.
- Decisions beyond the SDD are listed in `reviewer-d.md` (10) and `reviewer-e.md` (8); the lead accepts them (notably: four map Status values incl. `closed`; `br update --claim`; exactly one H1 in a map doc; the spike "Decided by" DEC id WARNs so the template passes; `safe_merge` keeps an exact source allowlist).

## Testing Summary

```
bats tests/unit/golden-path-charting.bats tests/unit/charting-decisions.bats tests/unit/chart-frontier.bats \
  tests/unit/charting-lint.bats tests/unit/spike-validator.bats tests/unit/unattended-prototype.bats \
  tests/unit/run-mode-ice.bats tests/unit/validate-artifact.bats tests/unit/skill-capabilities.bats \
  tests/unit/agents-md-gen.bats tests/unit/no-history-in-rule-text.bats tests/unit/prompt-budget.bats \
  tests/unit/dec-write-lib.bats tests/unit/user-invoked-commands.bats tests/unit/check-round-independence.bats \
  tests/unit/grimoire-index.bats tests/unit/loa-decisions-surface.bats tests/unit/implement-gate.bats tests/unit/verdict-derive.bats
# 462 tests, 462 ok
bats tests/unit/block-destructive-bash.bats           # green; the timing case "runtime within 1.5x baseline" flaked once under load and passed alone
bash tools/check-prompt-budget.sh                      # exit 0
bash .claude/scripts/agents-md-gen.sh --check          # consistent (51 commands)
bash .claude/scripts/validate-artifact.sh --type map --file .claude/skills/charting-decisions/resources/templates/map.md   # exit 0 (WARN: placeholder epic not in beads)
bash .claude/scripts/validate-artifact.sh --type spike --file grimoires/loa/spikes/TEMPLATE.md                           # exit 0 (WARN: placeholder DEC id)
bash .claude/scripts/chart-guard.sh                    # refused under the live RUNNING run state (interactive-only)
```
Background full `tests/unit` run (407 files, 40-minute cap): 3,555 ok before the cap; 11 failures, all reproduced on `main` in a throwaway worktree (model-alias pins `cheval-alias-regression.bats`, `cycle-114-opus-4-8-registry.bats`, `cost-report.bats` CR-7) or outside this cycle's files; none in the touched surface.

## Known Limitations

- `/chart` itself is skill prose over the helpers; the bats cover the helpers and the fixtures, not a live Claude session.
- `chart-researcher` runs through the Agent tool; the five-per-map cap and the 20-minute budget are enforced by `research-begin` slots and prose, not by the tool.
- The map validator's beads cross-checks run only when the validated file is inside the project (fixtures skip them by design).

## Verification Steps

1. `bash .claude/scripts/chart-guard.sh` → refused while the run state is RUNNING; interactive sessions pass.
2. `bash .claude/scripts/chart-ticket.sh epic --map demo --title "Demo" --destination "A demo" --dry-run` prints the `br create --dry-run` output and `would:` lines without writing.
3. `bash .claude/scripts/golden-path.sh` sourced: `golden_detect_plan_phase` returns `charting` with a `**Status**: charting` map doc under `grimoires/loa/maps/`.
4. `git merge spike/x` from another branch is blocked by the fence; `git push origin spike/x` is not.

## Decisions taken beyond the SDD (lead)

- Accepted D1–D10 and E1–E8 from the part reports; recorded for the ledger seed of this sprint's rows at cycle close (the lead writes them in the main checkout).
