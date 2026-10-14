# Post-Compact Recovery & Hooks Reference

> Extracted from CLAUDE.loa.md for token efficiency. See: `.claude/loa/CLAUDE.loa.md` for inline summary.

## Post-Compact Recovery Hooks (v1.28.0)

Loa provides automatic context recovery after compaction via Claude Code hooks.

### How It Works

1. **PreCompact Hook**: Saves current state to `.run/compact-pending`
2. **UserPromptSubmit Hook**: Detects marker, injects recovery reminder
3. **One-shot delivery**: Reminder appears once, marker is deleted

### Automatic Recovery

When compaction is detected, you will see a recovery reminder instructing you to:
1. Re-read this file (CLAUDE.md) for conventions
2. Check `.run/sprint-plan-state.json` - resume if `state=RUNNING`
3. Check `.run/bridge-state.json` - resume if `state=ITERATING` or `state=FINALIZING`
4. Check `.run/simstim-state.json` - resume from last phase
5. Review `grimoires/loa/NOTES.md` for learnings

### Installation

Hooks are in `.claude/hooks/`. To enable, merge `settings.hooks.json` into `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreCompact": [{"matcher": "", "hooks": [{"type": "command", "command": ".claude/hooks/pre-compact-marker.sh"}]}],
    "UserPromptSubmit": [{"matcher": "", "hooks": [{"type": "command", "command": ".claude/hooks/post-compact-reminder.sh"}]}]
  }
}
```

See `.claude/hooks/README.md` for full documentation.

## Session-Limit Capture & Resume (cycle-117 item A)

Recovery after the primary Claude session/usage cap — the analogue of
Post-Compact Recovery for a quota reset rather than a compaction event.

### How It Works

1. **Capture** (`.claude/scripts/session-limit-capture.sh --raw '<error text>'`):
   When a session-limit / usage-cap error string surfaces in a tool or subagent
   result, the agent runs this CLI with the full error text (see the
   "Session-Limit Recovery" trigger in `CLAUDE.loa.md`). It parses the reset
   time (TZ-aware, via `session-limit-lib.sh`) and writes
   `.run/session-limit-state.json` with `hit_at`, `reset_at` (ISO + offset),
   `reset_at_epoch` (plain unix epoch), and an **embedded scalar snapshot** of
   the live sprint-plan / bridge / simstim state (never bare path references, so
   the resume context survives even if those files are later mutated/deleted).

2. **UserPromptSubmit** (`.claude/hooks/post-session-limit-reminder.sh`):
   A **conditional** one-shot (distinct from post-compact-reminder's
   unconditional one-shot) — it stays SILENT on every prompt while
   `now < reset_at_epoch`, leaving the marker in place to re-check next prompt.
   Once `now >= reset_at_epoch` it injects a single resume reminder (sprint id +
   state, allowlist-validated + sanitized) and deletes the marker. Fail-open
   silent on an absent/malformed marker.

### Parser scope (`session-limit-lib.sh`)

GNU-`date`-only today (bats CI is ubuntu-only). On macOS the shape is still
DETECTED but the reset math returns non-zero (capture no-ops) — see the
`loa:shortcut` marker in the lib for the BSD/perl-tier upgrade trigger.

### Diagnostic probe (`.claude/hooks/safety/stop-input-probe.sh`)

Ships **UNREGISTERED**, default-OFF (gated by `LOA_STOP_INPUT_PROBE=1`). It
appends the raw Stop-hook input to `.run/stop-input-probe.jsonl` to empirically
answer whether Stop input ever carries the session-limit error text (static
investigation found no such field). Merge it into `settings.local.json` for one
cap-hitting session, record the result on the PR, then remove — do NOT wire it
into `settings.hooks.json`.

## Safety Hooks (v1.37.0)

### PreToolUse:Bash — Destructive Command Blocking

Blocks `rm -rf`, `git push --force`, `git reset --hard`, `git clean -f` with actionable alternatives.

**Script**: `.claude/hooks/safety/block-destructive-bash.sh`

### PreToolUse:Bash — Team Role Guard (v1.39.0)

Enforces lead-only constraints when `LOA_TEAM_MEMBER` is set (Agent Teams mode). Blocks `br` commands, `.run/*.json` overwrites, and `git commit/push` for teammates. Complete no-op when `LOA_TEAM_MEMBER` is unset. Fail-open design.

**Script**: `.claude/hooks/safety/team-role-guard.sh`

