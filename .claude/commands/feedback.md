---
name: "feedback"
version: "2.1.0"
description: |
  Submit developer feedback about Loa experience with optional execution traces.
  Creates GitHub Issues with structured format for debugging.
  Smart routing to appropriate ecosystem repo (loa, loa-constructs, forge, project).
  Open to all users (OSS-friendly).

command_type: "survey"

arguments: []

integrations: []

pre_flight: []

outputs:
  - path: "GitHub Issue"
    type: "external"
    description: "Feedback posted to GitHub"
  - path: "grimoires/loa/analytics/pending-feedback.json"
    type: "file"
    description: "Safety backup if submission fails"

mode:
  default: "foreground"
  allow_background: false
---

# Feedback

## Purpose

Collect developer feedback on the Loa experience and submit to GitHub Issues with optional execution traces for debugging. Open to all users (OSS-friendly).

## Invocation

```
/feedback
```

## Prerequisites

- None (open to all users)
- `gh` CLI recommended for direct submission (falls back to clipboard if not available)

## Workflow

### Phase 0: Check for Pending Feedback

Check if there's pending feedback from a previous failed submission:
- Check `grimoires/loa/analytics/pending-feedback.json`
- If exists and < 24h old: offer "Submit now" / "Start fresh" / "Cancel"
- If > 24h old: delete and start fresh

### Phase 0.5: Smart Routing Classification (v2.1.0)

If `feedback.routing.enabled` is true in `.loa.config.yaml`:

1. Run `.claude/scripts/feedback-classifier.sh` with conversation context
2. Get recommended repository based on signal matching
3. Present AskUserQuestion with routing options:

```yaml
questions:
  - question: "Where should this feedback be submitted?"
    header: "Route to"
    options:
      - label: "0xHoneyJar/loa (Recommended)"
        description: "Core framework - skills, commands, protocols"
      - label: "0xHoneyJar/loa-constructs"
        description: "Registry API - skill installation, licensing"
      - label: "0xHoneyJar/forge"
        description: "Sandbox - experimental constructs"
      - label: "Current project"
        description: "Project-specific issues"
    multiSelect: false
```

