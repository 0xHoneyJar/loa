All good

Observations documented and non-blocking. See Observations below.

# Sprint 271 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent (Fable 5.1, lead session; the cross-model dissent below is the independent voice — gpt-5.5-pro primary, claude-headless companion, both completed)
**Date:** 2026-10-23
**Sprint Reference:** grimoires/loa/sprint.md — "Sprint 3 (Final): Phases 2–3 — reads, report, proof, ship (global 271)"
**Implementation Report:** grimoires/loa/a2a/sprint-271/reviewer.md

---

## Overall Assessment

The sprint delivers what the plan asked for and nothing it did not: the registered reads re-taken under an analysis-only addendum (every registered figure byte-identical to the REGISTRATION-14 read), a report whose every table row is copied from a generated artefact and policed by a bats case, the label-set re-grades done on hard-link copies that never touch the record, a sandbox-lite record whose faithfulness was proven empirically (28/28 reconstructed units re-grade byte-identically, then every recorded grade, row and read from a fresh clone), the declared exploratory judge read labelled post hoc everywhere, the release metadata cut only after the proof, and fifteen decision rows with the alternatives rejected. The pinned pipeline is byte-identical to the pin (asserted three times by the register script). Nothing shipped by default changes.

Code read, not the report: `reads.py` (the three addendum-16 changes are additive — a new sensitivity after `v1_labels` in `DEFAULT_SENSITIVITIES` (`reads.py:100`), `co_reads` appended to the final document (`reads.py:716`) and rendered after the pre-registered reads (`reads.py:951`), `label_descriptive` (`reads.py:503`) printed beside the status; `regrade_cells` still builds a cell without a re-grade with `grade None`, the registered behaviour), `stats.py` (`cost_per_extra_defect` `stats.py:699-712`: the `dominated` / `dominated_by_cost` branches are exhaustive — `extra > 0 and dcost <= 0`, `extra <= 0 and dcost > 0`, the pre-existing `no_extra_defects`, then `ok`; no caller divides by `value`), `regrade_labels.py` (session `run_dir` validated by `^sessions/[A-Za-z0-9._-]+\Z` and not a symlink (`:278-280`); `--out`/`--work`/`--roots` refused inside the results or suite roots and on another filesystem (`check_paths`, `:290-303`); hard-link copies exclude `grading/` and `grade.json`, the only paths the grader writes, and the Phase 1 rows re-derived byte-identically after the re-grades prove the record's `meta/`, `eval/` and transcripts were not written through the links; label-set and grader-version refusals before `INDEX.json` (`verify_entries`, `:376-395`)), `record_lite.py` (symlink refusal covers parent components and the entry itself before any write (`take`, `:299-312`); manifest paths pass `safe_rel` (`:484`); every reconstructed file is checked against the manifest and the fixture (`:487-510`); recorded `grading/` is never copied into the reconstruction (`RECORDED_SUBDIRS`, `copy_recorded`) so the comparison is real; units the record never graded are skipped and listed (`compare_unit`, `classes`, `write_report`)), `reproduce.sh` (environment checks, the engine, the live rerun with the runner's gate flags), `judge_defects.py` (the leak scan refuses the whole run (`:339-358`); an item labelled in two sessions is refused at merge (`:520-523`); sampling seeded; the exploratory label in every heading), `report-assemble.py` + `evals/tests/c132-report.bats`.

Tests read and run: `python3 -m pytest evals/analysis/c132/tests -q` 182 passed (152 before the sprint; the 30 new tests assert specifics — record untouched, idempotence and `--force`, refusal before any write, label-set mismatch refused, `--check` byte identity, leak refusal, determinism, the three cost statuses, co-reads in `--final`, the ungraded-in-record classification); `evals/tests/c132-report.bats` 3/3. Seams under test (sprint.md): the final read twice on the tracked rows — identical, and reproduced from the fresh clone; `reproduce.sh` in a fresh clone — every hash equal; the allowlisted diff vs `main` — empty where the PRD requires it.

**Verdict:** APPROVED

---

## Observations

### 1. Complexity (SIMPLICITY, non-blocking with the justification stated)

- **MEDIUM** (confidence: high) `evals/analysis/c132/record_lite.py:666-842` — `reproduce()` is about 175 lines; `plan_run_dir` (`record_lite.py:280-369`) about 90; `judge_defects.py:362-480` `sample()` about 120. Each is a straight-line sequence of commented stages (reconstruct → grade → rows → reads; scan → take → compare) with no nesting beyond two levels and early `continue`s; splitting them would add plumbing between stages that share eight local names. Justified for this cycle; lift the stages into named functions when the tooling is reused. `SIMPLICITY[shrink]: net −0 lines possible without a real reuse case. Lean enough. Ship.`

### 2. Robustness (non-blocking)

