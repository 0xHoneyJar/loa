# Riding Through the Codebase

You are analyzing an existing codebase to generate evidence-grounded Loa artifacts following the v0.6.0 Enterprise-Grade Managed Scaffolding model.

> *"The Loa rides through the code, channeling truth into the grimoire."*

## Core Principles

```
CODE IS TRUTH → Loa channels CODE → Grimoire reflects REALITY
```

1. **Never trust documentation** - Verify everything against code
2. **Flag, don't fix** - Dead code/issues flagged for human decision
3. **Evidence required** - Every claim needs `file:line` citation
4. **Target repo awareness** - Grimoire lives WITH the code it documents

---

## Phase 0: Preflight & Mount Verification

### 0.1 Verify Loa is Mounted

```bash
if [[ ! -f ".loa-version.json" ]]; then
  echo "❌ Loa not mounted on this repository"
  echo ""
  echo "The Loa must mount before it can ride."
  echo "Run '/mount' first, or:"
  echo "  curl -fsSL https://raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/scripts/mount-loa.sh | bash"
  exit 1
fi

VERSION=$(jq -r '.framework_version' .loa-version.json)
echo "✓ Loa mounted (v$VERSION)"
```

### 0.2 System Zone Integrity Check (BLOCKING)

Before the Loa can ride, verify the System Zone hasn't been tampered with:

```bash
CHECKSUMS_FILE=".claude/checksums.json"
FORCE_RESTORE="${1:-false}"

if [[ ! -f "$CHECKSUMS_FILE" ]]; then
  echo "⚠️ No checksums found - skipping integrity check (first ride?)"
else
  echo "🔐 Verifying System Zone integrity..."

  DRIFT_DETECTED=false
  DRIFTED_FILES=()

  while IFS= read -r file; do
    expected=$(jq -r --arg f "$file" '.files[$f] // empty' "$CHECKSUMS_FILE")
    [[ -z "$expected" ]] && continue

    if [[ -f "$file" ]]; then
      actual=$(sha256sum "$file" | cut -d' ' -f1)
      if [[ "$expected" != "$actual" ]]; then
        DRIFT_DETECTED=true
        DRIFTED_FILES+=("$file")
      fi
    else
      DRIFT_DETECTED=true
      DRIFTED_FILES+=("$file (MISSING)")
    fi
  done < <(jq -r '.files | keys[]' "$CHECKSUMS_FILE")

  if [[ "$DRIFT_DETECTED" == "true" ]]; then
    echo ""
    echo "╔═════════════════════════════════════════════════════════════════╗"
    echo "║  ⛔ SYSTEM ZONE INTEGRITY VIOLATION                             ║"
    echo "╚═════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "The following framework files have been modified:"
    for f in "${DRIFTED_FILES[@]}"; do
      echo "  ✗ $f"
    done
    echo ""
    echo "The Loa cannot ride with a corrupted saddle."
    echo ""
    echo "Options:"
    echo "  1. Move customizations to .claude/overrides/ (recommended)"
    echo "  2. Run '/ride --force-restore' to reset System Zone"
    echo "  3. Run '/update --force-restore' to sync from upstream"
    echo ""

    if [[ "$FORCE_RESTORE" == "--force-restore" ]]; then
      echo "Force-restoring System Zone from upstream..."
      git checkout loa-upstream/main -- .claude 2>/dev/null || {
        echo "❌ Failed to restore - run '/mount' to reinstall"
        exit 1
      }
      echo "✓ System Zone restored"
    else
      echo "❌ BLOCKED: Use --force-restore to override"
      exit 1
    fi
  else
    echo "✓ System Zone integrity verified"
  fi
fi
```

### 0.3 Detect Execution Context

```bash
CURRENT_DIR=$(pwd)
CURRENT_REPO=$(basename "$CURRENT_DIR")

# Check if we're in the Loa framework repo
if [[ -f ".claude/commands/ride.md" ]] && [[ -d ".claude/skills/riding-codebase" ]]; then
  IS_FRAMEWORK_REPO=true
  echo "📍 Detected: Running from Loa framework repository"
else
  IS_FRAMEWORK_REPO=false
  TARGET_REPO="$CURRENT_DIR"
  echo "📍 Detected: Running from project repository"
fi
```

