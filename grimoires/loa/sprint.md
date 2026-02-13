# Sprint Plan: Harness Engineering Adaptations

> Source: SDD cycle-011, Issue [#297](https://github.com/0xHoneyJar/loa/issues/297)
> Cycle: cycle-011
> Sprints: 3

## Sprint 1: Safety Hooks + Deny Rules (P1, P2)

**Goal**: Ship the core safety infrastructure — destructive command blocking and credential deny rules.

### Task 1.1: Create Safety Hook Script

**File**: `.claude/hooks/safety/block-destructive-bash.sh`

Create the `PreToolUse:Bash` hook that blocks destructive patterns:
- `rm -rf` → suggest `trash` or individual removal
- `git push --force` → suggest `--force-with-lease` or feature branch
- `git reset --hard` → suggest `git stash`
- `git clean -f` without `-n` → suggest dry-run first

**Acceptance Criteria**:
- Script reads stdin JSON, extracts `command` via `jq`
- Returns exit 2 with descriptive stderr for blocked commands
- Returns exit 0 for all other commands
- Script is executable (`chmod +x`)
- Tested with sample inputs

### Task 1.2: Create Deny Rules Template

**File**: `.claude/hooks/settings.deny.json`

Create the deny rules template covering:
- SSH keys (`~/.ssh/**`)
- AWS credentials (`~/.aws/**`)
- Kubernetes config (`~/.kube/**`)
- GPG keys (`~/.gnupg/**`)
- Package registry credentials (`~/.npmrc`, `~/.pypirc`)
- Git credentials (`~/.git-credentials`, `~/.config/gh/**`)
- Shell config (edit-only deny: `~/.bashrc`, `~/.zshrc`, `~/.profile`)

**Acceptance Criteria**:
- Valid JSON file
- Comment field explaining purpose
- Covers all Trail of Bits recommended deny paths

### Task 1.3: Create Deny Rules Installation Script

**File**: `.claude/scripts/install-deny-rules.sh`

Script that merges deny rules into `~/.claude/settings.json`:
- `--auto` flag: install without prompting (for `/mount`)
- `--prompt` flag: ask user before installing
- `--dry-run` flag: show what would be added
- Backs up existing settings before modification
- Additive merge (never removes existing deny rules)

**Acceptance Criteria**:
- Creates backup at `~/.claude/settings.json.bak`
- Merges deny rules into existing permissions.deny array
- Handles case where settings.json doesn't exist
- Handles case where permissions.deny already has some rules
- Reports what was added

### Task 1.4: Update settings.hooks.json

**File**: `.claude/hooks/settings.hooks.json`

Add `PreToolUse:Bash` hook registration pointing to `block-destructive-bash.sh`.

**Acceptance Criteria**:
- Existing PreCompact and UserPromptSubmit hooks preserved
- New PreToolUse section added
- Valid JSON

### Task 1.5: Test Safety Hooks

Test the safety hook with sample inputs:
- Test `rm -rf /` → blocked
- Test `rm file.txt` → allowed
- Test `git push --force origin main` → blocked
- Test `git push origin feature` → allowed
- Test `git reset --hard HEAD~1` → blocked
- Test `git reset HEAD file.txt` → allowed
- Test `git clean -fd` → blocked
- Test `git clean -nd` → allowed

**Acceptance Criteria**:
- All blocked patterns return exit 2
- All allowed patterns return exit 0
- No false positives on common commands

---

## Sprint 2: Stop Hook + Audit Logger + CLAUDE.md Optimization (P3, P4, P5)

**Goal**: Ship the stop guard, audit logging, and reduce CLAUDE.md token footprint by ~50%.

### Task 2.1: Create Stop Hook — Run Mode Guard

**File**: `.claude/hooks/safety/run-mode-stop-guard.sh`

Stop hook that detects active autonomous runs:
- Check `.run/sprint-plan-state.json` state=RUNNING
- Check `.run/bridge-state.json` state=ITERATING or FINALIZING
- If active: inject context reminder via stdout JSON
- If not active: allow stop (exit 0)

**Acceptance Criteria**:
- Reads sprint-plan-state.json and bridge-state.json
- Only fires when state=RUNNING/ITERATING/FINALIZING
- Uses stdout JSON `decision` field, not hard block
- Handles missing state files gracefully (exit 0)
- Add to settings.hooks.json Stop section

### Task 2.2: Create Audit Logger Hook

**File**: `.claude/hooks/audit/mutation-logger.sh`

PostToolUse:Bash hook that logs mutating commands:
- Parse stdin JSON for command and exit_code
- Filter for mutating commands (git, npm, pip, cargo, rm, mv, cp, mkdir, docker, kubectl)
- Append JSONL entry to `.run/audit.jsonl`
- Handle log rotation if file exceeds 10MB

**Acceptance Criteria**:
- JSONL format: `{ts, tool, command, exit_code, cwd}`
- Only logs mutating commands (not `ls`, `cat`, `grep`, etc.)
- Creates `.run/` directory if missing
- Script is executable
- Add to settings.hooks.json PostToolUse section

### Task 2.3: Extract Verbose Sections to Reference Files

Move these sections from `.claude/loa/CLAUDE.loa.md` to dedicated reference files:

| Section | Target File |
|---------|------------|
| Beads-First Architecture details | `.claude/loa/reference/beads-reference.md` |
| Run Bridge details | `.claude/loa/reference/run-bridge-reference.md` |
| Flatline Protocol details | `.claude/loa/reference/flatline-reference.md` |
| Persistent Memory details | `.claude/loa/reference/memory-reference.md` |
| Input Guardrails details | `.claude/loa/reference/guardrails-reference.md` |
| Post-Compact Recovery details | `.claude/loa/reference/hooks-reference.md` |

**Acceptance Criteria**:
- Each reference file has the full content that was in CLAUDE.loa.md
- CLAUDE.loa.md sections replaced with 2-line pointers
- No content lost — just relocated
- Reference files are well-structured with headers

### Task 2.4: Optimize CLAUDE.loa.md Inline Content

After extraction, optimize remaining inline content:
- Remove redundant explanations where skill SKILL.md already covers
- Tighten configuration examples to essential-only
- Ensure constraints, zone model, workflow, and golden path remain prominent
- Update hash in header comment

**Acceptance Criteria**:
- Line count: 350-400 lines (from 757)
- Word count: ~1700 words (from 3433)
- All NEVER/ALWAYS rules preserved
- All constraint-generated blocks preserved
- Zone model, golden path, and workflow table preserved
- Token savings: ~50%

### Task 2.5: Update settings.hooks.json with All New Hooks

Final update to settings.hooks.json adding:
- PostToolUse:Bash → mutation-logger.sh
- Stop → run-mode-stop-guard.sh

**Acceptance Criteria**:
- All 5 hook types registered: PreCompact, UserPromptSubmit, PreToolUse:Bash, PostToolUse:Bash, Stop
- Valid JSON

---

## Sprint 3: Invariant Linter + Integration (P6)

**Goal**: Ship mechanical invariant enforcement and wire everything together.

### Task 3.1: Create Invariant Linter Script

**File**: `.claude/scripts/lint-invariants.sh`

Validate Loa structural invariants:
- Invariant 1: No unexpected `.claude/` modifications (check git diff)
- Invariant 2: CLAUDE.loa.md integrity hash valid
- Invariant 3: constraints.json is valid JSON
- Invariant 4: Constraint-generated blocks in CLAUDE.loa.md exist
- Invariant 5: Required files present (`.loa-version.json`, `.loa.config.yaml`, CLAUDE.loa.md)

Flags: `--json` for machine-readable output, `--fix` for auto-fix where possible.

**Acceptance Criteria**:
- Reports PASS/WARN/ERROR for each invariant
- `--json` outputs structured results
- Exit code 0 if all pass, 1 if warnings, 2 if errors
- Handles missing files gracefully

### Task 3.2: Add Harness Configuration Section

Update `.loa.config.yaml.example` with new harness configuration:

```yaml
harness:
  safety_hooks:
    enabled: true
  deny_rules:
    auto_install: true
  audit_logging:
    enabled: true
  stop_guard:
    enabled: true
  invariant_linting:
    enabled: true
```

**Acceptance Criteria**:
- New harness section added to example config
- Comments explain each option
- Defaults match what we ship

### Task 3.3: Update Hooks README

Update `.claude/hooks/README.md` to document:
- Safety hooks (block-destructive-bash.sh)
- Deny rules (settings.deny.json + install script)
- Stop guard (run-mode-stop-guard.sh)
- Audit logger (mutation-logger.sh)
- Installation instructions

**Acceptance Criteria**:
- All new hooks documented
- Installation instructions updated
- Troubleshooting section updated

### Task 3.4: Final Validation

- Run lint-invariants.sh and verify all pass
- Verify CLAUDE.loa.md token reduction (measure before/after)
- Verify settings.hooks.json is valid and complete
- Verify all new scripts are executable

**Acceptance Criteria**:
- lint-invariants.sh exits 0
- CLAUDE.loa.md word count < 2000 (from 3433)
- All .sh files have +x permission
- All .json files are valid
