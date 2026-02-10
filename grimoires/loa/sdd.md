# SDD: /ride Persistent Artifacts & Context-Aware Invocation

**Version**: 1.0.0
**Status**: Draft
**Author**: Architecture Phase (architect)
**PRD**: grimoires/loa/prd.md (v1.0.0)
**Issue**: [#270](https://github.com/0xHoneyJar/loa/issues/270)
**Date**: 2026-02-10

---

## 1. Executive Summary

The `/ride` skill produces 10+ analysis artifacts across its phases but none persist to disk. The root cause is a tool access gap: the SKILL.md frontmatter restricts the agent to `Read, Grep, Glob, Bash(git *)` — the `Write` tool is not in the allowed tools list, and `Bash(git *)` restricts shell access to only `git` commands. The agent literally cannot write files with its current permissions.

This SDD designs three changes to fix the problem:

1. **Tool access fix** — Add `Write` to `allowed-tools` so the agent can persist files
2. **Write checkpoints** — Add explicit file-write verification after each artifact-producing phase
3. **Context-aware mode detection** — Add Phase 0.6 to select full vs lightweight execution

All changes are confined to SKILL.md (the skill definition) and its reference files. No application code changes.

---

## 2. Root Cause Analysis

### 2.1 The Tool Access Gap

The SKILL.md frontmatter currently specifies:

```yaml
---
name: ride
description: Analyze codebase to extract reality into Loa artifacts
context: fork
agent: Explore
allowed-tools: Read, Grep, Glob, Bash(git *)
---
```

**Problem**: The `Explore` agent type with these `allowed-tools` has no mechanism to write files:

| Tool | Available | Can Write Files |
|------|-----------|-----------------|
| `Read` | Yes | No |
| `Grep` | Yes | No |
| `Glob` | Yes | No |
| `Bash(git *)` | Yes | Only `git` commands — no `echo >`, `cat >`, `tee`, etc. |
| `Write` | **No** | Would enable file persistence |

The SKILL.md instructions say "create" and "generate" various files, and even use `mkdir -p` in code blocks, but the agent has no tool to actually write them. The instructions are correct; the tool permissions are wrong.

### 2.2 The Instruction Gap

Even with Write access, the SKILL.md instructions lack explicit file-write checkpoints. Phases say "Create `grimoires/loa/drift-report.md`" but don't include:

- An explicit "Use the Write tool to persist this file" instruction
- A verification step to confirm the file exists on disk
- A failure mode if the write doesn't happen

### 2.3 Impact Chain

```
Tool access gap → Agent renders content inline → No files on disk
  → /translate-ride pre-flight fails (no drift-report.md)
  → Cross-session context lost (no reality files)
  → /plan-and-analyze can't use cached ride results
```

---

## 3. Architecture Overview

### 3.1 Component Model

The fix modifies one file in the System Zone (`.claude/skills/riding-codebase/SKILL.md`) and two reference files. No new components are introduced.

```
.claude/skills/riding-codebase/
├── SKILL.md                          ← MODIFY (frontmatter + 4 sections)
└── resources/references/
    ├── output-formats.md             ← MODIFY (add architecture-overview template)
    └── analysis-checklists.md        ← NO CHANGE
```

### 3.2 Change Scope

| Component | Change Type | Lines Added | Lines Modified |
|-----------|-------------|-------------|----------------|
| SKILL.md frontmatter | Modify | 1 | 1 |
| SKILL.md Phase 0.6 (new) | Add | ~45 | 0 |
| SKILL.md Phase 2b checkpoint | Add | ~8 | 0 |
| SKILL.md Phase 4 checkpoint | Add | ~8 | 0 |
| SKILL.md Phase 5 checkpoint | Add | ~8 | 0 |
| SKILL.md Phase 6.5 checkpoint | Add | ~12 | 0 |
| SKILL.md Phase 7 checkpoint | Add | ~8 | 0 |
| SKILL.md Phase 9 checkpoint | Add | ~8 | 0 |
| SKILL.md Phase 10 verification | Add | ~25 | 3 |
| output-formats.md | Add | ~30 | 0 |
| **Total** | | ~153 | ~4 |

---

## 4. Detailed Design

### 4.1 Fix 1: Tool Access — Add Write to allowed-tools

**Change**: Modify SKILL.md frontmatter line 6.

**Before**:
```yaml
allowed-tools: Read, Grep, Glob, Bash(git *)
```

**After**:
```yaml
allowed-tools: Read, Grep, Glob, Write, Bash(git *)
```

**Rationale**: The `Write` tool is the Claude Code mechanism for persisting files to disk. Adding it to `allowed-tools` gives the Explore agent the ability to create the artifacts that every phase already instructs it to create. The `Bash(git *)` restriction remains unchanged — `Write` is the proper tool for file creation, not Bash redirects.

**Risk**: The agent could write to unexpected paths. Mitigated by:
- SKILL.md instructions explicitly list every output path
- All outputs are in the State Zone (`grimoires/loa/`)
- The `context: fork` setting limits blast radius

### 4.2 Fix 2: Write Checkpoints

Add explicit write-and-verify blocks after each artifact-producing phase. Each checkpoint follows the same pattern:

```markdown
### N.X File Persistence Checkpoint

**MANDATORY**: Use the `Write` tool to persist the artifact to disk, then verify:

1. Write `grimoires/loa/{artifact}.md` using the Write tool
2. Verify: `Glob` for `grimoires/loa/{artifact}.md` — must return the file
3. If verification fails: retry Write, then log failure to trajectory

**Do NOT render the artifact inline without also writing it to disk.**
```

#### Checkpoint Locations

| Phase | Artifact | Path | Checkpoint ID |
|-------|----------|------|---------------|
| 1.5 | Claims to Verify | `grimoires/loa/context/claims-to-verify.md` | CP-1 |
| 2b | Hygiene Report | `grimoires/loa/reality/hygiene-report.md` | CP-2b |
| 4.4 | Drift Report | `grimoires/loa/drift-report.md` | CP-4 |
| 5.1 | Consistency Report | `grimoires/loa/consistency-report.md` | CP-5 |
| 6.4 | PRD | `grimoires/loa/prd.md` | CP-6a |
| 6.4 | SDD | `grimoires/loa/sdd.md` | CP-6b |
| 6.5 | Reality Files (6 files) | `grimoires/loa/reality/*.md` | CP-6.5 |
| 6.5 | Reality Meta | `grimoires/loa/reality/.reality-meta.json` | CP-6.5m |
| 7.1 | Governance Report | `grimoires/loa/governance-report.md` | CP-7 |
| 9.3 | Trajectory Audit | `grimoires/loa/trajectory-audit.md` | CP-9 |

**Note**: Phase 6.5 has a compound checkpoint for 6 reality files + the meta JSON. The checkpoint verifies all files individually.

#### Checkpoint Template (inserted after each phase)

```markdown
### X.Y File Persistence Checkpoint (CP-N)

**WRITE TO DISK**: Use the `Write` tool now:

| File | Path |
|------|------|
| {Artifact Name} | `grimoires/loa/{path}` |

After writing, verify with `Glob`:
- Pattern: `grimoires/loa/{path}`
- Expected: 1 match

If the file does not exist after Write, retry once. If still missing, log:
```json
{"phase": N, "action": "write_failed", "artifact": "{path}", "status": "error"}
```
```

### 4.3 Fix 3: Context-Aware Mode Detection (Phase 0.6)

Add a new Phase 0.6 between Phase 0.5 (Codebase Probing) and Phase 1 (Context Discovery).

#### 4.3.1 Mode Detection Logic

```markdown
## Phase 0.6: Invocation Mode Detection

Determine execution mode before proceeding:

### Detection Priority (highest to lowest)

1. **`--full` flag**: If `--full` argument present → FULL mode
2. **Environment variable**: Check `LOA_RIDE_CALLER`
   - Not set or `user` → FULL mode
   - `plan-and-analyze` → LIGHTWEIGHT mode (unless override triggers)
3. **Artifact existence check**: If `grimoires/loa/drift-report.md` does NOT exist → FULL mode (override lightweight)
4. **Default**: FULL mode

### Mode Summary

| Mode | Phases Executed | Artifacts Produced |
|------|----------------|--------------------|
| **FULL** | All (0-10) | All reports + reality files + PRD/SDD |
| **LIGHTWEIGHT** | 0, 0.5, 1, 2, 2b, 6.5 | Reality files + claims-to-verify + hygiene report |

### Execution

After determining mode, log to trajectory:
```json
{"phase": 0.6, "action": "mode_detection", "mode": "FULL|LIGHTWEIGHT", "reason": "..."}
```

If LIGHTWEIGHT:
- Execute Phases 0-2b normally
- Skip Phases 3-6
- Execute Phase 6.5 (reality files)
- Skip Phases 7-8
- Execute Phase 9 (limited self-audit of reality files only)
- Execute Phase 10 (handoff)
```

#### 4.3.2 Practical Mode Detection

Since skills are invoked via the Skill tool (which doesn't support env vars), and `/plan-and-analyze` already handles staleness detection itself, the simplest approach is:

**`/ride` always runs FULL mode when invoked.** The lightweight behavior is achieved by `/plan-and-analyze` not invoking `/ride` at all when artifacts are fresh. This aligns with the existing staleness check in `plan-and-analyze.md` and requires no mode-switching complexity in SKILL.md.

If future requirements need lightweight mode, the detection can be added via:
- A marker file (`.run/ride-caller.json`) written by `/plan-and-analyze` before invocation
- Or the `--phase` argument already supported by ride.md (e.g., `--phase reality-only`)

**Recommendation for MVP**: Skip Phase 0.6 mode detection. Focus on Steps 1-3 (tool access + checkpoints + verification gate). The `/plan-and-analyze` integration already provides the "don't re-ride if fresh" behavior.

### 4.4 Stretch: Architecture Grounding Document (FR-3)

Add to Phase 6.5 reality file generation:

| File | Purpose | Token Budget |
|------|---------|-------------|
| `architecture-overview.md` | System component diagram, data flows, tech stack, entry points | < 1500 |

**Template** (added to `output-formats.md`):

```markdown
# Architecture Overview

> Token-optimized architecture grounding for agent consumption.
> Generated: [date] | Budget: <1500 tokens

## System Components

[ASCII component diagram derived from structure.md and api-routes.txt]

## Data Flow

1. [Primary data flow path with file references]
2. [Secondary paths]

## Technology Stack

| Layer | Technology | Evidence |
|-------|-----------|----------|
| [layer] | [tech] | [file:line] |

## Entry Points

| Entry | Path | Type |
|-------|------|------|
| [name] | [file path] | [HTTP/CLI/Worker/etc] |
```

This file is generated alongside the other 6 reality files in Phase 6.5, using the same code extraction data from Phase 2.

### 4.5 Stretch: Staleness Detection (FR-5)

Add to Phase 0 (after mount verification, before probing):

```markdown
### 0.7 Artifact Staleness Check

If `grimoires/loa/reality/.reality-meta.json` exists:

1. Read `generated_at` timestamp
2. Read `ride.staleness_days` from `.loa.config.yaml` (default: 7)
3. If artifacts are fresh (< staleness_days old) AND not `--fresh` flag:
   - Use `AskUserQuestion`: "Ride artifacts are N days old. Re-analyze or Skip?"
   - If skip: Exit early with message "Using existing ride artifacts"
4. If `--fresh` flag: proceed regardless of age

Log staleness check to trajectory.
```

**`.reality-meta.json` schema** (already partially defined in SKILL.md Phase 6.5):

```json
{
  "generated_at": "2026-02-10T14:30:00Z",
  "generator": "riding-codebase",
  "version": "1.0.0",
  "token_counts": {
    "index.md": 450,
    "api-surface.md": 1800,
    "types.md": 1900,
    "interfaces.md": 950,
    "structure.md": 900,
    "entry-points.md": 480,
    "architecture-overview.md": 1400
  },
  "total_tokens": 7880,
  "within_budget": true,
  "codebase_hash": "sha256:abc123..."
}
```

**Config addition** (`.loa.config.yaml.example`):

```yaml
ride:
  staleness_days: 7        # Days before ride artifacts are considered stale
```

---

## 5. Phase 10 Verification Gate

The existing Phase 10 (Maintenance Handoff) is extended with an artifact verification step. This is the final gate ensuring all files were persisted.

### 5.1 Verification Checklist

Add before the existing Phase 10.1 (Update NOTES.md):

```markdown
### 10.0 Artifact Verification Gate (BLOCKING)

Before handoff, verify ALL expected artifacts exist on disk.

**Full Mode Checklist**:

| # | Artifact | Path | Verify |
|---|----------|------|--------|
| 1 | Claims to Verify | `grimoires/loa/context/claims-to-verify.md` | Glob |
| 2 | Hygiene Report | `grimoires/loa/reality/hygiene-report.md` | Glob |
| 3 | Drift Report | `grimoires/loa/drift-report.md` | Glob |
| 4 | Consistency Report | `grimoires/loa/consistency-report.md` | Glob |
| 5 | PRD | `grimoires/loa/prd.md` | Glob |
| 6 | SDD | `grimoires/loa/sdd.md` | Glob |
| 7 | Reality Index | `grimoires/loa/reality/index.md` | Glob |
| 8 | Governance Report | `grimoires/loa/governance-report.md` | Glob |
| 9 | Trajectory Audit | `grimoires/loa/trajectory-audit.md` | Glob |
| 10 | Reality Meta | `grimoires/loa/reality/.reality-meta.json` | Glob |

**Procedure**:

1. For each file in the checklist, use `Glob` to verify existence
2. Count: passed / total
3. If any missing:
   - Log missing files to trajectory
   - Attempt to write missing artifacts from context (if content was generated but not persisted)
   - Re-verify
4. Report final count in completion summary

**The ride MUST NOT complete with 0/N artifacts verified.**
```

### 5.2 Updated Completion Summary

Modify the existing Phase 10.2 completion summary to include verification results:

```
The Loa Has Ridden

Artifact Verification: X/Y files persisted

Grimoire Artifacts Created:
- grimoires/loa/prd.md (Product truth)
- grimoires/loa/sdd.md (System truth)
- grimoires/loa/drift-report.md (Three-way analysis)
- grimoires/loa/consistency-report.md (Pattern analysis)
- grimoires/loa/governance-report.md (Process gaps)
- grimoires/loa/reality/* (Raw extractions + token-optimized files)
- grimoires/loa/trajectory-audit.md (Self-audit)

Next Steps:
1. Review drift-report.md for critical issues
2. Address governance gaps
3. /translate-ride for executive communications
4. Schedule stakeholder PRD review
5. Run /implement for high-priority drift
```

---

## 6. `/translate-ride` Compatibility

No changes needed to `/translate-ride` itself. The fix ensures artifacts exist at the paths its pre-flight already expects:

| translate-ride Pre-flight | Ride Fix |
|---------------------------|----------|
| `grimoires/loa/drift-report.md` must exist | CP-4 ensures Write + verify |
| `grimoires/loa/governance-report.md` loaded | CP-7 ensures Write + verify |
| `grimoires/loa/consistency-report.md` loaded | CP-5 ensures Write + verify |
| `grimoires/loa/reality/hygiene-report.md` loaded | CP-2b ensures Write + verify |
| `grimoires/loa/trajectory-audit.md` loaded | CP-9 ensures Write + verify |

The Phase 10 verification gate provides a final safety net.

---

## 7. Non-Functional Requirements

### 7.1 Performance

| Metric | Requirement | Design Impact |
|--------|-------------|---------------|
| Write checkpoint overhead | < 2s per checkpoint | Glob verification is fast; 10 checkpoints add < 20s total |
| Mode detection | < 1s | Single file existence check + JSON read |
| Full mode total | < 20 minutes | No change from current (write checkpoints add negligible time) |

### 7.2 Backward Compatibility

| Concern | Status |
|---------|--------|
| CLI arguments unchanged | `--full` already exists in ride.md; no new required args |
| `context: fork` preserved | No change to agent model |
| `/plan-and-analyze` integration | No changes needed; it already handles staleness |
| Existing SKILL.md structure | Phases numbered 0-10 preserved; 0.6 inserted in existing gap |

### 7.3 Word Count Impact

Current SKILL.md: ~6,905 words (already over the 5,000 word Anthropic benchmark).

Additions: ~153 lines (~750 words for checkpoints, mode detection, and verification gate).

New total: ~7,655 words. This exceeds the benchmark further, but:
- Issue #261 (Sprint 1, Task 5) already plans to refactor riding-codebase to ≤4,500 words
- The checkpoint instructions are repetitive by design (each follows the same template)
- Post-#261 refactoring can move checkpoint templates to `resources/references/persistence-protocol.md`

**Recommendation**: Implement the checkpoints inline for correctness, then extract to a reference file during the #261 refactoring sprint.

---

## 8. File Changes Summary

### 8.1 `.claude/skills/riding-codebase/SKILL.md`

| Section | Change |
|---------|--------|
| Frontmatter line 6 | Add `Write` to `allowed-tools` |
| After Phase 0.5 | Add Phase 0.6: Invocation Mode Detection (~45 lines) |
| After Phase 1.5 | Add CP-1: claims-to-verify write checkpoint (~8 lines) |
| After Phase 2b | Add CP-2b: hygiene-report write checkpoint (~8 lines) |
| After Phase 4.3 | Add CP-4: drift-report write checkpoint (~8 lines) |
| After Phase 5 | Add CP-5: consistency-report write checkpoint (~8 lines) |
| After Phase 6.3 | Add CP-6a/6b: PRD + SDD write checkpoint (~10 lines) |
| Phase 6.5 (end) | Add CP-6.5: reality files compound write checkpoint (~12 lines) |
| After Phase 7 | Add CP-7: governance-report write checkpoint (~8 lines) |
| After Phase 9.2 | Add CP-9: trajectory-audit write checkpoint (~8 lines) |
| Phase 10 (beginning) | Add 10.0: Artifact Verification Gate (~25 lines) |
| Phase 10.2 | Update completion summary template (~3 lines modified) |

### 8.2 `.claude/skills/riding-codebase/resources/references/output-formats.md`

| Section | Change |
|---------|--------|
| After reality file templates | Add architecture-overview.md template (~30 lines) |

### 8.3 `.loa.config.yaml.example`

| Section | Change |
|---------|--------|
| Root level | Add `ride.staleness_days: 7` config option (~3 lines) |

---

## 9. Testing Strategy

### 9.1 Smoke Test: Artifact Persistence

1. Invoke `/ride` on a small test codebase
2. After completion, verify all artifacts exist: `ls grimoires/loa/drift-report.md grimoires/loa/consistency-report.md grimoires/loa/governance-report.md grimoires/loa/reality/hygiene-report.md grimoires/loa/trajectory-audit.md`
3. **Pass**: All 5 report files + reality files exist
4. **Fail**: Any file missing

### 9.2 Smoke Test: Translate-Ride Pipeline

1. After `/ride` completes successfully
2. Invoke `/translate-ride`
3. **Pass**: `grimoires/loa/translations/EXECUTIVE-INDEX.md` is created
4. **Fail**: Pre-flight error about missing artifacts

### 9.3 Smoke Test: Mode Detection

1. Invoke `/ride` directly → should run all phases (FULL mode)
2. Check trajectory log for mode detection entry
3. **Pass**: All 10 phases executed, all artifacts persisted

### 9.4 Verification Gate Test

1. Invoke `/ride` on a test codebase
2. Check completion summary includes "Artifact Verification: X/Y files persisted"
3. **Pass**: X = Y (all files verified)

---

## 10. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `context: fork` blocks Write tool | Medium | High | Test before merging; if blocked, change to `context: shared` |
| Agent ignores Write instructions | Low | High | Checkpoint verification catches this at Phase 10 |
| Word count increase delays #261 | Low | Low | Checkpoints can be extracted to reference file |
| Staleness check adds friction | Low | Low | `--fresh` flag bypasses; configurable via `ride.staleness_days` |

---

## 11. Implementation Order

| Step | Description | Blocking? |
|------|-------------|-----------|
| 1 | Add `Write` to `allowed-tools` in SKILL.md frontmatter | Yes — this unblocks everything |
| 2 | Add write checkpoints after each artifact-producing phase | Yes — ensures persistence |
| 3 | Add Phase 10.0 artifact verification gate | Yes — catches any missed writes |
| 4 | Update Phase 10.2 completion summary | No — cosmetic |
| 5 | Add Phase 0.6 mode detection (if implementing FR-2) | No — enhancement |
| 6 | Add architecture-overview.md template (FR-3 stretch) | No — enhancement |
| 7 | Add staleness detection (FR-5 stretch) | No — enhancement |
| 8 | Add `ride.staleness_days` to config example | No — with step 7 |

Steps 1-3 are the MVP. Steps 4-8 are progressive enhancements.

---

*Generated from PRD v1.0.0 via /architect. Architecture grounded against SKILL.md (443 lines), ride.md command definition, translate-ride.md expectations, and plan-and-analyze.md integration.*
