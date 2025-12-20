# Integration Context

This file provides configuration for Loa integrations.

## Feedback Configuration

Feedback submissions are posted to the **Loa Feedback** project in Linear.

The `/feedback` command:
1. Searches for existing feedback issue by project name
2. Creates new issue or adds comment to existing
3. Includes analytics data from `loa-grimoire/analytics/usage.json`

No additional configuration required - the feedback command discovers
the project dynamically via `mcp__linear__list_projects`.
