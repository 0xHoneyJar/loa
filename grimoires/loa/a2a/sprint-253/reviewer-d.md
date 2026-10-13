# Sprint 253 (cycle-128 Sprint 2), implementer D: `/chart`

Worktree `/home/merlin/Documents/thj/code/loa-wt-s2a` (branch `wt/s2a`, base `16f38539`), uncommitted.
Patch: `/home/merlin/.cache/loa/cycle-128/s2-d.patch` (24 files, +2116 / -16; `git apply --check` clean against `16f38539`).

## Executive Summary

Tasks 2.1, 2.3 and 2.4 are done. The `/chart` command and the `charting-decisions` skill (9,670 B, no resource charged) chart a map and work one ticket per session. They hand a map off to `/plan-and-analyze` and close it. Every write step goes through one new helper, `.claude/scripts/chart-ticket.sh`, so the write order (ledger row, then bead, then map doc), idempotency, the five-dispatch research cap, the research scope check and the unattended-close rule are mechanical and bats-tested with a `br` stub and a fixture ledger. `chart-guard.sh` refuses unattended or `br`-less runs. `chart-frontier.sh` computes the frontier. `chart-unblock-probe.sh` runs probes in a throwaway worktree. `golden-path.sh` gains the file-based `charting` phase and a multi-map helper, and `/plan` and `/plan-and-analyze` gain the routing and hand-off steps. New suites: 55 tests, all green. Every regression suite I ran matches its baseline.

## AC Verification (Sprint 2, verbatim from sprint.md)

| # | Acceptance criterion | Status | Evidence |
|---|---|---|---|
| 1 | A fixture one-cycle idea stops at the no-fog check without creating beads | ⚠ Partial | The stop and its exact message come before any write step: `.claude/skills/charting-decisions/SKILL.md:96-98`, pinned by `tests/unit/charting-decisions.bats:109` (CD-5). The stop is model behaviour; no script runs before `CT epic`, so "no beads" holds by construction but is not executed in bats. A headless fixture belongs in Task 2.6. |
| 2 | A fixture map creates the epic, children, labels and edges under `br --dry-run` and the map doc validates | ⚠ Partial | Dry run: `chart-ticket.sh` `--dry-run` runs `br create --dry-run` and prints the ledger and edge writes as `would:` lines with beads, ledger and doc untouched (`tests/unit/charting-decisions.bats:156` CD-11). Real walk with the stub: epic, three `question` children with one `decision:` label each, open rows, edges, `deps:none` (CD-12, `:177`). Map-doc validation was run once by hand against E's uncommitted `--type map` from wt-s2b. A doc written by `chart-ticket.sh` passed fresh, after a resolve and after a close, and the template passes too (now with example slug and epic values). The beads cross-check was skipped because `br` was off PATH. No bats calls the validator yet, so the lead should add that call to the Task 2.6 fixture after merge. |
| 3 | A `question` bead with a `sprint:` label or under a sprint epic is rejected by the lint (bats) | n/a (part E) | |
| 4 | `golden-path.sh` returns `charting` with a charting map, `discovery` without one, `discovery` after `/chart close`, and `discovery` with exit 0 when `br` is absent (bats with a `br` stub) | ✓ Met | `.claude/scripts/golden-path.sh:143-152`; `tests/unit/golden-path-charting.bats:29,34,38,57` (GPC-1, 2, 3 covering handed-off, closed and abandoned, 6 with a failing `br` stub on PATH). `/chart close` sets `closed`/`abandoned` (`chart-ticket.sh:398-436`, CD-21/CD-22). |
| 5 | Resolving a fixture `question` bead writes a `DEC` row via `decide` with evidence, closes the bead and appends to the map doc; `/plan-and-analyze` Phase 0 with a handed-off fixture map loads the map doc and its `DEC` rows as priority-1 context (bats) | ✓ Met | Resolve: `chart-ticket.sh:291-329`, CD-17 (`charting-decisions.bats:252`) asserts row `proposed`, `decided_by` null, transition evidence, bead closed with the row id, `Proposed: ...` comment, one Decisions-so-far line, idempotent re-run. Hand-off: CD-20 (`:301`) asserts the snapshot heading, every row id and the fenced research section. `/plan-and-analyze`: the `context/chart-*.md` entry at priority 1 and the Phase 0 multi-map step (`.claude/commands/plan-and-analyze.md`), pinned by CD-28 (`:431`). |
| 6 | `get-ready-work.sh` omits a `question` bead even when it carries a `sprint:` label or sits under a sprint epic (bats) | n/a (part E) | |
| 7 | Existing `golden-path`, `run-mode-ice` and `validate-artifact` suites stay green (backward compatibility) | ✓ Met (golden-path) / n/a (others, part E) | `tests/integration/test_golden_path.bats` 47/47, plus golden-path-c8 33/33, grimoire-guard 5/5, agent-ergonomics 4/4, bridge-golden-path 11/11, workflow-position-drift 5/5. `tests/unit/golden-path.bats` does not exist; the integration suite is the existing one. |
| 8 | `validate-artifact --type spike` passes the template and fails on a missing verdict | n/a (part E) | |
| 9 | Fence corpus: spike push/merge/PR/cherry-pick cases (bats) | n/a (part E) | |
| 10 | The charting skill's frontmatter passes `validate-skill-capabilities.sh`; `check-prompt-budget.sh` green | ✓ Met | `validate-skill-capabilities.sh`: 37/37 skills pass, 0 errors; CD-1/CD-2. Budget: charting-decisions 9,670 B, charged 0; all skills green. |
| 11 | The planning skills carry the prototype sentence (≤ 2 lines each) with budgets green | n/a (part E) | |

