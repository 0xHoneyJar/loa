All good

# Sprint 259 review — round 2 (cycle-130 Sprint 2) — APPROVED

**Reviewer:** Senior Technical Lead (Claude Fable 5.1, `global.anthropic.claude-fable-5-1`)
**Date:** 2026-10-15
**Implementation:** `75d84262` (fix round r259-1 `67477489` on `6be23186`, plus the lead's round-2 integration edits `9c5a493d` and `75d84262`; base `4374c446`); reports `reviewer.md` (Feedback Addressed section), `reviewer-fix.md`, `reviewer-d.md`, `reviewer-e.md`, `reviewer-f.md`, `regrade-batch-1.md`, `survey.md`
**Dissent:** `adversarial-review.json` (round 2, fixture-free diff of the fix range `6be23186..67477489`, 14 files / 842 lines) — two voices (`codex-headless` gpt-5.5-pro: DISS-001; `claude-headless` companion: DISS-C-001 … DISS-C-004), `verdict_quality.status` APPROVED, consensus, chain_health ok, 0 rejected payloads. Round 1 is `engineer-feedback-r1.md` / `adversarial-review-r1.json` (companion timeout, KF-037 rec 10); shrinking the diff to the harness restored both voices.
**Local checks on `75d84262`:** `evals/tests/` 322/322, unit 20/20; `validate-suite.sh --smoke` 18 valid; `freeze.sh --smoke --check` OK (158 files, sha256 `30e1f2ad…`); image self-check 36/36 PASS on the re-frozen suite (`self-check-image.log`, rerun after the fix round; spot-checked again after the integration edits); trust-boundary scan clean.

## Round 1 items

Every round-1 finding is closed in `67477489`, each with a test that fails on `6be23186` and passes now (`reviewer-fix.md` has the method: temporary copies of the HEAD scripts):

- **HIGH-1 closed.** `remove_path` chmods only entries whose `lstat` is a real directory; `copy_tree` drops a symlink whose target is absolute or resolves outside the destination (a lexical check, then a realpath pass repeated until stable) and counts them as `grade.json.symlinks_dropped`; the snapshot tar filter's rejection of escaping symlink members is asserted with a real bundle. AG-19 grades a sandbox with an absolute, an escaping and a lexically-in-tree-but-really-escaping link twice: the probe directory keeps mode 0755, the three links are absent, two in-tree links survive.
- **MEDIUM-1 closed.** Grader 1.1.0: for `type: refactor` `hidden_tests` is the structural check and `test_command` the regression check at base and final; snapshot accuracy needs the structural check and the suite green on the tree the gate read; `structural` keeps its shape for the self-check; header and README updated. AG-7 rewritten; AG-20 grades then rows a refactor run: `hidden_test_pass_rate` is the structural rate and an untouched tree scores 0 (1.0.0 scored it 1.0).
- **MEDIUM-2 closed.** The eight D tasks list every file under `fixture/tests/`; `validate-suite.sh` enforces the rule for build types (VS-12: top-level, nested and symlinked files; review-catch exempt). Nine manifest entries changed; the suite was re-frozen (158 files, sha256 `30e1f2ad7015590227e9cc2fa25ca791e31867fec65289e4a41554e9e53357ba`).
- **MEDIUM-3 closed.** `all_pass` requires `rc == 0` and no timeout; `hidden_tests` and `regressions.base/final` carry `rc` and `timed_out`; the self-check and per-gate accuracy follow (AG-21: `1..1 ok 1` then exit 1 is not green and the reference self-check FAILs).
- **LOW-1 closed.** `bugfix-02`'s discarded-store case confirms address reuse through a weakref and `gc.collect()` (bounded at 500 allocations, stop after three reuses); ten consecutive base runs red on CPython 3.11, 3.12 and 3.13; the `success_criterion` reads six failed deterministically; the image self-check reads base 7/13, reference 13/13.
- **LOW-2 closed.** `regressions()` derives `newly_failing` from the exit statuses when a side is unparseable and sets `parse_error` (AG-22).

## Round 2 dissent findings (checked against the tree)

- **Fixed at integration — the self-check's suite-green rule accepted an unparseable fixture-suite run that exited 0 (DISS-001, codex, confirmed).** `self_check` computed `suite_green` from counts and exit status only, so an unparsed run (fallback `passed == total`) passed. `9c5a493d` adds `not r["parse_error"]` to the rule; AG-21's regression command now prints TAP so its "exit 0 passes" branch is a parsed, green run (`75d84262`).
- **Fixed at integration — snapshot trees relied on the tar filter alone, which judges members in archive order (DISS-C-001, confirmed).** A link that escapes only through a later link passes `tarfile.data_filter`. `9c5a493d` runs the same `drop_escaping_links` realpath pass over every extracted snapshot tree and adds the count to `symlinks_dropped`; `put_file` already unlinks a symlink leaf and replaces a symlinked parent before writing, so restores never wrote through a link.
- **LOW-1 — `regressions` ignores a non-zero exit when both runs parse (DISS-C-002, confirmed as a consumer gap).** `9c5a493d` records `regressions.base_green` and `regressions.final_green` (`all_pass` of each run) so the data is in `grade.json`; the row writer and the Sprint 261 report still count `newly_failing` only. Follow-up `bd-m0hw7` (Sprint 261 report / row writer): a bug-fix final tree whose suite exits non-zero while every parsed case passes must not read as zero regressions.
- **Fixed at integration — a refactor task's `regression_command` was silently ignored (DISS-C-003, confirmed).** `validate-suite.sh` now refuses a non-null `regression_command` on a refactor task (VS-13); the README already said it stays null.
- **Refuted — the manifest changed `bugfix-02`'s hidden test hash without the test changing (DISS-C-004).** The dissent diff excludes `tasks/*/hidden/` by design (the fixture-free helper, so the companion voice fits its budget); `git show --stat 67477489` lists `tasks/bugfix-02/hidden/tests/test_memo_freshness.py`, and `freeze.sh --smoke --check` is OK on the committed tree.

The lead's integration edits (`9c5a493d`, `75d84262`: 2 grader hardenings, 1 validator rule, 2 test updates) are small, tested, and read by the audit dissent (run 3) on the full fixture-free sprint diff; this is the Sprint 258 practice.

## Acceptance criteria

AC-2.1 … AC-2.10 met (evidence in `reviewer.md` and its Feedback Addressed section; AC-2.1's manifest hash is now `30e1f2ad…`; AC-2.3's self-check rerun 36/36 on the re-frozen suite; AC-2.10's suites green at `75d84262`). The floor is untouched.

## Verdict

APPROVED — Sprint 259 proceeds to the security audit.

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":1},"excluded":0,"sprint_id":"sprint-259","ts":"2026-10-15T06:20:00Z"} -->