### PreToolUse:Write/Edit — Team Role Guard (v1.39.0)

Extends defense-in-depth to the Write and Edit tools. When `LOA_TEAM_MEMBER` is set, blocks writes to the System Zone (`.claude/`) and top-level state files (`.run/*.json`). Allows writes to teammate-owned paths (`.run/bugs/*/`, `grimoires/`, `app/`). Complete no-op when `LOA_TEAM_MEMBER` is unset. Fail-open design.

**Script**: `.claude/hooks/safety/team-role-guard-write.sh`

### PreToolUse:Skill — Team Skill Guard (v1.39.0)

Enforces the Skill Invocation Matrix mechanically when `LOA_TEAM_MEMBER` is set (Agent Teams mode). Blocks lead-only skill invocations (`/plan-and-analyze`, `/architect`, `/sprint-plan`, `/simstim`, `/run-bridge`, etc.) for teammates. Uses blocklist-based matching against `tool_input.skill`. Complete no-op when `LOA_TEAM_MEMBER` is unset. Fail-open design.

**Script**: `.claude/hooks/safety/team-skill-guard.sh`

### Stop — Run Mode Guard

Detects active `/run`, `/run-bridge`, or `/simstim` execution and injects context reminder before stopping.

cycle-117 item C: at the "no active runs" fallthrough it also fires a best-effort, operator-configurable push (`notifications.push_command` in `.loa.config.yaml`) exactly once per terminal gate (sprint JACKED_OUT/READY_FOR_HITL/HALTED, bridge JACKED_OUT/HALTED, simstim COMPLETED/AWAITING_HITL/HALTED) via `push-notify-lib.sh` — a side channel that never alters the hook's exit code or stdout contract.

cycle-117 item A: when an **unexpired** `.run/session-limit-state.json` is present (a session cap whose reset time has not yet passed), the background-task soft-block is swapped for a loud stderr advisory and falls through to the remaining checks — a quota-hung teammate cannot respond to TaskStop and would otherwise deadlock every Stop. Freshness (`now < reset_at_epoch`) is computed inside the guard's existing single jq call (jq builtin `now`, no extra spawn). An expired/absent/malformed marker keeps today's block (fail-open to the deadlock guard).

**Script**: `.claude/hooks/safety/run-mode-stop-guard.sh`

### PostToolUse:Bash — Audit Logger

Logs mutating commands (git, npm, rm, mv, etc.) to `.run/audit.jsonl` in JSONL format.

**Script**: `.claude/hooks/audit/mutation-logger.sh`

### PostToolUse:Write/Edit — Write Audit Logger (v1.39.0)

Logs Write and Edit tool file modifications to `.run/audit.jsonl` in JSONL format. Captures file path, tool name, team identity, and timestamp. Does NOT log file content (privacy, size). Complements `mutation-logger.sh` to ensure all file modifications — whether via Bash, Write, or Edit — appear in the audit trail.

**Script**: `.claude/hooks/audit/write-mutation-logger.sh`

## Deny Rules

Template of recommended file access deny rules for credential protection. Blocks agent access to `~/.ssh/`, `~/.aws/`, `~/.kube/`, `~/.gnupg/`, and credential stores.

**Template**: `.claude/hooks/settings.deny.json`
**Installer**: `.claude/scripts/install-deny-rules.sh`

## Known Scope Boundaries (cycle-114 FR-7)

The safety layer is a **fence against routine destructive mistakes**, not a
hardened security boundary. It defends two surfaces:

- **Filesystem destruction** — `block-destructive-bash.sh` blocks `rm -rf` on
  catastrophic paths, force-push, hard-reset, `DROP`/`TRUNCATE`, etc.
- **Credential reads** — `settings.deny.json` blocks access to `~/.ssh/`,
  `~/.aws/`, `~/.kube/`, `~/.gnupg/`, and credential stores.

It does **NOT** guard:

- **Network egress / data exfiltration.** There is no monitoring or restriction
  of outbound data — `curl`/`wget` POSTs, `scp`, cloud uploads (S3, gcs), or
  bulk transfers of repository contents are not inspected. Preventing
  exfiltration is the **operator's responsibility**, via network policy /
  firewall / egress proxy external to Claude Code (Claude Code's own auto-mode
  classifier provides some bulk-exfil detection, but Loa does not add a guard).
