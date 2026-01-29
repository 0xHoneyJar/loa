# Skill Forking Protocol

This protocol documents when and how to use Claude Code's `context: fork` feature for isolated skill execution.

## Overview

Claude Code 2.1.0 introduced skill forking via `context: fork` frontmatter. This executes skills in an isolated subagent context, preventing conversation pollution and enabling parallel execution.

**Reference**: [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills)

---

## When to Use `context: fork`

| Use Case | Fork? | Reason |
|----------|-------|--------|
| **Read-only exploration** | YES | Isolated, parallel-safe |
| **Codebase analysis** | YES | Doesn't need conversation history |
| **Validation/auditing** | YES | Independent verification |
| **Code modification** | NO | Needs main context for state |
| **Interactive Q&A** | NO | Needs conversation history |
| **Multi-step refactoring** | NO | Needs persistent context |

### Decision Tree

```
Does the skill need to:
├─ Read conversation history? → NO fork
├─ Modify code/files? → NO fork (usually)
├─ Run independently and return results? → YES fork
└─ Execute multiple times in parallel? → YES fork
```

---

## Configuration

### Skill Frontmatter

Add YAML frontmatter at the top of your skill's SKILL.md:

```yaml
---
name: my-skill
description: Short description of what this skill does
context: fork
agent: Explore
allowed-tools: Read, Grep, Glob, Bash(git *)
---

# Skill Content

Your skill instructions here...
```

### Frontmatter Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Skill identifier (used in `/skill-name`) |
| `description` | No | Brief description of skill purpose |
| `context` | No | `fork` for isolated execution, omit for inline |
| `agent` | No | Agent type: `Explore`, `Plan`, `general-purpose` |
| `allowed-tools` | No | Tool restrictions for forked context |

---

## Agent Types

| Agent | Use Case | Available Tools |
|-------|----------|-----------------|
| `Explore` | Read-only codebase exploration | Read, Grep, Glob, Bash (limited) |
| `Plan` | Architecture and design planning | Read, Grep, Glob, Write (plans only) |
| `general-purpose` | Full capabilities (default) | All tools |

### Choosing an Agent Type

- **Explore**: Best for `/ride`, validators, code analysis
- **Plan**: Best for `/architect`, design reviews
- **general-purpose**: Only when full tool access needed in fork

---

## Loa Skills Using Fork

### /ride (riding-codebase)

```yaml
---
name: ride
description: Analyze codebase to extract reality into Loa artifacts
context: fork
agent: Explore
allowed-tools: Read, Grep, Glob, Bash(git *)
---
```

**Why forked**:
- Read-only codebase analysis
- Doesn't need conversation history
- Can run in parallel with other work
- Results returned as summary to main context

### Validator Subagents

All read-only validators use forked context:

| Validator | Agent | Why |
|-----------|-------|-----|
| `architecture-validator` | Explore | Reads code, compares to SDD |
| `security-scanner` | Explore | Reads code, checks patterns |
| `test-adequacy-reviewer` | Explore | Reads tests, assesses quality |
| `documentation-coherence` | Explore | Reads docs, checks consistency |
| `goal-validator` | Explore | Reads PRD/sprint, validates goals |

---

## What Happens in a Forked Context

1. **New context created**: Fresh conversation starts
2. **CLAUDE.md loaded**: Project instructions still apply
3. **Tools restricted**: Only `allowed-tools` available
4. **Isolation**: Changes don't affect main conversation
5. **Results returned**: Summary returned to main context

### What Gets Preserved

- CLAUDE.md project instructions
- Tool configurations from settings.json
- File system access (read-only with Explore)

### What Gets Lost

- Previous conversation history
- In-flight state and decisions
- Todo list items (new list in fork)

---

## Troubleshooting

### Forked Skill Can't Find Files

**Symptom**: Skill reports files don't exist

**Solution**: Forked context starts in project root. Use absolute or project-relative paths.

### Forked Skill Loses Context

**Symptom**: Skill doesn't remember earlier discussion

**Solution**: This is expected. Fork for independent tasks only, or pass context via skill arguments.

### Results Not Visible

**Symptom**: Skill ran but results not shown

**Solution**: Forked skills should write to files (e.g., `grimoires/loa/`) for persistence. Main context receives summary only.

### Skill Runs Too Long

**Symptom**: Forked skill times out

**Solution**: Check `allowed-tools` restrictions. Consider if task is too large for single fork.

---

## Best Practices

1. **Fork read-only skills**: Analysis, validation, exploration
2. **Don't fork interactive skills**: Q&A, multi-step refactoring
3. **Write results to files**: Forked context is ephemeral
4. **Use Explore agent**: For most read-only operations
5. **Restrict tools**: Only allow what's needed
6. **Keep skills focused**: Single responsibility per skill

---

## Examples

### Good Fork Candidate

```yaml
---
name: analyze-deps
description: Analyze project dependencies for security issues
context: fork
agent: Explore
allowed-tools: Read, Grep, Glob
---

# Analyze Dependencies

1. Read package.json / requirements.txt / Cargo.toml
2. Check for known vulnerabilities
3. Report findings to grimoires/loa/a2a/deps-report.md
```

### Bad Fork Candidate

```yaml
# DON'T fork this - needs conversation history
---
name: refactor-wizard
description: Interactive refactoring with user confirmation
# context: fork  <- Would break interactive flow
---

# Refactor Wizard

1. Ask user what to refactor
2. Show options
3. Get confirmation
4. Apply changes
```

---

## References

- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills)
- [Claude Code Agent Types](https://code.claude.com/docs/en/skills#agent-types)
- [Loa CLAUDE.md](../../CLAUDE.md) - Project instructions
