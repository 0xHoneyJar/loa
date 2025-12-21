# Loa Established Codebase Support - Implementation Prompt

You are implementing comprehensive support for established codebases in the Loa framework. This adds a complete "adoption" workflow that extracts documentation from actual code, detects drift from legacy docs, and establishes Loa as the source of truth.

## Overview

Create/update the following files:

**New Files (7):**
1. `.claude/commands/adopt.md`
2. `.claude/skills/adopting-codebase/SKILL.md`
3. `.claude/skills/adopting-codebase/resources/drift-checklist.md`
4. `.claude/skills/refactoring-legacy/SKILL.md`
5. `.claude/scripts/detect-drift.sh`
6. `.claude/scripts/validate-change-plan.sh`
7. `.claude/protocols/change-validation.md`

**Updated Files (5):**
1. `.claude/commands/setup.md` - Add repo mode detection
2. `.claude/skills/implementing-tasks/SKILL.md` - Add legacy code protocol
3. `.claude/skills/reviewing-code/SKILL.md` - Add refactoring criteria
4. `.claude/skills/auditing-security/SKILL.md` - Add legacy audit checks
5. `.claude/protocols/session-end.md` - Add drift detection + compaction

---

## PART 1: NEW FILES

### 1.1 Create `.claude/commands/adopt.md`

```markdown
# /adopt - Adopt Existing Codebase into Loa

Migrates an existing codebase to Loa-maintained documentation. Analyzes actual code behavior, compares against existing documentation, generates Loa-standard artifacts grounded in code evidence, and establishes Loa as the single source of truth.

## Prerequisites

- `/setup` completed with `repo_mode: established`
- Beads initialized
- Git repository

## Phases

| Phase | Name | Output |
|-------|------|--------|
| 1 | Code Reality Extraction | `loa-grimoire/reality/` |
| 2 | Legacy Doc Inventory | `loa-grimoire/legacy/` |
| 3 | Drift Analysis | `loa-grimoire/drift-report.md` |
| 4 | Loa Artifact Generation | `prd.md`, `sdd.md`, Beads backlog |
| 5 | Legacy Deprecation | Deprecation notices in old docs |
| 6 | Maintenance Handoff | Drift detection, protocol updates |

## Execution

Invoke the `adopting-codebase` skill and execute all phases sequentially.

## Options

| Flag | Effect |
|------|--------|
| `--phase <name>` | Run single phase (reality, inventory, drift, generate, deprecate, handoff) |
| `--dry-run` | Preview changes without writing files |
| `--skip-deprecation` | Don't modify legacy docs |

## Post-Adoption

1. Review `loa-grimoire/drift-report.md` for critical issues
2. Schedule stakeholder review of `prd.md` and `sdd.md`
3. Resolve high-priority drift items via `/implement`
4. Communicate to team that Loa docs are now source of truth

## Beads Integration

Creates migration epic with child tasks:
- Validate PRD with stakeholders
- Validate SDD with team
- Resolve critical drift items
- Deprecate legacy documentation

Plus imports all TODO/FIXME comments as tech debt issues.
```

---

### 1.2 Create `.claude/skills/adopting-codebase/SKILL.md`

```yaml
---
name: adopting-codebase
description: >
  Adopts existing codebases into Loa's documentation system. Extracts actual
  code behavior, compares against existing docs for drift, generates Loa-standard
  artifacts grounded in evidence, and establishes migration path. Use when
  importing a project into Loa or auditing documentation accuracy.
allowed-tools: [Read, Write, Glob, Grep, Bash]
---
```

```markdown
# Adopting Codebase into Loa

You are migrating an existing codebase to Loa-maintained documentation. Your goal is to make Loa artifacts the **single source of truth** by grounding them in actual code behavior.

## Core Principle

```
CODE is truth → Loa documents CODE → Legacy docs are deprecated
```

Never trust existing documentation. Verify everything against actual code.

---

## Phase 1: Code Reality Extraction

### 1.1 Setup

```bash
mkdir -p loa-grimoire/reality loa-grimoire/legacy
```

### 1.2 Extract System Reality

#### Directory Structure
```bash
find . -type d -maxdepth 3 \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -not -path "*/dist/*" \
  -not -path "*/build/*" \
  2>/dev/null > loa-grimoire/reality/directory-structure.txt
