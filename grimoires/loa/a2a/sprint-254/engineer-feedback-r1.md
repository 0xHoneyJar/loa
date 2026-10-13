# Sprint 254 Review Feedback (round 1)

**Reviewer:** Senior Tech Lead Reviewer Agent (Claude Fable 5.1)
**Date:** 2026-10-13T07:01:12Z
**Sprint Reference:** grimoires/loa/sprint.md § Sprint 3 (global 254)
**Implementation Report:** grimoires/loa/a2a/sprint-254/reviewer-f.md (FR-6), reviewer-g.md (FR-7); docs (Task 3.6) and the E2E report follow from implementer H
**Commit under review:** efacf754 on feature/cycle-128-decision-surfaces (30 files, +1,932/-157), on top of 8f7932b2
**Dissent:** adversarial-review.json (gpt-5.5-pro via codex-headless + claude-headless; 2/2 voices, consensus; 6 findings, all advisory, 0 schema-rejected)

---

## Overall Assessment

The code does what the sprint asked and the implementers verified it the way the plan asked. The glossary checker keeps exactly the token shape SDD D-6.2 specifies, resolves against entries and aliases with the documented folds, reports stale and redundant allowlist entries, and its live run over the kernel is honest about what it sees (16 tokens kept: 5 aliases, 11 allowlisted identifiers, 0 misses; no kernel backtick names a glossary term directly). The glossary validator is strict in the right places (one-line entries, two sentences, 300 characters, adjacency of the annotation lines, duplicate terms and aliases folded the way the checker folds). The seams rule is Date-gated as designed and this cycle's plan passes it; the archived cycle-127 plan gains only a WARN from it. `red-test-check.sh` is careful: detached worktrees under a trap, hook-free checkout, dependency symlinks unlinked before removal, `--setup` as an argv, three timeout strategies, verdict precedence stated, honest scope in the header. I exercised it on a throwaway repository (verified pair → exit 0 with the JSON shape documented; decoy → exit 3; no worktree left behind) and reproduced the suites on the merged tree: 257 ok, 0 failed across thirteen suites, prompt budgets exit 0, skill capabilities 37/37, AGENTS.md consistent, the swallowed-jq and raw-sha256sum lints clean, `bash -n` on every new script, shell-compat greps clean.

One finding is MEDIUM because it goes to the premise of FR-6: the gate can be satisfied by the glossary itself, with one `_Aliases_:` line that names every kernel token, and nothing caps or reports that. Seven LOWs follow: fence tracking that ignores the fence character and length, the four `decision:` entries that the token shape can never check, a jq 1.6 dependency the preflight does not state, an orphan-alias record that turns into a misleading MISS, a test shim built from fixed directories, prompt budgets left with 5 to 12 bytes of headroom, and a cosmetic blank red-output block. Each is a small, local fix.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. The FR-6 gate can be satisfied by an alias line

- **MEDIUM** (confidence: high) `tools/check-glossary-terms.sh` (the glossary pass and `lookup()`), `validate-artifact.sh` `validate_glossary` — any token on an `_Aliases_:` line resolves, with no cap, no reason and no stale or redundant reporting (those exist for the allowlist only; the 30-entry cap guards the allowlist only). One `_Aliases_:` line enumerating every backticked kernel token makes CI green while the glossary defines nothing (dissent DISS-C-001, confirmed).
**File:** `tools/check-glossary-terms.sh`, `.claude/scripts/validate-artifact.sh` (`validate_glossary`), tests
**Issue:** The drift gate's integrity rests on the allowlist cap; the alias path has no equivalent, so the one agent under pressure to make CI pass has a one-line bypass that the review of a glossary diff would not flag.
**Why This Matters:** FR-6's whole promise is "a shared vocabulary that does not rot"; an uncapped alias list is the rot in a different file.
**Required Fix:** `validate_glossary` fails an entry with more than six aliases (a violation naming the term) and WARNs on an alias that shares no word with its term; the checker WARNs when alias-resolved tokens exceed the defined-term count (the kernel today: 5 aliases, 0 terms, so phrase the WARN as advisory) and the `--report` keeps the `alias` column so the ratio is visible. Tests: a seven-alias entry fails validation; the checker's WARN fires on a crafted glossary; the live files stay green.

### 2. Fence tracking toggles on any fence line

