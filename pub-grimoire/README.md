# Public Grimoire

Public documents from the Loa framework that are tracked in git.

## Purpose

While `loa-grimoire/` contains project-specific state (gitignored), `pub-grimoire/` contains documents intended for public sharing:

| Directory | Owner | Git Status | Contents |
|-----------|-------|------------|----------|
| `loa-grimoire/` | Project | Ignored | PRD, SDD, sprints, notes, trajectories |
| `pub-grimoire/` | Project | Tracked | Research, public docs, shareable artifacts |

## Structure

```
pub-grimoire/
├── research/           # Research documents and pattern analysis
├── docs/               # Public documentation
└── artifacts/          # Shareable build artifacts, reports
```

## Usage

When creating documents that should be:
- **Private/project-specific**: Use `loa-grimoire/`
- **Public/shareable**: Use `pub-grimoire/`

This pattern keeps the gitignore rules simple (no exceptions within grimoire folders) while providing a clear location for tracked documents.

## Template Protection

The main Loa template repository blocks non-README content in `pub-grimoire/` via CI checks. This ensures the template stays clean.

When working on project-specific branches, you can freely add content to `pub-grimoire/`. The protection only applies to PRs targeting `main`.
