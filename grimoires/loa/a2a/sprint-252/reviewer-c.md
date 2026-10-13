# Sprint 252 (cycle-128 Sprint 1), part C: operator-only commands

Implementer C. Tasks 1.0 and 1.8 (FR-8). Worktree `/home/merlin/Documents/thj/code/loa-wt-s1c` (branch `wt/s1c`, base `e9f175a6`), staged, not committed. Patch: `/home/merlin/.cache/loa/cycle-128/s1-c.patch`.

## Executive Summary

The harness check ran once, live, before any flag landed: **verified**. A command carrying `disable-model-invocation: true` is refused to the Skill tool with the error "cannot be used with Skill tool due to disable-model-invocation. Ask the user to run /fixture-hidden themselves", and its body never loads; the unflagged control ran. FR-8 is harness-enforced, not lint-only.

Seven commands now carry the flag: the existing `gpt-review`, the safe set (`loa-eject`, `toggle-gpt-review`, `permission-audit`, `loa-setup` command file only), and two from the triage set (`contribute`, `run-halt`). The other seven triage commands stay unflagged: four are orchestrator steps, `feedback` is a sanctioned teammate path, and `mount` and `update-loa` are advice-only but deferred because the specified lint reads eight of their advice lines (files outside part C) as operative. `decisions` is not in the allowlist: part B lands that file, and a guarded test asserts it once present.

## AC Verification

