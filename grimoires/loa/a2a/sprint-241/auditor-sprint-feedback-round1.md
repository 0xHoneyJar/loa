# Sprint 1 (global 241) Security & Quality Audit — round 1

**Auditor:** Paranoid Cypherpunk Auditor (Fable 5.1, inline under `/run sprint-plan`)
**Date:** 2026-09-23
**Scope:** commit `87b7522c` (review-approved round 2) — `.claude/hooks/safety/block-destructive-bash.sh`, `.claude/scripts/git-branch-prune.sh`, `tests/unit/block-destructive-bash.bats`, `tests/unit/git-branch-prune.bats`, `tests/fixtures/fence-corpus/*`, `CHANGELOG.md`
**Methodology:** Phase 0.5 scope (`security-audit-scope.sh`), recon of the new allow paths as sinks, forward/backward tracing of every relaxation predicate, hand-built probes replayed through the hook at the audited commit, independent cross-model dissent (`adversarial-audit.json`, gpt-5.5-pro, diff only), then the 4 applicable categories (Security, Architecture, Code Quality, DevOps; no blockchain surface).

---

## Executive Summary

A fence sprint is audited on two axes: do the retained blocks still fire (yes — 55 dangerous corpus rows and 216 legacy cases block), and does any new ALLOW path open something the old fence closed. The review already closed six such holes. The dissenter returned zero schema-valid findings but two rejected payloads (`adversarial-rejected-audit.jsonl`, both `missing-or-empty-failure_mode`); I triaged both by hand rather than dropping them. One is a genuine bypass at the audited commit and is the single HIGH of this audit: an assignment in *command position after a reserved word* (`if T=/; then …`) rebinds the "once-bound" mktemp variable without being counted, so `T=$(mktemp -d); if T=/; then rm -rf "$T"; fi` exits 0 at `87b7522c` and executes `rm -rf /`-shaped deletes. The other (grep carrier scrub hiding `$(…)`) is refuted with a probe: the scrubber never redacts a value containing `$(` or a backtick, so the inner command is judged on its own merits.

The helper `git-branch-prune.sh` is sound on its deletion guards (never the current branch, the base, `main`/`master`; restore SHA printed) but trusts "a merged PR exists for this branch name" as proof that the *current* head is merged; a branch that received new local commits after its PR merged is deleted with those commits reachable only from the reflog. Medium: recoverable, and the helper prints the SHA.

**Overall Risk Level:** HIGH (one confirmed bypass at the audited commit; fix present in the working tree, pending re-review)

**Key Statistics:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 1 |
| Low | 4 |

---

## Category Scores (Rubric-Based Assessment)

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 3.6/5 | IV:3 AZ:4 CI:4 IN:4 AV:3 |
| Architecture | 4.4/5 | MO:4 SC:5 RE:4 CX:4 ST:5 |
| Code Quality | 4.2/5 | RD:4 TC:5 EH:4 TS:4 DC:4 |
| DevOps | 4.2/5 | AU:4 OB:4 RC:4 AC:5 DS:4 |
| **Overall** | **4.0/5** | |

---

## High Priority Issues (Fix Before Production)

### [HIGH-001] Assignment after a reserved word rebinds the once-bound mktemp variable

