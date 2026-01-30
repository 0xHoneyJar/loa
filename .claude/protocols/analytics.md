# Analytics Protocol

This protocol defines how Loa tracks usage metrics for THJ developers. **Analytics are only enabled for THJ developers** - OSS users have no analytics tracking.

## User Type Detection

THJ membership is detected via the `LOA_CONSTRUCTS_API_KEY` environment variable:

| Detection | User Type | Analytics | `/feedback` |
|-----------|-----------|-----------|-------------|
| Valid API key | **THJ** | Full tracking | Available |
| No API key | **OSS** | None (skipped) | Unavailable |

## What's Tracked (THJ Only)

| Category | Metrics |
|----------|---------|
| **Environment** | Framework version, project name, developer (git user) |
| **Phases** | Start/completion timestamps for PRD, SDD, sprint planning, deployment |
| **Sprints** | Sprint number, start/end times, review iterations, audit iterations |
| **Feedback** | Submission timestamps, GitHub issue URLs |

## Files

- `grimoires/loa/analytics/usage.json` - Raw usage data (JSON)
- `grimoires/loa/analytics/summary.md` - Human-readable summary
- `grimoires/loa/analytics/pending-feedback.json` - Pending feedback (if submission failed)

## Analytics JSON Schema

```json
{
  "schema_version": "1.0.0",
  "framework_version": "0.15.0",
  "project_name": "my-project",
  "developer": {
    "git_user_name": "Developer Name",
    "git_user_email": "dev@example.com"
  },
  "initialized_at": "2025-01-15T10:30:00Z",
  "phases": {
    "prd": { "started_at": null, "completed_at": null },
    "sdd": { "started_at": null, "completed_at": null },
    "sprint_planning": { "started_at": null, "completed_at": null },
    "deployment": { "started_at": null, "completed_at": null }
  },
  "sprints": [],
  "reviews": [],
  "audits": [],
  "deployments": [],
  "feedback_submissions": [],
  "totals": {
    "commands_executed": 0,
    "phases_completed": 0
  }
}
```

## Updating Analytics

Each phase command follows this pattern:

1. Check for `LOA_CONSTRUCTS_API_KEY` environment variable
2. If not set: Skip analytics entirely, continue with main workflow
3. If set: Check if `usage.json` exists (create if missing)
4. Update relevant phase/sprint data
5. Regenerate `summary.md`
6. Continue with main workflow

## How It Works

1. **Initialization**: First phase command creates `usage.json` with environment info (THJ only)
2. **Phase tracking**: Each phase command checks for API key first, skips analytics for OSS users
3. **Non-blocking**: Analytics failures are logged but don't stop workflows
4. **Opt-in sharing**: Analytics stay local; only shared via `/feedback` if you choose

## Helper Scripts

See `.claude/scripts/analytics.sh` for helper functions:
- `get_framework_version()` - Extract version from package.json or CHANGELOG.md
- `get_git_user()` - Get git user name and email
- `get_project_name()` - Get project name from git remote or directory
- `get_timestamp()` - Get current ISO-8601 timestamp
- `init_analytics()` - Initialize analytics file if missing
- `update_analytics_field()` - Update a field in analytics JSON