- **Documented bypass classes.** Newline statement separators, subshell
  wrapping (`bash -c`, `$(...)`), `eval`/base64 decode, SQL comments containing
  `WHERE`, python scripts loaded from disk, and `jq` absent from PATH all bypass
  `block-destructive-bash.sh` by design — see cycle-111 SDD §11 for the full
  accepted-bypass list and rationale. The NOTES.md size gate (cycle-124 FR-10)
  inherits the same classes: `notes-size-guard.sh` sees Write/Edit/MultiEdit
  payloads and `FR-NOTES` sees `>>` appends; `python -c`, `tee`, heredocs into
  the file and other Bash writers are an accepted bypass — the writer-side gate
  is `update-notes-learnings.sh`, and `notes-guard.sh rotate` (mv) is never
  intercepted, so the escape hatch cannot deadlock.

Treat the safety hooks as defense-in-depth against accidental damage by
autonomous agents — not as a sandbox.

## All Hook Registrations

Generated from `.claude/settings.json` (the registrations Claude Code runs) and `.claude/data/guard-origins.yaml` (status, knob, purpose) by `.claude/scripts/guard-yield.sh --hooks-table`; CI fails on drift (`--check`). The full guard register, with fence pattern ids, validator rules, gates and origins, is `grimoires/loa/guards.md`.

<!-- guard-register:begin -->
<!-- Generated by .claude/scripts/guard-yield.sh --hooks-table from .claude/settings.json and .claude/data/guard-origins.yaml; do not edit by hand. Full register: grimoires/loa/guards.md -->
| Event | Matcher | Script | Status | Knob | Purpose |
|-------|---------|--------|--------|------|---------|
| Setup | (all) | `scripts/upgrade-health-check.sh` | active | none | Post-install and post-upgrade health check of the framework mount |
| SessionStart | (all) | `scripts/check-updates.sh` | active | update_check.enabled | Notify when a newer framework release exists (cached; LOA_DISABLE_UPDATE_CHECK=1 silences it) |
| SessionStart | (all) | `session-start/loa-l6-surface-handoffs.sh` | active | structured_handoff.enabled | Surface unread L6 structured handoffs inside a data fence |
| SessionStart | (all) | `session-start/loa-l7-surface-soul.sh` | active | soul_identity_doc.enabled | Surface the L7 soul identity document inside a data fence |
| SessionStart | (all) | `session-start/loa-run-mode-session-title.sh` | active | none | Set the session title from the run-mode state for recovery |
| SessionStart | (all) | `loa-kf-surface.sh` | active | known_failures.surface_at_session_start | Print the known-failures symptom table at session start (default off) |
| SessionStart | (all) | `hook-guard.sh session-start/loa-decisions-surface.sh` | active | decisions.surface_at_session_start | Default off: up to ten proposed or open decision rows inside the L6 data fence, plus a stale unattended-marker notice |
| SessionStart | (all) | `hook-guard.sh session-start/loa-run-state-surface.sh` | active | none | One Run line when a run is HALTED or INTERRUPTED or RUNNING idle 12h+, plus a session-limit-reset line; silent otherwise |
| SessionStart | (all) | `hook-guard.sh session-start/loa-context-class.sh` | active | LOA_CONTEXT_CLASS | Write .run/context-class (long by default, standard for a 200K-or-less model) for the context-discipline thresholds; silent, never blocks |
| PreCompact | (all) | `pre-compact-marker.sh` | active | none | Save a marker before compaction |
| UserPromptSubmit | (all) | `post-compact-reminder.sh` | active | none | Inject the recovery reminder after compaction |
| UserPromptSubmit | (all) | `post-session-limit-reminder.sh` | active | none | Inject the resume reminder after a session cap resets |
| PreToolUse | Skill(plan-and-analyze.*) | `scripts/cleanup-context.sh` | active | none | Archive the previous cycle's discovery context before /plan-and-analyze |
| PreToolUse | Bash | `hook-guard.sh safety/block-destructive-bash.sh` | active | none | Block destructive commands and System-Zone shell writes (the fence; per-pattern rows are fence:<id>) |
| PreToolUse | Bash | `hook-guard.sh safety/team-role-guard.sh` | dormant | LOA_TEAM_MEMBER | Enforce lead-only operations in Agent Teams (armed only when LOA_TEAM_MEMBER is set) |
| PreToolUse | Write\|Edit\|MultiEdit\|NotebookEdit | `hook-guard.sh safety/team-role-guard-write.sh` | dormant | LOA_TEAM_MEMBER | Block teammate writes to the System Zone, state files and append-only files (armed only when LOA_TEAM_MEMBER is set) |
| PreToolUse | Write\|Edit\|MultiEdit\|NotebookEdit | `hook-guard.sh safety/spiral-dispatch-guard.sh` | active | none | Block inline implementation writes under /spiraling until spiral-harness.sh is dispatched |
| PreToolUse | Write\|Edit\|MultiEdit\|NotebookEdit | `hook-guard.sh safety/zone-write-guard.sh` | active | LOA_ZONE_GUARD_DISABLE | Block project-work writes into the framework zone (bounded marker .run/zone-guard-authorization.json for framework development) |
| PreToolUse | Write\|Edit\|MultiEdit\|NotebookEdit | `hook-guard.sh compliance/implement-gate.sh` | active | implement_gate.mode | implement_gate.mode ask (default: ask + row) \| telemetry (allow + row) \| deny (refuse an unsanctioned App Zone write while the run position is known, else ask); sanctions: derived RUNNING cache, fresh .run/implement-active.json, LOA_IMPLEMENT_GATE_OVERRIDE; trust-input writes ask in every mode; a fence only under deny |
| PreToolUse | Write\|Edit\|MultiEdit\|NotebookEdit | `hook-guard.sh safety/notes-size-guard.sh` | active | none | Refuse a write that would grow grimoires/loa/NOTES.md at or over 200 KiB (shrinking edits and notes-guard.sh rotate pass) |
| PreToolUse | Write\|Edit\|MultiEdit\|NotebookEdit | `hook-guard.sh safety/adversarial-review-gate.sh` | active | flatline_protocol.code_review.enabled | Block a COMPLETED marker write when cross-model dissent is enabled and its artefact is missing or invalid (the floor row is gate:adversarial-review-gate) |
| PreToolUse | Skill | `hook-guard.sh safety/team-skill-guard.sh` | dormant | LOA_TEAM_MEMBER | Block lead-only skill invocations for teammates (armed only when LOA_TEAM_MEMBER is set) |
| PreToolUse | Skill | `hook-guard.sh safety/spiral-skill-sentinel.sh` | active | none | Write the spiral sentinel when /spiraling is invoked so the dispatch guard arms itself |
| PostToolUse | Bash | `audit/mutation-logger.sh` | telemetry | none | Log mutating shell commands to .run/audit.jsonl |
| PostToolUse | Write | `audit/write-mutation-logger.sh` | telemetry | none | Log Write and Edit tool file modifications to .run/audit.jsonl |
| PostToolUse | Edit | `audit/write-mutation-logger.sh` | telemetry | none | Log Write and Edit tool file modifications to .run/audit.jsonl |
| PostToolUse | Write\|Edit\|NotebookEdit | `quality/karpathy-surgical-diff-check.sh` | telemetry | karpathy_principles.surgical_diff_warning | Warn-only: track per-task diff size against diff_lines_per_task; never blocks |
| Stop | (all) | `safety/run-mode-stop-guard.sh` | active | none | Soft-block a Stop while an autonomous run is active |
| Stop | (all) | `hygiene/settings-cleanup.sh` | active | none | Prune one-off permission entries from settings.local.json at session end |
| PermissionRequest | (all) | `scripts/permission-audit.sh` | telemetry | none | Log permission requests for prompt analysis (async) |
<!-- guard-register:end -->

