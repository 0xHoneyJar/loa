# Sprint 4 Security Audit — cycle-124 "model-generation floor" (global sprint-238)

**Auditor:** Paranoid Cypherpunk Auditor (Fable 5.1 lead acting as gate; independent input: diff-only cross-model audit dissent gpt-5.5-pro — `adversarial-audit.json`, status `clean`, 0 findings, 0 rejected payloads)
**Date:** 2026-09-22
**Sprint Reference:** grimoires/loa/sprint.md (Sprint 4)
**Implementation Report:** grimoires/loa/a2a/sprint-238/reviewer.md
**Scope:** `51d18251..b1a8ef79` — 28 files, +1,065/−136 outside the a2a record (SMALL; all five categories sequentially by the lead). New surfaces: one script, one PreToolUse hook, one fence pattern, one writer gate, six doc/prompt edits, five test files, one memo.
**Review gate:** round 1 APPROVED (`engineer-feedback.md`, 2026-09-22)

---

## Verdict: APPROVED - LET'S FUCKING GO

---

## Executive Summary

FR-10 adds a bounded-memory mechanism whose security shape is right: the fences are additive and fail open on their own faults, the escape hatch cannot deadlock, every threshold is a literal, and the new code takes no input from a model — it reads a file the operator owns and a tool payload the harness produces. The dissenter retained no finding. One medium is recorded: a pre-existing mode-vocabulary mismatch that leaves the run-mode input guardrail inert (found by the review, not in this diff). No finding blocks.

**Security Issues Found (Phase 2.5 tally):**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 1 |
| Low | 2 |

---

## Phase 1 — Findings (trust boundaries, sinks, fail-modes)

Every item verified by reading the code at the cited line and, where stated, by running it.

### Sources and sinks

