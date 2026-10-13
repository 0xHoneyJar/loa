# Sprint 252 (cycle-128 Sprint 1), implementer B: decision ledger

Patch: `/home/merlin/.cache/loa/cycle-128/s1-b.patch` (worktree `loa-wt-s1b`, base `e9f175a6`, staged, not committed; 16 files, +2460/-21).

## Executive Summary

The decision ledger is built: the tracked empty ledger, its single locked writer `dec-write-lib.sh` (all eight subcommands), `validate-artifact.sh --type decisions`, the PRD tag-to-row rule, the SDD DEC-column WARN, the `## decisions` index family, the default-off SessionStart surface, the operator-only `/decisions` command and the template appendices. Attribution is derived: no caller can set `decided_by`, every unattended signal forces `proposed` with `proposed_by: agent`, and only `--recorded-by decisions-command` reaches confirm, decided-row reject/supersede and `context --clear`.

All new suites pass (dec-write-lib 43, loa-decisions-surface 8, validate-artifact 51 incl. 15 new, grimoire-index 12 incl. 5 new). Every regression suite named in the brief is green. One existing suite, `agents-md-gen.bats`, now fails 2 tests because it pins the command-file count at 49 and `/decisions` is a new command; README/AGENTS.md regeneration is outside my file set (see Known Limitations).

A dry run of the lead's 64-row seed file (`~/.cache/loa/cycle-128/seed-decisions.json`) in a scratch project under a RUNNING run state landed 64 rows, all `proposed / agent / decided_by null`, and the result validates.

## AC Verification