```

#### API Routes
```bash
grep -rn "@Get\|@Post\|@Put\|@Delete\|@Patch\|router\.\|app\.\(get\|post\|put\|delete\|patch\)" \
  --include="*.ts" --include="*.js" --include="*.py" --include="*.go" 2>/dev/null \
  > loa-grimoire/reality/api-routes.txt
```

#### Data Models
```bash
grep -rn "model \|class.*Entity\|@Entity\|CREATE TABLE\|type.*struct" \
  --include="*.prisma" --include="*.ts" --include="*.sql" --include="*.go" 2>/dev/null \
  > loa-grimoire/reality/data-models.txt
```

#### Environment Variables
```bash
grep -roh 'process\.env\.\w\+\|os\.environ\[.\+\]\|os\.Getenv\(.\+\)' \
  --include="*.ts" --include="*.js" --include="*.py" --include="*.go" 2>/dev/null \
  | sort -u > loa-grimoire/reality/env-vars.txt
```

#### Tech Debt
```bash
grep -rn "TODO\|FIXME\|HACK\|XXX\|BUG\|@deprecated" \
  --include="*.ts" --include="*.js" --include="*.py" --include="*.go" 2>/dev/null \
  > loa-grimoire/reality/tech-debt.txt
```

#### Features & Permissions
```bash
grep -rn "feature\|flag\|toggle\|role\|permission\|isAdmin\|canAccess\|@Roles" \
  --include="*.ts" --include="*.js" --include="*.py" 2>/dev/null \
  > loa-grimoire/reality/features-permissions.txt
```

### 1.3 Generate Reality Summary

Create `loa-grimoire/reality/REALITY-SUMMARY.md` with:
- File counts by type
- API endpoint count
- Data model count
- External dependency count (from env vars)
- Tech debt count
- Key architectural patterns observed

---

## Phase 2: Legacy Documentation Inventory

### 2.1 Find All Docs

```bash
find . -type f \( -name "*.md" -o -name "*.rst" -o -name "*.txt" -o -name "*.adoc" \) \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -not -path "*/loa-grimoire/*" \
  2>/dev/null > loa-grimoire/legacy/doc-files.txt
```

### 2.2 Categorize Documents

For each doc, determine type (Tutorial, How-To, Reference, Explanation) and extract key claims about features, architecture, and APIs.

### 2.3 Create Inventory

Create `loa-grimoire/legacy/INVENTORY.md` listing all docs with their type and key claims.

---

## Phase 3: Drift Analysis

### 3.1 Compare Reality vs Claims

For each claim in legacy docs, verify against code reality:
- **Ghost**: Documented but doesn't exist in code
- **Shadow**: Exists in code but not documented
- **Aligned**: Documentation matches code

### 3.2 Generate Drift Report

Create `loa-grimoire/drift-report.md`:

```markdown
# Documentation Drift Report

> Generated: [timestamp]

## Summary

| Category | Reality | Documented | Ghosts | Shadows |
|----------|---------|------------|--------|---------|
| API Endpoints | X | Y | Z | W |
| Data Models | X | Y | Z | W |
| Features | X | Y | Z | W |

## Drift Score: X% (lower is better)

## Critical Drift Items

### Ghosts (Documented but Missing)
[List with legacy doc location]

### Shadows (Exist but Undocumented)
[List with code location]

## Recommendations
[Prioritized list of drift to resolve]
```

### 3.3 Create Beads Issues for Drift

```bash
DRIFT_EPIC=$(bd create "Epic: Documentation Drift Resolution" -t epic -p 1 -l migration,drift --json | jq -r '.id')

# For critical ghosts
bd create "Drift: [item] documented but missing" -t bug -p 1 -l drift,ghost --json

# For important shadows  
bd create "Drift: [item] exists but undocumented" -t task -p 2 -l drift,shadow --json
```

---

## Phase 4: Loa Artifact Generation

### 4.1 Generate PRD

Create `loa-grimoire/prd.md` with:

```markdown
# Product Requirements Document

> ⚠️ **Source of Truth Notice**
> Generated from code analysis on [date]. Supersedes legacy documentation.

## Document Metadata
| Field | Value |
|-------|-------|
| Generated | [timestamp] |
| Source | Code reality extraction |
| Drift Score | X% |

## User Types
[From actual role/permission code with file:line evidence]

## Features
[From actual code with evidence for each]

