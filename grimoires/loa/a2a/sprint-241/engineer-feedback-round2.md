All good

Sprint 1 has been reviewed and approved. All acceptance criteria met. Observations documented and non-blocking. See Observations below.

# Sprint 1 (global 241) Review Feedback — round 2

**Reviewer:** Senior Tech Lead Reviewer Agent (Fable 5.1, inline under `/run sprint-plan`)
**Date:** 2026-09-23
**Sprint Reference:** grimoires/loa/sprint.md — Sprint 1: Fence precision
**Implementation Report:** grimoires/loa/a2a/sprint-241/reviewer.md (§Review round 1 → fixes)
**Previous round:** grimoires/loa/a2a/sprint-241/engineer-feedback-round1.md (6 HIGH, 2 MEDIUM, 2 LOW) · cross-model dissent `adversarial-review.json` (gpt-5.5-pro, 1 BLOCKING: DISS-001)

---

## Overall Assessment

Every round-1 item is fixed in the code, not the report, and each fix carries a corpus row and a named twin, so the gate that missed the holes now catches them. I re-ran the round-1 probe set and the fixture-repo probes against `87b7522c`: all 26 hand-built bypasses block; the only two shapes that pass are the two intended allows (`rm -rf /tmp/x/*`, pre-sprint behaviour, and `T=$(mktemp -d); rm -rf "$T"`). The corpus stands at 47 benign / 50 dangerous / 3 residual with 47/47 and 50/50; the three suites are 299/299; `repo-map-gen.sh --validate` is consistent and the checksum regen shows 0 drift. The design rule from `sdd.md` §6 — "every D-1.x relaxation applies only when its predicate is positively established" — now holds for the three text-proof predicates as well as the shape predicates. `reviewer.md` §AC Verification is complete with `file:line` evidence and the round-1 table names every fix by line.

Complexity: `_fr2_scratch_cwd` grew to 31 lines and `_fr11_all_merged` to 40, both under the ceiling; the shared `_fr2_rebindable` removed the duplicated denylist. Lean already. Ship.

**Verdict:** APPROVED

---

## Observations

### 1. Conservative false-positive classes introduced by the fixes (documented, not in the corpus)

- **MEDIUM** (confidence: high) `.claude/hooks/safety/block-destructive-bash.sh:1273-1283` — `_fr2_rebindable` is a whole-command denylist: a benign `T=$(mktemp -d); source ./env.sh; cp out "$T"; rm -rf "$T"` or any command that mentions `read`, `local`, `declare` or `unset` anywhere now loses the mktemp allowance and blocks as FR-2-AMBIGUOUS. This is the intended trade (a text fence cannot scope bindings), but it is a new FP class with no corpus row; add one `residual` row so the next precision pass measures it.
**Suggestion:** corpus row `R04` with `expect: residual`.

- **LOW** (confidence: high) `.claude/hooks/safety/block-destructive-bash.sh:1352-1354` — `_fr2_scratch_cwd` voids on `exec` and `source` anywhere before the segment; `cd /tmp/x && exec 3>log && rm -rf work` (fd redirection, not a program exec) blocks. Rare; acceptable.

### 2. Helper ergonomics

- **LOW** (confidence: high) `.claude/scripts/git-branch-prune.sh:49` — `--help` exits 2 like a usage error; conventional is 0. Cosmetic.

---

## Previous Feedback Status

| Issue | Status | Notes |
|-------|--------|-------|
| H-1 newline-initial rebinding (`"\n"` = letter n) | Resolved | `_fr2_var_value` regex in `$'…'`; probe `T=$(mktemp -d)⏎T=/home/me⏎rm -rf "$T"` → 2; D33 |
| H-1 `+=` / `readonly` / `NAME[` / `getopts` | Resolved | `_fr2_rebindable` (`:1273-1283`); probes → 2; D34–D37 |
| H-2 `$TMPDIR` mutation | Resolved | `_fr2_rebindable TMPDIR` + suffix captured before later `=~` (`:1323-1333`); probes → 2; D38–D40 |
| H-3a second identical rm segment | Resolved | `_seg_before` from cursor (`:1437-1441`); `cd /tmp/x && rm -rf work; cd / && rm -rf work` → 2; D41; both-after-one-cd still 0 |
| H-3b pushd / eval / inline shell | Resolved | voiders + non-statement-initial `cd` count (`:1345-1370`); probes → 2; D42–D44 |
| H-4 first-segment-only FR-1.1 / FR-1.3 | Resolved | both helpers iterate segments; fixture: compound forms → 2, `git branch -D main` → 2, single merged → 0; D45 |
| DISS-001 temp root through a glob | Resolved | `_fr2_temp_glob_re` → FR-2-BLOCK (`:1551`), `$TMPDIR/*` refused (`:1332`); `/tmp/*`, `/var/tmp//*`, `"$TMPDIR"/*`, `$TMPDIR/*` → 2; `/tmp/loa-cache-*` → 0; D46–D49, B47 |
| Obs-1 SQL runner list | Resolved | `php -r`, rails, manage.py, artisan, alembic, dbt, atlas, mongosh, sqlx (`:822-826`); D50 |
| Obs-2 `"${timeout_cmd[@]}"` under `set -u` | Resolved | guarded expansion; header names the no-`timeout` residual |
| Obs-3 runtime gate vs corpus growth | Resolved | `baseline.json` `rows: 73`; gate scales per row (bats `:1576-1590`) |
| Obs-4 report/header mismatch on `timeout` | Resolved | helper header updated |

---

## Acceptance Criteria Check

| Criterion | Status | Notes |
|-----------|--------|-------|
| Corpus benign ≥ 80 %, dangerous 100 %; 216 existing cases green | Pass | 47/47, 50/50; fence suite 276 cases (216 + 4 gates + 56 named) all `ok` |
| Every relaxation has its dangerous twin | Pass | D01–D50 cover vocabulary, scratch cwd (incl. cursor, pushd, eval, inline shell), temp roots (incl. bare glob), `$TMPDIR` (incl. mutation), mktemp variables (incl. five rebinding vectors), SQL sinks, branch `-D` segments, checkout `--` segments |
| Runtime within 1.5× | Pass | 5314 ms over 100 rows vs 4061 ms over 73 (scaled limit 8344 ms) |
| `git-branch-prune.sh` bats: four cases | Pass | 13/13 |
| No other hook file changed; `hook-wiring.bats` green | Pass | `git diff 867cbc37 --stat -- .claude/hooks` lists one file; hook-wiring 10/10 |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (corpus lint gate green over 100 rows)
- [x] Input validation at the trust boundary — the six text-proof holes are closed and pinned by twins
- [x] No network in the hook; `gh` only in the helper, bounded, opt-out
- [x] Error messages keep the `BLOCKED [id]` grammar and redact via `emit_block`

---

## Code Quality Summary

**Strengths:** the review loop worked as designed — the corpus is now the artefact that would have caught its own gaps; one shared `_fr2_rebindable`; segment iteration in both git helpers; the `BASH_REMATCH` capture-first fix also removed a latent bug in the original `$TMPDIR` suffix check.

**Areas for Improvement:** the two FP classes above should become residual rows so the next pass measures them rather than rediscovering them.

---

*Generated by Senior Tech Lead Reviewer Agent*
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":2},"excluded":0,"sprint_id":"sprint-241","ts":"2026-09-23T04:22:00Z"} -->
