All good

APPROVED - LET'S FUCKING GO

Sprint 271 passes the security and quality audit. Eight findings, two medium and six low, none blocking: five from the audit dissent (run 2 of 3; the claude-headless companion raised them, gpt-5.5-pro raised none) and three of the auditor's own. Each was verified against the code and against the recorded run; none alters a grade, a row, a read or the proof, and all are filed as follow-up beads instead of being patched in the proof apparatus between the proof and the Bridgebuilder round (DEC-0816).

# Sprint 271 Security Audit Feedback

**Auditor:** lead (Fable 5.1, auditing-security contract). The audit used the sprint's second dissent run (`adversarial-audit.json`: gpt-5.5-pro primary, 0 findings; claude-headless companion, 5 findings, `independent_voice`; status clean, not degraded, hallucination filter applied with 0 downgrades, no rejected payloads or sidecars). One dissent run remains for this sprint.
**Date:** 2026-10-23
**Scope:** `03e12ed0..3407ba63`, 965 paths. Code: `evals/analysis/c132/` (`reads.py`, `stats.py`, `regrade_labels.py`, `record_lite.py`, `reproduce.sh`, `judge_defects.py`, tests), `evals/tests/c132-report.bats`, `grimoires/loa/reports/review-catch-c132/scripts/` (`final.sh`, `report-assemble.py`, `run-judge-defects.sh`). Artefacts: the report and its reads, the registration chain REGISTRATION-15 → 16 → 17 at the unchanged pin `fbd36a0c`, the sandbox-lite record and the public record branch (stage 1 `b15e546e`, stage 1b `3be895f2`), the reproducer's two fresh-clone runs and the DEC-0812 live rerun, the exploratory judge sessions, the rc.7 release commit. The pinned pipeline (`evals/harness`, suites, fixtures, `.claude/`) is byte-identical to the pin; nothing shipped by default changes.
**Review:** `engineer-feedback.md` APPROVED, 0 critical / 0 high / 5 medium / 6 low, 1 excluded (dissent run 1).
**Working file:** `grimoires/loa/a2a/audits/2026-10-23/SECURITY_ANALYSIS_TODO.md` (sources, sinks, trust levels); machine-readable findings in `grimoires/loa/a2a/audits/2026-10-23/findings.jsonl`.

---

## Verification performed by the auditor

