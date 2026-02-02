# URL Registry Protocol

> **Version**: 1.0
> **Purpose**: Prevent agent URL hallucination by providing canonical URL sources

---

## Overview

Agents frequently hallucinate URLs when generating documentation, PR descriptions, or example code. This protocol establishes a canonical URL registry that agents MUST reference instead of guessing.

---

## URL Registry Location

The canonical URL registry lives in the State Zone:

```
grimoires/loa/urls.yaml
```

This file is user-owned and project-specific.

---

## Registry Schema

```yaml
# grimoires/loa/urls.yaml
# Canonical URLs for this project - agents MUST use these

environments:
  production:
    base: https://myapp.com
    api: https://api.myapp.com
  staging:
    base: https://staging.myapp.com
  local:
    base: http://localhost:3000
    api: http://localhost:3000/api

# Placeholder for unconfigured environments
placeholders:
  domain: your-domain.example.com
  api_base: "{{base}}/api"

# Service-specific URLs
services:
  docs: https://docs.myapp.com
  dashboard: https://dashboard.myapp.com
```

---

## Agent Protocol

### Before Generating ANY URL

1. **Check registry**: Read `grimoires/loa/urls.yaml` if exists
2. **Use configured URL**: If environment/service is configured, use exact URL
3. **Use placeholder**: If not configured, use explicit placeholder from registry
4. **Default placeholder**: If no registry exists, use `https://your-domain.example.com`

### NEVER

- Assume/guess production domains
- Hallucinate plausible-sounding URLs
- Use domains from other projects
- Invent subdomains

---

## Integration Points

### Skills That Generate URLs

These skills MUST check the URL registry:

| Skill | URL Usage |
|-------|-----------|
| `implementing-tasks` | API endpoints in code, config files |
| `deploying-infrastructure` | Production/staging URLs in IaC |
| `translating-for-executives` | Links in executive summaries |
| `designing-architecture` | Service URLs in SDD diagrams |

### PR Descriptions

When generating PR descriptions with example commands:

```markdown
## Good (uses registry)
curl -X POST {{urls.production.api}}/endpoint

## Good (uses placeholder when not configured)
curl -X POST https://your-domain.example.com/api/endpoint

## Bad (hallucinated URL)
curl -X POST https://mibera.xyz/api/endpoint
```

---

## Template Substitution

Skills can use mustache-style templates that get resolved:

```markdown
## Usage

```bash
curl -X POST {{urls.production.api}}/v1/generate
```
```

Resolution order:
1. `grimoires/loa/urls.yaml` → `environments.production.api`
2. Fallback to placeholder: `{{urls.placeholders.api_base}}`
3. Final fallback: `https://your-domain.example.com/api`

---

## Initialization

### Via `/mount`

The `mount-loa.sh` script creates a template `urls.yaml`:

```yaml
# grimoires/loa/urls.yaml
# Configure your project URLs here
# Agents will use these instead of guessing

environments:
  production:
    base: ""  # e.g., https://myapp.com
    api: ""   # e.g., https://api.myapp.com
  staging:
    base: ""
  local:
    base: http://localhost:3000
    api: http://localhost:3000/api

placeholders:
  domain: your-domain.example.com
```

### Manual Creation

Users can create `grimoires/loa/urls.yaml` at any time.

---

## Validation

### Pre-Commit Check

Skills should validate URLs before committing:

```bash
# Check for hallucinated URLs in staged files
git diff --cached | grep -E 'https?://[a-z0-9.-]+\.(xyz|io|com|app)' | \
  grep -v -f grimoires/loa/urls.yaml
```

### Review Checklist

Reviewers should check:
- [ ] No hardcoded URLs that should use registry
- [ ] Placeholders used for unconfigured environments
- [ ] URLs match registry when configured

---

## Configuration

Optional settings in `.loa.config.yaml`:

```yaml
url_registry:
  enabled: true                    # Enable URL registry protocol
  require_registry: false          # Block if urls.yaml missing
  placeholder_domain: your-domain.example.com
  warn_on_missing: true            # Warn when URL not in registry
```

---

## Error Messages

| Scenario | Message |
|----------|---------|
| URL not in registry | `"URL 'example.com' not found in registry. Using placeholder."` |
| Registry missing | `"No URL registry found. Using default placeholders."` |
| Hallucination detected | `"Detected potential hallucinated URL. Please verify or add to registry."` |

---

## Related Protocols

- [Grounding Enforcement](grounding-enforcement.md) - Factual citation requirements
- [Negative Grounding](negative-grounding.md) - Avoiding hallucination

---

**Protocol Version**: 1.0
**Last Updated**: 2026-02-02
