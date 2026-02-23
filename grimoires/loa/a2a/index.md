# A2A Audit Trail Index

> Cycle: cycle-035 — Minimal Footprint by Default — Submodule-First Installation

## Sprint Status

| Sprint | Global ID | Status | Artifacts |
|--------|-----------|--------|-----------|
| sprint-1 | sprint-44 | **In Review** (conditional pass, 2 required fixes) | [reviewer.md](sprint-44/reviewer.md), [engineer-feedback.md](sprint-44/engineer-feedback.md) |

## Sprint 44 (sprint-1): Foundation — Default Flip + Symlinks + Gitignore

- **Implementation**: Complete (7/7 tasks)
- **Review**: Conditional pass — 2 required fixes (RF-1: dotfile bug in relocation, RF-2: EXIT trap override)
- **Audit**: Pending (blocked on review fixes)
- **30/30 tests passing**

### Required Fixes Before Audit

1. **RF-1** (HIGH): `mount-submodule.sh:167` — use `cp -r "$source"/. "$target"/` to capture dotfiles during Memory Stack relocation
2. **RF-2** (MEDIUM): `mount-loa.sh:1563` — combine EXIT trap handlers so `_exit_handler` is not silently dropped
