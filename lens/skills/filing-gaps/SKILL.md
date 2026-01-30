---
name: filing-gaps
description: Create GitHub/Linear issues from gap analysis reports with proper taxonomy labels. Use when you need to file a gap as a trackable issue.
user-invocable: true
allowed-tools: Read, Write, Edit, Bash, Glob
---

# Filing Gaps

Create structured issues from Laboratory gap analysis reports with proper taxonomy labels and artifact linking.

---

## Trigger

```
/file-gap {journey-id} {gap-id}              # File specific gap as issue
/file-gap {journey-id} --all                 # File all open gaps
/file-gap {journey-id} {gap-id} --provider {github|linear}  # Specify provider
/file-gap {journey-id} {gap-id} --dry-run    # Preview without creating
```

**Examples:**
```bash
/file-gap reward-understanding GAP-reward-understanding-3
/file-gap reward-understanding --all
/file-gap deposit-flow GAP-deposit-flow-1 --provider github
/file-gap reward-understanding GAP-reward-understanding-4 --dry-run
```

---

## Taxonomy Labels

Issues are tagged with a structured taxonomy for organization:

### [A] Artifact Type

| Label | Description | Use Case |
|-------|-------------|----------|
| `[A] Bug Report` | Defect in existing functionality | Code doesn't work as designed |
| `[A] Feature Request` | New functionality needed | Missing capability |
| `[A] Experiment Design` | Hypothesis to validate | Need to test before building |
| `[A] Product Spec` | Specification document | Design/scope definition |
| `[A] Tech Debt` | Technical improvement | Refactoring, optimization |

### [W] Workstream

| Label | Description | Use Case |
|-------|-------------|----------|
| `[W] Discovery` | Research and validation | Understanding user needs |
| `[W] Delivery` | Implementation work | Building features |
| `[W] Experimentation` | Hypothesis testing | A/B tests, prototypes |
| `[W] Tech Debt` | Technical improvements | Performance, maintainability |
| `[W] Operations` | Operational work | Monitoring, support |

### [J] Job-to-be-Done

Maps to user JTBD from UTC canvases:

| Label | Description |
|-------|-------------|
| `[J] Find Information` | User needs to discover/learn something |
| `[J] Reassure Me This Is Safe` | User needs trust/confidence |
| `[J] Make Transaction` | User needs to execute an action |
| `[J] Give Me Peace of Mind` | User needs ongoing assurance |
| `[J] Reduce My Anxiety` | User needs clarity about state |
| `[J] Help Me Feel Smart` | User wants to understand/verify |
| `[J] Organize Assets` | User wants control/organization |

### [LS] Learning Status

From UTC learning status of affected users:

| Label | Description |
|-------|-------------|
| `[LS] Strongly Validated` | Multiple users, high confidence |
| `[LS] Directionally Correct` | Some evidence, medium confidence |
| `[LS] Smol Evidence` | Limited data, low confidence |

### [SO] Source

| Label | Description |
|-------|-------------|
| `[SO] User Research` | From user interviews/feedback |
| `[SO] Analytics` | From usage data |
| `[SO] Code Review` | From code analysis |
| `[SO] Walkthrough` | From interactive testing |
| `[SO] Gap Analysis` | From Laboratory gap analysis |

---

## Workflow

### Step 1: Load Gap Report

Read gap report:
```bash
grimoires/crucible/gaps/{journey-id}-gaps.md
```

Parse frontmatter and find specified gap by ID.

### Step 2: Load Gap Details

For the specified gap, extract:
- Gap ID
- Type (Bug/Feature/Flow/Communication/Strategy)
- Severity (Critical/High/Medium/Low)
- JTBD impact
- User Expects (with quotes and source canvas)
- Code Does (with file:line references)
- Gap description
- Resolution recommendations

### Step 3: Load Source Canvas Context

For each linked canvas:
- Read UTC file
- Extract learning status
- Get JTBD (primary/secondary)
- Get relevant quotes

### Step 4: Map to Taxonomy Labels

**Gap Type → Artifact Type:**
| Gap Type | Artifact Label |
|----------|----------------|
| Bug | `[A] Bug Report` |
| Feature | `[A] Feature Request` |
| Flow | `[A] Feature Request` or `[A] Experiment Design` |
| Communication | `[A] Product Spec` |
| Strategy | `[A] Experiment Design` |

**Gap Severity → Priority:**
| Severity | Priority |
|----------|----------|
| Critical | P0 / Urgent |
| High | P1 / High |
| Medium | P2 / Medium |
| Low | P3 / Low |

**Gap Type → Workstream:**
| Gap Type | Workstream |
|----------|------------|
| Bug | `[W] Delivery` or `[W] Tech Debt` |
| Feature | `[W] Delivery` |
| Flow | `[W] Discovery` |
| Communication | `[W] Delivery` |
| Strategy | `[W] Discovery` or `[W] Experimentation` |

### Step 5: Generate Issue Content

**Title Format:**
```
[{Gap Type}] {Short Title}
```

