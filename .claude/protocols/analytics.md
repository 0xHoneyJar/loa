# Analytics Protocol

This protocol defines how Loa tracks usage metrics for THJ developers. **Analytics are only enabled for THJ developers** - OSS users have no analytics tracking.

## User Type Behavior

| User Type | Analytics | `/feedback` | `/config` |
|-----------|-----------|-------------|-----------|
| **THJ** | Full tracking | Available | Available |
| **OSS** | None (skipped) | Unavailable | Unavailable |

## What's Tracked (THJ Only)

| Category | Metrics |
|----------|---------|
| **Environment** | Framework version, project name, developer (git user) |
| **Setup** | Completion timestamp, configured MCP servers |
| **Phases** | Start/completion timestamps for PRD, SDD, sprint planning, deployment |
| **Sprints** | Sprint number, start/end times, review iterations, audit iterations |
| **Feedback** | Submission timestamps, Linear issue IDs |

## Files

- `loa-grimoire/analytics/usage.json` - Raw usage data (JSON)
- `loa-grimoire/analytics/summary.md` - Human-readable summary
- `loa-grimoire/analytics/pending-feedback.json` - Pending feedback (if submission failed)

## Setup Marker File

The `.loa-setup-complete` file determines user type and stores configuration:

```json
{
  "completed_at": "2025-01-15T10:30:00Z",
  "framework_version": "0.4.0",
  "user_type": "thj",
  "mcp_servers": ["linear", "github"],
  "git_user": "developer@example.com",
  "template_source": {
    "detected": true,
    "repo": "0xHoneyJar/loa",
    "detection_method": "origin_url",
    "detected_at": "2025-01-15T10:30:00Z"
  }
}
```

**User Types**:
- `"thj"` - THJ team member with full analytics, MCP config, and feedback access
- `"oss"` - Open source user with streamlined experience, no analytics

## Analytics JSON Schema

```json
{
  "schema_version": "1.0.0",
  "framework_version": "0.4.0",
  "project_name": "my-project",
  "developer": {
    "git_user_name": "Developer Name",
    "git_user_email": "dev@example.com"
  },
  "setup": {
    "completed_at": "2025-01-15T10:30:00Z",
    "mcp_servers_configured": ["linear", "github"]
  },
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

1. Check `user_type` in `.loa-setup-complete`
2. If OSS: Skip analytics entirely, continue with main workflow
3. If THJ: Check if `usage.json` exists (create if missing)
4. Update relevant phase/sprint data
5. Regenerate `summary.md`
6. Continue with main workflow

## How It Works

1. **Initialization**: `/setup` creates `usage.json` with environment info (THJ only)
2. **Phase tracking**: Each phase command checks `user_type` first, skips for OSS users
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
