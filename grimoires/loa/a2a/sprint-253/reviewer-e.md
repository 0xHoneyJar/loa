# Sprint 253 (cycle-128 Sprint 2), implementer E: lints and spikes (Tasks 2.2, 2.5)

**Worktree:** `/home/merlin/Documents/thj/code/loa-wt-s2b` (branch `wt/s2b`, base `16f38539`), changes staged, not committed
**Patch:** `/home/merlin/.cache/loa/cycle-128/s2-e.patch` (`git diff --cached --binary`, 19 files, +1673/-31)
**Date:** 2026-10-13

## Executive Summary

Task 2.2 and Task 2.5 are implemented with tests, and every suite I touched is green.

- Decision tickets cannot enter the build path. `create-sprint-task.sh` refuses type `question` and a `map` epic before any bead exists. `get-ready-work.sh` drops `question` beads whatever their labels and keeps every other type. `/implement` and the implementing-tasks skill now select work through it. The sprint validator flags a `question` bead with a `sprint:` label or under a sprint epic.
- `validate-artifact.sh` gains `--type map` (D-4.8) and `--type spike` (D-5.5), with shared plain-prose (D-3.17) and PII helpers.
- The spike discipline is mechanical in run mode and in the fence. ICE adds `is-spike`, a `spike/*`-aware `merge [source]` and a spike PR refusal. The fence adds rule SP-1 and the D-5.9 spike-delete predicate.
- `interview.unattended_prototype: defer|halt` is documented in the config example, defaulting to `defer`. The D-5.1 sentence is in all three planning skills, and "High-Risk Early" now points at prototype tickets.
- New tests fail against HEAD and pass on the patch. On HEAD, 38 of the 44 new tests fail. The 6 that pass are controls and keep-the-block negatives. The HEAD hook blocks 61 of the 72 dangerous corpus rows. The patched hook blocks 72 of 72.

## AC Verification

Sprint 2 acceptance criteria, quoted from `grimoires/loa/sprint.md`:

- "A fixture one-cycle idea stops at the no-fog check without creating beads": n/a (part D).
- "A fixture map creates the epic, children, labels and edges under `br --dry-run` and the map doc validates": ⚠ Partial. The validation half is mine. `validate-artifact.sh --type map` is at `.claude/scripts/validate-artifact.sh:1021` (doc rules) and `:1097` (epic children: question type, exactly one of the four `decision:` labels, no `sprint:`, an `external_ref` that is a ledger id). Tests are at `tests/unit/validate-artifact.bats` (map group, 9 tests) and `tests/unit/charting-lint.bats` (tests 19-22). The `br --dry-run` chart fixture is part D.
- "A `question` bead with a `sprint:` label or under a sprint epic is rejected by the lint (bats)": ✓ Met.
  - Creation-time refusal: `.claude/scripts/beads/create-sprint-task.sh:102` (type `question`, before any br call) and `:126` (a `map` epic, before `br create`).
  - Sprint cross-check: `.claude/scripts/validate-artifact.sh:979` `validate_sprint_beads`, called at `:298`.
  - Tests: `tests/unit/charting-lint.bats` 1-5 and 14-18.
- "`golden-path.sh` returns `charting` ... (bats with a `br` stub)": n/a (part D).
- "Resolving a fixture `question` bead writes a `DEC` row ...; `/plan-and-analyze` Phase 0 ...": n/a (part D).
- "`get-ready-work.sh` omits a `question` bead even when it carries a `sprint:` label or sits under a sprint epic (bats)": ✓ Met. The filter is at `.claude/scripts/beads/get-ready-work.sh:69-74`. Tests are `tests/unit/charting-lint.bats` 7-12, using a stub that returns task, bug, feature, chore, docs and two question rows, one with `sprint:3` and one under epic `bd-sp`.
- "Existing `golden-path`, `run-mode-ice` and `validate-artifact` suites stay green (backward compatibility)": ⚠ Partial.
  - `run-mode-ice.bats` passes 50/50, including the original `safe_merge: ALWAYS blocked` call shape.
  - `validate-artifact.bats` passes 60/60.
  - `validate-artifact-bsd.bats` passes 3/3.
  - I did not touch or run golden-path. It is part D's file.