### Feature: [Name]
- **Status**: Active in code
- **Evidence**: `src/path/file.ts:line`
- **Endpoints**: [list]
- **Code Quote**:
  ```typescript
  // Actual code
  ```

## Deprecated/Ghost Features
[Features in legacy docs but not in code]
```

### 4.2 Generate SDD

Create `loa-grimoire/sdd.md` with:

```markdown
# System Design Document

> ⚠️ **Source of Truth Notice**
> Generated from code analysis on [date]. Supersedes legacy documentation.

## Architecture (Actual)

### External Dependencies
[From env vars with evidence]

### Module Structure
[From directory analysis]

### Data Model
[From schema files with quotes]

### API Surface
[From route extraction]

| Method | Endpoint | Handler | Evidence |
|--------|----------|---------|----------|
| GET | /api/x | Controller.method | file:line |
```

### 4.3 Import Tech Debt to Beads

```bash
# Create tech debt epic
DEBT_EPIC=$(bd create "Epic: Imported Tech Debt" -t epic -p 2 -l legacy,tech-debt --json | jq -r '.id')

# Import each TODO/FIXME
while IFS=: read -r file line content; do
  [[ -z "$content" ]] && continue
  PRIORITY=3
  TYPE="task"
  [[ "$content" =~ FIXME|BUG ]] && PRIORITY=2 && TYPE="bug"
  
  bd create "Legacy: ${content:0:80}" -t $TYPE -p $PRIORITY -l legacy,imported \
    -d "Found in $file:$line" --json
done < loa-grimoire/reality/tech-debt.txt
```

---

## Phase 5: Legacy Deprecation

### 5.1 Add Deprecation Notices

For each file in `loa-grimoire/legacy/doc-files.txt`, prepend:

```markdown
<!--
╔════════════════════════════════════════════════════════════════════╗
║  ⚠️  DEPRECATED - DO NOT UPDATE                                    ║
╠════════════════════════════════════════════════════════════════════╣
║  This document has been superseded by Loa-managed documentation.   ║
║                                                                    ║
║  Source of Truth:                                                  ║
║  • Product Requirements: loa-grimoire/prd.md                       ║
║  • System Design: loa-grimoire/sdd.md                              ║
║  • Task Tracking: Beads (.beads/)                                  ║
║                                                                    ║
║  Drift Report: loa-grimoire/drift-report.md                        ║
╚════════════════════════════════════════════════════════════════════╝
-->

```

### 5.2 Update README

Add to top of README.md:

```markdown
## 📚 Documentation

This project uses **Loa** for documentation management.

| Document | Location |
|----------|----------|
| Product Requirements | [`loa-grimoire/prd.md`](loa-grimoire/prd.md) |
| System Design | [`loa-grimoire/sdd.md`](loa-grimoire/sdd.md) |
| Task Tracking | `.beads/` (use `bd list`) |
| Drift Report | [`loa-grimoire/drift-report.md`](loa-grimoire/drift-report.md) |

> Legacy docs in `docs/` are deprecated. See files for notices.
```

---

## Phase 6: Maintenance Handoff

### 6.1 Install Drift Detection

Ensure `.claude/scripts/detect-drift.sh` exists and is executable.

### 6.2 Create Migration Tasks

```bash
MIGRATION_EPIC=$(bd create "Epic: Loa Migration Complete" -t epic -p 1 -l migration --json | jq -r '.id')

bd create "Validate PRD with stakeholders" -t task -p 2 -l migration --json
bd create "Validate SDD with team" -t task -p 2 -l migration --json
bd create "Resolve critical drift items" -t task -p 1 -l migration --json
bd create "Communicate Loa as source of truth" -t task -p 2 -l migration --json
```

### 6.3 Report Completion

Output summary:
- Files analyzed
- Docs inventoried
- Drift score
- Issues created
- Next steps

---

## Uncertainty Protocol

If code behavior is ambiguous:
1. State: "I'm uncertain about [specific aspect]"
2. Quote the ambiguous code with file:line
3. List possible interpretations
4. Ask for clarification
5. Create Beads issue tagged `needs-clarification`

**Never assume. Always ground in evidence.**
```

---

### 1.3 Create `.claude/skills/adopting-codebase/resources/drift-checklist.md`

