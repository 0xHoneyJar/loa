# Agent Working Memory

## Current Focus

| Field | Value |
|-------|-------|
| **Active Task** | Cycle-035: Minimal Footprint by Default — Submodule-First Installation |
| **Status** | Sprint plan complete — ready for `/run sprint-plan` |
| **Blocked By** | None |
| **Next Action** | `/run sprint-plan` to execute implementation |
| **Previous** | Cycle-034 archived (Declarative Execution Router + Adaptive Multi-Pass, PR #404, bridge flatlined) |

## Session Log

| Timestamp | Event | Details |
|-----------|-------|---------|
| 2026-02-24T12:00:00Z | Cycle-035 created | Minimal Footprint by Default, source issue #402 |
| 2026-02-24T12:05:00Z | Research complete | 12 cross-repo issues/PRs + web4.html + local codebase analyzed |
| 2026-02-24T12:10:00Z | Bridgebuilder comment posted | Issue #402, comprehensive architectural review with FAANG parallels |
| 2026-02-24T12:20:00Z | PRD written | 12 sections, 3 sprints, 7 FRs, full ecosystem impact analysis |
| 2026-02-24T13:00:00Z | SDD written | 11 sections, 3 sprints, critical @-import correction from PRD |
| 2026-02-24T13:05:00Z | PRD corrected | `.claude/loa` → `.loa/` per SDD §2.3 analysis |
| 2026-02-24T13:20:00Z | Sprint plan written | 3 sprints (global 44-46), 22 tasks, all 5 Flatline blockers addressed |

## Decisions

| ID | Decision | Reasoning | Date |
|----|----------|-----------|------|
| D-012 | Submodule stays at `.loa/` (NOT `.claude/loa`) | `.claude/loa` breaks `@.claude/loa/CLAUDE.loa.md` import — submodule root would nest the path. `.loa/` is mount-submodule.sh's existing design (line 50). | 2026-02-24 |
| D-013 | Memory Stack relocates to `.loa-cache/` | Project-local (not user-global) preserves multi-project isolation | 2026-02-24 |
| D-014 | `--vendored` flag for backward compat | Existing standard mode preserved; just no longer the default | 2026-02-24 |
| D-015 | Root docs gitignored by default | Generated on-demand by `/loa setup`, users can un-ignore if they want to commit | 2026-02-24 |

## Key Discovery

**`mount-submodule.sh` already exists** (619 lines in `.claude/scripts/`). The submodule installation path is fully implemented with:
- `safe_symlink()` security validation
- Mode detection in `.loa-version.json`
- Routing in `mount-loa.sh` at line 1463

The work is NOT building submodule support from scratch — it's **flipping the default** and resolving the `.loa/` path collision.

**Critical SDD Finding**: PRD proposed `.claude/loa` as submodule path. SDD analysis (§2.3) proved this breaks the `@.claude/loa/CLAUDE.loa.md` import chain. The @-import resolves to `.claude/loa/CLAUDE.loa.md` — if `.claude/loa` were the submodule root, that file would be at `.claude/loa/.claude/loa/CLAUDE.loa.md` (nested), unreachable. Submodule stays at `.loa/`, Memory Stack moves to `.loa-cache/`.

**Missing Symlinks Found**: mount-submodule.sh lacks symlinks for `.claude/hooks/`, `.claude/data/`, `.claude/loa/reference/`, `.claude/loa/feedback-ontology.yaml`, `.claude/loa/learnings/`. SDD §3.2 addresses these.

## Blockers

_None currently_

## Technical Debt

- TD-001: `.loa/` used for both Memory Stack and submodule target — RESOLVED in SDD (Memory Stack → `.loa-cache/`)
- TD-002: Stealth mode `apply_stealth()` only adds 4 .gitignore entries — RESOLVED in SDD §3.4 (expanded to 14)

## Learnings

| ID | Learning | Source | Date |
|----|----------|--------|------|
| L-012 | mount-submodule.sh is 619 lines and fully functional — submodule mode is already built | Explore agent analysis | 2026-02-24 |
| L-013 | hub-interface has 2,416 .ck/ files committed — stealth mode doesn't cover regenerable caches | Issue #393 audit | 2026-02-24 |
| L-014 | .gitignore already covers .ck/, .run/, .beads/ — the gap is stealth mode's 4-entry limitation | .gitignore analysis | 2026-02-24 |
| L-015 | Mode conflict detection in mount-loa.sh prevents accidental standard↔submodule switches | mount-loa.sh lines 1310-1333 | 2026-02-24 |
| L-016 | @-import in CLAUDE.md constrains submodule placement — `.claude/loa` is occupied by reference docs with CLAUDE.loa.md | SDD analysis §2.3 | 2026-02-24 |
| L-017 | mount-submodule.sh missing symlinks for hooks/, data/, loa/reference/ — these directories exist but aren't linked | SDD component analysis §3.2 | 2026-02-24 |

## Session Continuity

**Recovery Anchor**: Sprint plan for cycle-035 complete. 3 sprints (global 44-46), 22 tasks, ~985 lines estimated. Next step: `/run sprint-plan` to execute.

**Key Context**:
- Cycle: cycle-035 (Minimal Footprint by Default)
- Source: Issue #402
- Related: Issues #393 (stealth gap), #110 (install UX)
- Bridgebuilder comment: https://github.com/0xHoneyJar/loa/issues/402#issuecomment-3944873665
- Key file: `.claude/scripts/mount-submodule.sh` (619 lines, already functional)
- Key file: `.claude/scripts/mount-loa.sh` (1540 lines, needs default flip at line 183)
- Path collision: Memory Stack moves from `.loa/` to `.loa-cache/`; submodule stays at `.loa/`
- Sprints: sprint-44 (Foundation), sprint-45 (Migration+Polish), sprint-46 (Hardening)

**If resuming**: Run `/run sprint-plan` to begin implementation.
