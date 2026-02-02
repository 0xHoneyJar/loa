# Helper Scripts Reference

Core scripts in `.claude/scripts/`. Run any script with `--help` for usage details.

## Core Scripts

| Script | Purpose |
|--------|---------|
| `mount-loa.sh` | Install Loa onto existing repo |
| `update.sh` | Framework updates with atomic commits |
| `upgrade-health-check.sh` | Post-upgrade migration and config validation |
| `check-loa.sh` | CI validation |

## Context Management

| Script | Purpose |
|--------|---------|
| `context-manager.sh` | Context compaction + semantic recovery |
| `cache-manager.sh` | Semantic result caching |
| `condense.sh` | Result condensation engine |
| `early-exit.sh` | Parallel subagent coordination |

## Workflow Support

| Script | Purpose |
|--------|---------|
| `synthesize-to-ledger.sh` | Continuous synthesis to NOTES.md/trajectory |
| `schema-validator.sh` | Output validation |
| `permission-audit.sh` | Permission request analysis |
| `search-orchestrator.sh` | ck-first semantic search with grep fallback |
| `compound-orchestrator.sh` | `/compound` command orchestration |
| `collect-trace.sh` | Execution trace collection for `/feedback` |

## Visual & Documentation

| Script | Purpose |
|--------|---------|
| `mermaid-url.sh` | Beautiful Mermaid preview URL generation |

## Integrations

| Script | Purpose |
|--------|---------|
| `mcp-registry.sh` | MCP server management |
| `gh-label-handler.sh` | GitHub issue creation with label fallback |
| `feedback-classifier.sh` | Smart feedback routing |

---

## Search Orchestration (v1.7.0)

Skills use `search-orchestrator.sh` for ck-first semantic search with automatic grep fallback.

### Usage

```bash
# Semantic/hybrid search (uses ck if available, falls back to grep)
.claude/scripts/search-orchestrator.sh hybrid "auth token validate" src/ 20 0.5

# Regex search (uses ck regex mode or grep)
.claude/scripts/search-orchestrator.sh regex "TODO|FIXME" src/ 50 0.0
```

### Search Types

| Type | ck Mode | grep Fallback | Use Case |
|------|---------|---------------|----------|
| `semantic` | `ck --sem` | keyword OR | Conceptual queries |
| `hybrid` | `ck --hybrid` | keyword OR | Discovery + exact |
| `regex` | `ck --regex` | `grep -E` | Exact patterns |

### Environment Override

```bash
LOA_SEARCH_MODE=grep  # Force grep fallback
```

---

## Clean Upgrade (v1.4.0+)

Both `mount-loa.sh` and `update.sh` create single atomic git commits:

```
chore(loa): upgrade framework v1.3.0 -> v1.4.0
```

Version tags: `loa@v{VERSION}`. Query with `git tag -l 'loa@*'`.

---

## Post-Upgrade Health Check

Runs automatically after `update.sh`. Manual usage:

```bash
.claude/scripts/upgrade-health-check.sh          # Check for issues
.claude/scripts/upgrade-health-check.sh --fix    # Auto-fix where possible
.claude/scripts/upgrade-health-check.sh --json   # JSON output for scripting
```

Checks: bd->br migration, deprecated settings, new config options, recommended permissions.

---

## MCP Registry

```bash
.claude/scripts/mcp-registry.sh list      # List servers
.claude/scripts/mcp-registry.sh info <s>  # Server details
.claude/scripts/mcp-registry.sh setup <s> # Setup instructions
```

Pre-built configs available in `.claude/mcp-examples/` for Slack, GitHub, Sentry, PostgreSQL.

---

## Full Documentation

See `.claude/protocols/helper-scripts.md` for comprehensive script documentation.
