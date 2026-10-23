All good

APPROVED - LET'S FUCKING GO

Sprint 269 passes the security audit after one round. The five round-1 findings are fixed, tested, self-checked in the image and bound by the rebuilt registration; nothing blocks Phase 1.

# Sprint 269 Security Audit Feedback — round 2 (auditor re-verification)

**Auditor:** Fable 5.1 lead (auditing-security contract). Round 1 used the sprint's second dissent run (`adversarial-audit.json`); this round verifies the fixes without a third run (kept spare).
**Date:** 2026-10-21
**Scope:** `346dbb87..99b46a5f`; the audit fixes are commit `a763fe06` (grader 1.3.5, sanitizer), the docs commit and the re-registration `99b46a5f`.

## Round-1 findings — verification

| # | Sev | Fix | Verified by |
|---|---|---|---|
| A1 | MEDIUM | class 9 recurses into `bash|sh|zsh -c` string arguments | ablation-grade.bats 70/70 (AG-c132-8: 28 bypass forms → `network_egress`) |
| A2 | MEDIUM | `EGRESS_HOST` matches any host ending in github.com / githubusercontent.com / github.io, subdomains included; `EGRESS_PYLIB` adds urllib3, http.client, httpx, aiohttp, pycurl, socket | AG-c132-8 (codeload, patch-diff, gist, objects, www, raw) |
| A3 | MEDIUM | `egress_words` strips leading shell keywords and wrappers (class 9 only — `seg_words` and the oracle detector unchanged); `<(…)` read like `$(…)`; a heredoc piped into bash/sh/python counts as fed to it; segment-level host + fetcher rule for curl/wget stages | AG-c132-8 positives; the six negatives stay clean (round-3 prose heredoc, separate commands, `grep \| grep`, `rg`, `git log \| grep github.com`, `echo` of a github.io string) |
| A4 | LOW | `--union` refuses a valid session whose `grader_version` is not this grader's; `per_session[].grader_version` recorded | ablation-grade.bats union cases |
| A5 | LOW | `safe()` marks U+200B–U+200D, U+202A–U+202E, U+2066–U+2069, U+FEFF with U+FFFD; the leak check refuses a packet still carrying one | annotation-packets.bats 11/11; the 14 completed packets hold none of these code points (lead scan at round 1) |

Recorded-run re-grade identical through 1.3.3 → 1.3.4 → 1.3.5 (the recall block never moved); image self-check 42/42 on 1.3.5; `bash -n` clean; full `evals/tests/` 655/655 on the review-approved tree with the audit-round files re-run green per file.

## Registration

Rebuilt after the fixes: `REGISTRATION.json` sha256 `7d520011996628de0d4be270b0648bcfaa1b3a0fc922092f385ebaa9525d02ad` at pin `622d0043d34af6359ea44cd4f71aab00ae7a5e34` (commit 99b46a5f; `registration.py verify` ok); NOTES heading written; no Phase 1 row exists; the smoke dry run passes every gate (spend gate 4,200 − 63.26).

## Residual risk, stated

- Class 9 is a detector, not a sandbox: an agent determined to reach GitHub through an unlisted tool or an obfuscated command can still do so; the pre-registration treats prior exposure as recorded and runtime leakage as scanned, and the open-mount positive control measures what the closed mount withholds. A network-egress block at the container level (no outbound except the model API) is the structural fix and is named as a follow-up, not a Sprint 269 deliverable.
- The per-run HOME of pipeline arms carries the codex auth copy (cycle-131 design, unchanged); its exposure path is KF-048's, outside this sprint.

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-269","ts":"2026-10-21T08:15:00Z"} -->