Sprint 1 acceptance criteria, verbatim from `grimoires/loa/sprint.md`:

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | `tools/check-prompt-budget.sh` green; `discovering-requirements/SKILL.md` ≤ 16,384 B | n/a (part A) | I did not touch any SKILL.md; `prompt-budget.bats` 9/9 green on my tree |
| 2 | `.loa.config.yaml.example` documents `pacing: rounds` (frontier rule, numbered format, "yes accepts the recommendation", the `sequential` opt-out) | n/a (part A) | I added only the `decisions:` block (`.loa.config.yaml.example:261-277`); `interview:` untouched |
| 3 | A fixture transcript in `rounds` mode carries `<!-- round: N; questions: [{id, depends_on}] -->` blocks; `tools/check-round-independence.sh` reports ≥ 2 questions per round (final round exempt) and no same-round dependency (bats); transcript in the sprint a2a directory | n/a (part A) | |
| 4 | `dec-write-lib.sh` bats: ids allocate max+1 under the lock in the main checkout; a linked worktree writes the pending file and `import` allocates real ids and rewrites references; the file never shrinks and never drops an id; content edits to an existing row are rejected; a failed write leaves the previous file intact; `decide`/`confirm` without `--evidence` and `reject` without a follow-up exit non-zero; under every unattended signal (run-state marker, `LOA_UNATTENDED`, autonomous Flatline mode, PRD Status line) a write lands `proposed` with `decided_by: agent` whatever the flags; `CI=1` makes the writer exit 1; the hostile-string corpus round-trips against the sanitised input | ✓ Met | `tests/unit/dec-write-lib.bats:63` (max+1), `:370` (worktree, pending, import, ref rewrite), `:72` (never shrinks / drops), `tests/unit/validate-artifact.bats:697` plus writer verify `.claude/scripts/lib/dec-write-lib.sh:393` (content edit), `:84` (failed write byte-identical), `:113` (evidence / follow-up), `:276-305` (six unattended signals, `--answer-ref` and `--as` ignored), `:349` (CI / GITHUB_ACTIONS / LOA_HOOK_CONTEXT), `:470` (corpus). Note on "decided_by: agent": see Decisions beyond the SDD, item 1 |
| 5 | `validate-artifact.sh --type decisions` exits 0 on the live file and 1 on each negative fixture: missing `decided_by`, duplicate id, illegal transition (`rejected` → `decided`), `decided` row without evidence, `operator` row without an answer reference, a content edit to an existing row; `supersede` leaves the old row `superseded` and removes nothing | ✓ Met | live file `validate-artifact.bats:642`; negatives `:671` (missing field, duplicate, PEND id, no evidence, operator without ref, non-operator `→ decided`, decided_by on a proposed row, ref grammar, schema_version, URL, phase, alternatives, first transition), `:689` (rejected → decided; rejected without follow-up), `:697` (content edit, dropped row, rewritten history), `:719` (supersede). Rules at `.claude/scripts/validate-artifact.sh:527-725` |
| 6 | `validate-artifact.sh --type prd` fails a fixture where an `[ASSUMPTION decision]` tag has no `DEC` row; `--type sdd` WARNs on a Resolved open question without a `DEC` id; `prd-template.md` and `sdd-template.md` carry the decisions appendix; `loa-learnings-index.sh` and `path-lib.sh` resolve the tracked ledger (bats) | ✓ Met | `validate-artifact.bats:739`, `:749`, `:764`, `:781`, `:793` (prd); `:805` (sdd); `:816` (templates: `prd-template.md:283`, `sdd-template.md:376,398`); readers `tests/unit/grimoire-index.bats:129`, both unchanged |
| 7 | The SessionStart surface wraps its block in the L6 data fence, caps summaries at 100 chars, and a negative bats case shows control characters and instruction-like text neutralised | ✓ Met | `.claude/hooks/session-start/loa-decisions-surface.sh:67-75,118-124`; `tests/unit/loa-decisions-surface.bats:41` (fence), `:92` (ESC, NUL, BEL, NEL, U+2028, a closing `</untrusted-content>`, "ignore previous instructions", `<invoke`, 100-char cap) |
| 8 | Existing suites for `validate-artifact`, `grimoire-index`, `prompt-budget` and `skill-capabilities` stay green (backward compatibility) | ✓ Met | see Testing Summary |
| 9 | `grimoire-index.sh` emits `## decisions` with ID / status / decided_by / summary / source (bats for TSV, JSON and markdown, and the no-yq skip); the SessionStart surface prints nothing when the key is off | ✓ Met | `.claude/scripts/grimoire-index.sh:177-195,224-228`; `grimoire-index.bats:89` (TSV via new `--tsv`), `:98` (JSON), `:107` (md), `:118` (no yq v4); `loa-decisions-surface.bats:28` (key off), `:34` (seam ignored outside bats) |
| 10 | No skill's `allowed-tools` grants `dec-write-lib.sh confirm`, `supersede` or `context --clear`; `/decisions` carries `disable-model-invocation: true` and is the only caller (bats over frontmatter) and the open rows when on | ✓ Met | `dec-write-lib.bats:526` (no SKILL.md grants), `:531` (flag in frontmatter; `--recorded-by decisions-command` appears only in `.claude/commands/decisions.md`); writer gate `dec-write-lib.sh:508`, `:574`, `:597`, `:718` |
| 11 | `tests/unit/user-invoked-commands.bats` green; the automated harness check passes or is recorded as skipped (CLI absent) with the lint-only contingency stated; the triage table and its `DEC` rows exist under `grimoires/loa/a2a/sprint-252/triage-fr8.md` | n/a (part C) | `decisions` must be added to `.claude/data/user-invoked-commands.txt` by part C |
| 12 | `no-history-in-rule-text.bats`, `skill-capabilities.bats`, `implement-gate.bats`, `verdict-derive.bats`, `validate-artifact` suites green | ✓ Met | 3/3, 36/36, 23/23, 75/75, 51/51 + bsd 3/3 |

## Tasks Completed

**Task 1.3 (ledger file, tracking, validator, templates)**
- `grimoires/loa/decisions.yaml`: header comment (append-only rules, lifecycle, the bar, writer and `/decisions`), `schema_version: 1`, `decisions: []`.
- `.gitignore`: line 149 `grimoires/loa/decisions.yaml` kept; `!grimoires/loa/decisions.yaml` added directly after it at line 150, then a one-line comment.
- `validate-gitignore-state.sh`: `tracked_set` row; negated matches are no longer reported as drift (see Decisions beyond the SDD, item 4).
- `validate-artifact.sh`: `--type decisions`, `--base-file`, `--ledger`; usage, header and dispatch updated; `validate_decisions`, `validate_prd_assumptions`, `validate_sdd_open_questions`, and the sprint-side `validate_sprint_deferred` WARN from D-2.5.
- `prd-template.md` gains Appendix E and `sdd-template.md` gains §11 D, each rendered by `dec-write-lib.sh list --not-decided-by operator --cycle {cycle} --format md`. The SDD template's Open Questions table gains the `DEC` column.