Sprint 1 acceptance criteria, verbatim (`grimoires/loa/sprint.md:52-64`):

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | `tools/check-prompt-budget.sh` green; `discovering-requirements/SKILL.md` ≤ 16,384 B | ⚠ Partial | Budget green in this tree (exit 0); the SKILL.md byte target is part A's |
| 2 | `.loa.config.yaml.example` documents `pacing: rounds` (frontier rule, numbered format, "yes accepts the recommendation", the `sequential` opt-out) | n/a (part A) | |
| 3 | A fixture transcript in `rounds` mode carries `<!-- round: N; questions: [{id, depends_on}] -->` blocks; `tools/check-round-independence.sh` reports ≥ 2 questions per round (final round exempt) and no same-round dependency (bats); transcript in the sprint a2a directory | n/a (part A) | |
| 4 | `dec-write-lib.sh` bats: ids allocate max+1 under the lock in the main checkout; a linked worktree writes the pending file and `import` allocates real ids and rewrites references; the file never shrinks and never drops an id; content edits to an existing row are rejected; a failed write leaves the previous file intact; `decide`/`confirm` without `--evidence` and `reject` without a follow-up exit non-zero; under every unattended signal (run-state marker, `LOA_UNATTENDED`, autonomous Flatline mode, PRD Status line) a write lands `proposed` with `decided_by: agent` whatever the flags; `CI=1` makes the writer exit 1; the hostile-string corpus round-trips against the sanitised input | n/a (part B) | |
| 5 | `validate-artifact.sh --type decisions` exits 0 on the live file and 1 on each negative fixture: missing `decided_by`, duplicate id, illegal transition (`rejected` → `decided`), `decided` row without evidence, `operator` row without an answer reference, a content edit to an existing row; `supersede` leaves the old row `superseded` and removes nothing | n/a (part B) | |
| 6 | `validate-artifact.sh --type prd` fails a fixture where an `[ASSUMPTION decision]` tag has no `DEC` row; `--type sdd` WARNs on a Resolved open question without a `DEC` id; `prd-template.md` and `sdd-template.md` carry the decisions appendix; `loa-learnings-index.sh` and `path-lib.sh` resolve the tracked ledger (bats) | n/a (part A/B) | |
| 7 | The SessionStart surface wraps its block in the L6 data fence, caps summaries at 100 chars, and a negative bats case shows control characters and instruction-like text neutralised | n/a (part B) | |
| 8 | Existing suites for `validate-artifact`, `grimoire-index`, `prompt-budget` and `skill-capabilities` stay green (backward compatibility) | ⚠ Partial | In this tree: validate-artifact 36/36, prompt-budget 9/9, skill-capabilities 36/36; grimoire-index not run (part B's surface) |
| 9 | `grimoire-index.sh` emits `## decisions` with ID / status / decided_by / summary / source (bats for TSV, JSON and markdown, and the no-yq skip); the SessionStart surface prints nothing when the key is off | n/a (part B) | |
| 10 | No skill's `allowed-tools` grants `dec-write-lib.sh confirm`, `supersede` or `context --clear`; `/decisions` carries `disable-model-invocation: true` and is the only caller (bats over frontmatter) and the open rows when on | ⚠ Partial | The allowed-tools assertion lands here: `tests/unit/user-invoked-commands.bats:131`, proved by the fixture at `:210`. The `/decisions` flag assertion is at `:137` and skips until part B's file lands |
| 11 | `tests/unit/user-invoked-commands.bats` green; the automated harness check passes or is recorded as skipped (CLI absent) with the lint-only contingency stated; the triage table and its `DEC` rows exist under `grimoires/loa/a2a/sprint-252/triage-fr8.md` | ✓ Met | 12 tests, 11 ok and 1 guarded skip; live harness passed (`tests/unit/user-invoked-harness.bats:134`); triage table and nine proposed DEC rows in `triage-fr8.md` (the lead writes the ledger rows) |
| 12 | `no-history-in-rule-text.bats`, `skill-capabilities.bats`, `implement-gate.bats`, `verdict-derive.bats`, `validate-artifact` suites green | ✓ Met (this tree) | 3/3, 36/36, 23/23, 75/75, 36/36 |

Deliverable line "An automated harness check ... recorded first; then `disable-model-invocation: true` on the safe set ..., the referenced set triaged ..., `.claude/data/user-invoked-commands.txt`, `tests/unit/user-invoked-commands.bats`": ✓ Met. Flags: `contribute.md:56`, `loa-eject.md:6`, `loa-setup.md:4`, `permission-audit.md:4`, `run-halt.md:34`, `toggle-gpt-review.md:4` (all under `.claude/commands/`). Allowlist: `.claude/data/user-invoked-commands.txt:6-12`.

## Tasks Completed

- **Task 1.0.** `tests/unit/user-invoked-harness.bats`: four offline classifier cases over canned stream-json and one live case. The live case builds a temp git project with `fixture-hidden` (flagged) and `fixture-visible` (control), runs one `claude -p --max-turns 3 --tools Skill --output-format stream-json --verbose --no-session-persistence` call, and classifies. It skips when `claude` is absent, when `LOA_HARNESS_CHECK=0`, on CLI error or unparsable output, and when the control never ran. It fails only when the hidden body reaches the stream ("flag does not hide the command: FR-8 is lint-only, G-7 partial"). `LOA_HARNESS_OUT` keeps the raw stream.
- **Task 1.8.** Allowlist file; flags on the safe set (minimal frontmatter blocks added to `toggle-gpt-review.md` and `loa-setup.md`); `contribute` and `run-halt` flagged after triage; `tests/unit/user-invoked-commands.bats`; `triage-fr8.md` with 127 per-reference rows and a per-command decision table.

## Technical Highlights

- The live run grants only the Skill tool, so the model cannot read the fixture bodies, run Bash, or reach a real Loa command. "Ran" is judged by the body marker reaching the stream, never by the model's claim.
- The operative-reference check widens the SDD D-8.3 pattern in two ways: verbs match in any case, and an optional "the" is allowed. The SDD pattern as written misses `ship.md:60` ("execute `/deploy-production`") and `loa.md:262` ("Invoke the `/ship` skill"). With the widening, a probe that appends all nine triage names catches every orchestrator step found by hand.
- Exempt words match at a word start, so "task" does not exempt a line through "ask". The name must end at a non-name character, so `/alpha` does not match `/alphabet` or `/alpha-two`.
- Every check is a function over a root directory and has a fixture case that fails when its invariant breaks: missing file, missing flag, flag outside the frontmatter, unlisted flag, operative line, and a skill granting `confirm` or `context --clear`.

## Testing Summary

```
LOA_HARNESS_OUT=~/.cache/loa/cycle-128/s1c-harness-stream.jsonl \
  bats -f "live harness" tests/unit/user-invoked-harness.bats
# 1..1
# verdict=verified rc=0
# skill_call: fixture-hidden   true    (is_error)
# skill_call: fixture-visible  false
# ok 1 live harness: disable-model-invocation hides a command from the Skill tool
```

Recorded outcome: **verified**, run once before any flag was written (Claude Code 2.1.296, `global.anthropic.claude-opus-5-5`, 4 turns, USD 0.088). The init event listed both fixtures as slash commands, so the operator can still type a flagged command.

```
LOA_HARNESS_CHECK=0 bats tests/unit/user-invoked-commands.bats tests/unit/user-invoked-harness.bats \
  tests/unit/skill-capabilities.bats tests/unit/no-history-in-rule-text.bats
# 1..56, all ok; skips: the /decisions guard, and the live case (already run once)
bash tools/check-prompt-budget.sh            # exit 0 (pre-existing protocols WARN, untouched)
bats tests/unit/{implement-gate,verdict-derive,validate-artifact,prompt-budget}.bats   # 23, 75, 36, 9 ok
bats tests/unit/{documentation-coherence,zone-compliance,agents-md-gen}.bats         # 54, 18, 8 ok
```

`bats` is not on the default PATH here. It came from `~/.config/nvm/versions/node/v24.11.1/bin`. Interactive `grep` is aliased to ugrep, so the triage greps used `/usr/bin/grep`.

## Known Limitations

- **`loa-setup` stays model-reachable as a skill.** The skill `loa-setup` shares the name and is unflagged (D-8.1, A12). The single harness run did not test whether a Skill call naming `loa-setup` resolves to the flagged command or the unflagged skill.
- **The safe set is not reference-free.** `loa.md:263` routes the `loa-setup` menu choice with "Invoke the `/loa setup` skill". `loa.md:268` falls back to showing the command when a skill call is denied, so `/loa` degrades rather than breaks. The lint does not model the `/loa setup` alias form.
- **`mount` and `update-loa` deferred.** Both are advice-only. Flagging them needs eight user-facing lines reworded or an error-message exemption in the lint: `ride.md:62,66,70,282,283`, `run.md:60`, `run-sprint-plan.md:44`, `translate-ride.md:145`.
- **The lint is lexical.** It cannot see an orchestrator step phrased without one of the four verbs, such as "routes to `/x`".
- **Live check default.** The live case runs whenever `claude` is on PATH, unless `LOA_HARNESS_CHECK=0`. The SDD D-8.4 default was opt-in via `LOA_LIVE_HARNESS=1`. The SDD file name was `harness-hidden-command.bats`. The lead's brief chose the current name and default.
- **Lead follow-up at PR time.** `.claude/checksums.json` covers the edited command files, so REPO-MAP, `.checksum` and `checksums.json` need regeneration.

## Verification Steps

1. `git apply --check /home/merlin/.cache/loa/cycle-128/s1-c.patch` on `e9f175a6`, then apply.
2. `bats tests/unit/user-invoked-commands.bats tests/unit/user-invoked-harness.bats`. This makes one live call when `claude` is present. Set `LOA_HARNESS_CHECK=0` to skip it.
3. Mutation: delete `disable-model-invocation: true` from `.claude/commands/run-halt.md`. Test 2 now fails with "unflagged: run-halt". Then add `Run /run-halt` to any skill body. Test 4 now fails with that file and line.
4. Read `grimoires/loa/a2a/sprint-252/triage-fr8.md` and spot-check any row against its cited line.

## Proposed CHANGELOG lines

```
- Operator-only commands (FR-8): `disable-model-invocation: true` on `/loa-eject`, `/toggle-gpt-review`,
  `/permission-audit`, `/loa-setup` (command), `/contribute` and `/run-halt`; the model's Skill tool refuses
  them and the operator types them. Allowlist `.claude/data/user-invoked-commands.txt`, lint
  `tests/unit/user-invoked-commands.bats`, live harness check `tests/unit/user-invoked-harness.bats`
  (verified on Claude Code 2.1.296; `LOA_HARNESS_CHECK=0` skips the live call).
- Ask the operator to type `/run-halt` and `/contribute`; an agent can no longer invoke them.
```

## Decisions taken beyond the SDD

| Decision | Alternatives | Why |
|---|---|---|
| Live run grants only the Skill tool (`--tools Skill`) | all default tools | The model cannot read the fixture body or run anything else, so a marker in the stream proves the body loaded |
| One live invocation asking for both fixtures | two runs as in D-8.4 step 3 | The lead's brief caps the live run at one invocation |
| File `user-invoked-harness.bats`, skip on `LOA_HARNESS_CHECK=0` | SDD's `harness-hidden-command.bats` with opt-in `LOA_LIVE_HARNESS=1` | The lead's brief names this file and switch |
| Operative regex: case-insensitive verbs, optional "the" | the D-8.3 pattern verbatim | The verbatim pattern misses `ship.md:60` and `loa.md:262`, both real orchestrator steps |
| Exempt words matched at a word start | substring match | Substring lets "task" exempt a line through "ask" |
| D-8.3's allowed-tools assertion lands in part C's bats | leave it to part B | D-8.3 places it in `user-invoked-commands.bats`; it passes vacuously until `dec-write-lib.sh` exists |
| `loa-setup` skill not flagged | flag it | A12 requires the harness to show the operator's command still works with the skill flagged; the single run did not test that |
| `update-loa` and `mount` deferred, not flagged | flag and exempt the lines; reword the lines | Both remedies touch files or lint rules outside part C's brief; the lead decides |
| `feedback` not flagged | flag on the body references alone | `agent-teams-reference.md:59,278` allows teammates to invoke it |

Proposed DEC rows, one per triaged command (`proposed`, `decided_by: agent`, `source` = the command file). The lead writes them through the lib at sprint close.

| Command | Decision | Rationale |
|---|---|---|
| update-loa | not flagged, deferred | advice-only; `translate-ride.md:145` trips the operative lint |
| mount | not flagged, deferred | advice-only; seven error-message lines trip the operative lint |
| contribute | flagged | one advice reference; opens an upstream PR |
| feedback | not flagged | teammates may invoke it per the agent-teams reference |
| deploy-production | not flagged | `/ship` and the autonomous agent execute it |
| archive-cycle | not flagged | `/ship` executes it; `/loa` invokes it after confirmation |
| ship | not flagged | `/loa` invokes it from its menu |
| run-halt | flagged | every reference is advice; the circuit breaker halts without it |
| run-resume | not flagged | `/simstim` resume invokes it |

## Review round 1

**Finding (advisory, cross-model dissent):** `check_operative` dropped any line holding an exempt word anywhere. That let "Run `/decisions confirm` on the operator's behalf" and "Invoke /contribute for the user" pass unreported.

**Fix** (`tests/unit/user-invoked-commands.bats`, `check_operative`). The check now works in two steps per line, in awk:
1. Find every verb + `/name` match, with the same widened pattern and name boundary as before.
2. Judge only the text before that match, cut to the current clause, meaning after the last ". ", ";" or " then ".

A match is exempt only when that clause prefix holds an exempt word at a word start, or an odd number of backticks. The odd count means the verb sits inside an inline quote. An exempt word after the command, or in an earlier clause, does not exempt the match. A line is reported when any match on it is operative. Fenced code blocks are deliberately not exempt.

**New fixture** ("an exempt word only exempts when it precedes the verb"):

| Line | Expected |
|---|---|
| Run `/alpha confirm` on the operator's behalf. | reported |
| Invoke /beta for the user. | reported |
| Tell the user to run /alpha. | exempt |
| Ask the operator to type `/alpha`. | exempt |
| Example reply: `Run /alpha first.` | exempt (inline quote) |
| Tell the user to run /alpha, then Run /beta yourself. | reported (second clause) |
| Recommend the operator Run `/beta --force` after review. | exempt |

**Results.** The live-tree check still reports nothing for the seven listed commands. The probe with all nine triage names appended reports the same lines as round 0, with nothing new.

```
LOA_HARNESS_CHECK=0 bats tests/unit/user-invoked-commands.bats tests/unit/user-invoked-harness.bats
# 1..18, all ok; skips: the /decisions guard, the live harness case
```

**Incremental patch:** `/home/merlin/.cache/loa/cycle-128/s1-c-fix1.patch`. It applies on top of `s1-c.patch` on `e9f175a6`, checked on a throwaway worktree, and gives a byte-identical bats file. The worktree index now holds both patches, so `git diff --cached` is the cumulative patch.
