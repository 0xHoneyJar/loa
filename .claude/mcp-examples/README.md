# MCP Configuration Examples

> **WARNING**: MCP (Model Context Protocol) is OPTIONAL and intended for power users only.
> These examples require careful security consideration before deployment.

## Security Notice

MCP servers extend Claude's capabilities by connecting to external services. This means:

1. **Credential Exposure**: MCP servers require API tokens/credentials that Claude can use
2. **Data Access**: External services may contain sensitive business data
3. **Action Execution**: Some MCP servers can perform write operations (create issues, send messages)
4. **Audit Trail**: Actions taken via MCP may not have the same audit controls as direct API usage

**Before enabling any MCP integration:**
- Review the security implications with your security team
- Use service accounts with minimal required permissions
- Enable audit logging on connected services
- Consider using read-only tokens where possible

## Available Examples

| Example | Service | Read/Write | Risk Level |
|---------|---------|------------|------------|
| [slack.json](./slack.json) | Slack | Read + Write | HIGH |
| [github.json](./github.json) | GitHub | Read + Write | MEDIUM |
| [sentry.json](./sentry.json) | Sentry | Read only | LOW |
| [postgres.json](./postgres.json) | PostgreSQL | Read + Write | CRITICAL |
| [dev-browser.json](./dev-browser.json) | Browser Automation | Local only | MEDIUM |

## Example Format

Each example file contains:

```json
{
  "name": "service-name",
  "description": "What this integration provides",
  "security_notes": [
    "Important security considerations"
  ],
  "required_scopes": [
    "list of required permissions"
  ],
  "config": {
    "mcpServers": {
      "service-name": {
        "command": "...",
        "args": ["..."],
        "env": {
          "API_KEY": "${SERVICE_API_KEY}"
        }
      }
    }
  },
  "required_env": [
    "SERVICE_API_KEY"
  ],
  "setup_steps": [
    "1. Step one",
    "2. Step two"
  ]
}
```

## Required Scopes by Integration

### Slack

| Scope | Purpose | Risk |
|-------|---------|------|
| `channels:read` | List channels | Low |
| `channels:history` | Read messages | Medium |
| `chat:write` | Send messages | High |
| `users:read` | List users | Low |

**Recommendation**: Create a dedicated bot user with minimal channel access.

### GitHub

| Scope | Purpose | Risk |
|-------|---------|------|
| `repo` | Full repository access | High |
| `read:org` | Read organization data | Low |
| `read:project` | Read project boards | Low |

**Recommendation**: Use fine-grained PATs scoped to specific repositories.

### Sentry

| Scope | Purpose | Risk |
|-------|---------|------|
| `event:read` | Read error events | Low |
| `project:read` | Read project info | Low |

**Recommendation**: Use organization-level read-only tokens.

### PostgreSQL

| Permission | Purpose | Risk |
|------------|---------|------|
| `SELECT` | Read data | Medium |
| `INSERT/UPDATE/DELETE` | Modify data | Critical |

**Recommendation**: Use read-only database user. Never give write access without explicit approval.

## Security Recommendations

### General

1. **Environment Variables**: Never hardcode credentials. All examples use `${VAR}` placeholders.
2. **Minimal Permissions**: Request only the scopes you need.
3. **Service Accounts**: Use dedicated accounts, not personal credentials.
4. **Rotation**: Rotate credentials regularly (at least quarterly).
5. **Audit Logging**: Enable audit logs on all connected services.

### Per-Environment

| Environment | Recommendation |
|-------------|----------------|
| Development | Use sandbox/test accounts with fake data |
| Staging | Use read-only tokens where possible |
| Production | Require security review before enabling |

### MCP Server Vetting

Before using any MCP server:

1. **Source Review**: Verify the MCP server source code
2. **Permissions Audit**: Understand what actions it can perform
3. **Network Access**: Know what endpoints it connects to
4. **Data Handling**: Understand what data it processes

## Installation

1. Copy the desired example to your Claude Code configuration:

```bash
# Example: Add GitHub integration
cat .claude/mcp-examples/github.json
# Copy the "config" section to your claude_desktop_config.json or settings
```

2. Set required environment variables:

```bash
export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_xxxxxxxxxxxx"
```

3. Restart Claude Code to pick up changes.

## Integration with Loa

MCP integrations are documented in the Loa MCP registry:

- Registry: `.claude/mcp-registry.yaml`
- Validation: `.claude/scripts/validate-mcp.sh`

Skills can declare MCP dependencies in their `index.yaml`:

```yaml
integrations:
  optional:
    - name: "github"
      reason: "Sync issues to GitHub"
      fallback: "Issues tracked locally"
```

## Troubleshooting

### MCP Server Not Starting

1. Check environment variables are set
2. Verify the MCP server package is installed
3. Check Claude Code logs for errors

### Permission Denied

1. Verify token has required scopes
2. Check token hasn't expired
3. Verify service account has access to required resources

### Connection Timeout

1. Check network connectivity to service
2. Verify firewall allows outbound connections
3. Check service status page for outages

## Further Reading

- [MCP Protocol Specification](https://modelcontextprotocol.io/)
- [Claude Code MCP Documentation](https://docs.anthropic.com/claude-code/mcp)
- [Loa Integrations Protocol](./../protocols/integrations.md)
