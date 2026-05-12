# Cycle-106 PRD: Framework Template Hygiene (zone boundaries)

> **Status**: draft (awaiting /architect for SDD)
> **Cycle**: cycle-106-zone-hygiene
> **Created**: 2026-05-12
> **Source issues**:
> - [#818](https://github.com/0xHoneyJar/loa/issues/818) — `/update-loa`: zone-boundary leak (the canonical bug)
> - [#736](https://github.com/0xHoneyJar/loa/issues/736) — mount error (related)
> - [#817](https://github.com/0xHoneyJar/loa/issues/817) — spiral IMPL_FIX stub-writing (referenced from #818)
> - Operator-reported intuition: "my local observations whilst building Loa SHOULD not enter the framework / repo / template"

---

## 1. Problem statement

Loa is a framework template that operators install onto their own projects. Today, the framework's own project-state files (its `grimoires/loa/cycles/cycle-NNN/` planning history, its `grimoires/loa/NOTES.md`, its `grimoires/loa/handoffs/`) are **tracked in the framework repo** and propagate to downstream consumers via `/update-loa` merges.

**Empirical downstream evidence** (#818):
- `0xHoneyJar/loa-constructs` has accumulated **76 framework cycle files** under `grimoires/loa/cycles/cycle-{093,094,098,099,100,102}*/` — none authored by loa-constructs, all bled through framework merges.
- First leak observed in PR #225 (cycle-network-migration); pattern continued through every subsequent `/update-loa`.

**Empirical upstream evidence** (this operator's experience):
- Cycles 098 through 105 have shipped their full PRD/SDD/sprint docs into `grimoires/loa/cycles/` in this repo.
- `grimoires/loa/NOTES.md` carries this operator's session-specific decision logs.
- `grimoires/loa/known-failures.md` mixes universal entries (KF-005 beads) with operator-specific reproductions (KF-008 with PR-844 evidence).
- A new operator cloning `0xHoneyJar/loa` inherits all of it whether they want to or not.

**Root architectural cause** (#818 §"Root architectural cause"): both Loa framework AND its downstream consumers use IDENTICAL paths for project-zone files. `/update-loa` cannot distinguish "framework's project state" from "downstream's project state" without an explicit zone manifest.

## 2. Cycle goals

| ID | Goal | Acceptance |
|----|------|-----------|
| G1 | **Zone manifest contract** — declare which paths are framework-zone (propagate via /update-loa) vs project-zone (don't) | `.claude/data/zones.schema.yaml` ships as JSON Schema; `grimoires/loa/zones.yaml` ships as the framework's own instance |
| G2 | **`/update-loa` zone-aware merge filter** (#818 F2) | Phase 5.X skips `--diff-filter=A` ADDS that match project-zone patterns; tested with positive control (synthetic add under cycle-N/) |
| G3 | **`zone-write-guard.sh` PreToolUse hook** (#818 F1) | Hook reads zones.yaml + actor identity (project work / /update-loa / sync-constructs.sh); blocks zone-violating writes with operator-readable diagnostic |
| G4 | **`mount-loa` seeds properly** — new installs get empty project-zone scaffolding, not the framework's history | `mount-loa --dry-run` against a fresh repo lists what WOULD be added; project-zone paths show as "seed" (empty) not "copy" (with framework content) |
| G5 | **Framework history cleanup** — strip the framework's own operator history from the tracked tree | Cycles 098-105 + NOTES.md decision logs + handoffs/ become gitignored (operator-local); `git ls-files grimoires/loa/cycles/` returns zero entries on `main` after the migration |

## 3. Non-goals

- Removing the operator-local content. Cycle archives stay on the operator's disk. Just don't track them in git.
- Force-rewriting downstream history. The 76 leaked files in `loa-constructs` are downstream's problem to clean per their own cycle-0 plan. Cycle-106 stops the bleed; downstream cleans the legacy state.
- Replacing the existing `.claude/loa/CLAUDE.loa.md` import pattern. The Three-Zone Model in CLAUDE.md is correct; cycle-106 makes it enforceable.

## 4. Architecture sketch (informs /architect)

```
Framework repo (0xHoneyJar/loa)             Downstream project (any install)
┌──────────────────────────────┐            ┌──────────────────────────────┐
│ .claude/loa/  ← framework    │            │ .claude/loa/  ← inherited    │
│ .claude/scripts/ ← framework │  /update   │ .claude/scripts/ ← inherited │
│ .claude/data/zones.schema.yaml──── loa──→ │ .claude/data/zones.schema.yaml│
│                              │            │                              │
│ grimoires/loa/zones.yaml ← FW seed         │ grimoires/loa/zones.yaml ← project authored
│ grimoires/loa/runbooks/ ← FW   │           │ grimoires/loa/runbooks/ ← FW inherited
│                              │            │                              │
│ grimoires/loa/cycles/  ← GITIGNORED        │ grimoires/loa/cycles/  ← project's own
│ grimoires/loa/NOTES.md ← GITIGNORED        │ grimoires/loa/NOTES.md ← project's own
│ grimoires/loa/handoffs/← GITIGNORED        │ grimoires/loa/handoffs/← project's own
│ grimoires/loa/a2a/     ← GITIGNORED        │ grimoires/loa/a2a/     ← project's own
│ grimoires/loa/visions/ ← GITIGNORED        │ grimoires/loa/visions/ ← project's own
│ grimoires/loa/known-failures.md ← LIBRARY  │ grimoires/loa/known-failures.md ← inherited library + project additions
└──────────────────────────────┘            └──────────────────────────────┘
```

The zone manifest at `grimoires/loa/zones.yaml` declares paths in one of three modes:

| Mode | Semantics | Examples |
|------|-----------|----------|
| `framework` | Owned by framework; `/update-loa` propagates from upstream; project doesn't modify | `.claude/loa/**`, `.claude/scripts/**`, `.claude/data/**` |
| `project` | Owned by operator; `/update-loa` MUST NOT propagate framework's version; project's git owns it | `grimoires/loa/cycles/**`, `grimoires/loa/NOTES.md`, `grimoires/loa/handoffs/**` |
| `shared` | Both contribute; `/update-loa` merges sections; conflict-flagged when overlap | `grimoires/loa/known-failures.md` (framework ships universal entries + library; projects add their own) |

## 5. Sprint shape (informs /sprint-plan)

Estimated 2 sprints, 10-12 tasks total:

### Sprint 1 — Zone manifest + hook + framework gitignore
- T1.1 `.claude/data/zones.schema.yaml` JSON Schema (validates the YAML shape)
- T1.2 `grimoires/loa/zones.yaml` framework instance with the canonical project/framework/shared lists
- T1.3 `.claude/hooks/safety/zone-write-guard.sh` PreToolUse hook with bats coverage (positive + negative controls)
- T1.4 Gitignore tightening — add `grimoires/loa/cycles/`, `grimoires/loa/NOTES.md`, `grimoires/loa/handoffs/`, `grimoires/loa/a2a/`, `grimoires/loa/visions/` to `.gitignore`
- T1.5 Framework history clean — `git rm --cached` the operator-specific tree; commit as the inflection point
- T1.6 Bats: `tests/unit/zone-write-guard.bats` exercises hook behavior across actor types

### Sprint 2 — `/update-loa` filter + `mount-loa` seed
- T2.1 `/update-loa` Phase 5.X zone-aware merge filter — skip `--diff-filter=A` ADDS into project-zone paths
- T2.2 `mount-loa` seed behavior — new installs get empty project-zone scaffolding (not the framework's history)
- T2.3 Integration test: simulated /update-loa merge with a synthetic project-zone ADD asserts the ADD is filtered
- T2.4 Update `.claude/loa/CLAUDE.loa.md` Three-Zone Model section to reference zones.yaml as the enforceable mechanism
- T2.5 Issue #818 closure comment with cycle-106 PR links + new zones.yaml shape
- T2.6 Operator-facing runbook `grimoires/loa/runbooks/zone-hygiene.md` (will be FRAMEWORK-zone content; ships in template)

## 6. Acceptance criteria (informs /architect)

| AC | Statement |
|----|-----------|
| AC-1 | `.claude/data/zones.schema.yaml` exists; validates `grimoires/loa/zones.yaml` shape |
| AC-2 | `grimoires/loa/zones.yaml` lists project/framework/shared paths per §4 |
| AC-3 | `zone-write-guard.sh` PreToolUse hook blocks `/update-loa` writes into project-zone paths; allows project writes into project-zone; allows /update-loa writes into framework-zone |
| AC-4 | `/update-loa` Phase 5.X filters `--diff-filter=A` adds into project-zone paths; positive control test asserts a synthetic ADD is dropped |
| AC-5 | `git ls-files grimoires/loa/cycles/` returns zero entries on main after the migration |
| AC-6 | `mount-loa` on a fresh repo creates empty project-zone scaffolding; does NOT copy the framework's cycle/handoff/NOTES content |
| AC-7 | Issue #818 closed with cycle-106 evidence |

## 7. Risk register

| ID | Risk | Likelihood | Impact | Mitigation |
|----|------|-----------|--------|-----------|
| R1 | Removing tracked files breaks downstream `/update-loa` merges (the very pull operation that's leaking) | High | High | Sprint 2 lands the merge-filter BEFORE Sprint 1's gitignore + history-clean takes effect downstream. Stage the rollout: filter first, clean second. Or: do them in the same release tag so downstream gets both atomically. |
| R2 | Schema bikeshed — operators want different zone semantics than the proposed 3-mode (framework/project/shared) | Medium | Low | The schema is versioned. v1.0 ships with 3 modes; downstream can request additional modes via issue. |
| R3 | `zone-write-guard.sh` false-positives on legitimate operator workflows | Medium | Medium | Hook emits operator-readable diagnostic + `LOA_ZONE_GUARD_BYPASS=1` escape hatch for triage. Logged to trajectory for review. |
| R4 | History rewrite of framework cycles 098-105 forces force-push to main | High | Medium | We DON'T rewrite history. We just `git rm --cached` going forward. Existing main history keeps the framework-cycle commits; new main history is clean. This is the canonical "stop the bleed forward" pattern. |
| R5 | Some operator runbooks (e.g., headless-mode.md from cycle-104) ARE framework-zone but written during operator work | Low | Low | The zones.yaml lists `grimoires/loa/runbooks/**` as framework-zone explicitly. Runbooks stay tracked. |

## 8. Definition of done (cycle exit)

- [ ] All G1-G5 goals met per AC table
- [ ] Sprint 1 + Sprint 2 merged to main
- [ ] Issue #818 closed with cycle-106 PR references
- [ ] Downstream `loa-constructs` cycle-0 unblocked (cycle-106 ships F1 + F2 upstream)
- [ ] Operator's local working tree under `grimoires/loa/cycles/` is gitignored — cycles 098-105 live on disk but not in git
- [ ] New operator installing via `mount-loa` does NOT inherit the framework's operator history

## 9. Budget

- Engineering: 2-3 days operator-time across 2 sprints
- Live-API: **$0** (framework hygiene cycle; no model calls needed)
- Operator coordination: 1 round-trip with downstream loa-constructs maintainer (you) to confirm F1+F2 lands the unblock

## 10. Predecessor + successor

- **Predecessor**: cycle-105-beads-recovery (archived 2026-05-12; v1.153.0). Cycle-106 has no functional dependency on cycle-105; both are independent operational-debt cycles.
- **Successor**: Once cycle-106 lands, the framework template is structurally clean. Downstream `loa-constructs` cycle-0 can complete. Future cycles can use beads task tracking (now that KF-005 is closed) AND can ship cleanly to downstream consumers.

---

🤖 Generated as cycle-106 kickoff PRD, 2026-05-12. Next step: `/architect` to produce the SDD.
