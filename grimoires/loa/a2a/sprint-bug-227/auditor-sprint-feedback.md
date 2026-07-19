# Sprint bug-227 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-07-18
**Sprint Reference:** `grimoires/loa/a2a/bug-20260718-i1227-cf7ca4/sprint.md`
**Implementation Report:** `grimoires/loa/a2a/sprint-bug-227/reviewer.md`
**Commit Range:** `d75f5b60...2051b754`

---

## Verdict: APPROVED - LET'S FUCKING GO

---

## Executive Summary

The sprint closes the false-green trust-boundary defect: transport-successful model prose no longer participates in Flatline quorum, every participating verdict envelope is schema- and invariant-valid, stale consensus is invalidated, publication is atomic, and consumer-visible evidence fails closed unless the canonical status is `APPROVED`. Cursor remains a pure-inference subprocess (`--mode ask`, sandbox enabled, isolated working directory, no force/yolo).

No critical or high security issue was found. One medium concurrency-integrity residual and one low diagnostic-disclosure residual remain; neither can bypass the new content-qualified quorum in a single isolated run, so they are follow-up work rather than release blockers.

**Security Issues Found:**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 1 |
| Low | 1 |

## Medium/Low Priority Issues

### [ARCH-001] Same-phase concurrent runs can cross-contaminate consensus evidence

- **Severity:** MEDIUM
- **File:** `.claude/scripts/flatline-orchestrator.sh:644`
- **Issue:** Atomic rename prevents partial JSON, but the default target remains `${phase}-final_consensus.json`. Concurrent runs with the same phase can invalidate, replace, or read each other's complete artifact because the path is not bound to `run_id`.
- **Impact:** Agent automation can consume a valid but wrong run's verdict under concurrency, weakening evidence ownership.
- **Fix:** Make the canonical artifact run-scoped and publish a separate latest pointer only after the owning run consumes its artifact.
- **Reference:** CWE-362, CWE-367

### [SEC-001] Schema rejection can echo an untrusted value into logs

- **Severity:** LOW
- **File:** `.claude/adapters/loa_cheval/verdict/aggregate.py:181`
- **Issue:** `jsonschema` includes rejected instances in some `.message` values; the CLI prints that message and the orchestrator logs it on aggregation failure.
- **Impact:** An invalid model response can copy sensitive prompt material or control bytes into operator/CI stderr.
- **Fix:** Emit a bounded, control-character-stripped validator/path diagnostic without the raw rejected instance.
- **Reference:** CWE-117, CWE-209

## Dismissed Dissenter Concern

The independent security dissenter flagged possible traversal through `phase` at `.claude/scripts/flatline-orchestrator.sh:647`. Production `main` allowlists `prd|sdd|sprint|beads|spec|pr` at lines 2069-2077 before any consensus invalidation or publication; a live `../escape` probe exited 1 before the sink. Sourced helper calls do not create a privilege boundary because a caller able to source and invoke arbitrary shell functions already has process-level file authority.

## Security Checklist for This Sprint

- [x] No hardcoded secrets added
- [x] Untrusted model content normalized and schema-validated before quorum
- [x] Canonical verdict envelope schema and cross-field invariants enforced
- [x] No SQL, HTML, URL-fetch, auth, or cryptocurrency-key path introduced
- [x] Subprocess arguments remain structured argv; no shell interpolation
- [x] Cursor runs in ask mode, sandboxed, isolated, and without force/yolo
- [x] Stale evidence removed before provider work; publication is atomic
- [x] Consumer-visible evidence requires `verdict_quality.status == APPROVED`
- [ ] Default same-phase output is run-scoped
- [ ] Rejection diagnostics exclude raw model-supplied values

## Verification

- Focused Bats: **61 passed**
- Focused Python contract suites: **121 passed, 1 skipped**
- Invalid phase traversal probe: **exit 1 before file sink**
- Shell syntax: **passed**
- Diff whitespace validation: **passed**
- Independent dissenter: **reviewed, non-degraded, 1/1 Codex voice**; its one rejected-format finding was manually recovered and adjudicated above
- Integrity pre-check: `.loa.config.yaml` has no strict enforcement mode. The legacy checksum registry reports broad pre-existing drift on both `origin/main` and this branch; the branch introduced no unique checksum mismatch.

## Threat Model Summary

**Trust boundaries:** model content and per-voice envelope files are untrusted; process environment is operator-controlled; Cursor is an external inference subprocess; consensus artifacts are integrity-sensitive evidence consumed by later gates.

**Primary mitigations:** phase allowlist, JSON normalization, agent response schema validation, full verdict schema validation, cross-field invariant/status reconciliation, fixed planned denominator, fail-closed consumer gate, isolated/sandboxed subprocess, atomic publication.

**Residual risks:** phase-global concurrency ownership and value-bearing schema diagnostics, tracked as ARCH-001 and SEC-001.

## Next Steps

1. Publish this approved repair for issue #1227.
2. Consume the exact repaired harness into Sonar and rerun mechanical Flatline.
3. Track ARCH-001 and SEC-001 as linked follow-ups; do not expand sprint-bug-227.

---

**APPROVED - LET'S FUCKING GO**

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":1},"sprint_id":"sprint-bug-227","ts":"2026-07-19T01:07:44Z"} -->
