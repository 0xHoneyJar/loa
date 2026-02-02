# /retrospective

## Purpose

Trigger manual learning retrospective to extract reusable skills from debugging discoveries. Run at end of session or after significant implementation work.

## Invocation

```
/retrospective
/retrospective --scope implementing-tasks
/retrospective --force
```

## Agent

Activates `continuous-learning` skill from `.claude/skills/continuous-learning/`.

## Workflow

The retrospective follows a five-step process:

```
┌──────────────────────────────────────────────────────────────────┐
│                    /retrospective Workflow                        │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Step 1: Session Analysis                                        │
│  ├── Review conversation for discoveries                         │
│  ├── Identify error resolutions                                  │
│  ├── Identify workarounds implemented                            │
│  └── Identify patterns learned                                   │
│                                                                   │
│  Step 2: Quality Gate Evaluation                                 │
│  ├── For each candidate discovery:                               │
│  │   ├── Evaluate Discovery Depth                                │
│  │   ├── Evaluate Reusability                                    │
│  │   ├── Evaluate Trigger Clarity                                │
│  │   └── Evaluate Verification                                   │
│  └── Present findings with confidence levels                     │
│                                                                   │
│  Step 3: Cross-Reference Check                                   │
│  ├── Search NOTES.md Decision Log                                │
│  ├── Search NOTES.md Technical Debt                              │
│  └── Skip if exact match, link if partial                        │
│                                                                   │
│  Step 4: Skill Extraction (for approved candidates)              │
│  ├── Generate skill using template                               │
│  ├── Write to grimoires/loa/skills-pending/{name}/SKILL.md       │
│  ├── Log to trajectory                                           │
│  └── Update NOTES.md Session Continuity                          │
│                                                                   │
│  Step 5: Summary                                                 │
│  ├── List skills extracted                                       │
│  ├── List skills skipped (with reasons)                          │
│  └── Provide next steps                                          │
│                                                                   │
│  Step 6: Upstream Detection (v1.16.0+)                           │
│  ├── Run post-retrospective-hook.sh                              │
│  ├── Evaluate recent learnings for upstream eligibility          │
│  ├── Present candidates via AskUserQuestion                      │
│  └── Silent if no candidates qualify                             │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

## Options

| Option | Description | Example |
|--------|-------------|---------|
| `--scope <agent>` | Limit extraction to specific agent context | `/retrospective --scope implementing-tasks` |
| `--force` | Skip quality gate prompts (auto-approve) | `/retrospective --force` |
| `--skip-upstream-check` | Skip upstream learning detection | `/retrospective --skip-upstream-check` |

### Scope Options

| Agent | Focus |
|-------|-------|
| `implementing-tasks` | Implementation debugging, code fixes |
| `reviewing-code` | Review insights, pattern observations |
| `auditing-security` | Security patterns, vulnerability fixes |
| `deploying-infrastructure` | Infrastructure discoveries, config fixes |

## Step Details

### Step 1: Session Analysis

Scan the current conversation for discovery signals:

**Discovery Signals**:
- Error messages that were resolved
- Multiple attempts before finding solution
- "Aha!" moments or unexpected behavior
- Trial-and-error experimentation
- Configuration discoveries
- Undocumented behavior found

**Output**: List of candidate discoveries with context.

### Step 2: Quality Gate Evaluation

For each candidate, evaluate all four quality gates:

| Gate | Question | PASS Signals |
|------|----------|-------------|
| **Discovery Depth** | Was this non-obvious? | Multiple investigation steps, hypothesis changes |
| **Reusability** | Will this help future sessions? | Generalizable pattern, not one-off |
| **Trigger Clarity** | Can triggers be precisely described? | Clear error messages, specific symptoms |
| **Verification** | Was solution tested? | Confirmed working in session |

**Output**: Table of candidates with gate assessment (PASS/FAIL for each).

### Step 3: Cross-Reference Check

Before extraction, check NOTES.md for existing coverage:

```markdown
## NOTES.md Sections to Check
- `## Learnings` - Existing patterns
- `## Decisions` - Architecture choices that cover this
- `## Technical Debt` - Known issues related to discovery
```

**Actions**:
- **Exact match found**: Skip extraction, note existing coverage
- **Partial match found**: Link to existing entry, consider updating
- **No match found**: Proceed with extraction

### Step 4: Skill Extraction

For approved candidates that pass all gates:

1. **Create Directory**: `grimoires/loa/skills-pending/{skill-name}/`
2. **Generate SKILL.md**: Use template from `.claude/skills/continuous-learning/resources/skill-template.md`
3. **Log to Trajectory**: Write extraction event to `grimoires/loa/a2a/trajectory/continuous-learning-{date}.jsonl`
4. **Update NOTES.md**: Add entry to `## Learnings` section

**Trajectory Entry**:
```json
{
  "timestamp": "2026-01-18T14:30:00Z",
  "type": "extraction",
  "agent": "implementing-tasks",
  "phase": "retrospective",
  "skill_name": "example-skill-name",
  "quality_gates": {
    "discovery_depth": {"status": "PASS"},
    "reusability": {"status": "PASS"},
    "trigger_clarity": {"status": "PASS"},
    "verification": {"status": "PASS"}
  },
  "outcome": "created",
  "output_path": "grimoires/loa/skills-pending/example-skill-name/SKILL.md"
}
```

### Step 5: Summary

Present extraction report:

