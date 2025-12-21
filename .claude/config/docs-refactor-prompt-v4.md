# Loa Documentation → Modular Architecture Refactoring Prompt

<context>
You are refactoring the Loa framework's core documentation files (CLAUDE.md, PROCESS.md, README.md) to align with the 3-level modular architecture already established for agent skills. The current documentation has grown organically and now violates key principles from Anthropic's prompt engineering and agent skills guidelines.

**Current Problems:**
1. **CLAUDE.md is too large** (~1000+ lines) - triggers context warnings, loads unnecessary content into every conversation
2. **Massive duplication** - workflow phases, command tables, and agent descriptions repeated across all three files
3. **Inline scripts** - ~150 lines of bash helpers embedded in CLAUDE.md instead of externalized
4. **Protocols mixed with overview** - Git Safety (~200 lines) and Analytics (~100 lines) always load, even when irrelevant
5. **No single source of truth** - same information in multiple places risks inconsistency and hallucination

**Design Principles (from Anthropic docs):**
- CLAUDE.md = "Level 0" context, always loaded → must be minimal (~200-400 tokens)
- Detailed instructions should load on-demand when relevant triggers detected
- Single source of truth per topic prevents contradictions and hallucinations
- Put critical instructions at the beginning and end of context
- Ground responses by pointing to authoritative source documents

**Your Goal:**
Refactor into a clean hierarchy where each file has one clear purpose and content lives in exactly one place.
</context>

<target_architecture>
## File Purposes (Post-Refactor)

| File | Purpose | Target Size | Audience |
|------|---------|-------------|----------|
| **CLAUDE.md** | Quick reference for Claude Code instances | 200-300 lines | AI agent |
| **PROCESS.md** | Authoritative workflow documentation | 600-800 lines | Developers |
| **README.md** | Project introduction and quick start | 200-300 lines | New users |
| **CONTRIBUTING.md** | Contribution guidelines | Keep as-is | Contributors |

## New Files to Create

```
.claude/
├── protocols/                    # Extracted from CLAUDE.md
│   ├── git-safety.md            # Git Safety Protocol (~200 lines)
│   ├── analytics.md             # Analytics system (~100 lines)
│   └── feedback-loops.md        # A2A communication patterns (~100 lines)
├── scripts/                      # Extracted bash helpers
│   ├── detect-template.sh       # Template repository detection
│   ├── init-analytics.sh        # Analytics initialization
│   ├── check-feedback.sh        # Feedback file detection
│   ├── assess-context.sh        # Context size assessment
│   └── get-env-info.sh          # Environment detection helpers
└── references/                   # Quick lookup tables
    ├── command-matrix.md        # Full command reference
    └── threshold-matrix.md      # Parallel execution thresholds
```

## Content Ownership (Single Source of Truth)

| Content | Owner | Other Files |
|---------|-------|-------------|
| Workflow phases (detailed) | PROCESS.md | Others link to sections |
| Command reference (detailed) | PROCESS.md | Others show summary table |
| Agent descriptions | `.claude/skills/*/index.yaml` | Others list names only |
| Git Safety Protocol | `.claude/protocols/git-safety.md` | CLAUDE.md has 1-line pointer |
| Analytics system | `.claude/protocols/analytics.md` | CLAUDE.md has 1-line pointer |
| Bash helpers | `.claude/scripts/*.sh` | Docs reference by path |
| Quick start | README.md | Others link to it |
| Contributing | CONTRIBUTING.md | Others link to it |
</target_architecture>

<transformation_rules>
## Rule 1: CLAUDE.md Must Be Minimal

CLAUDE.md is loaded into EVERY Claude Code conversation. It must contain only:
- Project overview (5-10 lines)
- Directory structure (simplified tree)
- Essential conventions (10-15 lines, numbered)
- Command quick reference (table with links, no details)
- "When to load more" section (pointers to protocols/skills)
- Notes for Claude Code (5-10 lines)

**Remove from CLAUDE.md:**
- Detailed workflow phases → link to PROCESS.md
- Full command documentation → link to PROCESS.md or skill
- Git Safety Protocol → move to `.claude/protocols/git-safety.md`
- Analytics functions → move to `.claude/protocols/analytics.md`
- Bash script examples → move to `.claude/scripts/`
- Agent descriptions → already in skills, just list names
- MCP server details → move to protocols or settings docs

