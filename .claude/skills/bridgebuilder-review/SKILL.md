---
name: bridgebuilder-review
description: "Bridgebuilder — Autonomous PR Review"
capabilities:
  schema_version: 1
  read_files: true
  search_code: true
  write_files: true
  execute_commands: true
  web_access: true
  user_interaction: false
  agent_spawn: true
  task_management: false
cost-profile: heavy
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
| model | `BRIDGEBUILDER_MODEL` | `claude-opus-4-7` |
| dry_run | `BRIDGEBUILDER_DRY_RUN` | `false` |
| max_prs | — | `10` |
| max_files_per_pr | — | `50` |
| max_diff_bytes | — | `100000` |
| max_input_tokens | — | `8000` |
| max_output_tokens | — | `4000` |
| persona_path | — | `grimoires/bridgebuilder/BEAUVOIR.md` |

## Self-Review Opt-In (#796 / vision-013)

When BB reviews a PR that modifies BB itself — or any other framework file under `.claude/`, `grimoires/`, `.beads/`, etc. — the Loa-aware filter normally strips those files from the review payload before the multi-model pass. This is correct for code-PR reviews (no review noise from grimoire side-effects) but inverts on self-modifying PRs (the framework files ARE the substance).

To opt a single PR into self-review (framework files visible to all reviewer models), apply the label:

```
bridgebuilder:self-review
```

When detected, BB:

- Skips the LOA framework exclusion for that PR's review pass — `.claude/`, `grimoires/`, `.beads/` files become reviewable
- **Continues to honor `.reviewignore` operator-curated patterns** (BR-003 / BB-001-security): `secrets/`, `vendor/`, private-doc patterns in your repo's `.reviewignore` still exclude their matches under self-review. The label is an Allow on framework files, NOT a global Deny suppressor.
- Surfaces a banner in the review output:
  - With `.reviewignore` user patterns: `[Loa-aware: self-review opt-in active — framework files included; .reviewignore (N user patterns) still honored (vision-013 / #796)]`
  - Without: `[Loa-aware: self-review opt-in active — framework files included (vision-013 / #796)]`
- Sets `truncated.selfReviewActive: true` on the typed `TruncationResult` (downstream consumers — cache key, audit logs, future analyzers — read this field; never substring-match the banner prose, BB-797-001)
- Leaves the global config (`loaAware`) untouched — the opt-in is per-PR, not workspace-wide
- The Pass 1 cache key includes `selfReview` as a distinct dimension, so toggling the label on a PR with unchanged `headSha` produces a fresh review (BB-003-cache)

Use this for: bridgebuilder TS adapter changes, cycle-planning PRs (PRD/SDD/sprint), construct manifest changes, anything where the framework artifacts ARE the diff. The label is a single source of truth (constant `SELF_REVIEW_LABEL` in `core/truncation.ts`); substring matches like `bridgebuilder:self-review-extra` do NOT trigger.

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