- `python3 -m pytest evals/analysis/c132/tests -q`: 182 passed (68 s). `bats evals/tests/c132-report.bats`: 3/3.
- `judge_defects.py aggregate` re-run on the tracked `key.json`, the ten session label files and `rows.jsonl` into a temporary directory: `result.json` and `result.md` byte-identical to the tracked files, exit 0 (this is the check behind the review's excluded finding, below).
- `audit-secret-redaction-scan.sh` over the 965 changed paths: exit 0, no hit. A secret-pattern grep (Anthropic/OpenAI/AWS/GitHub key shapes, private-key headers) over the public lite tree `evals/results/ablation-2.0/c132-lite`: no hit. The credential-named paths in that tree are source files of the cheval credential module, test fixtures and perf-cache token counts, confirmed by content; the per-run credential copies live outside `sandbox/` and were never in the lite set.
- `check-loa.sh`: all checks passed. The release commit's System Zone footprint is `.claude/checksums.json` and the version stamp on line 1 of `CLAUDE.loa.md`; the integrity hash in that stamp is unchanged, and the writes went through `update-loa-bump-version.sh` under a bounded framework marker that was removed in the same command.
- `security-audit-scope.sh` (bare, 66 s): the repository inventory shows no new controller, route or handler surface; the sprint adds analysis-side tooling only.
- The code regions each finding anchors to were read in full (`reproduce.sh:25-100`, `record_lite.py:83-97` and `:478-515`, `judge_defects.py:477-492` and `:586-592`, `regrade_labels.py:288-305`, `final.sh`, `run-judge-defects.sh:1-25`).

## Dissent triage (run 2 of 3)

The companion's five findings, each checked against the code and the record. The dissent's own severities are kept; the tally below counts them with the auditor's.

- DISS-C-001 (medium, `reproduce.sh:46-47`): the attestation `pin_tree_identical_to_head` compares the pin with HEAD, two commits, while everything executed is read from the working tree, and `evals/analysis/c132` is not in the compared set. **Confirmed as written.** The sprint's own evidence is unaffected: both reproducer runs were fresh clones (`clone_head` `b15e546e`, then `3be895f2`, recorded in `environment.json`), clean by construction. The hazard is a third-party rerun in a modified checkout whose report would still say "identical". Counted (DO-001).
- DISS-C-002 (low, `reproduce.sh:66-73`): `--no-env-check` records an image or pin mismatch but does not stop the paid live sample, and the runner's DEC-0435 gate is satisfied by the tracked historical self-check log rather than a fresh self-check. **Confirmed as written**; it composes with the review's DISS-C-004 (the live step is not gated on the engine's exit code either). In this sprint the environment check was on, image and pin matched, the engine exited 0 before the live step, and the first live attempt was refused by the runner's own gate with no spend. Counted (SEC-001).
- DISS-C-003 (low, `judge_defects.py:477-487`): `write_sample` refuses a non-empty packets directory but overwrites `key.json` unconditionally, item ids restart at `D0001`, and `aggregate` binds labels to the key by item id only; with `run-judge-defects.sh:7` reusing a filled chunk directory, a re-sample after clearing the packets could attribute old labels to new pairs silently. **Confirmed as written**; same class as the review's DISS-C-007. This run is unaffected: the chunk directory started empty, the sample is deterministic (byte-identical to its dry run), and the aggregation re-derived byte-identically above. Counted (SEC-002).
- DISS-C-004 (low, `record_lite.py:85-96`): `sha256_file` memoises by an `lstat` tuple (dev, inode, size, mtime_ns) while reading through `open()`, so a same-size same-mtime in-place rewrite within one process returns a stale digest. **Confirmed for the in-process rewrite; the symlink branch is not reachable** (`scan_sandbox` records links as `type: symlink` without hashing; `reconstruct_run_dir` refuses `islink` before hashing). Within `reproduce` every hashed file is written once and the grader writes fresh files, so no in-process rewrite happens today. Counted (SEC-003).
- DISS-C-005 (low, `final.sh:10`, cross-file to `reproduce.sh`): the tracked driver `source`s `~/.cache/loa/cycle-132/registration.txt` as shell code and `cd`s into one operator's home path (also `run-judge-defects.sh:5`). **Confirmed as written.** The provenance of the tracked reads does not rest on that cache: `reads-c132.py` validates the `--registration` file and writes its sha256 (`c9d98acb…`, REGISTRATION-15) into `INPUTS.json` and `reads.json`, and the reproducer re-derived the reads from the tracked registration without the cache file. Counted (SEC-004).

Rejected dissent payloads: none (`rejected_count` 0, no sidecar).

## Findings

### Medium

- **MEDIUM** (confidence: high) `evals/analysis/c132/reproduce.sh:46-47` — DO-001. The pipeline-identity attestation checks HEAD against the pin, not the working tree that executes, and omits `evals/analysis/c132`; a reproduction from a modified checkout would report "byte-identical to the pin". Fix: `git diff --quiet "$PIN" -- <paths>` against the worktree, `git status --porcelain -- <paths>` empty unless `--no-env-check`, `git describe --always --dirty` recorded, the analysis directory added to the set or the field renamed. Changes the proof apparatus → re-run Task 3.3b after it. Bead bd-jat0z.
- **MEDIUM** (confidence: high) `.github/workflows/bats-tests.yml:182-191` — DO-002. The pytest step runs adapter and maintenance suites only; the 182-test analysis suite never runs in CI (predates the sprint; the sprint's bats case does run). One line. Bead bd-yroj0.

### Low

- **LOW** (confidence: medium) `evals/analysis/c132/reproduce.sh:66-73` — SEC-001. The live rerun is not gated on `rc == 0` or on a passing environment check; the self-check it presents to the runner is historical; the `--pre-registration-ref` text hard-codes `REGISTRATION-16.json`; a refused live run exits 1 like a discrepancy; the recorded range includes invalid rows. Bead bd-161zz.
- **LOW** (confidence: medium) `evals/analysis/c132/judge_defects.py:477-487` — SEC-002. Labels are bound to the sample by item id only; `key.json` is overwritten when the packets directory is empty; the chunk directory is reused. Fix: refuse an existing `key.json`, a sample id in every packet and in `labels.json` that `aggregate` checks, the chunk directory keyed by the key's sha; and make `aggregate` load the grades so its validity filter cannot diverge from the sampler's (the review's DISS-C-001 residual). Bead bd-xr3uq.
- **LOW** (confidence: medium) `evals/analysis/c132/record_lite.py:86-97` — SEC-003. The digest cache is keyed by an `lstat` tuple; hash always on verification paths (reconstruct, compare, `--check`) and keep the cache for the build-side fixture map, or key on `realpath` plus a following `stat` including `st_ctime_ns`. Bead bd-ombvn.
- **LOW** (confidence: high) `grimoires/loa/reports/review-catch-c132/scripts/final.sh:10` (and `:8`, `run-judge-defects.sh:5`) — SEC-004. The tracked driver sources an unversioned cache file as code and hard-codes an operator home path. Parse the three values with a whitelist or pass them as arguments; derive the root from `BASH_SOURCE` as `reproduce.sh` does. Bead bd-o3a5h.
- **LOW** (confidence: medium) `evals/analysis/c132/record_lite.py:499-501` — SEC-005. A manifest symlink's `target` is recreated unvalidated in the scratch sandbox; no read follows it today (the grader drops symlinks when it copies `pr/`, `read_regular` refuses them), but REPRODUCE.md invites third parties to run against a clone. Validate with `safe_rel` or record links without recreating them. Bead bd-ombvn.
- **LOW** (confidence: high) `evals/analysis/c132/record_lite.py:424` — CQ-001. `build --only` writes `INDEX-only.json` and the stage-1 script requires `INDEX.json` (a partial build cannot pass as the record, good); neither name appears in `REPRODUCE.md`. Bead bd-ombvn.

## Review demotion confirmed independently

The review trailer excludes one finding: dissent run 1 DISS-C-001, a high marked blocking by the voice, which claimed the exploratory aggregation "can never run" because `run()` judges cell validity from the row alone while the sampler used the grade. The auditor re-ran the aggregation on the tracked inputs (above): exit 0, `result.json` and `result.md` byte-identical to the tracked files, 40 of 40 pairs judged in every arm. The row carries every field `validity()` reads, so the two filters agree on these rows; the residual hardening (load the grades in `aggregate`) is carried in bd-xr3uq. The demotion stands: speculative, confidence low; `excluded_confirmed` 1.

## Severity tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 2 |
| Low | 6 |

## What was audited, and how it stands

- **Credentials and secrets.** No credential enters the lite record or the tracked artefacts (scans above). The blind judge sessions copy no credential file and the taint check is clean; the live rerun authenticated from the operator's environment inside the runner's own gates and spent USD 51.33 under the 110 cap. The record branch is public; the stage-1 script runs the secret scan before every commit and the ICE wrapper is the only push path.
- **Input validation and symlinks.** Manifest paths pass `safe_rel`; session `run_dir`s match an anchored regex and must not be links; the lite set refuses a symlink in any path component before any write; `--out`/`--work`/`--roots` are refused inside the results or suite roots and on another filesystem; hard-link copies exclude the only two paths the grader writes, and the 140 rows re-derived byte for byte after the re-grades prove the record's `meta/`, `eval/` and transcripts were not written through the links. The one gap is the recreated symlink target (SEC-005).
- **Integrity of the record.** Every grade, row and read was re-derived from a fresh clone of the record, twice; the aggregation re-derived here; the registration chain resolves and `register-addendum-analysis.sh` asserted pipeline identity at each addendum. The attestation gap (DO-001) and the digest cache (SEC-003) weaken what a third party can prove from a run of their own, not what this run proved.
- **Command execution.** `subprocess.run` argument lists throughout, no shell; `reproduce.sh` quotes every path and refuses `:`/`,`; the two driver scripts' `source` of a cache file (SEC-004) is the only code-from-data path, local to the operator's machine.
- **Egress and blinding.** Unchanged from Sprint 270: class 9 detects repository reaches after the fact (bd-ijxuk moves the boundary to the container network); judge packets pass the provenance scan with PR-native exemptions recorded in `key.json`; the defect-level judge is labelled exploratory in every table.
- **Access control and release.** Protected branches are untouched; the System Zone changed only through the sanctioned bump script under a marker that expired with the command; rc.7 was cut after the reads and the proof, as the PRD requires.
- **Documentation.** `REPRODUCE.md`, `report.md` § Proof, `CHANGELOG.md` (`## [2.0.0-rc.7] — 2026-10-24`), `README.md` (version, badge, `--tag v2.0.0-rc.7`), `.loa-version.json` and the release notes agree with each other and with the record commits; the stage-1b commit is named in both REPRODUCE.md and the report. No per-task documentation-coherence reports exist for this sprint (none did for Sprint 270); the auditor verified the documents manually. The one gap is CQ-001.

## Residual risk, stated

- Until bd-jat0z lands, a third-party reproduction from a modified checkout can produce a report that claims pipeline identity. The two recorded runs are not exposed to this (fresh clones, heads recorded).
- Until bd-161zz lands, a reproducer who passes `--no-env-check --live-sample` can spend against an unverified image and get a pin-framed table. The default path refuses on mismatch.
- The judge's defect-level read is exploratory and decides nothing; SEC-002 bounds what a careless re-sample could corrupt in it.
- Class 9 remains a detector (Sprint 270 residual, unchanged).

## Decision

None of the eight findings is patched in this sprint. Every affected file is part of the proof apparatus whose bytes the stage-1b record and `REPRODUCE.md` attest, the sprint plan's own rule re-runs Task 3.3b for a fix that touches the analysis, and the Bridgebuilder round of Task 3.6 may add more; the fixes are filed as beads (bd-jat0z, bd-yroj0, bd-161zz, bd-xr3uq, bd-ombvn, bd-o3a5h) and the Task 3.6 triage decides whether any is pulled into this cycle with one reproduction re-run (DEC-0816).

---

*Generated by the Paranoid Cypherpunk Auditor (lead)*
<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":2,"low":6},"excluded":0,"excluded_confirmed":1,"sprint_id":"sprint-271","ts":"2026-10-23T15:51:18Z"} -->
