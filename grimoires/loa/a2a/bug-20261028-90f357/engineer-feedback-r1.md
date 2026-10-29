# sprint-bug-283 Review Feedback (round 1)

**Reviewer:** Senior Tech Lead Reviewer Agent (Claude Fable 5.1)
**Date:** 2026-10-29
**Sprint Reference:** grimoires/loa/a2a/bug-20261028-90f357/sprint.md (micro-sprint, `/bug` 20261028-90f357, KF-064)
**Implementation Report:** grimoires/loa/a2a/bug-20261028-90f357/reviewer.md
**reviewed_head:** 00597308e (ledger 46962aab0 → red 698ab4eca → fix f2b3d97e9 → hardening 00597308e on `fix/post-merge-release-readback`; the dissent ran on the diff up to f2b3d97e9)

---

## Overall Assessment

The red commit reproduces the production failure exactly (the stub stores the body the way GitHub does; case A fails on the old script with `[release] Release identifier or read-back mismatch` after `[TAG] Verified`), the fix makes the publication file 66/66, `red-test-check.sh` is VERIFIED, and the normaliser applied to the real rc.9 candidate body equals what GitHub stored. The structure is right: one documented rewrite applied to both sides, every other identity term exact, the sealed candidate untouched. The cross-model dissent (2/2 voices) found one thing I missed and one thing I had already fixed before the envelope landed: the normaliser reads the bodies through a text-mode Python stdin and through shell command substitution, so a CRLF-versus-LF difference and a trailing-newline difference between the stored body and the sent notes are silently tolerated — "any other body difference refuses" is not yet true for those two classes (DISS-001). The python3-failure path (DISS-C-001) was closed by 00597308e. Both advisories (trailing newlines; a tautology between stub and fix) are worth taking in the same fix round because the test for the first is the same fixture and the second is a real-data file.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Correctness — the comparison tolerates more than GitHub's rewrite

- **HIGH** (confidence: high) `.claude/scripts/post-merge-orchestrator.sh:1168-1176` — `release_body_normalize` reads `sys.stdin.read()` in text mode (universal newlines turn `\r\n` into `\n`) and both callers capture the result with `$(...)`, which strips every trailing newline. Failure: when a pre-existing release's stored body differs from the sent notes only by CRLF line endings or by trailing blank lines then the read-back reports the body identical and the release is marked verified, although the rule the fix documents is that only GitHub's caret rewrite is tolerated (DISS-001, primary voice; DISS-C-002, companion).
**Required Fix:** do the rewrite and the equality test in ONE python process over strings decoded from JSON (feed `{sent, read}` built by `jq -n --arg sent "$notes" --argjson rb "$readback"`), never through text-mode stdin or command substitution of body text; print a single token (`equal` / `differ <sent_len> <read_len>`) for the shell. Red first: a pre-existing release whose body is the candidate body with LF → CRLF must fail read-back; one whose body has two appended newlines must fail; the existing case A must still pass.

### 2. Robustness — the normaliser's own failure (FIXED in 00597308e)

- **MEDIUM** (confidence: high) `.claude/scripts/post-merge-orchestrator.sh:1252-1262` — at f2b3d97e9 the first fix captured `release_body_normalize` with a bare `$(...)` under `set -e`. Failure: when python3 is missing or the transform crashes then the script aborts with no `fail_phase` reason in the state receipt, or, without `set -e`, both sides normalise to empty and the body term passes regardless of content (DISS-C-001). Already closed before this round by 00597308e (status captured, empty-for-non-empty refuses, named failure) — re-verified in round 2 on the new comparison path.

---

## Observations

### 1. Stub and fix share the regex (adopt in the fix round)

- **LOW** (confidence: medium) `tests/unit/post-merge-publication.bats:66-78` — the stub's rewrite and the normaliser are the same regular expression. Failure: when both encode the same misunderstanding of GitHub's rewrite then the suite passes while a real publish still fails read-back for an escape value the two observed points do not cover (DISS-C-003). Fix round: a fixture carrying the REAL differing line from the rc.9 candidate body and from the stored GitHub body (literal, not regenerated) plus a small table of expected caret forms (`\u0000`→`\^@`, `\u0009`→`\^I`, `\u001c`→`\^\`, `\u001f`→`\^_`, `\u007f`→`\^?`), asserted directly against `release_body_normalize`.

---

## Rejected dissent payloads

None: `metadata.rejected_summary` is empty and `adversarial-rejected-review.jsonl` has zero rows.

---

## Cross-Model Observations

`adversarial-review.sh --type review --sprint-id sprint-bug-283 --diff-file <code-only diff 46962aab0..f2b3d97e9, 8.1 KB> --context-file reviewer-concerns.md --budget 300 --json` (run 1 of ≤ 3). Envelope `adversarial-review.json` (moved beside this file from `a2a/sprint-bug-283/`): status `reviewed`, `verdict_quality` 2/2 (codex-headless gpt-5.5-pro, claude-headless), no voice dropped, cost 0. Four findings: primary 1 BLOCKING (→ Change 1, CONFIRMED by the probe `printf 'a\r\nb\n\n' | python3 -c 'print(repr(sys.stdin.read()))'` → `'a\nb\n\n'`); companion 1 BLOCKING (→ Change 2, already fixed in 00597308e) + 2 ADVISORY (→ Change 1's trailing-newline half and Observation 1).

---

## Next Steps

1. Red tests (CRLF, trailing newlines; the real-pair fixture + caret table as guards) → the one-process JSON comparison → `red-test-check.sh` → manifests under the marker.
2. `/review-sprint sprint-bug-283` round 2 (dissent run 2 on the fix diff).

---

*Generated by Senior Tech Lead Reviewer Agent*
<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":1,"low":1},"excluded":0,"sprint_id":"sprint-bug-283","ts":"2026-10-28T23:40:00Z"} -->
