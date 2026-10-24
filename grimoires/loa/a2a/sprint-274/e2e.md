# Sprint 274 (cycle-133 Sprint 3) — End-to-End Goal Validation (Task 3.E2E)

Goals from `grimoires/loa/prd.md` touched by Sprint 3: G-4 (Loa reviews Loa without reading its own installed files), G-5 (every gate's findings carry a failure scenario a judge can grade), G-8 parts (a corpus can be seeded from outside Loa's history; measurement-cycle guidance; harness docs). Each row names the evidence path a reviewer can open; nothing here is asserted without one.

## G-4 — the home-scope mount and the smoke

| Check | Evidence | Result |
|---|---|---|
| The Task 3.0 spike: `--setting-sources user` loads nothing from the project scope in Claude Code 2.1.299 | `grimoires/loa/a2a/sprint-274/spike-3.0.md`; `spike-3.0/user/canaries.txt` (user-scope canaries only), `spike-3.0/both/canaries.txt` (positive control: every project canary), `spike-3.0/none/` | design (a′) confirmed; DEC-0908 |
| Negative control with distinct PR and pinned bytes | `evals/tests/fixtures/home-scope-nc/` (`pinned/.claude/protocols/nc-guard.md` ≠ `pr-nc/head/.claude/protocols/nc-guard.md`, `SHA256SUMS`); `evals/tests/sandbox-mount-home-scope.bats` HS-10 … HS-11 | clause (f) fails on a read of the pinned bytes; passes on the PR's |
| Design-neutral bats (executing SKILL.md, hook, script, deletion, rename, symlink, `.mcp.json`, root `CLAUDE.md`, rules, output styles, plugins) and clause (g) | `evals/tests/sandbox-mount-home-scope.bats` HS-1 … HS-12 (HS-13 single-file Bash reads; HS-14 dissent under home-scope); lead run `~/.cache/loa/cycle-133/tests/s3a-lead-100039.log` 352/352 | green |
| pinned-root unchanged | HS-4 (invariance: no new evidence key, no `mount.json`, `--setting-sources project`) | byte-identical |
| The smoke at the measurement pin within the USD 40 share | run 1: `grimoires/loa/reports/ablation-2.0/c133-smoke/run-1/` (a1_full × pr-20 at pin `32a8d79cf`, USD 11.54, 30 min); run 2: `run-2/` (a1_full × pr-03 at pin `7d2119477`, USD 9.30); both under the egress guard with the pin self-check 62/0 (`run-*/egress/self-check.log`); launch rule met (spend > USD 0.50) | two launches, both `infrastructure_error` on took-effect; USD 20.84 of the share; no third launch (DEC-0950) |
| Clauses (a)–(g) on the smoke run; `oracle_exposed_defects` 0; `pr_bytes_read` covering every cited changed `.claude/` file | `run-1/meta/took-effect.json`, `run-2/meta/took-effect.json`; `run-*/meta/arm-evidence.txt`; `run-*/reviewer-home-reads.txt`, `run-2/auditor-home-reads.txt` | (a)–(e) and (g) PASS in both runs; **(f) FAIL in both**: run 1 read the active skill, `CLAUDE.loa.md`, `profile-lib.sh` from HOME (all changed by pr-20); run 2 compared the HOME copy of `ledger-lib.sh` with `pr/base`, read `mount-submodule.sh` from HOME and executed the installed `classify-pr-type.sh` (all three changed by pr-03). `oracle_exposed_defects` not computed (no grade); `pr_bytes_read` voided by the pinned reads. dissent_present false in run 1 (KF-061, fixed by s3-a3), true in run 2 (gpt-5.5-pro reviewed, claude-headless companion succeeded) |
| `grade.json` under grader 1.5 with the pin recorded | none — the grader does not run after a took-effect FAIL (`run-*/rows.jsonl` grade null) | G-4 incomplete; FR-10 deferred (DEC-0950; bead bd-ivmtk); KF-060 recurrence 2 |

## G-5 — one finding contract

