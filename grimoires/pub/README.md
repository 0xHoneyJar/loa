# Public Grimoire

Public documents from the Loa framework that are tracked in git.

## Purpose

The grimoire pattern separates private project state from public shareable content:

| Directory | Git Status | Purpose |
|-----------|------------|---------|
| `grimoires/loa/` | Ignored | Project-specific state (PRD, SDD, notes, trajectories) |
| `grimoires/pub/` | Tracked | Public documents (research, shareable artifacts) |

## Directory Structure

```
grimoires/pub/
├── research/     # Research and analysis documents
├── docs/         # Shareable documentation
└── artifacts/    # Public build artifacts
```

## Usage

When creating documents, choose based on visibility:

- **Private/project-specific** → `grimoires/loa/`
- **Public/shareable** → `grimoires/pub/`

## Template Protection

The main Loa template repository blocks non-README content in `grimoires/pub/` via CI checks.

Projects using Loa as a template can add their own public documents here - the template-guard
only applies to PRs targeting the upstream Loa repository.
