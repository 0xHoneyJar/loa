# Sprint 259 fix round 1 — implementer report (s2-fix)

Worktree `/home/merlin/Documents/thj/code/loa-wt-s2fix` at `6be23186`. The review it fixes is `grimoires/loa/a2a/sprint-259/engineer-feedback.md`, round 1, CHANGES_REQUIRED. The patch is `~/.cache/loa/cycle-130/patches/s2-fix.patch`. Nothing was committed, no docker or model call was made, and nothing under `.claude/` was touched.

## What was changed, per finding

- **HIGH-1 (DISS-001), symlinks in the grader.** In `evals/harness/ablation-grade.sh`:
  - `remove_path` (:256) walks with `followlinks=False` and calls `os.chmod` only on entries whose `lstat` is a real directory.
  - `link_escapes` (:296) rejects an absolute target, or one whose `normpath(join(rel_dir, target))` climbs above the tree.
  - `drop_escaping_links` (:305) is a second pass. It removes any link whose full `realpath`, through the other links, leaves the tree, and repeats until stable.
  - `copy_tree` (:322) keeps only in-tree relative links and returns the dropped count. `grade()` records that count as `grade.json.symlinks_dropped`, from the final copy, or from the `pr/` copy for review-catch.
  - The snapshot tar filter, `tarfile.data_filter`, is confirmed by a test with a real bundle. The test shows absolute and escaping symlink members skipped and in-tree links kept. The filter normalises `./x` to `x`.
- **MEDIUM-1, refactor semantics.** In `grade()` (:1174), a refactor uses the structural command for `hidden_tests`, and its static floor is the structural file's case count (:464). `test_command` is the regression check, giving `regressions` from base vs final. `structural` keeps its 1.0.0 shape: `suite_green_base` and `suite_green_final` are `all_pass` of the base and final suite runs. The snapshot runs (:1210) use the structural command. For refactor, a gate's tree is green only when the structural check AND the suite are green on it. The self-check (:1305) reads `hidden_tests` and `regressions.final` for every build type. The header and the README's `grader_protected` paragraph, refactor table row and refactor paragraph are updated.
- **MEDIUM-3 (DISS-002), exit status.** `summary()` (:712) records `rc` and `timed_out`. `all_pass()` (:717) requires `rc == 0 and not timed_out`. The self-check applies the same rule to the summaries. `regressions.base` and `.final` carry `rc` and `timed_out`.
- **LOW-2 (DISS-003), unparseable regression commands.** `regressions()` (:730) handles a missing summary on either side and sets `regressions.parse_error`:
  - Base unparsed: every fallback id when the base exited 0 and the final run failed (non-zero exit or timeout).
  - Base parsed, final unparsed: every base-passing case when the final run failed.
  - Otherwise: none.
- **MEDIUM-2, `grader_protected`.** The eight D tasks now list every file under `fixture/tests/`: `bugfix-01` adds `tests/test_pages.py` and `tests/test_render.py`; `bugfix-02` `tests/test_layers.py`; `bugfix-03` `tests/test_tags.py`; `bugfix-04` `tests/test_resolve.py`; `refactor-01` `tests/test_ledgerio.py`; `refactor-02` `tests/test_report.py`; `refactor-03` `tests/test_fetchq.py`; `refactor-04` `tests/test_jobboard.py`. A new rule in `evals/harness/validate-suite.sh` (:293) refuses a build task whose list misses any file or symlink under `fixture/tests/`, recursively, with one line per file. The rule is documented in the header (check 1). The usage range moves from `2,45p` to `2,46p` for the added header line. Every reference patch touches only `src/`, so protecting the fixture tests cannot break a reference.
- **LOW-1, deterministic discarded-store case.** `tasks/bugfix-02/hidden/tests/test_memo_freshness.py::test_a_new_store_never_sees_a_discarded_one` now works as follows:
  - Each store is read once, then dropped; a weakref plus `gc.collect()` confirms it was freed and its address is recorded.
  - A later store whose `id()` is a recorded address must read its own value.
  - The loop is bounded at 500 and stops after three reuses.
  - An implementation that keeps every store alive frees none, so the case passes vacuously.
  - The `bugfix-02` `success_criterion` now reads "6 failed" deterministically.

## Proofs

**LOW-1.** Host 3.13, `python3 -P -m pytest -q -p no:cacheprovider tests` (with `-I` the user-site pytest is hidden):
- base, 10 consecutive runs: `6 failed, 7 passed` each time;
- reference, 10 runs: `13 passed` each time;
- the case alone (`-k discarded`) at base, 10 runs: `1 failed, 7 deselected` each time;
- uv CPython 3.11.14 and 3.12.12 through a plain driver: base `10 FAIL`, reference `10 PASS` on each version.
A reuse probe of the base code found the first reused address at allocation 1–5 on every run of 3.11, 3.12 and 3.13, with 484–497 of 500 later reads stale.

**MEDIUM-2.** `validate-suite.sh --root <copy with the HEAD task.yaml files> --smoke` reports 9 violations over 18 tasks, rc 1, one per unprotected file. With the patch: `validate-suite: OK — 18 task(s) valid`.

**Host self-check.** `ablation-grade.sh --self-check {base,reference[,noisy]} --executor host` on the frozen suite: 36/36 PASS. Refactor reads, for example, `base refactor-01: PASS structural 0/8, suite green` and `reference refactor-01: PASS structural 8/8, suite green`. Bug-fix reads, for example, `base bugfix-02: PASS hidden 7/13, fixture suite 5/5`.

