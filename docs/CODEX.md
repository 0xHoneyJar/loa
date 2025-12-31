# Codex + Loa

This repo ships Codex-compatible skills and prompt wrappers so you can use Loa workflows in Codex as well as Claude Code.

## What is included

- Repo-scoped Codex skills under `.codex/skills/`.
- Prompt wrappers under `.codex/prompts/` that map Loa commands to Codex `/prompts:<name>` invocations.

## Setup (Codex)

1. Install prompts to your user Codex directory:

```bash
./scripts/install-codex-prompts.sh
```

2. Start Codex from the repo root:

```bash
codex
```

3. Use Loa commands via Codex prompts:

```
/prompts:plan-and-analyze
/prompts:architect
/prompts:sprint-plan
/prompts:implement sprint-1
/prompts:review-sprint sprint-1
/prompts:audit-sprint sprint-1
```

4. Optional: run any Loa command via the generic prompt:

```
/prompts:loa COMMAND=ride ARGS="--phase extraction"
```

## How it works

- The `loa-command-runner` skill reads `.claude/commands/<name>.md`, runs pre-flight checks, loads context, and dispatches to the referenced Loa skill.
- Each prompt wrapper calls `loa-command-runner` with the command name and raw arguments.
- The Loa skills remain in `.claude/skills/` and are never edited directly.

## Notes

- Codex custom prompts are user-scoped (`~/.codex/prompts`), so the install script copies repo prompts into your home directory.
- If you update prompts, re-run the install script and restart Codex.
