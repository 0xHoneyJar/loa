# Sprint 254 (cycle-128 Sprint 3): implementer G report: FR-7 seams and red-before-green

Scope: sprint.md Task 3.3, Task 3.4 and the FR-7 part of Task 3.5 (SDD D-7.1…D-7.7, §5.2).
Worktree `loa-wt-s3b` detached at `8f7932b2`; nothing committed; patch at
`~/.cache/loa/cycle-128/patch-s3-g.patch`.

## Files changed

| File | Change |
|------|--------|
| `.claude/scripts/red-test-check.sh` | NEW. The §5.2 CLI. Two detached temp worktrees, dependency links, `--setup`, timeout, not-a-red patterns, verdicts 0/1/2/3/4/5, `--json`, the test-only-diff WARN, and one cleanup on every exit path |
| `.claude/scripts/validate-artifact.sh` | `validate_sprint_seams()` plus `SEAMS_REQUIRED_FROM=2026-10-13`, called from `validate_sprint()`. Header comment updated. `SPRINT_REQUIRED_SECTIONS` unchanged. Hunks: the header comment, one call line, one new function after `validate_sprint_deferred()` |
| `.claude/skills/planning-sprints/resources/templates/sprint-template.md` | `### Seams Under Test` table after `### Technical Tasks` in Sprint 1 and Sprint 2 |
| `.claude/skills/planning-sprints/SKILL.md` | Phase 2 asks the seams as one round. Phase 3 per-sprint list names Seams Under Test. Room made by compressing three Phase 1 gap bullets and one Phase 2 sentence (16,372 B) |
| `.claude/skills/reviewing-code/SKILL.md` | Phase 2 D-7.3 sentence. `Bash(.claude/scripts/red-test-check.sh *)` in allowed-tools plus a matching `execute_commands` entry. Room made by compressing Phase 1 steps 4 and 5, Phase -1, the Fast-Gate examples, the Automatic CHANGES_REQUIRED lead-in, the Coverage opening, the checklists pointer and the YAGNI sentence (16,378 B) |
| `.claude/skills/bug-triaging/resources/templates/micro-sprint.md` | Task 1 two-commit rule with `Red commit: <sha>`. Task 2 later-commit rule naming the script |
| `tests/unit/red-test-check.bats` | NEW, 17 cases |
| `tests/unit/sprint-seams.bats` | NEW, 10 cases |
| `tests/fixtures/sprint-seams/cycle-127-sprint.md` | NEW. A verbatim copy of the archived cycle-127 plan. The archive directory is gitignored, so CI needs a tracked copy |

I did not touch the shared hunk regions F owns. My only `validate-artifact.sh` change in the header is the sprint description lines, not the usage or type list. I did not edit `reviewing-code/resources/REFERENCE.md`, because the seam check lives in SKILL.md Phase 2 per D-7.3.

## Test results

| Check | Result |
|-------|--------|
| `red-test-check.bats` | 17/17 |
| `sprint-seams.bats` | 10/10 |
| `validate-artifact.bats`, `validate-ac-verification.bats`, `prompt-budget.bats`, `skill-capabilities.bats` with both new suites | 147/147 in one run on the final tree |
| `adversarial-review-companion.bats` CMP-148 and CMP-182, which pin the review skill's qmd step | ok |
| `no-history-in-rule-text.bats` | 3/3 |
| `tools/check-prompt-budget.sh` | exit 0. planning-sprints 16,372 B, reviewing-code 16,378 B, bug-triaging unchanged |
| `tools/check-no-raw-sha256sum.sh` | exit 0 |
| `validate-skill-capabilities.sh` | 37/37 passed. The 3 warnings predate this change: eval-running, flatline-knowledge, loa-setup |
| `bash -n` and the bash-3.2 greps (`,,`, `^^`, `mapfile`, `readarray`, `declare -A`, `local -n`) | clean |

Mutation checks:

- Disabling the cleanup trap fails 14 red-test-check cases.
- Turning dependency links off by default fails RTC-10 and RTC-13.
- Breaking the pytest pattern fails RTC-6.
- Moving `SEAMS_REQUIRED_FROM` to 2099 fails 3 seams cases.
- Counting header rows as data rows fails SEAMS-3.

A manual timeout run showed no orphaned child process and no job-control noise.

## AC Verification (FR-7 items)