Not registered by default: `safety/stop-input-probe.sh` (Stop, DIAGNOSTIC) is gated by `LOA_STOP_INPUT_PROBE=1` and dumps raw Stop input to `.run/stop-input-probe.jsonl` for one cap-hitting session; it is never in `settings.hooks.json`.

## Decision surfaces (cycle-128)

Hooks, fence rules and gates added for the decision ledger, `/chart` and spikes (FR-3, FR-4, FR-5, FR-8). Each is a fence, not a boundary; the accepted bypasses are listed per row.

| Surface | Where | What it does | Config / override | Accepted bypasses | Tests |
|---------|-------|--------------|-------------------|-------------------|-------|
| SessionStart decisions surface | `.claude/hooks/session-start/loa-decisions-surface.sh` (through `hook-guard.sh`) | Prints up to ten `proposed`, then `open`, rows of `grimoires/loa/decisions.yaml` (id, status, summary) so the operator sees what awaits `/decisions confirm`; adds one notice when `.run/unattended.json` belongs to another session or is older than the TTL. Exits 0 on every path. | `decisions.surface_at_session_start` (default `false`); `decisions.unattended_marker_ttl_hours` (default 24) | Silent without Mike Farah yq v4 or without the L6 sanitizer. Summaries are agent-written and untrusted: control characters (C0, C1, U+2028/9) are stripped, angle brackets replaced, each capped at 100 characters, and the block wrapped by `sanitize_for_session_start L6 … --max-chars 2000`. | `tests/unit/loa-decisions-surface.bats` |
| ICE spike rule | `.claude/scripts/run-mode-ice.sh` | `is-spike <branch>` (true for `spike/<x>` and remote or full refs ending in one). `merge [source]` stays blocked except on a spike head, where only the default branch (`main`/`master`) may come in, with `--ff` so `merge.ff=only` cannot refuse a diverged spike; a conflict returns git's exit code and names the way out. A spike source is refused. `pr-create` refuses a spike head. | none | Applies inside run mode only; outside it, fence rule SP-1 is the control. | `tests/unit/run-mode-ice.bats` |
| Fence rule SP-1 | `.claude/hooks/safety/block-destructive-bash.sh` | Spike content never enters another branch: merge, rebase, pull, cherry-pick, reset, read-tree and update-ref with a spike ref operand; checkout or restore of a path from a spike; branch force/move/copy with a spike ref; push refspecs carrying a spike ref to another branch, or HEAD to another branch while on a spike; a FETCH_HEAD merge after fetching a spike on the same line; git alias definitions; and PRs from a spike head (`gh pr create`, `gh api` on a pulls path). Pushes, checkouts and default-branch merges into a spike stay allowed. Judged on the carrier-scrubbed, whitespace-collapsed command. | none | Listed in the rule's header comment: `git show spike/x:path >` a file, `git diff spike/x` piped to `git apply`, `git switch -c new spike/x`, `git worktree add -b new <dir> spike/x`, a spike branched under a new name then merged, a fetch and a FETCH_HEAD merge in separate commands, an alias defined outside the agent's Bash calls, `gh api --input <file>`, and a spike spelled as a SHA. The usual fence classes also apply (subshells, `eval`, newlines). Prose that names a spike merge inside a heredoc body now allows when the heredoc's consumer is non-executing (cycle-129 FR-6 classifier, corpus B79–B83); a body line that *begins* with the verb is still scanned as a command (D140). | `tests/unit/block-destructive-bash.bats`, corpus `tests/fixtures/fence-corpus/` |
| FR-1.1 decided-spike unlock | `.claude/hooks/safety/block-destructive-bash.sh` (`_fr11_spike_decided`) | `git branch -D spike/<slug>` passes only when `refs/remotes/origin/spike/<slug>` exists with the local branch an ancestor of it, and the MAIN working tree's ledger holds a `decided` row with a transition to decided by `operator:*` and source `grimoires/loa/spikes/<slug>.md`. Offline (git, yq v4, jq); any failed lookup keeps the block. | none | Trusts the tracked ledger as operator-owned state: a forged operator row lets an agent delete a local branch that is already pushed, and nothing else. The remote-tracking ref is only as fresh as the last fetch or push. | `tests/unit/block-destructive-bash.bats` |
| `/chart` interactive-only gate | `.claude/scripts/chart-guard.sh`, the first step of the `charting-decisions` skill | Refuses (exit 1) when `dec-write-lib.sh context` says unattended (a fresh unattended marker, a RUNNING run state, `LOA_UNATTENDED=1`, `LOA_FLATLINE_MODE=autonomous`, or an autonomous PRD Status line) or when `br` is missing; a context it cannot read counts as unattended. `--close-consumed` allows the one unattended operation. | none | A skill step, not a hook: a session that skips the step is caught by `chart-ticket.sh`, whose every write subcommand repeats the context check (`--dry-run` and `close --consumed-by` exempt). An unattended session with none of the signals reads as interactive. | `tests/unit/charting-decisions.bats` |
| FR-8 `disable-model-invocation` lint | `tests/unit/user-invoked-commands.bats` over `.claude/data/user-invoked-commands.txt` | Every listed command file carries `disable-model-invocation: true` and every flagged file is listed; no other command or skill body has an operative line naming a listed command (the clause before the verb is judged; "tell the user to run" is advice); no SKILL.md `allowed-tools` grants `dec-write-lib.sh confirm`, `supersede` or `context --clear`. The harness refusal itself is checked live by `tests/unit/user-invoked-harness.bats`. | `LOA_HARNESS_CHECK=0` skips the live harness call (a skip, never a pass) | A text lint: an indirect reference it cannot parse as operative passes, and the harness refusal is the control. The live check skips without the `claude` CLI, `jq` or `timeout`, and on a CLI error or an inconclusive control. | `tests/unit/user-invoked-commands.bats`, `tests/unit/user-invoked-harness.bats` |

