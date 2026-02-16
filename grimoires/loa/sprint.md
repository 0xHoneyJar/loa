# Sprint Plan: TeamCreate Compatibility — Multi-Agent Orchestration for Loa

> Cycle: cycle-020
> PRD: `grimoires/loa/prd.md`
> SDD: `grimoires/loa/sdd.md`
> Source: [#337](https://github.com/0xHoneyJar/loa/issues/337)

## Overview

| Attribute | Value |
|-----------|-------|
| **Sprints** | 4 |
| **Tasks** | 21 |
| **Estimated complexity** | Medium |
| **Dependencies** | Sprint 3 builds on Sprint 2; Sprint 4 closes advisory gaps from Sprint 3's enforcement inventory |
| **Branch** | `feat/cycle-020-teamcreate-compat` |

## Sprint 1: Agent Teams Foundation

**Goal**: Establish schema, constraints, documentation, and audit trail support for Agent Teams compatibility. All changes gated on feature detection — zero regression for single-agent users.

---

### Task 1.1: Extend Constraint Schema with `condition` Field

**Description**: Add optional `condition` property to the constraint schema and `agent_teams` to the category enum.

**Files**:
- `.claude/schemas/constraints.schema.json`

**Changes**:
1. Add `"condition"` to `$defs.constraint.properties` with sub-properties: `when` (string, required), `override_text` (string, required), `override_rule_type` (enum, optional)
2. Add `"agent_teams"` to the `category` enum array
3. Add `"MAY"` to `rule_type` enum if not already present (needed for `override_rule_type`)

**Acceptance Criteria**:
- [ ] `condition` property is optional (existing constraints validate without it)
- [ ] `agent_teams` is a valid category
- [ ] Schema validates with `jq '.' .claude/data/constraints.json` after constraint changes in Task 1.2
- [ ] No changes to existing constraint validation behavior

---

### Task 1.2: Add Team Constraints to Registry

**Description**: Add conditional override to C-PROC-002 and create 3 new `C-TEAM-*` constraints.

**Files**:
- `.claude/data/constraints.json`

**Changes**:
1. Add `condition` field to `C-PROC-002`:
   ```json
   "condition": {
     "when": "agent_teams_active",
     "override_text": "In Agent Teams mode, TaskCreate/TaskUpdate serves dual purpose: team coordination (primary) and session display (secondary). Sprint lifecycle STILL uses beads exclusively.",
     "override_rule_type": "MAY"
   }
   ```
2. Add `C-TEAM-001` (lead_only_planning_skills): MUST restrict planning skills to lead
3. Add `C-TEAM-002` (lead_only_beads_operations): MUST serialize beads through lead
4. Add `C-TEAM-003` (lead_owns_state_files): MUST only let lead write to `.run/` state files
5. Bump `version` to `"1.1.0"` (minor: new optional field)

**Acceptance Criteria**:
- [ ] `constraints.json` validates against updated schema
- [ ] C-PROC-002 retains all existing fields unchanged
- [ ] 3 new constraints follow existing ID/naming conventions
- [ ] All new constraints have `agent_teams` category
- [ ] All new constraints target `claude-loa-md` section `agent_teams_constraints`

---

### Task 1.3: Extend Mutation Logger with Team Identity

**Description**: Add `team_id` and `team_member` fields to the audit JSONL schema.

**Files**:
- `.claude/hooks/audit/mutation-logger.sh`

**Changes**:
1. Add two `--arg` lines to the `jq -cn` call:
   ```bash
   --arg team_id "${LOA_TEAM_ID:-}" \
   --arg team_member "${LOA_TEAM_MEMBER:-}" \
   ```
2. Add `team_id: $team_id, team_member: $team_member` to the JSON template

**Acceptance Criteria**:
- [ ] When `LOA_TEAM_ID` and `LOA_TEAM_MEMBER` are unset, fields are empty strings (identical to `model`, `provider`, `trace_id`)
- [ ] When set, fields appear in JSONL entries
- [ ] Script still exits 0 on all paths
- [ ] No change to mutation detection regex or rotation logic

---

### Task 1.4: Update CLAUDE.loa.md with Agent Teams Section

**Description**: Add Agent Teams Compatibility section with constraint-generated markers and task tracking table.

**Files**:
- `.claude/loa/CLAUDE.loa.md`

**Changes**:
1. Add `## Agent Teams Compatibility (v1.39.0)` section after the existing `## Run Bridge` section
2. Include `<!-- @constraint-generated: start agent_teams_constraints -->` markers
3. Add constraint table rows for C-TEAM-001, C-TEAM-002, C-TEAM-003
4. Add "Task Tracking in Agent Teams Mode" comparison table
5. Add reference link to `.claude/loa/reference/agent-teams-reference.md`

**Acceptance Criteria**:
- [ ] New section follows existing CLAUDE.loa.md formatting patterns
- [ ] Constraint markers use same format as other generated sections
- [ ] Single-agent task tracking hierarchy is NOT modified
- [ ] Reference link points to correct file path

---

### Task 1.5: Create Agent Teams Reference Document

**Description**: Create comprehensive reference document for Agent Teams compatibility patterns.

**Files**:
- `.claude/loa/reference/agent-teams-reference.md` (new)

**Sections**:
1. **Overview**: What Agent Teams is, how to enable it
2. **Detection**: Runtime detection via env var check
3. **Skill Invocation Matrix**: Full table (lead-only vs teammate-safe vs either)
4. **Beads Protocol**: Lead-only single-writer pattern with SendMessage for teammate requests
5. **State File Ownership**: Lead-owned files, append-safe files, teammate-scoped pattern
6. **Team Topology Templates**:
   - Template 1: Parallel Sprint Implementation
   - Template 2: Isolated Attention (FE/BE/QA)
   - Template 3: Bridgebuilder Review Swarm
7. **Hook Propagation**: Explanation of project-scoped hook inheritance
8. **Quality Gate Preservation**: Lead enforces implement → review → audit for each teammate
9. **Environment Variables**: `LOA_TEAM_ID`, `LOA_TEAM_MEMBER` usage
10. **Troubleshooting**: Common issues and resolutions

**Acceptance Criteria**:
- [ ] Document follows existing reference file format (see `flatline-reference.md`, `beads-reference.md`)
- [ ] All three topology templates documented with lead/teammate roles
- [ ] Skill matrix matches PRD FR-5 exactly
- [ ] Environment variables match mutation logger implementation (Task 1.3)

---

### Task 1.6: Update Config Example

**Description**: Add `agent_teams` section to `.loa.config.yaml.example`.

**Files**:
- `.loa.config.yaml.example`

**Changes**:
1. Add `agent_teams:` section with `enabled`, `beads_access`, and `state_files` sub-keys
2. Add inline comments explaining each option
3. Place after existing `run_bridge:` section

**Acceptance Criteria**:
- [ ] Config section matches PRD §8 specification
- [ ] All values have inline comments
- [ ] `enabled: auto` is the default
- [ ] `beads_access: lead_only` is the default

---

## Task Dependencies

All 6 tasks are independent. Task 1.2 depends on Task 1.1's schema changes for validation, but they can be implemented in the same commit.

```
Task 1.1 (schema) ─┐
Task 1.2 (constraints) ─── can be combined
Task 1.3 (mutation logger) ── independent
Task 1.4 (CLAUDE.loa.md) ── independent (references Task 1.2 content)
Task 1.5 (reference doc) ── independent
Task 1.6 (config example) ── independent
```

## Sprint 2: Defense-in-Depth — Teammate Role Guard Hook

**Goal**: Add mechanical enforcement of lead-only constraints via a PreToolUse hook, completing the defense-in-depth pattern (advisory constraints in CLAUDE.md + mechanical enforcement via hooks). Source: Bridgebuilder SPECULATION-1.

---

### Task 2.1: Create `team-role-guard.sh` PreToolUse Hook

**Description**: Create a PreToolUse:Bash hook that, when `LOA_TEAM_MEMBER` is set (indicating a teammate context), blocks patterns matching lead-only operations.

**Files**:
- `.claude/hooks/safety/team-role-guard.sh` (new)

**Patterns to block (when LOA_TEAM_MEMBER is set)**:
1. `br ` commands (beads operations) — C-TEAM-002
2. Writes to `.run/*.json` state files (except audit.jsonl) — C-TEAM-003
3. `git commit` and `git push` — C-TEAM-004

**Design**:
- Follow `block-destructive-bash.sh` pattern exactly (fail-open, ERE not PCRE, check_and_block helper)
- When `LOA_TEAM_MEMBER` is empty/unset, exit 0 immediately (no-op for single-agent mode)
- Exit 0 = allow, Exit 2 = block with stderr message
- No `set -euo pipefail` — must never fail closed

**Acceptance Criteria**:
- [ ] When `LOA_TEAM_MEMBER` is unset, all commands are allowed (zero impact)
- [ ] When `LOA_TEAM_MEMBER` is set, `br close 123` is blocked with helpful message
- [ ] When `LOA_TEAM_MEMBER` is set, writes to `.run/simstim-state.json` are blocked
- [ ] When `LOA_TEAM_MEMBER` is set, `git commit` and `git push` are blocked
- [ ] When `LOA_TEAM_MEMBER` is set, `echo "..." >> .run/audit.jsonl` is NOT blocked (append-only safe)
- [ ] Script exits 0 on parse failures (fail-open)
- [ ] Uses ERE (grep -E) not PCRE for portability

---

### Task 2.2: Register Hook in `settings.hooks.json`

**Description**: Add the team-role-guard hook to the PreToolUse:Bash matcher list.

**Files**:
- `.claude/hooks/settings.hooks.json`

**Changes**:
1. Add `team-role-guard.sh` as a second hook in the PreToolUse:Bash array (after `block-destructive-bash.sh`)

**Acceptance Criteria**:
- [ ] Both hooks fire for every Bash tool use
- [ ] Order: block-destructive-bash.sh first, team-role-guard.sh second
- [ ] JSON validates

---

### Task 2.3: Update Reference Documentation

**Description**: Update agent-teams-reference.md and hooks-reference.md to document the new hook.

**Files**:
- `.claude/loa/reference/agent-teams-reference.md`
- `.claude/loa/reference/hooks-reference.md`

**Changes**:
1. Add `team-role-guard.sh` to the Hook Propagation section in agent-teams-reference.md
2. Add entry to hooks-reference.md if it has a hooks table

**Acceptance Criteria**:
- [ ] Hook is documented in both reference files
- [ ] Fail-open behavior is noted
- [ ] LOA_TEAM_MEMBER activation condition is documented

---

## Sprint 3: Excellence Pass — Closing Every Gap from the Bridgebuilder Horizon Review

**Goal**: Address ALL observations from the [Bridgebuilder Horizon Voice review](https://github.com/0xHoneyJar/loa/pull/341#issuecomment-3905519286), regardless of severity level. Extends defense-in-depth beyond the Bash tool boundary, documents the advisory-mechanical gap, and hardens reference documentation for cloud deployment scenarios.

**Source**: Bridgebuilder Deep Review Section VI (Critical Examination), Section V (Cross-Ecosystem Connections)

---

### Task 3.1: Create `team-role-guard-write.sh` — PreToolUse:Write/Edit Guard

**Description**: Close the "confused deputy" gap identified in Section VI.1 of the deep review. Create a PreToolUse hook for Write and Edit tools that blocks teammates from modifying protected paths: `.claude/` (System Zone) and `.run/*.json` (state files).

**Files**:
- `.claude/hooks/safety/team-role-guard-write.sh` (new)

**Design**:
- Same fail-open philosophy as `team-role-guard.sh`
- Reads `tool_input.file_path` from stdin JSON
- When `LOA_TEAM_MEMBER` is set, blocks:
  1. Any path starting with `.claude/` — System Zone protection
  2. Any path matching `.run/*.json` (top-level state files, not subdirs)
- When `LOA_TEAM_MEMBER` is unset, exit 0 immediately (no-op)
- Handles both Write and Edit tools (same input schema for `file_path`)
- No `set -euo pipefail` — must never fail closed

**Acceptance Criteria**:
- [ ] When `LOA_TEAM_MEMBER` is unset, all writes/edits are allowed
- [ ] When set, `Write` to `.claude/data/constraints.json` is blocked with message referencing System Zone
- [ ] When set, `Edit` to `.claude/loa/CLAUDE.loa.md` is blocked
- [ ] When set, `Write` to `.run/simstim-state.json` is blocked
- [ ] When set, `Write` to `.run/bugs/bug-123/state.json` is NOT blocked (subdirectory, teammate-owned)
- [ ] When set, `Write` to `grimoires/loa/a2a/sprint-1/reviewer.md` is NOT blocked (sprint-scoped)
- [ ] When set, `Edit` to `app/src/foo.ts` is NOT blocked (App Zone)
- [ ] Script exits 0 on parse failures (fail-open)

---

### Task 3.2: Register Write/Edit Hooks in `settings.hooks.json`

**Description**: Add PreToolUse:Write and PreToolUse:Edit matchers to the hook configuration, pointing to the new guard script.

**Files**:
- `.claude/hooks/settings.hooks.json`

**Changes**:
1. Add a PreToolUse entry with matcher `Write` pointing to `team-role-guard-write.sh`
2. Add a PreToolUse entry with matcher `Edit` pointing to `team-role-guard-write.sh`

**Acceptance Criteria**:
- [ ] JSON validates
- [ ] Both Write and Edit matchers present in PreToolUse array
- [ ] Single script handles both tools (DRY — same file_path logic)

---

### Task 3.3: Add PIPE_BUF Local Filesystem Caveat

**Description**: Address Section VI.3 of the deep review. The append-only safety section assumes local filesystem atomicity guarantees that don't hold on network filesystems (NFS, CIFS) or Docker volume mounts with certain storage drivers.

**Files**:
- `.claude/loa/reference/agent-teams-reference.md`

**Changes**:
1. Add caveat after the PIPE_BUF statement (line 91 area): "Assumes local filesystem. Network-mounted volumes (NFS, CIFS) and some Docker storage drivers may not preserve `PIPE_BUF` atomicity for concurrent appends."
2. Add note referencing the Hounfour cloud deployment scenario: "If teammates run on separate containers with a shared volume ([loa-finn#31](https://github.com/0xHoneyJar/loa-finn/issues/31) Section 8), use the lead-serialized pattern for all writes."

**Acceptance Criteria**:
- [ ] Caveat is present in the Append-Only Safety subsection
- [ ] Cloud deployment scenario is referenced with link to Hounfour RFC

---

### Task 3.4: Add Enforcement Coverage Inventory

**Description**: Address Section VI.1 and VI.2 of the deep review. Add a new section to the agent-teams reference doc that systematically catalogs which constraints have mechanical enforcement vs. advisory-only status. This makes the gap *visible* rather than hidden — honest engineering.

**Files**:
- `.claude/loa/reference/agent-teams-reference.md`

**Changes**:
1. Add new section `## Enforcement Coverage` after the Mechanical Enforcement subsection
2. Include a table mapping each C-TEAM constraint to its enforcement mechanisms:

| Constraint | Advisory (CLAUDE.md) | Mechanical (Hook) | Tool Coverage | Gaps |
|-----------|---------------------|-------------------|---------------|------|
| C-TEAM-001 (planning skills) | Yes | No | — | Skill invocations not hookable |
| C-TEAM-002 (beads) | Yes | Yes (Bash) | Bash: `br` commands | Write/Edit: covered by Task 3.1 |
| C-TEAM-003 (state files) | Yes | Yes (Bash + Write + Edit) | Full after Task 3.1 | — |
| C-TEAM-004 (git ops) | Yes | Yes (Bash) | Bash: `git commit/push` | — |

3. Add an explicit note about the skill matrix (line 34-48): "The Skill Invocation Matrix is advisory. There is no hook mechanism that can intercept skill invocations — Claude Code's hook system operates at the tool level, not the skill level. Enforcement relies on the lead assigning appropriate tasks via TaskCreate and the teammate reading CLAUDE.md constraints."

**Acceptance Criteria**:
- [ ] Every C-TEAM constraint has an entry in the enforcement table
- [ ] Advisory vs. mechanical columns are clearly labeled
- [ ] Gap column identifies remaining uncovered surfaces
- [ ] Skill matrix advisory nature is explicitly documented

---

### Task 3.5: Add C-TEAM-005 Constraint — System Zone Protection

**Description**: Formalize the System Zone protection as a constraint. The deep review identified that `.claude/` protection relies entirely on the three-zone model instruction in CLAUDE.md. Adding an explicit C-TEAM constraint makes this protection visible in the constraint registry alongside its siblings, and ties it to the new Write/Edit hook.

**Files**:
- `.claude/data/constraints.json`
- `.claude/loa/CLAUDE.loa.md` (add row to Agent Teams constraint table)

**Changes**:
1. Add `C-TEAM-005` constraint:
   - `id`: `C-TEAM-005`
   - `name`: `teammate_system_zone_readonly`
   - `rule_type`: `MUST`
   - `text`: "Teammates MUST NOT modify files in the System Zone (`.claude/`). All framework configuration is lead-only."
   - `why`: "System Zone modifications by a teammate could alter constraint definitions, hook behavior, or skill configurations for all agents in the team."
   - `severity`: `critical`
   - `category`: `agent_teams`
   - `source_incident`: `bridgebuilder-horizon-pr341`
2. Add row to CLAUDE.loa.md Agent Teams constraint table

**Acceptance Criteria**:
- [ ] C-TEAM-005 follows the established pattern of C-TEAM-001 through C-TEAM-004
- [ ] Severity is `critical` (System Zone integrity is foundational)
- [ ] CLAUDE.loa.md table includes the new constraint
- [ ] `constraints.json` still validates against schema

---

### Task 3.6: Update All Reference Documentation

**Description**: Update hooks-reference.md, agent-teams-reference.md, and CLAUDE.loa.md to reflect the new Write/Edit hooks and C-TEAM-005 constraint. Remove the "planned for a future iteration" note about PreToolUse:Write and replace with documentation of the actual implementation.

**Files**:
- `.claude/loa/reference/hooks-reference.md`
- `.claude/loa/reference/agent-teams-reference.md`
- `.claude/loa/CLAUDE.loa.md`

**Changes**:
1. **hooks-reference.md**: Add two new rows to the All Hook Registrations table (PreToolUse:Write, PreToolUse:Edit). Add a new section describing the Write/Edit guard.
2. **agent-teams-reference.md**:
   - Replace "Known limitation: The hook covers Bash tool only..." with documentation of the actual Write/Edit hook coverage
   - Add `team-role-guard-write.sh` to the Hook Propagation section
   - Update CLAUDE.loa.md hook table to include the new entries
3. **CLAUDE.loa.md**: Add rows for Write/Edit hooks in the Safety Hooks table

**Acceptance Criteria**:
- [ ] "Planned for a future iteration" text is replaced with actual implementation docs
- [ ] All three documentation files are consistent
- [ ] Hook Propagation section lists all 4 safety hooks (block-destructive, team-role-guard Bash, team-role-guard Write, team-role-guard Edit — though Write and Edit share a script)
- [ ] CLAUDE.loa.md Safety Hooks table includes new entries

---

## Task Dependencies (Sprint 3)

```
Task 3.1 (Write/Edit hook) ─┐
Task 3.2 (registration) ────┤── Task 3.1 must exist before registration
Task 3.3 (PIPE_BUF caveat) ── independent
Task 3.4 (enforcement inventory) ── depends on 3.1 for accurate coverage table
Task 3.5 (C-TEAM-005) ── independent (constraint data)
Task 3.6 (doc updates) ── depends on 3.1, 3.2, 3.4, 3.5
```

**Recommended order**: 3.1 → 3.2 → 3.5 → 3.3 → 3.4 → 3.6

---

## Risk Notes (Sprints 1–3)

- **Schema `additionalProperties: false`**: The constraint schema uses strict validation. Task 1.1 MUST add `condition` before Task 1.2 adds it to constraint data.
- **CLAUDE.loa.md is `@loa-managed`**: The file has a managed header (`<!-- @loa-managed: true | version: 1.37.0 -->`). Update the version to `1.39.0` when adding the new section.
- **Constraint hashes**: Generated sections use `hash:` markers. The new `agent_teams_constraints` section needs its own hash.
- **Write/Edit hook input format**: PreToolUse hooks for Write and Edit receive JSON with `tool_input.file_path`. Verify the exact schema by testing with a simple logging hook before implementing blocking logic.
- **Hook registration for multiple tools**: The `settings.hooks.json` format requires separate matcher entries for each tool. The same script can be referenced by both Write and Edit matchers.

---

## Sprint 4: Advisory-to-Mechanical Promotion — Zero Advisory Gaps

**Goal**: Close every remaining advisory-only enforcement gap. After this sprint, every enforceable C-TEAM constraint has mechanical hook coverage. The Enforcement Coverage table should show ZERO actionable gaps.

**Source**: [Bridgebuilder Horizon Review §VI](https://github.com/0xHoneyJar/loa/pull/341#issuecomment-3905844109) (Critical Examination), Enforcement Coverage Inventory in `agent-teams-reference.md`

**Key Insight**: The Sprint 3 claim that "skill invocations are not hookable" was incorrect. The `Skill` tool is a regular tool — `PreToolUse:Skill` works exactly like `PreToolUse:Bash`. This means C-TEAM-001 (planning skills lead-only) can be mechanically enforced. The `tool_input.skill` field contains the skill name, enabling a blocklist-based guard.

---

### Task 4.1: Create `team-skill-guard.sh` — PreToolUse:Skill Hook

**Description**: Close the C-TEAM-001 gap by creating a PreToolUse:Skill hook that blocks lead-only skill invocations for teammates. This is the most impactful task — it promotes the last critical advisory constraint to mechanical enforcement.

**Files**:
- `.claude/hooks/safety/team-skill-guard.sh` (new)

**Design**:
- Same fail-open philosophy as all other guards
- When `LOA_TEAM_MEMBER` is unset, exit 0 immediately (no-op for single-agent mode)
- When set, read `tool_input.skill` from stdin JSON
- Block if skill matches lead-only blocklist
- No `set -euo pipefail` — must never fail closed

**Lead-only skills** (from PRD FR-5 / Skill Invocation Matrix):
```
plan-and-analyze, architect, sprint-plan, simstim,
run-sprint-plan, run-bridge, ride, update-loa, ship,
autonomous, run, loa-setup, mount, loa-eject,
plan, deploy-production
```

**Teammate-allowed skills**:
```
implement, review-sprint, audit-sprint, bug, review,
build, feedback, translate, validate, audit
```

**Implementation sketch**:
```bash
#!/usr/bin/env bash
# Early exit: if not a teammate, allow everything
if [[ -z "${LOA_TEAM_MEMBER:-}" ]]; then
  exit 0
fi

input=$(cat)
skill=$(echo "$input" | jq -r '.tool_input.skill // empty' 2>/dev/null) || true

if [[ -z "$skill" ]]; then
  exit 0
fi

# Lead-only skill blocklist
LEAD_ONLY="plan-and-analyze architect sprint-plan simstim run-sprint-plan run-bridge ride update-loa ship autonomous run loa-setup mount loa-eject plan deploy-production"

for blocked in $LEAD_ONLY; do
  if [[ "$skill" == "$blocked" ]]; then
    echo "BLOCKED [team-skill-guard]: Skill /$skill is lead-only in Agent Teams mode (C-TEAM-001)." >&2
    echo "Teammate '$LOA_TEAM_MEMBER' cannot invoke planning/orchestration skills. Report to the lead via SendMessage." >&2
    exit 2
  fi
done

exit 0
```

**Acceptance Criteria**:
- [ ] When `LOA_TEAM_MEMBER` is unset, all skills are allowed (zero impact on single-agent mode)
- [ ] When set, `/plan-and-analyze` is blocked with helpful message referencing C-TEAM-001
- [ ] When set, `/architect` is blocked
- [ ] When set, `/simstim` is blocked
- [ ] When set, `/run-bridge` is blocked
- [ ] When set, `/implement sprint-1` is NOT blocked (teammate-allowed)
- [ ] When set, `/review-sprint sprint-1` is NOT blocked
- [ ] When set, `/bug` is NOT blocked
- [ ] When set, `/build` is NOT blocked (golden path, delegates to implement)
- [ ] Script exits 0 on parse failures (fail-open)
- [ ] Uses simple string comparison (no regex needed for exact skill names)

---

### Task 4.2: Register Skill Hook in `settings.hooks.json`

**Description**: Add PreToolUse:Skill matcher to the hook configuration.

**Files**:
- `.claude/hooks/settings.hooks.json`

**Changes**:
1. Add a new entry in the `PreToolUse` array:
```json
{
  "matcher": "Skill",
  "hooks": [
    {
      "type": "command",
      "command": ".claude/hooks/safety/team-skill-guard.sh"
    }
  ]
}
```

**Acceptance Criteria**:
- [ ] JSON validates (`jq '.' .claude/hooks/settings.hooks.json`)
- [ ] Skill matcher is present alongside Bash, Write, Edit matchers
- [ ] Hook fires when the Skill tool is invoked (verify in single-agent mode with `LOA_TEAM_MEMBER` unset — should be a no-op)

---

### Task 4.3: Close `install`/`patch` Gap in `team-role-guard.sh` (C-TEAM-005)

**Description**: The Enforcement Coverage table documents that `install` and `patch` commands targeting `.claude/` are unguarded. While low risk (unusual commands), excellence means zero documented gaps.

**Files**:
- `.claude/hooks/safety/team-role-guard.sh`

**Changes**:
1. Add `install` pattern for `.claude/` targets:
```bash
check_and_block \
  'install\s+.*(\S*/)?\.claude/' \
  "Using 'install' to write to System Zone (.claude/) is lead-only in Agent Teams mode (C-TEAM-005)."
```
2. Add `patch` pattern for `.claude/` targets:
```bash
check_and_block \
  'patch\s+.*(\S*/)?\.claude/' \
  "Patching System Zone (.claude/) files is lead-only in Agent Teams mode (C-TEAM-005)."
```

**Acceptance Criteria**:
- [ ] `LOA_TEAM_MEMBER=test && echo 'install -m 755 foo .claude/hooks/evil.sh' | ...` is blocked
- [ ] `LOA_TEAM_MEMBER=test && echo 'patch .claude/loa/CLAUDE.loa.md diff.patch' | ...` is blocked
- [ ] Normal `install` and `patch` commands NOT targeting `.claude/` are allowed
- [ ] Existing tests for other C-TEAM-005 patterns still pass

---

### Task 4.4: Protect Append-Only Files from Write/Edit Misuse

**Description**: Close the atomicity gap from Horizon Review §VI.2. The Write tool does a full read-modify-write cycle — it is NOT safe for concurrent access. If a teammate uses Write instead of `echo >> file` for append-only files (`.run/audit.jsonl`, `grimoires/loa/NOTES.md`), data loss can occur. Block Write/Edit on these specific files for teammates.

**Files**:
- `.claude/hooks/safety/team-role-guard-write.sh`

**Changes**:
1. After the `.run/*.json` check (line 68-72), add a new block:
```bash
# ---------------------------------------------------------------------------
# Append-Only File Protection
# These files MUST use Bash append (echo >> file) for POSIX atomic writes.
# The Write tool does full read-modify-write which is NOT concurrent-safe.
# Block Write/Edit for teammates; they must use Bash append instead.
# ---------------------------------------------------------------------------
APPEND_ONLY_FILES=".run/audit.jsonl grimoires/loa/NOTES.md"
for protected in $APPEND_ONLY_FILES; do
  if [[ "$file_path" == "$protected" ]]; then
    echo "BLOCKED [team-role-guard-write]: '$file_path' is append-only. Use Bash: echo \"...\" >> $file_path (POSIX atomic writes)." >&2
    echo "Teammate '$LOA_TEAM_MEMBER' must NOT use Write/Edit for append-only files — only Bash append (>>)." >&2
    exit 2
  fi
done
```

**Acceptance Criteria**:
- [ ] When `LOA_TEAM_MEMBER` is set, `Write` to `.run/audit.jsonl` is blocked with message explaining to use Bash append
- [ ] When `LOA_TEAM_MEMBER` is set, `Write` to `grimoires/loa/NOTES.md` is blocked with message explaining to use Bash append
- [ ] When `LOA_TEAM_MEMBER` is set, `Edit` to `grimoires/loa/NOTES.md` is blocked (Edit is also full replace)
- [ ] When `LOA_TEAM_MEMBER` is unset, all files are accessible (single-agent mode unaffected)
- [ ] When `LOA_TEAM_MEMBER` is set, `Write` to `grimoires/loa/a2a/sprint-1/reviewer.md` is NOT blocked (not append-only)
- [ ] Bash append (`echo "..." >> .run/audit.jsonl`) remains allowed (team-role-guard.sh does not block `>>`)

---

### Task 4.5: Extend Mutation Logger to Write/Edit Operations

**Description**: Close the audit gap. Currently, only Bash commands are logged to `.run/audit.jsonl`. Teammate modifications via Write/Edit tools are invisible to the audit trail. Create a PostToolUse logger for Write and Edit operations.

**Files**:
- `.claude/hooks/audit/write-mutation-logger.sh` (new)
- `.claude/hooks/settings.hooks.json`

**Design**:
- New script (not extending mutation-logger.sh) because the input format is different:
  - Bash PostToolUse: `tool_input.command` + `tool_result.exit_code`
  - Write/Edit PostToolUse: `tool_input.file_path` + `tool_input.old_string`/`tool_input.new_string` (Edit) or `tool_input.content` (Write)
- Same JSONL format as mutation-logger.sh for consistency
- Same audit.jsonl destination
- Captures: timestamp, tool name (Write/Edit), file_path, team_id, team_member
- Does NOT log file content (privacy, size)
- Same fail-open philosophy, same rotation threshold

**Implementation sketch**:
```bash
#!/usr/bin/env bash
input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || true
tool_name=$(echo "$input" | jq -r '.tool_name // "Write"' 2>/dev/null) || true

if [[ -z "$file_path" ]]; then
  exit 0
fi

AUDIT_FILE=".run/audit.jsonl"
mkdir -p .run 2>/dev/null
jq -cn \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg tool "$tool_name" \
  --arg file_path "$file_path" \
  --arg model "${LOA_CURRENT_MODEL:-}" \
  --arg provider "${LOA_CURRENT_PROVIDER:-}" \
  --arg trace_id "${LOA_TRACE_ID:-}" \
  --arg team_id "${LOA_TEAM_ID:-}" \
  --arg team_member "${LOA_TEAM_MEMBER:-}" \
  '{ts: $ts, tool: $tool, file_path: $file_path, model: $model, provider: $provider, trace_id: $trace_id, team_id: $team_id, team_member: $team_member}' \
  >> "$AUDIT_FILE" 2>/dev/null

exit 0
```

**Hook registration** (add to settings.hooks.json):
```json
{
  "matcher": "Write",
  "hooks": [
    {
      "type": "command",
      "command": ".claude/hooks/audit/write-mutation-logger.sh"
    }
  ]
},
{
  "matcher": "Edit",
  "hooks": [
    {
      "type": "command",
      "command": ".claude/hooks/audit/write-mutation-logger.sh"
    }
  ]
}
```

**Note**: PostToolUse can have multiple matchers for the same tool. The existing PreToolUse:Write guard and this new PostToolUse:Write logger are separate events.

**Acceptance Criteria**:
- [ ] After a Write tool use, a JSONL entry appears in `.run/audit.jsonl` with `tool: "Write"` and `file_path`
- [ ] After an Edit tool use, a JSONL entry appears with `tool: "Edit"` and `file_path`
- [ ] Team identity fields (`team_id`, `team_member`) are captured when set
- [ ] Script exits 0 on all paths (never blocks the operation — PostToolUse is informational)
- [ ] No file content is logged (privacy, size constraints)
- [ ] JSONL entries are compatible with existing audit.jsonl format (can be parsed alongside Bash entries)

---

### Task 4.6: Update Enforcement Coverage + All Reference Docs

**Description**: Update the Enforcement Coverage table and all reference documentation to reflect the new zero-gap state.

**Files**:
- `.claude/loa/reference/agent-teams-reference.md`
- `.claude/loa/reference/hooks-reference.md`
- `.claude/loa/CLAUDE.loa.md`

**Changes**:

1. **agent-teams-reference.md — Enforcement Coverage table**:

| Constraint | Advisory (CLAUDE.md) | Mechanical (Hook) | Tool Coverage | Gaps |
|-----------|---------------------|-------------------|---------------|------|
| C-TEAM-001 (planning skills lead-only) | Yes | Yes (Skill) | Skill: blocklist-based guard | — |
| C-TEAM-002 (beads serialization) | Yes | Yes (Bash) | Bash: `br` commands blocked | Write/Edit: no beads files to protect |
| C-TEAM-003 (state file ownership) | Yes | Yes (Bash + Write + Edit) | Full coverage | — |
| C-TEAM-004 (git serialization) | Yes | Yes (Bash) | Bash: `git commit/push` blocked | Git ops only available via Bash |
| C-TEAM-005 (System Zone readonly) | Yes | Yes (Bash + Write + Edit) | Bash: `cp`/`mv`, redirect, `tee`, `sed -i`, `install`, `patch`; Write/Edit: `realpath -m` normalization | — |

Remove the note about "Skill Matrix is advisory only" and replace with: "The Skill Invocation Matrix is mechanically enforced via `PreToolUse:Skill` hook (`team-skill-guard.sh`). Lead-only skills are blocked for teammates by matching `tool_input.skill` against a blocklist."

2. **agent-teams-reference.md — Append-Only Safety subsection**: Add note that Write/Edit are mechanically blocked for append-only files when `LOA_TEAM_MEMBER` is set.

3. **hooks-reference.md**:
   - Add PreToolUse:Skill section describing team-skill-guard.sh
   - Add PostToolUse:Write/Edit section describing write-mutation-logger.sh
   - Add 3 new rows to All Hook Registrations table (PreToolUse:Skill, PostToolUse:Write, PostToolUse:Edit)

4. **CLAUDE.loa.md**:
   - Add `team-skill-guard.sh` to Safety Hooks table
   - Add `write-mutation-logger.sh` to Safety Hooks table
   - Update version reference if applicable

**Acceptance Criteria**:
- [ ] Enforcement Coverage table shows zero actionable gaps (every constraint has mechanical enforcement)
- [ ] "Skill Matrix is advisory only" note is replaced with mechanical enforcement documentation
- [ ] All new hooks appear in hooks-reference.md registrations table
- [ ] CLAUDE.loa.md Safety Hooks table is complete and accurate
- [ ] All three documentation files are internally consistent
- [ ] Append-only file protection is documented in agent-teams-reference.md

---

## Task Dependencies (Sprint 4)

```
Task 4.1 (Skill hook) ─┐
Task 4.2 (registration) ── depends on 4.1
Task 4.3 (install/patch) ── independent
Task 4.4 (append-only) ── independent
Task 4.5 (Write/Edit logger) ── independent
Task 4.6 (docs) ── depends on 4.1, 4.2, 4.3, 4.4, 4.5
```

**Recommended order**: 4.1 → 4.2 → 4.3 + 4.4 + 4.5 (parallel) → 4.6

---

## Risk Notes (Sprint 4)

- **PreToolUse:Skill hookability**: The Skill tool is listed as a regular tool in Claude Code. If `PreToolUse:Skill` does NOT fire (undocumented limitation), Task 4.1 will need verification. Test with a simple logging hook first. If it doesn't work, update the enforcement table honestly and document the platform limitation.
- **Skill name matching**: Skills may have aliases or fully-qualified names (e.g., `projectSettings:implement`). The hook should match both short names and any prefix. Test with actual skill invocations.
- **PostToolUse for Write/Edit**: Verify that PostToolUse fires for Write and Edit tools. If Claude Code only supports PostToolUse for Bash, the audit gap remains and should be documented honestly.
- **append-only file list maintenance**: The `APPEND_ONLY_FILES` list in Task 4.4 is hardcoded. If new append-only files are added, the list needs updating. Consider a config-driven approach if the list grows.
- **Backward compatibility**: All new hooks are no-ops when `LOA_TEAM_MEMBER` is unset. Zero impact on single-agent mode. The PostToolUse logger (Task 4.5) fires for all users but only appends to audit.jsonl — same pattern as existing mutation-logger.sh.
