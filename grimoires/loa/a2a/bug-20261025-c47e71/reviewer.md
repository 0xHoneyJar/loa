# sprint-bug-277 (bug 20261025-c47e71, bd-ahxmh) — implementation report

**Implementer:** Opus 5.5 subagent (worktree `../loa-wt-bug-a`, brief `~/.cache/loa/bugs/briefs/a.md`) · **Lead:** Fable 5.1 (triage, landing, manifests, this report) · **Branch:** `fix/post-ship-bugs-classifier-bb-glob` (base `caacfb6f3` = main `3e903cb83` + the decisions-confirm commit)

**Red commit:** `893a68eb3` — `test(20261025-c47e71): failing test — sprint-bug-277 (tests/unit/post-merge-classifier.bats)`
**Fix commit:** `cfdd94f9d` — `fix(classify-pr-type): housekeeping merges classify other — …` (System Zone file under the bounded marker; `checksums.json`, `REPO-MAP.md` regenerated in the same commit)

## What was built

One rule in `classify_pr_type` (`.claude/scripts/classify-pr-type.sh:52-68`), after the labels rule and before the `\bcycle-[0-9]+\b` rule: a title that is a merge from a `chore/` branch (`^Merge pull request #[0-9]+ from [^ ]+/chore/`) or carries a housekeeping prefix (`^chore\((archive|ledger|decisions)\):`) returns `other`. Header rule list gains "1a" (`:32`). Nine bats cases PCT-T28 … T36 (`tests/unit/post-merge-classifier.bats:255-317`). CHANGELOG `[Unreleased]` `### Fixed` line (bd-ahxmh).

## Red run (at `893a68eb3`)

`npx --no-install bats tests/unit/post-merge-classifier.bats` → exit 1, 1..36, 31 ok: `not ok 28` (cycle-133 archive merge, PR #1293), `not ok 29` (cycle-134 archive merge, PR #1297), `not ok 30` (squash `chore(archive): … (#1297)`), `not ok 31` (publisher's `chore(ledger): archive … after merge`), `not ok 32` (decisions-confirm merge, PR #1298). T33 (labels precedence), T34 (Sprint 276 merge → cycle), T35 (`chore: bump deps` → other) and T36 (`chore(release): v1.130.0 … (cycle-098 …)` → cycle) pass before and after: they are the "both directions" guards. Log: `~/.cache/loa/bugs/red-a.log`.

## Green run (at `cfdd94f9d`)

`post-merge-classifier.bats` 36/36, `classify-merge-pr.bats` 31/31 (KF063-T1 … T14 included), `post-merge-workflow-guards.bats` 4/4 (one invocation, 1..71 ok); `bash -n` ok; `gen-checksums.sh --check` OK (2075 entries), `repo-map-gen.sh --validate` consistent, `check-manifest-paths.sh` 0 untracked / 0 missing. Log: `~/.cache/loa/bugs/green-a.log`.

**Red-then-green:** `red-test-check.sh --red 893a68eb3 --green cfdd94f9d -- bats tests/unit/post-merge-classifier.bats` — see the lead's note in `engineer-feedback.md` (the runner must be on the caller's PATH outside the repository: `bats` from the npx cache).

## E2E (function level, live subjects verbatim)

