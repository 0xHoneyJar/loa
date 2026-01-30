# Anthropic Oracle

Quick access to the Anthropic updates monitoring system.

---

## Usage

```bash
# Check for updates (fetch sources)
.claude/scripts/anthropic-oracle.sh check

# List monitored sources
.claude/scripts/anthropic-oracle.sh sources

# View check history
.claude/scripts/anthropic-oracle.sh history

# Generate research template
.claude/scripts/anthropic-oracle.sh template
```

---

## Workflow

1. **Fetch**: Run the check command to fetch latest Anthropic sources
2. **Analyze**: Run `/oracle-analyze` to have Claude analyze the cached content
3. **Document**: Generate research document with findings and gaps analysis
4. **Act**: Create issues or PRs for valuable improvements

---

## Automated Checks

The oracle also runs automatically:
- **Weekly**: GitHub Actions workflow on Mondays 9:00 UTC
- **Creates**: Issue with analysis prompt when new content detected

See `.github/workflows/oracle.yml` for configuration.

---

## Cache Location

Sources cached at: `~/.loa/cache/oracle/`
- TTL: 24 hours (configurable via `ANTHROPIC_ORACLE_TTL`)
- History: `check-history.jsonl`
- Manifest: `manifest.json`

---

## Sources Monitored

| Source | URL |
|--------|-----|
| Claude Code Docs | https://docs.anthropic.com/en/docs/claude-code |
| Changelog | https://docs.anthropic.com/en/release-notes/claude-code |
| API Reference | https://docs.anthropic.com/en/api |
| Blog | https://www.anthropic.com/news |
| GitHub (Claude Code) | https://github.com/anthropics/claude-code |
| GitHub (SDK) | https://github.com/anthropics/anthropic-sdk-python |

---

## Interest Areas

The oracle focuses on updates related to:
- hooks, tools, context, agents, mcp, memory
- skills, commands, slash commands, settings
- configuration, api, sdk, streaming, batch, vision, files

---

## Requirements

- bash 4.0+ (macOS: `brew install bash`)
- jq (JSON processing)
- curl (HTTP fetches)

---

## Related Commands

- `/oracle-analyze` - Analyze cached content and generate research document