- "`validate-artifact --type spike` passes the template and fails on a missing verdict": ✓ Met. `validate_spike` is at `.claude/scripts/validate-artifact.sh:1159` and the template is `grimoires/loa/spikes/TEMPLATE.md`. Tests are `tests/unit/spike-validator.bats` 1-8. Test 3 empties the Verdict in both the template and a filled report.
- "Fence corpus: `spike/x` push allowed; merging `spike/x` into another branch refused; `main` merged into `spike/x` allowed; `gh pr create --head spike/x` refused; cherry-pick from a `spike/*` ref listed under Misses (bats)": ✓ Met, with one interpretation.
  - Corpus rows live in `tests/fixtures/fence-corpus/corpus.jsonl:115-136` (B50 to B59 allow, D61 to D72 block).
  - ICE cases live in `tests/unit/run-mode-ice.bats:347-450`.
  - The interpretation concerns cherry-pick. The SDD (D-5.4, §7) has the fence block it, so corpus rows D64 and D71 do. "Listed under Misses" is read as a Miss of the ICE seam: ICE has no cherry-pick operation. That is pinned by the last test in `tests/unit/run-mode-ice.bats` and noted in the D64 `why` field.
- "The charting skill's frontmatter passes `validate-skill-capabilities.sh`; `check-prompt-budget.sh` green": ⚠ Partial. `check-prompt-budget.sh` is green on this tree and `skill-capabilities.bats` passes 36/36. The charting skill itself is part D.
- "The planning skills carry the prototype sentence (≤ 2 lines each) with budgets green": ✓ Met. The sentence is at `.claude/skills/discovering-requirements/SKILL.md:77`, `.claude/skills/designing-architecture/SKILL.md:205` and `.claude/skills/planning-sprints/SKILL.md:202`, one line each. Test: `tests/unit/unattended-prototype.bats` 4. Byte counts are under Testing Summary.

Task 2.5 deliverable items outside the AC list:
- `interview.unattended_prototype` is at `.loa.config.yaml.example:142-158` and tested by `tests/unit/unattended-prototype.bats` 1-3.
- "High-Risk Early" is at `.claude/skills/planning-sprints/resources/REFERENCE.md:100-104` and tested by test 5 in the same file.

## Tasks Completed

**Task 2.2: lints (D-4.7, D-4.8)**
- `create-sprint-task.sh`:
  - Refuses `question` case-insensitively, before `cd` or any `br` call.
  - Reads the epic's labels from the `br show --json` reply it already fetched. It handles the one-element array and both label shapes, strings and `{name}`.
  - Refuses a `map` epic before `br create`.
  - Fails closed with repair text when the reply cannot be parsed.
- `get-ready-work.sh`:
  - Drops `question` beads with an exclusion filter, so every other type passes.
  - `--include-questions` keeps them.
  - A non-array reply reads as empty.
  - The limit applies after the filter.
- `implementing-tasks/SKILL.md:213` and `commands/implement.md:196` now name `.claude/scripts/beads/get-ready-work.sh` instead of bare `br ready`.
- `validate-artifact.sh --type map`:
  - Headers: Slug, Status (`charting|handed-off|closed|abandoned`, per D-4.5) and Epic.
  - Exactly one H1.
  - The four H2s in order, then an optional final `## Closed`. Any other H2 fails as "carries no execution instructions". Out-of-order, repeated and missing sections are named.
  - Destination must be non-empty.
  - Every bullet under Decisions so far must cite a DEC id.
  - D-3.17 rules: no URL, no blockquote over two lines. A `pii-filter.sh` scan runs too.
  - With `br`: the epic-children checks and the Status/epic WARN with repair text. The doc wins for phase detection.
  - Without `br`: one WARN.
