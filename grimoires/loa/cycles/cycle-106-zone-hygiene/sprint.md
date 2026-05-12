# Cycle-106 Sprint Plan: Framework Template Hygiene

> **Predecessors**: `prd.md`, `sdd.md`
> **Cycle**: cycle-106-zone-hygiene
> **Created**: 2026-05-12
> **Local sprint IDs**: sprint-1, sprint-2 (global IDs 156, 157 per ledger `next_sprint_number=156`)

---

## 1. Sprint shape

| Sprint | Theme | Tasks | Live API | Days |
|--------|-------|-------|---------|------|
| Sprint 1 | Manifest + hook + gitignore migration | 6 | $0 | 1-2 |
| Sprint 2 | /update-loa filter + mount-loa seed + #818 closure | 6 | $0 | 1-2 |

**Total**: 12 tasks across 2 sprints; ~2-3 days operator-time.

**Sequencing**: Sprint 1 lands the manifest + hook (defense in depth at write time) + the gitignore migration (stops the bleed in the framework's own repo). Sprint 2 lands the /update-loa filter (stops the bleed in downstream consumers) + mount-loa seeding.

---

## 2. Sprint 1 — Manifest + hook + gitignore migration

**Goal**: G1 + G3 + G5 from PRD §2 — zones.yaml shape + zone-write-guard hook + framework's own tracked tree cleaned up.

### Tasks

- [ ] **T1.1** Write `.claude/data/zones.schema.yaml` JSON Schema per SDD §2.1. Validates the zones.yaml shape (schema_version, zones.framework, zones.project, zones.shared, tracked_paths array per zone). → **[G1]**

- [ ] **T1.2** Write framework instance `grimoires/loa/zones.yaml` per SDD §2.2. Lists the canonical framework / project / shared paths. → **[G1]**

- [ ] **T1.3** Implement `.claude/hooks/safety/zone-write-guard.sh` per SDD §3. Reads zones.yaml + actor identity, decides ALLOW/BLOCK. Honors `LOA_ZONE_GUARD_BYPASS=1` + `LOA_ZONE_GUARD_DISABLE=1` escape hatches. → **[G3]**

- [ ] **T1.4** Schema validation `tests/unit/zones-schema.bats` — ZS-T1..T5 per SDD §8.3. → **[G1]**

- [ ] **T1.5** Hook coverage `tests/unit/zone-write-guard.bats` — ZWG-T1..T12 per SDD §8.1. Positive (project work in project zone) + negative (project work in framework zone, /update-loa in project zone) + escape-hatch + missing-config graceful degradation. → **[G3]**

- [ ] **T1.6** Gitignore tightening + framework history migration. Edit `.gitignore` per SDD §5. Run `git rm --cached -r ...` per SDD §6. Operator's local working tree preserved; tracked tree clean going forward. → **[G5]**

### Sprint 1 exit

- All 6 tasks landed
- `grimoires/loa/zones.yaml` validates against schema
- 12+5 = 17 new bats tests green
- `git ls-files grimoires/loa/cycles/` returns zero
- Hook installed and PreToolUse-registered (operator action — refresh via `.claude/scripts/install-loa-hooks.sh` or equivalent)

---

## 3. Sprint 2 — /update-loa filter + mount-loa seed + #818 closure

**Goal**: G2 + G4 from PRD §2 — the merge filter that stops the bleed downstream + mount-loa seeds correctly + issue #818 closed.

### Tasks

- [ ] **T2.1** Implement `/update-loa` Phase 5.X zone-aware merge filter per SDD §4. Reads zones.yaml, walks `--diff-filter=A` added files, drops any that match project-zone patterns. Diagnostic includes file + matching pattern. → **[G2]**

- [ ] **T2.2** Integration tests `tests/integration/update-loa-zone-filter.bats` — ULZF-T1..T6 per SDD §8.2. Synthetic merge with positive/negative controls. → **[G2]**

- [ ] **T2.3** Update `mount-loa` (or `mounting-framework` skill) per SDD §7. New installs get empty project-zone scaffolding (.gitkeep files for dirs, empty stubs for single-file paths) + framework-zone copies. → **[G4]**

- [ ] **T2.4** Bats coverage for mount-loa seed behavior. Synthetic fresh-repo + run mount-loa; assert framework files present + project-zone scaffolding is empty (not the framework's history). → **[G4]**

- [ ] **T2.5** New operator-facing runbook `grimoires/loa/runbooks/zone-hygiene.md` documenting the three zones, when to edit zones.yaml, how to handle conflicts in shared zone. → **[G1]**

- [ ] **T2.6** Comment on issue #818 with cycle-106 PR links + close it. Update `.claude/loa/CLAUDE.loa.md` Three-Zone Model section to reference zones.yaml as the enforceable mechanism. → **[G2, AC-7]**

### Sprint 2 exit

- All 6 tasks landed
- 6+5 = 11 new bats integration tests green
- Issue #818 closed with cycle-106 evidence
- Downstream `loa-constructs` cycle-0 unblocked (F1 + F2 ship upstream as part of this cycle)
- New `/zone-hygiene.md` runbook ships

---

## 4. Acceptance criteria (per PRD §6)

| AC | Sprint | Closing evidence |
|----|--------|-----------------|
| AC-1 schema exists + validates instance | Sprint 1 (T1.1, T1.4) | `tests/unit/zones-schema.bats` green |
| AC-2 zones.yaml instance complete | Sprint 1 (T1.2) | YAML lints + validates against schema |
| AC-3 hook blocks zone violations | Sprint 1 (T1.3, T1.5) | `tests/unit/zone-write-guard.bats` green |
| AC-4 /update-loa filter drops ADDs | Sprint 2 (T2.1, T2.2) | `tests/integration/update-loa-zone-filter.bats` green |
| AC-5 git ls-files grimoires/loa/cycles returns zero | Sprint 1 (T1.6) | CI gate from SDD §9 |
| AC-6 mount-loa seeds correctly | Sprint 2 (T2.3, T2.4) | mount-loa-seed.bats green |
| AC-7 issue #818 closed | Sprint 2 (T2.6) | GitHub issue state |

---

## 5. Dependencies

- **Inbound**: cycle-105 merged (PR #857 ✓; KF-005 closed)
- **Live API**: $0 across both sprints
- **CLI binaries**: `yq` v4+ on PATH (CI runner default + operator's environment; already used elsewhere in framework)
- **Outbound**: With cycle-106 shipped, framework template is clean. Future cycles can ship to downstream without zone-leak risk.

---

## 6. Risk register (refined from SDD §10)

| ID | Sprint affected | Mitigation |
|----|-----------------|-----------|
| R1 (bleed-stop sequencing) | Sprint 1 then Sprint 2 | Document in cycle-106 PR descriptions that BOTH must merge before next `/update-loa` for downstream consumers. Or land them in the same release tag. |
| R2 (schema bikeshed) | Sprint 1 | Versioned schema; v1.0 with 3 modes; extensions via issue tracker. |
| R3 (hook false-positives) | Sprint 1 (T1.5) | Hook diagnostics include the operator-readable explanation + override. `LOA_ZONE_GUARD_BYPASS=1` documented in runbook. |
| R4 (history rewrite cost) | Sprint 1 (T1.6) | We DON'T rewrite. `git rm --cached` is forward-only. Downstream's legacy state is theirs to clean. |
| R5 (runbook overlap) | Sprint 2 (T2.5) | New runbook is framework-zone; operator-specific runbooks live elsewhere (per Q1 in SDD §10). |

---

## 7. Definition of done (cycle exit)

- [ ] All 12 tasks shipped
- [ ] AC-1..AC-7 all closed
- [ ] Issue #818 state = CLOSED with cycle-106 PR references
- [ ] `git ls-files grimoires/loa/cycles/` returns zero on main
- [ ] Operator's working tree under `grimoires/loa/cycles/` continues to function locally (not deleted, just untracked)
- [ ] Downstream `loa-constructs` confirmed unblocked (or their cycle-0 referenced in #818 closure comment)
- [ ] Framework's Three-Zone Model claim in CLAUDE.md is empirically enforceable

---

🤖 Generated as cycle-106 sprint plan, 2026-05-12. Next step: `/run sprint-1` autonomous loop over T1.1-T1.6.
