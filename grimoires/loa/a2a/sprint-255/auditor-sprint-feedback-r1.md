# Security & Quality Audit Report — sprint-255 (cycle-129 Sprint 1), round 1

**Auditor:** Paranoid Cypherpunk Auditor (Claude Fable 5.1, `global.anthropic.claude-fable-5-1`)
**Date:** 2026-10-14
**Scope:** `ffd25258..49895989`, code only (fixture copies, label files, generated register, plan documents excluded from the diff; the fixture trees were scanned separately); review approved in `engineer-feedback.md` (r2, `All good`)
**Dissent:** `adversarial-audit.json` — two voices (`gpt-5.5-pro`, `claude-headless`), status clean, verdict quality APPROVED (2/2), 9 findings (3 MEDIUM, 6 LOW), 0 rejected payloads

## Executive Summary

The sprint adds a CI-run generator that writes framework files, an eval driver that spawns model executors from inside an agent session, a corpus seeder that copies repository history into tracked fixtures, and a validator rule. The audit looked for what the review did not: the trust boundaries of those four surfaces. No CRITICAL or HIGH path was found. Four MEDIUM findings concern the integrity of the measurement the cycle is built on (an arm's toggles leaking from the environment, an unlisted fixture file passing the corpus check, a floor test that would fail the very next sprint for the wrong reason) and six LOW hardening gaps. All are small; the lead lands them in round r255-2 and the audit re-checks.

## Category Scores (Rubric-Based Assessment)

| Category | Score | Note |
|---|---|---|
| Secrets & credentials | 9/10 | eight fixture trees pass `no-secrets.sh`; executor scrubs GH/OpenAI/AWS credentials and the session coupling; redaction regexes extended in r255-2 |
| Input validation | 8/10 | hook commands parsed against a canonical schema; SHAs and arm ids validated; `--batch` admits `.`/`..` (LOW) |
| Trust boundaries | 7/10 | arm toggles reachable without arm mode (MEDIUM); unlisted fixture files pass (MEDIUM) |
| Supply chain / CI | 8/10 | `--check` is a pure function of the repository; floor proof now fetched in CI; snapshot scope too wide (MEDIUM) |
| Privacy / telemetry | 9/10 | register carries no command text, cwd, hostname or model name; `LOA_AUDIT_REPLAY` visibility noted (LOW) |

## Medium Priority Issues

### [MED-001] Arm toggles apply outside arm mode and leak from the environment (dissent DISS-C-001)
`evals/harness/execute-agent.sh:163-166` honoured `LOA_EVAL_ARM_TOGGLES` whenever set, with `ARM_MODE` false and `ARM=baseline`, so a stale exported variable would toggle a production eval run while rows said `baseline`; `run-arms.sh` passed its parent environment through to every trial. **Fix (r255-2):** toggles resolve only in arm mode (a set variable outside arm mode is ignored with a WARN); the baseline arm refuses toggles; `run-arms.sh` runs the executor under `env -u LOA_EVAL_ARM_TOGGLES`.

### [MED-002] `run-arms.sh` corpus check ignores unlisted files (dissent DISS-C-002)
`evals/harness/run-arms.sh:134-155` verified only the entries listed in `SHA256SUMS`; a file added under a fixture passed both the batch-start and the per-trial check and reached the sandbox under an unchanged digest, while the seeder's own `--check` flags such files. **Fix:** `verify_corpus` walks the fixture (or the corpus) and reports `(not listed)` files as drift, matching the seeder.

### [MED-003] Floor snapshot pins every hook registration and every fence call site
`tests/unit/floor-snapshot.bats` FS-3 and FS-4 (as landed in r255-1) compared the whole `.hooks` object and the whole ordered fence call-site list with `origin/main`. Sprint 2's FR-6 classifier changes fence call sites and any later cycle adds hooks; the floor proof would fail for non-floor reasons and invite a blanket update. **Fix:** FS-3 pins the registrations of the hooks that run floor guards (the fence host and the dissent artefact gate); FS-4 requires every floor fence id in `floor.yaml` to keep at least its `origin/main` call sites; FS-6 (r255-1) keeps the registration requirement.

### [MED-004] Fixture content may carry an instruction file for the agent under test (dissent DISS-C-003, partly refuted)
The dissent held that a sprint touching `CLAUDE.md` would put `head/CLAUDE.md` (importing the kernel) into a fixture, which Claude Code could load when the agent reads files beneath it, defeating the `no_karpathy` arm. Verified: no record fixture carries a `CLAUDE.md` (0 of 8); four carry a nested `.claude/loa/CLAUDE.loa.md`, which is not an auto-loaded file; the sandbox's own `CLAUDE.md` is written by the executor and points at the pinned prompt tree. The failure scenario is therefore future, not present. **Fix (defensive):** the seeder excludes a root `CLAUDE.md` from fixture scope. Tallied MEDIUM for the scenario's impact on the measurement; confidence medium.

## Low Priority Issues

### [LOW-001] `--batch` accepts `.` and `..` (dissent DISS-C-004)
`run-arms.sh:131`: the regex admits the two names; `..` would place the batch files beside the suite directories and `cleanup()` would remove `$RESULTS_ROOT/.jobs`. **Fix:** refuse both.

### [LOW-002] Transport-failure classifier reads the agent's own output (dissent DISS-C-005)
`run-arms.sh:318-319` grepped `agent-output.json` for `network`, `5[0-9][0-9]`, so a review mentioning a 5xx code earned a retry. **Fix:** classify on the CLI's stderr and executor exit codes only, with the CLI's transport phrases.

### [LOW-003] Pristine-worktree check ignores ignored files (dissent DISS-C-006)
`run-arms.sh:231`: `git status --porcelain` omits ignored files, so an earlier run's `.loa.config.yaml` or `.run/` in the worktree would be copied into every sandbox under one recorded commit. **Fix:** `--porcelain --ignored`.

### [LOW-004] Redaction regexes narrower than the grader's; two match across lines (dissent DISS-C-007)
`seed-corpus-from-record.sh:112-114`: nine patterns; the generic `password`/`secret` patterns used `\s*` and `[^"']{8,}`, which cross newlines. **Fix:** PEM blocks, JWTs, GitHub fine-grained/app/user tokens, Google and Stripe keys and generic key/token assignments added; the generic patterns are single-line. The eight fixture trees pass `no-secrets.sh` before and after.

### [LOW-005] Karpathy constraints rewrite could fail silently (dissent DISS-C-008)
`execute-agent.sh:256`: `jq … > tmp && mv` under `set -e` inside a function left the file untouched on a jq error with no post-check. **Fix:** error is exit 2; a post-check asserts zero Karpathy rows remain; the evidence records the count.

### [LOW-006] `LOA_EVAL_SOURCE_COMMIT` unvalidated (dissent DISS-C-009)
`execute-agent.sh:401`: any string was recorded as `source_commit`. **Fix:** hex id required and, when the prompt tree's HEAD is known, it must be that commit.

### [LOW-007] The replay flag is an environment variable
`block-destructive-bash.sh` writes `replay: true` whenever `LOA_AUDIT_REPLAY=1` is set. A session that exports it hides its blocks from the yield. The yield counts flagged rows separately (`replay_rows_by_rule.flag`) and the register disables nothing, so the effect is on a report, not a control. No change; recorded for the Sprint 2 register report.

## Security Checklist Status

- Secrets: no credential in the diff; fixtures scanned clean; executor unsets `GH_TOKEN`, `GITHUB_TOKEN`, `OPENAI_API_KEY`, `AWS_*` and the session coupling variables (`execute-agent.sh:339-349`).
- Auth/authz: `/loa` seams gated on the bats environment; `guard-yield.sh --hooks-table` writes a System-Zone file only under the cycle's zone marker.
- Input validation: hook commands (canonical schema, control characters rejected), SHAs, arm ids, fixture ids, `--by` grammar, `--out` confinement, record-ref paths (`/` and `..` refused).
- Data privacy: register and yield carry ids, counts and origin text only (GY-5).
- Supply chain: `--check` reads only tracked files; the CI step fetches one ref without tags; `seed --check` and `run-arms verify_corpus` now agree.

## Threat Model Summary

Attack surface added: a CI gate (`guard-yield.sh --check`), a detached executor driver reading a frozen corpus, a seeder copying history. Attacker positions considered: a malicious hook command in `settings.json` (rejected by schema, containment canonicalised in r255-1); a poisoned fixture file (MED-002 closes the unlisted-file path); environment poisoning of an arm run (MED-001); a review under test steering its own retries (LOW-002); secrets in history copies (LOW-004, grader clean).

## Positive Findings

- The origin lint failed on its first cross-implementer integration (a marker without a map row) — the gate works.
- `install_file` is temp-beside-destination then rename; outputs are sanitised at the cell.
- `verify_corpus` runs per trial, so a mid-batch approval of another fixture is visible and harmless.
- The executor's coupling scrub was found by the implementer in a real trial and fixed before any batch ran.

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 4 |
| Low | 7 |

## Verdict

CHANGES_REQUIRED — by judgment, not by the one-way rule: no CRITICAL or HIGH, but the four MEDIUM findings touch the integrity of the control-arm measurement the cycle depends on and the floor proof's durability. All eleven fixes are small and land in round r255-2; round 2 re-checks them.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":0,"medium":4,"low":7},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-255","ts":"2026-10-14T02:20:00Z"} -->
