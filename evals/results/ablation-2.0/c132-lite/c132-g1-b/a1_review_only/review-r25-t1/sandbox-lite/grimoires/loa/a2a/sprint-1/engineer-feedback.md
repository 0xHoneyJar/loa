# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)

---

## Overall Assessment

The change under review is `pr/head.diff`: grader 1.2.11 (basename-collision cleanup), per-task-kind run caps in `run-ablation.sh` and `lib/arms-common.sh`, the `--types` jq fix, the KF-048 codex credential handling (placeholder refresh token in `pipeline-run.sh`, access-token pre-flight in `run-ablation.sh`), suite v2 metadata, and the bats updates.

Most of the change is sound. The `--types` fix is correct (`.type as $t | … | index($t)` indexes the list with the task's type, head/evals/harness/run-ablation.sh:565). The per-kind cap plumbing is consistent end to end: `cap_for` feeds dispatch (run-ablation.sh:1186), the assumed charges (run-ablation.sh:1043, 1284, 1322), the in-flight reserve is the max cap over the plan's kinds (run-ablation.sh:850-854) and `--resume` takes all three caps from MANIFEST and ignores `--run-cap` (run-ablation.sh:447-452); `spend_charge`/`budget_gate` keep backward-compatible defaults (arms-common.sh:128, 143). `make_home` writes the placeholder-refresh copy at 0600, keeps every other key, never writes the host file, and degrades to a WARN on an unreadable file (pipeline-run.sh:611-645); the pre-flight decodes only the JWT payload and prints no token material. Tests RAB-22…34, AG-35 and the three KF-048 pipeline cases cover the stated behaviours.

The blocking problem is in the grader's new `remove_colliding`. It is meant to stop pytest's "import file mismatch" abort from failing a correct solution, but its reserved set is every `.py` basename under the fixture's `tests/` (helpers included, as the 1.2.11 header itself says: `from helpers import …`, `import _oracle_x`), and its removal walk covers the whole tree. An agent that adds `src/<pkg>/helpers.py` has its implementation deleted before the hidden suite runs, so a correct solution is graded as failing: the same damage class the fix targets, now introduced for a common module name. The fix is also incomplete for directory-shaped overlays. Both the primary (gpt-5.5-pro) and companion (claude-headless) dissent voices independently confirmed these two findings.

Process note: `reviewer.md` is the PR description only. It carries no `## AC Verification` section and no record of the bats run, formatter or shellcheck gate (FAST-GATE). The review environment states those artifacts do not exist here, so this is recorded as an observation rather than as the automatic trigger; the verdict stands on the code findings.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Grader correctness — `remove_colliding` deletes agent implementation modules

- **HIGH** (confidence: medium) `head/evals/harness/ablation-grade.sh:1086-1087` — `reserved` is seeded with every `.py` basename under any fixture directory named `tests/` or `test/` (only `__init__.py` and `conftest.py` are excluded), not just the modules pytest collects (`test_*.py`, `*_test.py`). The walk at `head/evals/harness/ablation-grade.sh:1092-1098` then unlinks any agent-added file with one of those basenames anywhere in the tree. Fixture helper modules the hidden suites import (`helpers.py`, `_oracle_x.py`, per the 1.2.11 header at `head/evals/harness/ablation-grade.sh:220-221`) are therefore reserved, and an agent that adds `src/<pkg>/helpers.py` or `src/<pkg>/utils.py` (not in the fixture, not an overlay dest) loses that file before `run_suite` runs. The hidden tests import the package, fail on the missing module, and a correct solution grades as failing.
**File:** `head/evals/harness/ablation-grade.sh:1086`
**Issue:** The reserved set is wider than the failure it guards against. Pytest's import-file-mismatch abort only arises for modules pytest itself imports by basename: collected test modules (and `conftest.py`, already excluded). A helper module under `tests/` never collides with an identically named module under `src/`.
**Why This Matters:** This is the grading oracle for every build task in the suite (`feature-build`, `bug-fix`, `refactor`). A false negative here silently lowers `hidden_test_pass_rate` for the arm that happened to pick a common module name, which biases the ablation H1/A4 estimates the cycle is built to produce. `grading/<label>.colliding-removed.txt` records the deletion, but nothing in the row flags it, so the bias is invisible in `runs.jsonl`.
**Required Fix:** Restrict `reserved` to basenames pytest would collect (`test_*.py` / `*_test.py`, or the suite's configured `python_files`), and restrict the removal walk to directories the `test_command` actually collects (the paths in `t.test_command`, or at minimum directories named `tests`/`test`). Add an AG case: fixture `tests/helpers.py` plus agent `src/pkg/helpers.py` imported by the solution; expect `colliding_tests_removed` 0 and the hidden suite green.
**Reference:** pytest docs, "Import modes" (`prepend`: "test files … must have unique basenames" applies to test modules); CWE-754 (improper check for unusual conditions, here an over-broad guard that destroys valid input).

**Example:**
```python
# Current (problematic): every .py under tests/ is reserved, whole tree is scanned
reserved.update(n for n in fs if n.endswith(".py") and n not in ("__init__.py", "conftest.py"))

# Should be: only modules pytest collects by basename
reserved.update(n for n in fs if (n.startswith("test_") or n.endswith("_test.py")) and n.endswith(".py"))
# and skip tree directories outside the collected test roots before appending to found
```

### 2. Grader correctness — directory-shaped hidden overlays get no collision protection

- **HIGH** (confidence: medium) `head/evals/harness/ablation-grade.sh:1079-1081` — `owned` keeps only overlay entries whose source is a file, and `reserved` is derived from `owned`, so a hidden overlay declared as a directory (a supported shape: `put_file` copies a directory source with `copy_tree`, `head/evals/harness/ablation-grade.sh:530-531`, and `remove_harness` at line 1050 comments "put_file rewrote these whole") contributes no basenames. An agent test module with the same basename as a module inside that directory survives, and pytest's default import mode aborts collection exactly as before 1.2.11. The fix the PR advertises is a no-op for those tasks.
**File:** `head/evals/harness/ablation-grade.sh:1081`
**Issue:** `reserved` must also walk directory overlays (`os.walk(f)` for each `(_s, d, f)` with `os.path.isdir(f)`) and add their collected-test basenames.
**Why This Matters:** Same damage as finding 1 (a correct solution graded as failing), on the task shapes 1.2.11 was meant to cover. The task fixtures are outside this diff, so I cannot name a specific v2 task that uses a directory overlay; the code path is live either way.
**Required Fix:** Enumerate `.py` basenames inside directory overlays into `reserved`; add an AG case with a directory overlay and a colliding agent test module elsewhere in the tree.

---

## Observations

### 1. Configuration validation — `suite_kind_cap` silently accepts what the header calls a usage error

- **MEDIUM** (confidence: high) `head/evals/harness/run-ablation.sh:502-503` — `(.[$k] // "" | tostring)` maps a present `null` or `false` entry to the empty string, so `run_usd_by_type: {build: null, review-catch: 20}` runs build trials at the 12 USD fallback with no diagnostic, contradicting the header at `head/evals/harness/run-ablation.sh:190-191` ("a present entry that is not an amount in USD … is a usage error"). A present `build: 0` passes `usd_ok` and reaches `--max-run-usd 0`, so every build run cap-fails. RAB-22 covers `"fifteen"` and a list, not these shapes.
**Suggestion:** Use `has($k)` to distinguish absent from present, refuse `null`/`false`, and refuse `0` as `--max-usd` already does.
**Benefit:** A one-character suite typo cannot change the batch's spend ceiling unnoticed.

### 2. KF-048 pre-flight — false refusal in host executor mode

- **MEDIUM** (confidence: high) `head/evals/harness/run-ablation.sh:785` — `CODEX_SKIP` is true only for `--smoke`; it never consults `EXECUTOR`. With `--executor host`, `pipeline-run.sh` does not call `make_home` (`[[ "$EXECUTOR" == container ]] && make_home`), the codex CLI runs against the real `$HOME/.codex/auth.json` with its real refresh token, and can renew the access token. The no-refresh premise of the refusal does not hold, yet a host batch with an access token inside the horizon is refused (exit 2, REFUSED.txt). It also reads `${LOA_EVAL_CREDS_HOME}/.codex/auth.json`, a path host mode never uses.
**Suggestion:** Skip (or downgrade to WARN) when `EXECUTOR == host`; record `codex_preflight.checked: false` with a reason.
**Benefit:** Host-mode batches run on a credential that can refresh instead of being blocked on a condition that cannot degrade them.

### 3. KF-048 pre-flight — the horizon is four times the serial phase budget

- **MEDIUM** (confidence: medium) `head/evals/harness/run-ablation.sh:806` — `required = now + 2 × Σ watchdog_s / concurrency`, but each `watchdog_s` is already 2 × the phase-sum timeout (RAB-1: phase_sum 140 min gives watchdog_s 16800, `head/evals/tests/run-ablation.bats:100-101`). For the 24-row priority batch that is about 59 h; a full A0–A4 batch (about 240 trials at concurrency 3) needs a token valid for weeks, longer than the roughly ten-day codex access-token lifetime the PR's own commit log reports ("token valid to 2026-10-28"). Such batches are refused regardless of how fresh the token is. On `--resume` the whole recorded plan counts, including trials that already have rows, so a nearly finished batch is held to the full original horizon.
**Suggestion:** Use a single safety factor on the phase-sum (or on `watchdog_s` without the extra 2×), count only un-rowed trials on `--resume`, and expose the horizon in the refusal so the operator can size the batch. The arithmetic matches the header's documented rule, so this is a design concern, not a coding slip.
**Benefit:** The pre-flight blocks the batches that would actually degrade, not every batch above a modest size.

### 4. Test dependencies outside the diff

- **MEDIUM** (confidence: low) `head/evals/tests/seed-bugfix.bats:80`, `head/evals/tests/seed-refactor.bats:78` — both tests now pass `--suite-version` to the seed scripts, which are not among the twelve files in this change. If `seed-bugfix.sh` / `seed-refactor.sh` do not already accept that flag, SB-1 and SR-1 fail at merge. The PR description carries no test-run record to confirm either way.
**Suggestion:** State in the PR (or the implementation report) that the seed scripts accept `--suite-version` on main, or include the flag in this change.

### 5. Process — no test-run or formatter evidence (FAST-GATE)

- **MEDIUM** (confidence: medium) `grimoires/loa/a2a/sprint-1/reviewer.md:1` — the implementation report is the PR description: no `## AC Verification`, no bats run record, no shellcheck/formatter record. I verified the test assertions by reading them against the code (RAB-5 arithmetic 17.5 − 2.5 + 15 + 5 = 35, RAB-24 20 + 15 + 2.5 = 37.5, RAB-25 gate arithmetic, RAB-30 horizon 2 × (9600 + 16800) / 3 = 17600 s), but I could not execute them here.
**Suggestion:** Add the bats run output (evals/tests/*.bats) and the lint gate result to the report before the next review round.

### 6. Telemetry — `colliding_tests_removed` over-counts across trees

- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:1018` — `COLLIDING[0] += remove_colliding(t, tree)` runs in every `prepare()` of one grade (`final`, `base`, and the `implement`/`fix1` snapshot trees, `head/evals/harness/ablation-grade.sh:1708`, `1723`, `1748`), so one colliding file is counted once per prepared tree, up to four. AG-35 only sees 1 because `make_run` has no snapshots. The per-label `.colliding-removed.txt` disambiguates, so this is an ambiguity in `grade.json`, not a grading error.
**Suggestion:** Count only the `final` tree, or document the field as "across prepared trees".

### 7. Test hygiene

- **LOW** (confidence: high) `head/evals/tests/run-ablation.bats:211` — the RAB-5 title still says "a cap failure charges run_cap"; the body now asserts the build kind's cap (15) at line 245.
- **LOW** (confidence: high) `head/evals/tests/pipeline-run.bats:973` — `! grep -q 'codex/auth.json' run-1.mounts` is vacuous: `auth.json` is never a mount (only `meta/home` is), so the assertion passes whether or not the file was copied. The `[ ! -e "$T/snap/.codex/auth.json" ]` on the previous line is the real check; drop or retarget this one.
- **LOW** (confidence: medium) `head/evals/tests/fixtures/ablation-pipeline-stub.sh:143` — the stub's rows still hard-code `suite_version: 1` while the suite file is now `suite_version: 2` (`head/evals/suites/ablation-2.0.yaml:31`). Nothing in `run-ablation.sh` compares the two today, but the downstream report partitions on `suite_version` per the commit log, so stub rows would land in the v1 partition.
- **LOW** (confidence: low) `head/evals/harness/run-ablation.sh:813` — a present but unreadable `auth.json` (permissions) is reported as "is not JSON"; a separate `OSError` branch would name the real cause.

### Complexity review

`remove_colliding` (29 lines), the pre-flight Python (about 55 lines in a heredoc) and `make_home` are each under the 50-line threshold or close to it with flat control flow; nesting stays at 3. No duplicate blocks beyond the two `assumed cap` log lines in `collect`, which mirror the pre-existing pattern. Lean already. Ship.

---

## Rejected dissent payloads

None: the envelope's `rejected_summary` is empty and the sidecar `adversarial-rejected-review.jsonl` holds no rows (two voices, `gpt-5.5-pro` via `codex-headless` and `claude-headless`, both succeeded, `consensus`).

## Cross-Model Observations

The dissent (`grimoires/loa/a2a/sprint-1/adversarial-review.json`) returned 10 findings. DISS-001/DISS-C-001 and DISS-002/DISS-C-002 match Changes Required 1 and 2. DISS-003/DISS-C-005 (host-mode refusal), DISS-004/DISS-C-006 (silent cap fallback, `0` cap), DISS-C-003 (count over-report) and DISS-C-004 (horizon) match Observations 1, 2, 3 and 6; I kept those at MEDIUM/LOW because each is an operational refusal, misconfiguration path or telemetry ambiguity rather than a wrong grade. No dissent finding was dropped.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | Grader 1.2.11 deletes agent implementation modules (Changes Required 1) and misses directory overlays (Changes Required 2) |

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| "review the pull request, report each defect it introduces with the file and line it sits on" | Pass | Findings above cite `head/<path>:<line>` |
| "give a merge verdict" | Pass | CHANGES_REQUIRED |
| Per-kind run caps (DEC-0567) reach dispatch, charges, reserve, MANIFEST, --resume | Pass | run-ablation.sh:515, 1043, 1186, 1284, 1322, 850-854, 895, 447-452 |
| `--types` filters the plan | Pass | run-ablation.sh:565; RAB-27 |
| KF-048 placeholder refresh token, host file untouched | Pass | pipeline-run.sh:611-645; pipeline-run.bats:938-985 |
| KF-048 pre-flight refuses a token inside the horizon | Pass with concerns | run-ablation.sh:784-841; Observations 2 and 3 |
| Grader 1.2.11 keeps a correct solution gradable under a basename collision | Fail | Changes Required 1 and 2 |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (the placeholder string `loa-ablation-no-refresh-token` is a sentinel, not a credential)
- [x] Input validation and sanitization present (JWT payload decode is wrapped; auth.json non-object rejected; caps validated except Observation 1)
- [x] Authentication/authorization correct (only the access token is copied into the per-run HOME, mode 0600, host file never written)
- [x] No SQL/XSS injection vulnerabilities (n/a)
- [x] Dependencies secure (no new dependencies)
- [x] Error messages don't leak sensitive data (refusal prints the path and timestamps only; RAB-28 asserts no token material)

---

## Code Quality Summary

**Strengths:**
- The cap change is threaded through every charge site and the manifest, with `--resume` pinned to the recorded caps and a stderr note on an ignored `--run-cap`.
- `make_home` fails closed to "no codex credential" and never touches the host file; the tests prove it with a snapshotting docker wrapper and a byte-hash of the host file.
- Header comments document each new rule (Run caps, pre-flight 6) in the same voice as the existing ones.

**Areas for Improvement:**
- `remove_colliding` guards against a narrow pytest behaviour with a wide deletion; match the guard to the behaviour.
- The pre-flight's horizon and executor handling should follow the actual refresh capability of the run, not only the smoke flag.

---

## Next Steps

1. Fix Changes Required 1 and 2 in `ablation-grade.sh` (restrict `reserved` and the walk; include directory overlays) and add the two AG cases.
2. Address Observations 1–3 or record the accepted design in NOTES (Decision Log) with the DEC id.
3. Record the bats run and lint gate in the implementation report.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":5,"low":5},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T04:06:00Z"} -->
