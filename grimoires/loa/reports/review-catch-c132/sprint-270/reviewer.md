# Sprint 270 (cycle-132 Sprint 2) — implementation report for the reviewer

**Cycle:** cycle-132 "the conclusive review-catch answer" · **Branch:** `feature/cycle-132-conclusive-review-catch` · **Sprint range:** `c3d21fef..e36da85d` (46 commits) · **Lead:** Fable 5.1 then Opus 5.5 (session model change on 2026-10-23); implementers C and D (Opus 5.5, isolated worktrees) · **Binding registration at close:** `REGISTRATION-13.json` sha256 `05fa23fe8c69ce300fd3f704234d9b477e5394ccd2980b4eee383b0f0839a33a`, pipeline pin `fbd36a0c9880b244af08133013f3b6959b085c94` (unchanged since addendum 9).

## What the sprint delivers

Phase 1 of the measurement, run as registered: the smoke, all three PR groups with every registered arm, a look after each group, the positive control, the blind judge on the stratified sample, the contamination hand-reads and the spend posts. The stopping rule ran to the final look, which reads **INCONCLUSIVE**. Fourteen pre-registration addenda (§12) corrected harness, grader, analysis and judge defects that the smoke and the looks exposed. Each was registered before the data it governs was read, and each records both reads.

| Task | Delivered | Where | Evidence |
|---|---|---|---|
| 2.1 pin and freeze | Pin recorded; suite root frozen (`MANIFEST.sha256`, 42 files); self-check 42/42 on grader 1.3.8; codex pre-flight green on every batch (token to 2026-10-28T04:44Z); each batch MANIFEST carries the registration it ran under | `grimoires/loa/evals/ablation-2.0-c132/`, `reports/ablation-2.0/self-check-c132.txt` | runner pre-flight lines in `~/.cache/loa/cycle-132/logs/batch-*.log` |
| 2.2 smoke | smoke2/3/4: `a1_full` ran end to end on 14/14 PRs and `a0_bare` on 14/14; `oracle_closed` on every PR; realized cost ratio full/bare 3.2–22 beside k 9–18 (k unchanged, §11). Smoke rows decide nothing | `evals/results/ablation-2.0/c132-smoke{2,3,4}/`, NOTES 2026-10-21T16:18Z | `smoke-check.sh` table |
| 2.3 G1 + look 1 | 4 batches (a1_full, a0_bare_matched, a1_full_openmount, fable-matched + review-only), 60 cells; look 1 **CONTINUE** (5 valid PRs < 6); positive control "not demonstrated" | `c132-g1-{a1,a2,a3,b}/`, `reports/ablation-2.0/c132-looks/look-1/` and `look-1-amended/` | DEC-0792 |
| 2.4 G2 + look 2 | 4 batches, 40 cells; look 2 **CONTINUE** (Δ̂ +0.105, SE 0.096, CP yes 0.96); positive control pass | `c132-g2-*/`, `c132-looks/look-2/` | DEC-0795 |
| 2.5 G3 + look 3 | 4 batches, 40 cells; look 3 = final look **INCONCLUSIVE** (10 valid PRs, 16 pairs, 122 defects; Δ̂ +0.0971, SE 0.0843, df 9; z_yes 1.15 vs 2.26; RCI [−0.094, 0.288]); a1_full guard tripped (0.39) | `c132-g3-*/`, `c132-looks/look-3/` | DEC-0797 |
| 2.6 judge | 1,903 items (10 per stratum over arm × PR × class), blind Opus 5.5 in 30 sessions of ≤ 64 packets; κ strict 0.199 [0.160, 0.238], lenient 0.274; registered HT corrected figures with a stated bias caveat | `reports/review-catch-c132/judge/`, `a2a/sprint-270/judge/` | DEC-0796, 0798, 0799, 0800 |
| 2.7 close | Rows copied to the tracked `reports/review-catch-c132/rows.jsonl` (140, byte-identical to the look-3 input); `batch-scans.md` (48 invalid units hand-read); batch log; spend table below; this report | `reports/review-catch-c132/`, `a2a/sprint-270/` | — |

