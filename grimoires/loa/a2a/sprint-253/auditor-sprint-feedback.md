# Security & Quality Audit Report — Sprint 253 (cycle-128 Sprint 2), round 2

**Auditor:** Paranoid Cypherpunk Auditor (Claude Fable 5.1)
**Date:** 2026-10-13T06:15:20Z
**Scope:** commits cea919ca (implementation), 30727c95 (review round r253-1) and 8f7932b2 (audit round r253-2) on feature/cycle-128-decision-surfaces: the `/chart` decision map and its helpers, the golden-path `charting` phase, the question-bead lints, `validate-artifact.sh --type map|spike` and the sprint cross-check, the spike template, `run-mode-ice.sh` spike rules, fence SP-1 and the D-5.9 unlock, `interview.unattended_prototype`, and the tests.
**Methodology:** Round 1 (auditor-sprint-feedback-r1.md): full read of every changed script, hand-walked sources and sinks, fence patterns re-derived against the corpus, two-voice audit dissent (`adversarial-audit.json`: gpt-5.5-pro via codex-headless + claude-headless, consensus, 18 findings, 0 schema-rejected) triaged payload by payload. Round 2: every hunk of 8f7932b2 re-read against the round-1 Required Fix text; the twelve suites re-run on the merged tree; the static lints re-run; no second dissent (each fix is the one the payload asked for and each is pinned by a test or a corpus case).
**Previous round:** CHANGES_REQUIRED (0 critical, 1 high, 6 medium, 8 low).

---

## Executive Summary

Round 1 found the model's edges softer than its centre; 8f7932b2 hardens each edge the way the audit asked, with tests. The probe no longer claims a read-only run it cannot enforce: it runs the argv under a scrubbed environment (no session token, agent socket, credential helper or global git config can reach it), snapshots refs, tags, HEAD, the git config files, the hooks directory and the main tree's status around the run, fails on any difference or any file under the main tree or the shared git directory newer than its start marker, states what remains outside the check, and the skill shows the operator the exact argv before running it. The hand-off snapshot validates and PII-scans the doc first, refuses any resolved row that lacks an operator answer reference, fences the doc, the ledger rows and each report as untrusted data through temp files appended only on success, and PII-scans the result before the rename. SP-1 now judges push refspecs, the reset/read-tree/update-ref/branch-move family, the one-line fetch-then-FETCH_HEAD shape, alias definitions and `gh api` pull creation, on a whitespace-collapsed copy with a single-step span so matching stays linear; the D-5.9 unlock requires the remote-tracking ref to exist and contain the local head, and reads the ledger from the main tree. awk receives its values through `ENVIRON`; every write subcommand consults the context on its own; `san1` strips C1 and format characters; the question-bead filters and the golden-path context check fail closed; the declarative context globs are gone.

