# AGENTS.md

- This repo uses Loa's three-zone model. Never edit `.claude/` directly; use `.claude/overrides/` or `.loa.config.yaml`.
- To use Loa workflows in Codex, install the prompt wrappers once:
  `./scripts/install-codex-prompts.sh`
  Restart Codex after running the script so prompts load.
- Run Codex from the repo root so `.codex/skills` is in scope.
- Invoke Loa workflows via `/prompts:<command>` (for example, `/prompts:plan-and-analyze`).
- The `loa-command-runner` skill reads `.claude/commands/<name>.md` and dispatches to the referenced Loa skill. Follow those instructions as the source of truth.
