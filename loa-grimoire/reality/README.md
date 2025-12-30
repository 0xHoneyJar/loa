# Reality Extraction (`reality/`)

This directory contains artifacts generated when mounting Loa onto an existing codebase.

## Purpose

When you run `/mount` on an existing project, Loa extracts the "reality" of your codebase:

- **Code structure analysis** - Components, modules, dependencies
- **Pattern detection** - Architectural patterns, conventions
- **Drift detection** - Gaps between docs and implementation

## Generated Files

- `drift-report.md` - Analysis of discrepancies between documentation and actual code
- Additional extraction artifacts as needed by the mounting process

## Workflow

1. Run `/mount` on your existing codebase
2. Agent analyzes code and generates reality artifacts
3. Use `/ride` to work with the extracted understanding
4. `drift-report.md` helps identify where docs need updating

## Note for Template Users

This directory is intentionally empty in the template. Reality extraction files are generated when you mount Loa onto your existing codebase.