**Body Template:**
```markdown
## Gap Analysis

**Journey**: {journey-id}
**Gap ID**: {gap-id}
**Severity**: {severity}
**Type**: {type}

### User Expects

> {User expectation description}
>
> Source: **{canvas-username}**, quote: "{relevant quote}"

### Code Does

> {Actual code behavior description}
>
> Source: `{file}:{line}`

### Gap Description

{Detailed description of the discrepancy}

### Proposed Resolution

{Resolution recommendations from gap report}

---

## Labels

- {Artifact label}
- {Workstream label}
- {JTBD label}
- {Learning Status label}
- `[SO] Gap Analysis`
- `laboratory`
- `{journey-id}`

---

## Evidence

### User Research

| User | Quote | Canvas |
|------|-------|--------|
| {username} | "{quote}" | [Link]({canvas-path}) |

### Code References

| File | Line | Description |
|------|------|-------------|
| {file} | {line} | {description} |

---

## Laboratory Artifacts

- **Gap Report**: `grimoires/crucible/gaps/{journey-id}-gaps.md`
- **Journey**: `grimoires/lens/journeys/{journey-id}.md`
- **Reality**: `grimoires/lens/reality/{component}-reality.md`
- **Canvas(es)**: {list of source canvases}
```

### Step 6: Output Issue Command

**For GitHub:**
```bash
gh issue create \
  --title "[{Type}] {Title}" \
  --body "$(cat <<'EOF'
{issue body content}
EOF
)" \
  --label "{label1}" \
  --label "{label2}" \
  --label "laboratory"
```

**For Linear:**
```bash
# Linear CLI command (if using linear-cli)
linear issue create \
  --title "[{Type}] {Title}" \
  --description "{issue body}" \
  --label "{label1}" \
  --priority "{priority}"
```

### Step 7: Update Gap Report

If issue created (not dry-run), update gap report:

```markdown
### Gap {N}: {Title}

...

**Linked Artifacts**:
- Canvas: `canvas/{username}.md`
- Reality: `reality/{component}-reality.md:{line}`
- Issue: `{REPO}#{NUMBER}` ← NEW
```

### Step 8: Report Output

**Dry Run:**
```
┌─────────────────────────────────────────────────────────────────┐
│ FILE GAP: DRY RUN                                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Gap: GAP-reward-understanding-3                                │
│  Type: Communication                                            │
│  Severity: Medium                                               │
│                                                                 │
│  Proposed Issue:                                                │
│  ───────────────                                                │
│  Title: [Communication] Transaction dialog lacks step context   │
│                                                                 │
│  Labels:                                                        │
│  - [A] Product Spec                                             │
│  - [W] Delivery                                                 │
│  - [J] Reassure Me This Is Safe                                 │
│  - [LS] Strongly Validated                                      │
│  - [SO] Gap Analysis                                            │
│  - laboratory                                                   │
│                                                                 │
│  Priority: P2 (Medium)                                          │
│                                                                 │
│  Body Preview:                                                  │
│  {first 200 chars of body}...                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

To create issue:
  /file-gap reward-understanding GAP-reward-understanding-3

Or manually:
  gh issue create --title "[Communication] Transaction dialog lacks step context" ...
```

**Issue Created:**
```
✓ Issue created: {REPO}#{NUMBER}

Gap: GAP-reward-understanding-3
Issue: https://github.com/{owner}/{repo}/issues/{number}

Labels Applied:
  - [A] Product Spec
  - [W] Delivery
  - [J] Reassure Me This Is Safe
  - [LS] Strongly Validated
  - [SO] Gap Analysis
  - laboratory

Gap report updated with issue link.

Next Steps:
  - View issue: gh issue view {number}
  - File next gap: /file-gap reward-understanding GAP-reward-understanding-4
  - View all gaps: Read grimoires/crucible/gaps/reward-understanding-gaps.md
```

---

## File All Mode (`--all`)

When `--all` is specified:

1. Read gap report
2. Filter to open gaps (no issue linked)
3. For each gap:
   - Generate issue content
   - Create issue (or dry-run)
   - Update gap report
4. Report summary

```
✓ Filed 3 issues

| Gap ID | Title | Issue | Priority |
|--------|-------|-------|----------|
| GAP-3 | Transaction context | #123 | P2 |
| GAP-4 | APY calculation | #124 | P1 |
| GAP-5 | Loading indicator | #125 | P3 |

Gap report updated: grimoires/crucible/gaps/reward-understanding-gaps.md
```

---

## Provider Configuration

**GitHub (default):**
- Uses `gh` CLI
- Requires `gh auth login`
- Creates issues in current repo

**Linear:**
- Uses Linear CLI or API
- Requires Linear API key
- Creates issues in configured team

**Detection:**
- Check for `.github` directory → GitHub
- Check for `linear.config.json` → Linear
- Use `--provider` flag to override

---

## Error Handling

| Error | Resolution |
|-------|------------|
| Gap not found | List available gaps in report |
| Gap report not found | Suggest running /analyze-gap first |
| Gap already filed | Show existing issue link, offer to update |
| gh CLI not found | Provide installation instructions |
| Not in git repo | Prompt for repo context |
| Auth required | Guide through `gh auth login` |

---

## Gap ID Format

Gap IDs follow the pattern:
```
GAP-{journey-id}-{number}
```

**Examples:**
- `GAP-reward-understanding-1`
- `GAP-deposit-flow-3`
- `GAP-informed-decision-2`

---

## Integration Points

- **analyzing-gaps**: Gap reports as input
- **walking-through**: Gaps discovered during walkthroughs
- **iterating-feedback**: Gap resolution tracking
- **GitHub/Linear**: Issue creation

---

## Related

- `/analyze-gap` - Create gap reports
- `/walkthrough` - Discover gaps interactively
- `/iterate` - Update artifacts after resolution
- `/diagram --with-reality` - Visualize gaps in diagrams