### 0.4 Target Resolution (Framework Repo Only)

If `IS_FRAMEWORK_REPO=true`, use `AskUserQuestion` to select target:

```markdown
## Target Repository Required

You're running /ride from the Loa framework repo.

**Which codebase should the Loa ride?**

Options:
1. Specify path: `/ride --target ../thj-envio`
2. Select sibling repo: [list siblings]

⚠️ The Loa rides codebases, not itself.
```

### 0.5 Initialize Ride Trajectory

```bash
RIDE_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TRAJECTORY_FILE="loa-grimoire/a2a/trajectory/riding-$(date +%Y%m%d).jsonl"
mkdir -p loa-grimoire/a2a/trajectory

echo '{"timestamp":"'$RIDE_DATE'","agent":"riding-codebase","phase":0,"action":"preflight","status":"complete"}' >> "$TRAJECTORY_FILE"
```

---

## Phase 1: Interactive Context Discovery

### 1.1 Check for Existing Context

```bash
if [[ -d "loa-grimoire/context" ]] && [[ "$(ls -A loa-grimoire/context 2>/dev/null)" ]]; then
  echo "📚 Found existing context in loa-grimoire/context/"
  find loa-grimoire/context -type f \( -name "*.md" -o -name "*.txt" \) | while read f; do
    echo "  - $f ($(wc -l < "$f") lines)"
  done
  CONTEXT_EXISTS=true
else
  CONTEXT_EXISTS=false
fi
```

### 1.2 Context File Prompt

Inform the user about context files using `AskUserQuestion`:

```markdown
## 📚 Context Files

Before we begin the interview, you can add any existing documentation to:

    loa-grimoire/context/

Supported formats:
- Architecture docs, diagrams, decision records
- Stakeholder interviews, requirements docs
- Tribal knowledge, onboarding notes
- Roadmaps, sprint plans, tech debt lists
- Any .md, .txt, or .pdf files

**Why this matters**: I'll analyze these files first and skip questions
you've already answered. This saves time and focuses the interview on
gaps in my understanding.

Would you like to add context files now, or proceed with the interview?
```

### 1.3 Analyze Existing Context (Pre-Interview)

If context files exist, analyze them BEFORE the interview to generate `context-coverage.md`:

```markdown
# Context Coverage Analysis

> Pre-interview analysis of user-provided context

## Files Analyzed
| File | Type | Key Topics Covered |
|------|------|-------------------|
| architecture-notes.md | Architecture | Tech stack, module boundaries, data flow |
| tribal-knowledge.md | Tribal | Gotchas, unwritten rules |

## Topics Already Covered (will skip in interview)
- ✅ Tech stack (from architecture-notes.md)
- ✅ Known gotchas (from tribal-knowledge.md)

## Gaps to Explore in Interview
- ❓ Business priorities and critical features
- ❓ User types and permissions model
- ❓ Planned vs abandoned WIP code

## Claims Extracted (to verify against code)
| Claim | Source | Verification Strategy |
|-------|--------|----------------------|
| "Uses PostgreSQL with pgvector" | architecture-notes.md | Check DATABASE_URL, imports |
```

### 1.4 Interactive Discovery (Gap-Focused Interview)

Use `AskUserQuestion` tool for each topic, focusing on gaps. Skip questions already answered by context files.

**Interview Topics:**

1. **Architecture Understanding**
   - What is this project? (one sentence)
   - What's the primary tech stack?
   - How is the codebase organized?
   - What are the main entry points?

2. **Domain Knowledge**
   - What are the core domain entities?
   - What external services does this integrate with?
   - Are there feature flags or environment-specific behaviors?

3. **Tribal Knowledge (Critical)**
   - What's surprising or counterintuitive about this codebase?
   - What would break if someone didn't know the unwritten rules?
   - Are there areas that "just work" and shouldn't be touched?
   - What's the scariest part of the codebase?