```markdown
# Drift Analysis Checklist

## API Drift
- [ ] All documented endpoints exist in code
- [ ] All code endpoints are documented
- [ ] HTTP methods match
- [ ] URL paths match exactly
- [ ] Request/response types match

## Data Model Drift
- [ ] All documented entities exist in schema
- [ ] All schema entities are documented
- [ ] Field names match
- [ ] Field types match
- [ ] Relationships match

## Feature Drift
- [ ] All documented features have implementing code
- [ ] All code features are documented
- [ ] Feature flags match documentation
- [ ] User permissions match documentation

## Architecture Drift
- [ ] Documented services exist
- [ ] Service communication patterns match
- [ ] External dependencies match env vars
- [ ] Database technology matches

## Severity Classification

| Severity | Definition | Action |
|----------|------------|--------|
| Critical | Core feature ghost/shadow | P1 Beads issue |
| Major | Supporting feature ghost/shadow | P2 Beads issue |
| Minor | Documentation wording | P3 Beads issue |
| Info | Outdated examples | Note in drift report |
```

---

### 1.4 Create `.claude/skills/refactoring-legacy/SKILL.md`

```yaml
---
name: refactoring-legacy
description: >
  Specialized skill for refactoring established codebases. Enforces chain-of-thought
  verification, evidence-based changes, and test validation. Use when modifying
  legacy code, fixing tech debt, or modernizing patterns. Safety over speed.
allowed-tools: [Read, Write, Grep, Glob, Bash]
---
```

```markdown
# Refactoring Legacy Code

You are refactoring established code. Priority: **safety over speed**.

## Core Workflow

```
UNDERSTAND → PLAN → VERIFY → EXECUTE → VALIDATE
```

## Freedom Levels

| Change Type | Freedom | Required Steps |
|-------------|---------|----------------|
| New isolated file | High | Lint |
| New function (no side effects) | Medium | Type check, tests |
| Modify existing function | **Low** | Full protocol |
| Modify shared utility | **Very Low** | Full protocol + integration |
| Modify DB schema | **Minimal** | Full protocol + migration plan |

## Low Freedom Protocol

### Step 1: Understand

Before ANY edit, document in Beads:

```bash
bd update <task-id> --notes "ANALYSIS:
## Current Behavior
[What the code does now]

## Evidence
File: [path:lines]
\`\`\`
[actual code quote]
\`\`\`

## Original Intent
[Hypothesis - mark confidence: High/Medium/Low]

## Unknowns
- [ ] [Questions about the code]
" --json
```

### Step 2: Plan

Create modification plan:

```xml
<modification_plan>
  <file>src/path/file.ts</file>
  <lines>45-67</lines>
  
  <current_behavior>
    [What it does now]
  </current_behavior>
  
  <proposed_change>
    [What you will change]
  </proposed_change>
  
  <reasoning>
    1. [Evidence-based reason 1]
    2. [Evidence-based reason 2]
  </reasoning>
  
  <callers>
    [List all code that calls this, with file:line]
  </callers>
  
  <risks>
    - Risk: [description]
      Mitigation: [how to handle]
  </risks>
  
  <rollback>
    git checkout HEAD -- [file]
  </rollback>
</modification_plan>
```

### Step 3: Pre-Flight

```bash
# Capture baseline
npm test > /tmp/before.txt 2>&1
npm run typecheck > /tmp/types-before.txt 2>&1
```

### Step 4: Execute

Make the minimal change. One logical change per commit.

### Step 5: Post-Flight

```bash
npm test > /tmp/after.txt 2>&1
diff /tmp/before.txt /tmp/after.txt

# If ANY test fails: STOP and rollback immediately
```

### Step 6: Document

```bash
bd update <task-id> --notes "COMPLETED:
## Change Applied
[Description]

## Verification
- Tests: ✅/❌
- Types: ✅/❌
- Manual: [what was tested]

## Commit: [sha]
" --json
```

## Red Flags (Stop and Ask Human)

- Code has no tests AND >5 callers
- `// DO NOT MODIFY` or `// HACK` comments present
- Last modified >2 years ago
- Imports from >10 files
- Contains DB transactions or external API calls
- You're uncertain about behavior

When you see a red flag:
1. Document in Beads with `needs-guidance` label
2. Ask human for explicit approval
3. Do NOT proceed without response

## Discovered Issues

When refactoring reveals problems:

