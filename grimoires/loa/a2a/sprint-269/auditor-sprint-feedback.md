# Sprint 269 Security Audit Feedback — round 1

**Auditor:** Fable 5.1 lead (auditing-security contract; audit dissent run 1 = the sprint's second dissent run: gpt-5.5-pro primary + claude-headless companion, both succeeded, envelope `adversarial-audit.json`, 0 rejected payloads)
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md § Sprint 1 (global 269); scope `346dbb87..055f17a1` after the review round-1 fixes (`engineer-feedback-r1.md` APPROVED).
**Verdict:** CHANGES_REQUIRED — no critical or high finding; the lead requires the three medium findings fixed before any Phase 1 row because they weaken the one mechanical safeguard against runtime answer-key retrieval (grader class 9), and the two low findings because they are cheap and the registration is rebuilt anyway.

## Findings

| # | Sev | Where | Finding | Required change | Owner |
|---|---|---|---|---|---|
| A1 | MEDIUM | `ablation-grade.sh` `egress_command` (~2013) (DISS-001) | `bash -c '<fetch of a github host>'` and `sh -c` evade class 9: the program in command position is the shell, and `-c` strings are not recursed into. | Recurse into `bash|sh|zsh -c` string arguments with the same command rules. | C round 4 |
| A2 | MEDIUM | `ablation-grade.sh` `EGRESS_HOST` (~1982) (DISS-C-001) | Only three literal hosts match and the lookbehind refuses a dotted prefix, so `codeload.github.com`, `patch-diff.githubusercontent.com`, `gist.github.com`, `objects.githubusercontent.com`, `www.github.com` — the hosts that serve code and PR diffs — evade the rule; `EGRESS_PYLIB` misses `http.client`, `httpx`, `aiohttp`, `pycurl`, `socket`, `urllib3`. | Any host ending in `github.com`, `githubusercontent.com` or `github.io` (subdomains included); extend the python library list. | C round 4 |
| A3 | MEDIUM | `ablation-grade.sh` `egress_command` (~2003) (DISS-C-002) | Shell keywords and wrappers in command position (`if curl …`, `for … do curl …`, `{ curl …; }`, `time`, `nohup`, `xargs`, `sudo`, `setsid`, `busybox wget`), process substitution `<(curl …)`, and a heredoc piped into `bash`/`sh`/`python` all evade the rule. | Strip leading keywords and wrappers in `seg_words`; treat `<(…)` like `$(…)`; treat a heredoc piped into an interpreter as fed to it; within one heredoc-stripped logical segment, a github host together with a fetcher token (curl, wget, git fetch/clone/pull/ls-remote, gh, pip/npm/go install) anywhere in the segment is egress — prose heredocs stay data, so review-round F1 holds. | C round 4 |
| A4 | LOW | `ablation-grade.sh` `grade_union` (~3006) (DISS-C-003) | The union admits a session whose grade.json has `contaminated: null` without checking its `grader_version`; a session graded by an older grader (no class 9) merges into the cell with a null contamination. | Require every valid session's `grader_version == GRADER_VERSION` (GradeError otherwise) and record `per_session[].grader_version`. | C round 4 |
| A5 | LOW | `annotation-packets.sh` `safe()` (~163) (DISS-C-004) | The sanitizer strips C0/C1 controls and the two line separators but not the bidirectional override/isolate (U+202A–U+202E, U+2066–U+2069) or zero-width (U+200B–U+200D, U+FEFF) characters — Trojan Source vectors in head context or incident excerpts shown to blind annotators. | Replace those code points with a visible marker and have the leak check refuse a packet that still carries one. For the record: the 14 packets of this cycle's annotation contain none of these code points (scan at audit time), so the completed annotation is unaffected. | A round 2 |

## Scope of the risk

Class 9 exists because the fixes to every fixture are public on GitHub (PREREGISTRATION §2): an agent under test that fetches a fix commit or a PR diff would hold the answer key. The closed mount removes the local copy; class 9 is the only detector of the remote path. The bypasses above are ordinary shell forms a model emits without intent, so the detector must prefer catching them; the review's F1 (prose in a heredoc written as data) remains excluded by construction, since heredoc bodies are only read when fed to an interpreter.

## Other observations (no change required)

- Secrets: no credential file enters a blind session (`blind-session.sh` copies none; Bedrock auth by environment, recorded as `<set>`); the per-run HOME of pipeline arms holds the codex auth copy (cycle-131 design) — unchanged by this sprint.
- Registration integrity: `registration.py verify` recomputes every input hash; the runner refuses a changed registration, a different pin or image; the spend gate derives from the registered cap and the cycle meter (now counting `all_spend_usd`).
- The matched cells never re-run a refusal-fallback or contaminated session (D-7.3), and the row's validity now comes from cell.json alone (review F6).

## Required before approval

A1–A5 fixed with bats cases (the bypass forms above → contaminated; the review's prose-heredoc and grep/rg negatives still clean; a session with an older `grader_version` refused by the union); grader → 1.3.5; recorded-run re-grade identical; the image self-check re-run (42/42); the registration rebuilt at the new pin with a NOTES heading before any Phase 1 row.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":0,"medium":3,"low":2},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-269","ts":"2026-10-21T07:55:00Z"} -->
