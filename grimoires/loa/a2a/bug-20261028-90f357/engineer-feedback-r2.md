# sprint-bug-283 Review Feedback (round 2)

**Reviewer:** Senior Tech Lead Reviewer Agent (Claude Fable 5.1)
**Date:** 2026-10-29
**Sprint Reference:** grimoires/loa/a2a/bug-20261028-90f357/sprint.md (micro-sprint, `/bug` 20261028-90f357, KF-064)
**Implementation Report:** grimoires/loa/a2a/bug-20261028-90f357/reviewer.md; round 1: `engineer-feedback-r1.md`
**reviewed_head:** 64e8eabf8 (round-1 pair 1c7588151 → 64e8eabf8 on top of 00597308e)

---

## Overall Assessment

Round 1's requirement is met: the rewrite and the equality test now run in one python process over JSON-decoded strings, the trailing-newline tolerance is gone (the red case refuses), the CRLF guard and the real rc.9 pair pin the mapping, and the file is 69/69 with `red-test-check.sh` VERIFIED. The round-2 dissent (2/2 voices) found one thing the new code introduced: `release_body_identical` hands both bodies to `jq` on the command line (`--arg sent "$1" --argjson rb "$2"`), and Linux caps a single argument at 128 KiB, so a release whose notes approach GitHub's 125 000-character limit — or whose read-back JSON (body plus metadata) crosses that size — makes `jq` fail with E2BIG, python sees empty input, and the phase refuses a perfectly verifiable release with a message that blames tool availability. That is a regression against the pre-fix code, which never put the read-back on argv. The four advisories are cheap and two of them are the same edit (one shared caret definition; the fixture test exercising the production comparator), so they land in the same fix round.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Correctness — the comparison cannot handle a large body

- **HIGH** (confidence: high) `.claude/scripts/post-merge-orchestrator.sh:1179-1190` — `release_body_identical` passes the sent notes and the whole read-back JSON as `jq` command-line arguments. Failure: when a release body is close to GitHub's 125 000-character limit, or the read-back JSON with its asset and author metadata exceeds 131 072 bytes, then `execve` of `jq` fails with E2BIG, python receives no JSON and exits non-zero, and the release phase refuses with "comparison unavailable (python3 and jq required)" although GitHub stored exactly the expected body (DISS-001, primary voice; DISS-C-001, companion).
**Required Fix:** carry both inputs through temp files written by the `printf` builtin (no exec, no argv limit) and read them in python as bytes; drop `jq` from the comparison. Red first: `release_body_identical` on a 200 000-byte body and a read-back JSON above 131 072 bytes must print `equal`.

---

## Observations

### 1. The refusal blames tools for size or decoding problems (adopt in the fix round)

- **LOW** (confidence: high) `.claude/scripts/post-merge-orchestrator.sh:1252-1256` — python's stderr goes to `/dev/null` and the message says "python3 and jq required". Failure: when the real cause is the body size, a non-string body field or a decoding error then the operator investigates tool installation while the receipt no longer explains the refusal (DISS-C-002). Capture the last stderr line into the `fail_phase` message; read bytes in python.

### 2. A bats negation that never fails (adopt in the fix round)

- **LOW** (confidence: high) `tests/unit/post-merge-publication.bats:689` — the fixture precondition is written `! cmp -s a b`. Failure: when the two fixture files are accidentally equalised or regenerated then the negated command never fails the test and the rc.9 mapping assertion passes without proving anything (DISS-C-003; the project's own gotcha). Use `run cmp -s …; [ "$status" -ne 0 ]` and split the two `-s` checks.

### 3. Two copies of the caret regex (adopt in the fix round)

- **LOW** (confidence: medium) `.claude/scripts/post-merge-orchestrator.sh:1168-1190` — `release_body_normalize` and `release_body_identical` each carry the regex and mapping. Failure: when a future edit widens the class or changes the DEL case in one copy then the fixture test keeps passing on the helper production does not call while the production comparator drifts (DISS-C-004). One shared python definition; the fixture test also drives `release_body_identical` on the real pair (`equal`) and on a one-caret shift (`differ`).

### 4. Pre-existing: the release POST also puts the body on argv

- **LOW** (confidence: medium) `.claude/scripts/post-merge-orchestrator.sh:1265` — the creation request is built with `jq -nc --arg body "$notes"`, unchanged by this sprint. Failure: when the notes exceed 131 072 bytes (multi-byte text under GitHub's 125 000-character limit can) then the POST itself cannot be exec'd and the release is never created — the same class as Change 1 on the write side, pre-existing since cycle-133 C-3; out of this bug's scope, bead filed.

---

## Rejected dissent payloads

None: `metadata.rejected_summary` is empty in both envelopes (`adversarial-review-r1.json`, `adversarial-review.json` = round 2) and the sidecar has zero rows.

---

## Cross-Model Observations

Round 2: `adversarial-review.sh --type review --sprint-id sprint-bug-283 --diff-file <code-only diff 00597308e..64e8eabf8, incl. the fixtures> --context-file reviewer-concerns-r2.md --budget 300 --json` (run 2 of ≤ 3; a first attempt with a process-substitution diff path was refused by the script — `Diff file not found: /proc/self/fd/N` — and re-run from a regular file). Envelope `adversarial-review.json` (copied beside this file from `a2a/sprint-bug-283/`): status `reviewed`, `verdict_quality` 2/2 (codex-headless gpt-5.5-pro, claude-headless), no voice dropped, cost 0. Five findings: primary 1 BLOCKING (→ Change 1, CONFIRMED: `getconf ARG_MAX` 2 097 152 with the per-argument cap 131 072 on this host); companion 4 ADVISORY (→ Observations 1–3 adopted; C-001 folded into Change 1). Round 3 will be the lead's verify-only re-check without a third run: the sprint's third dissent is the audit's (same rule as cycle-137 Sprint 282, DEC-1134).

---

## Next Steps

1. Red test (200 000-byte body through `release_body_identical` → `equal`; the real pair and a one-caret shift through the production comparator; the `run cmp` precondition) → the file-borne, jq-free, bytes-reading comparison with one shared caret definition and the stderr cause in the refusal → `red-test-check.sh` → manifests under the marker.
2. `/review-sprint sprint-bug-283` round 3 (lead verify-only), then `/audit-sprint sprint-bug-283` (dissent run 3).

---

*Generated by Senior Tech Lead Reviewer Agent*
<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":0,"low":4},"excluded":0,"sprint_id":"sprint-bug-283","ts":"2026-10-28T23:55:00Z"} -->