| Check | Evidence | Result |
|---|---|---|
| Four validators refuse missing / boilerplate / conflicting / outside-repo findings | `.claude/schemas/finding.vectors/invalid/` 01-one-word-clause, 02–04 denylist (TODO, see above, N/A), 28 placeholder phrase, 06 alias conflict, 07–09 path (dot-dot, absolute, backslash), 22 high without file; `tests/unit/finding-conformance.bats` FC-1 (python), FC-2 (jq), FC-3 (zod), FC-4 (markdown grammar), FC-7 (jq = python) | 47/47 vectors agree in all four |
| Aliases normalised with the warning; a differing pair refused | `tests/unit/adversarial-review-normalise.bats` NRM-C133-1 … 5 (one WARN per alias per run; `alias-conflict-failure_scenario-failure_mode`; the four cycle-132 envelopes, 22 findings, replay byte-identical) | green |
| A defect bullet without a clause is a violation; an invalid CRITICAL/HIGH/blocking bullet still blocks | `tests/unit/verdict-derive-failure-clause.bats` VFC-1 … 12 (VFC-1 only invalid blockers → non-zero; VFC-3 a malformed CRITICAL never approves; VFC-8/9 dash variants and last-token when/then) | 12/12 (9 red first) |
| Judged recall and unjudged count; stale verdicts rejected | `evals/tests/ablation-grade.bats` AG-c133-J1 … J8 (`--judge-verdicts`: recall_judged, judged_pairs_unblind, unjudged_pairs; stale row → exit 2; supersedes chain; run_id); `evals/tests/fixtures/grader-1.5/regress.sh` (417 pairs: 389 identical, 17 refused by both, 11 exit_differs all new) | 88/88; 1.4.0 grades unchanged |
| `--judge-defects` under registration v2 | `evals/analysis/c132/tests/test_judge_read.py` (5: v1 refused with exit 1; fully judged pairs only) | green |
| The cycle-132 chain still verifies | `registration.py verify` on the 18 `grimoires/loa/evals/ablation-2.0-c132/REGISTRATION*.json` (`test_registration_v2.py::Cycle132ChainTest`; skips on a depth-1 clone, KF-059) | 18/18 on the full clone |
| Templates and persona carry the field | `.claude/skills/reviewing-code/resources/templates/review-feedback.md`, `.claude/skills/auditing-security/resources/templates/sprint-audit-feedback.md` (`Failure:` clause), `.claude/skills/bridgebuilder-review/resources/BEAUVOIR.md` (`failure_scenario`); `FindingsBlockSchema.meta()` names the canonical schema; `check-bb-dist-fresh --check` OK | present |

## G-8 parts — external seeding, guidance, docs

| Check | Evidence | Result |
|---|---|---|
| Three dry-runs pass `--check` with no model call | `evals/fixtures/external-candidates.md` (three public candidates; `seed-corpus-from-external.sh --dry-run --check`; 0 rows in the model-invoke log) | pass |
| Refusals: symlink, submodule, oversize, licence, leakage | `evals/tests/seed-corpus-from-external.bats` (20 tests, 12 red first; every refusal exit 2 with a named reason per sdd § 5.4) | green |
| The record seeder is byte-identical after the extraction | `evals/tests/corpus-seed-lib.bats` (transcript golden, every mode); `evals/tests/seed-corpus.bats` 29 unchanged | identical |
| The C-4 scanner shared by `record-branch.sh` and the external seeder | `.claude/scripts/lib/secret-classes.sh`; `tests/unit/secret-classes.bats` (6, golden hit lists); `tests/unit/record-branch.bats` 14 unchanged | green |
| `looks_seen` verifier cases; v1 chain verifies | `evals/analysis/c132/tests/test_registration_v2.py` (13, 11 red first: ordering, integrity, completeness, self/successor refusal, v1 byte identity) | green |
| Measurement-cycle guidance and harness docs | `evals/harness/README.md` § Shipping a measurement cycle, § Mount modes, § Egress (guard namespace), § Pipeline version; `evals/README.md` index; `.claude/skills/planning-sprints/resources/REFERENCE.md` sequencing principle 5; `evals/tests/image-default.bats` ID-1/2 | present |
| Drift test removed only after a green smoke | BS-8 kept (`evals/tests/blind-session.bats`); D's prepared removal discarded (`~/.cache/loa/cycle-133/patches/s3-d2.patch`); DEC-0951 | deferred by the sprint condition; bead bd-nzblj |

## Spend against the USD 40 share

| Item | USD |
|---|---|
| Task 3.0 spike (three arms) | 0.027 |
| D4 spike `user` arm through the guard | 0.012 |
| Task 3.5 smoke | 20.84 (run 1 11.54, run 2 9.30) |
| **Total** | 20.88 |

## Not validated here

- **G-4 is not established.** Both home-scope launches failed clause (f) for a structural reason (KF-060): the reviewer consults its installed framework. The isolation claim of FR-10 is deferred; the detector and the negative control are established.
- **Egress during a live trial** is validated positively for the first time: run 2 logged 26 filtered denials from the trial's guard address (codex telemetry and asset hosts, one github.com attempt) while the allowlisted API hosts served the review and the dissent (`run-2/egress/denied-trial-window.jsonl`).
- Dissent under home-scope is stub-tested; the smoke is the first live run (bead bd-yv0d4 for the a7 arm and a live dissent check).
- Clause (g) is a lower bound (copies of a PR script run elsewhere are not seen; DEC-0937).
