# User Overrides

Files here are preserved across framework updates.

## How to Use

Mirror the `.claude/` structure for any customizations. For example:

```
.claude/overrides/
├── skills/
│   └── implementing-tasks/
│       └── SKILL.md          # Your customized skill
└── commands/
    └── my-custom-command.md  # Your custom command
```

## What Can Be Overridden

- Skill instructions (SKILL.md files)
- Command definitions
- Templates
- Protocol extensions

## Important Notes

- Overrides take precedence over system files
- Framework updates will never touch this directory
- Keep your customizations minimal to reduce drift

## Best Practices

1. **Don't copy entire files** - only override what you need
2. **Document your changes** - add comments explaining why
3. **Test after updates** - verify overrides still work with new version