- `validate-artifact.sh --type sprint` cross-check: `br list --type question --limit 0 --json` plus `br list --type epic --all --limit 0 --json`. It flags a `sprint:` label, or a sprint epic as parent through a parent-child edge or an `epic:` label. Without `br` it prints one info line.

**Task 2.5: spikes (D-5.1 to D-5.9)**
- D-5.5: `grimoires/loa/spikes/TEMPLATE.md` follows §4.4, with a comment on the working-branch rule. `--type spike` checks:
  - The five H2s are present and non-empty.
  - Pointer names a `spike/` branch or a path.
  - Decided by names operator or agent. A missing DEC id only WARNs, so the template can pass.
  - A Branch header must be `spike/`. A multi-line Verdict WARNs.
  - D-3.17 rules and the PII scan.
  - Validating a report on a `spike/*` checkout WARNs (D-5.6 working-branch rule).
- D-5.3 ICE:
  - New: `SPIKE_PATTERN="spike/*"`, `SPIKE_MERGE_SOURCES` (main, master, origin/main, origin/master), `is_spike_branch` and the `is-spike` subcommand.
  - `safe_merge [source]`: with no source the behaviour is unchanged. A spike source is refused with "ICE: spike branches are never merged into another branch". On a spike branch with an allowlisted source it runs `git merge --no-edit`. Anything else stays blocked.
  - `safe_pr_create` refuses a spike head with "ICE: spike branches never get a PR" and logs it with `log_ice_block`.
  - `safe_push` is unchanged.
  - Callers enumerated: the `merge` dispatch and `run-mode-ice.bats`. No skill calls `merge`.
- D-5.4 fence rule SP-1 is in `block-destructive-bash.sh`, after the git-family block. Through `emit_block` it blocks:
  - `merge|rebase|pull|cherry-pick` naming a spike ref, including `git -C dir` and `-c` global options and `main..spike/x` ranges.
  - `checkout <spike> -- <path>`.
  - `checkout <spike> <path>` without `--`.
  - `restore --source[= ]` and `-s <spike>`.
  - `gh pr create --head|-H [owner:]spike/`.
  - `gh pr create` with no head while the checkout is on `spike/*`.
  - Pushes, switches, `checkout -b`, `merge-base`, `log main..spike/x`, and `git merge main` or `git rebase main` all pass.
  - The `git pull origin spike/x` edge and the Misses are in the rule comment.
- D-5.9: `_fr11_spike_decided` lets `git branch -D spike/<slug>` pass only when all of these hold:
  - The ledger has a row with status `decided`.
  - Its last transition to `decided` is by `operator:*`.
  - Its `source`, with any `#anchor` removed, is `grimoires/loa/spikes/<slug>.md`.
  - yq v4 is present, the ledger is not a symlink, and the slug matches the grammar.
  - Any failure keeps the block. Every other name in the command must still be merged.
- D-5.8: `interview.unattended_prototype: defer` is documented with both values, the PRD `**Deferred:**` line form and the halt message.
- D-5.1: the sentence is in the three planning skills. In planning-sprints, the integration-context bullet list moved to `resources/REFERENCE.md` §Integration Context behind a guarded pointer to make room.
- D-5.7: "High-Risk Early" in planning-sprints REFERENCE.md is replaced.

## Technical Highlights

- Beads cross-checks run only against the project's own tracker. They need `br` on PATH, `.beads/` at PROJECT_ROOT, and the validated file inside the project by canonical path. This keeps the existing `/tmp`-fixture suites from querying a real database, and makes the checks testable with a PATH stub and a temp PROJECT_ROOT.
- `br list --json` returns `{issues: [...]}` in br 0.2.6, according to `br schema commands`. Several existing scripts assume a bare array. My helper `_br_json_array` normalises both forms. Ready rows carry no labels in that schema, which is why the build-path filter keys on `issue_type` only.
- SP-1 matches on the carrier-scrubbed line model. A commit message, echo or PR title that mentions `spike/x` stays allowed (corpus rows B54 and B58).
- The map H2 rule is an allowlist (A17), so a renamed section cannot dodge it.