4. **Work in Progress**
   - Is there intentionally incomplete code?
   - What's planned but not implemented yet?

5. **History**
   - How old is this codebase?
   - Has the architecture changed significantly over time?

### 1.5 Generate Claims to Verify

Create `loa-grimoire/context/claims-to-verify.md`:

```markdown
# Claims to Verify Against Code

> Generated from context discovery interview
> These are HYPOTHESES, not facts. Code is truth.

## Architecture Claims
| Claim | Source | Verification Strategy |
|-------|--------|----------------------|
| "Uses PostgreSQL" | Interview Q2 | Check DATABASE_URL, imports |

## Domain Claims
| Claim | Source | Verification Strategy |
|-------|--------|----------------------|
| "HenloProfile is main entity" | Interview Q5 | Grep for entity definitions |

## Tribal Knowledge (Handle Carefully)
| Claim | Source | Verification Strategy |
|-------|--------|----------------------|
| "Don't modify badge handler" | Interview Q10 | Check for warnings in code |
```

### 1.6 Tool Result Clearing Checkpoint

After context discovery, clear raw interview data and summarize:

```markdown
## Context Discovery Summary (for active context)

Captured [N] claims to verify from user interview.
Full details written to: loa-grimoire/context/claims-to-verify.md

Key areas to investigate:
- [Top 3 architectural claims]
- [Top 3 tribal knowledge items]

Raw interview responses cleared from context.
```

---

## Phase 2: Code Reality Extraction

### 2.1 Setup

```bash
mkdir -p loa-grimoire/reality
cd "$TARGET_REPO"
```

### 2.2 Directory Structure Analysis

```bash
echo "## Directory Structure" > loa-grimoire/reality/structure.md
echo '```' >> loa-grimoire/reality/structure.md
find . -type d -maxdepth 4 \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -not -path "*/dist/*" \
  -not -path "*/build/*" \
  -not -path "*/__pycache__/*" \
  2>/dev/null >> loa-grimoire/reality/structure.md
echo '```' >> loa-grimoire/reality/structure.md
```

### 2.3 Entry Points & Routes

```bash
grep -rn "@Get\|@Post\|@Put\|@Delete\|@Patch\|router\.\|app\.\(get\|post\|put\|delete\|patch\)\|@route\|@api" \
  --include="*.ts" --include="*.js" --include="*.py" --include="*.go" 2>/dev/null \
  > loa-grimoire/reality/api-routes.txt

ROUTE_COUNT=$(wc -l < loa-grimoire/reality/api-routes.txt 2>/dev/null || echo 0)
echo "Found $ROUTE_COUNT route definitions"
```

### 2.4 Data Models & Entities

```bash
grep -rn "model \|@Entity\|class.*Entity\|CREATE TABLE\|type.*struct\|interface.*{\|type.*=" \
  --include="*.prisma" --include="*.ts" --include="*.sql" --include="*.go" --include="*.graphql" 2>/dev/null \
  > loa-grimoire/reality/data-models.txt
```

### 2.5 Environment Dependencies

```bash
grep -roh 'process\.env\.\w\+\|os\.environ\[.\+\]\|os\.Getenv\(.\+\)\|env\.\w\+\|import\.meta\.env\.\w\+' \
  --include="*.ts" --include="*.js" --include="*.py" --include="*.go" 2>/dev/null \
  | sort -u > loa-grimoire/reality/env-vars.txt
```

### 2.6 Tech Debt Markers

```bash
grep -rn "TODO\|FIXME\|HACK\|XXX\|BUG\|@deprecated\|eslint-disable\|@ts-ignore\|type: any" \
  --include="*.ts" --include="*.js" --include="*.py" --include="*.go" 2>/dev/null \
  > loa-grimoire/reality/tech-debt.txt
```

### 2.7 Test Coverage Detection

```bash
find . -type f \( -name "*.test.ts" -o -name "*.spec.ts" -o -name "*_test.go" -o -name "test_*.py" \) \
  -not -path "*/node_modules/*" 2>/dev/null > loa-grimoire/reality/test-files.txt

