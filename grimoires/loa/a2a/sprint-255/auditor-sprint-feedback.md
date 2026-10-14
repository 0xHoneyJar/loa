# Security & Quality Audit Report — sprint-255 (cycle-129 Sprint 1), round 2

**Auditor:** Paranoid Cypherpunk Auditor (Claude Fable 5.1, `global.anthropic.claude-fable-5-1`)
**Date:** 2026-10-14
**Scope:** `ffd25258..HEAD` after round r255-2 (code only; fixture copies, label files, generated register and plan documents excluded from the diff; the fixture trees scanned separately with `no-secrets.sh`, 8/8 clean)
**Round 1:** `auditor-sprint-feedback-r1.md` — CHANGES_REQUIRED by judgment (0/0/4/7)
**Dissent:** `adversarial-audit.json` — two voices (`gpt-5.5-pro`, `claude-headless`), status clean, verdict quality APPROVED (2/2), 9 findings, 0 rejected payloads

## Executive Summary

Every round-1 finding except one accepted LOW landed in round r255-2 and was re-checked against the code and the suites. The four MEDIUM items that touched the measurement's integrity are closed: arm toggles exist only in arm mode and never reach a trial from the parent environment (`execute-agent.sh` ignores a stale `LOA_EVAL_ARM_TOGGLES` outside arm mode and refuses toggles on `baseline`; `run-arms.sh` runs the executor under `env -u LOA_EVAL_ARM_TOGGLES`); `run-arms.sh`'s corpus check now reports unlisted files as drift like the seeder's `--check`; the floor snapshot pins the floor hooks' registrations and the floor fence ids' call sites instead of every hook and every site; the seeder excludes a root `CLAUDE.md` from fixture scope. The six LOW hardening items are closed (`--batch` refuses `.`/`..`; the transport classifier reads the CLI's stderr only; the pristine check includes ignored files; sixteen single-line redaction patterns; the constraints rewrite fails loudly and is post-checked; `LOA_EVAL_SOURCE_COMMIT` must be a hex id matching the prompt tree's HEAD). One LOW stands as recorded: the replay flag is an environment variable whose effect is on a report, counted separately in the yield.

No CRITICAL or HIGH finding. The sprint's new surfaces (a CI gate that is a pure function of the repository, a detached executor driver with a scrubbed environment, a seeder with path confinement and redaction, a validator rule over untrusted plan text) hold their trust boundaries.

## Round-1 findings, re-checked

| Finding | Status in r255-2 | Evidence |
|---|---|---|
| MED-001 arm toggles outside arm mode / env leak (DISS-C-001) | fixed | `evals/harness/execute-agent.sh` `resolve_toggles` (arm-mode guard, baseline refusal); `evals/harness/run-arms.sh` `env -u LOA_EVAL_ARM_TOGGLES`; `evals/tests/arm-toggles.bats` AT-12 |
| MED-002 unlisted fixture files pass `verify_corpus` (DISS-C-002) | fixed | `run-arms.sh` `verify_corpus` walks the fixture and reports `(not listed)`; `evals/tests/run-arms.bats` 5/5 |
| MED-003 floor snapshot pins every registration and call site | fixed | `tests/unit/floor-snapshot.bats` FS-3 (floor hooks' registrations), FS-4 (floor fence ids keep their `origin/main` call sites), FS-6 (floor gate hooks registered): 6/6 |
| MED-004 instruction file inside a fixture (DISS-C-003, partly refuted) | fixed defensively | `seed-corpus-from-record.sh` `EXCL` excludes a root `CLAUDE.md`; no record fixture carried one (verified: 0 of 8) |
| LOW-001 `--batch` `.`/`..` (DISS-C-004) | fixed | `run-arms.sh` refuses both |
| LOW-002 transport classifier reads agent output (DISS-C-005) | fixed | `run-arms.sh` `is_transport_failure` reads stderr and exit codes only |
| LOW-003 pristine check ignores ignored files (DISS-C-006) | fixed | `git status --porcelain --ignored` |
| LOW-004 redaction coverage and cross-line matches (DISS-C-007) | fixed | 16 single-line patterns (PEM, JWT, `github_pat_`, `ghs_`/`ghu_`, `AIza`, Stripe, generic key/token); eight fixtures still pass `no-secrets.sh`; `SHA256SUMS` unchanged (842 files) |
| LOW-005 constraints rewrite could fail silently (DISS-C-008) | fixed | exit 2 on a jq error; post-check asserts zero Karpathy rows; evidence records the count |
| LOW-006 `LOA_EVAL_SOURCE_COMMIT` unvalidated (DISS-C-009) | fixed | hex id required and equal to the prompt tree's HEAD when known; AT-11/AT-12 |
| LOW-007 replay flag is an environment variable | accepted, open | reporting-only effect; `replay_rows_by_rule.flag` makes it visible; revisited in the Sprint 2 register report |

Re-verified on the fixed tree: `evals/tests/*.bats` 126/126 (arm-toggles 12, arms-report 7, eval-recall-grader 28, execute-agent 12, golden-path 33, implement-discipline-grader 10, recall-baseline-freshness 13, run-arms 5, seed-corpus 6), `tests/unit/floor-snapshot.bats` 6/6, `guard-origins.bats` 15/15, `guard-yield.bats` 11/11, `seed-corpus-from-record.sh --check` 842 files OK, `bash -n` on the three changed scripts, the sixteen regexes compile, `tools/check-no-direct-llm-fetch.sh`, `check-no-raw-curl.sh`, `check-bb-no-direct-fetch.sh` clean.

## Security Checklist Status

- Secrets: none in the diff; fixtures 8/8 clean; executor unsets `GH_TOKEN`, `GITHUB_TOKEN`, `OPENAI_API_KEY`, `AWS_*` and the session coupling variables.
- Auth/authz: `/loa` seams gated on the bats environment; `guard-yield.sh` writes a System-Zone file only under the cycle's zone marker; the CI step only reads.
- Input validation: hook commands (canonical schema, control characters rejected, physical-path containment), SHAs, arm ids, batch names, fixture ids, `--by` grammar, `--out` confinement, record-ref paths.
- Data privacy: register and yield carry ids, counts and origin text only.
- Supply chain: `--check` reads tracked files only; `origin/main` fetched as one ref without tags; the seeder's and the runner's corpus checks agree.

## Positive Findings

- The origin lint tripped on its first cross-implementer integration — the gate works.
- The executor's coupling scrub was found and fixed by the implementer in a real trial before any batch ran.
- `verify_corpus` runs per trial and now matches the seeder's rule.

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 1 |

## Verdict

APPROVED - LET'S FUCKING GO

One accepted LOW (the replay flag's reporting-only effect) stands as recorded; everything else from round 1 is closed and re-verified.

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":1},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-255","ts":"2026-10-14T02:35:00Z"} -->
