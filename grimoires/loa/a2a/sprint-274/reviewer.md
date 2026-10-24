# Sprint 274 (cycle-133 Sprint 3) — Implementation Report

**Sprint:** Sprint 3 — the product (global 274) · `grimoires/loa/sprint.md` § Sprint 3
**Run:** `run-20261024-ca505ad4` (`/run sprint-plan`), branch `feature/cycle-133-follow-through`, base `de366cc63` (the Sprint 2 head + KF-037 commit at dispatch) → Sprint 3 head ``0d51dcf45` (the close commits follow)`
**Implementers:** A (Task 3.1 — home-scope mount; follow-up s3-a2), B (3.2 — finding contract and grader 1.5), C (3.3 — external seeding, registration v2, guidance), D (3.4 — docs; 3.6 — drift-test removal after the smoke), D4 (s3-e — the KF-058 egress gap found by CI on the Sprint 273 head), lead (3.0 spike, 3.5 pin and smoke, 3.7 close). All implementers Opus 5.5 in worktrees `../loa-wt-s3{a,b,c,d,e}` cut from `de366cc63` (`c31aad7cc` for D4); the lead Fable 5.1.
**Briefs:** `~/.cache/loa/cycle-133/briefs/{common-s3,s3-a,s3-b,s3-c,s3-d,s3-e}.md`; patches `~/.cache/loa/cycle-133/patches/s3-*.patch`; the implementers' reports beside this file as `reviewer-{a,b,c,d,e}.md`; the spike record `spike-3.0.md` + `spike-3.0/`.

## Status