TEST_COUNT=$(wc -l < loa-grimoire/reality/test-files.txt 2>/dev/null || echo 0)

if [[ "$TEST_COUNT" -eq 0 ]]; then
  echo "⚠️ NO TESTS FOUND - This is a significant gap"
fi
```

### 2.8 Tool Result Clearing Checkpoint (MANDATORY)

After all extractions complete, **clear raw tool outputs** from active context:

```markdown
## Phase 2 Extraction Summary (for active context)

Reality extraction complete. Results synthesized to loa-grimoire/reality/:
- Routes: [N] definitions → reality/api-routes.txt
- Entities: [N] models → reality/data-models.txt
- Env vars: [N] dependencies → reality/env-vars.txt
- Tech debt: [N] markers → reality/tech-debt.txt
- Tests: [N] files → reality/test-files.txt

⚠️ RAW TOOL OUTPUTS CLEARED FROM CONTEXT
Refer to reality/ files for specific file:line details.
```

---

## Phase 2b: Code Hygiene Audit

### Purpose

Flag potential issues for HUMAN DECISION - do not assume intent or prescribe fixes.

### 2b.1 Files Outside Standard Directories

Generate `loa-grimoire/reality/hygiene-report.md`:

```markdown
# Code Hygiene Audit

## Files Outside Standard Directories
| Location | Type | Question for Human |
|----------|------|-------------------|
| `script.js` (root) | Script | Move to `scripts/` or intentional? |

## Potential Temporary/WIP Folders
| Folder | Files | Question |
|--------|-------|----------|
| `.temp_wip/` | 15 files | WIP for future, or abandoned? |

## Commented-Out Import/Code Blocks
| Location | Question |
|----------|----------|
| src/handlers/badge.ts:45 | Remove or waiting on fix? |

## Potential Dependency Conflicts
⚠️ Both `ethers` and `viem` present - potential conflict or migration in progress?
```

### 2b.2 Dead Code Philosophy

```markdown
## ⚠️ Important: Dead Code Philosophy

Items flagged above are for **HUMAN DECISION**, not automatic fixing.

When you see potential dead code:
✅ Ask: "What's the status of this?"
❌ Don't assume: "This needs to be fixed and integrated"

Possible dispositions:
- **Keep (WIP)**: Intentionally incomplete, will be finished
- **Keep (Reference)**: Useful for copy-paste or learning
- **Archive**: Move to `_archive/` folder
- **Delete**: Confirmed abandoned

Add disposition decisions to `loa-grimoire/NOTES.md` Decision Log.
```

---

## Phase 3: Legacy Documentation Inventory

### 3.1 Find All Documentation

```bash
mkdir -p loa-grimoire/legacy

find . -type f \( -name "*.md" -o -name "*.rst" -o -name "*.txt" -o -name "*.adoc" \) \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -not -path "*/loa-grimoire/*" \
  2>/dev/null > loa-grimoire/legacy/doc-files.txt
```

### 3.2 Assess AI Guidance Quality (CLAUDE.md)

```bash
if [[ -f "CLAUDE.md" ]]; then
  LINES=$(wc -l < CLAUDE.md)
  HAS_TECH_STACK=$(grep -ci "stack\|framework\|language\|database" CLAUDE.md || echo 0)
  HAS_PATTERNS=$(grep -ci "pattern\|convention\|style" CLAUDE.md || echo 0)
  HAS_WARNINGS=$(grep -ci "warning\|caution\|don't\|avoid" CLAUDE.md || echo 0)

  SCORE=0
  [[ $LINES -gt 50 ]] && ((SCORE+=2))
  [[ $HAS_TECH_STACK -gt 0 ]] && ((SCORE+=2))
  [[ $HAS_PATTERNS -gt 0 ]] && ((SCORE+=2))
  [[ $HAS_WARNINGS -gt 0 ]] && ((SCORE+=1))

  # Score out of 7 - below 5 is insufficient
