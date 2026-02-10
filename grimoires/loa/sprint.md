# Sprint Plan: /ride Persistent Artifacts & Context-Aware Invocation

**Version**: 1.0.0
**Date**: 2026-02-10
**PRD**: grimoires/loa/prd.md (v1.0.0)
**SDD**: grimoires/loa/sdd.md (v1.0.0)
**Issue**: #270

---

## Sprint 1: MVP — Tool Access Fix + Write Checkpoints + Verification Gate

**Goal**: Fix the root cause (missing Write tool permission), add persistence checkpoints after every artifact-producing phase, and add a verification gate at Phase 10. This single sprint delivers the complete MVP.

### Task 1: Add Write tool to SKILL.md allowed-tools

- **File**: `.claude/skills/riding-codebase/SKILL.md`
- **Description**: Change frontmatter line 6 from `allowed-tools: Read, Grep, Glob, Bash(git *)` to `allowed-tools: Read, Grep, Glob, Write, Bash(git *)`. This is the root cause fix — the agent currently has no mechanism to write files to disk.
- **Acceptance Criteria**:
  - [ ] Frontmatter `allowed-tools` includes `Write`
  - [ ] All other frontmatter fields unchanged
  - [ ] SKILL.md backup created before modification (`SKILL.md.bak-270`)

### Task 2: Add write checkpoints after each artifact-producing phase

- **File**: `.claude/skills/riding-codebase/SKILL.md`
- **Description**: Add explicit file-write checkpoint blocks after each of the 10 artifact-producing phases. Each checkpoint instructs the agent to: (1) use the Write tool to persist the artifact, (2) verify with Glob that the file exists, (3) log failure to trajectory if missing. Checkpoints follow the template defined in SDD Section 4.2.
- **Checkpoint Locations**:
  - After Phase 1.5: CP-1 (`claims-to-verify.md`)
  - After Phase 2b: CP-2b (`reality/hygiene-report.md`)
  - After Phase 4.3: CP-4 (`drift-report.md`)
  - After Phase 5: CP-5 (`consistency-report.md`)
  - After Phase 6.3: CP-6a/6b (`prd.md`, `sdd.md`)
  - End of Phase 6.5: CP-6.5 (6 reality files + `.reality-meta.json`)
  - After Phase 7: CP-7 (`governance-report.md`)
  - After Phase 9.2: CP-9 (`trajectory-audit.md`)
- **Acceptance Criteria**:
  - [ ] 10 checkpoint blocks added (CP-1, CP-2b, CP-4, CP-5, CP-6a, CP-6b, CP-6.5, CP-6.5m, CP-7, CP-9)
  - [ ] Each checkpoint follows the standard template: Write → Glob verify → trajectory log on failure
  - [ ] Checkpoints reference the correct file paths per SDD Section 4.2
  - [ ] No existing phase content removed or modified (additive only)

### Task 3: Add Phase 10.0 artifact verification gate

- **File**: `.claude/skills/riding-codebase/SKILL.md`
- **Description**: Insert a new section `10.0 Artifact Verification Gate` before the existing Phase 10.1. This gate verifies all expected artifacts exist on disk using Glob, reports a pass/fail count, and attempts recovery for missing files. The ride must not complete if 0 artifacts are verified.
- **Acceptance Criteria**:
  - [ ] Phase 10.0 section added before existing 10.1
  - [ ] Full mode checklist includes all 10 artifacts (per SDD Section 5.1)
  - [ ] Verification uses Glob tool
  - [ ] Recovery attempt for missing files documented
  - [ ] Trajectory logging for verification results

### Task 4: Update Phase 10.2 completion summary

- **File**: `.claude/skills/riding-codebase/SKILL.md`
- **Description**: Update the existing completion summary template (Phase 10.2) to include: artifact verification count, checkmark per artifact, and `/translate-ride` as a next step.
- **Acceptance Criteria**:
  - [ ] Summary includes "Artifact Verification: X/Y files persisted"
  - [ ] Each artifact listed with verification indicator
  - [ ] `/translate-ride` added to next steps
  - [ ] `trajectory-audit.md` listed in artifacts

### Task 5: Add architecture-overview.md template (FR-3 stretch)

- **File**: `.claude/skills/riding-codebase/resources/references/output-formats.md`
- **Description**: Add the `architecture-overview.md` template to the Phase 6.5 section of output-formats.md. Also update SKILL.md Phase 6.5 reality file table to include `architecture-overview.md` with <1500 token budget.
- **Acceptance Criteria**:
  - [ ] Template added to output-formats.md with sections: System Components, Data Flow, Technology Stack, Entry Points
  - [ ] SKILL.md Phase 6.5 table updated with new row for `architecture-overview.md`
  - [ ] Token budget note: <1500 tokens
  - [ ] Total reality file budget updated (< 8500 tokens with architecture-overview)

### Task 6: Add staleness detection (FR-5 stretch)

- **Files**: `.claude/skills/riding-codebase/SKILL.md`, `.loa.config.yaml.example`
- **Description**: Add Phase 0.7 (Artifact Staleness Check) to SKILL.md between Phase 0.5 and Phase 1. Reads `.reality-meta.json` timestamp, checks `ride.staleness_days` config (default 7), prompts user if artifacts are fresh. Add `ride.staleness_days` config option to `.loa.config.yaml.example`.
- **Acceptance Criteria**:
  - [ ] Phase 0.7 section added to SKILL.md
  - [ ] Reads `generated_at` from `.reality-meta.json`
  - [ ] Respects `--fresh` flag bypass
  - [ ] Uses `AskUserQuestion` for fresh artifact prompt
  - [ ] `ride.staleness_days: 7` added to `.loa.config.yaml.example`
  - [ ] Trajectory logging for staleness check

### Task 7: Validation and smoke test

- **Description**: Verify all changes are internally consistent. Word count check on SKILL.md. Verify the checkpoint paths match translate-ride expectations. Run `wc -w` on modified SKILL.md to document the new word count.
- **Acceptance Criteria**:
  - [ ] SKILL.md word count documented (expected ~7,600 words)
  - [ ] All 5 translate-ride artifact paths confirmed in checkpoints
  - [ ] No syntax errors in SKILL.md markdown
  - [ ] Backup exists (`SKILL.md.bak-270`)
  - [ ] output-formats.md has valid markdown

---

## NFR Compliance

| NFR | Verification |
|-----|-------------|
| NFR-1: Performance | Write checkpoints add <20s total (Glob verification is fast) |
| NFR-2: Token budget | Architecture-overview.md adds <1500 tokens; total budget documented |
| NFR-3: Backward compatibility | No CLI argument changes; `context: fork` preserved; plan-and-analyze unchanged |
| NFR-4: No breaking changes | All changes additive to SKILL.md; phase structure preserved |

---

## Risk Mitigations

| Risk | Mitigation |
|------|-----------|
| `context: fork` blocks Write tool | Test after implementation; fallback to `context: shared` if blocked |
| Word count increases past #261 limit | Document for extraction to reference file during #261 Sprint 1 Task 5 |
| Agent ignores checkpoint instructions | Phase 10.0 verification gate catches missed writes |

---

## Rollback

If issues discovered post-merge:
1. Restore `SKILL.md.bak-270` to `SKILL.md`
2. Revert output-formats.md changes
3. Revert config example changes
4. Re-run `wc -w` to confirm word count restored

---

*Generated from PRD v1.0.0 and SDD v1.0.0 via /sprint-plan.*