## Tasks Completed

- **Task 2.1** `/chart` and the skill.
  - `.claude/commands/chart.md`: truename, one optional `target`, `agent: charting-decisions`, `br --version` pre-flight.
  - `.claude/skills/charting-decisions/SKILL.md`: D-4.2 frontmatter with no `agent:` key and `deny_raw_shell: true`. The chart, work, prototype, research, close and rules sections.
  - `resources/REFERENCE.md`: label guide, worked example, recovery table, lifecycle, snapshot layout and scope check.
  - `resources/templates/map.md`: the D-4.8 shape.
  - `.claude/agents/chart-researcher.md` (D-4.10) with its `agent-types.yaml` row.
  - `chart-guard.sh`, `chart-unblock-probe.sh` and `chart-ticket.sh`.
  - `grimoires/loa/maps/README.md` and the `.gitignore` research negation (D-4.9).
- **Task 2.3** Golden path, hand-off and command routing.
  - `golden-path.sh` gains `golden_list_maps`, `golden_charting_maps`, `golden_open_maps` and `golden_resolve_open_map [--snapshots] [slug]` (exit 0, 1 or 3).
  - The `charting` phase maps to workflow state `initial`, gets a "Continue charting" menu line, and routes the truename to `/chart <slug>`, or `/chart` when several maps are open.
  - `plan.md` gains the `charting` row, the multi-map table, the "never starts a chart" rule and the proposed-rows pointer.
  - `plan-and-analyze.md` gains a priority-1 snapshot context entry, the Phase 0 multi-map step and the post-PRD `/chart close --consumed-by`.
  - `chart-ticket.sh handoff` writes the snapshot.
- **Task 2.4** Frontier and the claim and resolve steps.
  - `chart-frontier.sh <epic-id|map-slug> [--json] [--root DIR]` lists the frontier.
  - `chart-ticket.sh claim` and `resolve` are the claim and resolve steps.

## Technical Highlights

- **One helper, one subcommand per step.** `chart-ticket.sh` has ten subcommands: `epic`, `ticket`, `edge`, `claim`, `resolve`, `rule-out`, `handoff`, `close`, `research-begin` and `research-end`. Each re-run finds the row by `source` and the bead by `external_ref`. A failed or unreadable `br list` stops before `br create`, so a ticket cannot be duplicated.
- **Fail closed on context.** `chart-guard.sh` treats an unreadable context as unattended. `close --reason` re-checks the context itself, so the skill prose is not the only fence.
- **Frontier membership is re-filtered locally.** The helper keeps only open, unassigned `question` beads with one `decision:` label, so a `br` that ignores a filter cannot widen the set. Titles are control-stripped.
- **Research scope check.** It snapshots `git status --porcelain --untracked-files=all --ignored=matching` and fails on any new path outside `research/`. It also fails on any `.run/` or `.beads/` file newer than the dispatch marker, and on a report without the `> UNTRUSTED research output` first line.
- **Golden-path detection stays file-based.** The multi-map rule asks `dec-write-lib.sh context` when installed and falls back to `LOA_UNATTENDED=1`. It never reads run-state files, which `workflow-position-drift.bats` checks.

