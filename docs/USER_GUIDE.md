# Onomancer Bot User Guide

> Transform technical documentation into stakeholder-ready summaries with a simple Discord command.

## Introduction

**Onomancer Bot** is a Discord bot that transforms technical documentation (PRDs, SDDs, sprint plans, audit reports) into persona-targeted summaries for different stakeholder groups. It automatically adapts content for Leadership, Product, Marketing, and DevRel audiences.

### Why Use Onomancer Bot?

- **Save Time**: No more manually rewriting technical docs for different audiences
- **Consistency**: Summaries follow consistent formatting and tone
- **Security**: Built-in secret scanning prevents credential leaks
- **Access Control**: Role-based permissions ensure the right people see the right information

---

## Getting Started

### Prerequisites

1. **Discord Access**: You must be a member of the Honey Jar Discord server
2. **Role Assignment**: Ask an admin to assign you the appropriate role:
   - `Researcher`: View summaries and provide feedback
   - `Developer`: Full access to all commands
   - `Admin`: Administrative access

### Accessing the Bot

1. Navigate to any channel where the bot is active
2. Type `/` to see available commands
3. Select a command and fill in the required parameters

---

## Commands Reference

### `/translate` - Manual Document Translation

Transform a document into a persona-targeted summary.

**Syntax:**
```
/translate <project> <@document> for <audience>
```

**Parameters:**
| Parameter | Required | Description |
|-----------|----------|-------------|
| `project` | Yes | Project name (e.g., `mibera`, `onomancer`, `honeyjar`) |
| `document` | Yes | Document reference (e.g., `@prd`, `@sdd`, `@sprint`) |
| `audience` | Yes | Target audience (e.g., `leadership`, `product`, `marketing`, `devrel`) |

**Examples:**
```
/translate mibera @prd for leadership
/translate onomancer @sdd for product
/translate honeyjar @sprint for devrel
```

**What Happens:**
1. Bot acknowledges your request (loading message)
2. Document is fetched and validated
3. Security scan runs (secrets are blocked/redacted)
4. Content is transformed for your specified audience
5. Summary is stored in Google Docs
6. You receive a link to the generated summary

---

### `/exec-summary` - Get Sprint Executive Summary

Get a role-appropriate executive summary of a sprint.

**Syntax:**
```
/exec-summary <sprint-id>
```

**Parameters:**
| Parameter | Required | Description |
|-----------|----------|-------------|
| `sprint-id` | Yes | Sprint identifier (e.g., `sprint-1`, `sprint-2`) |

**Example:**
```
/exec-summary sprint-1
```

**What Happens:**
1. Bot detects your Discord role
2. Appropriate persona summary is selected (Leadership, Product, etc.)
3. Link to existing summary is returned (or generated if missing)

---

### `/audit-summary` - Get Security Audit Summary

Get a summary of security audit findings for a sprint.

**Syntax:**
```
/audit-summary <sprint-id>
```

**Parameters:**
| Parameter | Required | Description |
|-----------|----------|-------------|
| `sprint-id` | Yes | Sprint identifier (e.g., `sprint-1`, `sprint-2`) |

**Example:**
```
/audit-summary sprint-1
```

**What Happens:**
1. Bot retrieves the security audit for the sprint
2. Summary shows severity breakdown (CRITICAL, HIGH, MEDIUM, LOW)
3. Link to full audit report is provided

---

### `/show-sprint` - View Sprint Status

Display current sprint status and progress.

**Syntax:**
```
/show-sprint [sprint-id]
```

**Parameters:**
| Parameter | Required | Description |
|-----------|----------|-------------|
| `sprint-id` | No | Specific sprint (defaults to current sprint) |

**Examples:**
```
/show-sprint
/show-sprint sprint-2
```

---

### `/doc` - View Document

View a specific document from the codebase.

**Syntax:**
```
/doc <path>
```

**Parameters:**
| Parameter | Required | Description |
|-----------|----------|-------------|
| `path` | Yes | Relative path to document (e.g., `docs/prd.md`) |

**Example:**
```
/doc docs/prd.md
```

---

## Document References

Use these shorthand references in commands:

| Shorthand | Resolves To | Description |
|-----------|-------------|-------------|
| `@prd` | `docs/prd.md` | Product Requirements Document |
| `@sdd` | `docs/sdd.md` | Software Design Document |
| `@sprint` | `docs/sprint.md` | Sprint Plan |
| `@audit` | Latest audit report | Security Audit Report |

