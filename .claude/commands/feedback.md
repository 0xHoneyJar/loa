---
name: "feedback"
version: "3.0.0"
description: |
  Submit developer feedback about Loa experience with optional execution traces.
  Creates GitHub Issues with structured format for debugging.
  Smart routing to appropriate ecosystem repo (loa, loa-constructs, forge, project).
  Construct-aware routing files issues on construct vendor repos with content redaction.
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

#### Phase 0.5b: Construct Routing (v3.0.0)

When the classifier returns `classification: "construct"`:

1. **Dedup check**: Read `.run/feedback-ledger.json` (create if missing). Calculate fingerprint (`sha256` of redacted body). If same fingerprint + repo exists within `dedup_window_hours` (default 24h):
   - Show: "This feedback was already filed: {issue_url}"
   - Offer: [View existing issue] / [File anyway] / [Cancel]
   - If "File anyway": continue. Otherwise: stop.

2. **Rate limit check**: Count submissions to same repo in last 24h using `epoch` field for portable comparison:
   ```
   now_epoch=$(date +%s)
   cutoff_epoch=$((now_epoch - 86400))
   count = submissions where repo matches AND epoch > cutoff
   ```
   - If count >= `per_repo_daily` (default 5): show warning, require extra confirmation
   - If count >= `per_repo_daily_hard` (default 20): block with "Rate limit exceeded for {repo}"

3. **Redaction preview**: Run `.claude/scripts/feedback-redaction.sh --preview` on the draft feedback content. Display the redacted preview to user:
   ```
   This feedback will be filed on {source_repo} ({construct} v{version}):

   --- Redacted Preview ---
   {redacted_content}
   --- End Preview ---
   ```

4. **Trust warnings**: If `attribution.trust_warning` is non-null, display prominently:
   ```
   WARNING: {trust_warning}
   Please verify this is the correct target repository before submitting.
   ```

5. **Routing options** via AskUserQuestion:
   ```yaml
   questions:
     - question: "Where should this feedback be submitted?"
       header: "Route to"
       options:
         - label: "{source_repo} (Recommended)"
           description: "Construct vendor repo - {construct} v{version}"
         - label: "0xHoneyJar/loa"
           description: "Core Loa framework instead"
         - label: "Current project"
           description: "Your project repo"
         - label: "Copy to clipboard"
           description: "Manual submission"
       multiSelect: false
   ```

6. **On confirmation** (construct repo selected):
   - Apply full redaction via `feedback-redaction.sh --input <draft>`
   - Create issue via `gh issue create` with structured format (see Phase 5b)
   - Record in dedup ledger (see Phase 5.1)

7. **gh access failure handling**:
   - If `gh issue create` fails (permission denied, repo not found, issues disabled):
     - Show: "Cannot file on {source_repo} - {error_reason}"
     - Offer: [Copy to clipboard] / [Route to loa instead] / [Cancel]

When classifier returns any other classification, continue with existing 4-repo routing unchanged.

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

Check trace collection status in `.claude/settings.local.json`:

**If trace collection is ENABLED** (`collectTraces: true`):

1. Run `.claude/scripts/collect-trace.sh` to gather execution data
2. Display summary: source count, total size, redaction count
3. Ask user via AskUserQuestion: "Include traces?" (Yes / No)

**If trace collection is DISABLED or not configured** (v2.2.0):

1. Inform user: "Trace collection is not enabled."
2. Offer AskUserQuestion:
   ```yaml
   questions:
     - question: "Would you like to include execution traces with this feedback? Traces help debug issues."
       header: "Traces"
       options:
         - label: "Enable for this submission (Recommended)"
           description: "Collect traces one-time without changing settings"
         - label: "Skip traces"
           description: "Submit feedback without execution context"
       multiSelect: false
   ```
3. If "Enable for this submission": Run `collect-trace.sh` with one-time collection
4. If "Skip traces": Continue to Phase 4 without traces

**Note**: One-time trace collection does NOT modify `.claude/settings.local.json`. To enable persistent trace collection, see the Trace Configuration section below.

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

### Phase 5b: Construct Issue Submission (v3.0.0)

When routing to a construct repo (from Phase 0.5b):

1. Apply full redaction: `.claude/scripts/feedback-redaction.sh --input <draft_file>`
2. Build structured issue body:

```markdown
## [Loa Feedback] {summary}

**Source**: {feedback_type} (user feedback / audit / review)
**Loa Version**: {framework_version}
**Pack**: {vendor}/{pack} v{version}
**Severity**: {severity_if_applicable}

### Description

{redacted description of the finding}

### Details

{redacted file references, NO code snippets by default}

---
Filed by [Loa Framework](https://github.com/0xHoneyJar/loa) with user confirmation
```

3. Create issue:
   ```bash
   gh issue create \
       --repo "{source_repo}" \
       --title "[Loa Feedback] {summary}" \
       --body "{structured_body}"
   ```

4. On success: proceed to Phase 5.1
5. On failure: offer clipboard fallback (see Phase 0.5b step 7)

### Phase 5.1: Update Dedup Ledger (v3.0.0)

After successful submission to a construct repo:

1. Calculate fingerprint: `sha256sum` of the redacted issue body
2. Get current epoch: `date +%s`
3. Read or create `.run/feedback-ledger.json`:
   ```json
   {
     "schema_version": 1,
     "submissions": []
   }
   ```
4. Append new submission using atomic write (temp file + mv):
   ```json
   {
     "repo": "{source_repo}",
     "fingerprint": "sha256:{hash}",
     "timestamp": "{ISO-8601}",
     "epoch": {unix_timestamp},
     "issue_url": "{created_issue_url}",
     "construct": "{vendor/pack}",
     "feedback_type": "user_feedback"
   }
   ```
5. Write back: `jq` to temp file, then `mv` to `.run/feedback-ledger.json`

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
| **Construct repo** | `.claude/constructs/`, pack/skill paths, vendor refs | **Construct issues (v3.0.0)** |

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
| "Cannot file on {repo}" | gh lacks write access to construct repo | Clipboard fallback or route to loa |
| "Already filed" | Duplicate within dedup window | Shows existing issue URL |
| "Rate limit exceeded" | Too many issues to same repo | Blocks submission with count |
| "source_repo format invalid" | Tampered/malformed manifest | Blocks routing, falls back to 4-repo |
| "Redaction produced empty output" | Input entirely sensitive | Warns user, suggests editing |

## Privacy

- **Opt-in only**: Traces only collected when explicitly enabled
- **Automatic redaction**: API keys, tokens, paths anonymized
- **User review**: Preview and confirm before submission
- **No telemetry**: No automatic data collection