**Task 1.4 (writer)**
- `.claude/scripts/lib/dec-write-lib.sh` provides `new`, `decide`, `confirm`, `reject`, `supersede`, `import`, `list` and `context`, per SDD §5.1.
- **Locking:** a portable lock uses `flock -w` (10 s default), or a `mkdir` lock with a pid file and a stale check at 60 s with the pid dead.
- **Write path:** the jq-built row is passed to yq v4 only through `env()`/`strenv()`.
- **Verify before swap:** the ledger is copied to a temp beside the target and verified (parse, ids, count, every other row JSON-equal, the validator with `--base-file`), then renamed with `mv -f`.
- **Attribution:** context-derived; `flatline`/`dissent` voices need an artifact and record its sha256.
- **Worktrees:** a linked worktree, or `--pending`, writes to the sprint pending file with `PEND-` ids.
- **Refusals:** live writes refuse under CI/hook; jq plus Mike Farah yq v4 preflight, fail closed, no `br`.
- `tests/unit/dec-write-lib.bats` has 43 tests.

**Task 1.5 (surfaces)**
- `grimoire-index.sh` gains `emit_decisions()`, the `voice` JSON field and the `## decisions` table, plus a `--tsv` mode.
- `.claude/hooks/session-start/loa-decisions-surface.sh` is wired in `.claude/settings.json` after `loa-kf-surface.sh`, through `hook-guard.sh`, with `once: true`.
- `.loa.config.yaml.example` gains a `decisions:` block with `surface_at_session_start: false` and `unattended_marker_ttl_hours: 24`.
- `.claude/commands/decisions.md` adds `list`, `confirm`, `reject`, `supersede` and `clear-unattended`, with `disable-model-invocation: true`.
- A readers check covers both readers, which needed no change.
- `tests/unit/loa-decisions-surface.bats` has 8 tests.

**Task 1.7 (validator half)**
- The PRD tag classes are counted outside fenced and inline code.
- `BARE_ASSUMPTION_FAILS_FROM="2026-11-13"` is compared with the PRD `**Date:**`.
- Each `[ASSUMPTION decision]` line must cite a ledger row whose `source` names the PRD.
- A `**Deferred:**` line must cite an existing row.
- A miss FAILs unattended and WARNs interactive. Unattended means `dec-write-lib.sh context --prd <file>` reports a signal, so the writer and the gate agree.

## Technical Highlights

- **No associative arrays.** The flag parser stores values with `printf -v O_<key>`. Repeatable flags use a unit-separator join. This keeps the writer bash-3.2-safe, which `kf-write-lib.sh`'s `declare -A` is not. Flag names are validated, and unknown flags exit 2, so an agent cannot pass `--decided-by`.
- **Readable YAML.** Rows come out in block style with every string double-quoted. `yes`, `0x1F`, `null`, `~`, `!!binary`, `&anchor` and the rest of the corpus read back as the same strings. The header comment survives every write.
- **Large ledgers.** Whole-ledger JSON reaches jq through `--slurpfile`. Passing it as `--argjson` failed with "Argument list too long" at about 1,000 rows, and the dry run caught it. Rows are indexed by id, so the append-only comparison is linear.
- **Worktree runs.** In a linked worktree the writer also reads the main checkout's `.run`. A RUNNING run in the lead's checkout therefore makes an implementer's worktree write unattended too.
- **Agent supersede.** Superseding a decided row adds `supersede_proposed_by` on the old row and a `proposed` new row. Confirming the new row moves the old one to `superseded` in the same verified write.
- **Surface fencing.** Summaries are stripped of C0, C1 and U+2028/9. `<`, `>` and backticks are replaced, so no row can close the fence. Summaries are capped at 100 code points, and the block is wrapped by `sanitize_for_session_start L6 … --max-chars 2000`. If the sanitizer is unavailable, the hook prints a count line instead of the rows.

## Testing Summary

