# Security & Quality Audit Report — Sprint 253 (cycle-128 Sprint 2), round 1

**Auditor:** Paranoid Cypherpunk Auditor (Claude Fable 5.1)
**Date:** 2026-10-13T05:35:31Z
**Scope:** commits cea919ca (implementation) and 30727c95 (review round r253-1) on feature/cycle-128-decision-surfaces: the `/chart` decision map (`charting-decisions` skill, `chart.md`, `chart-researcher` agent, `chart-ticket.sh`, `chart-guard.sh`, `chart-frontier.sh`, `chart-unblock-probe.sh`), the golden-path `charting` phase, the question-bead lints in `create-sprint-task.sh` / `get-ready-work.sh`, `validate-artifact.sh --type map|spike` and the sprint cross-check, the spike template, `run-mode-ice.sh` spike rules, fence SP-1 and the D-5.9 decided-spike unlock, `interview.unattended_prototype`, and the tests.
**Methodology:** Systematic 5-category review (Security, Architecture, Code Quality, DevOps; Blockchain not applicable); every changed script read in full; sources and sinks walked by hand (the scope scanner's repo-wide counts are not sprint-scoped: 68 sources / 3,053 sinks across the tree); fence patterns re-derived against the corpus; two-voice audit dissent (`adversarial-audit.json`: gpt-5.5-pro via codex-headless + claude-headless, 2/2 voices, consensus, 18 findings, 0 schema-rejected) triaged payload by payload against the code; review verdicts (engineer-feedback-r1.md, engineer-feedback.md) read for demotions.
**Review input:** review round 1 CHANGES_REQUIRED (1 HIGH, 1 MEDIUM, 8 LOW), round 2 APPROVED after 30727c95.

---

## Executive Summary

The sprint's trust model is right in its shape: the map is beads plus a doc the validator keeps execution-free, every write goes through one helper with a fixed order and idempotent re-runs, the researcher can no longer write, the unattended path into the map is one guarded operation, and the fence plus ICE refuse the merge and PR shapes the design names. The review round closed the two defects it found and pinned the rest with tests.

The audit finds the model's edges softer than its centre. One finding is HIGH: `chart-unblock-probe.sh` is the single arbitrary-execution path inside an otherwise fenced skill (`allowed-tools` lets the chart session run only named scripts, and this script runs whatever follows `--`), and its verdict is a porcelain diff of the main tree. The throwaway worktree shares the object database, refs, `.git/config`, `.git/hooks` and the session environment, so a probe can push, tag, move refs, install a hook, write the home directory or the global git config and still exit "unchanged". Six MEDIUMs follow the same pattern of a stated boundary with an unchecked side: the hand-off snapshot inlines the map doc and ledger rows without the untrusted-data fence the research reports get; SP-1 never looks at `git push` refspecs, so `spike/x:main` lands spike content on another branch in one command; a handful of one-line verbs (`reset`, `read-tree`, `update-ref`, `branch -f`, a `fetch` followed by a merge of `FETCH_HEAD`, alias definitions, `gh api …/pulls`) move spike content past the fence; the D-5.9 unlock says "a pushed branch" and never checks the remote; `awk -v` interprets backslash escapes in the lines `chart-ticket.sh` appends to the map doc, so `\n` in a ticket title becomes a new heading; and the write subcommands other than `close` never consult the context, leaving step 0 of the skill as prose. Eight LOWs are consistency and hygiene (field names, fail-open context fallback, Unicode controls, a nested quantifier, a bead-reply shape, declarative context globs, dispatch markers). Two companion claims did not survive verification and are recorded as refuted below (the ledger writer does sanitise every free-text field; the four `br create` flags exist).

Every item has a small, local fix; none changes the design. The round-2 fixes are dispatched with this report; approval follows when they land with tests.

**Verdict:** CHANGES REQUIRED

---

## Category Scores (Rubric-Based Assessment)

| Category | Score | Notes |
|---|---|---|
| Security | 6/10 | Right shape (single writer, read-only researcher, fail-closed guard, execution-free map doc); the probe's boundary, the snapshot fence, the push refspec gap and the write-subcommand context check are the open edges |
| Architecture | 9/10 | Write order and idempotency mechanical in one helper; frontier double-filtered; ICE and fence agree with the SDD; the researcher returns text and the session writes it |
| Code Quality | 8/10 | Consistent sanitisation and shape handling in most places; `awk -v` escape handling and the `.issue_type`-only filter are the exceptions |
| DevOps | 9/10 | 552 tests across eleven suites, fence corpus, stub br, fixture roots; no live-ledger or live-beads writes from tests; CI lints clean |
| Blockchain | n/a | |

---

## Findings

### [HIGH-001] `chart-unblock-probe.sh` is an arbitrary-execution path with a boundary that checks only the main tree's status

**Where:** `.claude/scripts/chart-unblock-probe.sh` (`(cd "$WT" && run_with_timeout "$TIMEOUT" "$@")`, the `before`/`after` porcelain comparison and the `.run`/`.beads` newer-than check); `.claude/skills/charting-decisions/SKILL.md` `allowed-tools` (`Bash(.claude/scripts/chart-unblock-probe.sh *)`); dissent DISS-002 and DISS-C-007, confirmed.
**Issue:** The skill's grant restricts Bash to named scripts; this one runs any argv. The detached worktree shares the repository's object database, refs, `.git/config`, `.git/hooks` and remotes, and the probe inherits the session environment (tokens, credential helpers, SSH agent). A probe can `git push` any branch, create tags, `update-ref`, set `core.hooksPath` or write a hook that runs on the operator's next git command, write `~/.gitconfig` or `~/.claude/settings.json`, or target the main checkout with `git -C`. None of that changes the main tree's porcelain status, so the helper prints `probe-exit` and exits 0. The header's "read-only probes" claim is not what the code enforces.
**Impact:** An injected research report or ticket body that talks the session into a probe gains execution the skill was designed to deny; the operator is present but sees only the argv.
**Required Fix:** (1) Run the probe under a scrubbed environment: `env -i PATH="$PATH" HOME="$SCRATCH/home" TMPDIR="$SCRATCH/tmp" LC_ALL=C TERM=dumb GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false` (no tokens, no `SSH_AUTH_SOCK`, no credential helper reachable). (2) Snapshot and compare, around the run: `git for-each-ref` (refs and tags), a hash of `.git/config`, a listing plus hashes of `.git/hooks/*`, and a whole-main-tree `find … -newer "$MARK"` (excluding the scratch dir and `.git/objects`), in addition to the porcelain diff. (3) In SKILL.md "Work the map" for `unblock`: the session prints the exact argv and asks the operator to confirm with AskUserQuestion before running the probe; never runs a probe the operator did not see. (4) The header states what remains outside the check (network egress other than git credentials, writes to other checkouts) rather than claiming read-only. Tests: a probe that tags, one that writes a hook, one that edits `.git/config`, one that writes `$HOME` (fails or lands in the scratch home), one that pushes to a local bare remote (refused without credentials or detected by the ref snapshot), and the existing clean case.

### [MEDIUM-001] The hand-off snapshot inlines the map doc and the ledger rows without the untrusted-data fence

**Where:** `.claude/scripts/chart-ticket.sh` `op_handoff` (the `sed` heading demotion, `dw list --source-epic … --format md`, the L6 subshell), `op_resolve`; dissent DISS-001, DISS-C-005 and DISS-C-006, confirmed in part.
**Issue:** The snapshot `grimoires/loa/context/chart-<slug>.md` is read by `/plan-and-analyze` as priority-1 context under the heading "these decisions are settled; confirm, do not re-ask". Only the research reports pass `sanitize_for_session_start L6`; the map doc is heading-demoted (including `#` lines inside fenced code) and the ledger rows are emitted as rendered markdown with no fence, and the snapshot itself is never PII-scanned. If the L6 subshell fails after partial output, that partial text precedes the fallback line. **Refuted part:** DISS-001/C-005 claim the fields `op_resolve` passes raw reach the ledger raw; `dec-write-lib.sh` applies `san1` (C0, C1, DEL stripped; newlines flattened) to decision, rationale, evidence, alternatives, consequences and answer-ref (lines 335, 366-373, 459, 466, 515-519), and `validate-artifact.sh --type decisions` fails any URL in free text (line 676). The remaining exposure is single-line instruction-like text in rows, re-surfaced as settled context.
**Impact:** A row or doc line written by an agent (every unattended row is agent-proposed) is rendered to the next planning session as trusted prose; the sanitiser that every other surface of this cycle applies is missing here.
**Required Fix:** In `op_handoff`: run `validate-artifact.sh --type map` and the PII scanner on `$DOC` first and refuse on failure; render the map doc and the `dw list` output inside the same L6 untrusted-data fence as the reports (or, where the sanitizer library is unavailable, control-strip them and label them as data); write each sanitizer's output to a temp file and append it only on success; PII-scan the assembled snapshot before the `mv`; demote headings only outside fenced code. `op_resolve`: apply `san1` and `no_url` to `--decision`, `--rationale`, `--evidence`, consequences and `--answer-ref` before calling the writer (defence in depth; the writer stays the authority) and validate each `--alternative-json` is an object with string members. Tests for the fence markers in the snapshot, the refusal on an invalid doc, and a `\n`-bearing field.

### [MEDIUM-002] SP-1 does not look at `git push` refspecs

**Where:** `.claude/hooks/safety/block-destructive-bash.sh` SP-1 block; dissent DISS-C-001, confirmed.
**Issue:** `git push -u origin spike/x` is allowed by design. `git push origin spike/x:main`, `git push origin spike/x:refs/heads/feature`, `git push origin +spike/x:main`, and `git push origin HEAD:main` while checked out on `spike/x` put the spike head on another remote branch in one command. The documented miss list does not include push refspecs.
**Impact:** The D-5.4 invariant (spike content never enters another branch) is bypassed by the one verb the skill is granted (`Bash(git push -u origin spike/*)` allows `spike/x:main` through the glob).
**Required Fix:** An SP-1 push rule: block `git push` when any argument contains `:` and either side matches the spike ref pattern; block `HEAD:` and bare `:<dst>` refspecs when the current branch (one offline `git rev-parse --abbrev-ref HEAD`) is `spike/*`; block `+`-prefixed and `--force`/`-f` refspecs to or from a spike ref. Keep `git push -u origin spike/x` and `git push origin spike/x` allowed. Corpus cases both ways; narrow the SKILL grant to `Bash(git push -u origin spike/*)` only if the glob can exclude a colon (otherwise rely on the fence and say so).

### [MEDIUM-003] One-line verbs beyond the SP-1 set move spike content

**Where:** fence SP-1 verb set `(merge|rebase|pull|cherry-pick)`, `_sp1_git` prefix; dissent DISS-C-002, confirmed in part.
**Issue:** Beyond the documented two-step misses: `git reset --soft|--hard spike/x`, `git read-tree -u -m spike/x`, `git branch -f feature spike/x`, `git update-ref refs/heads/feature spike/x` move a non-spike branch onto the spike head; `git branch -m|-M spike/x feature` renames the spike away from the `spike/` namespace; `git -c alias.m=merge m spike/x` and `git config alias.m merge` defeat the literal-verb match; `gh api repos/O/R/pulls -f head=spike/x` opens the PR `gh pr create` refuses; and the r253-1 narrowing lets the one-liner `git fetch origin spike/x && git merge FETCH_HEAD` through. (The `fetch`-then-`FETCH_HEAD` across two commands stays a documented miss.)
**Impact:** Same invariant, same single-command convenience as the shapes already blocked.
**Required Fix:** Extend SP-1: `reset`, `read-tree`, `update-ref` with a spike ref; `branch` with `-f|--force|-m|-M|-c|-C` and a spike ref among the operands; a `fetch` naming a spike ref in the same command as `merge|rebase|cherry-pick|reset` of `FETCH_HEAD`; `git -c alias.` anywhere in the git family and `git config … alias.` definitions (agents do not define aliases); `gh api` with a path containing `/pulls` and `head=` naming a spike ref. Update the header's allowed/blocked/miss lists; corpus cases for each.

### [MEDIUM-004] The D-5.9 unlock never checks that the spike branch is pushed

**Where:** `block-destructive-bash.sh` `_fr11_spike_decided` and its call site; dissent DISS-C-003, confirmed.
**Issue:** The rationale added in r253-1 says the consequence is "a local delete of a pushed spike branch", but the code checks only the ledger row. An unpushed spike, the one case where `-D` loses work, is exactly what the unlock permits.
**Impact:** FR-1.1's purpose (never lose unmerged work on a forced delete) is weakened for spike branches on the strength of a ledger row.
**Required Fix:** Before `continue`, require `git rev-parse -q --verify refs/remotes/origin/spike/$slug` and `git merge-base --is-ancestor refs/heads/spike/$slug refs/remotes/origin/spike/$slug`; any failure keeps the block. Read the ledger from the main working tree (`git rev-parse --git-common-dir` parent) so a linked worktree's checkout is not the authority. Bats: pushed-and-decided passes; decided-but-unpushed blocks; pushed-but-ahead-of-remote blocks.

### [MEDIUM-005] `awk -v` interprets backslash escapes in the lines appended to the map doc

**Where:** `chart-ticket.sh` `section_append` (`awk -v sec=… -v line="$2"`), called from `op_resolve` and `op_rule_out` (the latter with a bead title from `br show`); dissent DISS-C-004, confirmed.
**Issue:** `san1` flattens real newlines, but awk `-v` assignments process escape sequences, so the two characters `\n` in `--line`, `--name`, `--why` or a bead title become a real newline in `grimoires/loa/maps/<slug>.md`: an extra line, a new `## ` heading or a blockquote, which `op_handoff` then inlines.
**Impact:** Map-doc structure injection from ticket text; the validator's H2 allowlist is the control it defeats.
**Required Fix:** Pass the values through the environment (`LINE="$2" SEC="## $1" awk '… ENVIRON["LINE"] …'`) in `section_append`, `set_status` and `section_bullets`; add a test with `--line 'a\nb'` asserting one new line and the doc still validating.

### [MEDIUM-006] The write subcommands never consult the context

**Where:** `chart-ticket.sh` dispatcher: `epic`, `ticket`, `edge`, `claim`, `resolve`, `rule-out`, `handoff`, `research-begin`; dissent DISS-C-008, confirmed.
**Issue:** Only `close --reason` checks `dec-write-lib.sh context`; the skill's step 0 (`chart-guard.sh`) is prose. An unattended run, or a session that skips step 0 under injection, can chart, resolve and hand off a map, producing a priority-1 snapshot. Rows land `proposed` with `recorded_by: chart`, so `/decisions confirm` still stands between them and `decided`, which bounds the impact.
**Impact:** The interactive-only rule the design states (PRD D12, SDD D-4.3) is enforced at one of nine write entry points.
**Required Fix:** One `need_interactive` check at the top of every write subcommand except `close --consumed-by` and `--dry-run`, using the same `dec-write-lib.sh context --prd "${G}/prd.md"` call `op_close` makes (refuse on `unattended` or an unreadable context); `op_handoff` additionally refuses when any row on the map was written under an unattended marker (the writer records it). Tests under `LOA_UNATTENDED=1` for each refused subcommand and for `--dry-run` passing.

### [LOW-001] `get-ready-work.sh` filters on `.issue_type` only, fail-open

**Where:** `.claude/scripts/beads/get-ready-work.sh` (`map(select((.issue_type // "") != "question"))`); dissent DISS-C-010. `chart-frontier.sh` and `chart-ticket.sh` read `.issue_type // .type` in the same sprint. Fix: `((.issue_type // .type // "") | ascii_downcase) != "question"`; when no element carries either field, warn on stderr and treat the set as empty; stub test emitting `type`.

### [LOW-002] `_gp_is_unattended` fails open

**Where:** `.claude/scripts/golden-path.sh` `_gp_is_unattended`; dissent DISS-C-011. Any first line other than `unattended` (including an error line) reads as interactive, `--prd` is not passed, and `LOA_UNATTENDED=1` is honoured only when the writer printed nothing. `chart-guard.sh` fails closed on the same input. Fix: treat any first line other than `interactive` as unattended, pass `--prd`, honour `LOA_UNATTENDED=1` regardless.

### [LOW-003] `san1` in `chart-ticket.sh` strips C0 and DEL only

**Where:** `chart-ticket.sh` `san1`; dissent DISS-C-012. The comment claims C1; UTF-8 C1, bidi overrides and zero-width characters pass into titles, summaries and the doc (`dec-write-lib.sh`'s `san1` already handles C1 via `DEC_ULB_RE`). Fix: reuse the writer's pattern (C1 and the Unicode line/paragraph separators) and add a `python3 -I` pass for `Cf` where python3 exists, with the `tr` pass as the floor; correct the comment.

### [LOW-004] The r253-1 SP-1 span is a nested quantifier under bash `=~`

**Where:** `block-destructive-bash.sh` `([[:space:]]+["']?[^…]*)*`; `_match` uses `[[ =~ ]]` (glibc), not grep; dissent DISS-C-013. The SP-1 comment says "no nested quantifiers". Fix: make each iteration consume exactly one whitespace character, or collapse runs of whitespace on the scrubbed line before matching; a corpus timing case with a long run of spaces asserting sub-second completion.

### [LOW-005] `create-sprint-task.sh` map-epic check misses the `{"issues":[…]}` reply shape

**Where:** `.claude/scripts/beads/create-sprint-task.sh` (`EPIC_IS_MAP` jq); dissent DISS-C-014. Fix: reuse the `first_obj` shape logic and treat a reply with no `labels` key as `unknown` (refuse), not `no`.

### [LOW-006] Declarative `context_files` globs load every snapshot and every report

**Where:** `.claude/commands/plan-and-analyze.md` (`grimoires/loa/context/chart-*.md`, priority 1) and `.claude/commands/chart.md` (`grimoires/loa/research/chart-*.md`); dissent DISS-C-015. If the command framework preloads `context_files`, the multi-map rule and the L6 fence have no effect on what the model sees. Fix: drop both globs; read the single resolved snapshot in Phase 0 after `golden_resolve_open_map`; load reports only through the sanitizer.

### [LOW-007] Dispatch markers, the pending-file glob and the research exemption

**Where:** `chart-ticket.sh` `op_research_begin`, `op_research_end`, `map_rows`; dissent DISS-C-016. Markers are never removed (including after a failed `research-end`); `map_rows` reads pending files from `${SCRIPT_DIR}/../../grimoires/loa/a2a/` rather than `$ROOT`, so a `--root` fixture run merges the live tree's pending rows; the scope check exempts the whole `grimoires/loa/research/` directory rather than the one report path. Fix all three.

### [LOW-008] The researcher holds unrestricted Read and WebFetch (carried)

**Where:** `.claude/agents/chart-researcher.md`; dissent DISS-C-009. A page can direct it to read a repo file and fetch a URL carrying the content; the harness offers no per-agent path or domain restriction today. The repo holds no secrets by rule (zone-state), the agent runs only in an interactive chart session, and its output is text the session reviews. Carried as a follow-up bead (project-level `permissions.deny` for `Read(./.env*)` and a WebFetch host allowlist hook when the harness supports them).

---

## Sources and sinks walked

- Operator and agent text → `chart-ticket.sh` (`san1`, `no_url`) → `dec-write-lib.sh` (`san1` on every field, URL ban at validation) → ledger → `dw list` → snapshot (**no fence: MEDIUM-001**) → `/plan-and-analyze`.
- Ticket text → `br create` (sanitised) → `br show` title → `section_append` via `awk -v` (**escape processing: MEDIUM-005**) → map doc → validator (H2 allowlist) → snapshot.
- Fetched pages → `chart-researcher` (read-only after r253-1) → final message → session Write (path printed by `research-begin`) → `research-end` (status diff, `.run`/`.beads` mtimes, first line) → report → L6 sanitizer → snapshot. Declarative glob in `chart.md` loads reports raw (**LOW-006**).
- Probe argv → `chart-unblock-probe.sh` (**execution with a status-only boundary: HIGH-001**).
- Shell commands → fence SP-1 (`merge|rebase|pull|cherry-pick`, checkout copies, restore, `gh pr create`; **push refspecs and five verbs missing: MEDIUM-002/003**) and the D-5.9 unlock (**no pushed check: MEDIUM-004**); ICE `safe_merge` (exact allowlist, `--ff`, conflict message), `safe_pr_create` (spike head refused).
- Context detection → `dec-write-lib.sh context` → `chart-guard.sh` (fail closed), `op_close --reason` (fail closed), `_gp_is_unattended` (**fail open: LOW-002**), other write subcommands (**not consulted: MEDIUM-006**).
- Beads replies → `_br_json_array` / `first_obj` / `list_items` (array, object, `{issues}`), `get-ready-work.sh` (**`.issue_type` only: LOW-001**), `create-sprint-task.sh` (**envelope missed: LOW-005**).
- Tests → stub `br`, temp ledgers, fixture roots; no live writes (verified by grep and by the stub log assertions).

## Review demotions confirmed

The review's observation 1 (`Bash(br *)` grant) and observation 4 (SP-1 two-step misses) stand as design acceptances; the audit adds the one-line shapes above (MEDIUM-002, MEDIUM-003) because they are single commands the fence can see, which is the fence's own standard.

## Refuted dissent claims

- DISS-001 / DISS-C-005, "fields reach the ledger raw": the writer sanitises every free-text field and the validator bans URLs in free text (cited under MEDIUM-001). The snapshot fence is the real gap.
- DISS-C-005 (review round) and the companion's doubt about `--slug`, `--dry-run`, `--external-ref`: all exist in br 0.2.6.

## Severity Tally (Phase 2.5)

| Severity | Count | Items |
|---|---|---|
| CRITICAL | 0 | |
| HIGH | 1 | HIGH-001 |
| MEDIUM | 6 | MEDIUM-001 … MEDIUM-006 |
| LOW | 8 | LOW-001 … LOW-008 (LOW-008 carried as a bead) |

## Verdict

**CHANGES REQUIRED.** Round-2 fixes dispatched: implementer D takes HIGH-001, MEDIUM-001, MEDIUM-005, MEDIUM-006, LOW-001, LOW-002, LOW-003, LOW-005, LOW-006, LOW-007; implementer E takes MEDIUM-002, MEDIUM-003, MEDIUM-004, LOW-004 (fence, corpus and bats). LOW-008 becomes a follow-up bead. Approval follows the re-read of the fixes and a green run of the suites.

## Rejected dissent payloads

None. The envelope lists zero rejected payloads and no sidecar files.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":6,"low":8},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-253","ts":"2026-10-13T05:35:31Z"} -->
