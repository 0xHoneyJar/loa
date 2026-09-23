# Sprint 1 (global 241) Review Feedback — round 1

**Reviewer:** Senior Tech Lead Reviewer Agent (Fable 5.1, inline under `/run sprint-plan`)
**Date:** 2026-09-23
**Sprint Reference:** grimoires/loa/sprint.md — Sprint 1: Fence precision
**Implementation Report:** grimoires/loa/a2a/sprint-241/reviewer.md

---

## Overall Assessment

The corpus, the runner, the gates and the helper are well built and the report's AC Verification is complete and specific. The relaxations themselves are sound where their predicate is a *path shape* (vocabulary, temp roots, generated paths, SQL sink) but three of the *proof-by-text* predicates admit inputs their own design forbids. I replayed hand-built twins through the committed hook (`223012f0`) and the pre-sprint hook (`223012f0^`): eight shapes that blocked before now pass, and every one of them ends in a recursive delete or checkout outside the proven target. The SDD's rule for this sprint is quoted verbatim in `sdd.md` §6: "every D-1.x relaxation applies only when its predicate is positively established". These are predicate holes, not corpus gaps, so they block.

Pre-existing behaviour that is *not* a regression (verified against `223012f0^`): `rm -rf /tmp/*` and `rm -rf /tmp/x/*` were already allowed by the old `/tmp/.+` allow entry; `bash -c '…'` wrapping is an accepted bypass class (hook header, SDD §11) — but see H-4 for how the new scratch rule widens it.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Once-bound variable proof — rebinding vectors the text check misses

- **HIGH** (confidence: high) `.claude/hooks/safety/block-destructive-bash.sh:1240` — `_fr2_var_value` builds its assignment regex in a double-quoted string, so the `\n` alternative is the literal letter `n`, not a newline: a second `T=` at the start of the *next line* is never counted. `T=$(mktemp -d)⏎T=/home/me⏎rm -rf "$T"` → hook exit 0 (was 2). Multi-line commands are the normal shape of Claude Code Bash calls.
**Required Fix:** `local re=$'(^|[;&|(]|\\n)…'` (ANSI-C quoting, as `_fr2_scratch_cwd` already does at `:1303`), and a twin in the corpus and the named cases.

- **HIGH** (confidence: high) `.claude/hooks/safety/block-destructive-bash.sh:1245-1250` — the rebind denylist omits `NAME+=`, `readonly NAME=`, array element `NAME[…]=`, and `getopts … NAME`; each rebinds `T` after the trusted `mktemp` binding and none is counted as an assignment (the assignment regex requires `NAME=` at a statement start with only an optional `export`). Verified: `T=$(mktemp -d); T+=/../..; rm -rf "$T"` (deletes `/`), `T=$(mktemp -d); readonly T=/; rm -rf "$T"`, `T=$(mktemp -d); T[0]=/; rm -rf "$T"`, `T=$(mktemp -d); getopts a: T; rm -rf "$T"` → all exit 0 (all were 2).
**Required Fix:** treat any of `NAME+=`, `NAME[`, `readonly`, `getopts`, `select NAME in` as rebinding (return 1), alongside the existing `eval/read/declare/…` list; factor the denylist into one `_fr2_rebindable NAME` helper so the `$TMPDIR` branch can share it (next finding).

### 2. `$TMPDIR` proof — checks the hook's environment, not the command's mutations

- **HIGH** (confidence: high) `.claude/hooks/safety/block-destructive-bash.sh:1281-1287` — the `$TMPDIR` branch only refuses when the text contains `TMPDIR=`; it never applies the rebind denylist. With a real temp `TMPDIR` in the environment: `read TMPDIR <<< /home/me; rm -rf "$TMPDIR"` → 0; `TMPDIR+=/../..; rm -rf "$TMPDIR"` → 0 (resolves to `/`); `unset TMPDIR; rm -rf "$TMPDIR/x"` → 0 (deletes `/x`). All three were 2.
**Required Fix:** the `$TMPDIR` branch must return 1 when `_fr2_rebindable TMPDIR` holds (including `TMPDIR+=`, `unset`, `read`, `for TMPDIR in`, `${TMPDIR:=`), not only on `TMPDIR=`.

