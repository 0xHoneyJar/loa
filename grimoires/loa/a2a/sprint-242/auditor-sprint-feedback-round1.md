# Sprint 2 (global 242) Security & Quality Audit — round 1

**Auditor:** Paranoid Cypherpunk Auditor (Fable 5.1, inline under `/run sprint-plan`)
**Date:** 2026-09-23
**Scope:** commit `5791f92f` (review-approved round 2) — `.claude/scripts/notes-guard.sh`, `.claude/scripts/loa-status.sh`, `.claude/scripts/update-loa.sh`, `.claude/data/skill-includes/context_discipline.md` + the 10 regenerated skills, three trimmed skills, `docs/migration/v2.0-model-generation-floor.md`, `tests/unit/{notes-guard,update-loa-notes-rotation,loa-status-artefacts}.bats`
**Methodology:** Phase 0.5 scope; recon of the new inputs (a user-supplied `--file`, a `--section` spec, two env variables, three settings-free scripts); forward tracing from each input to its sinks (awk regex construction, `sed -n` line ranges, temp files, the rotation's `cp`/`mv`, the vendored refresh's child process); independent cross-model dissent (`adversarial-audit.json`, gpt-5.5-pro, diff only: `status: clean`, 0 findings, 0 rejected); the four applicable categories.

---

## Executive Summary

The reader takes untrusted text (a heading spec) and turns it into an awk regex or an `index()` search; the only interpolations into a regex are digit runs captured by `[0-9]+`, and the free-text path goes through `ENVIRON` and `index()`, so no spec can escape into pattern syntax or the shell. Line ranges come from awk's own `NR`, never from the spec. Output is capped through a `mktemp` file with default 0600 permissions and removed. The rotation is unchanged from rc.1 (archive-first, fsync, `mv -f` in the same directory, no stash). The `/loa` line only reads sizes and the `check` verdict.

One finding is worth a fix before approval and is the reason this round is CHANGES_REQUIRED on the auditor's judgment rather than by the one-way rule: the vendored-mode refresh now honours `LOA_VENDORED_UPDATE_SCRIPT` unconditionally. It exists for the ULR-5 test, but in a real update an environment variable can substitute an arbitrary executable for `update.sh`, run as the operator with the repository as cwd. This repository's convention (agent-network primitives, CLAUDE.loa.md "test-mode env overrides are test-mode/bats gated") is that test seams are honoured only under a bats marker. Same user, local env, no privilege change — MEDIUM, not HIGH — but it is a new production-path hook that should not exist, and the fix is three lines.

**Overall Risk Level:** LOW after MED-001

**Key Statistics:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 1 |
| Low | 3 |

---

## Category Scores (Rubric-Based Assessment)

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 4.2/5 | IV:5 AZ:4 CI:4 IN:4 AV:4 |
| Architecture | 4.6/5 | MO:5 SC:5 RE:4 CX:4 ST:5 |
| Code Quality | 4.4/5 | RD:4 TC:5 EH:4 TS:5 DC:4 |
| DevOps | 4.4/5 | AU:4 OB:5 RC:4 AC:5 DS:4 |
| **Overall** | **4.4/5** | |

---

## Medium Priority Issues (Address in Next Sprint)

### [MED-001] Test seam `LOA_VENDORED_UPDATE_SCRIPT` is honoured in production updates

**Severity:** MEDIUM | **Confidence:** high
**Component:** `.claude/scripts/update-loa.sh:576` (`local update_script="${LOA_VENDORED_UPDATE_SCRIPT:-${script_dir}/update.sh}"`)
**Criterion:** SEC-AZ / CWE-15 External Control of System or Configuration Setting (https://cwe.mitre.org/data/definitions/15.html); CWE-489 Active Debug Code (https://cwe.mitre.org/data/definitions/489.html)

**Reasoning Trace:**
> Introduced by the review-round-1 fix so ULR-5 can drive `main()` with a stub. The variable is read with no gate; `"$update_script" "$@"` then executes it. A `direnv`/`.envrc`, a CI environment, or a shell profile can set it. The operator already runs `update-loa.sh` with their own privileges, so this is not an escalation, but it is a silent redirection of a trusted refresh step to an arbitrary path, and the repository has a stated rule against ungated test overrides.

**Impact:** an update that appears to refresh the framework runs a different executable instead; nothing in the log distinguishes the two.
**Proof of Concept:**
```
LOA_VENDORED_UPDATE_SCRIPT=/tmp/evil.sh .claude/scripts/update-loa.sh   # vendored mode → runs /tmp/evil.sh
```
**Remediation:** honour the override only when `BATS_TEST_FILENAME` is set (the bats marker used elsewhere); add a case to ULR-5 that proves the variable is ignored without the marker.
**References:** CWE-15, CWE-489

---

## Low Priority Issues (Technical Debt)

### [LOW-001] GNU `stat -c%s` in `display_artefacts_line` and `notes-guard.sh`
**Component:** `.claude/scripts/loa-status.sh:699`, `.claude/scripts/notes-guard.sh:70`
**Description:** BSD `stat` uses `-f%z`; on macOS the sizes read as 0 and the warn is never raised. Pre-existing in `notes-guard.sh` (rc.1); consistent, not new. A `size_of` helper with a BSD fallback would fix both.

### [LOW-002] Per-block byte count over-counts by one without a trailing newline
**Component:** `.claude/scripts/notes-guard.sh:92-99`
**Description:** budget hint only; documented in the report.

### [LOW-003] `--section` miss prints up to 400 bytes of headings from the target file
**Component:** `.claude/scripts/notes-guard.sh:191`
**Description:** headings are the caller's own artefact; if a heading ever carried a secret it would be echoed. Acceptable for grimoire files; noted because the reader now accepts any `--file`.

---

## Cross-Model Security Observations

- Dissent (`gpt-5.5-pro`, diff only): `status: clean`, 0 findings, 0 rejected payloads — nothing to merge or refute.

---

## Security Checklist Status

- [x] No hardcoded secrets; no credential reads
- [x] Input validation: spec → digit-only regex or `ENVIRON`+`index()`; line ranges from `NR`; `--file` must be a regular file
- [ ] No debug/test hooks in production paths — MED-001
- [x] Temp files via `mktemp` (0600), removed; rotation archive-first, `mv -f` same directory, no stash
- [x] No new dependencies; no network
- [x] Fail-open where wanted (rotation never fails the update; reader never empty)

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 1 |
| Low | 3 |

## Verdict

**CHANGES_REQUIRED** — by auditor's judgment (zero critical/high): MED-001 is a new ungated test seam on the framework's own update path and contradicts a stated repository convention; the fix is small and testable in the same round. LOW-001…003 are recorded as debt.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":0,"medium":1,"low":3},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-242","ts":"2026-09-23T04:47:00Z"} -->