## Rule 2: PROCESS.md Is the Authoritative Source

PROCESS.md should be the single source of truth for:
- Detailed workflow phases (0-6)
- Complete command documentation
- A2A communication patterns
- Feedback loop details
- Phase prerequisites and outputs

**Structure for PROCESS.md:**
```markdown
# Development Process

## Overview (brief)
## Agents (list with 1-line descriptions, link to skills)
## Workflow
### Phase 0: Setup
### Phase 1: Planning
### Phase 2: Architecture
### Phase 3: Sprint Planning
### Phase 4: Implementation
### Phase 5: Review
### Phase 5.5: Sprint Security Audit
### Phase 6: Deployment
### Post-Deployment: Feedback
### Maintenance: Updates
### Ad-Hoc Commands
## Command Reference (detailed table)
## Document Artifacts
## A2A Communication
## Best Practices
```

## Rule 3: README.md Is for Humans, Not AI

README.md should help new users understand and get started:
- What is Loa? (2-3 paragraphs)
- Quick start (5 steps max)
- The agents (names and 1-line descriptions)
- Example workflow (simplified)
- Links to detailed docs

**Remove from README.md:**
- Detailed command tables (link to PROCESS.md)
- Full workflow phases (link to PROCESS.md)
- Analytics details (internal implementation)
- Repository structure (keep minimal)

## Rule 4: Extract Protocols to Load On-Demand

Create `.claude/protocols/` for content that should load only when relevant:

**git-safety.md** (load when git operations detected):
- Known Template Repositories list
- Warning Message Templates
- Step-by-Step Detection Procedure
- Detection Layers (1-4)
- Remediation Steps
- User Confirmation Flow
- Exceptions

**analytics.md** (load during /setup, /feedback, phase commands):
- Analytics Helper Functions
- Environment Detection Commands
- MCP Server Detection
- Analytics File Operations
- User Type Behavior table

**feedback-loops.md** (load during /implement, /review, /audit):
- Implementation Feedback Loop
- Sprint Security Audit Feedback Loop
- Deployment Feedback Loop
- A2A file paths and conventions

## Rule 5: Externalize Bash Scripts

Move all bash functions to `.claude/scripts/` with proper structure:

```bash
#!/bin/bash
# script-name.sh
# Purpose: One-line description
# Usage: ./script-name.sh [args]
# Returns: Expected output format

set -e  # Exit on error

# Implementation
```

**Scripts to create:**
- `detect-template.sh` - Template repository detection (4 layers)
- `init-analytics.sh` - Initialize analytics file
- `check-feedback.sh` - Check for pending feedback files
- `assess-context.sh` - Assess context size for parallel splitting
- `get-env-info.sh` - Get framework version, git user, project name

## Rule 6: Use Reference Links, Not Duplication

When content exists elsewhere, link to it:

**Good:**
```markdown
## Workflow
See [PROCESS.md](PROCESS.md) for detailed workflow documentation.

Quick reference:
1. `/setup` → Configure Loa
2. `/plan-and-analyze` → Create PRD
...
```

**Bad:**
```markdown
## Workflow
### Phase 0: Setup
[300 lines of setup details that duplicate PROCESS.md]
```

## Rule 7: Front-Load Critical Information

Per Anthropic's guidance, put the most important instructions at the beginning and end.

**CLAUDE.md structure:**
```markdown
# CLAUDE.md

## Critical Conventions (TOP - always visible)
1. Never skip phases
2. Check feedback files FIRST in /implement
3. User type in .loa-setup-complete gates features
...

## Project Overview
## Directory Structure  
## Quick Reference
## When to Load More Context
## Notes for Claude Code (BOTTOM - reinforcement)
```
</transformation_rules>

<target_claude_md>
# CLAUDE.md

This file provides guidance to Claude Code when working with the Loa framework.

## Critical Conventions

1. **Never skip phases** - each builds on the previous
2. **Check feedback FIRST** - audit feedback → engineer feedback → new work
3. **User type gates features** - check `.loa-setup-complete` for `thj` vs `oss`
4. **Single source of truth** - PROCESS.md for workflows, skills for agents
5. **A2A files preserve audit trail** - never delete `loa-grimoire/a2a/sprint-N/`

