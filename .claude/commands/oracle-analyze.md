# Anthropic Oracle Analysis

Analyze recent Anthropic updates for potential Loa improvements.

---

## Pre-Flight

1. Run the oracle check to fetch latest sources:
   ```bash
   .claude/scripts/anthropic-oracle.sh check
   ```

2. Verify cache exists:
   ```bash
   ls -la ~/.loa/cache/oracle/
   ```

---

## Analysis Instructions

You are the Anthropic Oracle Analyst. Your task is to review recent Anthropic official sources and identify updates that could benefit the Loa framework.

### Sources to Analyze

Fetch and analyze content from these cached sources:

1. **Claude Code Documentation** (`~/.loa/cache/oracle/docs.html`)
   - New features, capabilities, best practices

2. **Claude Code Changelog** (`~/.loa/cache/oracle/changelog.html`)
   - Recent releases, new tools, deprecations

3. **API Reference** (`~/.loa/cache/oracle/api_reference.html`)
   - API changes, new endpoints, SDK updates

4. **Anthropic Blog** (`~/.loa/cache/oracle/blog.html`)
   - Announcements, new capabilities, research

5. **GitHub Repositories**
   - `~/.loa/cache/oracle/github_claude_code.html`
   - `~/.loa/cache/oracle/github_sdk.html`

### Interest Areas

Focus analysis on these Loa-relevant topics:
- hooks, tools, context, agents, mcp, memory
- skills, commands, slash commands, settings
- configuration, api, sdk, streaming, batch, vision, files

### Analysis Process

1. **Read each cached source** using the Read tool or WebFetch for URLs
2. **Identify updates** since the last analysis
3. **Categorize findings**:
   - New Features (could enhance Loa)
   - API Changes (may require Loa updates)
   - Deprecations (may break Loa)
   - Best Practices (should adopt in Loa)
4. **Assess impact** on Loa's existing features
5. **Generate recommendations** with effort/value ratings

---

## Output

Generate a research document at `grimoires/pub/research/anthropic-updates-YYYY-MM-DD.md` using the template:

```bash
.claude/scripts/anthropic-oracle.sh template
```

### Document Structure

1. **Executive Summary** - Key findings in 3-5 bullets
2. **New Features** - Features Loa could adopt
3. **API Changes** - Breaking/non-breaking changes
4. **Deprecations** - Sunset items affecting Loa
5. **Best Practices** - Recommendations to adopt
6. **Gaps Analysis** - What Anthropic offers that Loa lacks
7. **Recommended Actions** - Prioritized action items

---

## Workflow

1. Run analysis and generate research document
2. Create a PR with the research document
3. Tag PR with `research` and `oracle` labels
4. Request review from maintainers

---

## Automation

This analysis can be triggered:
- **Manually**: Run `/oracle-analyze` in Claude Code
- **Scheduled**: GitHub Actions runs weekly (see `.github/workflows/oracle.yml`)
- **On-demand**: When Anthropic announces major updates

---

## References

- Script: `.claude/scripts/anthropic-oracle.sh`
- Cache: `~/.loa/cache/oracle/`
- History: `~/.loa/cache/oracle/check-history.jsonl`