### 3. Scratch-cwd proof — evaluated against the first identical rm segment, and blind to other cwd changes

- **HIGH** (confidence: high) `.claude/hooks/safety/block-destructive-bash.sh:1475` — `_seg_before="${_fr2_cmd%%"$rm_segment"*}"` cuts at the *first* occurrence of the segment text, while the loop already maintains a left-to-right cursor (`_fr2_remaining`, `:1347`, `:1369-1370`) precisely so that "repeated identical rm segments each resolve against THEIR OWN preceding text". `cd /tmp/x && rm -rf work; cd / && rm -rf work` → 0: the second `rm -rf work` runs in `/` but is judged by the text before the first. Was 2.
**Required Fix:** use `_seg_prefix` (the cursor-derived prefix computed two lines above) as the "text before" argument; add the twin.

- **HIGH** (confidence: medium) `.claude/hooks/safety/block-destructive-bash.sh:1301-1320` — `_fr2_scratch_cwd` recognises only `cd` as a cwd change. `cd /tmp/x && pushd /home && rm -rf work` → 0; `cd /tmp/x && eval "cd /home" && rm -rf work` → 0; `cd /tmp/x && bash -c "cd /home && rm -rf work"` → 0. All were 2. The first two are plain shell; the third is the accepted `bash -c` class, but the new rule turns a previously-blocked shape into an allowed one *because* of a preceding safe `cd`, which is the wrong direction for an accepted gap.
**Required Fix:** the scratch proof is void (return 1) when the text before the segment contains `pushd`, `popd`, `eval`, `-c ` / `-lc ` after a shell name, `source`/`.`, or a `cd` token that is *not* statement-initial (a quoted or nested `cd` means the true cwd is unknown). Conservative false positives here are acceptable; the corpus has no such benign row.

### 4. FR-1.1 and FR-1.3 — only the first segment of a multi-statement command is inspected

- **HIGH** (confidence: high) `.claude/hooks/safety/block-destructive-bash.sh:635` — `_fr11_all_merged` takes `head -1` of the `git branch` segments, so a merged name in the first segment vouches for every later one. Fixture repo (merged-br merged, wip-br not): `git branch -D merged-br; git branch -D wip-br` → 0 and `… && …` → 0; `git branch -D wip-br` alone → 2. Both compound forms were 2 before the sprint. This is exactly the "loses unmerged work" case the rule exists for.
**Required Fix:** iterate every `git branch` segment (drop `head -1`); a segment whose flags include the force-delete family must have ≥ 1 name and every name must be an ancestor; also refuse `main`/`master` by name (the helper already does — `git branch -D main` on the fixture is 0 today).

- **HIGH** (confidence: high) `.claude/hooks/safety/block-destructive-bash.sh:737` — same `head -1` in `_fr13_all_generated`: `git checkout -- dist/x.js; git checkout -- src/app.ts` → 0 (was 2); in the fixture, `git checkout -- dist/x.js; git checkout -- a` → 0 and overwrites the hand-written `a`.
**Required Fix:** iterate every `git checkout --` segment; every operand of every segment must qualify.

---

## Observations

### 1. SQL sink list

