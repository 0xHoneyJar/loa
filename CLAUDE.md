@.claude/loa/CLAUDE.loa.md

# Project-Specific Instructions

> This file contains project-specific customizations that take precedence over the framework instructions.
> The framework instructions are loaded via the `@` import above.

## Context Intake Discipline (read FIRST at session start)

Before any substantive work — before reading PRD/SDD/sprint, before grepping
the codebase, before drafting a plan — every agent in this repo MUST consult
the known-failures **INDEX**, not the full 157KB log:

1. If `.loa.config.yaml`'s `known_failures.surface_at_session_start` is `true`,
   the SessionStart hook (`.claude/hooks/loa-kf-surface.sh`) has already printed
   a compact symptom → KF table (with recurrence) into this session's context —
   read it. Otherwise regenerate the same data on demand:
   `bash .claude/scripts/grimoire-index.sh`, then read the `## kf` section of
   `grimoires/loa/INDEX.md` (derived; symptom + numeric recurrence per KF-NNN).
2. When a symptom matches what you are triaging, open
   `grimoires/loa/known-failures.md`, jump to that `## KF-NNN:` heading, and read
   only its **Reading guide** section — that is the actionable next-step text.
   Reading it prevents re-attempting prior dead-ends (e.g. bumping
   `max_output_tokens` on `gpt-5.5-pro` empty-content; re-running BB hoping the
   network recovers; trying to fix `beads_rust` mid-sprint).
3. Read the whole file only when authoring a NEW entry (dedup check) or repairing
   the ledger itself.

The file remains append-only and uses a structured schema (KF-NNN entries with
Status / Symptom / Recurrence count / Attempts table / Reading guide).
**Recurrence count ≥ 3** is the load-bearing signal — that failure class is
structural; route through the upstream issue, do not retry the listed attempts.

When you observe a degradation that's already documented in known-failures.md:
increment its recurrence and append an evidence row (commit SHA / PR# / run ID)
via `bash .claude/scripts/lib/kf-write-lib.sh recur --id KF-NNN` and
`kf-write-lib.sh attempt …`. When you observe a NEW degradation, add a fresh
entry via `kf-write-lib.sh new …`. The point of the file is to compound across
sessions — it only works if every session contributes.

For code navigation, consult `grimoires/loa/REPO-MAP.md` (generated ranked symbol
map; regenerate via `bash .claude/scripts/repo-map-gen.sh`) before broad grep
sweeps of `.claude/`.

## Team & Ownership

- **Primary maintainer**: @deep-name
- **Default PR reviewer**: @deep-name — always request review from them
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
