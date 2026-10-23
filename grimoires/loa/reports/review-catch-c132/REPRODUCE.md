# REPRODUCE — cycle-132 "the conclusive review-catch answer" (PRD FR-10; PREREGISTRATION §13; DEC-0811, DEC-0812)

Every grade, row and read of the measurement is re-derived from a fresh clone of the stage-1 record commit by one script. Nothing below needs the lead's working tree.

## 1. Clone the record

```
git clone --branch record/cycle-132-conclusive-review-catch --single-branch https://github.com/0xHoneyJar/loa.git c132-record
cd c132-record
git rev-parse HEAD      # stage 1 = b15e546e649f98d81378ad3c6261525925b88a1c; stage 1b = 3be895f230aa1eef6137e632bffc26dc274c5e5f (one commit on top, the live-rerun flag fix of addendum 18) is what the branch points at before the merge: `git rev-parse HEAD^` must print b15e546e…; stage 2 appends the reproduction report and the gate records
```

The record is the cycle tree at the Sprint 271 head plus the gitignored records: `grimoires/loa/a2a/` (sprints 269–271, the bug micro-sprints, Flatline consensus records, annotation packets and labels, dissent envelopes), `grimoires/loa/NOTES.md` and its archive, the judge files, `evals/results/ablation-2.0/runs.jsonl`, every `c132-*` batch and smoke record (MANIFEST, STATUS, logs, rows; per run directory `grade.json`, `meta/`, `transcripts/`, `eval/`, `grading/gates-combined.md`; never `sandbox/`, `snapshots/` or `grading/pr/`), and the sandbox-lite tree `evals/results/ablation-2.0/c132-lite/` — per run directory the agent's outputs (`review.md`, everything under the sandbox's `grimoires/`), the sandbox copies of the key's defect files, every `pr/` file that differs from the tracked fixture, and `sandbox-manifest.json` listing every sandbox file with its sha256.

## 2. Environment

Docker with the image `loa-ablation:258` at digest `sha256:4e37cb5fd4d85c3231b3ef11a0d6179b5a5452bc024c23a26a1bea2668e86f5f` (REGISTRATION-15 `image_digest`), python3 ≥ 3.11 (stdlib only), jq, bash ≥ 5. The pinned pipeline (`evals/harness`, `evals/suites`, `evals/fixtures`, the suite root's `tasks/` and `MANIFEST.sha256`) is byte-identical between the pin `fbd36a0c` and the record head; `reproduce.sh` asserts both before doing anything.

## 3. Reproduce

```
evals/analysis/c132/reproduce.sh --scratch /tmp/c132-repro --jobs 4
```

The script (header: `evals/analysis/c132/reproduce.sh`) reconstructs every recorded run directory (142 cells — 86 pipeline cells and 56 matched cells with 438 sessions — plus the smoke runs are in the record; the group batches are what the reads use), re-grades every session and cell with `ablation-grade.sh` in the container (`--union` per matched cell), re-rows every tracked row with `ablation-row.sh` exactly as the runner called it, re-runs `reads-c132.py --make-inputs`, `--final` (with the judge directory and the label-set re-grades) and `--placebo` under `REGISTRATION-15.json` (the registration the tracked reads were taken under), compares every artefact's sha256 with the record and writes `grimoires/loa/a2a/sprint-271/reproduction/report.md`. Exit 0 means every comparison equal; exit 1 names the differences in the report. About 10 minutes with 4 jobs on a 2024 workstation.

## 4. Expected hashes (the tracked artefacts in this directory and beside it)

| artefact | sha256 |
|---|---|
| `grimoires/loa/reports/review-catch-c132/rows.jsonl` (140 rows) | `522e1980a1cca46bd3132c83abba8512b7b847acb951d8d98e9e7f7b3f7e41ad` |
| `grimoires/loa/reports/ablation-2.0/c132-final/INPUTS.json` | `17725093540e47b7c14f362a14536c84eec523b41df4b497af11c9170e7abb62` |
| `c132-final/final.md` (= `reads.md` here) | `0e4a42f4f01f9a79478a291939aacf7683e401a0e74465e0ecba39ee46d52db7` |
| `c132-final/final.json` (= `reads.json` here) | `17bf0668777d8eb222b46bea51007620210340cacdc4091a4659c3cb304923bd` |
| `c132-final/placebo-phase1.md` | `346244fced08bb825d4b9c986e400994464a517f6f6a94884177c0b65ec5b8c3` |
| `c132-final/placebo-phase1.json` | `ca52c25efe080585042fd295aa7be07c0604b647ae46f79bbd066993d0b108f0` |
| `REGISTRATION-15.json` (binding for the reads) | `c9d98acb2668dabb4e7a9e3942bc6f1d880997cfe1e3e8c5cbc25cf42906eeb9` |
| every cell `grade.json` | `INPUTS.json` `cells[*].grade_sha256` (140 entries); every session grade: the recorded file in the record |

Seven recorded run directories carry no `grade.json`: runs the runner never graded — pipeline status `running` or `interrupted` (killed by the host reboots of 2026-10-22) or a session superseded before grading. The reproducer does not grade them either; the report lists them under *Not graded in the record*, excluded from every count.

## 5. Live rerun (DEC-0812; needs model credentials; about USD 50)

```
evals/analysis/c132/reproduce.sh --scratch /tmp/c132-repro --jobs 4 --live-sample --max-usd 110
```

Reruns review-r24 in `a1_full`, `a0_bare_matched` (k 11) and `a1_review_only`, one trial each, with `run-ablation.sh` at the pin under REGISTRATION-15 (the tracked image self-check log passed as the batch driver did; the runner's conservative plan estimate is USD 104, the recorded cost USD 50), into `<scratch>/live`, and appends to the report each rerun grade against the recorded arm range on review-r24 (both recorded trials). A grade inside the range confirms the apparatus; one outside is a named discrepancy.

## 6. What the reproducer reports

The report's hash table (recorded vs reproduced per artefact class), the environment block, every difference by path with both hashes, and the live-rerun table. The lead copies the report to `grimoires/loa/reports/review-catch-c132/reproduction/report.md` and the record's stage 2 appends it; `report.md` § Proof links both.