```
bats tests/unit/dec-write-lib.bats            # 43 ok
bats tests/unit/loa-decisions-surface.bats    # 8 ok
bats tests/unit/validate-artifact.bats        # 51 ok (36 existing + 15 new)
bats tests/unit/validate-artifact-bsd.bats    # 3 ok
bats tests/unit/grimoire-index.bats           # 12 ok (7 existing + 5 new)
bats tests/unit/kf-write-lib.bats             # 34 ok
bats tests/unit/skill-capabilities.bats       # 36 ok
bats tests/unit/no-history-in-rule-text.bats  # 3 ok
bats tests/unit/prompt-budget.bats            # 9 ok
bats tests/unit/validate-gitignore-state.bats # 7 ok
bats tests/unit/kf-surface.bats               # 8 ok
bats tests/unit/hook-wiring.bats              # 10 ok
bats tests/unit/hook-guard.bats               # 8 ok
bats tests/unit/settings-permissions.bats     # 65 ok
bats tests/unit/implement-gate.bats           # 23 ok
bats tests/unit/verdict-derive.bats           # 75 ok
bats tests/unit/agents-md-gen.bats            # 6 ok, 2 FAIL (command count 49 -> 50; see Known Limitations)
bash tools/check-no-raw-sha256sum.sh          # OK (the script lives in tools/, not .claude/scripts/)
bash .claude/scripts/validate-artifact.sh --type decisions --file grimoires/loa/decisions.yaml   # exit 0, 0 rows
bash .claude/scripts/validate-gitignore-state.sh   # "no State-Zone gitignore drift found."
git check-ignore -q grimoires/loa/decisions.yaml   # exit 1 (not ignored)
git check-ignore -v grimoires/loa/decisions.yaml   # prints ".gitignore:150:!grimoires/loa/decisions.yaml ...", exit 0
```

bats is not on this host's default PATH. I ran it from `~/.config/nvm/versions/node/v24.11.1/lib/node_modules/bats/bin`. `shellcheck` is not installed, so it was not run.

The `git check-ignore -v` check in the brief cannot print nothing while line 149 stays. With `-v`, git prints a matching negation and exits 0 by design. `-q` exits 1, which is the "not ignored" answer. The bats test at `dec-write-lib.bats:543` asserts `-q` exits 1 and that any `-v` match is the negation. Deleting line 149 would make the brief's literal command pass, but the SDD says keep it.

## Known Limitations

- **Command count.** `agents-md-gen.bats` (2 tests) fails until the lead updates README "49 total commands", regenerates AGENTS.md and moves the bats constant to 50, or lists `decisions` in `golden-path.json` `excluded_from_count`. None of those files were in my set.
- **Hook marker export.** The writer refuses `LOA_HOOK_CONTEXT=1`, but `hook-guard.sh` does not export it yet (D-3.14/A35). Not in my file set.
- **Not in my file set.** `run-preflight.sh` P9, `INSTALLATION.md`, the hooks template `.claude/hooks/settings.hooks.json`, and adding `decisions` to `.claude/data/user-invoked-commands.txt` (part C) are not done.
- **Write time.** A write on a 1,000-row ledger takes about 1.5 s; validation alone takes about 0.7 s. The SDD's target is under 1 s. The cost is several yq parses plus the PII scan. A cycle adds tens of rows, so I did not optimise further.
  - `# loa:shortcut: yq parses the ledger ~4 times per write; ~1.5 s at 1,000 rows — cache the parsed JSON across verify and validator when a ledger passes ~500 rows` (not written into the file; recorded here)
- **Map lines.** The surface's "map open > 30 days" lines (§4.3) are not built, because maps are Sprint 2 (FR-4).
- **BSD coverage.** No separate `dec-write-lib-bsd.bats` exists. Two tests in the main suite cover the BSD-relevant paths: flock removed from PATH, and the `mkdir` lock forced with `LOA_DEC_NO_FLOCK=1`.
- **Beads in `import`.** `import` prints the PEND to DEC mapping and the `br update <bead> --external-ref` repair line. It does not call `br` itself (see Decisions beyond the SDD, item 6).

## Verification Steps

1. Apply the patch to a clean checkout of `e9f175a6`:
   ```
   git apply --index ~/.cache/loa/cycle-128/s1-b.patch
   ```
2. Run the suites listed in the Testing Summary.
3. Seed the ledger in the main checkout, from the repo root, with the RUNNING state present. This uses the dry-run-tested script:
   ```
   bash ~/.cache/loa/cycle-128/s1b/seed-ledger.sh ~/.cache/loa/cycle-128/seed-decisions.json > ~/.cache/loa/cycle-128/seed-map.tsv
   bash .claude/scripts/validate-artifact.sh --type decisions --file grimoires/loa/decisions.yaml   # INFO: 64 decision rows
   .claude/scripts/lib/dec-write-lib.sh list --format md | head
   ```