- **"Sprint validator fails on a missing Seams block for a plan dated on or after 2026-10-13 and still passes the archived cycle-127 plan and undated fixtures"**: Met, with one caveat. SEAMS-1 and SEAMS-3 cover the failures, SEAMS-4 and SEAMS-5 the WARNs, SEAMS-8 this plan. The archived cycle-127 plan got exit 1 before this change, because it lacks `### Risks & Mitigation` and `### Success Metrics`. The seams rule adds only one WARN to it. SEAMS-9 pins exactly that.
- **"`red-test-check.sh` bats: red+green passes; a decoy … exits 3; a missing test file or collection error … exits 4; a timeout yields `TIMEOUT`; a fixture whose test imports an external dependency passes through the bootstrap; `git worktree list` is clean after every case; the red output is printed"**: Met. RTC-1, RTC-2, RTC-3, RTC-4, RTC-5, RTC-6, RTC-8, RTC-9 and RTC-10 cover these. `assert_clean` runs in every case and checks the worktree list, the stash list and the scratch directory. RTC-16 covers an interrupted run.
- **"`micro-sprint.md` Task 1 requires the separate red commit; `reviewing-code` names the script"**: Met. RTC-17 pins both.

## Lead attention

1. **The cycle-127 plan cannot fully pass.** It fails on two required sections that predate this rule. Making it pass would mean changing `SPRINT_REQUIRED_SECTIONS` or editing the archive, and both are out of my scope. The E2E table should state the criterion as "the rule adds no violation", as SEAMS-9 does.
2. **The SDD's separate BSD suite is folded in.** SDD §7 names `red-test-check-bsd.bats`. Its bash-watcher case is RTC-9 in `red-test-check.bats`, which uses a PATH shim without `timeout` or `gtimeout`. I made no separate file.
3. **Release surfaces for the new script are yours.** That covers REPO-MAP, `.checksum` and `checksums.json` for `red-test-check.sh`, plus CHANGELOG and AGENTS.md.
4. **One security cue was dropped from the review skill.** The qmd step lost its "(paths only)" note for budget. The `--query "<changed file paths>"` placeholder still carries the meaning, and CMP-148 still passes. Restoring the note needs 13 bytes, and only 6 bytes of headroom remain.

## Assumptions

- [ASSUMPTION fact] Only `**Date:**` is used as a plan header date. Of the archived plans checked, four use it, five have no date line, and one (cycle-113) has `**Authoring date**`, which is before the cutoff anyway. No plan uses `**Created:**` or `**Updated:**`.
- [ASSUMPTION decision] The header date is the first `**Date:**` line before the first H2. A date line further down does not gate the plan.
- [ASSUMPTION decision] A sprint block runs from its `## Sprint N` heading to the next H2 of any kind. Headings inside fenced code are ignored.
- [ASSUMPTION decision] A Seams block passes only with at least one table row below its separator line. A heading with only the header row counts as missing.
- [ASSUMPTION decision] An earlier or undated plan WARNs once, and only when at least one sprint block lacks the block.
- [ASSUMPTION decision] `--setup` is split on whitespace into an argv and never passed to `bash -c`. This keeps the no-`bash -c` rule. Anything more complex should point `--setup` at a script.
- [ASSUMPTION decision] A `--setup` failure or timeout exits 2. TIMEOUT (exit 5) is kept for test runs.
- [ASSUMPTION decision] Verdict precedence judges the red side first (timeout, then DECOY, then NOT_A_RED), then the green side (timeout, then GREEN_FAILS).
- [ASSUMPTION decision] Both runs always happen, so `--json` reports both exits.
- [ASSUMPTION decision] A red exit of 126 or 127 is NOT_A_RED alongside the D-7.6 patterns. The bats patterns also cover the gather failure (`not ok N bats-gather-tests`), the missing-file message and dash's `: not found`.
- [ASSUMPTION decision] With `timeout` or `gtimeout`, exit 124 means a timeout. So does exit 137 once the limit has elapsed. A test that itself exits 124 reads as a timeout, and the script header says so. The bash watcher uses a flag file instead and is exact.
- [ASSUMPTION decision] Each run gets its own process group through `set -m`, so a timeout or an interrupt stops the whole tree it spawned. Dependency symlinks are removed before `git worktree remove --force`.
- [ASSUMPTION decision] A path counts as a test path for the WARN if it is under `test/`, `tests/`, `spec/`, `__tests__/`, `testdata/` or `fixtures/`. So does a basename matching `test_*`, `*_test.*`, `*.test.*`, `*.spec.*`, `*_spec.*` or `*.bats`, and the `--test-file` itself.
- [ASSUMPTION decision] `--test-file` must be relative to the repository root. `--red` and `--green` values starting with `-` are rejected, so a value can never be read as an option.
- [ASSUMPTION decision] Exit-2 errors print to stderr only. `--json` emits its object for verdicts 0, 1, 3, 4 and 5, with exits set to null when a run did not happen.
- [ASSUMPTION decision] `reviewing-code` gains the allowed-tools and `execute_commands` grant for the script, so the Phase 2 instruction can run without a permission prompt.