fi
```

### 3.3 Create Inventory

Create `loa-grimoire/legacy/INVENTORY.md` listing all docs with type and key claims.

---

## Phase 4: Three-Way Drift Analysis

### 4.1 Drift Categories

| Category | Definition |
|----------|------------|
| **Ghost** | Documented/claimed but doesn't exist in code |
| **Shadow** | Exists in code but not documented |
| **Aligned** | Documentation matches code |
| **Conflict** | Context AND docs claim X, code shows Y |

### 4.2 Generate Drift Report

Create `loa-grimoire/drift-report.md`:

```markdown
# Three-Way Drift Report

> Generated: [timestamp]
> Target: [repo path]

## Truth Hierarchy Reminder

```
CODE wins every conflict. Always.
```

## Summary

| Category | Code Reality | Legacy Docs | User Context | Aligned |
|----------|--------------|-------------|--------------|---------|
| API Endpoints | X | Y | Z | W% |
| Data Models | X | Y | Z | W% |
| Features | X | Y | Z | W% |

## Drift Score: X% (lower is better)

## Critical Drift Items

### Ghosts (Documented/Claimed but Missing in Code)
| Item | Claimed By | Evidence Searched | Verdict |
|------|------------|-------------------|---------|
| "Feature X" | legacy/api.md | `grep -r "FeatureX"` found nothing | ❌ GHOST |

### Shadows (In Code but Undocumented)
| Item | Location | Needs Documentation |
|------|----------|---------------------|
| RateLimiter | src/middleware/rate.ts:45 | Yes - critical infrastructure |

### Conflicts (Context + Docs disagree with Code)
| Claim | Sources | Code Reality | Confidence |
|-------|---------|--------------|------------|
| "Uses PostgreSQL" | context + legacy | MySQL in DATABASE_URL | HIGH |
```

---

## Phase 5: Consistency Analysis

Generate `loa-grimoire/consistency-report.md`:

```markdown
# Consistency Analysis

## Naming Patterns Detected

### Entity Naming
| Pattern | Count | Examples |
|---------|-------|----------|
| `{Domain}{Type}` | 15 | `SFPosition`, `SFVaultStats` |
| `{Type}` only | 8 | `Transfer`, `Mint` |

## Consistency Score: X/10

## Improvement Opportunities (Non-Breaking)
| Change | Type | Impact |
|--------|------|--------|
| Add `Event` suffix to event entities | ✅ Additive | GraphQL schema addition |

## Breaking Changes (Flag Only)
| Change | Why Breaking | Impact |
|--------|--------------|--------|
| Rename `Mint` → `MintEvent` | GraphQL queries break | Downstream consumers |
```

---

## Phase 6: Loa Artifact Generation

### 6.1 Generate PRD

Create `loa-grimoire/prd.md` with evidence-grounded content:

```markdown
# Product Requirements Document

> ⚠️ **Source of Truth Notice**
> Generated from code analysis on [date].
> All claims cite `file:line` evidence.

## Document Metadata
| Field | Value |
|-------|-------|
| Generated | [timestamp] |
| Source | Code reality extraction |
| Drift Score | X% |

## User Types
[From actual role/permission code with evidence]

### User Type: [Name]
- **Evidence**: `src/auth/roles.ts:23`
- **Permissions**: [list from code]

## Features (Code-Verified)

### Feature: [Name]
- **Status**: Active in code
- **Evidence**: `src/features/x/index.ts:1-50`
- **Endpoints**: [from api-routes.txt]
```

### 6.2 Generate SDD

Create `loa-grimoire/sdd.md` with architecture evidence:

```markdown
# System Design Document

> ⚠️ **Source of Truth Notice**
> Generated from code analysis on [date].

## Architecture (As-Built)

### Tech Stack (Verified)
| Component | Technology | Evidence |
|-----------|------------|----------|
| Runtime | Node.js | `package.json:engines` |
| Database | [from env vars] | `DATABASE_URL` pattern |

### Module Structure
[From directory analysis with actual paths]

### Data Model
[From data-models.txt with schema quotes]