## Testing Summary

Bats 1.13.0 (`/home/merlin/.cache/npm/_npx/cd2c4d46c11457b7/node_modules/bats/bin/bats`; `bats` is not on this host's PATH).

```
bats tests/unit/charting-decisions.bats      # 29/29
bats tests/unit/golden-path-charting.bats    # 14/14
bats tests/unit/chart-frontier.bats          # 12/12
bats tests/integration/test_golden_path.bats # 47/47
bats tests/unit/skill-capabilities.bats      # 36/36 (SC-T-AGENT-7 expectation updated for chart-researcher)
bats tests/unit/no-history-in-rule-text.bats # 3/3
bats tests/unit/prompt-budget.bats           # 9/9
bats tests/unit/agents-md-gen.bats           # 8/8 (command count 50 -> 51)
bats tests/unit/user-invoked-commands.bats   # 13/13
bats tests/unit/dec-write-lib.bats           # 47/47
golden-path-c8 33/33, golden-path-grimoire-guard 5/5, agent-ergonomics-golden-path 4/4,
workflow-position-drift 5/5, bridge-golden-path 11/11, skill-capabilities-role-lint 11/11, zone-compliance 18/18
bash tools/check-prompt-budget.sh            # exit 0; charting-decisions 9670 B, charged 0
bash .claude/scripts/validate-skill-capabilities.sh   # 37 passed, 0 errors (3 warnings, none on this skill)
bash tools/check-no-raw-sha256sum.sh         # OK
bash .claude/scripts/agents-md-gen.sh --check  # exit 0
```

**Baseline comparison.** I ran these suites at `16f38539` in a detached worktree and again on the patched tree:

- **Same counts both times:** skill-includes, context-class, skill-inputs-manifest, skill-resource-read-correlator, skills-adapter, subagent-loader, unit documentation-coherence, user-invoked-harness, symlink-manifest-agents, early-exit, c119-c8-consumer-inventory, skill-audit and gitattributes.
- **Same failures both times:** `test_skill_metadata` fails 4 at base (it pins 25 skills). Integration `documentation-coherence` fails 17 at base. `validate-flow` fails 2 at base. The failing test names are identical before and after.

## Known Limitations

- **Two AC rows are partial.** The no-fog stop and the map validation depend on model behaviour and on E's `--type map` validator, as the AC table says.
- **Linked worktrees get `PEND-` ids.** The bead's `external_ref` keeps the `PEND-` id after `import`, and E's validator may reject a `PEND-` id in a Decisions-so-far bullet. REFERENCE.md says to chart in the main checkout.
- **The `br ready --json` shape is unverified.** I worked only from `--help` and the JSONL export, which carries `labels`. When labels are absent from `br ready` output, the frontier keeps the item.
- **Not run here:** `shellcheck` is not installed, and there is no bash 3.2 binary. The new scripts avoid `${x,,}`, associative arrays and `mapfile`. Empty-array expansions are guarded.
- **Live trees refuse `/chart` today.** The `prd.md` Status line in this branch says "autonomous", and the main checkout's run state is RUNNING. `/chart` therefore refuses in both trees by design, which is why the suites copy the scripts into a fresh repo.
- **`/loa` is unchanged.** `loa.md` displays `phase` and will show `charting` without special text. That file was outside my scope.
- **Regenerate after merge.** `AGENTS.md` and its checksum were regenerated and the README counts went from 50 to 51. Regenerate again after merging E's patch, and refresh REPO-MAP, `.checksum` and `checksums.json`. `.claude/rules/skill-invariants.md` could list `chart-researcher` in its agent table; I left the rules file alone.

## Verification Steps

```
cd /home/merlin/Documents/thj/code/loa && git apply --check /home/merlin/.cache/loa/cycle-128/s2-d.patch
bats tests/unit/charting-decisions.bats tests/unit/golden-path-charting.bats tests/unit/chart-frontier.bats \
     tests/integration/test_golden_path.bats tests/unit/skill-capabilities.bats tests/unit/agents-md-gen.bats
bash tools/check-prompt-budget.sh && bash .claude/scripts/validate-skill-capabilities.sh
# after E's validator lands:
.claude/scripts/validate-artifact.sh --type map --file <a doc written by: chart-ticket.sh epic --root <tmp> ...>
```

## Proposed CHANGELOG lines (`[Unreleased]`)

- Added `/chart`, which maps a multi-cycle effort as a `map` epic of `question` beads plus a tracked map doc in `grimoires/loa/maps/`. It plans but never builds, refuses unattended, and stops when the idea fits one cycle.
- Added `chart-ticket.sh`, the write-order-safe and idempotent steps behind `/chart`. Added `chart-frontier.sh` for the frontier, `chart-guard.sh` for the interactive-only refusal and `chart-unblock-probe.sh` for read-only `decision:unblock` probes in a throwaway worktree.
- Added the `chart-researcher` agent for `decision:research` tickets. It runs on Opus with no Bash and writes only `grimoires/loa/research/chart-*.md`, which are now tracked. Each map allows five dispatches, and a scope check runs after each one.
- `golden-path.sh` reports a `charting` planning phase from the map doc's Status line, so it works without `br`. `/plan` offers `/chart <slug>`, and with several open maps it asks, or exits 1 unattended with "more than one open map: name one".
- `/plan-and-analyze` reads a handed-off map snapshot as priority-1 context and closes the map once the PRD is written.

## Decisions taken beyond the SDD (alternatives and why)

1. **One helper owns the write steps.** I added `chart-ticket.sh` and put it in `allowed-tools` beside the SDD's raw `br` and ledger-writer grants, which I kept. The alternative was SKILL prose alone. The prose option could not prove the write order, idempotency, the research cap or the unattended-close rule in bats. Task 2.4's "claim/resolve shell steps the skill calls" covers this.
2. **The row source follows the SDD.** The row's `source` is `map:<slug>/<ticket>` (SDD A22), not the bead id from the brief. The row is written before the bead exists, and `source` is immutable. `list --source-epic <slug>` already keys on this form.
3. **Claiming follows the SDD.** The claim uses `br update --claim` (D-4.4), not `--status in_progress`. `--claim` also sets the assignee, which is how the frontier's unclaimed filter works.
4. **Status values follow the SDD.** There are four: `charting`, `handed-off`, `closed` and `abandoned` (D-4.5). Close sets `closed` for a consumed map and `abandoned` for a reason. The epic closes at `close`, not at hand-off, because D-4.5 puts the epic close in the close step. The brief said hand-off closes the epic.
5. **Open tickets live on beads, not in the doc.** The map doc gains a line only when a ticket is resolved or ruled out. The four allowed sections have no place for open tickets, and listing them would duplicate beads state. A new map doc writes `_None yet._` under Decisions so far.
6. **Frontier ordering is inlined.** The frontier helper applies `get-ready-work.sh`'s `bv --robot-triage` ranking inline instead of calling that script. After E's change the script drops `question` beads, and its limit would cap the set.
7. **Snapshots are wider than the SDD's.** The SDD names only `--ignored`. The probe and scope check use `--untracked-files=all --ignored=matching`, because a write inside an already-untracked or ignored directory is invisible to a collapsed status.
8. **`unblock` takes a required flag.** An `unblock` ticket needs `--unblocks <ticket|DEC>`, which is appended to the body as "Unblocks: X". This makes "the body names the decision it unblocks" (D-4.12) mechanical.
9. **My suites have their own names.** They are `charting-decisions.bats` and `chart-frontier.bats`, not `charting-lint.bats`, so they do not collide with E's lint suite.
10. **Existing tests were edited.** `skill-capabilities.bats` SC-T-AGENT-7 and `agents-md-gen.bats` pin the agent-type list and the command count. The SDD's own additions, a new agent and a new command, require both edits.