## Compliance Hooks — Agent Hook Pattern (v1.40.0)

### When to Use Agent vs Shell Hooks

| Criterion | Shell Hook | Compliance Hook |
|-----------|-----------|----------------|
| Detection | Pattern matching (regex) | State file reading + integrity checks |
| Failure mode | Fail-open (allow) | Fail-ask (prompt user) |
| Performance | <10ms | <100ms (file I/O) |
| Scope | Syntax-level (command text) | Semantic-level (active skill context) |

### implement-gate.sh (FR-7; modes since cycle-129 FR-4(a))

**Type**: Command hook. It is a **fence only under `implement_gate.mode: deny`**; under `ask` (the default) and `telemetry` it never blocks. **Wired by default** in `.claude/settings.json` and `.claude/hooks/settings.hooks.json` through `hook-guard.sh`, matcher `Write|Edit|MultiEdit|NotebookEdit`.

**Output** (Claude Code PreToolUse contract): allow is a silent exit 0 with empty stdout; ask and deny are exit 0 with `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask"|"deny","permissionDecisionReason":"…"}}`. A top-level `decision` field is never emitted.

**Modes** (`implement_gate.mode` in `.loa.config.yaml`; `/loa` prints the effective mode through `implement-gate.sh --effective-mode`, so the status line and the hook share one parser). The position is the derived `.run/sprint-plan-state.json` (`run-checkpoint.sh derive`); it is *known* when the cache parses and its `derived_at` is within `run_mode.stale_hours` (12 h).

