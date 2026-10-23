# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Change under audit:** `pr/head.diff` (12 files, +719/-164); citations are `head/<path>:<line>` from `pr/head/`

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The change touches the ablation harness's three trust boundaries: the grading copy of an agent-shaped tree (`ablation-grade.sh` 1.2.11, `remove_colliding`), the operator's codex credential as it enters a container (`pipeline-run.sh` `make_home`, KF-048) and is pre-checked by the batch runner (`run-ablation.sh` pre-flight 6), and the spend controls (per-kind run caps, DEC-0567, through `lib/arms-common.sh`). The credential handling is a clear improvement over base: the single-use refresh token no longer leaves the host (`"tok["refresh_token"] = "loa-ablation-no-refresh-token"` — head/evals/harness/pipeline-run.sh:636), the copy is 0600, the host file is never written, no token value reaches argv or a refusal line, and the JWT payload is decoded only for `exp`. The cap chain is implemented as its header documents and is pinned by RAB-22…26.

Two defects block merge, both confirmed independently of the review. First, the grader's new collision rule reserves every `.py` basename under a fixture `tests/` directory and unlinks any agent-added file in the whole tree with that basename (head/evals/harness/ablation-grade.sh:1087, :1100), although pytest only aborts on two *collected* test modules with one basename in package-less directories; I reproduced under pytest 9.0.2 that `tests/helpers.py` beside `src/app/helpers.py` passes, so the grader deletes part of a correct solution and grades it failing — the measurement corruption 1.2.11 was written to remove. Second, the codex pre-flight horizon doubles a `watchdog_s` that the plan already writes as `2 * s * 60` (head/evals/harness/run-ablation.sh:772, :806), so the pre-registered A0/A1/A4 × 3 batch needs a token valid ~10.4 days out while its wall time is ~2.6 days, and the check fires under `--executor host` where `make_home` (container-only, head/evals/harness/pipeline-run.sh:648) never installs the non-refreshable copy.

The security dissent ran with two independent voices (gpt-5.5-pro: clean; claude-headless: one MEDIUM, two LOW). No payload was rejected. Not a degraded review.

**Security Issues Found:**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 5 |
| Low | 6 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] `remove_colliding` deletes non-colliding agent modules from the graded tree

**Severity:** HIGH (confidence: high — reproduced)
**File:** `head/evals/harness/ablation-grade.sh:1087` (reservation), `head/evals/harness/ablation-grade.sh:1096-1100` (removal)
**Issue:** The reserved set is built from every `.py` under any fixture path component named `tests`/`test`:
```python
reserved.update(n for n in fs if n.endswith(".py") and n not in ("__init__.py", "conftest.py"))
```
(head/evals/harness/ablation-grade.sh:1087), and the removal walks the entire grading tree, pruning only `EXCLUDE_TOP`/`__pycache__`, unlinking any file whose basename is reserved and whose path is neither an overlay dest nor present in the fixture (head/evals/harness/ablation-grade.sh:1090-1100). pytest's default import mode only collides on *collected* modules (`test_*.py`, `*_test.py`) in package-less directories. Verified with pytest 9.0.2:

| Layout | pytest result | grader 1.2.11 |
|---|---|---|
| `tests/helpers.py` + `tests/test_a.py` (`from helpers import h`) + `src/app/helpers.py` | 1 passed | deletes `src/app/helpers.py` |
| `tests/test_slug.py` + `tests/extra/test_slug.py` (package-less) | collection ERROR (the 1.2.11 target) | removes `tests/extra/test_slug.py` (correct) |
| `tests/test_slug.py` + `tests/pkg/__init__.py` + `tests/pkg/test_slug.py` | 2 passed | deletes `tests/pkg/test_slug.py` |