## Testing Summary

Commands, run in the worktree:

```
bats tests/unit/validate-artifact.bats              60/60
bats tests/unit/charting-lint.bats                  22/22  (new)
bats tests/unit/spike-validator.bats                16/16  (new)
bats tests/unit/unattended-prototype.bats            6/6   (new)
bats tests/unit/run-mode-ice.bats                   50/50  (12 new)
bats tests/unit/block-destructive-bash.bats        281/281 (corpus gates incl. runtime)
bats tests/unit/block-destructive-bash-limitations.bats 6/6
bats tests/unit/validate-artifact-bsd.bats           3/3
bats tests/unit/skill-capabilities.bats             36/36
bats tests/unit/no-history-in-rule-text.bats         3/3
bats tests/unit/prompt-budget.bats                   9/9
bats tests/unit/bash32-portability.bats              5/5, 1 skip (no bash 3.2 on host)
bash tests/fixtures/fence-corpus/run-corpus.sh       benign 59/59 dangerous 72/72 residual 0/5
bash tools/check-prompt-budget.sh                    exit 0
bash tools/check-no-raw-sha256sum.sh                 OK
bash tools/check-no-swallowed-jq.sh                  OK
bash .claude/scripts/validate-artifact.sh --type spike --file grimoires/loa/spikes/TEMPLATE.md
                                                     exit 0 (one WARN: the template cites no real DEC row)
```

Total: 497 tests run, 0 failures.

Red-first check: the HEAD tree came from `git archive` with the new tests copied in.

| Suite | Fail at HEAD | Pass at HEAD |
|---|---|---|
| charting-lint | 20 of 22 | 2 controls |
| spike-validator | 13 of 16 | 3 keep-the-block cases |
| unattended-prototype | 5 of 6 | 1, the validator form it cross-checks |

SKILL.md byte counts (limit 16,384):

| Skill | Before | After |
|---|---|---|
| discovering-requirements | 15,439 | 15,701 |
| designing-architecture | 15,146 | 15,407 |
| planning-sprints | 16,347 | 16,360 (≈ 250 B moved to REFERENCE.md) |
| implementing-tasks | 16,221 | 16,274 |

## Known Limitations

- `tests/bash/beads_dependency_edges.bats` was not run. It creates throwaway `br` workspaces, and my instructions limited `br` to `--help` and PATH stubs. It exercises the changed `create-sprint-task.sh` and `get-ready-work.sh` against real `br show --json` output. The lead should run it once.
- planning-sprints has 24 B of budget left.
- Other `br ready` mentions remain as selection advice:
  - `.claude/protocols/beads-integration.md:86,334`
  - `run-mode/resources/halt-resume.md:74`
  - `commands/ride.md`
  - They are outside the D-4.7 list and were left untouched.
- SP-1 Misses, listed in the rule comment:
  - `git show spike/x:path > f`
  - `git diff spike/x | git apply`
  - `git switch -c new spike/x`
  - `git worktree add -b new <dir> spike/x`
  - refs given as a SHA
  - `git checkout -b feat spike/x` creating a branch from a spike
- `git merge main -m "...spike/x..."` is blocked as a false positive, because merge messages are not a scrubbed carrier.
- The map validator does not check H3 and deeper headings, only the H2 allowlist and a single H1.
- I found a pre-existing bug and did not fix it. `run-mode/resources/halt-resume.md:36` and `sprint-plan-mode.md:49,69` pass `--draft` as `pr-create`'s third argument, which is `base`.
- REPO-MAP, `.checksum` and `checksums.json` were not regenerated for the `.claude/` changes. That is left to the lead at integration, since part D also touches `.claude/`.