- **`notes-guard.sh`** — inputs: `--file PATH` (operator/caller-controlled), `--delta N` (regex-validated integer, `:49`), the file's bytes. Sinks: `sed -n "${s},${e}p"` with awk-derived integers only (`:119`); `mktemp` (`:135`, `:166`, `:169`); `cp`/`mv` inside the file's own directory; `head -c` with integer budgets. No `eval`, no `bash -c`, no shell interpolation of file content; every path is quoted and `--`-terminated. Usage errors exit 2 (`:37-40`, NG-12). Clean.
- **`notes-size-guard.sh`** — input: the PreToolUse payload on stdin (harness-produced JSON). Parsed only with `jq`; file-path comparison after `realpath -m` on both sides (`:43-44`) — symlinks and relative paths resolve to the canonical NOTES.md, and a different `LOA_GRIMOIRE_DIR` changes the target (NSG-6). Any non-JSON, missing field, missing file or `stat` failure exits 0 (`:31-47`). String fields are read NUL-delimited (`:53-56`), so no field content is ever executed. Output: stderr message + exit 2 (the zone-write-guard convention). Clean.
- **`FR-NOTES`** (`block-destructive-bash.sh:1288-1298`) — reads only `$command` (already the fence's input), calls the guard with a fixed argv; a missing guard or NOTES.md falls through (allow). Clean.
- **`update-notes-learnings.sh:148-157`** — the gate runs before `ensure_learnings_section` and the rewrite; exit 3 leaves the file byte-identical (NG-11). `NOTES_FILE` now follows `LOA_GRIMOIRE_DIR`, the same contract `path-lib.sh` exports — no new trust boundary. Clean.

### Data-loss review of `rotate` (the #555 class)

- Order of operations (`notes-guard.sh:158-175`): existing target refused first (exit 4, nothing touched — NG-8); `cp` to the archive; `sync -d` the archive (fallback `sync`); build the retained content in a separate temp; `mv` into place. The live file changes only by an atomic rename after the archive is durable; NG-7 asserts archive == original, archived + retained ≥ original, and archive mtime ≤ live mtime. No `git stash`, no in-place edit. Clean.
- Residual (LOW, below): a temp file can be left behind if the process dies between `mktemp` and `mv`; the live file is never at risk.

### Fail-open and deadlock analysis

- The hook is wrapped by `hook-guard.sh` (parse error → WARN + allow, NSG-8) and exits 0 on every internal problem; `FR-NOTES` allows when the guard script is missing. Neither fence can brick writes to NOTES.md: shrinking edits pass by construction (`delta ≤ 0 → exit 0`), and `rotate` (which uses `mv`, not `>>`, and is invoked through the Bash tool with no redirect) is never intercepted — NG-9 proves `check` exits 3 before and 0 after a rotation at 200 KiB.
- Accepted bypass classes are stated at the point of use (`notes-size-guard.sh` header, `hooks-reference.md:155-160`): `tee`, `python -c`, heredocs into the file, `sed -i`. Fence, not boundary — consistent with the parent fence's posture.

### Secrets and state hygiene

- No key shapes in any added line (`git diff 51d18251..HEAD` scanned). NOTES.md stays untracked; `grimoires/loa/archive/` is gitignored (`.gitignore:185`); fixtures are generated at test time (nothing large committed); the memo carries no operator content.
- The G-6 work removed two ways a plain `bats tests/unit/` run wrote the production ledgers — one of them a real `codex-headless` dispatch of ~25k input tokens from a unit test (repository content leaving the host on every test run). Both suites now isolate their ledgers and the live case runs through the mock adapter; the discovery scan catches the two missed shapes (`ledger-isolation-discovery.bats` DS-1..DS-5 green); ledgers rotated per the runbook with the archive paths recorded in the report. KF-033 records the class.

### Fences and zones

- `git diff 51d18251..HEAD -- .claude/hooks/safety/{zone-write-guard,team-role-guard-write}.sh .claude/hooks/compliance/implement-gate.sh .claude/scripts/audit-envelope.sh` is empty; `block-destructive-bash.sh` gained one additive pattern (216/216 with the three new cases, the 213 existing cases unmodified); `settings.json` and the hooks template gained one entry each (`lint-invariants.sh --hooks-wiring-only` 1 pass). System-Zone edits were made under the cycle's zone marker, which is deleted at cycle end.

### Open (counted)

**AUD4-M1 · MEDIUM · `.claude/scripts/guardrails-orchestrator.sh:223` (pre-existing, not in this diff)** — the input-guardrail orchestrator is invoked with `--mode run` in run mode; `danger-level-enforcer.sh` accepts only `interactive|autonomous`, so every run-mode skill invocation gets `{action: BLOCK, reason: error}` and proceeds fail-open (observed on this sprint's review and on the sprint-3 audit; identical line at `80be4b0f`). The PII/injection/danger-level scan is therefore inert in exactly the unattended mode it was meant for. Confidence high. Bead bd-rk9o (map `run`→`autonomous`; an enforcer error becomes a WARN distinct from a policy BLOCK; bats on a benign prompt returns PROCEED).

**AUD4-L1 · LOW · `.claude/scripts/notes-guard.sh:169-175`** — temp-file residue if `rotate` dies between `mktemp` and `mv`; not gitignored; live file untouched. Bead bd-cs3f.

**AUD4-L2 · LOW · `.claude/hooks/safety/block-destructive-bash.sh:1288`** — `FR-NOTES` shares the parent fence's quote-blindness false-positive class (a string containing `>> grimoires/loa/NOTES.md` while the file is at/over 200 KiB). Accepted by design, documented; recorded.

### Verified negatives (summary)

- Dissent: `adversarial-review.sh --type audit --sprint-id sprint-238` on the full diff → `clean`, 0 findings, sidecar absent (gpt-5.5-pro via codex-headless, `parse_path: normalized`, the unenforced hop as measured in Sprint 2).
- Suites: `notes-guard.bats` 12/12, `notes-size-guard.bats` 10/10, `block-destructive-bash.bats` 216/216, `notes-template.bats` 73/73, `hook-wiring.bats` 10/10, `ledger-isolation-discovery.bats` 5/5, `cheval-preflight-gate.bats` 17/17, `lib-curl-fallback-flatline-chat.bats` 11/11; full unit suite 5,527 with the unchanged 38-case baseline; adapters pytest 2276 passed.
- Tripwires: `tools/check-ledger-hygiene.sh` OK; `tools/check-prompt-budget.sh` `ok: true` (protocols 199,525 B); `tools/check-no-swallowed-jq.sh` OK; `tools/regen-model-artifacts.sh --check` OK; `repo-map-gen.sh --validate` consistent.

## Phase 2.5 — Severity Tally (open findings at verdict time)

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 1 |
| Low | 2 |

## Phase 3 — Verdict

APPROVED - LET'S FUCKING GO

Improvements to carry: fix the run-mode guardrail mode mismatch (AUD4-M1, bd-rk9o — the one item here worth scheduling first, since it re-arms a scan that is currently inert); trap-clean the rotate temp file (bd-cs3f); confined A/B re-measure and the sprint-3 mediums as already tracked.

## Documentation audit

CHANGELOG entry per task (FR-10 bullet + the G-6 test-isolation bullet); security-relevant code commented (`notes-size-guard.sh` header states the bypass classes; `FR-NOTES` block comment; `notes-guard.sh` header); docs updated (`hooks-reference.md`, `structured-memory.md`, `context-engineering.md`, `session-continuity.md`); no secrets or internal URLs; no API change. Manually verified — no `documentation-coherence-*` reports exist for this sprint.

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":2},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-4","ts":"2026-09-22T09:30:00Z"} -->
