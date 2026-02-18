---
zones:
  system:
    path: .claude
    permission: read
  state:
    paths: [grimoires/bridgebuilder]
    permission: read
  app:
    permission: none
---

# Bridgebuilder — Autonomous PR Review

## Prerequisites

- `gh` CLI installed and authenticated (`gh auth status`)
- `ANTHROPIC_API_KEY` environment variable set
- Node.js >= 20.0.0

## Usage

```bash
/bridgebuilder                          # Review all open PRs on auto-detected repo
/bridgebuilder --dry-run                # Preview reviews without posting
/bridgebuilder --pr 42                  # Review only PR #42
/bridgebuilder --repo owner/repo        # Target specific repo
/bridgebuilder --no-auto-detect         # Skip git remote detection
```

## How It Works

1. Resolves configuration from 5-level precedence: CLI > env > YAML > auto-detect > defaults
2. Detects current repo from `git remote -v` (unless `--no-auto-detect`)
3. Fetches open PRs via `gh` CLI
4. For each PR:
   - Checks if already reviewed (marker: `<!-- bridgebuilder-review: {sha} -->`)
   - Builds review prompt from persona + truncated diff
   - Calls Anthropic API for review generation
   - Sanitizes output (redacts leaked secrets)
   - Posts review to GitHub (`COMMENT` or `REQUEST_CHANGES`)
5. Prints JSON summary: `{ reviewed, skipped, errors }`

## Configuration

Set in `.loa.config.yaml` under `bridgebuilder:` section, or via environment variables:

| Setting | Env Var | Default |
|---------|---------|---------|
| repos | `BRIDGEBUILDER_REPOS` | Auto-detected from git remote |
| model | `BRIDGEBUILDER_MODEL` | `claude-opus-4-6` |
| dry_run | `BRIDGEBUILDER_DRY_RUN` | `false` |
| max_prs | — | `10` |
| max_files_per_pr | — | `50` |
| max_diff_bytes | — | `100000` |
| max_input_tokens | — | `8000` |
| max_output_tokens | — | `4000` |
| persona_path | — | `grimoires/bridgebuilder/BEAUVOIR.md` |

## Persona

Override the default reviewer persona by creating `grimoires/bridgebuilder/BEAUVOIR.md`. The default persona reviews across 4 dimensions: Security, Quality, Test Coverage, and Operational Readiness.

## Execution

This skill runs `entry.sh` which invokes the compiled Node.js application:

```bash
.claude/skills/bridgebuilder-review/resources/entry.sh [flags]
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All reviews completed successfully |
| 1 | One or more reviews encountered errors |
