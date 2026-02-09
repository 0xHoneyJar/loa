# RTFM Command

## Purpose

Test documentation usability by spawning zero-context agents that attempt tasks using only the provided docs. Identifies gaps that human reviewers miss due to the curse of knowledge.

## Invocation

```
/rtfm README.md                         # Test README usability
/rtfm INSTALLATION.md                   # Test installation guide
/rtfm README.md INSTALLATION.md         # Test combined onboarding
/rtfm --task "Install and run first command" README.md
/rtfm --template install                # Use pre-built task template
/rtfm --model haiku README.md           # Use haiku for tester agent
```

## Arguments

| Argument | Description | Required | Default |
|----------|-------------|----------|---------|
| `docs` | Documentation file paths (positional) | Yes* | - |
| `--task` | Custom task description for the tester | No | Inferred from doc filename |
| `--template` | Pre-built task template ID | No | - |
| `--model` | Model for tester subagent | No | `sonnet` |

*At least one doc file required unless `--template` provides defaults.

## Templates

| Template | Task | Default Docs |
|----------|------|-------------|
| `install` | Install this tool on a fresh repository | INSTALLATION.md |
| `quickstart` | Follow the quick start guide | README.md |
| `mount` | Install framework onto existing project | README.md, INSTALLATION.md |
| `beads` | Set up the task tracking tool | INSTALLATION.md |
| `gpt-review` | Configure cross-model review | INSTALLATION.md |
| `update` | Update framework to latest version | INSTALLATION.md |

## Process

1. **Argument Resolution**: Parse docs, task, template, model from arguments
2. **Document Bundling**: Read and concatenate doc files with headers
3. **Tester Spawn**: Launch zero-context subagent with bundled docs and task
4. **Gap Parsing**: Extract [GAP] markers, count by type and severity
5. **Report & Display**: Write report and show verdict to user

## Skill

Routes to: `.claude/skills/rtfm-testing/SKILL.md`

## Output

Reports written to: `grimoires/loa/a2a/rtfm/report-{date}.md`

## Verdicts

| Verdict | Condition |
|---------|-----------|
| SUCCESS | 0 BLOCKING gaps found |
| PARTIAL | >0 BLOCKING gaps but tester made partial progress |
| FAILURE | Tester could not start or gave up early |

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "No documentation files found" | No files provided and no template | Provide file paths or use --template |
| "File not found" | Doc file doesn't exist | Check file path |
| "Document too large" | Total doc size > 50KB | Split into smaller files |

## Related

- `/validate docs` — Static documentation quality checks
- `/review-sprint` — Code quality review (includes doc coherence)