- **LOW** (confidence: high) `tools/check-glossary-terms.sh` (both awk passes), `validate-artifact.sh` `validate_glossary` — a line starting with ``` or ~~~ toggles the fence state regardless of fence character or length; a four-backtick block containing three-backtick lines, or a backtick block containing a tilde line, inverts the state for the rest of the file (dissent DISS-C-002). Fix: record the opening character and length, close only on the same character with at least that length; one implementation shared by the kernel and glossary passes; a test with a nested fence. (The Sprint 2 helpers `_md_unfenced_lines` and friends have the same simplification; out of scope here, note it for a follow-up.)

### 3. The four `decision:` entries can never be checked

- **LOW** (confidence: high) `tools/check-glossary-terms.sh` shape `^[A-Za-z][A-Za-z0-9_-]*$` — a kernel reference such as `decision:grilling` is dropped as a candidate, so the four label entries D-6.1 asks for are dead weight for the gate and a typo like `decision:griling` passes (dissent DISS-C-003). Fix: run the report with the shape widened to one interior colon (`^[A-Za-z][A-Za-z0-9_-]*(:[A-Za-z0-9_-]+)?$`) and record what the kernel gains; adopt it if the new tokens resolve or are legitimate allowlist entries, otherwise keep the shape and state in the header that label-style terms are out of the gate's scope. Either way the header says which.

### 4. `--json` needs jq 1.6 and the preflight does not say so

- **LOW** (confidence: high) `tools/check-glossary-terms.sh` — `--rawfile` and `IN(...)` are jq 1.6 features; on jq 1.5 the script exits 2 with a jq usage dump, colliding with the documented usage code (dissent DISS-C-004). Fix: replace `--rawfile` with `--arg` over `"$(cat …)"` (or `--slurpfile`) and `IN` with an `index` test, or check `jq --version` in the preflight with a clear message; a test for the message when the check is kept.

### 5. An orphan `_Aliases_:` line yields a misleading MISS

- **LOW** (confidence: high) `tools/check-glossary-terms.sh` glossary pass — an `_Aliases_:` line before any `**Term**:` is stored with an empty entry; `put()` is first-wins, so it also blocks a later legitimate alias of the same name, and the kernel token then reports a plain MISS that points at the kernel rather than the glossary (dissent DISS-C-006). Fix: skip alias lines while `entry == ""` and print a WARN naming the glossary line; a test.

### 6. RTC-9 builds its shim from fixed directories

- **LOW** (confidence: high) `tests/unit/red-test-check.bats` RTC-9 — the no-`timeout` shim symlinks `/usr/local/bin`, `/usr/bin` and `/bin`; on Homebrew (Apple Silicon), Nix or asdf hosts, jq, a modern bash, git or bats live elsewhere and the test fails for environmental reasons; an empty directory leaves a dangling `*` link (dissent DISS-C-005). Fix: build the shim from the entries of `$PATH`, skipping only `timeout` and `gtimeout`, with `[ -e "$f" ] || continue`.

### 7. Prompt budgets left at the edge

- **LOW** (confidence: high) `planning-sprints/SKILL.md` 16,372, `reviewing-code/SKILL.md` 16,378, `riding-codebase/SKILL.md` 16,379 of 16,384 bytes — every future one-word edit to these three skills fails `check-prompt-budget` in CI. Fix: trim each to at least 150 bytes of headroom without losing a rule (compress phrasing, not content); `tools/check-prompt-budget.sh` and the skill-capabilities validator stay green.

### 8. A blank red-output block when the test prints nothing

- **LOW** (confidence: high) `.claude/scripts/red-test-check.sh` `finish()` — a red run with no output prints an empty block between the markers (my throwaway run). Fix: print `(no output)` inside the block when the tail is empty; same for the green block.

---

## Observations

### 1. The gate sees backticked tokens only

By design (SDD D-6.2) the checker extracts backticked spans, and the live kernel names no glossary **Term** in backticks (the framework words appear in prose). The gate therefore guards aliases and identifiers today and the glossary's prose terms are unguarded; the glossary's value is the definitions themselves. Record this in the E2E G-5 row; no change required.

### 2. The archived cycle-127 plan fails the validator for reasons older than this sprint

`validate-artifact.sh --type sprint` on `grimoires/loa/archive/cycle-127-operator-decisions/sprint.md` exits 1 on two pre-existing required-section violations (`### Risks & Mitigation`, `### Success Metrics`); the Seams rule contributes only a WARN there, which SEAMS-9 pins. The acceptance criterion "still passes the archived cycle-127 plan" is met for the Seams rule and not for the validator as a whole; the E2E G-6 row states both.

### 3. `red-test-check.sh` and `set -m`

Job control in a non-interactive script is unusual but deliberate here (own process group per run so a timeout or an interrupt stops the whole tree), and RTC-8, RTC-9 and RTC-16 exercise it. Keep an eye on macOS bash 3.2 in the field; the suite is the guard.

---

## Cross-Model Observations

Both voices succeeded; the primary (gpt-5.5-pro) raised nothing and the companion raised six advisories, all on the glossary checker and one test. I promoted DISS-C-001 to MEDIUM because it undoes the gate's premise with one line; the rest are LOW as filed. My own additions are the budget headroom and the blank output block. Zero schema rejections.

---

## Rejected dissent payloads

None. The envelope lists zero rejected payloads and no sidecar files.

---

## Previous Feedback Status

First round for sprint-254.

---

## Incomplete Tasks

Task 3.6 (docs and release surfaces) and Task 3.E2E are in progress with implementer H; their diff is reviewed in round 2. Tasks 3.1 to 3.5 are implemented and their beads closed.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":0,"medium":1,"low":7},"excluded":0,"sprint_id":"sprint-254","ts":"2026-10-13T07:01:12Z"} -->
