# Sprint 1 (global 241) Security & Quality Audit — round 2 (final)

**Auditor:** Paranoid Cypherpunk Auditor (Fable 5.1, inline under `/run sprint-plan`)
**Date:** 2026-09-23
**Scope:** commit `52ff4830` (review-approved round 3) — `.claude/hooks/safety/block-destructive-bash.sh`, `.claude/scripts/git-branch-prune.sh`, `tests/unit/block-destructive-bash.bats`, `tests/unit/git-branch-prune.bats`, `tests/fixtures/fence-corpus/*`, `CHANGELOG.md`
**Methodology:** re-verification of round 1 (`auditor-sprint-feedback-round1.md`) against the fixed tree — every round-1 probe replayed, the dissent record (`adversarial-audit.json`, `adversarial-rejected-audit.jsonl`) re-read, the four categories re-scored. No new code surface since round 1 beyond the two fixes and the runner's clock.

---

## Executive Summary

Round 1 found one HIGH (an assignment in command position after a reserved word rebinding the once-bound mktemp variable) and one MEDIUM (the helper trusting "a merged PR exists" instead of "this head is merged"). Both are fixed in `52ff4830` and pinned: the hook now requires the single statement-initial `NAME=` to be the only `NAME=` token anywhere in the command (`block-destructive-bash.sh:1297-1306`), which I verified closes `if T=/; then`, `while T=/; do`, `{ T=/; }`, `! T=/` and `true && T=/` (all exit 2) while `T=$(mktemp -d) && cp -r out "$T"/ && rm -rf "$T"` still exits 0; the helper requires the merged PR's `headRefOid` to equal the local head (`git-branch-prune.sh:78-86`) and the stub-`gh` test with a stale OID keeps the branch. The refuted dissent payload (grep carrier hiding `$(…)`) is pinned by corpus D55 and a named case so nobody re-litigates it.

The fence's retained blocks are intact: 55 dangerous corpus rows and all 216 legacy cases block; the new allow paths admit only what their predicate proves. Remaining debt is two LOWs recorded, not fixed (a pre-existing variable-content gap under temp roots, and the corpus-lint TLD list). No critical or high remains.

**Overall Risk Level:** LOW

**Key Statistics:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 2 |

---

## Category Scores (Rubric-Based Assessment)

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 4.4/5 | IV:4 AZ:5 CI:4 IN:4 AV:5 |
| Architecture | 4.6/5 | MO:4 SC:5 RE:5 CX:4 ST:5 |
| Code Quality | 4.4/5 | RD:4 TC:5 EH:4 TS:5 DC:4 |
| DevOps | 4.4/5 | AU:4 OB:5 RC:4 AC:5 DS:4 |
| **Overall** | **4.5/5** | |

---

## Round-1 findings — verification

| Finding | Status | Evidence at `52ff4830` |
|---|---|---|
| HIGH-001 reserved-word rebinding | **Fixed** | probes `if`/`while`/`{ }`/`!`/`true &&` → 2; legit shapes → 0; corpus D51–D54 (block) + R05 (accepted FP); bats "audit r1 twin" |
| MED-001 helper trusts PR existence | **Fixed** | `squash_merged` compares `headRefOid` to `git rev-parse refs/heads/<name>`; bats "a merged PR whose head is not the local head keeps the branch" (15/15) |
| LOW-001 variable contents under a temp root | Recorded | pre-existing accepted class (hook header, SDD §11); no change |
| LOW-002 corpus-lint TLD list | Recorded | rows hand-authored this sprint; extend on the next session-seeded corpus |
| LOW-003 GNU-only clock | **Fixed** | `run-corpus.sh` `now_ms()` via `$EPOCHREALTIME` with `date` fallback |
| LOW-004 `--help` exit 2 | **Fixed** | exits 0; bats case |
| Dissent payload 1 (grep `$(…)`) | Refuted, pinned | D55; named case `grep "$(rm -rf /)" file` → 2 |

## Low Priority Issues (Technical Debt)

### [LOW-001] Variable contents inside a temp path remain invisible (pre-existing)
**Component:** `.claude/hooks/safety/block-destructive-bash.sh:1240`
**Description:** `rm -rf "/tmp/$D"` with `D=../../home` resolves outside `/tmp`; the pre-sprint `/tmp/.+` entry had the same property. Accepted-bypass class; carried.

### [LOW-002] Corpus lint TLD list
**Component:** `tests/unit/block-destructive-bash.bats:1569`
**Description:** misses `.ai`, `.co`, `.xyz`, `.app`, `.cloud`, `.sh`. Extend when rows are next seeded from sessions.

---

## Cross-Model Security Observations

- Round-1 dissent (`gpt-5.5-pro`, diff only, `status: reviewed`, 0 accepted, 2 rejected on `missing-or-empty-failure_mode`): payload 2 confirmed and fixed as HIGH-001; payload 1 refuted with probes. No second dissent run was needed for round 2: the diff since round 1 is the two fixes, the runner clock and tests, all exercised by the replayed probes above.

---

## Security Checklist Status

- [x] No hardcoded secrets (corpus lint gate over 107 rows; helper uses `gh`'s own auth)
- [x] Input validation at the trust boundary — HIGH-001 closed; every relaxation predicate falls back to the pre-sprint block on any error
- [x] No network in the hook; helper probe bounded (`timeout 5`) and opt-out (`LOA_FENCE_NO_NETWORK=1`)
- [x] Audit trail — `emit_block` row unchanged; helper prints restore SHAs
- [x] Fail-open posture unchanged (hook-guard wrapper)
- [x] Destructive-tool guards in the helper — never the current branch, the base, `main`, `master`; `--dry-run` deletes nothing (tested)

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 2 |

## Verdict

APPROVED - LET'S FUCKING GO

Both LOWs are recorded as debt with owners in the next precision pass; neither affects the retained blocks or opens an allow path.

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":2},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-241","ts":"2026-09-23T04:29:00Z"} -->