### API Surface
| Method | Endpoint | Handler | Evidence |
|--------|----------|---------|----------|
| GET | /api/x | Controller.method | file:line |
```

---

## Phase 7: Governance Audit

Generate `loa-grimoire/governance-report.md`:

```markdown
# Governance & Release Audit

| Artifact | Status | Impact |
|----------|--------|--------|
| CHANGELOG.md | ❌ Missing | No version history |
| CONTRIBUTING.md | ❌ Missing | Unclear contribution process |
| SECURITY.md | ❌ Missing | No security disclosure policy |
| CODEOWNERS | ❌ Missing | No required reviewers |
| Semver tags | ❌ None | No release versioning |
```

---

## Phase 8: Legacy Deprecation

For each file in legacy/doc-files.txt, prepend deprecation notice:

```html
<!--
╔════════════════════════════════════════════════════════════════════╗
║  ⚠️  DEPRECATED - DO NOT UPDATE                                    ║
╠════════════════════════════════════════════════════════════════════╣
║  This document has been superseded by Loa-managed documentation.   ║
║                                                                    ║
║  Source of Truth:                                                  ║
║  • Product Requirements: loa-grimoire/prd.md                       ║
║  • System Design: loa-grimoire/sdd.md                              ║
║                                                                    ║
║  Drift Report: loa-grimoire/drift-report.md                        ║
╚════════════════════════════════════════════════════════════════════╝
-->
```

---

## Phase 9: Trajectory Self-Audit

Generate `loa-grimoire/trajectory-audit.md`:

```markdown
## Trajectory Audit Summary

| Metric | Count | Status |
|--------|-------|--------|
| Total steps logged | X | ✓ |
| Grounded claims | Y | ✓ |
| Inferred claims | Z | ⚠️ Review recommended |
| Ungrounded claims | W | ❌ Must be flagged as [ASSUMPTION] |

### Reasoning Quality Score: X/10
```

### Grounding Categories

| Category | Marker | Requirement |
|----------|--------|-------------|
| **Grounded** | `(file.ts:L45)` | Direct code citation |
| **Inferred** | `[INFERRED: ...]` | Logical deduction from multiple sources |
| **Assumption** | `[ASSUMPTION: ...]` | No direct evidence - requires validation |

---

## Phase 10: Maintenance Handoff

### 10.1 Update NOTES.md

```markdown
## Session Continuity
| Timestamp | Agent | Summary |
|-----------|-------|---------|
| [now] | riding-codebase | Completed /ride workflow |

## Ride Results
- Routes documented: X
- Entities documented: Y
- Tech debt imported: Z
- Drift score: W%
- Governance gaps: N items
```

### 10.2 Completion Summary

```markdown
╔═════════════════════════════════════════════════════════════════╗
║  ✓ The Loa Has Ridden                                           ║
╚═════════════════════════════════════════════════════════════════╝

### Grimoire Artifacts Created
- loa-grimoire/prd.md (Product truth)
- loa-grimoire/sdd.md (System truth)
- loa-grimoire/drift-report.md (Three-way analysis)
- loa-grimoire/consistency-report.md (Pattern analysis)
- loa-grimoire/governance-report.md (Process gaps)
- loa-grimoire/reality/* (Raw extractions)

### Next Steps
1. Review drift-report.md for critical issues
2. Address governance gaps
3. Schedule stakeholder PRD review
4. Run `/implement` for high-priority drift

The code truth has been channeled. The grimoire reflects reality.
```

---

## Uncertainty Protocol

If code behavior is ambiguous:

1. State: "I'm uncertain about [specific aspect]"
2. Quote the ambiguous code with `file:line`
3. List possible interpretations
4. Ask for clarification via `AskUserQuestion`
5. Log uncertainty in `NOTES.md`

**Never assume. Always ground in evidence.**

---

## Trajectory Logging

Log each phase to `loa-grimoire/a2a/trajectory/riding-{date}.jsonl`:

```json
{"timestamp": "...", "agent": "riding-codebase", "phase": 2, "action": "code_extraction", "output_summary": "Found 47 routes, 60 entities", "next_action": "Phase 2b hygiene audit"}
```
