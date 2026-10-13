# Sprint 252 (cycle-128 Sprint 1): implementer A report, part "interview"

**Scope:** Task 1.1, Task 1.2, and the prose half of Task 1.7.
**Worktree:** `/home/merlin/Documents/thj/code/loa-wt-s1a` (branch `wt/s1a`, base `e9f175a6`), nothing committed.
**Patch:** `/home/merlin/.cache/loa/cycle-128/s1-a.patch` (12 files, +579 / -66).

## Executive Summary

`interview.pacing: rounds` is now the `thorough` default. The interview asks the whole settled frontier per turn, numbers the questions, gives each a recommendation that "yes" accepts, and ends every round with a machine-readable comment block. The rule lives in `discovering-requirements/resources/REFERENCE.md` §Question Pacing. The discovery SKILL.md points at it in one 3-line section, and `/architect` and `/sprint-plan` Phase 2 point at the same rule in one line each. `tools/check-round-independence.sh` checks a transcript's round blocks and passes on a four-round fixture. A negative fixture with a same-round dependency fails it. Its 13-case bats suite is green, and a mutation run proved the cases can fail.

The Mode Behavior, Input Style and Question Pacing tables moved out of `discovering-requirements/SKILL.md`. The file went from 16,304 B to 15,439 B with both new rules in it. That covers the bytes the later sprints add plus 400 B headroom.

The fact/decision rule and the `[ASSUMPTION fact]` / `[ASSUMPTION decision]` tag classes are in the Backpressure Protocol. Karpathy §1 and the autonomous-agent prime directive now name `dec-write-lib.sh new` as the unattended record for decisions. The run-mode completion and sprint-plan-incomplete PR bodies gain "Decisions taken on your behalf". A numbered step list renders that section from `dec-write-lib.sh list`.

All four required suites and the prompt budget gate pass. Every suite that references a touched file was run. Three integration suites fail identically at the base commit, so those failures are pre-existing.

## AC Verification

Sprint 1 acceptance criteria, quoted verbatim from `grimoires/loa/sprint.md:53-64`.

