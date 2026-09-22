All good

Observations documented and non-blocking. See Observations below.

# Sprint 4 Review Feedback — round 1

**Reviewer:** Senior Tech Lead Reviewer Agent (Fable 5.1 lead acting as gate; independent input: cross-model dissent gpt-5.5-pro on the full sprint diff with the reviewer's concern list — `adversarial-review.json`, status `clean`, 0 findings, 0 rejected payloads)
**Date:** 2026-09-22
**Sprint Reference:** grimoires/loa/sprint.md (Sprint 4, global sprint-238)
**Implementation Report:** grimoires/loa/a2a/sprint-238/reviewer.md
**Range:** `51d18251..b1a8ef79` — 28 files outside the a2a record, +1,065/−136 (SMALL; reviewed sequentially)

---

## Overall Assessment

The sprint delivers FR-10 as specified and nothing beyond it. Verified in the code, not the report:

- **`notes-guard.sh`** (`.claude/scripts/notes-guard.sh`): thresholds are literals (`:33-35`); `check` is direction-aware — `--delta ≤ 0` returns before any comparison (`:67`), a positive delta is added to the size and compared with the block line (`:68-70`), so compaction can never be locked out; `read` selects by `## ` boundaries in one awk pass (`:82-97`), Blockers first, newest Session Continuity and the three newest Decision Logs by heading date with a documented position fallback (`:103-112`), and the cap is applied to the total output including the footer (`:138-142`: `budget = READ_CAP − len(footer)`); drift falls back loudly and an empty file still prints a marker (`:129-133`); `--full` is `cat` (`:125`). `rotate` archives, `sync -d`s the archive (falling back to `sync`), refuses an existing target before touching anything (`:158-161`), writes the retained selection to a same-directory temp file and `mv`s it (`:163-175`); no stash anywhere (NG-10).
- **`notes-size-guard.sh`**: realpath match against `$LOA_GRIMOIRE_DIR/NOTES.md` with early `exit 0` on every non-matching or malformed input (`:38-47`); byte-exact deltas via `utf8bytelength` and NUL-delimited reads (`:52-58`, `:66-86`); `replace_all` multiplies by the occurrence count computed on the file text (`:59-64`); denial only when `delta > 0` and `size + delta ≥ 204,800` (`:90-99`), delegated to `check --delta` for the message. Wired in `settings.json:580` and the hooks template `settings.hooks.json:102` behind `hook-guard.sh` (the W4 wiring lint caught the missing template entry during the sprint — good).
- **`FR-NOTES`** (`block-destructive-bash.sh:1277-1299`): pre-filtered on `NOTES.md`, anchored with a trailing boundary class so `NOTES.md.bak` does not match, blocks only when `check` exits 3, falls through when the guard script or the file is absent. The 213 pre-existing fence cases pass unmodified.
- **Writer gate** (`update-notes-learnings.sh:24,148-157,175`): `check` before any write, exit 3 with nothing written; the script now honours the existing `LOA_GRIMOIRE_DIR` contract instead of a new knob. No in-repo caller depends on its exit code (only docs reference it).
- **Readers/docs**: `head -50 … | grep -A 20` is gone (`session-continuity.md:102`), Level 3 is `read --full` (`:112`), the ride reader is bounded (`ride-translation.md:34`), the exec-translation prose points at `read` (`SKILL.md:180`); thresholds and the accepted bypass classes are documented (`structured-memory.md:28`, `context-engineering.md:15`, `hooks-reference.md:155-160,180`). The stale "template ships `## Decisions`" drift sentence was removed because the template already says `## Decision Log` (`notes-template.bats:38` pins it). Protocol total after the edits: 199,525 B (budget gate `ok: true`).
- **Memo** present and decision-shaped (keep NOTES.md; the four reasons and revisit triggers are concrete).
- **Tests first**: the report's red→green record matches the files — NG-1..NG-12, NSG-1..NSG-10, FR-NOTES ×3, FR-10 ×3 in `notes-template.bats` were red before the scripts existed (I re-ran the suites: 73/73 and 216/216). The two test-side corrections (delta margin; payloads by file because of the 128 KiB argv limit) are the right fixes, not loosenings.
- **G-6**: the plan expected identical ledger hashes across the full unit suite; the implementer measured it honestly (failed twice), bisected per suite, fixed the two writers at the test seam (`cheval-preflight-gate.bats` P17 via `--mock-fixture-dir` — I confirmed the mock run exits 0 without a `[preflight]` marker, so the assertion is live; `lib-curl-fallback-flatline-chat.bats` env), tightened the discovery scan for the two missed shapes (DS-1..DS-5 green), rotated the ledgers per the runbook and re-measured clean. KF-033 records the class.

Karpathy: `notes-guard.sh` is 185 lines including its 30-line header; the hook is 100 lines of linear flow with early exits; no function exceeds 40 lines; no new config surface. Fast-gate parity: `bash -n` on every touched script; `lint-invariants.sh --hooks-wiring-only` 1 pass; `repo-map-gen.sh --validate` consistent; checksums regenerated. CHANGELOG carries one entry per task plus the G-6 fix.

Zero critical/high findings. The one medium below is a pre-existing framework bug found while running this review's own pre-execution guardrail, filed with its root cause; the lows are polish. Approval rationale: every AC row is met with `file:line` evidence, the fences are additive (existing fence cases unmodified), the escape hatch is proven open, and the dissent found nothing.

**Verdict:** APPROVED

---

## Observations

### 1. Found while running the review (pre-existing)

- **MEDIUM** (confidence: high) `.claude/scripts/guardrails-orchestrator.sh:223` — the skill-include invokes the orchestrator with `--mode ${LOA_RUN_MODE:-interactive}`; in run mode that is `--mode run`, and `danger-level-enforcer.sh` accepts only `interactive|autonomous` ("Error: --mode must be 'interactive' or 'autonomous'"), so the orchestrator substitutes `{action: BLOCK, reason: error}` for every run-mode skill invocation and the skill continues fail-open — the input guardrail (PII / injection / danger level) has been inert in run mode since at least the branch base (identical line at `80be4b0f`). Scenario: a pasted invocation carrying an injection pattern in `/run` is never scanned. Not in this sprint's diff; bead bd-rk9o (map `run`→`autonomous`, make an enforcer error a WARN distinct from a policy BLOCK, bats on a benign prompt).

### 2. Polish on the new code

- **LOW** (confidence: high) `.claude/scripts/notes-guard.sh:169-175` — if `rotate` dies between `mktemp` and `mv`, `.NOTES.md.rotate.XXXXXX` remains next to NOTES.md and is not gitignored; the live file is untouched, so no data is at risk. Fix: `trap` cleanup inside `cmd_rotate` or a `.gitignore` line. Bead bd-cs3f.
- **LOW** (confidence: high) `.claude/hooks/safety/block-destructive-bash.sh:1288` — `FR-NOTES` inherits the parent fence's quote-blindness: `echo ">> grimoires/loa/NOTES.md"` (the text inside a string) would be blocked while the file is at/over 200 KiB. Same accepted false-positive class as FR-1.2b/FR-SZ2, documented in `hooks-reference.md`; recorded, not tracked.
- **LOW** (confidence: medium) `.claude/hooks/safety/notes-size-guard.sh:61` — `_occurrences` reads the whole file into a bash variable for `replace_all`; at the 200 KiB ceiling that is bounded by construction (the file cannot grow past it through this path), so cost is capped. Recorded.

---

## Previous Feedback Status

First round for this sprint — no previous feedback.

---

## Acceptance Criteria Check

| Criterion | Status | Notes |
|-----------|--------|-------|
| AC-10.1 generated fixtures; read ≤ 20k tokens, non-empty, three headings; selection; drift; `--full`; `check` thresholds; hook direction/paths/fail-open; FR-NOTES; rotate not blocked; writer exit 3 | Pass | NG-1..NG-12, NSG-1..NSG-10, FR-NOTES ×3 (`reviewer.md` §AC-10.1 cites each `file:line`) |
| AC-10.2 rotate invariants (archive ≥, fsync-before-rewrite ordering, gitignored archive, existing target refused, retained < 100 KiB with both headings) | Pass | NG-7, NG-8, NG-10 |
| AC-10.3 memo; docs; `notes-template.bats` thresholds + empty unbounded-reader set, existing assertions untouched | Pass | memo present; 70 pre-existing assertions untouched; 3 added |
| `block-destructive-bash.bats` existing cases green unmodified | Pass | 216/216, three appended |
| `notes-template.bats` existing assertions untouched | Pass | append-only |
| Task 4.E2E G-1…G-8 | Pass | report §4.E2E; G-6 met on run 3 after the test-seam fixes (record kept honest) |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Fence patterns additive; hooks wired behind `hook-guard.sh`; existing fence cases unmodified
- [x] Escape hatch (`rotate`) proven open at 200 KiB (NG-9; FR-NOTES never matches it)
- [x] Hook fails open on malformed input and under `hook-guard.sh` (NSG-5, NSG-8)
- [x] No new dependencies (`jq`, `realpath`, `stat`, `awk`, `sort`)
- [x] Error output carries no credentials; NOTES.md stays untracked; archive dir gitignored

---

## Next Steps

1. `/audit-sprint sprint-4` — confirms `excluded_confirmed: 0` and writes the COMPLETED marker.
2. Cycle close: draft PR, zone-marker deletion, final notes.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":3},"excluded":0,"sprint_id":"sprint-4","ts":"2026-09-22T09:25:00Z"} -->