- **MEDIUM** (confidence: high) `.claude/hooks/safety/block-destructive-bash.sh:797-798` — `php -r "…DROP TABLE t…"` → 0 (PHP's inline flag is `-r`, not `-e`); Rails (`rails runner`, `rails dbconsole`), Django (`manage.py shell -c` / `dbshell`), Laravel `artisan tinker`, `alembic`, `dbt`, `atlas`, `mongosh` are absent. Was 2 for all of them. The SDD accepts a bounded list with the residual documented; adding `php -r`, `rails`, `manage.py`, `artisan`, `alembic`, `dbt`, `atlas` is cheap and the corpus has no benign row that mentions them.

### 2. Portability of the helper

- **MEDIUM** (confidence: high) `.claude/scripts/git-branch-prune.sh:73` — `"${timeout_cmd[@]}"` with an empty array under `set -u` is an unbound-variable error on bash < 4.4 (macOS ships 3.2); `.claude/rules/shell-conventions.md` prescribes `${timeout_cmd[@]+"${timeout_cmd[@]}"}`. On macOS without coreutils the helper aborts inside `squash_merged` instead of probing.

### 3. Runtime measurement noise

- **LOW** (confidence: medium) `tests/unit/block-destructive-bash.bats:1576-1585` — the 1.5× gate compares 81 rows against a 73-row baseline and the three post-fix runs span 2104–4401 ms on the same code; the gate is meaningful only because the floor is `base + 2000`. Record the row count next to `runtime_ms` in `baseline.json` (or per-row mean) so a future corpus growth does not read as a regression.

### 4. Report accuracy

- **LOW** (confidence: high) `grimoires/loa/a2a/sprint-241/reviewer.md` §Security — states the helper "runs unbounded only where `timeout` is absent … documented in the header as the residual"; the helper header does not say so. Add the sentence to the header or drop it from the report.

---

## Incomplete Tasks

None by scope — all seven tasks delivered; the blocking items above are defects inside Tasks 1.2, 1.5 and 1.6.

---

## Acceptance Criteria Check

| Criterion | Status | Notes |
|-----------|--------|-------|
| Corpus benign ≥ 80 %, dangerous 100 %; 216 existing cases green | Pass (as measured) | 46/46, 32/32; 265 fence cases green — but the corpus lacks the twins above, which is why the gate did not catch them |
| Every relaxation has its dangerous twin | Fail | rebinding by newline / `+=` / `readonly` / array / `getopts`, `$TMPDIR` mutation, second identical rm segment, `pushd`/`eval`, multi-segment `branch -D` / `checkout --` have no twin |
| Runtime within 1.5× | Pass | 4401 ≤ 6091 ms |
| `git-branch-prune.sh` bats: four cases | Pass | 13/13 |
| No other hook file changed; `hook-wiring.bats` green | Pass | verified in `git diff 94b5302f..223012f0 --stat` |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (corpus lint gate green)
- [ ] Input validation at the trust boundary — the proof-by-text predicates accept the inputs listed under Changes Required
- [x] No network in the hook; `gh` only in the helper, bounded, opt-out
- [x] Error messages keep the `BLOCKED [id]` grammar and redact via `emit_block`

---

## Code Quality Summary

**Strengths:** the corpus-as-gate design; `_fr2_plain_relative`'s strict character discipline; temp-path check placed before the catastrophic list with bare roots still blocked; the helper's restore hint; tests that run the hook from a fixture repo rather than mocking git.

**Areas for Improvement:** the three text-proof predicates each re-derive "what can change this name / this cwd" independently — one shared `_fr2_rebindable` and one shared segment-iteration idiom (for FR-1.1/FR-1.3) would have prevented four of the six blocking items. Complexity: `_fr2_value_allowed` is 30 lines, `_fr2_var_value` 32, both under the 50-line ceiling. Lean already for the surface it covers; fixes above add lines, not abstractions. net: +25 lines expected.

---

## Next Steps

1. Fix the six HIGH items; add each probe above as a corpus dangerous row (D33+) and as a named twin.
2. Re-run `run-corpus.sh`, the three suites, and the probes in this file against the new hook.
3. Update `reviewer.md` (Test-first record + the header sentence) and request `/review-sprint sprint-1` again.

---

*Generated by Senior Tech Lead Reviewer Agent*
<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":6,"medium":2,"low":2},"excluded":0,"sprint_id":"sprint-241","ts":"2026-09-23T04:14:20Z"} -->