```bash
NEW_ID=$(bd create "Discovered: [issue]" -t bug -p 2 -l legacy,discovered --json | jq -r '.id')
bd dep add $NEW_ID <current-task-id> --type discovered-from
```
```

---

### 1.5 Create `.claude/scripts/detect-drift.sh`

```bash
#!/bin/bash
set -e

echo "🔍 Checking for documentation drift..."

DRIFT_FOUND=0

# Check schema drift
if [ -f "prisma/schema.prisma" ]; then
  CURRENT_HASH=$(md5sum prisma/schema.prisma 2>/dev/null | cut -d' ' -f1)
  RECORDED_HASH=$(grep -o 'schema_hash: [a-f0-9]*' loa-grimoire/sdd.md 2>/dev/null | cut -d' ' -f2)
  
  if [ -n "$RECORDED_HASH" ] && [ "$CURRENT_HASH" != "$RECORDED_HASH" ]; then
    echo "⚠️  Schema drift detected"
    DRIFT_FOUND=1
    bd create "Drift: Schema changed, update SDD" -t task -p 2 -l drift,auto --json 2>/dev/null || true
  fi
fi

# Check route count drift
CURRENT_ROUTES=$(grep -rn "@Get\|@Post\|@Put\|@Delete" --include="*.ts" 2>/dev/null | wc -l)
DOCUMENTED_ROUTES=$(grep -c "| GET\|| POST\|| PUT\|| DELETE" loa-grimoire/sdd.md 2>/dev/null || echo 0)

if [ "$CURRENT_ROUTES" -gt "$((DOCUMENTED_ROUTES + 5))" ]; then
  echo "⚠️  New undocumented routes detected ($CURRENT_ROUTES in code, $DOCUMENTED_ROUTES documented)"
  DRIFT_FOUND=1
  bd create "Drift: New routes need documentation" -t task -p 3 -l drift,auto --json 2>/dev/null || true
fi

# Check for new env vars
if [ -f "loa-grimoire/reality/env-vars.txt" ]; then
  CURRENT_ENVS=$(grep -roh 'process\.env\.\w\+' --include="*.ts" 2>/dev/null | sort -u | wc -l)
  RECORDED_ENVS=$(wc -l < loa-grimoire/reality/env-vars.txt 2>/dev/null || echo 0)
  
  if [ "$CURRENT_ENVS" -gt "$((RECORDED_ENVS + 2))" ]; then
    echo "⚠️  New environment variables detected"
    DRIFT_FOUND=1
  fi
fi

if [ "$DRIFT_FOUND" -eq 0 ]; then
  echo "✅ No significant drift detected"
else
  echo ""
  echo "Run /adopt --phase drift to regenerate drift report"
fi

exit 0
```

---

### 1.6 Create `.claude/scripts/validate-change-plan.sh`

```bash
#!/bin/bash
set -e

PLAN_FILE="$1"

if [ -z "$PLAN_FILE" ] || [ ! -f "$PLAN_FILE" ]; then
  echo "❌ Usage: validate-change-plan.sh <plan.json>"
  exit 1
fi

echo "🔍 Validating change plan..."

# Check all affected files exist
MISSING=0
for file in $(jq -r '.files_affected[].path' "$PLAN_FILE" 2>/dev/null); do
  if [ ! -f "$file" ]; then
    echo "❌ File not found: $file"
    MISSING=1
  else
    echo "✅ File exists: $file"
  fi
done

[ "$MISSING" -eq 1 ] && exit 1

# Check for protected files
for file in $(jq -r '.files_affected[].path' "$PLAN_FILE" 2>/dev/null); do
  if grep -q "DO NOT MODIFY\|GENERATED FILE\|AUTO-GENERATED" "$file" 2>/dev/null; then
    echo "❌ Protected file: $file"
    exit 1
  fi
done

# Check tests exist
if command -v npm &> /dev/null && [ -f "package.json" ]; then
  if ! npm test --dry-run &> /dev/null; then
    echo "⚠️  Warning: npm test may not be configured"
  fi
fi

echo "✅ Change plan validated"
exit 0
```

---

### 1.7 Create `.claude/protocols/change-validation.md`

```markdown
# Change Validation Protocol

## Purpose

Ensure modifications to established code don't break existing functionality.

## Freedom Levels