| Subject | Before | After |
|---|---|---|
| `Merge pull request #1293 from 0xHoneyJar/chore/cycle-133-archive — cycle-133 archive` | cycle | **other** |
| `Merge pull request #1297 from 0xHoneyJar/chore/cycle-134-archive — cycle-134 archive` | cycle | **other** |
| `chore(archive): cycle-134 post-ship fixes — archive directory, ledger archived (#1297)` | cycle | **other** |
| `chore(ledger): archive cycle-134-post-ship-fixes after merge` | cycle | **other** (the wrapper's KF-063 no-PR guard already said other; the function now agrees on its own) |
| `Merge pull request #1298 from 0xHoneyJar/chore/cycle-134-decisions-confirm — …` | cycle | **other** |
| `Merge pull request #1296 from 0xHoneyJar/feature/cycle-134-post-ship-fixes — … (Sprint 276)` | cycle | cycle |
| chore-branch merge with `--labels cycle,release` | cycle | cycle |
| `chore(release): v1.130.0 — named milestone (cycle-098 + cycle-099 …) (#747)` | cycle | cycle |

## AC verification

| AC (sprint.md) | Status | Evidence |
|---|---|---|
| T1 tests fail on current code | met | red run above; `post-merge-classifier.bats:265-317` |
| T1 names describe the scenario | met | PCT-T28 … T36 titles name the subject class and bd-ahxmh |
| T1 isolated (`--title`/`--labels` only) | met | every case is `run "$CLASSIFIER" --title … [--labels …]` |
| T1 red committed alone, SHA recorded | met | `893a68eb3` (tests only) |
| T2 failing tests pass; three suites green | met | green run above |
| T2 no regressions (PCT backtest still cycle) | met | 27 pre-existing cases ok, incl. "cycle-NNN with content after" (`chore: cycle-042 release prep …` → cycle) |
| T2 root cause (rule order), no special-casing | met | `classify-pr-type.sh:65` — a shape rule, no PR numbers or cycle ids |
| T2 fix commit does not weaken the test | met | the fix commit touches no test file; `red-test-check` (lead) |
| T2 manifests regenerated in the fix commit | met | `cfdd94f9d` (checksums.json, REPO-MAP.md, REPO-MAP.md.checksum) |
| T3 CHANGELOG entry (bd-ahxmh) | met | `CHANGELOG.md:10-12` |
| T3 E2E on live subjects | met | table above |
| Bug no longer reproducible | met | triage repro steps 1–3 print `other` |

## DECISION bullets (judgment calls → decision rows)

- **Prefix form narrowed to housekeeping scopes** `chore\((archive|ledger|decisions)\):` instead of the brief's bare `^chore(\([^)]*\))?:`. Why: the bare form turned the pinned case `chore: cycle-042 release prep and final doc update` (expected cycle) red, and would reroute the named-release squash `chore(release): v1.130.0 … (cycle-098 …)` (PR #747) to the simple-release path — the R-005 / bd-m1o6 incident class. Alternatives rejected: bare prefix + flipping the pinned case (edits a contract, opens the release hole); routing every `chore(*)` scope (same hole). Cost: `chore(cycle-NNN): RESUMPTION.md …` squash merges keep classifying cycle (status quo).
- **Branch-merge clause as briefed** (`from [^ ]+/chore/`): every first-parent `chore/` merge on main is housekeeping (#1297, #1295, #1294, #1293, #1291, #1290, #1287, #1284, #1280, #1276, #436). Side effect: PR #1295 (`chore/cycle-133-post-ship`; the triage mis-named its branch `feature/…`) now classifies other — correct for its content.
- **Case-sensitive `chore`** (no `-i`): lowercase is the convention; `Chore(archive):`, `chores:`, `chore(archive!:` and `chore(archive)!:` fall through to the cycle-id rule.
- **`fix/`-branch merges unchanged** (`Merge pull request #1288 from 0xHoneyJar/fix/cycle-132-bugs` → cycle today): out of scope per the triage; a follow-up could route `from [^ ]+/fix/` merges to bugfix when no cycle label is present.
- **CHANGELOG**: a plain `### Fixed` heading directly under `[Unreleased]`, above the Sprint-276-scoped heading (shared with sprint-bug-278's line).

## Open items

- `red-test-check.sh` refuses `npx` as a runner; `bats` is only on PATH through the npx cache (`~/.cache/npm/_npx/<hash>/node_modules/.bin`). The lead ran the check with that directory prepended to PATH (it survives the scrubbed-PATH rule: absolute, outside the repository). Worth a one-line note in the harness docs.
- Not changed: `fix/` branch merges that name a cycle (see the DECISION bullet).

## Suites

`post-merge-classifier.bats` 36/36 · `classify-merge-pr.bats` 31/31 · `post-merge-workflow-guards.bats` 4/4 · `bash -n` · `gen-checksums.sh --check` · `repo-map-gen.sh --validate` · `check-manifest-paths.sh`.


## Rounds after the first landing

- Review round 1 `b1acf9a64`: stated effect corrected (the Bugfix-or-Other job also prepares a candidate; the rule changes which job runs). Audit round `4cf08e1c4`: branch clause anchored to the first segment after the owner (`[^ /]+`), PCT-T37/T38. Bridgebuilder round `ced408300`: PCT-T39/T40 pins (label precedence for the prefix form; case-sensitivity). Final head `84c328455` (shared branch). Recorded 2026-10-26T00:52:50Z.