**Freeze.**
```
freeze: wrote MANIFEST.sha256 (158 files, sha256 30e1f2ad7015590227e9cc2fa25ca791e31867fec65289e4a41554e9e53357ba)
freeze: OK — 158 files match MANIFEST.sha256 (sha256 30e1f2ad7015590227e9cc2fa25ca791e31867fec65289e4a41554e9e53357ba)
validate-suite: OK — 18 task(s) valid in …/grimoires/loa/evals/ablation-2.0
```
Exactly nine manifest entries changed: eight `task.yaml` files and one hidden test. The old sha256 was `ab1d631f…`. `no-secrets.sh` passes on all eight changed tasks, and the trust-boundary grep is clean.

## Tests added or changed

Every new case was run against the HEAD scripts through temporary executable copies, deleted afterwards. Each failed there and passes with the patch:
- **AG-7, updated:** refactor `hidden_tests` is the structural check (`1/1 0 false`, untouched `0/1 t1`), and `regressions` comes from the suite. A behaviour-breaking refactor gives `newly_failing t1,t2`. HEAD fails on the `hidden_tests` shape.
- **AG-19, new:** absolute `evil -> <probe>` (0755), escaping `src/up -> ../../../probe-dir` and `hop -> sub/root/..` (lexically in-tree, really the parent) are graded twice. The probe stays 755, the three links are absent, `symlinks_dropped` is 3, and the in-tree links `tests/alias` and `sub/root -> ..` survive. In the snapshot variant, the bundle's absolute and escaping links are skipped and the probe is untouched. HEAD fails on `stat -c %a probe = 755`: the second grade chmodded it to 700.
- **AG-20, new:** refactor gate accuracy and the row:
  - accuracy needs the structural check AND the suite green;
  - `ablation-row.sh` gives `hidden_test_pass_rate` 1 with `regressions` 2 for a behaviour-breaking refactor, and 0 with 0 for an untouched tree (1.0.0 scored that tree 1.0).
- **AG-21, new:** a runner that prints `1..1` and `ok 1`, then exits 1, gives `hidden_tests` 1/1 with `rc: 1`. The gate's APPROVED is inaccurate, and `--self-check reference` FAILs with exit 1. The same runner exiting 0 PASSes.
- **AG-22, new:** a bash regression command printing nothing, exiting 0 at base and 1 at final, gives `newly_failing t1` and `parse_error: true`. Green at both ends gives none.
- **VS-12, new:** a missing file at the top of `tests/`, in a subdirectory or as a symlink is listed for bug-fix and refactor. Listing them validates. Review-catch is exempt.

**bats counts.** Before: `evals/tests/` 316/316. After: 321/321, with `ablation-grade.bats` at 22 and `validate-suite.bats` at 12.

## DECISION bullets
- DECISION: grader_version 1.0.0 → 1.1.0: refactor grades, green and symlink handling differ, so a 1.0.0 grade.json is distinguishable.
- DECISION: beyond the brief's lexical rule, copy_tree runs a realpath second pass (drop_escaping_links) that removes links escaping through other links (AG-19 `hop -> sub/root/..`), repeated until stable; both passes count in symlinks_dropped.
- DECISION: symlinks_dropped is in every grade.json (0 by default; the final copy for build, the pr/ copy for review-catch), placed before contaminated; links skipped by the snapshot tar filter are not counted.
- DECISION: remove_path chmods an entry only when lstat says it is a real directory (covers islink and anything else).
- DECISION: structural keeps its 1.0.0 shape (rc and timed_out popped); hidden_tests carries rc and timed_out; regressions.base/final carry {passed, total, rc, timed_out}; regressions.parse_error is always present as a boolean.
- DECISION: for refactor the regression check is test_command even if a task set regression_command (none does); the hidden total floor is the structural file's static case count.
- DECISION: base parsed with the final run unparsed counts every base-passing case as newly failing only when the final run failed (non-zero or timeout); 1.0.0 counted them whatever the exit status.
- DECISION: a parsed final run whose cases all pass but which exits non-zero gives newly_failing [] (no case to attribute); it is visible in regressions.final.rc and makes the self-check's suite red.
- DECISION: the self-check base mode still requires a failing hidden case (passed < total), not merely "not green": a base that fails only by exit status does not pass base.
- DECISION: LOW-1 uses real address reuse confirmed by weakref, not a monkeypatched id() (implementation-coupled) or a weakref on the memoised value (would fail a correct fix that keeps stores alive); a store never freed makes the case pass vacuously.
- DECISION: the validator rule covers files and symlinks under fixture/tests/ recursively, for build types only, one violation line per missing path.
- DECISION: validate-suite.sh and validate-suite.bats were edited although the brief's ownership list does not name them: the feedback and the brief require the rule and a VS case.
- DECISION: AG-19's probe directory is under the test's $T (absolute, outside the run dir) rather than /tmp/<probe>, so teardown cleans it.

## Could not do / limitations
- No docker. The image self-check (36 cases) and the image-side pytest proofs are for the lead to rerun. The host self-check is 36/36.
- `ablation-row.sh` was not changed: it already reads `hidden_tests`, and the row's `regressions` is the length of `newly_failing`.

## Handoff notes for the lead
- `freeze.sh` and `validate-suite.sh` accept `__pycache__` inside a fixture. My first reuse probe ran inside the bugfix-02 fixture, and freeze then hashed nine `.pyc` files (167 files). I deleted the strays and re-froze at 158. A validator rule refusing caches in fixtures would close this. It is not in this round's scope.
- `python3 -I -m pytest` finds no pytest on this host, because pytest lives in the user site. Proofs used `-P`, as the grader's host mode does.
- The new manifest digest is `30e1f2ad…57ba`. AC-2.1's hash moves, and the CHANGELOG and decisions need the lead's rows.
