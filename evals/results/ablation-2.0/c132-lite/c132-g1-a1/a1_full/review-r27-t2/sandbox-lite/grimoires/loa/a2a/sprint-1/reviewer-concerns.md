# Reviewer concerns — sprint-1 (PR: cycle-131 sprint-263, 35 files)

Phase 2 notes from the primary reviewer. The change under review is `pr/head.diff`; files under `pr/head/`.

## Suspected defects

1. `tests/unit/adversarial-review-budget-scale.bats` BSC-9 asserts the *live* `.loa.config.yaml` has no
   `budget_scale` key under either gate, while the same PR adds `budget_scale: fixed` to
   `.loa.config.yaml.example` (whose header says to copy sections into the live file). Any operator who
   copies the flatline section, or who enables `diff` (as this workspace's live config does), gets a red
   unit test. A test must not depend on an operator-owned, untracked file.
2. `evals/tests/ablation-grade.bats` AG-50 reads `evals/tests/fixtures/c131-oracle/<run>/{transcripts,task,dotclaude}`
   and pins exact results against "curated" `manifests/pr-17.json` and `manifests/v1/`. None of those
   fixtures or manifests are in the diff (35 files, no `evals/fixtures/review-prs/manifests/*`, no
   `evals/tests/fixtures/c131-oracle/*`). The PR title claims "curated multi-site labels, versioned re-grade".
3. `evals/graders/recall-vs-defects.sh` `close_line`: `CLOSE_ONE = \{.*\}\s*(?:#.*)?$` + `"{" in header`
   treats any function header whose trailing comment contains a `}` (e.g. `f() {  # writes ${OUT}`) as a
   one-line function, so its body gets no scope. Also the `}` indentation compare uses raw `len(t)-len(t.lstrip())`
   while header indentation used `expandtabs(8)` — tab-indented bash never finds its closing brace.
4. `evals/harness/lib/sandbox-mount.sh` `cmd_check` clause (d): "exactly the base commit over every ref" and
   "fsck --unreachable reports nothing" — any `git commit`/`git stash`/`git add; git reset` by the agent in the
   sandbox fails `oracle_closed` post-run → infrastructure_error → the arm is paused (a1_full in the suite).
   Only the "no later-only pinned blob / no remote / no alternates" parts are oracle-relevant.
5. `evals/harness/ablation-grade.sh` `repo_name_exempt`: the unit is the backtick span, so a bare
   `` `0xHoneyJar/loa` `` is exempt whenever the fixture holds the token anywhere; `gh api repos/`0xHoneyJar/loa`/…`
   would pass the contamination scan on pr-18.
6. `evals/harness/ablation-row.sh` `evkv` takes the LAST `key=` line; `took-effect.sh evidence_line`,
   `sandbox-mount.sh read_evidence` and `check_mount_closed` (`sed -n '1p'`) take the FIRST; `pipeline-run.sh`
   takes the last for copy_source. Inconsistent evidence reading.
7. `recall-vs-defects.sh valid_cite`: a range whose end is past EOF credits nothing even when its first line
   is valid (ordering of the two validity rules), while `file:N` alone credits.
8. `ablation-grade.sh oracle_scan`: `exposed_unknown` is only emitted when no range/must_match hit at all in a
   section; the header comment says "every other defect of that file".
9. `.loa.config.yaml.example` now writes `budget_scale: fixed` explicitly, so copying it flips
   `CONF_BUDGET_SCALE_SET` and changes the envelope shape (adds reason/budget_* keys) despite "absent key is
   the shipped gate byte for byte".
10. No CHANGELOG entry in the diff; `PR.md` is a one-line title (no AC walkthrough).

## Areas I'd like a second opinion on

- `_sm_oracle_py diff_paths` hunk-count tracking and `header_names` on unusual `diff --git` headers.
- `oracle_plan` / `split_segments` / `classify` edge cases (false positives via `.` or `..` tokens, `cd -`).
- `ablation-report.py` partition keys (`"2 · pin … · rule …"`) flowing into `version_order` callers.
- jq validation block in `ablation-row.sh` (`positions_rule`, `need` on 1.4 fields).
- `_normalize_finding_for_validation` jq concatenation and the schema-enforced numeric-anchor branch.
