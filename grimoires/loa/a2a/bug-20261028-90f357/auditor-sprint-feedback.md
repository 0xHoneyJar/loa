# Security & Quality Audit Report — sprint-bug-283 (bug 20261028-90f357, KF-064)

**Auditor:** Paranoid Cypherpunk Auditor (Claude Fable 5.1)
**Date:** 2026-10-29
**Scope:** `git diff 46962aab0..af514ab6a -- .claude/scripts/post-merge-orchestrator.sh tests/unit/post-merge-publication.bats tests/fixtures/post-merge/rc9-release-body/` — the publisher's release read-back comparison (`phase_release`, two new helpers, one shared caret definition), the test stub's `GH_BODY_REWRITE=caret` mode, seven new test cases, two literal fixtures. Working notes: `audit-notes.md` (4 sources, 5 sinks, every entry traced).
**reviewed_head:** 50ee08bbc — af514ab6a (the head the dissent-informed audit was written on; the audit's four advisories are adopted in it) plus the Bridgebuilder round-1 adoptions 50ee08bbc, re-bound verify-only: a refusal message string, a success-receipt field (`body_match`), fixture README text and test assertions — no identity term, tolerance or failure path changed; 71/71; `red-test-check.sh` VERIFIED against 50ee08bbc. The review verdict in `engineer-feedback.md` is bound to the same head.
**Methodology:** 5-category review over the full diff, source/sink tracing, two executable probes (the real rc.9 pair through the production comparator; a 200 000-byte body), and the two-voice security dissent (the sprint's third and last run — DEC-1142).

---

## Executive Summary

The change narrows to one question: can the publisher's release read-back be made to accept a release that is not the one it created, or to refuse the one it did? Before the fix the second failure was real (v2.0.0-rc.9: GitHub stores a literal `\u00XX` escape of a C0 control or DEL as caret notation, so an exact body equality never passed for notes that quoted one, and the ledger and notify phases stayed pending). After the fix the body comparison tolerates exactly that rewrite — one shared regular expression applied to BOTH the sent notes and the read-back body inside one `python3 -I` process that reads both inputs as bytes from temp files written by the `printf` builtin — and nothing else: CRLF-versus-LF, trailing newlines, an appended line and a one-caret shift all refuse (pinned by tests), the real rc.9 pair compares `equal`, a 200 000-byte body compares (no argv limit), and `id`, `tag_name`, `draft`, `prerelease` and `name` stay exact. The read-back is data throughout (a file read as bytes, `json.loads`, no interpolation into any program), the program text is a script literal, python runs with `-I`, and every failure path — python missing, an unparsable or non-object read-back, a non-string body, a failed `mktemp`, an unexpected token — is a named phase failure, never an accidental `equal`. The sealed candidate is never rewritten (its digest is checked before any phase and after a publish in the fixture test). The security dissent (gpt-5.5-pro via codex-headless + claude-headless, 2/2, status `clean`) returned four LOW advisories from the companion voice and nothing from the primary; all four are adopted in af514ab6a.

**Overall Risk Level:** LOW

**Key Statistics:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 4 |

---

## Category Scores (Rubric-Based Assessment)

| Category | Score | Notes |
|---|---|---|
| Security | 9/10 | identity check kept exact on every term but the body; the body tolerance is one documented rewrite proven against real data; fail-closed on every error path; inputs never on argv, never interpolated |
| Architecture | 9/10 | one shared definition of the rewrite; the comparison owns its temp files; no new flag, config key or dependency |
| Code Quality | 8/10 | three review rounds were needed to get the shell/python boundary right (command substitution, argv) — the final shape is the simple one; 7 new tests incl. a real-data fixture |
| DevOps | 9/10 | manifests regenerated under the bounded marker at every System Zone commit; red-test-check VERIFIED ×3 |
| Blockchain | N/A | — |

---

## Critical Issues (Fix Immediately)

None.

---

## High Priority Issues (Fix Before Production)

None.

---

## Medium Priority Issues (Address in Next Sprint)

None.

---

## Low Priority Issues (Technical Debt)

### [LOW-001] a non-object read-back relied on the jq identity terms to refuse (FIXED in af514ab6a)

- **LOW** (confidence: high) `.claude/scripts/post-merge-orchestrator.sh:1196-1200` — before af514ab6a the python comparator mapped a non-dict read-back to an empty body and left the refusal to the surrounding identity check. Failure: when the read-back is a JSON array or scalar then the helper that owns the body comparison prints `differ` instead of naming the shape error, and correctness rests on the separate jq terms (DISS-C-001). Fixed: `if not isinstance(rb, dict): raise SystemExit('read-back is not a release object')`.

### [LOW-002] temp files on abrupt termination (FIXED in af514ab6a; SIGKILL residual)

- **LOW** (confidence: high) `.claude/scripts/post-merge-orchestrator.sh:1184-1190` — the comparison's `mktemp -d` directory was removed only on the normal path. Failure: when the function returns early or the script exits under `set -e` between the write and the removal then two files of public release-note text remain under `TMPDIR` (DISS-C-002). Fixed with a `RETURN` trap; a SIGKILL cannot be trapped and may still leave them (no secret, never read later).

### [LOW-003] a failed mktemp for the stderr capture exited without a recorded phase (FIXED in af514ab6a)

- **LOW** (confidence: high) `.claude/scripts/post-merge-orchestrator.sh:1252-1255` — `body_err=$(mktemp …)` ran unguarded under `set -e`. Failure: when `mktemp` fails after the release has been created then the script exits with no `fail_phase` reason and the state receipt disagrees with GitHub (DISS-C-003). Fixed: the failure is a recorded release-phase failure.

### [LOW-004] tests wrote transient files to the host's shared temp directory (FIXED in af514ab6a)

- **LOW** (confidence: high) `tests/unit/post-merge-publication.bats:9-11` — the orchestrator under test used the host `TMPDIR`. Failure: when a run is interrupted then release-body temp files are left in the shared `/tmp` instead of the case tree that `teardown` removes (DISS-C-004). Fixed: `setup` exports `TMPDIR` under `$CASE_DIR`; the big-body case asserts the comparison left nothing behind.

---

## Rejected dissent payloads

None: `metadata.rejected_summary` is empty and no `adversarial-rejected-audit*.jsonl` sidecar exists beside the envelope.

---

## Cross-Model Observations

`adversarial-review.sh --type audit --sprint-id sprint-bug-283 --diff-file <code-only diff 46962aab0..36fcbbfe5 incl. the fixtures> --context-file auditor-concerns.md --budget 400 --json` (run 3 of the sprint's ≤ 3). Envelope `adversarial-audit.json` (copied beside this file from `a2a/sprint-bug-283/`): status `clean`, `verdict_quality` 2/2 (codex-headless gpt-5.5-pro, claude-headless), no voice dropped, cost 0. Four findings, all LOW, all from the companion voice; the primary voice returned none. Triage: DISS-C-001 → LOW-001 (fixed), DISS-C-002 → LOW-002 (fixed; SIGKILL residual), DISS-C-003 → LOW-003 (fixed), DISS-C-004 → LOW-004 (fixed). The dissent ran on 36fcbbfe5; af514ab6a is the adoption of its own advisories, read in full by the auditor (no identity term, tolerance or happy-path behaviour changed; 71/71; red-test-check VERIFIED against it).

---

## Security Checklist Status

### Secrets & Credentials
- [x] No secrets in the diff or the fixtures (public release-note text); no credential, push configuration or trust store touched

### Authentication & Authorization
- [x] The publish gates (`publish_gate release`: main contains the merge; the approved digest) are unchanged; the release is created and verified under the same identity as before, with one documented body tolerance

### Input Validation
- [x] The read-back is parsed with `json.loads` on bytes; a non-object, a non-string body, invalid JSON or invalid UTF-8 refuse; the token the shell accepts is `equal` or `differ <n> <n>` only
- [x] The normalisation is one regex on a 6-character literal pattern; it is applied to both sides; a stored body that differs in any other way (CRLF, trailing newlines, an appended line, a one-caret shift) refuses (seven tests + the real rc.9 pair)
- [x] No body text enters a program: the python source is a script literal (`RELEASE_BODY_CARET_PY`), inputs travel through temp files, nothing on argv

### Data Privacy
- [x] Up to 200 characters of python's last stderr line reach the state receipt — public release-note text at most; no secret surface

### Supply Chain
- [x] Dependencies unchanged (python3 and jq already required on the publish path); `.claude/checksums.json` consistent (`check-loa.sh` All checks passed on af514ab6a)

### API Security
- [x] No new network call; the POST path is unchanged (its argv-borne body is pre-existing → bd-qyvju)

---

## Threat Model Summary

| Actor | Vector | Control | Residual |
|---|---|---|---|
| Someone with write access to the repo's releases | edit the release body before the publisher's read-back so a different body passes | the body must equal the sent notes after GitHub's caret rewrite on both sides; any other difference refuses | a body that differs only by that rewrite IS the same rendered notes — by design |
| Same actor | change the title, draft or prerelease flag | exact identity terms unchanged | none |
| GitHub (storage normalisation) | rewrite other escape families in future | they would refuse (fail closed) until the normaliser learns them | a future publish could fail read-back like rc.9 did — detectable, never a false pass |
| Local user with write access to TMPDIR | tamper with the two temp files between write and read | a fresh `mktemp -d` (0700) directory per comparison; files written and read within one function | none for a sticky-bit /tmp |
| Operator (large release notes) | notes near GitHub's limit | inputs through files, not argv | the POST side still uses argv (pre-existing, bd-qyvju) |

---

## Positive Findings

- The fix is the minimal one: a single documented tolerance, proven against the real production pair, with every other difference still refused.
- Three review rounds of cross-model dissent each found a real boundary defect (newline stripping, argv size) and each was closed red-first with a deterministic test; the production comparator itself is exercised by the fixture test.
- Every failure path names its cause in the state receipt instead of aborting or passing silently.

---

## Recommendations

### Immediate Actions (24 Hours)
- None required for merge.

### Short-Term Actions (1 Week)
- bd-qyvju: move the release POST and notify bodies off argv (`--rawfile` / stdin).

### Long-Term Actions (1 Month)
- Consider recording the sent body's sha256 in the state receipt at creation time as a second oracle for post-hoc audits.

---

## Verdict

**APPROVED - LET'S FUCKING GO**

sprint-bug-283 is approved on reviewed head af514ab6a: no critical, high or medium finding; the four low findings from the dissent are adopted in the head. `COMPLETED` follows this file; the bug state and the ledger's bugfix cycle move to completed.

---

*Generated by Paranoid Cypherpunk Auditor Agent*
<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":4},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-bug-283","ts":"2026-10-29T00:45:00Z"} -->