| # | Criterion (verbatim) | Status | Evidence |
|---|---|---|---|
| 1 | "`tools/check-prompt-budget.sh` green; `discovering-requirements/SKILL.md` ≤ 16,384 B" | ✓ Met | `bash tools/check-prompt-budget.sh` exits 0; `discovering-requirements` 15,439 B (`.claude/skills/discovering-requirements/SKILL.md:67-75` holds the pointer and the fact/decision rule) |
| 2 | "`.loa.config.yaml.example` documents `pacing: rounds` (frontier rule, numbered format, \"yes accepts the recommendation\", the `sequential` opt-out)" | ✓ Met | `.loa.config.yaml.example:125-140`: key scope `:125-126`, unset defaults `:127`, frontier rule `:128-130`, numbering `:131`, "yes" semantics `:132-134`, recompute and comment block `:135-136`, `sequential` opt-out `:137-138`, `pacing: rounds   # sequential \| batch \| rounds` `:140`; header `:100` |
| 3 | "A fixture transcript in `rounds` mode carries `<!-- round: N; questions: [{id, depends_on}] -->` blocks; `tools/check-round-independence.sh` reports ≥ 2 questions per round (final round exempt) and no same-round dependency (bats); transcript in the sprint a2a directory" | ⚠ Partial | Met: `tests/fixtures/rounds/independent.md:25,48,75,90` (four rounds, one re-asked question); `tools/check-round-independence.sh` reports average 2.33, final round exempt, PASS; `tests/unit/check-round-independence.bats` RI-1, RI-2, RI-3. Not done: copying the transcript into `grimoires/loa/a2a/sprint-252/`, because my brief allows only the report file outside the worktree. The lead copies `tests/fixtures/rounds/independent.md` there. |
| 4 | "`dec-write-lib.sh` bats: ids allocate max+1 …" | n/a (part B) | |
| 5 | "`validate-artifact.sh --type decisions` exits 0 on the live file …" | n/a (part B) | |
| 6 | "`validate-artifact.sh --type prd` fails a fixture where an `[ASSUMPTION decision]` tag has no `DEC` row …" | n/a (part B) | The tag classes it validates are defined at `.claude/skills/discovering-requirements/SKILL.md:75` |
| 7 | "The SessionStart surface wraps its block in the L6 data fence …" | n/a (part B) | |
| 8 | "Existing suites for `validate-artifact`, `grimoire-index`, `prompt-budget` and `skill-capabilities` stay green (backward compatibility)" | ⚠ Partial (A's share ✓) | `prompt-budget.bats` 9/9 and `skill-capabilities.bats` green with this patch; `validate-artifact` and `grimoire-index` are part B's files and are untouched here |
| 9 | "`grimoire-index.sh` emits `## decisions` …" | n/a (part B) | |
| 10 | "No skill's `allowed-tools` grants `dec-write-lib.sh confirm`, `supersede` or `context --clear` …" | n/a (parts B/C) | This patch adds no `allowed-tools` entries. The prime directive names `context --set-unattended`, never `--clear`, at `.claude/skills/autonomous-agent/SKILL.md:66` |
| 11 | "`tests/unit/user-invoked-commands.bats` green …" | n/a (part C) | |
| 12 | "`no-history-in-rule-text.bats`, `skill-capabilities.bats`, `implement-gate.bats`, `verdict-derive.bats`, `validate-artifact` suites green" | ⚠ Partial (A's share ✓) | `no-history-in-rule-text.bats`, `skill-capabilities.bats`, `implement-gate.bats` green with this patch. I did not run `verdict-derive` or `validate-artifact` because this patch touches no file they read. |

Deliverable and FR checks for this part:

| Item | Status | Evidence |
|---|---|---|
| Mode Behavior and Input Style tables moved to `resources/REFERENCE.md` behind guarded pointers | ✓ Met | `REFERENCE.md:49-70` (§Interview Modes); pointer with guard word "see" at `SKILL.md:69` |
| `planning-sprints` Phase 2 and `designing-architecture` Phase 2 reference the same pacing rule | ✓ Met | `.claude/skills/planning-sprints/SKILL.md:208`; `.claude/skills/designing-architecture/SKILL.md:204` |
| Backpressure Protocol states the fact/decision rule and tag classes in ≤ 3 lines | ✓ Met | `.claude/skills/discovering-requirements/SKILL.md:75` (one line) |
| Karpathy §1 and the autonomous-agent prime directive name the `DEC` row as the unattended record | ✓ Met | `.claude/protocols/karpathy-principles.md:32-38`; `.claude/skills/autonomous-agent/SKILL.md:66` |
| `render-templates.md` carries the section, rendered by the `list` subcommand | ✓ Met | `.claude/skills/run-mode/resources/render-templates.md:30-31` (incomplete body), `:70-71` (completion body), `:100-124` (§decisions-section-steps) |

## Tasks Completed

**Task 1.1: tables out, bytes freed.**
- The Mode Behavior, Input Style Resolution and Question Pacing tables moved to `REFERENCE.md` §Interview Modes and §Question Pacing. The Mode table's pacing column now reads `rounds` for `thorough` and `batch` for `minimal`.
- The Phase 4 EARS line moved into `REFERENCE.md` §Discovery Phase Questions Phase 4. The Phase Topics pointer now names it.
- The Phase 4 anti-inference directive was shortened in place. Its rule is unchanged.
- The Config Reading block now uses a one-line `cfg` helper instead of eight repeated `yq … || echo` lines. A fixture run on five configs showed identical values for every variable.
- The Phase 8 PRD source-tracing example duplicated the Output Format block. It is now one sentence pointing there.

**Task 1.2: rounds pacing.**
- `REFERENCE.md` §Question Pacing has the pacing table with `rounds`, plus §Rounds with seven rules: frontier, facts stay out, phase scope, format, answers, recompute, and the comment block. It also has a worked three-question round with a re-asked entry and the checker's interface.
- The SKILL.md has a 3-line pointer section, "Modes and Pacing".
- Config default: the reader resolves an unset `interview.pacing` to `rounds` under `thorough` and `batch` under `minimal`, after `per_skill` picks the mode. An explicit value always wins.
- The `.loa.config.yaml.example` interview block documents all of this.
- `planning-sprints` and `designing-architecture` Phase 2 each gained the shared line.
- New `tools/check-round-independence.sh`, `tests/unit/check-round-independence.bats`, and fixtures `tests/fixtures/rounds/independent.md` (passes) and `same-round-dependency.md` (fails).

**Task 1.7, prose half.**
- The Backpressure "Fact or decision" rule uses the SDD D-2.1 text verbatim. The old "record assumptions with `[ASSUMPTION]` tags" clause was removed so that it does not contradict the classed tags.
- The Karpathy §1 sentence follows D-2.2 and uses the full writer path.
- The prime directive follows D-2.3.
- The PR-body section and §decisions-section-steps follow D-2.4.

## Technical Highlights

- **The checker's logic is one jq reduce.** Bash extracts the blocks and validates each array's shape. A single jq program then tracks asked ids, the same-round set and the earlier-round set. A malformed block becomes a reported violation, not a crash. Round numbers are normalised with `10#` and capped at 9 digits, so `02` and huge numbers cannot break `--argjson`.
- **The checker enforces more than the SDD minimum.** It also fails on a self-dependency, on `reasked` for an id never asked, and on round numbers that do not increase. These close gaps a sloppy transcript would otherwise pass.
- **The worked example is tested.** Bats RI-13 feeds the `<!-- round: 2 -->` line from `REFERENCE.md` through the checker, so the documented example cannot drift into an invalid one.
- **The PR section fails loudly.** If `dec-write-lib.sh list` exits non-zero, the section says the ledger is unavailable instead of rendering empty. An empty section would falsely claim the operator decided everything.
- **Bash 3.2 compatible.** The checker uses no `mapfile`, no `declare -A` and no `${x,,}`. It sets `LC_ALL=C` and uses POSIX ERE through `grep -oE` and `sed -E`.

## Testing Summary

```
$ bash tools/check-prompt-budget.sh            # exit 0
autonomous-agent        16328
designing-architecture  15146
discovering-requirements 15439
planning-sprints        16347
run-mode                15372
CLAUDE.loa.md 10225 B (limit 10240)
protocols total 131444 B over 27 files (fail > 160000)  WARN (> 114688)   # pre-existing WARN, +255 B

$ bats tests/unit/prompt-budget.bats tests/unit/no-history-in-rule-text.bats \
       tests/unit/skill-capabilities.bats tests/unit/check-round-independence.bats
1..61   61 ok, 0 not ok

$ bash tools/check-no-raw-sha256sum.sh          # OK, exit 0
$ bash tools/check-no-swallowed-jq.sh --root tools   # new tool not flagged (only pre-existing stage-tier-benchmark.sh sites)
$ bats tests/unit/skill-capabilities-role-lint.bats  # green
$ bash .claude/scripts/validate-skill-capabilities.sh # exit 0
```

**Mutation check.** I disabled the same-round rule and the average rule in the checker. RI-3, RI-5 and RI-6 then failed. With the original restored, the suite was 13/13 green.

**Sweep of every suite that references a touched file.** I ran 18 suites. 15 are fully green, including `implement-gate`, `karpathy-config-schema`, `instruction-diet-revert`, `model-residue` and `no-history-in-rule-text`. Three integration suites have failures that are identical at the base commit, checked in a detached HEAD worktree:

| Suite | Failing cases (same at `e9f175a6`) |
|---|---|
| `tests/integration/gpt-review-skills.bats` | 5, 12, 14, 15, 16, 17 |
| `tests/integration/test_process_compliance.bats` | 6, 7, 9, 10 |
| `tests/integration/scheduled-cycle-skill-3D.bats` | 10 |

**Byte counts, before and after.**

| File | Before | After |
|---|---|---|
| `discovering-requirements/SKILL.md` | 16,304 | 15,439 |
| `discovering-requirements/resources/REFERENCE.md` (uncharged) | 15,226 | 20,116 |
| `planning-sprints/SKILL.md` | 16,370 | 16,347 |
| `designing-architecture/SKILL.md` | 15,006 | 15,146 |
| `autonomous-agent/SKILL.md` | 16,211 | 16,328 |

**Task 1.1 headroom accounting for `discovering-requirements/SKILL.md`.**

| Quantity | Bytes |
|---|---|
| Removed (tables, pacing table, EARS line, config boilerplate, Phase 8 example, shortened directive) | 1,577 |
| Added this sprint: rounds pointer section | 325 |
| Added this sprint: fact/decision line | 387 |
| Later sprints, measured from SDD D-5.1 and D-6.5 text: prototype sentence | ≈ 260 |
| Later sprints, measured from SDD D-5.1 and D-6.5 text: glossary sentence | ≈ 160 |
| Required: all this cycle's additions plus 400 B | ≈ 1,532 |
| Projected size after Sprints 2 and 3 | ≈ 15,860 (≈ 520 B under the limit) |

## Known Limitations

- **The rounds transcript is not in the sprint a2a directory yet.** AC 3 wants it there, and my brief limits writes outside the worktree to this report. The lead should copy `tests/fixtures/rounds/independent.md` into `grimoires/loa/a2a/sprint-252/`.
- **The fixture is hand-authored.** SDD §7 asks for a scripted headless transcript plus `rounds-rubric.md`. That needs `claude -p`, which is a live model call and outside my brief. G-3 in Sprint 3 scores a different transcript.
- **`planning-sprints/SKILL.md` has 37 B headroom.** Sprint 2 adds the ≈ 260 B prototype line there. It must first use the SDD's named fallback cut, the Beads Flatline Loop section, or move the Phase 2 checklist text. I could not move text into `planning-sprints/resources/REFERENCE.md` because it is not in my file list.
- **`autonomous-agent/SKILL.md` has 56 B headroom.** The D-2.3 text is longer than the parenthetical it replaces.
- **No Decisions section in `halt-incomplete-pr-body`.** D-2.4 names the completion body and "the incomplete body". I added it to `completion-pr-body` and `sprint-plan-incomplete-pr-body`, the two bodies with a Flatline block. `halt-incomplete-pr-body` is unchanged.
- **The run-mode step lists do not name the new step.** `sprint-plan-mode.md` "Completion PR" steps 1-6 do not mention §decisions-section-steps; the PR-body placeholder names it instead. That file was not in my list. The lead or a later task can add a step 4.5 that points there.
- **The PR-section steps assume an output shape.** They assume `dec-write-lib.sh list --format md` prints a `| Decision | Voice | Status | Why | Source |` table. Step 5 appends "Confirm with /decisions confirm." only if the output does not already end with it, so either writer choice renders correctly. Implementer B should confirm the column header.
- **D-2.6 is not done.** That is the debrief and `designing-architecture/SKILL.md:347` sentence that writes interactive Key Decisions as rows. It is not in Task 1.7's text and was not assigned to me.
- **Pre-existing bug, not fixed.** yq's `//` operator treats `false` as missing. So `no_infer: false`, `between_phases: false` and `before_generation: false` read back as `true`, before this patch and after. The `cfg` helper keeps that behaviour identical on purpose. A fix needs `yq '.a.b | select(. != null)'` or similar, and should go through `/bug`.
- **Integrity files are not regenerated.** `REPO-MAP.md`, `.checksum` and `checksums.json` were not regenerated for the `.claude/` edits. Per the PR checklist, the lead regenerates them at merge.

## Verification Steps

```bash
cd /path/to/checkout && git apply /home/merlin/.cache/loa/cycle-128/s1-a.patch
bash tools/check-prompt-budget.sh; echo $?                    # 0
wc -c .claude/skills/discovering-requirements/SKILL.md        # 15439
tools/check-round-independence.sh tests/fixtures/rounds/independent.md; echo $?          # PASS, 0
tools/check-round-independence.sh tests/fixtures/rounds/same-round-dependency.md; echo $? # FAIL, 1
bats tests/unit/prompt-budget.bats tests/unit/no-history-in-rule-text.bats \
     tests/unit/skill-capabilities.bats tests/unit/check-round-independence.bats          # 61/61
yq eval '.interview.pacing' .loa.config.yaml.example          # rounds
grep -n 'Fact or decision' .claude/skills/discovering-requirements/SKILL.md
grep -n 'decisions-section-steps' .claude/skills/run-mode/resources/render-templates.md
```

## Proposed CHANGELOG lines

Under `[Unreleased]`:

- **Interview rounds.** `interview.pacing: rounds` asks every question whose prerequisites are settled in one numbered round, each with a recommended answer. A bare "yes" accepts every recommendation, and a numbered answer overrides one. Each round ends with a `<!-- round: N; questions: [...] -->` block. The rule covers discovery, `/architect` Phase 2 and `/sprint-plan` Phase 2.
- **New checker.** `tools/check-round-independence.sh` checks those blocks. It fails on a same-round or unknown dependency, or when rounds average fewer than `--min-average` questions (default 2, final round exempt).
- **Fact or decision.** The discovery Backpressure Protocol splits questions into facts, which the agent looks up and never asks, and decisions, which belong to the operator. Assumption tags carry their class: `[ASSUMPTION fact]` or `[ASSUMPTION decision] (DEC-NNNN)`.
- **Unattended decisions go to the ledger.** Karpathy principle 1 and the `/autonomous` prime directive record each one with `dec-write-lib.sh new` instead of only a NOTES.md line.
- **Run-mode PR bodies.** The completion and sprint-plan-incomplete bodies gain "Decisions taken on your behalf", rendered from `dec-write-lib.sh list`.
- **Migration: the `thorough` pacing default moves from `sequential` to `rounds`.** An explicit `interview.pacing` value in your config is unchanged. Set `interview.pacing: sequential` to keep one question per turn. `minimal` mode still defaults to `batch`.

## Decisions taken beyond the SDD

For the lead to record as `DEC` rows (`decided_by: agent`, `proposed`).

1. **Checker test file name.** I named it `tests/unit/check-round-independence.bats`, as the brief and sprint Task 1.9 do. The SDD component map and §7 say `round-independence.bats`. *Alternative:* follow the SDD name. *Why:* the brief names the file explicitly, and it matches the tool name.
2. **Extra checker rules.** The checker also fails on a self-dependency, on `reasked` for an id never asked before, and on non-increasing round numbers. Malformed blocks exit 1, not 2. *Alternative:* only the three SDD §5.4 failure rules, and exit 2 for any parse problem. *Why:* each extra rule is a transcript the frontier rule forbids. Exit 2 stays reserved for "no block found" and usage errors, as §5.4 specifies.
3. **Single-round transcripts are held to the minimum.** With one round, that round counts toward the average. *Alternative:* exempt it as the final round. *Why:* §5.4 exempts the final round only "when there are two or more". A one-round interview of a single question is the sequential shape that rounds exist to replace.
4. **The pacing default lives in the reader.** An unset `interview.pacing` resolves after `per_skill` picks the mode. *Alternative:* only change the fallback string to `"rounds"`, as D-1.1 says literally. *Why:* D-1.1 also says `minimal` → `batch`, and a single fallback string cannot give per-mode defaults.
5. **Config Reading compressed with a `cfg` helper.** The SDD lists the tables, the pacing table and the EARS line as the bytes to free. *Alternative:* cut the SDD's named fallback, the Phase 4 anti-inference directive, by moving it behind a pointer. *Why:* the helper frees about 370 B with byte-identical behaviour across five fixture configs, and the anti-inference rule stays in the always-loaded file. I also shortened the directive in place and replaced the Phase 8 example that duplicated Output Format.
6. **`structured` input style during rounds.** In `rounds`, a round is one markdown message even when `discovery_questions` is `structured` (`REFERENCE.md` §Input Style Resolution). *Alternative:* split a round across several AskUserQuestion calls. *Why:* a round has no size cap, and splitting it would bring back the turn-per-question cost that rounds remove.
7. **The planning-sprints Semantic Labels table became one line.** It points at `.claude/protocols/beads-integration.md` §Labels, and the Phase 2 bullets became one sentence pointing at the REFERENCE checklist. *Alternative:* move both into `planning-sprints/resources/REFERENCE.md`, as SDD §1.4 suggests. *Why:* that file is outside my list, and the protocol already holds the same labels table at `beads-integration.md:136-146`.
8. **The PR section uses the §5.1 flags.** It renders with `list --voice agent,flatline,dissent --cycle "$cycle_id" --format md`, with `cycle_id` taken from `ledger.json` `.active_cycle`. *Alternative:* `list --not-decided-by operator`, which sprint Task 1.7 and the PRD name but SDD §5.1 does not define. *Why:* the brief says to use the CLI exactly as §5.1 specifies, and D-2.4 uses the `--voice` form.
9. **The PR section has an "unavailable" line.** It is printed when `list` exits non-zero. *Alternative:* render nothing or the zero-row line. *Why:* both alternatives would claim the operator made every decision when the ledger simply failed to load.
10. **The prime directive carries `--reason <why>`.** It reads `context --set-unattended --reason <why>`, per the §5.1 `context` row, where D-2.3 omits the flag. *Why:* the brief says §5.1 is authoritative for the CLI.

## Review round 1

The incremental patch is `/home/merlin/.cache/loa/cycle-128/s1-a-fix1.patch` (4 files, +18 / -6). It is the unstaged diff against the index, which still holds the first patch unchanged (`cmp` matched). A clean HEAD worktree applied `s1-a.patch` and then `s1-a-fix1.patch` without conflict. `git add -A && git diff --cached` would have produced the cumulative patch, not an incremental one.

**Finding 1: the shipped example pinned `rounds` for every mode. Fixed.**
- `.loa.config.yaml.example:140` is now a commented example: `# pacing: rounds   # sequential | batch | rounds; unset = rounds for thorough, batch for minimal`. `yq eval '.interview.pacing'` on the example returns `null`, so the per-mode default applies.
- Lines `:127-128` say the shipped default is unset and how to pin a value. The header at `:100` was adjusted to match.
- `discovering-requirements/resources/REFERENCE.md:60` now says the key is unset by default and the mode default applies.
- The SKILL.md `cfg` fallback already agreed and is unchanged. Unset resolves to `rounds` under thorough and `batch` under minimal.
- This supersedes the AC 2 evidence above that cited `pacing: rounds` at `:140` as a live value. The documentation lines are unchanged.

**Finding 2: a two-value capture escaped the shape check. Fixed.**
- The shape check now slurps the capture and requires exactly one well-formed array: `jq -se 'length == 1 and (.[0] | type == "array" and all(...))'`. The change is at `tools/check-round-independence.sh:72-77`.
- `questions: [] [{...}]` is now reported as "round 1: malformed questions array" with exit 1.
- New bats case RI-11b covers it. Run against the old check, RI-11b failed (the script exited 2). With the fix it passes.

**Re-run:**

```
$ bats tests/unit/check-round-independence.bats tests/unit/prompt-budget.bats
1..23   23 ok, 0 not ok
$ bash tools/check-prompt-budget.sh --quiet; echo $?
0
```

No SKILL.md changed in this round, so the byte counts above still stand.

**Decision for the ledger:** the incremental patch is the unstaged diff rather than the cumulative `--cached` diff. The alternative was a cumulative `s1-a-fix1.patch`. I chose the incremental diff because the brief requires a patch that applies on top of the first one.

## Audit round

The incremental patch is `/home/merlin/.cache/loa/cycle-128/s1-a-fix2.patch` (3 files, +95 / -16). Before editing, I staged the review-round-1 changes, so fix2 is the diff against an index holding `s1-a.patch` plus `s1-a-fix1.patch`. A clean HEAD worktree applied the three patches in order without conflict. The result was byte-identical to this worktree for the checker and the example config. Everything is staged again, so the cumulative state is `git diff --cached`.

**Finding 1: untrusted ids could put escapes on the terminal. Fixed.**
- The shape check now requires every `id` and every `depends_on` name to match `^[A-Za-z0-9_.-]{1,64}$`. Anything else is a "malformed questions array" violation with exit 1.
- As defence in depth, every line of the human output passes through a jq `clean` filter that replaces control characters with `?`, so no raw control byte reaches the terminal. `--json` output keeps JSON escaping and never contains raw bytes.
- New fixture `tests/fixtures/rounds/escape-id.md` has a `\u001b[31mPASS` id in one round and an escape in a `depends_on` name in another. Bats RI-11c asserts exit 1, both rounds reported malformed, and no ESC byte in either output mode.
- RI-11d covers an id with a space and a 65-character id.

**Finding 2: transcript content travelled as jq argv strings. Fixed.**
- Content no longer travels as a jq argv string. Each captured block is written to a temp file, and per-round entries are appended to a JSONL file. The report reads the rounds with `--slurpfile`. The work directory comes from `mktemp -d` and is removed by an EXIT trap.
- The malformed entry no longer echoes the raw capture; it carries a fixed reason string instead.
- A block over 65,536 B is a malformed violation that names its size and the limit.
- RI-11e uses a block of more than 200 KiB, which reports the limit with exit 1.
- RI-11f uses a 900-round transcript of more than 128 KiB. It now passes and reports all 1,800 questions.

**Red check:** I ran RI-11c, RI-11d, RI-11e and RI-11f against the round-1 checker from the index. All four failed there and pass with the fix.

**Re-run:**

```
$ bats tests/unit/check-round-independence.bats
1..18   18 ok, 0 not ok   (about 60 s wall clock; RI-11e and RI-11f build large transcripts)
$ bash tools/check-prompt-budget.sh --quiet; echo $?
0
```

**Decisions for the ledger:**
- **Size guard.** Blocks are capped at 64 KiB and also moved through files, which does both remedies the auditor offered. The alternative was files only, with no cap. A single round over 64 KiB is not a plausible interview, so the cap turns it into a clear violation rather than a slow parse.
- **Id grammar.** It is the auditor's pattern, `[A-Za-z0-9_.-]{1,64}`. It admits the documented `Q<n>` ids and slug-style ids. The alternative was a stricter `^Q[0-9]+$`, which would reject ids other tools may use.
