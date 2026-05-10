@.claude/loa/CLAUDE.loa.md

# Project-Specific Instructions

> This file contains project-specific customizations that take precedence over the framework instructions.
> The framework instructions are loaded via the `@` import above.

## Context Intake Discipline (read FIRST at session start)

Before any substantive work — before reading PRD/SDD/sprint, before grepping
the codebase, before drafting a plan — every agent in this repo MUST read:

- **`grimoires/loa/known-failures.md`** — the operational log of degradation
  patterns we've already hit and the workarounds that did NOT fix them.
  Reading this before triaging a problem prevents re-attempting prior dead-ends
  (e.g., bumping `max_output_tokens` on `gpt-5.5-pro` empty-content; re-running
  BB hoping the network recovers; trying to fix `beads_rust` mid-sprint).

The file is append-only and uses a structured schema (KF-NNN entries with
Status / Symptom / Recurrence count / Attempts table / Reading guide).
**Recurrence count ≥ 3** is the load-bearing signal — that failure class is
structural; route through the upstream issue, do not retry the listed attempts.

When you observe a degradation that's already documented in known-failures.md:
increment `Recurrence count` and add a row to `Attempts` with your evidence
(commit SHA / PR# / run ID). When you observe a NEW degradation: add a
fresh KF-NNN entry. The point of the file is to compound across sessions —
it only works if every session contributes.

## Team & Ownership

- **Primary maintainer**: @janitooor
- **Default PR reviewer**: @janitooor — always request review from them
- **Repo**: 0xHoneyJar/loa
- **CODEOWNERS**: `.github/CODEOWNERS` handles auto-assignment on GitHub

## How This Works

1. Claude Code loads `@.claude/loa/CLAUDE.loa.md` first (framework instructions)
2. Then loads this file (project-specific instructions)
3. Instructions in this file **take precedence** over imported content
4. Framework updates modify `.claude/loa/CLAUDE.loa.md`, not this file

## Related Documentation

- `.claude/loa/CLAUDE.loa.md` - Framework-managed instructions (auto-updated)
- `.loa.config.yaml` - User configuration file
- `PROCESS.md` - Detailed workflow documentation

## Construct Support

When `.run/construct-index.yaml` exists, constructs are installed and available:
- When a user mentions a construct name, check the index to resolve it
- Load the construct's persona file if available
- Scope to the construct's skill set and grimoire paths
- Use `construct-resolve.sh resolve <name>` for programmatic resolution
- Use `construct-resolve.sh compose <source> <target>` to check composition paths
