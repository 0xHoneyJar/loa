All good

sprint-bug-283 has been reviewed and approved. All acceptance criteria met. Observations documented and non-blocking. See Observations below.

# sprint-bug-283 Review Feedback (round 3 — final)

**Reviewer:** Senior Tech Lead Reviewer Agent (Claude Fable 5.1)
**Date:** 2026-10-29
**Sprint Reference:** grimoires/loa/a2a/bug-20261028-90f357/sprint.md (micro-sprint, `/bug` 20261028-90f357, KF-064)
**Implementation Report:** grimoires/loa/a2a/bug-20261028-90f357/reviewer.md; rounds 1 and 2: `engineer-feedback-r1.md`, `engineer-feedback-r2.md`
**reviewed_head:** 36fcbbfe5 — ledger 46962aab0 → red 698ab4eca → fix f2b3d97e9 → hardening 00597308e → r1 red 1c7588151 → r1 fix 64e8eabf8 → r2 red ceaeba1f8 → r2 fix 462d4fd80 → test correction 36fcbbfe5, on `fix/post-merge-release-readback` from `main` 2abe98199.

---

## Overall Assessment

The bug is the v2.0.0-rc.9 publish of 2026-10-28: the publisher created the release and then failed its own read-back because GitHub stores a literal `\u00XX` escape of a C0 control or DEL as caret notation, so the exact body comparison could never pass for notes that quote one. The fix keeps the C-3 identity check and gives it exactly one tolerance: `release_body_identical` normalises both the sent notes and the read-back body with one shared definition of GitHub's rewrite (in one `python3 -I` process fed through temp files written by the `printf` builtin, read as bytes) and prints `equal` or `differ <a> <b>`; `id`, `tag_name`, `draft`, `prerelease` and `name` stay exact; the sealed candidate is never modified; any other outcome refuses with the cause in the state receipt. Two rounds of cross-model dissent each found a real defect in the fix as it stood — a trailing-newline tolerance from command substitution (round 1) and an argv E2BIG failure for large bodies (round 2) — and each was closed red-first. Round 3 is my verify-only re-check of the round-2 pair and the fixture correction without a third dissent run (the sprint's third run is the audit's — BUG-283-2): I read the final diff of `phase_release`, `release_body_normalize` and `release_body_identical` in full, ran the whole publication file (71/71), ran `red-test-check.sh` for all three red/fix pairs (VERIFIED ×3, each red failing only its own case), and re-proved the real rc.9 pair (`equal`), a tampered body (`differ`) and a CRLF body (`differ`) through the production comparator. The only test defect of the round was the fixture's own trailing newline (`200009` vs `200010`), corrected in 36fcbbfe5 with the production code untouched.

**Verdict:** APPROVED

---

## Observations

### 1. The release POST still carries the body on argv (pre-existing)

- **LOW** (confidence: medium) `.claude/scripts/post-merge-orchestrator.sh:1297` — the creation request is built with `jq -nc --arg body "$notes"`, unchanged by this sprint (cycle-133 C-3). Failure: when the notes exceed 131 072 bytes then the POST itself cannot be exec'd and the release is never created — the write-side twin of the read-back defect fixed here. Bead bd-qyvju.

### 2. Temp files on a hard kill

- **LOW** (confidence: high) `.claude/scripts/post-merge-orchestrator.sh:1190-1205` — `release_body_identical` creates a `mktemp -d` directory and removes it after python returns. Failure: when the publisher is SIGKILLed between the write and the removal then two small files of public release-note text remain under `$TMPDIR`; no secret, no later read of them.

### 3. A refusal message carries up to 200 characters of python's last stderr line

- **LOW** (confidence: medium) `.claude/scripts/post-merge-orchestrator.sh:1248-1256` — the cause of a comparison failure is copied into the state receipt. Failure: when a `JSONDecodeError` or `UnicodeDecodeError` quotes bytes of the read-back then up to 200 characters of public release-note text appear in `.run/post-merge-state.json`; the receipt already records the release body's identifiers, and bodies are public, so the exposure is nil — noted for the auditor.

---

## Rejected dissent payloads

None: `metadata.rejected_summary` is empty in both review envelopes (`adversarial-review-r1.json`, `adversarial-review.json` = round 2) and the sidecar has zero rows; round 3 ran no dissent (BUG-283-2).

---

## Cross-Model Observations

Round 1 (`--diff-file` of 46962aab0..f2b3d97e9, budget 300): 2/2 voices, four findings — 1 BLOCKING primary (trailing-newline tolerance, CONFIRMED → r1 fix), 1 BLOCKING companion (python3-failure path, already fixed in 00597308e), 2 ADVISORY (adopted). Round 2 (`--diff-file` of 00597308e..64e8eabf8, budget 300; a process-substitution path was refused by the script and re-run from a regular file): 2/2 voices, five findings — 1 BLOCKING primary (argv E2BIG, CONFIRMED → r2 fix), 4 ADVISORY (three adopted; one pre-existing → bd-qyvju). Cost 0 in both runs. Round 3: no run.

---

## Acceptance Criteria Check

| Criterion (micro-sprint) | Status | Evidence |
|---|---|---|
| Failing test reproduces the bug, committed alone before the fix | Pass | 698ab4eca: case A fails on the unfixed script with the production transcript (`[TAG] Verified …` then `[release] Release identifier or read-back mismatch`) |
| The fix is a later commit that does not weaken the test (`red-test-check.sh` exits 0) | Pass | VERIFIED ×3: 698ab4eca → f2b3d97e9, 1c7588151 → 64e8eabf8, ceaeba1f8 → 36fcbbfe5 (`~/.cache/loa/cycle-137/logs/rtc-bug-283*.json`; `--env-pass PYTHONUSERBASE` so the sandbox can import `rfc8785` for the unrelated `recanon` cases) |
| No regressions | Pass | `tests/unit/post-merge-publication.bats` 71/71 at 36fcbbfe5 (64 pre-existing + 7 new); the change is confined to `phase_release`'s comparison and two new helpers |
| Root cause, not symptom | Pass | the tolerance is exactly GitHub's rewrite, applied to both sides; CRLF, trailing newlines, an appended line and a one-caret shift still refuse; the real rc.9 pair compares `equal` |
| System Zone discipline | Pass | manifests regenerated under the bounded marker at each of the four System Zone commits; `check-loa.sh` All checks passed on 36fcbbfe5 |

---

## Security Checklist

- [x] No secrets: the fixtures are public release-note text; no credential or push configuration touched
- [x] Inputs stay data: the read-back JSON reaches jq-free python as a file read as bytes and `json.loads`; the body is never evaluated or interpolated; the python program text is a script literal
- [x] Fail closed: python3 missing, unparsable read-back, non-dict/non-string body, any unexpected token → named refusal (never `equal` by accident)
- [x] The sealed candidate is never rewritten (its approved digest is checked before any phase and after a publish in the fixture test)
- [x] No new flag, config key or dependency

---

## Next Steps

1. `/audit-sprint sprint-bug-283` on 36fcbbfe5 (the sprint's third dissent run, full code diff 46962aab0..36fcbbfe5).
2. On `APPROVED`: `COMPLETED`, bug state `COMPLETED`, ledger bugfix cycle `completed`, PR from `fix/post-merge-release-readback` (classifies `other`; the rc.10 candidate is not published by this PR), Bridgebuilder, merge.

---

*Generated by Senior Tech Lead Reviewer Agent*
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":3},"excluded":0,"sprint_id":"sprint-bug-283","ts":"2026-10-29T00:20:00Z"} -->