4. Then re-run `validate-artifact.sh --type prd` on this cycle's PRD. It has no real `[ASSUMPTION decision]` tags (all mentions are in code spans) and 3 bare tags, which WARN.

## Proposed CHANGELOG lines

- Added: `grimoires/loa/decisions.yaml`, a tracked append-only decision ledger. Its single writer is `.claude/scripts/lib/dec-write-lib.sh` (`new`, `decide`, `confirm`, `reject`, `supersede`, `import`, `list`, `context`). It has a portable lock, verify-before-rename, attribution derived from the run context, and per-sprint pending files for linked worktrees. It requires jq and Mike Farah yq v4.
- Added: `validate-artifact.sh --type decisions`, which checks schema, transitions, ref grammars, artifact hashes and append-only content against `--base-file`.
  - `--type prd` now classifies `[ASSUMPTION fact|decision]` tags. A bare tag WARNs, and fails from 2026-11-13. Decision tags and `**Deferred:**` lines must cite a ledger row.
  - `--type sdd` WARNs on a Resolved open question without a DEC id.
- Added: `/decisions`, an operator-only command (`disable-model-invocation: true`) and the only path to `confirm`, decided-row `reject`/`supersede` and clearing the unattended marker.
- Added: a `## decisions` family in `grimoire-index.sh` (plus a `--tsv` mode) and a default-off SessionStart surface, `decisions.surface_at_session_start`, which prints pending rows inside the L6 data fence.
- Changed: the PRD and SDD templates gain a "Decisions taken on the operator's behalf" appendix rendered by `dec-write-lib.sh list`. The SDD Open Questions table gains a DEC column.
- Fixed: `validate-gitignore-state.sh` no longer reports a path re-included by a `!` negation as gitignored drift.

## Decisions taken beyond the SDD

1. **`decided_by` on proposed rows.** The PRD and the sprint AC say a proposed row has `decided_by: agent`. SDD §3.1, D-3.11 and A31 say `decided_by` stays null until confirm and `proposed_by` records the voice. I followed the SDD mechanism. The AC's "decided_by: agent" is met as `proposed_by: agent, decided_by: null`. `list --decided-by`, `--not-decided-by`, the PR table's Voice column and the index's "Decided by" column all use `decided_by // proposed_by`. The alternative was setting `decided_by: agent` at proposal, which breaks A31 and the set-once rule.
2. **Unattended `--status open`.** Under an unattended signal, the default and any `--status proposed` land `proposed`. An explicit `--status open` stays `open`. An open row is a question, not a decision taken; FR-5 deferral needs one, and forcing it to proposed would require invented alternatives. The alternative was forcing every unattended write to proposed.
3. **CI and hook refusal scope.** These refusals apply to the live ledger and the pending file. `--file` fixtures are exempt, per D-3.14, so the suites run in CI. The brief's wording had no exemption.
4. **Negation handling in `validate-gitignore-state.sh`.** I changed it to ignore `!` matches. Without that, the remedy it recommends (a negation) kept warning, because it keys off `git check-ignore -v`. The alternative was deleting `.gitignore:149`, which the SDD forbids.
5. **Operator detection and session id.** An operator call is `--recorded-by decisions-command` in an interactive context; this is honest-limit attribution, per SDD §9. The session id comes from `CLAUDE_SESSION_ID`, falling back to `CLAUDE_CODE_SESSION_ID`, which this harness sets. A marker is stale when the session ids differ, provided both are known, or when it is older than the TTL.
6. **`import` and beads.** `import` does not run `br update --external-ref`. Beads operations are lead-only and tests must not touch beads, so it prints the repair line instead.
7. **Rejecting a decided row.** An agent's `reject` of a decided row exits 1 and points at `supersede`, because that is how an agent proposes a reversal. The alternative was a reject that silently writes `supersede_proposed_by` without a replacement row.
8. **"Source names the PRD".** This is matched on the PRD's basename (`prd.md`), so archived PRDs and absolute paths work.
9. **Pending sprint number.** `--sprint N` wins. Otherwise the writer takes `global_id` of `.sprints.current` from either checkout's `sprint-plan-state.json`, else `sprint-unknown` with a WARN.
10. **Cycle default.** It is `.cycle_id // .cycle` from run state, else `ledger.json` `.active_cycle`. Run state has no cycle field today, so the writer added the `active_cycle` fallback. The seed script passes `--cycle` explicitly: `cycle-128`, and `cycle-127` for the `c127-*` rows.
11. **Template appendix command.** The appendices use `--not-decided-by operator`, the PRD's form. It is equivalent to the SDD's `--voice agent,flatline,dissent`, and both filters are implemented, along with `--since`, `--source-prefix` and `--source-epic`.
12. **Index column label.** The index column is labelled "Decided by", per the AC and the brief; the SDD calls it "Voice". The PR-body table keeps "Voice", per §4.6.