Landed in the planned order C → B → A → D (D's docs landed early, before the spike), with D4's egress fix between B and A: C `08843c515` (Task 3.3), B `9462a4016` (3.2), DEC `85ad4b68b` (DEC-0909 … 0927), D4 `874fc64a9` (KF-058), KF/DEC `b77edf20e` (DEC-0928 … 0932), A `1e54af937` (3.1 + README § Mount modes), DEC `0e55e00b3` (DEC-0933 … 0941), suite `db668858d` (smoke task), s3-a2 `55f4b58fb` (clause (f) widened), pin 1 `32a8d79cf` (DEC-0942/0943), KF-059 guard `9af4d44e8`, floor amendment `92aa210d6` (DEC-0946), s3-a3 `7d2119477` = pin 2 (DEC-0947 … 0949), smoke evidence `a0227e9fd` (DEC-0950 … 0952), runner test counts `0d51dcf45`. D's Task 3.4 docs landed in `c31aad7cc` (Sprint 273 close window) with the lead's CI fixes. The spike (Task 3.0) confirmed design (a′): DEC-0908.

## AC Verification

| AC | Status | Evidence |
|---|---|---|
| PRD FR-10 AC 1–4 (positive-evidence clause (f) and negative control with distinct PR and pinned bytes; the smoke at the measurement pin within the USD 40 share with the launch rule; design-neutral bats incl. executing SKILL.md, hook, script, deletion, rename, symlink, `.mcp.json`, root `CLAUDE.md`, rules, output styles, plugins, and clause (g) proving no planted item loaded or executed; docs). A failed smoke leaves G-4 incomplete and defers FR-10 with a DEC row. | ⏸ [ACCEPTED-DEFERRED] | Delivered: positive-evidence clause (f) and the negative control (`evals/tests/fixtures/home-scope-nc/SHA256SUMS:1`, distinct PR and pinned bytes; `evals/tests/sandbox-mount-home-scope.bats:1` HS-1 … HS-14 incl. executing SKILL.md, hook, script, deletion, rename, symlink, `.mcp.json`, root `CLAUDE.md`, rules, output styles, plugins; clause (g) in HS-12); docs `evals/harness/README.md:1` § Mount modes. The smoke ran twice at recorded pins within the USD 40 share with the launch rule (run 1 `grimoires/loa/reports/ablation-2.0/c133-smoke/run-1/rows.jsonl:1` USD 11.54; run 2 `grimoires/loa/reports/ablation-2.0/c133-smoke/run-2/rows.jsonl:1` USD 9.30) and FAILED clause (f) both times (`run-2/meta/took-effect.json:1`): the reviewer consults its installed framework copy in HOME as the reference for a Loa PR (KF-060). Per the AC's own last sentence G-4 is incomplete and FR-10 is deferred with DEC-0950 (NOTES Decision Log 2026-10-24T13:55Z); follow-up bead bd-ivmtk. |
| PRD FR-11 AC 1–4 (four validators refuse missing/boilerplate/conflicting/outside-repo findings and normalise aliases with the warning; judged recall and unjudged count; stale verdicts rejected; grader 1.5; cycle-132 chain still verifies; templates and persona carry the field) | ✓ Met | `tests/unit/finding-conformance.bats:1` FC-1 … FC-7 (python, jq, zod and the markdown grammar agree on 47 vectors: 18 valid, 29 invalid incl. one-word clause, denylist, outside-repo path, alias conflict); `tests/unit/adversarial-review-normalise.bats:1` NRM-C133-1 … 5 (alias warning once per alias per run, differing pair refused, the four cycle-132 envelopes replay byte-identical); `evals/tests/ablation-grade.bats:1` AG-c133-J1 … J8 (`--judge-verdicts`: recall_judged, judged/unjudged counts, stale row refuses exit 2, supersedes chain, run_id); `evals/analysis/c132/tests/test_judge_read.py:1` (5: `--judge-defects` under v2, v1 refused); `registration.py verify` 18/18 cycle-132 registrations; `.claude/skills/reviewing-code/resources/templates/review-feedback.md:1` and `.claude/skills/auditing-security/resources/templates/sprint-audit-feedback.md:1` carry the clause; `.claude/skills/bridgebuilder-review/resources/BEAUVOIR.md:1` asks for `failure_scenario`; `tests/unit/verdict-derive-failure-clause.bats:1` VFC-1 … 12 |
| PRD FR-12 AC 1–2 (three dry-runs pass `--check`, no model call; refusals for symlink, submodule, oversize, licence, leakage; `looks_seen` verifier cases; v1 chain verifies) | ✓ Met | `evals/fixtures/external-candidates.md:1` (three public candidates dry-run with `--check` clean, 0 model calls); `evals/tests/seed-corpus-from-external.bats:1` (20: symlink, submodule, non-regular, oversize via trees-API sizes, licence outside the allowlist, PR.md leakage, credential hit — every refusal exit 2); `evals/analysis/c132/tests/test_registration_v2.py:1` (13: ordering, integrity, completeness, self/successor refusal, v1 byte-identity); `evals/tests/corpus-seed-lib.bats:1` (transcript-golden byte identity of the record seeder) |
| Review APPROVED, audit APPROVED, ≤ 3 dissent runs | ⏸ pending | review and audit follow this report (dissent runs 1 and 2 of 3) |

### Seams under test (sprint.md)

| Seam | Result |
|---|---|
| A planted project-scope hook under the HOME-scope mount | spike arm `user`: 0 project canaries (`a2a/sprint-274/spike-3.0.md`); HS-12 (a stubbed pipeline run: `--setting-sources user` on every phase, PR data only at the root, (g) reads the process samples); the smoke's clause (g): run 1 and run 2: no project hook, MCP server, canary or PR `.claude/` script executed — clause (g) PASS in both (`c133-smoke/run-2/meta/took-effect.json:1`); the failing clause was (f) |
| The negative-control fixture (cycle-132 mount) through clause (f) and the grader | `evals/tests/fixtures/home-scope-nc/` (distinct PR and pinned bytes); HS-10/HS-11 (`pinned_bytes_read` fails (f)) |
| A finding with a one-word `Failure:` clause through all four validators | `finding.vectors/invalid/01-one-word-clause.json` refused by python, jq, zod and verdict-derive (FC-1 … 4; VFC-1: an invalid CRITICAL never approves) |
| An external repository with a symlink and a submodule | `seed-corpus-from-external.bats` (symlink, submodule and non-regular entries refuse before any blob is materialised) |

## Tasks Completed

| Task | Delivered | Where | Evidence |
|---|---|---|---|
| 3.0 Spike (lead) | three `claude -p` arms in `loa-ablation:259` under the egress block (`--setting-sources ""`, `user`, `user,project`) with a canary per surface item; `user` loads the user scope only, `""` nothing, `user,project` every project item; `local` governs `CLAUDE.local.md`/`settings.local.json`; project `.claude/plugins/` is not a load location; design (a′) confirmed | `a2a/sprint-274/spike-3.0.md`, `spike-3.0/{none,user,both}/`, driver `spike-3.0/driver.sh` | DEC-0908; spend USD 0.027 |
| 3.1 Loa reviews Loa (A) | `mount_home_scope` (five reversible redirect rules through `LOA_FRAMEWORK_ROOT`, residual refuses, verify), `surface()` for 2.1.299, home-scope launch path in `pipeline-run.sh` (HOME first, PR head overlay, `--setting-sources user`, `docker top` sampler, `mount.json`, `home-integrity.json`), clauses (e)–(g), negative control; pinned-root byte-identical | `1e54af937`; s3-a2 `55f4b58fb` (HS-13); s3-a3 `7d2119477` (dissent under home-scope: project-root climbs resolve to the workspace via `LOA_PROJECT_ROOT`, R5 slash-only, persona surface; HS-14; 208/208 lead-side) | HS-1 … 12 (9 of 10 red first); 352/352 across eleven suites on the merged tree |
| 3.2 One finding contract and grader 1.5 (B) | `finding.schema.json` v1 + 47 vectors; python/jq/zod validators + verdict-derive grammar; failure clause and blocking tally; templates and persona; alias normalisation; grader 1.5.0 `--judge-verdicts`; `reads.py --judge-defects` | `9462a4016` | FC 7, VFC 12 (9 red first), NRM-C133 5, AG-c133-J 8 (red first), test_judge_read 5, node 1068/1068, dist fresh; lead 783/783 unit + 154/154 eval |
| 3.3 External seeding, registration v2, guidance (C) | `lib/corpus-seed.sh` (byte-identical), `seed-corpus-from-external.sh`, `.claude/scripts/lib/secret-classes.sh` shared with `record-branch.sh`, registration v2 `looks_seen`, README § Shipping a measurement cycle, planning-sprints pointer | `08843c515` | 89/89 across eight suites; pytest 245; test_registration_v2 13 (11 red first); three dry-runs `--check` clean |
| 3.4 Harness documentation (D) | README complete (mount modes, egress threat model and supervisor, refusal policy and denominators, pipeline version table, exit codes), evals index, launchers default to the pinned image | `c31aad7cc` (+ `1e54af937` § Mount modes) | `evals/tests/image-default.bats` ID-1/2 |
| s3-e KF-058 egress gap (D4) | a guard namespace per blocked sandbox; `must_unreach` in-namespace rejections only; EGR-8 deterministic listener probe, EGR-13, EP-9; pre-flight refuses an unlabelled proxy image | `874fc64a9` | gate 22/22 with real containers on two hosts; regression 189/189; pin self-check 62/0; spike `user` arm through a guard SPIKE-OK 0 denials |
| 3.1 follow-up s3-a3 (A) | dissent under home-scope: root climbs resolve to the workspace via `LOA_PROJECT_ROOT` (R6–R8), R5 slash-only, persona surface, HOME build items | `7d2119477` | HS-14 (red first with the smoke's own error); lead 208/208; confirmed live in smoke run 2 (dissent_present true); KF-061 |
| Floor amendment (lead) | `floor.yaml` `floor_amendments` rows (exact sha, DEC, additive-only); FS-1 accepts the C-11 verdict-derive.sh bytes; FS-1b/1c negatives; `FLOOR_SHA256` re-pinned | `92aa210d6` | DEC-0946; floor-snapshot + guard-origins + profile-floor 30/30; CI FS-1 green on 92aa210d6 |
| CI repairs (lead) | Cycle132ChainTest skips on a depth-1 clone (KF-059); RAB-4 / RAB-c131-5 derive counts from the smoke set | `9af4d44e8`, `0d51dcf45` | pytest step green on 9af4d44e8; run-ablation.bats 59/59 |
| 3.5 Measurement pin and the smoke (lead with A) | pin 1 `32a8d79cf` (DEC-0942) → smoke run 1 (pr-20) FAILED clause (f) + dissent absent → s3-a3 → pin 2 `7d2119477` (DEC-0949) → verification rerun (pr-03) FAILED clause (f), dissent present, egress held → G-4 incomplete, FR-10 deferred (DEC-0950 … 0952); the integrated self-check and the egress gate passed at both pins (self-check 62/0, gate 22/22, CI eval job green) | `evals/harness/README.md` § Pipeline version (cycle-133 Sprint 274 pin); `grimoires/loa/reports/ablation-2.0/c133-smoke/{README.md,suite.yaml,run-1,run-2}`; `self-check-c133-s274.txt` | `c133-smoke/run-1/rows.jsonl`, `run-2/rows.jsonl` (infrastructure_error, took-effect oracle_closed false, dissent_present true in run 2), `run-2/egress/denied-trial-window.jsonl` (26 filtered), `run-2/dissent/`; KF-060 (rec 2), KF-061 (fixed) |
| 3.6 Drift-test removal (D) | deferred by the sprint's own condition (no green smoke): BS-8 stays; D's prepared removal `s3-d2` (+1/−37, 139/139 after) discarded unlanded | `evals/tests/blind-session.bats` BS-8 unchanged; `~/.cache/loa/cycle-133/{patches/s3-d2.patch,reports/s3-d2.md}` | DEC-0951; bead bd-nzblj; bd-l0y9e corrected by comment |
| 3.7 Sprint close (lead) | patches applied C → B → (D4) → A; CHANGELOG entries with revert paths per task; DEC rows from every Judgment-calls section; beads closed; worktrees removed as each patch landed | this report; `CHANGELOG.md` `[Unreleased]` | DEC-0908 … DEC-0952 (plus DEC-0946 floor amendment) |
| 3.E2E | G-4 (the smoke's grade and the negative control), G-5 (the four validators' refusal fixtures), G-8 parts (three dry-runs, `looks_seen` cases) | `a2a/sprint-274/e2e.md` | see e2e.md |

## Judgment calls → DEC rows

- Task 3.3 (C): DEC-0909 … DEC-0918 (base/ = PR merge base and fix^..fix; one exit code; shared scanner home; library shape; trees-API sizes and the synthesized-tree archive; limits over fetched blobs; licence policy by family; refuse on any scanner hit; registration v2 look identity, completeness, schema bump and self-reference; generated outputs).
- Task 3.2 (B): DEC-0919 … DEC-0927 (four validators; alias_conflict scope and pass-through; defect-only location, exact severity, cross-language identity; bullet grammar and sections; blocking tally and the one-way rule; lazy lib and unchanged `--json`; alias deprecation to 2.1.0; grader 1.5 rules; recall_judged and `--judge-defects` under v2).
- s3-e (D4): DEC-0928 … DEC-0932 (guard namespace per container, not shared; in-namespace rejection only; the sidecar's image with the guard label; unique guard names and the watcher's lifecycle; `--dns` on the guard and the recorded address).
- Task 3.1 (A): DEC-0933 … DEC-0941 (surface beyond the SDD list; head-only overlay and clause (e); pinned-root byte identity; clause (f) rules; clause (g) rules and the host-side sampler; suite key and the version pin; the reversible framework-root transform; absolute-path rule imports, project config at the root, integrity before deletion; the lead's clause (f) widening to single-file Bash reads).
- Lead landing decisions (no DEC, mechanical): `tests/COUNT` = 233 (the unittest-collected total with pytest importable); ablation-grade usage header keeps image 259 and gains `--judge-verdicts`; README § Mount modes replaced by the landed contract; smoke task `smoke-review-c133` added to the suite root and the root re-frozen with `--smoke` (the cycle-132 registrations bind `ablation-2.0-c132`, so they are unaffected).

## Tests run by the lead on the merged tree

| Suite | Result | Log |
|---|---|---|
| C's eight suites (secret-classes, record-branch, corpus-seed-lib, seed-corpus, seed-corpus-from-external, analysis-c132, manifest-v2, registration) | 89/89; pytest 245 | commit `08843c515` |
| B's unit suites (verdict-*, finding-conformance, adversarial-review*, golden-path-c8, profile-floor, wire-schemas*, run-checkpoint*) | 783/783 | `~/.cache/loa/cycle-133/tests/s3b-unit-092408.log` |
| B's eval suites (ablation-grade, analysis-c132, ablation-row, registration, manifest-v2) | 154/154 | `s3b-evals-093408.log` |
| Bridgebuilder `npm test`; `check-bb-dist-fresh --check` | 1068/1068; fresh | commit `9462a4016` |
| Egress gate `LOA_EGRESS_GATE=1 egress-proxy.bats` (real containers) | 22/22 | `s3e-lead-gate-094721.log` |
| Launcher regression (pipeline-run, blind-session, run-ablation, image-default, batch-supervisor) | 189/189 | `s3e-lead-regress-094837.log` |
| A's suites (sandbox-mount-home-scope, sandbox-mount, took-effect, pipeline-run, arm-toggles, execute-agent, validate-suite, ablation-row, run-ablation, blind-session, image-default) | 352/352 | `s3a-lead-100039.log` |
| Gates (guard-yield, knob-readers, manifest-paths, gen-checksums --check, swallowed-jq), prompt budget, raw-sha256sum, raw-curl, eval trust boundary | all clean | commits `08843c515`, `9462a4016`, `1e54af937` |
| CI on `db668858d` | Eval Sandbox green on every pushed head (KF-058 confirmed on the runner, run 40085119807). Shell Tests: red on `db668858d` (pytest import on the depth-1 checkout → KF-059 guard `9af4d44e8`), red on `9af4d44e8` (FS-1: verdict-derive.sh is a floor file → floor amendment `92aa210d6`, DEC-0946), red on `92aa210d6`/`ff26fdea3` (RAB-4, RAB-c131-5 hard-coded smoke counts → `0d51dcf45`); run on `0d51dcf45` in progress at report time — the reviewer should read its conclusion | run ids 40085119661, 40085874207, 40089588489, 40089623276 and the run on 0d51dcf45 |

## Spend

| Item | USD |
|---|---|
| Task 3.0 spike, three arms | 0.027 |
| D4's spike `user` arm through the guard | 0.012 |
| Task 3.5 smoke | 20.84 (run 1 11.54, run 2 9.30) |
| Total against the USD 40 share | 20.88 |

## Beads

Closed: bd-qwhfz (3.0), bd-r79h3 (3.1), bd-kloxz (3.2), bd-5hkgf + bd-y1smc (3.3), bd-vtikl (3.4), bd-0w7c0 (3.5, with the failed outcome), bd-l0y9e (3.6; closed early by D, corrected by comment). Open for the close: bd-o0wjy (3.7), bd-cudfb (E2E). Follow-ups filed: bd-ci4g9 (dissent wire alias → `failure_scenario` before 2.1.0), bd-yv0d4 (a7 arm + live dissent under home-scope), bd-nzblj (BS-8 stays until a green smoke), bd-ivmtk (FR-10 path: external fixtures or a base-version framework).

## Known gaps carried forward

- **home-scope is landed but not claimed (FR-10 deferred).** A Loa reviewer consults its installed Loa in HOME as the reference for a Loa PR (compared the HOME copy with `pr/base`, executed the installed version of a changed script); the mount isolates the workspace root, not the install. Clause (f) detects it reliably (two of two). Path: external fixtures (C-12) or a base-version framework — the operator's call (bd-ivmtk, DEC-0952).
- **Floor amendment**: byte identity with `origin/main` is no longer absolute for floor files; an additive, sha-pinned, DEC-named row is the sanctioned path (DEC-0946). Surfaced for the audit.
- Dissent under home-scope is stub-tested only (HS-11 proves cheval loads the HOME catalog); the first live run is the smoke.
- `skill_effort_stripped` (the a7 arm) still reads `sandbox/.claude` and is not adapted to home-scope; only `a1_full` smokes.
- Clause (g) is a lower bound: copies of a PR script run from elsewhere are not seen.
- The dissent wire schema and prompt still ask for `failure_mode`; every dissent run warns until the wire moves (bead bd-ci4g9, before 2.1.0).
- Other hosts must rebuild `loa-egress-proxy:259` from the landed Dockerfile before their next batch (the runner refuses the unlabelled image).

