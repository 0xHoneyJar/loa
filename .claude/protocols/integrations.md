# Integrations Protocol

External service integrations (MCP servers) in Loa follow a lazy-loading pattern to minimize context overhead.

## Design Principles

### 1. Lazy Loading
The integration registry (`mcp-registry.yaml`) is only loaded when:
- A command with `integrations.required` is invoked (e.g., `/feedback`)
- A user manually configures integrations via `.claude/scripts/mcp-registry.sh`
- A skill explicitly needs to use an integration

**Never load the registry into skill context preemptively.**

### 2. Progressive Disclosure
Skills declare integrations in their `index.yaml` using a lightweight reference:

```yaml
integrations:
  required: []
  optional:
    - name: "linear"
      scopes: [issues, projects]
      reason: "Sync sprint tasks to Linear"
      fallback: "Tasks remain in sprint.md only"
```

The skill only knows the integration *name*. Setup instructions, URLs, and configuration details live in the registry and are fetched only when needed.

### 3. Graceful Degradation
All skill integrations should be optional with explicit fallbacks:

```yaml
optional:
  - name: "github"
    reason: "GitHub Actions CI/CD setup"
    fallback: "Manual CI/CD configuration required"
```

Required integrations are reserved for commands (like `/feedback`) where the integration is essential to functionality.

## File Structure

```
.claude/
├── mcp-registry.yaml      # Single source of truth (lazy-loaded)
├── scripts/
│   ├── mcp-registry.sh    # Query tool (requires yq)
│   └── validate-mcp.sh    # Lightweight validation (no registry load)
└── protocols/
    └── integrations.md    # This file
```

## Naming Convention

Use `integrations` (not `mcp_dependencies` or `mcp_requirements`):

| Location | Field Name |
|----------|------------|
| Skill index.yaml | `integrations:` |
| Command frontmatter | `integrations:` |
| Command frontmatter | `integrations_source:` |

## Validation Flow

### Pre-flight Check (Commands)
```yaml
pre_flight:
  - check: "script"
    script: ".claude/scripts/validate-mcp.sh linear"
    error: "Linear integration not configured..."
```

`validate-mcp.sh` checks `settings.local.json` directly without loading the registry.

### Runtime Check (Skills)
Skills check integration availability at runtime, not during loading:

```bash
# Only when integration is needed:
if .claude/scripts/validate-mcp.sh github; then
    # Use GitHub integration
else
    # Fall back to manual approach
fi
```

## Registry Query Tool

Requires `yq` for YAML parsing:

```bash
# Install yq
brew install yq        # macOS
sudo apt install yq    # Ubuntu
go install github.com/mikefarah/yq/v4@latest  # Go

# Query commands
.claude/scripts/mcp-registry.sh list          # List all servers
.claude/scripts/mcp-registry.sh info linear   # Server details
.claude/scripts/mcp-registry.sh setup github  # Setup instructions
.claude/scripts/mcp-registry.sh groups        # List groups
.claude/scripts/mcp-registry.sh group essential  # Group members
```

## Integration Declaration Examples

### Skill (optional integrations)
```yaml
# .claude/skills/deploying-infrastructure/index.yaml
integrations:
  required: []
  optional:
    - name: "github"
      scopes: [repos, actions]
      reason: "GitHub Actions CI/CD setup"
      fallback: "Manual CI/CD configuration required"
    - name: "vercel"
      scopes: [deployments, projects]
      reason: "Vercel deployment automation"
      fallback: "Manual deployment documentation provided"
```

### Command (no required integrations)
```yaml
# .claude/commands/feedback.md
# Note: /feedback uses gh CLI with clipboard fallback - no MCP required
integrations: []
```

### Integration Registry Location
```yaml
# MCP registry location
integrations_source: ".claude/mcp-registry.yaml"
```

## Adding New Integrations

1. Add server definition to `mcp-registry.yaml`
2. Add to appropriate group(s)
3. Update skills/commands that can use it
4. Test with `mcp-registry.sh info <server>`