| Mode | Unsanctioned App-Zone write | Audit row |
|------|-----------------------------|-----------|
| `ask` (default; also unset or an unknown value) | ask | `ask/ask` |
| `telemetry` | allow silently | `telemetry/outside_run` |
| `deny` | deny while the position is known; ask when it is unknown (missing, stale, never derived or unparseable) | `deny/deny`, `ask/unknown_position` |

`implement_gate.claims: authoritative` is the tighten-only modifier: a model-authored non-implementation claim in `tool_input.active_skill` asks (or is denied where `deny` would deny anyway); an implementation claim never allows by itself; an absent claim falls through. The deny reason ends with the two remedies (run the write inside `/implement` or `/bug`, or set `implement_gate.mode: ask`).

**Sanctions** (checked in the order run, marker, override; each allows with its own row): a derived RUNNING cache with a fresh `derived_at` (`allow/sanctioned_run`); a fresh `.run/implement-active.json` marker, written by `run-checkpoint.sh mark` at the start of `implementing-tasks` and `bug-triaging` and removed by `unmark` at their end (`allow/sanctioned_marker`; a stale marker logs `stale_marker` and does not sanction); `LOA_IMPLEMENT_GATE_OVERRIDE=1` (`allow/override`, logged only when nothing else sanctioned). The legacy state files below keep sanctioning as before. This repository stays on `ask` until the cycle's last commit (DEC-0168).

**Path rule**: the path is `tool_input.file_path`, or `tool_input.notebook_path` for NotebookEdit. A relative path resolves from the payload's `cwd`. The root is `PROJECT_ROOT`, else `CLAUDE_PROJECT_DIR`, else the hook's own location (`<root>/.claude/hooks/compliance/`), never the process cwd, which follows Claude's `cd`. Both sides are canonicalised. The path counts as App Zone (`src/`, `lib/`, `app/`, at any depth under the root) when its physical form (symlinks followed) or its logical form (symlinks kept) matches, compared lowercased.

**Legacy heuristic** (still a sanction in every mode): an App Zone write is allowed when one state file shows an active run that is at most 24 h old. The former `implement_gate.mode: authoritative` value is read as `ask` plus `claims: authoritative`.

| State file | Allows when | Freshness field |
|------------|-------------|-----------------|
| `.run/sprint-plan-state.json` | `state == RUNNING` and a `plan_id` | `.timestamps.last_activity` (over 24 h asks) |
| `.run/simstim-state.json` | `phase == implementation` | `.timestamps.last_activity` (absent, unparsable or over 24 h asks) |
| `.run/state.json` | `state == RUNNING` | `.timestamps.last_activity`, else `.updated_at` (absent, unparsable or over 24 h asks) |