- **LOW** (confidence: high) `evals/analysis/c132/reproduce.sh:72` — the `--pre-registration-ref` string recovers the reads' registration hash from `REGISTRATION-16.json`'s `supersedes`, a hard-coded file name; a later registration (REGISTRATION-17 now exists) leaves the reference text stale, while the live run itself still passes `REGISTRATION-15.json` (`REG`) as registered. Read the hash from `$REG` directly. (Also raised by the dissent as DISS-C-002.)
- **LOW** (confidence: medium) `evals/analysis/c132/record_lite.py:499-501` — a `pr/` symlink is recreated from the manifest's `target` unvalidated into the scratch sandbox; the grader drops symlinks when it copies `pr/` to `grading/pr` and `read_regular` refuses them, so no read follows the link, but a record from an untrusted source could plant one. Validate `target` with `safe_rel` or record symlinks without recreating them.
- **LOW** (confidence: high) `evals/analysis/c132/record_lite.py:424` — `build --only` writes `INDEX-only.json`; the stage-1 script requires `INDEX.json`, so a partial build cannot be mistaken for the record (good), but the two names are undocumented in `REPRODUCE.md`.

### 3. Test adequacy in CI (non-blocking, predates the sprint)

- **MEDIUM** (confidence: high) `.github/workflows/bats-tests.yml:182-191` — the repository's pytest step lists adapter and maintenance suites only; `evals/analysis/c132/tests` (182 tests after this sprint) runs locally and in the reviewer's verification but not in CI. The sprint's `evals/tests/c132-report.bats` does run in the bats step. Follow-up: add `evals/analysis/c132/tests` to that pytest step (one line) in the next harness sprint.

### 4. Cross-model dissent triage (run 1 of 3)

Dissent run 1 of 3 for this sprint (`adversarial-review.sh --type review --sprint-id sprint-271 --diff-file …/s3-code.diff --context-file reviewer-concerns.md --budget 1000`): status `clean`, primary gpt-5.5-pro, companion claude-headless `succeeded` (`independent_voice`); nine findings, all from the companion, one marked blocking by the voice. Each triaged against the code and the recorded runs:

- **HIGH** (speculative, confidence: low) `evals/analysis/c132/judge_defects.py:588` — DISS-C-001 (voice: blocking): "the exploratory read can never be aggregated; every invocation exits 1 'inputs invalid'" because `run()` judges validity with `build_cell(r, None)` (row only) while the sampler judged it with the grade. **Refuted by the record:** the aggregation ran on the real key and labels and exited 0 — `reports/review-catch-c132/judge-defects/result.md` reports `40 of 40` pairs judged in every arm and 593 items — because the row carries `contaminated`, `oracle_exposed_defects`, `status`, `took_effect` and `sessions_valid`, the fields `validity()` reads, so the row-only filter equals the grade-inclusive one on these rows. The residual point stands as a hardening note: make `aggregate` load the grades so the two filters cannot diverge on a future row. Demoted to an observation; counted under `excluded`.
- **MEDIUM** (confidence: medium) `evals/analysis/c132/reproduce.sh:66` — DISS-C-004: the live sample runs even when the reproduction engine exited non-zero, so paid model calls could follow a broken reproduction and the report would mix the two. True as written (`rc` is carried but not gated). In this sprint the engine exited 0 before the live step. Suggest gating `--live-sample` on `rc == 0` unless `--live-anyway` is passed.
- **MEDIUM** (confidence: medium) `grimoires/loa/reports/review-catch-c132/scripts/run-judge-defects.sh:7` — DISS-C-007: the chunk directory under `~/.cache` is filled once and reused; a re-sample that changes the packets would leave stale chunks whose item ids collide with the new packets, and the aggregator checks ids, not content. True as an operational hazard; this sprint's run started from an empty chunk directory and the sample is deterministic (byte-identical to its dry run). Suggest keying the chunk directory by the key.json sha and refusing a mismatch.
- **MEDIUM** (confidence: low) `evals/analysis/c132/reproduce.sh:86` — DISS-C-005: the recorded range for the live rerun is taken over every recorded row of the arm on the task, valid or not, so an invalid row could widen it. Checked against the record: the three live arms' review-r24 rows are all `completed`, uncontaminated, unexposed, every took-effect rule true — the ranges used were not widened. Suggest filtering to valid rows (`common.build_cell(...)["valid"]`) for robustness.
- **LOW** (confidence: medium) `evals/analysis/c132/reproduce.sh:74` — DISS-C-003: an infrastructure failure in the live step (e.g. a refusal) yields "not run" rows and exit 1, read as a discrepancy. The appended table does carry the `status` column ("not run" vs "completed"), so the report distinguishes them, but the exit code does not. Suggest a distinct exit code for "live sample not run".
- **LOW** (confidence: low) `evals/analysis/c132/reproduce.sh:44` — DISS-C-006: the image digest comparison could always fail or always pass depending on the digest form the registration recorded. **Refuted by the record:** the registration holds the `sha256:…` image Id form and `docker image inspect --format '{{.Id}}'` returns the same form; both reproducer environment blocks show `image_matches: True`.
- **LOW** (confidence: low) `evals/analysis/c132/reads.py:1012` — DISS-C-008: "`--final` crashes while rendering a `not_provided` label sensitivity". **Refuted by execution:** the reviewer ran `reads-c132.py --final` on the tracked inputs without `--sensitivity-grades`; exit 0 and the markdown renders `| frozen_c131_labels (key dir `c131`) | status `not_provided` | PRs — |`.
- **LOW** (confidence: low) `evals/analysis/c132/reproduce.sh:60` — DISS-C-009: if the tracked `review-catch-c132/rows.jsonl` and the `c132-final` rows diverged, the reads would be reproduced against a different baseline without naming the cause. Both are tracked and byte-identical (sha `522e1980…`), and `reads-c132.py` validates the rows file hash against `INPUTS.json` before any output and names the mismatch (`inputs invalid`, exit 1) — the failure would not be silent.
- DISS-C-002 (advisory) is the stale `--pre-registration-ref` reference recorded under Observations 2 above.