The PR's own header says fixture suites do `from helpers import …`, so fixtures ship support modules with ordinary names (`helpers.py`, `utils.py`, `_oracle_x.py`). A correct solution that adds `src/<pkg>/helpers.py` loses it before `test_command` runs; the hidden suite then `ImportError`s and the row is graded failing. The deletion is invisible to the agent and recorded only in `grading/<label>.colliding-removed.txt`. The walk also reaches vendored trees and virtualenvs inside the snapshot (dissent DISS-C-003).
**Impact:** Silent false negatives in the H1/A4 ablation rows, in a direction that can differ by arm (arms that add more source modules lose more). This is the measurement-integrity failure the grader exists to prevent; `colliding_tests_removed` is telemetry and nobody reads it per row.
**Fix:** Reserve only basenames pytest imports by name — `test_*.py` / `*_test.py` from the fixture's test roots and from overlay files — and remove only candidates that are themselves collectable test modules in package-less directories (no `__init__.py` on the path from the collection root). Prune `.git`, `.venv`/`venv`, `node_modules`, `site-packages`. Add an AG case asserting `src/app/helpers.py` survives beside a fixture `tests/helpers.py`, and one asserting a `tests/pkg/__init__.py` sibling survives.
**Reference:** CWE-697 Incorrect Comparison — https://cwe.mitre.org/data/definitions/697.html
**Cross-model:** Confirmed by cross-model review (claude-headless DISS-C-002, at LOW; raised here because the scenario is reproduced, not hypothesised).

### [HIGH-002] Codex pre-flight horizon double-counts the watchdog and runs for the host executor