## Fix round 1 (id allocation after the live seed)

**Root cause:** the test fixtures, not `dec-write-lib.sh`. Three suites built their fixture by copying the repository's live `grimoires/loa/decisions.yaml`. In the main checkout that file now holds the seeded rows, so every fixture started with them and `new` correctly returned the next id after them (DEC-0065).
- `dec-write-lib.bats` `setup()` copied it as both the temp project's ledger and `--file` fixture.
- `grimoire-index.bats` `_decisions_project` copied it too.
- `validate-artifact.bats` `_dec_project` copied it too.

The writer already reads only its resolved target. The max id, the verify base, the import target and `list` all take the target file, and the lock is keyed per target. I confirmed this before changing anything: in a scratch project whose live ledger held 15 rows, `new --file <fresh empty file>` returned DEC-0001.

**Fix:** the fixtures are now built from the tracked file's header comment plus `schema_version: 1` and `decisions: []`, so they never inherit live rows. `dec-write-lib.bats` gains an `empty_ledger` helper, and the other two suites use the same one-liner. `dec-write-lib.sh` is unchanged.

**New test:** "ids come from the target file only; a populated live ledger does not shift a fresh --file fixture" in `tests/unit/dec-write-lib.bats`.
1. It seeds 5 rows into the temp project's live ledger and copies that ledger to another path.
2. It writes to a fresh `--file` fixture and asserts `DEC-0001`, with exactly one row there.
3. It writes to the live ledger again and asserts it continues at `DEC-0006`.
4. It asserts the other copy is unchanged.

**Suite counts:** I ran these with the main checkout's populated live ledger (73 rows) copied into the worktree, then restored the empty ledger and re-ran dec-write-lib.

| Suite | Passing | Failing |
|---|---|---|
| `dec-write-lib.bats` | 44 | 0 |
| `validate-artifact.bats` | 51 | 0 |
| `grimoire-index.bats` | 12 | 0 |
| `loa-decisions-surface.bats` | 8 | 0 |
| `dec-write-lib.bats` (empty ledger restored) | 44 | 0 |

**Incremental patch:** `~/.cache/loa/cycle-128/s1-b-fix1.patch` covers the three test files only. It is the unstaged diff against the first patch's staged index, so it is incremental, not a full `git diff --cached`. I checked that both patches apply in order on a clean detached worktree of `e9f175a6`. Your test-43 change in the main checkout touches a different hunk, so it should not conflict.

## Review round 1 (CI/hook exemption keyed on the resolved path)

**Finding (advisory, from the dissent run):** the CI/hook write refusal exempted any call that passed `--file`. So `CI=1 dec-write-lib.sh new --file grimoires/loa/decisions.yaml …` was treated as a fixture and allowed. This held for a relative path, an absolute path, and a path to a pending file.

**Fix (`.claude/scripts/lib/dec-write-lib.sh`, `canon`, `file_kind`, `resolve_target`):** an explicit `--file` is now classified by its canonical path, computed as `pwd -P` of its directory plus the basename. There are three kinds:
- **live:** the target is this checkout's or the main checkout's `grimoires/loa/decisions.yaml`.
- **pending:** the target is `grimoires/loa/a2a/<one dir>/decisions-pending.yaml` under either root.
- **fixture:** anything else.

Live and pending targets get that kind's semantics:
- The CI, GITHUB_ACTIONS and LOA_HOOK_CONTEXT refusal applies.
- A pending target allocates `PEND-` ids.
- `confirm` and `supersede` refuse a pending target.