**Decision matrix**:

| Write | Decision |
|-------|----------|
| Payload unparsable, `jq` missing, or a path that cannot be canonicalised | `ask` (fail-ask) |
| A trust input: `.run/state.json`, `.run/sprint-plan-state.json`, `.run/simstim-state.json`, `.run/implement-active.json`, `.run/platform-features.json`, `.run/audit.jsonl`, `.loa.config.yaml` | `ask` in every mode + `compliance.state_write` row (`decision: trust_input`) |
| Any other non-App-Zone path, or a payload without a path | `allow` |
| App Zone, `claims: authoritative`, non-implementation claim | `ask` (deny under `deny` with a known position) + `compliance.mode.model_signal` row |
| App Zone, sanctioned (run, marker, override, or a fresh legacy state file) | `allow` + the sanction's row |
| App Zone, unsanctioned | per the mode table above |

**Audit events** (plain rows in `.run/audit.jsonl`, not the signed `audit_emit` chain; model-authored values cut to 256 bytes and written with `jq -a`): one row per decision carrying `hook: implement-gate`, `action` (`allow`, `ask`, `telemetry`, `deny`), `decision` and `mode`; `compliance.state_write` for trust inputs; `compliance.mode.model_signal` per authoritative claim; `replay: true` under `LOA_AUDIT_REPLAY=1`. The guard register (`guard-yield.sh`) counts the ask and telemetry rows as the gate's yield. Paths and claims shown on stderr have control and format characters stripped.

**Accepted gaps**: writes through the Bash tool are not seen (the C-PROC-001 fence gap). The sanctions trust `.run/` files a Bash command can write (bead bd-taee); a marker and a trailer forged together with the right sprint id pass `derive`. A direct `/implement` without `/run` leaves no run cache, so its writes rely on the marker. `deny` reads the sprint-plan cache only: a `/run sprint-N` run that leaves only `.run/state.json` is an unknown position under `deny` and asks.

**Tests**: `tests/unit/implement-gate.bats` (33 cases: the mode × claims × write class × sanction × cache-state matrix), `tests/unit/compliance-hook.bats`, `tests/unit/run-checkpoint-derive.bats`.

## block-destructive-bash.sh — Full Pattern Set & Posture (moved from CLAUDE.loa.md)

Blocks 12 destructive shapes: `rm -rf` (context-aware: blocks `/`, `~`, `$HOME`, `*`, `.`, `./.git`; allows `./build`, `./node_modules`, `/tmp/*`), `git push --force`/`-f`, `git reset --hard`, `git clean -f`, `git branch -D`/force-delete, `git stash drop`/`clear`, `git checkout -- <path>`, SQL `DROP {DATABASE,TABLE,SCHEMA}`, `TRUNCATE`, `DELETE FROM` no-WHERE (multi-statement loop), `kubectl delete namespace`, `kubectl delete --all`/`-A`. Audit-log trail to `.run/audit.jsonl` on every block with sanitized command + matched substring. Ported from Anthropic DCG public pattern set (cycle-111).

**cycle-122 additions**: `FR-MERGE-2` blocks manual `git tag` creation (listing/inspect/delete forms allowed; audited override `LOA_ALLOW_GIT_TAG=1`) — C-MERGE-002's mechanical twin. `FR-1.2b` blocks output-swallowed `git stash push/pop/apply` (`| tail`/`| head`, `|| true`, `2>/dev/null` — the issue #555 silent-data-loss shapes); remedy: `stash_with_guard`. `FR-SZ2` blocks direct Bash writes into `.claude/` (redirect/tee/copy/sed-i/rm shapes; `.claude/overrides/` + `.claude/cache/` excluded) unless the bounded framework-dev marker (`.run/zone-guard-authorization.json`, same validation as zone-write-guard) or `LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1` authorizes — closing the single-agent System-Zone Bash gap. Same accepted-bypass classes as their parents (fence, not boundary).