```markdown
## Retrospective Summary

### Skills Extracted
| Skill | Agent | Gate Results |
|-------|-------|--------------|
| nats-consumer-durable | implementing-tasks | 4/4 PASS |

### Skills Skipped
| Candidate | Reason |
|-----------|--------|
| config-typo-fix | Failed: Reusability (one-off) |

### Next Steps
- Review pending skills: `/skill-audit --pending`
- Approve skills: `/skill-audit --approve <name>`
```

## NOTES.md Integration

### Adding Learnings Entry

When a skill is extracted, add to NOTES.md:

```markdown
## Learnings
- [NATS JetStream] Durable consumers required for restart persistence → See `skills-pending/nats-consumer-durable`
```

### Checking for Duplicates

Before extraction, grep NOTES.md for related terms:

```bash
grep -i "keyword" grimoires/loa/NOTES.md
```

## Example Conversation Flow

```
User: /retrospective

Agent: Starting retrospective analysis...

## Step 1: Session Analysis

Scanning conversation for discoveries...

Found 3 potential candidates:

1. **NATS Consumer Restart Issue**
   - Context: Messages lost after process restart
   - Resolution: Added durable consumer name

2. **TypeScript Type Narrowing**
   - Context: Type guard not working as expected
   - Resolution: Used `in` operator instead of `typeof`

3. **Config Typo**
   - Context: Service failed to start
   - Resolution: Fixed environment variable name

## Step 2: Quality Gate Evaluation

| # | Candidate | Depth | Reuse | Trigger | Verify | Overall |
|---|-----------|-------|-------|---------|--------|---------|
| 1 | NATS Consumer | ✓ | ✓ | ✓ | ✓ | PASS |
| 2 | TypeScript Type | ✓ | ✓ | ✓ | ✓ | PASS |
| 3 | Config Typo | ✗ | ✗ | ✗ | ✓ | FAIL |

Candidate #3 failed: Simple typo fix, not reusable.

## Step 3: Cross-Reference Check

Checking NOTES.md for existing coverage...

- NATS Consumer: No existing entry → Proceed
- TypeScript Type: Found partial in Learnings → Will link

## Step 4: Extraction

Extracting 1 new skill:

✓ Created: grimoires/loa/skills-pending/nats-consumer-durable/SKILL.md
✓ Logged to trajectory
✓ Updated NOTES.md Learnings

Skipping TypeScript Type (linked to existing entry)

## Step 5: Summary

### Extraction Complete

| Action | Count |
|--------|-------|
| Extracted | 1 |
| Linked | 1 |
| Skipped | 1 |

**Next Steps**:
- Review: `/skill-audit --pending`
- Approve: `/skill-audit --approve nats-consumer-durable`
```

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "No discoveries found" | Clean session | Normal - no action needed |
| "NOTES.md not found" | Missing file | Create from template |
| "skills-pending/ not accessible" | Permissions | Check directory exists |
| "Trajectory write failed" | Directory missing | Create trajectory directory |

## Configuration

Options in `.loa.config.yaml`:

```yaml
continuous_learning:
  enabled: true              # Master toggle
  auto_extract: false        # Require confirmation (recommended)
  retrospective:
    default_scope: null      # Default to all agents
    skip_cross_reference: false  # Always check NOTES.md
```

## Step 6: Upstream Detection (v1.16.0+)

After retrospective completes, the upstream detection hook automatically runs:

```bash
.claude/scripts/post-retrospective-hook.sh --session-only --json
```

This hook:
1. Scans recent learnings from the current session
2. Evaluates each against upstream eligibility thresholds
3. Presents qualifying candidates via AskUserQuestion
4. Is completely silent if no candidates qualify

### Eligibility Thresholds

| Criterion | Threshold | Configurable |
|-----------|-----------|--------------|
| Upstream Score | ≥ 70 | `.upstream_detection.min_upstream_score` |
| Applications | ≥ 3 | `.upstream_detection.min_occurrences` |
| Success Rate | ≥ 80% | `.upstream_detection.min_success_rate` |

### Disabling Upstream Detection

Use `--skip-upstream-check` to bypass this step:

```bash
/retrospective --skip-upstream-check
```

Or disable globally in `.loa.config.yaml`:

```yaml
upstream_detection:
  enabled: false
```

### When Candidates Are Found

If learnings qualify, you'll see options like:

```
Upstream Learning Candidates Detected
─────────────────────────────────────────

The following learnings qualify for upstream proposal:

  • L-0001: Three-Zone Model prevents framework pollution
    Score: 78/100

  • L-0003: JIT retrieval reduces context bloat
    Score: 75/100

─────────────────────────────────────────

Would you like to propose any of these learnings?

  1. Propose L-0001
  2. Propose L-0003
  3. Skip for now
```

## Related Commands

| Command | Purpose |
|---------|---------|
| `/skill-audit --pending` | Review extracted skills |
| `/skill-audit --approve` | Approve a skill |
| `/implement` | Primary discovery context |
| `/propose-learning` | Submit learning as upstream proposal |
| `/compound` | Cross-session learning synthesis |

## Protocol Reference

See `.claude/protocols/continuous-learning.md` for:
- Detailed quality gate criteria
- Zone compliance rules
- Trajectory schema

See `grimoires/loa/prd.md` (Upstream Learning Flow) for:
- Full proposal workflow
- Anonymization requirements
- Maintainer acceptance criteria