**Severity:** HIGH | **Confidence:** high
**Component:** `.claude/hooks/safety/block-destructive-bash.sh:1284-1302` (`_fr2_var_value` at `87b7522c`)
**Criterion:** SEC-IV Input Validation — CWE-20 Improper Input Validation (https://cwe.mitre.org/data/definitions/20.html); consequence class CWE-78 (https://cwe.mitre.org/data/definitions/78.html)

**Reasoning Trace:**
> The proof requires exactly one statement-initial `NAME=` (`(^|[;&|(]|\n)[[:space:]]*(export[[:space:]]+)?NAME=`) and no rebinding builtin (`_fr2_rebindable`). Bash also accepts an assignment-only command as the *condition* of `if`/`while`/`until`, inside `{ }`, and after `!`; those positions are preceded by a reserved word plus a space, not by a separator, so the counter sees one binding while the shell performs two. Dissent payload 2 named the shape; I replayed it.

**Proof of Concept (at `87b7522c`, hook exit code shown):**
```
0  <- T=$(mktemp -d); if T=/; then rm -rf "$T"; fi
0  <- T=$(mktemp -d); while T=/; do rm -rf "$T"; break; done
0  <- T=$(mktemp -d); { T=/; }; rm -rf "$T"
0  <- T=$(mktemp -d); ! T=/; rm -rf "$T"
2  <- T=$(mktemp -d); true && T=/ ; rm -rf "$T"      (separator form: already counted)
```
**Impact:** an agent-produced (or model-injected) command can delete an arbitrary directory while the fence reports it as a scratch cleanup. The `rm -rf /` literal itself is stopped by GNU `--preserve-root`, but `T=/home/me` is not.
**Remediation (present in the working tree, `:1297-1306`):** after the statement-initial count, count *every* `NAME=` token in the command with `(^|[^[:alnum:]_])NAME=`; the proof holds only when that total is also exactly one. Verified: all five shapes above → 2; `T=$(mktemp -d) && cp -r out "$T"/ && rm -rf "$T"` → 0. Corpus rows D51–D54 and one named case pin it; `echo T=/` becomes an accepted false positive (R05).
**References:** CWE-20, CWE-78; OWASP A03:2021 Injection (https://owasp.org/Top10/A03_2021-Injection/)

---

## Medium Priority Issues (Address in Next Sprint)

### [MED-001] `git-branch-prune.sh` treats "a merged PR exists for this branch name" as proof the current head is merged

**Severity:** MEDIUM | **Confidence:** high
**Component:** `.claude/scripts/git-branch-prune.sh:70-76` (`squash_merged`)
**Description:** the probe is `gh pr list --state merged --head <name> --json number --jq length > 0`. A branch whose PR merged and which then received local commits (re-used branch name, unpushed follow-up) is deleted; the new commits survive only in the reflog and in the SHA the helper prints.
**Impact:** loss of local-only work behind a recoverable pointer — exactly the class the FR-1.1 fence exists for, reintroduced by the sanctioned path.
**Remediation:** ask for `headRefOid` and require it to equal the local head (`git rev-parse refs/heads/<name>`); otherwise keep the branch. Test: stub `gh` returns a stale OID → branch kept.
**References:** CWE-706 Use of Incorrectly-Resolved Name or Reference (https://cwe.mitre.org/data/definitions/706.html)

---

## Low Priority Issues (Technical Debt)

### [LOW-001] Variable contents inside a temp path remain invisible (pre-existing)
**Component:** `.claude/hooks/safety/block-destructive-bash.sh:1240` (`_fr2_temp_path_re`)
**Description:** `rm -rf "/tmp/$D"` is allowed and `D=../../home` resolves outside `/tmp`. The pre-sprint `/tmp/.+` allow entry had the same property; the accepted-bypass table (header, SDD §11) covers variable contents. Not a regression; recorded for completeness.

### [LOW-002] Corpus lint TLD list
**Component:** `tests/unit/block-destructive-bash.bats:1569`
**Description:** `\b[a-z0-9-]+\.(com|io|net|fm|dev|org)\b` misses `.ai`, `.co`, `.xyz`, `.app`, `.cloud`, `.sh`. Rows are hand-authored today; extend when the corpus is next seeded from sessions.

### [LOW-003] `run-corpus.sh` timing is GNU-only
**Component:** `tests/fixtures/fence-corpus/run-corpus.sh:38,58`
**Description:** `date +%s%N` prints a literal `N` on BSD/macOS `date`, so `runtime_ms` is garbage there and the runtime gate misfires locally. Use `$EPOCHREALTIME` (bash ≥ 5) with a `date` fallback.

### [LOW-004] `--help` exits 2
**Component:** `.claude/scripts/git-branch-prune.sh:49`
**Description:** cosmetic; conventional exit 0 for an explicit help request.

---

## Cross-Model Security Observations

- Dissent run: `gpt-5.5-pro`, 94 k input tokens, 70 s, `status: reviewed`, 0 accepted findings, 2 rejected on schema (`missing-or-empty-failure_mode`), `degraded: false` per the orchestrator. Both rejected payloads were triaged:
  - Payload 2 (reserved-word rebinding) → **confirmed**, tallied as HIGH-001 above.
  - Payload 1 (grep carrier hides `$(…)`) → **refuted**. `_bdb_scrub` (`:287-300`, unchanged this sprint) redacts a quoted value only when it holds neither `$(` nor a backtick (runbook `docs/runbooks/hook-safety.md` Case A). Probes at `87b7522c`: `grep "$(rm -rf /)" file` → 2, `grep -rn "$(rm -rf /)" .` → 2, `` grep -e `rm -rf /` file `` → 2. `grep "$(rm -rf /tmp/victim)" file` → 0 because the *inner* `rm -rf /tmp/victim` is itself an allowed temp-path delete — identical to typing it directly. Pinned by corpus D55 and a named case.

---

## Security Checklist Status

- [x] No hardcoded secrets (corpus lint gate; helper reads no credentials; `gh` uses its own auth)
- [x] Secrets in gitignore (no new state files)
- [x] Input validation at the trust boundary — one hole found (HIGH-001), fixed in the working tree
- [x] No network in the hook; helper probe bounded and opt-out
- [x] Audit trail — `emit_block` still writes the sanitized row; helper prints restore SHAs
- [x] Fail-open posture unchanged (hook-guard wrapper; every predicate falls back to the pre-sprint block on error)

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 1 |
| Low | 4 |

## Verdict

**CHANGES_REQUIRED** — HIGH-001 is a confirmed bypass at the audited commit. The fix is already in the working tree with corpus and named-case coverage; it must land as a commit, pass the suites, and be re-reviewed before the audit can approve. MED-001 should be fixed in the same round (small, tested with the existing stub `gh`).

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":1,"low":4},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-241","ts":"2026-09-23T04:24:30Z"} -->
