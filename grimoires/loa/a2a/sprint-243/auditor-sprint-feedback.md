# Sprint 3 (global 243) Security & Quality Audit — round 1 (final)

**Auditor:** Paranoid Cypherpunk Auditor (Fable 5.1, inline under `/run sprint-plan`)
**Date:** 2026-09-23
**Scope:** commit `d6ff411a` (review-approved round 1) — `.claude/scripts/run-preflight.sh`, `.claude/scripts/run-checkpoint.sh`, `.claude/hooks/session-start/loa-run-state-surface.sh`, `.claude/settings.json`, `.claude/hooks/settings.hooks.json`, `.claude/scripts/workflow-state.sh`, `.claude/scripts/loa-status.sh`, run-mode / run-bridge / implementing-tasks skill prose, four new test files
**Methodology:** Phase 0.5 scope; recon of the new inputs (settings files, `.loa.config.yaml` keys, `.env.local`/`.env`, `.run/*.json`, CLI flags, two bats-gated seams); forward tracing from each input to its sinks (yq expressions, `jq` filters, `command -v`, `br show`, `flock`/`mv`, stdout injected into session context); independent cross-model dissent (`adversarial-audit.json`, gpt-5.5-pro, diff only: `status: clean`, 0 findings, 0 rejected); Security / Architecture / Code Quality / DevOps.

---

## Executive Summary

The sprint adds three scripts that read a lot and write almost nothing: the preflight writes nothing at all, the checkpoint writes one JSON file atomically under a lock, and the SessionStart surface writes one or two sanitised lines into session context. The audit therefore centres on what reaches an interpreter and what reaches the session. Every model id that reaches a yq expression is shape-checked first; every bead id that reaches `br show` matches `^[A-Za-z0-9._-]+$`; state values are control-byte-stripped and capped before they are echoed; credential detection reads env and dotenv for presence and the value never leaves the function or reaches any output (PF-3 asserts the negative). The two test seams are honoured only under a bats marker and each has a negative test. The SessionStart hook runs behind `hook-guard.sh`, exits 0 on every path, and a parse-broken hook fails open with a WARN (probed by hand). `hook-wiring.bats` W10 keeps the two settings files in parity.

No critical or high finding. One MEDIUM carries over from the review (P2's inspection scope) and is filed as a follow-up bead; the LOWs are portability, a missing timeout on a resume-path subprocess, a cosmetic vacuous message, and CI coverage of the new integration proof.

**Overall Risk Level:** LOW

**Key Statistics:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 1 |
| Low | 5 |

---

## Category Scores (Rubric-Based Assessment)

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 4.4/5 | IV:5 AZ:4 CI:4 IN:4 AV:5 |
| Architecture | 4.6/5 | MO:5 SC:5 RE:4 CX:4 ST:5 |
| Code Quality | 4.4/5 | RD:4 TC:5 EH:4 TS:5 DC:4 |
| DevOps | 4.2/5 | AU:4 OB:5 RC:4 AC:4 DS:4 |
| **Overall** | **4.4/5** | |

---

## Medium Priority Issues (Address in Next Sprint)

### [MED-001] P1's conditional pass rests on P2, which inspects only `.claude/settings.json`

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `.claude/scripts/run-preflight.sh:99-107,120-124` (P2 via `check-permissions.sh:19`)
**Criterion:** SEC-AZ Authorization coverage — CWE-863 Incorrect Authorization (https://cwe.mitre.org/data/definitions/863.html) (availability consequence: an unattended run that cannot answer prompts stalls)
**Reasoning Trace:**
> P1 accepts `acceptEdits`/`default` when P2 says the run's allow rules are present. `check-permissions.sh` reads one file. Claude Code merges `settings.local.json` and `~/.claude/settings.json` and a `deny` there overrides an `allow`. The preflight would print PASS and the run would auto-deny its first fenced tool.
**Impact:** the checklist's promise ("can this run finish?") is weaker than it reads for operators with layered settings.
**Remediation:** widen `check-permissions.sh` to merge the three files and honour `deny` (bead bd-n7v3, filed by the review); until then P1's detail names the file it inspected.
**References:** CWE-863

---

## Low Priority Issues (Technical Debt)

### [LOW-001] Credential value is held transiently in a shell variable
**Component:** `.claude/scripts/run-preflight.sh:131-147` (`cred_present`)
**Description:** presence is decided by reading the dotenv value into `val`, stripping quotes and testing non-emptiness; the value is never printed, exported or logged, and the function returns 0/1 only. A `grep -qE` with a quote-aware pattern would avoid holding it at all. No exposure path exists today (PF-3 asserts no value in output).

### [LOW-002] GNU `date -d` for ages
**Component:** `.claude/scripts/run-preflight.sh:84-92`, `.claude/hooks/session-start/loa-run-state-surface.sh:37-45`
**Description:** BSD `date` prints `?` ages; staleness never triggers there (fails safe: a stale RUNNING is still refused as "in progress"; the surface stays silent). Consistent with the repository's GNU assumption.

### [LOW-003] `br show` without a timeout on the resume path
**Component:** `.claude/scripts/run-checkpoint.sh:63-68`
**Description:** a wedged beads database (KF-005 class) would hang `read`, which `/run-resume` now calls. `timeout 10` where available, discard on timeout.

### [LOW-004] Vacuous P3 message when no flatline stage is enabled
**Component:** `.claude/scripts/run-preflight.sh:186-190`
**Description:** "every configured voice has a credential or CLI hop ()" — say "no flatline stage enabled". Cosmetic.

### [LOW-005] The re-entry proof lives under `tests/integration/`
**Component:** `tests/integration/implement-reentry.bats`
**Description:** `bats-tests.yml` enumerates `tests/unit/*.bats`; the integration proof runs locally (real `br`) and skips cleanly without it. If the CI job does not run `tests/integration/`, the proof is not continuously verified — confirm in Sprint 4's full run and move or wire it if needed.

---

## Cross-Model Security Observations

- Dissent (`gpt-5.5-pro`, diff only): `status: clean`, 0 findings, 0 rejected payloads. The review dissent on the same diff was also clean. Nothing to merge or refute.

---

## Security Checklist Status

- [x] No hardcoded secrets; credential values never printed (PF-3 negative assertion)
- [x] Inputs shape-checked before interpreters (model ids → yq; bead ids → `br show`; flags → usage 2)
- [x] Session-context output sanitised and capped; fixed labels
- [x] Test seams bats-gated with negative tests (PF-S; ULR-5 precedent)
- [x] State writes atomic + locked; never replace with unparseable output (CK-4, CK-5)
- [x] SessionStart hook behind `hook-guard.sh`; exit 0 on every path; parse-broken hook fails open with WARN (probed)
- [x] No network; no new dependencies; no new config key

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 1 |
| Low | 5 |

## Verdict

APPROVED - LET'S FUCKING GO

MED-001 is filed (bd-n7v3) and documented in the checklist's own detail line; the LOWs are recorded as debt for the Sprint 4 pass and the cycle report.

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":5},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-243","ts":"2026-09-23T05:12:00Z"} -->