## AC Verification

| AC | Status | Evidence |
|---|---|---|
| FR-8 AC 1: suite root per PR with bounds, k, v2 manifests, frozen MANIFEST, self-check log | PASS | 14 `tasks/review-rNN/` with `review_catch.{fixture,manifest,bare_sessions_matched,bare_sessions_matched_fable}`; `MANIFEST.sha256`; `self-check-c132.txt` 42/42 |
| FR-8 AC 2: smoke decides nothing; k table and `oracle_closed` per PR in NOTES before the first batch row | PASS | NOTES "SMOKE COMPLETE" 2026-10-21T16:18:50Z precedes g1-a1's first row (16:47Z); smoke rows live only in `c132-smoke*` batches, which `look.sh` and `final.sh` exclude by name |
| FR-8 AC 3: batch rows in `c132-g1…g3/` and the tracked `rows.jsonl`; every row at the pin; refusal fallbacks and contaminations reported per row | PASS | 140 rows, `source_commit` fbd36a0c on all (make-inputs validates it); refusal fallbacks on 3 rows (a1_full r20-t2; open mount r20-t1 and r24-t2; KF-051); 48 invalid units in `batch-scans.md` |
| FR-8 AC 4: look reads and boundary decisions in NOTES with timestamps; batches stop at a boundary or the cap | PASS | looks at 2026-10-22T06:35Z, 18:10Z, 2026-10-23T07:49Z, each with a DEC row; no boundary fired before the final look; spend USD 3,310 of the 4,200 cap at close |
| FR-4 AC 1: deterministic seeded sampler writes packets and `key.json`; bats pins the strata | PASS | `judge-sample.bats` 24/24 (JS-1…JS-19, incl. the sampling-identity baseline); seed 20261021 |
| FR-4 AC 2: `judge/result.md` with n per stratum, agreement, κ with interval, confusion table, corrected recall/precision per arm | PASS | `reports/review-catch-c132/judge/result.md` (and `a2a/sprint-270/judge/`) |
| FR-4 AC 3: the grader stays primary; judge-corrected figures only under sensitivities | PASS | the looks and the registered decision use the grader only; the judge result feeds `--final` as a sensitivity in Sprint 271 |
| Every batch MANIFEST carries `registration_sha256` equal to the registered hash | PASS with stated lineage | every batch carries the registration binding at its launch (REGISTRATION-8 for G1 and g2-a1; REGISTRATION-10 from g2-a2); addendum 11 makes the read accept the declared `supersedes` chain, verified on disk from REGISTRATION-13 back to REGISTRATION.json with nothing unresolved; "Rows by registration" printed in every look |
| The positive-control read and its mechanism evidence recorded before any other read | PASS | look 1 records the control (exposure in r14-t2 and r15-t1, the oracle detector's `oracle_exposed_defects`); amended per §8 by addendum 10; pass at looks 2 and 3 (9 exposed open runs) |

## Registration lineage (Sprint 270)

| file | sha256 | pin | addendum | what it corrects |
|---|---|---|---|---|
| REGISTRATION-1 | 277a6eff… | 664c4516 | 1 | runner arm-id guard: PR-native arm ids |
| REGISTRATION-2 | 857669e7… | 5af8b80e | 2 | dissent budget 600 → 1,200 c; `dissent_present` took-effect rule |
| REGISTRATION-3 | 57304181… | 51a55a98 | 3 | spend meter reads the live results-root rows |
| REGISTRATION-4 | f2c0e8f9… | 09fb0900 | 4 | grader 1.3.6: `hidden` class for build tasks only |
| REGISTRATION-5 | 6ad2e34e… | 426c6c3d | 5, 6 | adapters pinned in the closed mount (KF-050); class-9 repo_named telemetry and sensitivity; run cap 45 |
| REGISTRATION-6 | 6205eaf5… | 3d6f6a40 | 7 | grader 1.3.7: `suite_path` for build tasks only |
| REGISTRATION-7 | a31e5942… | 9544948b | 8 | grader 1.3.8: class-7 PR-native read exemption; per-class contamination sensitivity |
| REGISTRATION-8 | 614bcea5… | fbd36a0c | 9 | whole `.claude/` pinned; oracle-exposure sensitivity rows (the structural limitation) |
| REGISTRATION-9 | ae0b1da6… | fbd36a0c | 10 | analysis: positive control per §8; §5 co-reads at every look |
| REGISTRATION-10 | 13cbd850… | fbd36a0c | 11 | analysis: rows under predecessor registrations readable (supersedes chain) |
| REGISTRATION-11 | 2f6909d2… | fbd36a0c | 12 | judge sampler: PR-native arm ids are not provenance |
| REGISTRATION-12 | 9a0dda4b… | fbd36a0c | 13 | judge sampler: cited paths resolved as the grader credits them |
| REGISTRATION-13 | 05fa23fe… | fbd36a0c | 14 | judge packets: real defect descriptions; report title |

Addenda 10–14 are analysis- or judge-only. `register-addendum-analysis.sh` builds them at the unchanged pipeline pin after checking that `.claude/`, `evals/harness` (except the two judge tools), `evals/suites`, `evals/fixtures`, the suite tasks and the suite manifest are byte-identical between the pin and HEAD.

## Outcomes per arm (intention to run)

| arm | planned cells | valid | excluded | main causes |
|---|---|---|---|---|
| a1_full | 28 | 17 | 11 | oracle exposure on the PRs that modify `.claude/` (6); contamination (5: class-7 report heredoc, /home probe, two absent-path probes, one jq probe; r20-t2 also carries a refusal fallback) |
| a0_bare_matched | 28 | 25 | 3 | matched cells below ⌈k/2⌉ valid sessions (r22 ×2, r20-t2): jq-binary downloads, upstream-repository reach, one took-effect FAIL |
| a0_bare_fable_matched | 28 | 28 | 0 | — |
| a1_review_only | 28 | 20 | 8 | oracle exposure (7: r15 ×2, r16-t2, r19-t1, r20 ×2, r21-t2); 1 class-7 contamination |
| a1_full_openmount | 28 | 23 | 5 | contamination on r22 ×2 and r24 ×2 (test inputs, one grader false positive); a refusal fallback on r20-t1 (oracle exposure is not applied to this arm, §4) |

## Contamination hand-reads (`batch-scans.md`, 48 invalid units)

The units fall into five shapes. **Nine** are reaches for the upstream repository (a clone, an `ls-remote`, or fetches of files from `main`), all by bare matched agents on pr-19 and pr-20; no pipeline arm reached. **Fourteen** are jq 1.7.1 downloads or connectivity probes that do not name the repository, thirteen of them on pr-22. **Twelve** are fictional paths or the repository token inside test inputs that reviewers fed to the PR's own guard or grader code. **Six** are grader false positives: a sed or awk address such as `/re/d` read as a two-component path. Those cost sessions but never a primary cell. The rest are three environment probes, two absent-path probes, one report written through a heredoc and one took-effect FAIL caused by PR hook code (KF-053). Every unit stays invalid on the primary as registered (DEC-0791), and bead bd-kddde holds the grader 1.4 work.

## Judge (Task 2.6)

The registered sample is 1,903 items: 10 per stratum over arm × PR × class, about twelve times the 150 floor, which §7's USD 30 reserve had been sized on. Two runs before the registered one were caught and set aside. A pilot exposed packets missing their cited code (302 of them), fixed by addendum 13. Run 1 then showed every defect only as its id, fixed by addendum 14; run 1 is kept as an invalid-run record. Run 2 is the §9 judge.

- **Agreement:** strict κ 0.199 [0.160, 0.238] and lenient κ 0.274 [0.230, 0.318]. Run 1 read 0.219, so the descriptions barely move it: the low agreement belongs to the ±3 rule, not to the packets.
- **Arm symmetry:** on grader-credited citations the judge says "describes" 19–23 % of the time in every arm, plus 8–13 % "partially". The proximity grader inflates every arm's absolute recall by a similar factor.
- **Registered HT corrected recall (strict):** a1_full 0.015, matched bare 0.052, fable 0.057, open 0.057, review-only 0.091. It is not an arm comparison. The registered rule removes 1/m of a defect's credit per rejected citation, and m, the citations per credited defect, is 4.30 for a1_full against 2.51 for matched bare. DEC-0800 records the caveat and declares an exploratory defect-level judge read for Sprint 271.

## Spend

| item | USD |
|---|---|
| G1 batches (4) | 1,052.0 |
| G2 batches (4) | 835.9 |
| G3 batches (4) | 930.3 |
| smoke (2/3/4 + the superseded first smoke) | ≈ 410 |
| judge (pilot 0.73, run 1 20.97, run 2 21.35) | 43.1 |
| reboot-interrupted attempts, unmetered (priced from transcripts) | ≈ 20.2 |
| **cycle meter at close** (`spend.sh --since 2026-10-21T00:23:00Z`, incl. Phase 0 and the judge rows) | **3,309.99** of the 4,200 cap (+ ≈ 20.2 unmetered) |

## Deviations, stated

1. **Fourteen addenda.** Each corrected a defect a smoke row, a look or a judge pilot exposed, and each was registered before the data it governs was read. Addenda 1, 4, 7, 8, 12 and KF-053 share one cause: guards written for build tasks or for framework leakage fired on PRs whose content is this harness itself.
2. **The structural limitation (addendum 9).** Nine PRs modify `.claude/`, and the pinned pipeline reading its own fixed files is oracle exposure under §4. That exposure is why the a1_full guard is tripped. The registered oracle-exposure rows are the second read.
3. **Operational incidents:** a host reboot (KF-052), a tool-call timeout that killed a detached runner (KF-052 rec 3, now structural: bead bd-yvjew), and one took-effect pause cleared with `--clear-arm` (KF-053). Each was recovered with `--resume` under the runner's attempt rules, with no rule change.
4. **The lead session model changed** from Fable 5.1 to Opus 5.5 on 2026-10-23. Arms and judge are unaffected: arm and judge models are pinned in the registration and the batch commands.
5. **The positive control runs on every group, as §8 registers it.** The sprint plan's "on G1" wording predates the Flatline amendment. Addendum 10 aligned the module.

## Commits (c3d21fef..e36da85d)

The fix commits are 664c4516, 5af8b80e, 51a55a98, 09fb0900, 426c6c3d, 3d6f6a40, c2408392, 9544948b, 350e52cf, fbd36a0c, 2f023159, 0d1fe51e, c1948aa7, fc31c990 and 6ee50833. The registrations are f209c566, 9ee9ad15, dff97c93, ca71fbc7, 70d1e21a, bb00f2c4, c57a5315, 984b3fc8, eb109f0d, cee7601f, 993928d2, 81d13ea0 and be54cbc0. The looks are 2616407f, 593148c8, fd771dee and 9f5746b3. The judge and report commit is 0d3caff7, and the driver copies for reproduction are e36da85d. Known-failures updates are f187b10f, 41314915, 66feca0e, bc7d0697 and d3589eea. Decision rows are be948217, 48607e55, 7d0d3b5d, 058f6cdf, 3aef5b27, 5ff0fdda and 1e521a0b.

## Tests at close

`evals/analysis/c132/tests` 149 passed. `judge-sample.bats` 24/24 and `defect-descriptions.bats` 5/5. Each addendum round ran its own bats: pipeline-run, sandbox-mount, took-effect, ablation-grade, spend and run-ablation, recorded in its commit.