**Severity:** HIGH (confidence: high — arithmetic from the code and the PR's own numbers)
**File:** `head/evals/harness/run-ablation.sh:806`; context `head/evals/harness/run-ablation.sh:772`, `head/evals/harness/pipeline-run.sh:648`
**Issue:** The plan writes `"watchdog_s": 2 * s * 60` (head/evals/harness/run-ablation.sh:772) — already twice the phase-sum budget (RAB-1 asserts 16800 s for a 140-min A1 build). The pre-flight then computes
```python
required = int(math.ceil(now + 2 * sum(float(e.get("watchdog_s") or 0) for e in plan) / max(conc, 1)))
```
(head/evals/harness/run-ablation.sh:806): four times the serial phase budget over concurrency, summed over the whole plan, for every executor. With the suite's numbers (a0 build 9600 s, a1 build 16800 s, a4 build 6000 s, a1 review 7200 s, a0 review 8400 s; 12 build + 4 review tasks; 3 trials; concurrency 3):

| Plan | Σ watchdog_s | required horizon | expected wall time |
|---|---|---|---|
| A0 + A1 + A4 (pre-registered) | ≈1,353,600 | ≈10.4 d | ≈2.6 d |
| A0 + A1 | ≈950,400 | ≈7.3 d | ≈1.8 d |
| RAB-30's own case (1 task, a0+a1, 1 trial) | 26,400 | 4.9 h | ≤ 1.2 h |

The PR's DEC-0593 token was valid for 10 days after login, so a freshly logged-in operator is refused with `run codex login on the host`, which cannot help. `--dry-run` is refused the same way (RAB-34 pins this). The check has no `EXECUTOR` condition (head/evals/harness/run-ablation.sh:784-841) although only `[[ "$EXECUTOR" == container ]] && make_home` (head/evals/harness/pipeline-run.sh:648) installs the non-refreshable copy; a host run keeps the CLI's own refreshable credential.
**Impact:** The runner refuses exactly the batches it was built to launch. Operators will split batches or hand-edit the plan to get past it, eroding the pre-registration discipline the batch record depends on (availability failure of a safety control, not a bypass).
**Fix:** Derive the horizon from the phase budget (`phase_sum_min` or `watchdog_s / 2`) with a bounded, named margin; skip with `checked: false` and a `reason: host` when `EXECUTOR != container`; when `exp` is earlier than the horizon but no fresh login could reach it either, say "the batch outlives any codex token; split it". Re-pin RAB-30's `17600` to the new formula.
**Reference:** CWE-682 Incorrect Calculation — https://cwe.mitre.org/data/definitions/682.html

---

## Medium/Low Priority Issues

### [MED-001] Pre-flight fails open when the credential file is absent

- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/run-ablation.sh:802-804`
- **Issue:** An expired token refuses the batch, but a *missing* `auth.json` only warns:
  ```python
  if not present:
      out["warn"] = "run-ablation: WARN no codex auth.json under %s; codex-using arms will run without the OpenAI voice"
      done()
  ```
  Both states produce the same outcome inside the container (no OpenAI voice, every codex-using row degraded). A mistyped `LOA_EVAL_CREDS_HOME`, a creds directory not mounted on the batch host, or a `codex logout` therefore launches a full-cost batch (the PR's own p1 batch was USD 142) whose a1 rows are all degraded, with one stderr line as the only signal — and under `--detach` (head/evals/harness/run-ablation.sh:459-469) that line lands in `driver.log`. The header documents the asymmetry as intended; the audit still rates a cost-bearing control that fails open as a defect.
- **Fix:** Refuse when `codex_arms` is non-empty and the file is absent, with an explicit opt-in (`--allow-no-codex`) that records `codex_preflight.waived: true` in MANIFEST; or at least refuse unless `--smoke`.
- **Reference:** CWE-636 Not Failing Securely — https://cwe.mitre.org/data/definitions/636.html

### [MED-002] Per-kind cap lookup treats `false`/`null`/`""` as "no entry"

- **Severity:** MEDIUM (confidence: high)
- **File:** `head/evals/harness/run-ablation.sh:503`
- **Issue:** `(.[$k] // "" | tostring)` maps a present `false` or `null` (and an empty string) to `""`, which line 507 returns as "none" and line 511 silently replaces with `RUN_CAP`, contradicting the header's "a present entry that is not an amount in USD … is a usage error" (head/evals/harness/run-ablation.sh:191). `run_usd_by_type: {build: ~}` launches build trials at 12 and records 12 as the effective cap in MANIFEST — a broken spend setting recorded as intentional.
- **Fix:** `if has($k) then (.[$k] | tostring) else "" end` and validate every present value with `usd_ok` (also reject `0`, which pipeline-run accepts and turns into a cap failure after phase 1).
- **Reference:** CWE-20 Improper Input Validation — https://cwe.mitre.org/data/definitions/20.html
- **Cross-model:** raised by the review's dissent (DISS-001); confirmed.

### [MED-003] Overlay basenames are not filtered for `__init__.py`

- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/ablation-grade.sh:1081`
- **Issue:** `reserved = {d.rsplit("/", 1)[-1] for d in owned if d.endswith(".py")}` applies no `__init__.py` exclusion while the fixture walk at :1087 does. A hidden overlay that ships `tests/<dir>/__init__.py` makes every agent-added package `__init__.py` in the tree a removal target: a new package under `src/` loses its marker and its imports fail.
- **Fix:** Apply the same `("__init__.py", "conftest.py")` exclusion to the overlay set (subsumed by the HIGH-001 rework).
- **Reference:** CWE-1023 Incomplete Comparison with Missing Factors — https://cwe.mitre.org/data/definitions/1023.html

### [MED-004] Directory overlays contribute nothing to the reserved set

- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/ablation-grade.sh:1079-1081`
- **Issue:** `owned` keeps only file overlays (`if not os.path.isdir(f)`), so `.py` files inside a directory overlay never enter `reserved`; an agent test module elsewhere in the tree with the same basename is not removed and the collection abort 1.2.11 targets still happens for those tasks. The fix is incomplete for one overlay shape the manifest allows.
- **Fix:** Walk each directory overlay for collectable test basenames when building `reserved`.
- **Reference:** CWE-1023 — https://cwe.mitre.org/data/definitions/1023.html
- **Cross-model:** Confirmed by cross-model review (claude-headless DISS-C-003).

### [MED-005] `--resume` pre-flight is scoped to the whole recorded plan

- **Severity:** MEDIUM (confidence: high)
- **File:** `head/evals/harness/run-ablation.sh:794`
- **Issue:** `arms = sorted({e["arm"] for e in plan if uses_codex(e["arm"])})` reads the entire plan, so a `--resume` that only re-rows (`--rerow …`) or resumes a batch with every trial rowed is refused on an expired token although no pipeline call would run. The PR's own history re-rowed 24 rows under row writer 1.2; with a lapsed token that bookkeeping would have been blocked until a re-login.
- **Fix:** On `--resume`, derive `codex_arms` and the horizon from the trials that will launch (plan entries without a row plus `--rerun` targets); skip when that set is empty.
- **Reference:** CWE-1025 Comparison Using Wrong Factors — https://cwe.mitre.org/data/definitions/1025.html

### [LOW-001] Per-run credential copy is a one-key denylist, not an allowlist

- **Severity:** LOW (confidence: medium)
- **File:** `head/evals/harness/pipeline-run.sh:634-636`
- **Issue:** `make_home` rewrites only `tokens.refresh_token`; `tokens.access_token`, `tokens.id_token` (an identity JWT with the account's subject/email), `tokens.account_id` and a top-level `OPENAI_API_KEY` (non-expiring, present under API-key auth) are copied verbatim into the HOME mounted read-write in the container where the evaluated agent runs arbitrary shell with network. The new KF-048 bats case asserts `has("OPENAI_API_KEY")` is preserved, pinning the broader copy. Base copied the whole file including the refresh token, so this change strictly reduces exposure; it is rated LOW as a missed hardening at the moment the copy was rewritten, not as a regression.
- **Fix:** Write only what the chatgpt auth mode needs (`auth_mode`, `tokens.access_token`, `tokens.account_id`, the placeholder refresh token), null `OPENAI_API_KEY` unless `auth_mode` is api-key, drop `id_token` if the CLI does not need it; assert the absence in the test.
- **Reference:** CWE-522 Insufficiently Protected Credentials — https://cwe.mitre.org/data/definitions/522.html
- **Cross-model:** claude-headless DISS-C-001 (MEDIUM), adopted at LOW for the reason above.

### [LOW-002] An out-of-range `exp` aborts the pre-flight with a generic failure instead of a refusal

- **Severity:** LOW (confidence: high — reproduced)
- **File:** `head/evals/harness/run-ablation.sh:827-830`
- **Issue:** `math.isfinite(exp)` admits `1e300`; `iso(exp)` at :830 then calls `time.gmtime`, which raises `OverflowError: timestamp out of range for platform time_t` (verified). The traceback escapes the heredoc, the script hits `|| die "the codex token pre-flight failed"` (:836) and exits 2 without `REFUSED.txt` or a reason. Operator-owned input, so no exposure, but the error path the PR built is bypassed.
- **Fix:** Bound `exp` (e.g. `0 < exp < 2**33`) in the same check and refuse with "exp out of range".
- **Reference:** CWE-755 Improper Handling of Exceptional Conditions — https://cwe.mitre.org/data/definitions/755.html

### [LOW-003] `colliding_tests_removed` sums the same collisions across every prepared tree

- **Severity:** LOW (confidence: medium)
- **File:** `head/evals/harness/ablation-grade.sh:1019`; call sites `:1708`, `:1723`, `:1748`
- **Issue:** `COLLIDING[0] += remove_colliding(t, tree)` runs for `final`, the `base` tree and each gate snapshot (`implement`, `fix1`). The agent's colliding file exists in `final` and in every snapshot, so a run with two gate snapshots reports 3 for one collision. AG-35 only exercises a snapshot-less run. The header describes the field as a per-grade count, so this is ambiguity rather than a wrong number, but a consumer reading it as "files removed from the graded solution" over-counts.
- **Fix:** Record per-tree counts (`{final: n, implement: n, …}`) or count `final` only; say which in the header.
- **Reference:** CWE-682 — https://cwe.mitre.org/data/definitions/682.html

### [LOW-004] `uses_codex` over-approximates the arms that run the dissent

- **Severity:** LOW (confidence: low)
- **File:** `head/evals/harness/run-ablation.sh:792-793`
- **Issue:** Every arm with `loa_mount != false` is treated as codex-using; an arm whose toggles disable the gates (a4_no_gates) never runs the dissent, so an a4-only batch is refused on an expired token needlessly and MANIFEST `codex_arms` is inaccurate.
- **Fix:** Derive codex use from the toggles that drive the dissent (gates on), not from `loa_mount` alone.
- **Reference:** CWE-1023 — https://cwe.mitre.org/data/definitions/1023.html

### [LOW-005] RAB-1 comment contradicts its own assertion

- **Severity:** LOW (confidence: high)
- **File:** `head/evals/tests/run-ablation.bats:95-97`
- **Issue:** Lines 95-96 say "A0 BARE stays 70 min … the … derivation (80) does not apply"; line 97 asserts `9600` (= 2 × 80 min) with a trailing comment "BARE = 15 + 35 + 2 x 15 on a v2 task". One is stale.
- **Fix:** Delete the 70-min sentence.
- **Reference:** CWE-1116 Inaccurate Comments — https://cwe.mitre.org/data/definitions/1116.html

### [LOW-006] RAB-25 "launches" branches are timing-dependent

- **Severity:** LOW (confidence: low)
- **File:** `head/evals/tests/run-ablation.bats:832` (and `:844`)
- **Issue:** The pass/fail criterion is the relative order of `launch` and `done` lines in `run.log`, with a stub that finishes in milliseconds and the driver's poll interval between them. In the `kc`/`ke` cases the second launch must be logged before the first trial's collection; on a slow CI host the first trial can complete first and the assertion inverts.
- **Fix:** Give the stub a short sleep in these cases, or assert on `in_flight_reserved` in a recorded cut instead of log ordering.
- **Reference:** CWE-362 Concurrent Execution using Shared Resource with Improper Synchronization — https://cwe.mitre.org/data/definitions/362.html

---

## Observations (not tallied)

- `head/evals/harness/ablation-grade.sh:1100` — bare `os.unlink(p)` raises on a read-only parent (review Observations §5, dissent DISS-C-002 of the review round). `copy_tree` creates directories with `os.makedirs` (default mode) and only preserves *file* modes (`:479-519`), so the agent cannot make a grading directory read-only through the snapshot; theoretical, and the same pattern as `remove_harness` (`:1065`). Fold into a shared `try/except OSError` helper during the collision-rule rework (finding 1 above).
- `head/evals/tests/seed-bugfix.bats:80`, `head/evals/tests/seed-refactor.bats:78` — the seed scripts the tests drive with `--suite-version`, and the frozen `*-v2-*` task set and `MANIFEST.sha256` the RAB tests reference under `grimoires/`, are not in this diff; **Unable to assess** here. Scope limit, not a defect.
- `head/evals/harness/run-ablation.sh:809` — refusal text embeds the credential path (`~/.codex/auth.json` under the operator's home) into `REFUSED.txt`, which the batch `.gitignore` (:1005-1008) does not exclude. Path only, no token; same class as existing refusals.

---

## Cross-Model Security Observations

Envelope: `grimoires/loa/a2a/sprint-1/adversarial-audit.json` (type audit; primary gpt-5.5-pro answered by codex-headless: clean, 0 findings; companion claude-headless: 3 findings; `companion_voice.status: succeeded`, `counted_as: independent_voice`; `verdict_quality.voices_succeeded 2/2`; `degraded: false`; `locality` null → not a degraded security review).

- DISS-C-001 (claude-headless, MEDIUM, secrets) — adopted as LOW-001 with the severity rationale given there (strict reduction versus base).
- DISS-C-002 (claude-headless, LOW, input-validation) — Confirmed by cross-model review: same defect as HIGH-001; the audit's reproduction raises it above the dissenter's rating.
- DISS-C-003 (claude-headless, LOW) — Confirmed by cross-model review: the directory-overlay half is MED-004; the vendored-tree half is folded into HIGH-001's fix.

## Rejected dissent payloads

- None: `metadata.rejected_summary` is empty, `rejected_count` 0, `companion_voice.rejected_sidecar` null, and no `adversarial-rejected-audit*.jsonl` exists beside the envelope.

---

## Review-demotion confirmation

The review trailer records `excluded: 0` — no speculative HIGH was demoted, so there is nothing to confirm; `excluded_confirmed: 0`. Both review HIGHs were re-derived here from the head files (HIGH-001 reproduced under pytest; HIGH-002 from `:772` and `:806`) and stand.

---

## Rubric Scores

| Dimension | Score | Basis |
|---|---|---|
| Security (SEC-IV, SEC-CI, SEC-AV) | 4/5 | Credential copy hardened (0600, placeholder refresh, no token in argv/refusals, host file untouched); denylist not allowlist (LOW-001); one fail-open control (MED-001); cap validation gap (MED-002) |
| Architecture (ARCH-RE, ARCH-ST) | 3/5 | Pre-flight horizon mis-derived and executor-agnostic (HIGH-002); resume scope (MED-005) |
| Code Quality (CQ-TC, CQ-EH) | 3/5 | Collision rule models the wrong criterion (HIGH-001, MED-003/004); good RAB/AG coverage otherwise; one stale comment, one timing-dependent test |
| DevOps (DO-DS, DO-OB) | 4/5 | MANIFEST records caps and the pre-flight; `--resume` keeps recorded caps; detach hides the fail-open WARN |
| Blockchain/Crypto | n/a | — |

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added — head files scanned for JWT/API-key/private-key patterns: none; test tokens are synthetic (`h.<payload>.s`, `"R"`)
- [x] Input validation on new inputs — `usd_ok` on caps (gap: MED-002); JWT payload decoded without trust, `exp` type-checked (gap: LOW-002)
- [x] Authentication/credential handling — 0600 copy, placeholder refresh token, host file byte-identical (pipeline-run KF-048 tests); exposure of the remaining keys is pre-existing (LOW-001)
- [x] No SQL/XSS injection vulnerabilities — n/a (shell + Python stdlib, no interpolation into commands: `python3 -I -c` with argv paths, `jq --arg`)
- [x] Error handling doesn't leak info — refusals carry paths only; RAB-28 asserts no token material
- [x] Tests cover security paths — RAB-28…34, pipeline-run KF-048 ×3, AG-35; missing: a non-colliding-module survival case (HIGH-001), `OPENAI_API_KEY` absence (LOW-001)

## Documentation audit

No `documentation-coherence-*` subagent reports exist in this workspace (no `grimoires/loa/a2a/subagent-reports/`). Manually verified: the `run-ablation.sh` header documents pre-flight 6, the Run caps section and the MANIFEST fields (`:110-118`, `:188-199`, `:222-230`); the `pipeline-run.sh` header describes the placeholder copy (`:83-87`); `ablation-2.0.yaml` explains `run_usd_by_type` (`:34-41`); `ablation-grade.sh` records 1.2.10 → 1.2.11 (`:220-226`). The header claim at `run-ablation.sh:191` is contradicted by the code (MED-002). No CHANGELOG is in the diff; **Unable to assess** whether the repository's CHANGELOG names the KF-048 credential change.

## Scope and process notes

- Prerequisite deviation: Phase 0 requires `engineer-feedback.md` to say "All good"; it says CHANGES REQUIRED. The orchestrator instructed the audit to run regardless (`pr/AUDIT-INSTRUCTIONS.md`: "skip any pre-flight step that needs them and do not ask questions"); recorded here and in NOTES.
- `grimoires/loa/known-failures.md` is absent (hook warned); triaged without it.
- `br` is not installed; no beads comment or labels were written.
- `.claude/scripts/security-audit-scope.sh` ran against the workspace, not `pr/head/`; its counts are not meaningful for this diff and were not used.

---

## Next Steps

**CHANGES_REQUIRED:**
1. Fix HIGH-001 (collision rule restricted to collectable test modules; survival test) and HIGH-002 (horizon from the phase budget, container-only, honest message).
2. Pick up MED-001…005 while in those functions; LOW-001/002 are one-line hardenings in the same blocks.
3. Re-run `/review-sprint sprint-1`, then `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":5,"low":6},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T17:45:00Z"} -->
