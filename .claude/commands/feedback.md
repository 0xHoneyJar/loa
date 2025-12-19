---
description: Submit feedback about your Loa experience with auto-attached analytics
---

# Loa Feedback

Thank you for taking a moment to share your feedback! This helps improve Loa for everyone.

Your responses will be posted to Linear with your project analytics attached.

---

## Phase 0: Check for Pending Feedback

Before starting the survey, check if there's pending feedback from a previous failed submission:

```bash
ls -la loa-grimoire/analytics/pending-feedback.json 2>/dev/null
```

If pending feedback exists:
1. Display: "You have pending feedback from a previous session that wasn't submitted."
2. Read the pending feedback file
3. Ask: "Would you like to submit this pending feedback now?"
   - Yes: Skip to Phase 3 (Submission) with the pending data
   - No: Continue with new survey (pending data will be overwritten)

---

## Phase 1: Survey

Collect responses to all 4 questions. Display progress (1/4, 2/4, etc.) for each question.

### Question 1 of 4

**What's one thing you would change about Loa?**

(Free text response - be specific! What frustrated you, what could be better?)

Wait for user response before continuing.

---

### Question 2 of 4

**What's one thing you loved about using Loa?**

(Free text response - what worked well? What surprised you positively?)

Wait for user response before continuing.

---

### Question 3 of 4

**How does this build compare to your other Loa builds?**

Rate from 1-5:
1. Much worse than previous builds
2. Somewhat worse than previous builds
3. About the same as previous builds
4. Somewhat better than previous builds
5. Much better than previous builds

(If this is your first build, select "3 - About the same")

Wait for user response before continuing.

---

### Question 4 of 4

**How comfortable and intuitive was the overall process?**

Select one:
- A) Very intuitive - I always knew what to do next
- B) Somewhat intuitive - Mostly clear with occasional confusion
- C) Neutral - Neither particularly clear nor confusing
- D) Somewhat confusing - Often unsure of next steps
- E) Very confusing - Frequently lost or frustrated

Wait for user response before continuing.

---

## Phase 2: Prepare Submission

After collecting all responses, prepare the feedback submission.

### Load Analytics

Read `loa-grimoire/analytics/usage.json` for project analytics.

```bash
cat loa-grimoire/analytics/usage.json 2>/dev/null
```

If file doesn't exist or is invalid JSON, note "Analytics not available" but continue.

### Get Project Context

```bash
# Get project name
PROJECT_NAME=$(git remote get-url origin 2>/dev/null | sed 's/.*\///' | sed 's/\.git$//' || basename "$(pwd)")

# Get developer info
DEVELOPER_NAME=$(git config user.name 2>/dev/null || echo "Unknown")
DEVELOPER_EMAIL=$(git config user.email 2>/dev/null || echo "unknown@unknown")

# Get timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
```

### Save Pending Feedback (Safety Net)

BEFORE attempting Linear submission, save the feedback locally:

```bash
mkdir -p loa-grimoire/analytics
```

Create `loa-grimoire/analytics/pending-feedback.json` with:
```json
{
  "timestamp": "{TIMESTAMP}",
  "project_name": "{PROJECT_NAME}",
  "developer_name": "{DEVELOPER_NAME}",
  "developer_email": "{DEVELOPER_EMAIL}",
  "responses": {
    "q1_change": "{response_1}",
    "q2_love": "{response_2}",
    "q3_rating": {rating_number},
    "q4_comfort": "{comfort_choice}"
  },
  "analytics_snapshot": {full_usage_json_or_null}
}
```

---

## Phase 3: Linear Submission

### Search for Existing Issue

Use the Linear MCP to search for an existing feedback issue:

```
mcp__linear__list_issues({
  project: "Loa Feedback",
  query: "[{PROJECT_NAME}]"
})
```

Look for an issue with title matching `[{PROJECT_NAME}] - Feedback`.

### Prepare Issue Content

Format the feedback as markdown:

```markdown
---
## Feedback Submission - {TIMESTAMP}

**Developer**: {DEVELOPER_NAME} ({DEVELOPER_EMAIL})
**Project**: {PROJECT_NAME}

### Survey Responses

1. **What would you change?**
   {response_1}

2. **What did you love?**
   {response_2}

3. **Rating vs other builds**: {rating}/5

4. **Process comfort level**: {comfort_choice}

### Analytics Summary

| Metric | Value |
|--------|-------|
| Framework Version | {framework_version or "N/A"} |
| Phases Completed | {phases_completed or "N/A"} |
| Sprints Completed | {sprints_completed or "N/A"} |
| Total Reviews | {reviews_completed or "N/A"} |
| Total Audits | {audits_completed or "N/A"} |

<details>
<summary>Full Analytics JSON</summary>

```json
{full_analytics_json}
```

</details>
---
```

### Submit to Linear

**If existing issue found**:
Add a comment to the existing issue:
```
mcp__linear__create_comment({
  issueId: "{existing_issue_id}",
  body: "{formatted_feedback}"
})
```

**If no existing issue**:
Create a new issue:
```
mcp__linear__create_issue({
  title: "[{PROJECT_NAME}] - Feedback",
  team: "Laboratory",
  project: "Loa Feedback",
  description: "{formatted_feedback}",
  labels: ["type:feedback", "source:feedback"]
})
```

### Handle Submission Failure

If Linear submission fails (MCP not configured, network error, etc.):

1. Display error message:
   ```
   Unable to submit feedback to Linear.

   Your feedback has been saved locally to:
   loa-grimoire/analytics/pending-feedback.json

   You can retry by running `/feedback` again.
   ```

2. Keep the pending-feedback.json file
3. Do NOT update usage.json with feedback_submissions entry
4. Stop here

---

## Phase 4: Update Analytics

After successful Linear submission:

### Update usage.json

Add entry to `feedback_submissions` array in `loa-grimoire/analytics/usage.json`:

```bash
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LINEAR_ISSUE_ID="{issue_id_from_submission}"

jq --arg ts "$TIMESTAMP" --arg id "$LINEAR_ISSUE_ID" '
  .feedback_submissions += [{
    "timestamp": $ts,
    "linear_issue_id": $id
  }] |
  .totals.feedback_submitted = true
' loa-grimoire/analytics/usage.json > loa-grimoire/analytics/usage.json.tmp && \
mv loa-grimoire/analytics/usage.json.tmp loa-grimoire/analytics/usage.json
```

### Delete Pending Feedback

Remove the safety net file since submission succeeded:

```bash
rm -f loa-grimoire/analytics/pending-feedback.json
```

### Regenerate Summary

Regenerate `loa-grimoire/analytics/summary.md` to reflect the feedback submission.

---

## Phase 5: Confirmation

Display success message:

```
---

## Feedback Submitted Successfully!

Your feedback has been posted to Linear:
{linear_issue_url}

Thank you for helping improve Loa! Your input directly shapes the future of this framework.

---
```