| Level | Use Case | Validation |
|-------|----------|------------|
| High | New isolated code | Lint only |
| Medium | Extensions | Type check + unit tests |
| **Low** | Modify existing | Full protocol |
| **Very Low** | Shared utilities | Full + integration tests |
| **Minimal** | DB/API changes | Full + migration + rollback test |

## Low Freedom Workflow

### 1. Generate Change Plan

Before edits, create `loa-grimoire/plans/change-<bd-id>.json`:

```json
{
  "issue_id": "bd-xxxx",
  "freedom_level": "low",
  "files_affected": [
    {"path": "src/file.ts", "lines": "45-67", "action": "modify"}
  ],
  "reasoning": "...",
  "risks": ["..."],
  "rollback": "git checkout HEAD -- src/file.ts"
}
```

### 2. Validate Plan

```bash
.claude/scripts/validate-change-plan.sh loa-grimoire/plans/change-<bd-id>.json
```

### 3. Pre-Flight Baseline

```bash
npm test > /tmp/baseline.txt 2>&1
```

### 4. Apply Changes

Minimal change, one commit.

### 5. Post-Flight Verify

```bash
npm test > /tmp/result.txt 2>&1
diff /tmp/baseline.txt /tmp/result.txt
```

### 6. Rollback if Failed

```bash
git checkout HEAD -- <affected-files>
```

## Evidence Requirements

Every change to established code must have:
- File path and line numbers
- Before/after code snippets
- Reason with evidence
- Test results before/after
- Rollback command
```

---

## PART 2: FILE UPDATES

### 2.1 Update `.claude/commands/setup.md`

Add this section **after** the existing setup phases but **before** Beads initialization:

```markdown
## Phase 0.3: Repository Mode Detection

<repo_mode_detection>

### Detect Repository Type

```bash
ESTABLISHED_SCORE=0

# Git history depth
[ $(git rev-list --count HEAD 2>/dev/null || echo 0) -gt 100 ] && ((ESTABLISHED_SCORE+=2))

# Source file count
[ $(find . -name "*.ts" -o -name "*.js" -o -name "*.py" -o -name "*.go" 2>/dev/null | head -50 | wc -l) -gt 20 ] && ((ESTABLISHED_SCORE+=2))

# Has tests
[ -d "test" ] || [ -d "tests" ] || [ -d "__tests__" ] && ((ESTABLISHED_SCORE+=1))

# Has substantial README
[ -f "README.md" ] && [ $(wc -l < README.md) -gt 50 ] && ((ESTABLISHED_SCORE+=1))

if [ $ESTABLISHED_SCORE -ge 4 ]; then
  REPO_MODE="established"
  echo "📦 Detected: Established codebase (score: $ESTABLISHED_SCORE)"
else
  REPO_MODE="greenfield"
  echo "🌱 Detected: Greenfield project (score: $ESTABLISHED_SCORE)"
fi
```

### Confirm with User

Ask: "This appears to be an **[established/greenfield]** repository. Is this correct?"

### Configure Mode

```bash
mkdir -p .claude/config
echo "repo_mode: $REPO_MODE" >> .claude/config/loa-config.yaml

if [ "$REPO_MODE" = "established" ]; then
  echo "freedom_level: low" >> .claude/config/loa-config.yaml
fi
```

### Beads Mode Selection (Established Only)

If `repo_mode: established`:

Ask: "How should Beads track issues?"
- **Team mode** (default): `bd init --quiet` - Commits to repository
- **Stealth mode**: `bd init --stealth` - Local only, not committed

```bash
if [ "$BEADS_MODE" = "stealth" ]; then
  bd init --stealth
  echo "beads_mode: stealth" >> .claude/config/loa-config.yaml
else
  bd init --quiet
  echo "beads_mode: team" >> .claude/config/loa-config.yaml
fi
```

### Post-Setup Recommendation

If `repo_mode: established`, after setup completes:

```
✅ Setup complete for established codebase.

Recommended next step:
  /adopt

This will:
• Extract documentation from actual code
• Identify drift from existing documentation  
• Import tech debt to Beads
• Establish Loa as source of truth
```

</repo_mode_detection>
```

---

### 2.2 Update `.claude/skills/implementing-tasks/SKILL.md`

Add this section:

```markdown
## Legacy Code Modification Protocol

When `repo_mode: established` or modifying existing code:

<legacy_modification_protocol>

### Before Changing ANY Existing Code

#### 1. Understand First