**Note**: The recommended option appears first with "(Recommended)" suffix per Anthropic best practices (Issue #90).

If `feedback.routing.enabled` is false, skip to Phase 1 (routes to default 0xHoneyJar/loa).

### Phase 1: Survey

Collect responses to 4 questions with progress indicators:

1. **What would you change about Loa?** (free text)
2. **What did you love about using Loa?** (free text)
3. **Rate this build vs other approaches** (1-5 scale)
4. **How comfortable was the process?** (A-E multiple choice)

### Phase 2: Regression Classification

Classify the type of issue (if applicable) using AskUserQuestion with multiSelect:

- [ ] Plan generation issue (bad plan from PRD/SDD)
- [ ] Tool selection issue (wrong tool for task)
- [ ] Tool execution issue (correct tool, wrong params)
- [ ] Context loss (forgot earlier context)
- [ ] Instruction drift (deviated from plan)
- [ ] External failure (API, permissions, etc.)
- [ ] Other

### Phase 3: Trace Collection

If trace collection is enabled in `.claude/settings.local.json`:

1. Run `.claude/scripts/collect-trace.sh` to gather execution data
2. Display summary: source count, total size, redaction count
3. Ask user via AskUserQuestion: "Include traces?" (Yes / No)

### Phase 4: User Review

Before submission:

1. Display full issue preview (title + body with formatting)
2. Offer options via AskUserQuestion:
   - "Submit as-is"
   - "Edit content" (allow modification)
   - "Remove traces" (submit survey only)
   - "Cancel"

### Phase 5: GitHub Submission

Submit to GitHub Issues using graceful label handling:

1. Check `gh` CLI availability and authentication
2. Get target repo from Phase 0.5 routing (default: `0xHoneyJar/loa`)
3. If authenticated: create issue via `.claude/scripts/gh-label-handler.sh`:
   ```bash
   gh-label-handler.sh create-issue \
       --repo {target_repo} \
       --title "{issue_title}" \
       --body "{issue_body}" \
       --labels "feedback,user-report" \
       --graceful
   ```
4. The `--graceful` flag handles missing labels by retrying without them
5. If not authenticated: clipboard fallback
   - Copy formatted body to clipboard
   - Display manual submission URL for target repo
   - Save to pending-feedback.json as backup

### Phase 6: Update Analytics

- Record submission in `grimoires/loa/analytics/usage.json`
- Delete pending-feedback.json if exists
- Display success message with issue URL

## Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| None | | |

## Outputs

| Path | Description |
|------|-------------|
| GitHub Issue | Feedback posted to target repository (auto-detected or user-selected) |
| `grimoires/loa/analytics/pending-feedback.json` | Backup if submission fails |

## Smart Routing (v2.1.0)

Feedback is automatically classified and routed to the appropriate ecosystem repo:

| Repository | Signals | When to use |
|------------|---------|-------------|
| `0xHoneyJar/loa` | `.claude/`, skills, commands, protocols, grimoires | Framework issues |
| `0xHoneyJar/loa-constructs` | registry, API, install, pack, license | Registry/API issues |
| `0xHoneyJar/forge` | experimental, sandbox, WIP | Sandbox issues |
| Current project | application, deployment, no loa keywords | Project-specific |

### Configuration

```yaml
# .loa.config.yaml
feedback:
  routing:
    enabled: true           # Enable smart routing
    auto_classify: true     # Auto-detect target repo
    require_confirmation: true  # Always ask user to confirm
  labels:
    graceful_missing: true  # Don't fail on missing labels
```

### Disabling Routing

To always route to the default repo (0xHoneyJar/loa), set:

```yaml
feedback:
  routing:
    enabled: false
```

## Survey Questions

| # | Question | Type |
|---|----------|------|
| 1 | What's one thing you would change? | Free text |
| 2 | What's one thing you loved? | Free text |
| 3 | How does this build compare? | 1-5 rating |
| 4 | How comfortable was the process? | A-E choice |

## Classification Options

| Category | Description |
|----------|-------------|
| Plan generation | PRD/SDD produced a bad plan |
| Tool selection | Wrong tool chosen for task |
| Tool execution | Right tool, wrong parameters |
| Context loss | Agent forgot earlier context |
| Instruction drift | Deviated from original plan |
| External failure | API errors, permissions, etc. |
| Other | Uncategorized issue |

## GitHub Issue Format

**Title**: `[Feedback] {short_description} - v{framework_version}`

**Body**:

```markdown
## Feedback Submission

**Framework Version**: {version}
**Submitted**: {timestamp}
**Platform**: {os}

### Classification

- [{x| }] Plan generation issue
- [{x| }] Tool selection issue
- [{x| }] Tool execution issue
- [{x| }] Context loss
- [{x| }] Instruction drift
- [{x| }] External failure
- [{x| }] Other

### Survey Responses

| Question | Response |
|----------|----------|
| What would you change? | {q1_response} |
| What did you love? | {q2_response} |
| Rating vs other approaches | {q3_rating}/5 |
| Process comfort level | {q4_choice} |

---

## Execution Trace

> Trace collection: **{enabled|disabled}** | Scope: `{scope}`

### Trajectory Summary ({entry_count} entries)

| # | Timestamp | Agent | Tool | Result |
|---|-----------|-------|------|--------|
| 1 | 10:30:00 | implementing-tasks | Read | ✓ |
| 2 | 10:30:05 | implementing-tasks | Edit | ✗ FAILURE |

<details>
<summary>Full Trajectory</summary>

```json
[...]
```

</details>

<details>
<summary>Plan at Failure</summary>

```markdown
{plan_content}
```

</details>

<details>
<summary>Sprint Ledger</summary>

```json
{ledger_json}
```

</details>

---

Submitted via Loa `/feedback` command
```

## Trace Configuration

To enable trace collection, create `.claude/settings.local.json`:

```json
{
  "feedback": {
    "collectTraces": true,
    "traceScope": "execution"
  }
}
```

See CLAUDE.md for full configuration options.

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "gh not available" | CLI not installed | Uses clipboard fallback |
| "gh not authenticated" | Not logged in | Uses clipboard fallback |
| "Submission failed" | GitHub API error | Saved to pending-feedback.json |

## Privacy

- **Opt-in only**: Traces only collected when explicitly enabled
- **Automatic redaction**: API keys, tokens, paths anonymized
- **User review**: Preview and confirm before submission
- **No telemetry**: No automatic data collection