## Rejected dissent payloads

None. `rejected_summary` is empty and no `adversarial-rejected-review*.jsonl` sidecar was written.

---

## Acceptance Criteria Check

| Criterion (sprint.md, verbatim) | Status | Notes |
|---|---|---|
| PRD FR-9 AC 1–3 (report files tracked; `reads.md` byte-identical across runs; every figure in the report reproduced by the script; DEC rows per read) | Pass | six files tracked; two consecutive final runs identical and the REGISTRATION-15 re-read reproduced from the fresh clone; `report-assemble.py` + bats 3/3; DEC-0801…0808 |
| PRD FR-10 AC 1–2 (REPRODUCE.md exact; the reproducer's hashes equal; sampled rerun inside the recorded arm range or the discrepancy named; report § Proof links everything) | Pass | `reproduction/report.md`: 16 artefact classes, 0 differ, from stage 1 and stage 1b; live rerun: one inside, two one-defect outside and named (the AC's named-discrepancy branch); § Proof links the report, controls, judge, dissent records, registration chain |
| PRD G-7 (allowlisted diff vs `main` of `.loa.config.yaml`, skill frontmatter and shipped suite arms empty; rc.7 cut only after FR-9 and FR-10) | Pass | verified by the reviewer: `.loa.config.yaml` 0 files; `.claude/` = checksums.json + the CLAUDE.loa.md version stamp only (integrity hash unchanged); no skill frontmatter change; the suite file adds the two measurement arms and FR-11 took-effect rules; the release commit follows the re-read and the proof |
| Review APPROVED, audit APPROVED, Bridgebuilder round triaged, CI green, merged, record branch pushed, cycle archived through the fixed `archive-cycle.sh` | Pending (Task 3.6) | this review is the first gate; the record branch stage 1/1b is pushed; the rest follows in order (NOTES Decision Log 2026-10-23T17:30Z) |

---

## Security Checklist

- [x] No hardcoded secrets or credentials — the secret scan ran over every tracked artefact and over the record branch's 3,680 added paths (clean); `sandbox-manifest.json` lists `.git/` and `.eval/` entries by name only (the per-run credential copies live outside `sandbox/`)
- [x] Input validation — manifest paths (`safe_rel`), session `run_dir`s (anchored regex), label keys under `manifests/`, grader refusals before writes, provenance leak scan on packets
- [x] Symlink defenses — refusal before any write in the lite set; reconstruction never follows a link; the grader's `read_regular` refuses links
- [x] No shell injection — subprocess argument lists throughout; `reproduce.sh` quotes every path and refuses `:`/`,` in scratch paths (the grader's own refusal)
- [x] Dependencies — stdlib only; the pinned pipeline untouched
- [x] Error messages — refusals name paths relative to the roots; `regrade_labels.py` replaces absolute work/roots paths in INDEX.json

---

## Code Quality Summary

**Strengths:** every refusal happens before a write; deterministic output everywhere (sorted keys, `%.4f`, no timestamps) and proven by re-runs; the record design was validated empirically before it was adopted; tests assert specifics; the registration discipline held through three more addenda.

**Areas for improvement:** the three long stage functions; the analysis pytest suite's absence from CI; gating the live sample on a clean reproduction; the stale reference string in `reproduce.sh`.

---

*Generated by Senior Tech Lead Reviewer Agent*
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":5,"low":6},"excluded":1,"sprint_id":"sprint-271","ts":"2026-10-23T15:40:00Z"} -->