**cycle-128 additions**: `SP-1` keeps spike content out of every other branch, and FR-1.1 lets a fully pushed spike branch with an operator-decided ledger row be deleted. Both are described, with their accepted misses, under [Decision surfaces](#decision-surfaces-cycle-128).

A separate script-level runtime layer (`dcg-exec.sh` + `destructive-command-guard.sh`, pattern packs for core/database/docker/kubernetes) validates commands executed by Loa scripts with configurable BLOCK/WARN/ALLOW actions — invocation and pack details live in those scripts' headers.

**Defense-in-depth posture (cycle-111)**: this hook is a fence against routine destructive mistakes by autonomous agents — NOT a hardened security boundary. Documented accepted bypass classes (cycle-111 SDD §11): newline statement separators, subshell wrapping (`bash -c '...'` quoted-differently, `$(...)`), eval/base64 decode, SQL comments containing WHERE, python scripts loaded from disk, jq absent from PATH. ERE flavor: GNU/BSD-compatible extensions (`\s`, `\b`), NOT strict POSIX. Latency budget: p95 < 80ms across 100 invocations (bash startup + jq + 13 grep passes).

### Heredoc consumer classification (cycle-129 FR-6)

Knob: `destructive_command_guard.heredoc_classifier` (default `true`; `false` restores the pre-cycle scan and is the rollback key). The fence reads the knob from `.loa.config.yaml` only for commands that hold `<<`. The full grammar, both class lists and the default are stated in the block comment above `_bdb_hd_is_interp` in `block-destructive-bash.sh`. In summary:

- **Grammar.** The fence sees literal command text, with CRLF folded to LF. A control character, an unreadable header, more than one heredoc on a header, a non-word or variable delimiter, or a missing terminator makes the whole command scan in full.
- **Interpreter class.** The body is scanned exactly as before. This applies when the consumer or any pipe target is a shell, interpreter, argument-running wrapper or SQL runner, when the statement holds a substitution, group or continuation, or when an allowlisted form carries an unknown or exec-shaped flag. It also applies when the write target is executable content: a script extension, a shebang first line, `.claude/hooks/`, `.claude/settings*.json`, `.git/hooks/`, an rc or profile file, `/etc`, or a directory on `PATH`. Naming the target elsewhere on the same command outside a safe reader has the same effect.
- **Non-executing class.** This covers exact forms only: `cat`, `tee`, `printf` and `echo` to a plain file or stdout, `gh pr|issue comment -F -`, `gh pr create --body-file -`, `git commit -F -`, `br create|update` reading stdin, `jq`/`yq` without in-place, `grep`, print-only `sed -n`, `sort` and `wc`. Their bodies are scanned per segment. Segments that start with a fence verb are kept for the normal rules, and the rest are dropped. A substitution under an unquoted delimiter, an interpreter word or a variable command word sends the body back to a full scan.
- **Default.** A consumer on neither list, or a parse failure, scans in full. The #1245 quoted standalone `cat` scrub is the special case and is also the knob-off path.
- **Export.** Source the hook with `BDB_LIB_ONLY=1` and call `_bdb_heredoc_consumer_class <command>`, which prints `interpreter`, `nonexec` or `none`. `heredoc_nonexec <command>` exits 0 for a non-executing heredoc. Library mode applies only when the file is sourced. An executed hook ignores the variable.
- **Remaining gap.** A body written to a plain file by one command and executed by a later command is outside a per-command fence. The Write tool shares this limit.

**Accepted false positives (quote-blindness residue, cycle-120 C-D3)**: the inert-carrier scrub redacts a known data carrier's value (git commit `-m`, `br`/`bd -d`, `gh … create --body/--title`, `echo`/`printf`) only when the value holds **neither `$(` nor a backtick**. A lone `$` (dollar amount, `$ENV` mention, trailing bare `$`) is now permitted inside a redacted value — so `git commit -m "saved $5 by dropping find . -exec rm -rf {} +"` correctly ALLOWs. One residual false positive is **accepted by design**:

- **Case A — a `$(…)` command-substitution inside a carrier value** (e.g. a multi-line commit body wrapped in `$(cat <<'EOF' … find -exec rm -rf … EOF)`). The `$(` disqualifies the value from redaction (a regex fence cannot parse subshell contents without reintroducing the #1047 bypass), so a destructive *shape* mentioned inside that subshell body still trips FR-2 and blocks a genuinely safe commit. **Workaround**: paraphrase the destructive shape in the commit body (as the cycle-119 commits did — e.g. write "find-exec-rm" rather than the literal `find … -exec rm -rf`), or drop the `$(…)` wrapper. This is a preserved false positive, never a bypass: leaving `$(`/backtick values un-redacted is what keeps command-substitution smuggling (`git commit -m "$(rm -rf /)"`) caught. Backtick command-substitution itself remains the separately-tracked, uncaught pre-existing gap (bd-bdb-backtick-bypass).