## Project Overview

Loa is an agent-driven development framework with 8 specialized agents and 14 commands that orchestrate the complete product lifecycle from requirements to deployment.

## Directory Structure

```
.claude/
├── skills/{agent}/          # Agent skills (index.yaml, SKILL.md, resources/)
├── commands/                # Slash command definitions
├── protocols/               # On-demand protocols (git-safety, analytics)
└── scripts/                 # Bash helpers

loa-grimoire/
├── prd.md, sdd.md, sprint.md    # Planning docs
├── a2a/                          # Agent-to-agent communication
│   └── sprint-N/                 # Per-sprint feedback files
├── analytics/                    # Usage tracking (THJ only)
└── deployment/                   # Infrastructure docs
```

## Command Quick Reference

| Command | Purpose | Details |
|---------|---------|---------|
| `/setup` | First-time configuration | [PROCESS.md §Phase0](PROCESS.md#phase-0-setup-setup) |
| `/plan-and-analyze` | Create PRD | [skills/prd-architect/](skills/prd-architect/) |
| `/architect` | Create SDD | [skills/architecture-designer/](skills/architecture-designer/) |
| `/sprint-plan` | Plan sprints | [skills/sprint-planner/](skills/sprint-planner/) |
| `/implement sprint-N` | Execute tasks | [skills/sprint-task-implementer/](skills/sprint-task-implementer/) |
| `/review-sprint sprint-N` | Code review | [skills/senior-tech-lead-reviewer/](skills/senior-tech-lead-reviewer/) |
| `/audit-sprint sprint-N` | Security audit | [skills/paranoid-auditor/](skills/paranoid-auditor/) |
| `/deploy-production` | Deploy | [skills/devops-crypto-architect/](skills/devops-crypto-architect/) |
| `/audit` | Codebase audit | [skills/paranoid-auditor/](skills/paranoid-auditor/) |
| `/translate @doc for audience` | Executive translation | [skills/devrel-translator/](skills/devrel-translator/) |
| `/feedback` | Submit feedback (THJ) | [PROCESS.md §Feedback](PROCESS.md#post-deployment-developer-feedback-feedback---thj-only) |
| `/update` | Pull updates | [PROCESS.md §Update](PROCESS.md#maintenance-framework-updates-update) |

## When to Load More Context

| Situation | Load This |
|-----------|-----------|
| Implementing sprint tasks | `skills/sprint-task-implementer/SKILL.md` |
| Git push/PR operations | `protocols/git-safety.md` |
| Analytics/setup/feedback | `protocols/analytics.md` |
| Understanding A2A flow | `protocols/feedback-loops.md` |
| Full workflow details | `PROCESS.md` |
| Contributing to Loa | `CONTRIBUTING.md` |

## Essential Patterns

### Feedback Priority (in /implement)
1. Check `auditor-sprint-feedback.md` FIRST (security)
2. Then check `engineer-feedback.md` (code review)
3. Address ALL feedback before new work

### Verdict Patterns
- Senior Lead: "All good" = approved
- Sprint Audit: "APPROVED - LETS FUCKING GO" = security cleared
- Sprint Audit: "CHANGES_REQUIRED" = fix security issues first

### Context Thresholds
| Agent | Split Threshold |
|-------|-----------------|
| sprint-task-implementer | >8,000 lines |
| senior-tech-lead-reviewer | >6,000 lines |
| paranoid-auditor | >5,000 lines |

## Notes for Claude Code

- Read `loa-grimoire/prd.md`, `sdd.md`, `sprint.md` for project context
- Sprint directories: `loa-grimoire/a2a/sprint-N/`
- Check user type before analytics: `cat .loa-setup-complete | grep user_type`
- For git operations, load `protocols/git-safety.md` first
- Never generate documents until confident - ask clarifying questions
- The process is designed for thoroughness, not speed
</target_claude_md>

<target_readme_md>
# Loa

[![Version](https://img.shields.io/badge/version-0.3.0-blue.svg)](CHANGELOG.md)
[![License](https://img.shields.io/badge/license-AGPL--3.0-green.svg)](LICENSE.md)

> AI agents that ride alongside you, guiding your project from idea to production.

## What is Loa?

Loa is an agent-driven development framework that orchestrates the complete product lifecycle using specialized AI agents. Eight agents work together through a structured workflow—from requirements gathering through production deployment.

While designed with crypto/blockchain projects in mind, Loa works for any software project.

## Quick Start

```bash
# 1. Clone and enter
git clone https://github.com/0xHoneyJar/loa.git
cd loa

# 2. Start Claude Code
claude

# 3. Run setup
/setup

# 4. Begin the workflow
/plan-and-analyze
```

## The Agents

| Agent | Role |
|-------|------|
| **prd-architect** | Product Manager - requirements discovery |
| **architecture-designer** | Software Architect - system design |
| **sprint-planner** | Technical PM - sprint planning |
| **sprint-task-implementer** | Senior Engineer - implementation |
| **senior-tech-lead-reviewer** | Tech Lead - code review |
| **paranoid-auditor** | Security Auditor - security review |
| **devops-crypto-architect** | DevOps - deployment |
| **devrel-translator** | DevRel - executive translation |

## The Workflow

```
/setup → /plan-and-analyze → /architect → /sprint-plan
                                              ↓
         ┌──────────────────────────────────────┐
         ↓                                      │
    /implement sprint-N                         │
         ↓                                      │
    /review-sprint sprint-N ──(feedback)────────┘
         ↓ (approved)
    /audit-sprint sprint-N ───(security issues)─┘
         ↓ (approved)
    Next sprint or /deploy-production
```

## Documentation

- **[PROCESS.md](PROCESS.md)** - Complete workflow documentation
- **[CONTRIBUTING.md](CONTRIBUTING.md)** - How to contribute
- **[CHANGELOG.md](CHANGELOG.md)** - Version history

## Key Commands

| Command | Purpose |
|---------|---------|
| `/setup` | First-time configuration |
| `/plan-and-analyze` | Create PRD |
| `/architect` | Create SDD |
| `/sprint-plan` | Plan sprints |
| `/implement sprint-N` | Execute sprint tasks |
| `/review-sprint sprint-N` | Code review |
| `/audit-sprint sprint-N` | Security audit |
| `/deploy-production` | Deploy to production |

See [PROCESS.md](PROCESS.md) for complete command reference.

## License

[AGPL-3.0](LICENSE.md) - You can use, modify, and distribute this software. If you modify and deploy it, you must release your source code.

## Links

- [Repository](https://github.com/0xHoneyJar/loa)
- [Claude Code](https://claude.ai/code)
</target_readme_md>

<protocols_to_create>
## .claude/protocols/git-safety.md

Extract from current CLAUDE.md:
- "Git Safety Protocol" section entirely
- Known Template Repositories
- Warning Message Templates (with placeholders)
- Step-by-Step Detection Procedure (flowchart)
- Template Detection Layers (1-4 with code)
- Remediation Steps (full guide)
- User Confirmation Flow
- Exceptions list

**Header for the file:**
```markdown
# Git Safety Protocol

> **When to load**: Before any `git push`, `gh pr create`, or GitHub MCP PR operations.

This protocol prevents accidental pushes to upstream template repositories.
```

## .claude/protocols/analytics.md

Extract from current CLAUDE.md:
- "Analytics System" section
- "Analytics Helper Functions" section
- Environment Detection Commands
- MCP Server Detection
- Analytics File Operations
- User Type Behavior table
- Setup Marker File Convention

**Header for the file:**
```markdown
# Analytics System

> **When to load**: During `/setup`, `/feedback`, or phase completion tracking.

Analytics are only enabled for THJ developers. OSS users skip all analytics.
```

## .claude/protocols/feedback-loops.md

Extract and consolidate:
- Implementation Feedback Loop (from CLAUDE.md)
- Sprint Security Audit Feedback Loop
- Deployment Feedback Loop
- A2A file conventions
- Priority ordering

**Header for the file:**
```markdown
# Feedback Loop Protocols

> **When to load**: During `/implement`, `/review-sprint`, `/audit-sprint`, or `/deploy-production`.

The framework uses three feedback loops for quality assurance.
```
</protocols_to_create>

<scripts_to_create>
## .claude/scripts/detect-template.sh

```bash
#!/bin/bash
# detect-template.sh
# Purpose: Detect if current repo is a fork/template of Loa
# Usage: ./detect-template.sh
# Returns: "TEMPLATE_DETECTED" or "NOT_TEMPLATE" with detection method

set -e

# Layer 1: Check cached result
if [ -f ".loa-setup-complete" ]; then
    if grep -q '"detected": *true' .loa-setup-complete 2>/dev/null; then
        echo "TEMPLATE_DETECTED|cached"
        exit 0
    fi
fi

# Layer 2: Check origin URL
ORIGIN_URL=$(git remote get-url origin 2>/dev/null || echo "")
if echo "$ORIGIN_URL" | grep -qE "(0xHoneyJar|thj-dev)/loa"; then
    echo "TEMPLATE_DETECTED|origin_url"
    exit 0
fi

# Layer 3: Check upstream/loa remote
if git remote -v 2>/dev/null | grep -E "^(upstream|loa)\s" | grep -qE "(0xHoneyJar|thj-dev)/loa"; then
    echo "TEMPLATE_DETECTED|upstream_remote"
    exit 0
fi

# Layer 4: GitHub API (if gh available)
if command -v gh &>/dev/null; then
    PARENT=$(gh repo view --json parent -q '.parent.nameWithOwner' 2>/dev/null || echo "")
    if echo "$PARENT" | grep -qE "(0xHoneyJar|thj-dev)/loa"; then
        echo "TEMPLATE_DETECTED|github_api"
        exit 0
    fi
fi

echo "NOT_TEMPLATE"
```

## .claude/scripts/check-feedback.sh

```bash
#!/bin/bash
# check-feedback.sh
# Purpose: Check for pending feedback files for a sprint
# Usage: ./check-feedback.sh sprint-1
# Returns: AUDIT_PENDING, REVIEW_PENDING, or NONE

set -e

SPRINT_ID="$1"

if [[ ! "$SPRINT_ID" =~ ^sprint-[0-9]+$ ]]; then
    echo "ERROR: Invalid sprint ID format. Expected: sprint-N" >&2
    exit 1
fi

A2A_DIR="loa-grimoire/a2a/${SPRINT_ID}"

# Check audit feedback (highest priority)
if [ -f "${A2A_DIR}/auditor-sprint-feedback.md" ]; then
    if grep -q "CHANGES_REQUIRED" "${A2A_DIR}/auditor-sprint-feedback.md"; then
        echo "AUDIT_PENDING"
        exit 0
    fi
fi

# Check engineer feedback
if [ -f "${A2A_DIR}/engineer-feedback.md" ]; then
    if ! grep -q "All good" "${A2A_DIR}/engineer-feedback.md"; then
        echo "REVIEW_PENDING"
        exit 0
    fi
fi

echo "NONE"
```

## .claude/scripts/assess-context.sh

```bash
#!/bin/bash
# assess-context.sh
# Purpose: Assess total context size for parallel splitting decision
# Usage: ./assess-context.sh [threshold]
# Returns: SMALL, MEDIUM, or LARGE

THRESHOLD=${1:-3000}

TOTAL=$(wc -l loa-grimoire/prd.md loa-grimoire/sdd.md \
        loa-grimoire/sprint.md loa-grimoire/a2a/*.md 2>/dev/null | \
        tail -1 | awk '{print $1}' || echo "0")

if [ "$TOTAL" -lt "$THRESHOLD" ]; then
    echo "SMALL|$TOTAL"
elif [ "$TOTAL" -lt $((THRESHOLD * 2)) ]; then
    echo "MEDIUM|$TOTAL"
else
    echo "LARGE|$TOTAL"
fi
```

## .claude/scripts/get-env-info.sh

```bash
#!/bin/bash
# get-env-info.sh
# Purpose: Get environment information for analytics
# Usage: ./get-env-info.sh [field]
# Fields: version, user, project, timestamp, all

FIELD="${1:-all}"

get_version() {
    if [ -f "package.json" ]; then
        grep -o '"version": *"[^"]*"' package.json | head -1 | cut -d'"' -f4
    elif [ -f "CHANGELOG.md" ]; then
        grep -o '\[[0-9]\+\.[0-9]\+\.[0-9]\+\]' CHANGELOG.md | head -1 | tr -d '[]'
    else
        echo "0.0.0"
    fi
}

get_user() {
    local name=$(git config user.name 2>/dev/null || echo "Unknown")
    local email=$(git config user.email 2>/dev/null || echo "unknown@unknown")
    echo "${name}|${email}"
}

get_project() {
    local remote=$(git remote get-url origin 2>/dev/null || echo "")
    if [ -n "$remote" ]; then
        basename -s .git "$remote"
    else
        basename "$(pwd)"
    fi
}

case "$FIELD" in
    version) get_version ;;
    user) get_user ;;
    project) get_project ;;
    timestamp) date -u +"%Y-%m-%dT%H:%M:%SZ" ;;
    all)
        echo "version=$(get_version)"
        echo "user=$(get_user)"
        echo "project=$(get_project)"
        echo "timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        ;;
    *) echo "Unknown field: $FIELD" >&2; exit 1 ;;
esac
```
</scripts_to_create>

<process_md_updates>
## Changes to PROCESS.md

PROCESS.md becomes the authoritative source. Make these adjustments:

### 1. Add Canonical Markers
At the top of each major section, add:
```markdown
<!-- CANONICAL: This is the authoritative source for [topic] -->
```

### 2. Remove Duplication Notes
Remove any "See also CLAUDE.md" references that create circular dependencies.

### 3. Consolidate A2A Documentation
Move all A2A details here from CLAUDE.md. This becomes the single source.

### 4. Keep Command Details Here
The full command documentation with all options, outputs, and error handling lives in PROCESS.md.

### 5. Link to Skills for Agent Details
Instead of duplicating agent descriptions:
```markdown
### 4. **sprint-task-implementer** (Senior Engineer)
- **Skill**: [.claude/skills/sprint-task-implementer/](.claude/skills/sprint-task-implementer/)
- **Output**: Production code + `loa-grimoire/a2a/sprint-N/reviewer.md`
```
</process_md_updates>

<validation_checklist>
## Self-Check Before Completing

### CLAUDE.md
- [ ] Under 300 lines total
- [ ] No bash function implementations (only references to scripts)
- [ ] No detailed workflow phases (links to PROCESS.md)
- [ ] No Git Safety Protocol details (links to protocol file)
- [ ] No Analytics implementation details (links to protocol file)
- [ ] Critical conventions at TOP of file
- [ ] "When to Load More" section with clear triggers
- [ ] All command entries link to PROCESS.md or skill

### README.md
- [ ] Under 300 lines total
- [ ] Clear "What is Loa?" section (2-3 paragraphs)
- [ ] Quick start is 5 steps or fewer
- [ ] Agent table is names + 1-line descriptions only
- [ ] Workflow diagram is simplified
- [ ] Links to PROCESS.md for details
- [ ] No analytics/internal implementation details

### PROCESS.md
- [ ] Is the single source for workflow phases
- [ ] Is the single source for command documentation
- [ ] Is the single source for A2A communication details
- [ ] Agent sections link to skills, not duplicate content
- [ ] Has canonical markers for authoritative sections

### Protocols
- [ ] `.claude/protocols/git-safety.md` created with full Git Safety content
- [ ] `.claude/protocols/analytics.md` created with analytics content
- [ ] `.claude/protocols/feedback-loops.md` created with A2A patterns
- [ ] Each protocol has "When to load" header

### Scripts
- [ ] All bash functions moved to `.claude/scripts/`
- [ ] Each script has: shebang, purpose comment, usage, set -e
- [ ] Scripts are referenced by path in docs, not inlined

### No Duplication
- [ ] Each piece of content exists in exactly ONE place
- [ ] Other files link to the canonical source
- [ ] No copy-paste between files
</validation_checklist>

<output_format>
Produce the following files in order:

1. **CLAUDE.md** (complete rewrite, ~250 lines)
2. **README.md** (complete rewrite, ~200 lines)
3. **PROCESS.md** (show only the changes/additions needed)
4. **.claude/protocols/git-safety.md** (extracted content)
5. **.claude/protocols/analytics.md** (extracted content)
6. **.claude/protocols/feedback-loops.md** (new consolidation)
7. **.claude/scripts/*.sh** (all scripts)
8. **Migration summary** showing:
   - Lines removed from each original file
   - Token savings estimate
   - Breaking changes (if any)
   - Files that need updating to reference new locations
</output_format>