True fixtures stay exempt. `import --file <live>` goes through the same path, so under CI it is refused and leaves the pending file in place.

One addition goes beyond the finding. In a linked worktree, a `--file` that names a live ledger is refused, whether the worktree's own or the main checkout's, because worktrees write the pending file. Without this, a worktree could allocate DEC ids itself, which the single-writer rule (D-3.18) exists to prevent.

**New tests (`tests/unit/dec-write-lib.bats`):**
- **CI refusal by path:** for each of CI=1, GITHUB_ACTIONS=1 and LOA_HOOK_CONTEXT=1, `--file` refuses five targets: the live ledger given as an absolute path, a relative path and a `..`-containing path, and a pending file given as an absolute and a relative path. A temp fixture is still allowed.
  - The live ledger and the pending file stay unchanged.
  - `CI=1 import --from <pending> --file <live>` is refused and keeps the pending file.
  - Without CI, `--file grimoires/loa/decisions.yaml` writes the live kind and returns DEC-0001.
- **Worktree refusal:** in a linked worktree, `--file` naming either live ledger is refused.

**Suite counts:**

| Suite | Passing | Failing |
|---|---|---|
| `dec-write-lib.bats` | 46 | 0 |
| `validate-artifact.bats` | 51 | 0 |

**Incremental patch:** `~/.cache/loa/cycle-128/s1-b-fix2.patch` covers 2 files. It is the unstaged diff against the index that holds s1-b and fix1. I checked that `s1-b`, `s1-b-fix1` and `s1-b-fix2` apply in order on a clean detached worktree of `e9f175a6`.

## Audit round (two LOW findings)

### 1. Index sanitisation

**Fix (`.claude/scripts/grimoire-index.sh`, `emit_decisions`):** every emitted field now goes through the same cleaning as the session surface. That covers id, status, summary, source and voice.
- C0 and C1 control characters, tab and newline included, become spaces, and so do U+2028 and U+2029.
- `<` and `>` become the single guillemets ‹ and ›.
- Each field is capped at 160 code points.

Markdown `|` escaping is unchanged.

The previous version already flattened controls, tab and newline: its `[[:cntrl:]]` class matched C1 in jq, and the TAB-safe emit dates from the first patch. It did not touch angle brackets. Run on a hostile row, it printed `<script>` verbatim.

**Test (`tests/unit/grimoire-index.bats`):** "untrusted row text is cleaned in TSV, JSON and md". The fixture's summary holds a real TAB, LF, ESC and C1 NEL plus `<script>alert(1)</script>`, and its source holds a TAB, `<x>` and LF. The test first checks that the bytes are really in the file.
- TSV keeps 9 columns, and the summary and source cells equal the cleaned strings.
- The JSON title and the INDEX.md row equal the cleaned strings.
- None of TSV, JSON or md contains `<script>`, `<x>`, a control byte or a NEL.

### 2. `import --rewrite` scope

**Fix (`.claude/scripts/lib/dec-write-lib.sh`, `op_import`):** every `--rewrite` target is checked before anything is written, and any failure exits 1. A target must:
- not contain `..`;
- be an existing regular file, not a symlink;
- have a canonical path (via `canon`) under the canonical PROJECT_ROOT.

**Test (`tests/unit/dec-write-lib.bats`):** "import: --rewrite targets outside the project, with '..', symlinks or missing files are refused before any write".
- Each of four targets is refused with exit 1: a file outside the project, a path with `..`, a symlink pointing outside, and a missing file.
- After the refusals the ledger and the pending file are unchanged, and the outside file is untouched.
- An in-project file is then rewritten from the PEND id to DEC-0001.

### Note on writing patterns

The Write tool turns `\uXXXX` escapes into literal characters. I wrote these edits through a script, converted them back to escapes before applying, and confirmed that no shipped file holds a literal U+2028, C1 byte or ESC. The test builds its guillemets from octal bytes.

### Results

| Suite | Passing | Failing |
|---|---|---|
| `dec-write-lib.bats` | 47 | 0 |
| `grimoire-index.bats` | 13 | 0 |

**Incremental patch:** `~/.cache/loa/cycle-128/s1-b-fix3.patch` covers 4 files. It is the unstaged diff against the index that already holds s1-b, fix1 and fix2. I checked that all four patches apply in order on a clean detached worktree of `e9f175a6`.