**Example:**
```
/translate mibera @prd for leadership
```
is equivalent to:
```
/translate mibera docs/prd.md for leadership
```

---

## Personas Guide

When you request a translation, content is adapted for specific audiences:

### Leadership Persona
- **Focus**: Business impact, ROI, strategic alignment
- **Tone**: Executive summary, high-level metrics
- **Removes**: Technical jargon, implementation details
- **Emphasizes**: Risks, timeline, resource needs

### Product Persona
- **Focus**: User stories, feature scope, acceptance criteria
- **Tone**: Product-centric, user journey focused
- **Removes**: Deep technical architecture
- **Emphasizes**: User impact, roadmap alignment

### Marketing Persona
- **Focus**: Market positioning, competitive advantage
- **Tone**: Benefits-oriented, customer-facing
- **Removes**: Internal process details
- **Emphasizes**: Value proposition, differentiators

### DevRel Persona
- **Focus**: Technical capabilities, integration points
- **Tone**: Developer-friendly, technically accurate
- **Removes**: Business/financial details
- **Emphasizes**: APIs, code examples, best practices

---

## Troubleshooting

### Common Errors

#### "You don't have permission to use this feature"
- **Cause**: Your Discord role doesn't have access to this command
- **Solution**: Ask an admin to assign you the appropriate role

#### "Invalid project name"
- **Cause**: The project name doesn't exist in the system
- **Solution**: Use one of the valid project names: `mibera`, `onomancer`, `honeyjar`

#### "Document not found"
- **Cause**: The document reference is invalid or doesn't exist
- **Solution**: Use valid document references like `@prd`, `@sdd`, `@sprint`

#### "Security Alert: Critical secrets detected"
- **Cause**: The document contains credentials or API keys
- **Solution**: Remove secrets from the source document before translating

#### "Rate limit exceeded"
- **Cause**: Too many requests in a short time
- **Solution**: Wait 1 minute and try again

#### "Transformation failed"
- **Cause**: AI service temporarily unavailable
- **Solution**: Wait a few minutes and retry; the bot has automatic retry logic

### Still Having Issues?

1. Check #bot-feedback channel for known issues
2. Contact the development team in #dev-support
3. Report bugs with `/feedback` command

---

## FAQ

### How long does translation take?
Translations typically complete in 30-60 seconds. You'll see a "loading" message immediately, and the bot will update with the result.

### Can I translate any document?
Only documents in the allowed directories can be translated:
- `docs/` - Main documentation
- `docs/a2a/` - Agent-to-agent communication

### Are my translations private?
Translations are stored in Google Docs with team-appropriate permissions. Only users with the correct role can access the summaries.

### What happens to secrets in documents?
The bot scans all content for secrets (API keys, tokens, passwords). Critical secrets **block** the translation entirely. You must remove them from the source document first.

### Can I translate multiple documents at once?
Currently, each `/translate` command handles one document. Run multiple commands for multiple documents.

### How do I get a different persona's summary?
The `/exec-summary` command automatically selects the persona based on your Discord role. For a specific persona, use `/translate` with the desired audience parameter.

---

## Quick Reference Card

### Essential Commands

| Command | Description |
|---------|-------------|
| `/translate <project> @prd for leadership` | Translate PRD for executives |
| `/exec-summary sprint-1` | Get role-appropriate sprint summary |
| `/audit-summary sprint-1` | Get security audit summary |
| `/show-sprint` | View current sprint status |
| `/doc docs/prd.md` | View a document |

### Document Shorthands

| Shorthand | Document |
|-----------|----------|
| `@prd` | Product Requirements |
| `@sdd` | Software Design |
| `@sprint` | Sprint Plan |
| `@audit` | Security Audit |

### Valid Projects
`mibera`, `onomancer`, `honeyjar`

### Valid Audiences
`leadership`, `product`, `marketing`, `devrel`

---

## Support

- **Bug Reports**: Use `/feedback` command or post in #bot-feedback
- **Feature Requests**: Post in #feature-requests
- **Urgent Issues**: Tag @dev-team in #dev-support

---

*Last Updated: December 2025*
*Version: 1.0.0*