```bash
# Who calls this?
grep -rn "functionName" src/ --include="*.ts"

# What's the history?
git log --oneline -5 -- path/to/file.ts

# Are there tests?
find . -name "*.test.ts" -exec grep -l "functionName" {} \;
```

Document in Beads:
```bash
bd update <task-id> --notes "ANALYSIS:
## Current Behavior
[Description]

## Evidence
\`\`\`typescript
// path/to/file.ts:45
[actual code]
\`\`\`

## Callers
- file1.ts:23
- file2.ts:67

## Confidence: High/Medium/Low
" --json
```

#### 2. Create Change Plan

```xml
<modification_plan>
  <file>path/to/file.ts</file>
  <lines>45-67</lines>
  <current_behavior>...</current_behavior>
  <proposed_change>...</proposed_change>
  <reasoning>...</reasoning>
  <risks>...</risks>
  <rollback>git checkout HEAD -- path/to/file.ts</rollback>
</modification_plan>
```

#### 3. Pre-Flight Check

```bash
npm test > /tmp/before.txt 2>&1
echo "Baseline: $(grep -c 'passing' /tmp/before.txt) tests passing"
```

#### 4. Apply Change

Minimal change. One logical change per commit.

#### 5. Post-Flight Verify

```bash
npm test > /tmp/after.txt 2>&1
diff /tmp/before.txt /tmp/after.txt
# If different: STOP, investigate, possibly rollback
```

#### 6. Record Results

```bash
bd update <task-id> --notes "COMPLETED:
Tests: ✅ [X] passing
Commit: [sha]
" --json
```

### Red Flags - Stop and Ask

- No tests + many callers
- `// HACK` or `// DO NOT MODIFY` comments
- Last modified >2 years ago
- Contains transactions or external calls
- You're uncertain about behavior

```bash
bd update <task-id> --notes "RED FLAG: [description]" --json
# Ask human before proceeding
```

### Discovered Issues

```bash
NEW=$(bd create "Discovered: [issue]" -t bug -p 2 -l discovered --json | jq -r '.id')
bd dep add $NEW <current-task> --type discovered-from
```

</legacy_modification_protocol>
```

---

### 2.3 Update `.claude/skills/reviewing-code/SKILL.md`

Add this section:

```markdown
## Refactoring Review Criteria

For established codebase changes:

<refactoring_review_criteria>

### Mandatory Checks (Block if Failed)

| Check | Command | Required |
|-------|---------|----------|
| Tests pass | `npm test` | All green |
| Types valid | `npm run typecheck` | No errors |
| No removed exports | API diff | Unchanged |
| Build succeeds | `npm run build` | No errors |

### Measured Metrics (Report)

| Metric | Threshold | Check |
|--------|-----------|-------|
| Bundle size | <5% increase | Compare build output |
| Test coverage | No decrease | Coverage report |
| Complexity | No increase | Lint rules |

### Evidence Required

Every refactoring PR must include:

```markdown
## Refactoring Evidence

### Files Changed
- `path/file.ts` (lines X-Y)

### Before/After
[Code comparison]

### Verification
- [ ] Tests before: X passing
- [ ] Tests after: X passing
- [ ] Type check: ✅
- [ ] Manual test: [description]

### Rollback
`git revert <sha>`
```

### Approval Criteria

✅ Approve if:
- All mandatory checks pass
- Evidence is complete
- Change plan exists in Beads
- No red flags unaddressed

❌ Request changes if:
- Tests fail or decrease
- Missing evidence
- No change plan
- Unaddressed red flags

</refactoring_review_criteria>
```

---

### 2.4 Update `.claude/skills/auditing-security/SKILL.md`

Add this section:

```markdown
## Established Codebase Audit

<established_audit_criteria>

### Legacy-Specific Security Checks

| Check | Command | Severity |
|-------|---------|----------|
| Hardcoded secrets | `grep -rn "password=\|secret=\|apikey=" --include="*.ts"` | Critical |
| Outdated deps | `npm audit` | High |
| Deprecated APIs | Check for `@deprecated` usage | Medium |
| SQL injection | `grep -rn "query.*\\$\\|execute.*\\$"` | Critical |
| Unvalidated input | Review route handlers | High |

### Refactoring Audit Checklist

- [ ] Behavior preserved (same inputs → same outputs)
- [ ] Error handling unchanged or improved
- [ ] All callers still work
- [ ] No removed exports
- [ ] Tests exist for changed code
- [ ] No skipped tests for critical paths

