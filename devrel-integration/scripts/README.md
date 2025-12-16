# DevRel Integration Scripts

This directory contains utility scripts for managing the DevRel integration system.

## Setup Scripts

### setup-linear-labels.ts

Initializes all base labels needed for the Linear audit trail system. This script should be run once during framework setup.

**Prerequisites:**
- `LINEAR_API_KEY` environment variable must be set in `.env`
- Node.js and npm/yarn installed
- `@linear/sdk` package installed

**Usage:**

```bash
# Use default team (first team in workspace)
npx ts-node scripts/setup-linear-labels.ts

# Specify a team ID
npx ts-node scripts/setup-linear-labels.ts --team-id team_abc123xyz

# Show help
npx ts-node scripts/setup-linear-labels.ts --help
```

**Labels Created:**

The script creates 18 base labels organized into 4 categories:

1. **Agent Labels** (who did the work):
   - `agent:implementer` - Work by sprint-task-implementer
   - `agent:devops` - Work by devops-crypto-architect
   - `agent:auditor` - Work by paranoid-auditor

2. **Type Labels** (what kind of work):
   - `type:feature` - New feature implementation
   - `type:bugfix` - Bug fix
   - `type:infrastructure` - Infrastructure/deployment
   - `type:security` - Security-related
   - `type:audit-finding` - Security audit finding
   - `type:refactor` - Code refactoring
   - `type:docs` - Documentation

3. **Source Labels** (where work originated):
   - `source:discord` - From Discord feedback
   - `source:github` - From GitHub
   - `source:internal` - Agent-created

4. **Priority Labels** (human-assigned urgency):
   - `priority:critical` - Drop everything
   - `priority:high` - Important, ASAP
   - `priority:normal` - Standard priority
   - `priority:low` - Nice to have

**Output:**

The script will:
- ✅ Create new labels
- ⏭️ Skip existing labels
- ❌ Report any errors
- 📊 Print a summary with counts

**Example Output:**

```
🔧 Linear Label Setup Script
================================

📋 Using team: Engineering (team_abc123xyz)

📥 Fetching existing labels...
   Found 3 existing labels

🏷️  Creating labels...

   ✅ Created: agent:implementer
   ✅ Created: agent:devops
   ⏭️  Skipped: agent:auditor (already exists)
   ...

================================
📊 Summary:
   ✅ Created: 15
   ⏭️  Skipped: 3
   ❌ Errors: 0

✨ Label setup complete!
```

**Troubleshooting:**

- **"LINEAR_API_KEY environment variable is required"**: Add your Linear API key to `.env`
- **"No teams found"**: Verify your API key has access to at least one team
- **Permission errors**: Ensure your API key has admin/write permissions

**Querying Issues by Label:**

After setup, you can query issues using these labels:

```typescript
// Find all implementation work
mcp__linear__list_issues({
  filter: {
    labels: { some: { name: { eq: "agent:implementer" } } }
  }
})

// Find all critical security findings
mcp__linear__list_issues({
  filter: {
    labels: {
      and: [
        { name: { eq: "type:audit-finding" } },
        { name: { eq: "priority:critical" } }
      ]
    }
  }
})

// Find Discord-sourced features
mcp__linear__list_issues({
  filter: {
    labels: {
      and: [
        { name: { eq: "type:feature" } },
        { name: { eq: "source:discord" } }
      ]
    }
  }
})
```

## Future Scripts

Additional scripts that may be added:

- `migrate-existing-issues.ts` - Migrate existing Linear issues to new label system
- `generate-audit-report.ts` - Generate audit trail report from Linear issues
- `sync-sprint-labels.ts` - Auto-create sprint labels from sprint.md files
- `verify-linear-integration.ts` - Test Linear MCP integration