## Verification Steps

```
cd /home/merlin/Documents/thj/code/loa-wt-s2b   # or apply s2-e.patch on the integration branch
bats tests/unit/charting-lint.bats tests/unit/spike-validator.bats tests/unit/unattended-prototype.bats \
     tests/unit/validate-artifact.bats tests/unit/run-mode-ice.bats tests/unit/block-destructive-bash.bats
bash tests/fixtures/fence-corpus/run-corpus.sh
bash tools/check-prompt-budget.sh
bash .claude/scripts/validate-artifact.sh --type spike --file grimoires/loa/spikes/TEMPLATE.md
bats tests/bash/beads_dependency_edges.bats      # lead: real br, throwaway workspaces
```

## Proposed CHANGELOG lines ([Unreleased])

- Decision tickets stay off the build path. `create-sprint-task.sh` refuses `question` beads and `map` epics. `get-ready-work.sh` drops `question` beads (`--include-questions` keeps them). `/implement` selects work through it. `validate-artifact.sh --type sprint` flags a `question` bead with a `sprint:` label or under a sprint epic.
- `validate-artifact.sh --type map` checks `/chart` map docs. It requires the four sections in order plus an optional `## Closed`, refuses any other H2, requires a DEC id on every decision bullet, and checks plain prose and PII. With `br` it also checks the epic's children.
- Added `grimoires/loa/spikes/TEMPLATE.md` and `validate-artifact.sh --type spike` for prototype reports.
- ICE (`run-mode-ice.sh`) adds `is-spike` and `merge [source]`. A spike branch may take `main`/`master` in, a spike is never merged into another branch, and a spike head never gets a PR.
- Fence rule SP-1 (`block-destructive-bash.sh`) blocks merge, rebase, pull and cherry-pick of a `spike/` ref, path copies out of a spike, and PRs from a spike. Pushing and switching stay allowed. `git branch -D spike/<slug>` passes once the spike's verdict row is decided by the operator.
- `interview.unattended_prototype: defer | halt` (default `defer`). The three planning skills turn "I need to see it" questions into `decision:prototype` tickets. Sprint sequencing points at prototype tickets instead of spike tasks.

## Decisions taken beyond the SDD

| Decision | Alternatives | Why |
|---|---|---|
| Beads cross-checks run only when the validated file is inside PROJECT_ROOT | always query `br` when present; an env opt-out | a `/tmp` fixture has no relation to the project's beads, and an env opt-out is a bypass; this keeps every existing suite off the real database |
| Map Status accepts four values, including `closed` | the three in the brief | D-4.5 and D-4.6 define `closed` as the consumed state |
| A map doc must have exactly one H1 | H1 unchecked | a second H1 would dodge the H2 allowlist |
| A missing DEC id under spike "Decided by" WARNs and does not fail | fail | the shipped template must pass (D-5.5), and the row may be written after the report |
| SP-1 also blocks `git checkout <spike> <path>` without `--`, `git -C` and `-c` forms, and commit ranges, and checks the current branch for a headless `gh pr create` | only the four D-5.4 shapes | the same copy, through the most common alternate spellings; each is positive and offline |
| `safe_merge` on a spike runs `git merge --no-edit <source>` for an exact allowlist (main, master, origin/main, origin/master) | report OK without merging; accept any default-branch-looking ref | the other ICE wrappers perform their operation; an exact list leaves no flag injection |
| D-5.9 requires the last transition to `decided` to be by `operator:*`, and strips a `#anchor` from `source` | status only | a decided row is operator-confirmed by schema; the anchor form is what the writer records elsewhere |
| The planning-sprints room came from moving the integration-context list to REFERENCE.md | shortening the sentence | the D-5.1 wording stays verbatim in all three skills |