Verification on the merged tree: 589 ok, 0 failed across twelve suites (the seven Sprint 2 suites, validate-artifact, skill-capabilities, block-destructive-bash with the corpus incl. the timing case, user-invoked-commands, agents-md-gen); prompt budgets exit 0 (charting-decisions 10,613 B); skill capabilities 37/37; AGENTS.md consistent at 51 commands; swallowed-jq and raw-sha256sum lints clean; `bash -n` on every changed script; shell-compat greps clean. The one carried item (LOW-008, the researcher's unrestricted Read and WebFetch) is bead bd-akas; the harness offers no per-agent restriction today.

**Verdict:** APPROVED - LET'S FUCKING GO

---

## Category Scores (Rubric-Based Assessment)

| Category | Score | Notes |
|---|---|---|
| Security | 9/10 | Every round-1 edge closed and pinned; the remaining point is the carried researcher restriction, which needs a harness feature |
| Architecture | 9/10 | Unchanged shape; the probe's boundary and the snapshot fence now match what the design claims |
| Code Quality | 9/10 | `ENVIRON` for awk values, fail-closed filters, one `need_interactive` at every write entry; the whitespace-collapse loop in the fence is clear and commented |
| DevOps | 9/10 | 589 tests across twelve suites; corpus cases both ways for each new fence shape; the timing case guards the regex engine |
| Blockchain | n/a | |

---

## Previous Feedback Status

| Round-1 item | Status | Evidence in 8f7932b2 |
|---|---|---|
| HIGH-001 probe boundary | Fixed | `chart-unblock-probe.sh`: `env -i` with PATH, scratch HOME/TMPDIR, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`, `GIT_TERMINAL_PROMPT=0`, failing askpass, empty credential helper via `GIT_CONFIG_COUNT`, `GIT_SSH_COMMAND=/bin/false`; `snapshot()` over refs, HEAD, config files, hooks, status; `newer_files()` over the main tree and the shared git dir; worktree add with `core.hooksPath=/dev/null`; honest header; SKILL.md unblock step asks the operator to confirm the argv; CD-27c…27g |
| MEDIUM-001 snapshot fence | Fixed | `op_handoff`: `validate-artifact.sh --type map` and `pii_count` on the doc, refusal of rows without `decided_by_ref`, `fence_append` through temp files with the closing-tag neutralised and a labelled fallback fence, PII scan of the assembled body, `demote_headings` outside fences; `op_resolve`: `clean_field` on decision, rationale, evidence, consequences and answer-ref, alternatives validated as string-valued objects, `--answer-ref` required; CD-20e/20f/20g, CD-17b/17c |
| MEDIUM-002 push refspecs | Fixed | `_sp1_push_refspec`: src:dst with a spike ref on either side, HEAD/@/empty source on a spike checkout, force and plus forms; same-branch and `-u` forms allowed; corpus B62–B66, D75–D81; three push bats |
| MEDIUM-003 one-line verbs | Fixed | verbs `reset`, `read-tree`, `update-ref`; `_sp1_branch_moves`; `_sp1_fetch_head`; `_sp1_alias_def` and the `-c alias.` / `--config-env` match; `gh api` pulls with a spike head; header lists updated; corpus B67–B76, D82–D98 |
| MEDIUM-004 unlock without pushed check | Fixed | `_fr11_spike_decided` requires `refs/remotes/origin/spike/<slug>` and ancestry, reads the ledger from the parent of `--git-common-dir`; three D-5.9 bats (unpushed, local ahead, worktree ledger) and the spike-validator fixture pushes to a local bare origin |
| MEDIUM-005 awk escapes | Fixed | `ENVIRON` in `set_status`, `section_append`, `section_bullets`; CD-17b |
| MEDIUM-006 write subcommands and the context | Fixed | `need_interactive` at every write entry (`--dry-run` and `close --consumed-by` exempt); `op_handoff` refuses rows without an operator answer reference; CD-21b |
| LOW-001 `get-ready-work.sh` field | Fixed | `issue_type // .type`, case-folded; a reply with neither field lists nothing with a warning; two tests |
| LOW-002 `_gp_is_unattended` | Fixed | `LOA_UNATTENDED=1` first, writer absent → interactive, any first line other than `interactive` → unattended, `--prd` passed; GPC-13b/14 |
| LOW-003 `san1` | Fixed | C1 and U+2028/2029 pattern from the writer, format-character ranges, python3 `Cf` pass; CD-17d |
| LOW-004 nested quantifier | Fixed | single-whitespace span steps plus a whitespace-collapsed copy of the scrubbed command; the 20,000-space timing bats passes |
| LOW-005 `create-sprint-task.sh` envelope | Fixed | `{issues}` shape read; no labels key → `br label list`, a failure there refuses; four tests |
| LOW-006 context globs | Fixed | both globs removed; Phase 0 reads the one resolved snapshot; CD-28/28b |
| LOW-007 markers, pending glob, exemption | Fixed | marker removed on every `research-end` path, a per-map `.dispatched` ledger for the cap, pending files from `$ROOT`, exemption limited to this map's dispatched reports; CD-24b/24c |
| LOW-008 researcher Read/WebFetch | Carried | bead bd-akas |

---

## Findings (open)

### [LOW-008] The researcher holds unrestricted Read and WebFetch (carried)

Unchanged from round 1; bead bd-akas. No per-agent path or domain restriction exists in the harness; the repo holds no secrets by rule, the agent runs only in an interactive chart session, and its output is text the session reviews.

---

## Observations (no change required)

1. **Heredoc prose trips the fence.** The carrier scrub covers commit messages and `echo`, not heredoc bodies, so a heredoc that writes documentation naming the alias rule or a spike merge is blocked (this report's CHANGELOG bullets had to go through the Edit tool). A fence false positive with a working path around it; a follow-up could scrub heredoc bodies the way it scrubs quoted strings.
2. **Hook cost.** Across Sprint 2 the hook's per-row cost over the 179-row corpus rose about 30 % (85 to 110 ms per row at load 26; the recorded baseline is 55 ms per row on a quiet machine). The cycle-125 timing test fails under heavy load and passes at load 10 (589/589 run); on a quiet runner the current cost stays within the 1.5× budget. Worth watching if SP-1 grows again.
3. **`resolve` now requires `--answer-ref`.** A behaviour change the skill text already assumed (step 5 passes `session:<id>#turn-<n>`); a ticket is resolved only with the operator, and the hand-off refuses rows without the reference. Recorded here so the change is visible.

---

## Sources and sinks walked (round 2 delta)

- Probe argv → scrubbed `env -i` → detached worktree with `core.hooksPath=/dev/null` for the add → `snapshot()` before/after (refs, HEAD, config, hooks, status) + `newer_files()` → verdict. Remaining outside: anonymous network egress, absolute paths outside the work tree (stated in the header).
- Ticket text → `san1` (C0, C1, line separators, format characters) → `clean_field` (URL ban) → writer (`san1` again, validator URL ban) → `dw list` → `fence_append` (L6 or labelled fallback, temp file, appended on success) → PII scan → snapshot.
- Shell commands → SP-1 on `_sp1_lines` (whitespace-collapsed, carrier-scrubbed): verbs, checkout copies, restore, branch moves, push refspecs, fetch+FETCH_HEAD, alias definitions, `gh pr create`, `gh api` pulls; FR-1.1 unlock with the pushed check.
- Context → `need_interactive` at every write entry; `_gp_is_unattended` fail-closed; `chart-guard.sh` unchanged.

## Refuted dissent claims (unchanged from round 1)

DISS-001 / DISS-C-005 "fields reach the ledger raw" (the writer sanitises; the snapshot fence was the gap, now closed); the companion's doubt about the `br create` flags.

## Severity Tally (Phase 2.5)

| Severity | Count | Items |
|---|---|---|
| CRITICAL | 0 | |
| HIGH | 0 | HIGH-001 fixed in 8f7932b2 |
| MEDIUM | 0 | MEDIUM-001 … MEDIUM-006 fixed in 8f7932b2 |
| LOW | 1 | LOW-008 carried (bd-akas); LOW-001 … LOW-007 fixed in 8f7932b2 |

## Verdict

**APPROVED - LET'S FUCKING GO.** Sprint 253 may be marked COMPLETED.

## Rejected dissent payloads

None. The envelope lists zero rejected payloads and no sidecar files.

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":1},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-253","ts":"2026-10-13T06:15:20Z"} -->
