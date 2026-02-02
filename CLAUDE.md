@.claude/loa/CLAUDE.loa.md

# Project-Specific Instructions

> This file contains project-specific customizations that take precedence over the framework instructions.
> The framework instructions are loaded via the `@` import above.

## Project Configuration

Add your project-specific Claude Code instructions here. These instructions will take precedence over
the imported framework defaults.

### Example Customizations

```markdown
## Tech Stack
- Language: TypeScript
- Framework: Next.js 14
- Database: PostgreSQL

## Coding Standards
- Use functional components with hooks
- Prefer named exports
- Always include unit tests

## Domain Context
- This is a fintech application
- Security is paramount
- All API calls must be authenticated
```

## How This Works

1. Claude Code loads `@.claude/loa/CLAUDE.loa.md` first (framework instructions)
2. Then loads this file (project-specific instructions)
3. Instructions in this file **take precedence** over imported content
4. Framework updates modify `.claude/loa/CLAUDE.loa.md`, not this file

## Related Documentation

- `.claude/loa/CLAUDE.loa.md` - Framework-managed instructions (auto-updated)
- `.loa.config.yaml` - User configuration file
- `PROCESS.md` - Detailed workflow documentation