### Tech Debt Assessment

During audit, create Beads issues for:
- Security vulnerabilities (P0-P1)
- Missing tests for critical paths (P2)
- Deprecated dependencies (P2)
- Code quality issues (P3)

```bash
bd create "Security: [finding]" -t bug -p 1 -l security,audit --json
```

</established_audit_criteria>
```

---

### 2.5 Update `.claude/protocols/session-end.md`

Add these sections:

```markdown
## Drift Detection (Established Repos)

If `repo_mode: established`:

```bash
# Run drift check
.claude/scripts/detect-drift.sh
```

Review any drift issues created and prioritize for next session.

## Compaction Check (Weekly)

For repos with substantial Beads history:

```bash
CLOSED_COUNT=$(bd list --status closed --json 2>/dev/null | jq 'length')

if [ "$CLOSED_COUNT" -gt 50 ]; then
  echo "📦 $CLOSED_COUNT closed issues - consider compaction"
  echo "Run: bd compact --analyze --json"
fi
```

Compaction summarizes old closed issues to save context window tokens.

## Established Repo Checklist

- [ ] All modified files have test coverage
- [ ] Change plans documented in Beads
- [ ] No red flags left unaddressed
- [ ] Drift detection run
- [ ] Discovered issues filed with `discovered-from` links
```

---

## PART 3: MAKE SCRIPTS EXECUTABLE

```bash
chmod +x .claude/scripts/detect-drift.sh
chmod +x .claude/scripts/validate-change-plan.sh
```

---

## PART 4: VERIFICATION

After implementation, run:

```bash
# Check new files exist
ls -la .claude/commands/adopt.md
ls -la .claude/skills/adopting-codebase/SKILL.md
ls -la .claude/skills/refactoring-legacy/SKILL.md
ls -la .claude/scripts/detect-drift.sh
ls -la .claude/scripts/validate-change-plan.sh
ls -la .claude/protocols/change-validation.md

# Check scripts are executable
[ -x .claude/scripts/detect-drift.sh ] && echo "✅ detect-drift.sh executable"
[ -x .claude/scripts/validate-change-plan.sh ] && echo "✅ validate-change-plan.sh executable"

# Check updates were applied
grep -q "repo_mode_detection" .claude/commands/setup.md && echo "✅ setup.md updated"
grep -q "legacy_modification_protocol" .claude/skills/implementing-tasks/SKILL.md && echo "✅ implementing-tasks updated"
grep -q "refactoring_review_criteria" .claude/skills/reviewing-code/SKILL.md && echo "✅ reviewing-code updated"
grep -q "established_audit_criteria" .claude/skills/auditing-security/SKILL.md && echo "✅ auditing-security updated"
grep -q "Drift Detection" .claude/protocols/session-end.md && echo "✅ session-end updated"
```

---

## PART 5: COMMIT

```bash
git add -A
git commit -m "feat(loa): add established codebase support

New features:
- /adopt command for migrating existing codebases to Loa
- adopting-codebase skill with 6-phase workflow
- refactoring-legacy skill with chain-of-thought verification
- Drift detection between code and documentation
- Change validation protocol with freedom levels

Updates:
- /setup now detects repo mode (greenfield vs established)
- implementing-tasks has legacy code modification protocol
- reviewing-code has refactoring criteria
- auditing-security has legacy-specific checks
- session-end has drift detection and compaction checks

This enables Loa to adopt any existing codebase and establish
Loa-maintained documentation as the single source of truth."
```

---

## Summary

After running this prompt, Loa will support:

| Capability | Implementation |
|------------|----------------|
| Repo mode detection | Auto-detect in `/setup` |
| Code reality extraction | Phase 1 of `/adopt` |
| Drift analysis | Phase 3 of `/adopt` + `detect-drift.sh` |
| Loa artifact generation | Phase 4 of `/adopt` |
| Legacy deprecation | Phase 5 of `/adopt` |
| Chain-of-thought refactoring | `refactoring-legacy` skill |
| Change validation | `change-validation.md` protocol |
| Freedom levels | Low/Very Low/Minimal for legacy |
| Tech debt import | Auto-import TODOs to Beads |
| Compaction guidance | Session-end protocol |

Run `/adopt` on any established codebase to make Loa the source of truth.