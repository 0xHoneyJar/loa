# Sprint Audit Trail Preservation - Implementation Plan

**Date**: 2025-12-12
**Status**: Approved for Implementation

---

## Overview

Refactor `/implement`, `/review-sprint`, and `/audit-sprint` commands to preserve all A2A communication files in sprint-specific directories, creating a complete audit trail for organizational memory and intelligence.

---

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Sprint naming | Enforce `sprint-N` format | Self-explanatory, sortable, consistent |
| Backwards compatibility | Yes | Support flat structure for migration |
| Index file | Yes | `docs/a2a/index.md` tracks all sprints |
| Archival marker | Yes | `COMPLETED` marker file in sprint dir |

---

## Target Directory Structure

```
docs/a2a/
├── index.md                       # Sprint index with status tracking
├── README.md                      # Existing documentation
├── KERNEL.md                      # Existing kernel docs
│
├── sprint-1/
│   ├── COMPLETED                  # Marker file (empty, signals completion)
│   ├── reviewer.md                # Final implementation report
│   ├── engineer-feedback.md       # Review feedback history
│   └── auditor-sprint-feedback.md # Security audit record
│
├── sprint-2/
│   ├── COMPLETED
│   ├── reviewer.md
│   ├── engineer-feedback.md
│   └── auditor-sprint-feedback.md
│
├── sprint-3/                      # Current sprint (no COMPLETED marker)
│   ├── reviewer.md
│   ├── engineer-feedback.md
│   └── auditor-sprint-feedback.md
│
└── templates/                     # Template files (existing)
    ├── deployment-feedback.md.template
    └── deployment-report.md.template
```

---

## File: docs/a2a/index.md (Auto-generated)

```markdown
# Sprint Audit Trail Index

> Auto-generated index of all sprint A2A communication records.
> Last updated: {timestamp}

## Sprint Status Overview

| Sprint | Status | Engineer Report | Review | Security Audit |
|--------|--------|-----------------|--------|----------------|
| sprint-1 | COMPLETED | [reviewer.md](sprint-1/reviewer.md) | [feedback](sprint-1/engineer-feedback.md) | [audit](sprint-1/auditor-sprint-feedback.md) |
| sprint-2 | COMPLETED | [reviewer.md](sprint-2/reviewer.md) | [feedback](sprint-2/engineer-feedback.md) | [audit](sprint-2/auditor-sprint-feedback.md) |
| sprint-3 | IN_PROGRESS | [reviewer.md](sprint-3/reviewer.md) | pending | pending |

## Sprint Details

### sprint-1: Google Workspace Foundation
- **Started**: 2025-12-11
- **Completed**: 2025-12-12
- **Tasks**: 5 tasks, all completed
- **Security Audit**: APPROVED

### sprint-2: Transformation Pipeline Core
- **Started**: 2025-12-12
- **Completed**: 2025-12-12
- **Tasks**: 5 tasks, all completed
- **Security Audit**: APPROVED

### sprint-3: Discord Command Interface
- **Started**: 2025-12-12
- **Status**: IN_PROGRESS
```

---

## Command Changes

### 1. `/implement sprint-N`

**Changes to implement.md:**

```markdown
---
description: Launch the sprint implementation engineer to execute sprint tasks with feedback loop support
args: <sprint-name> [background]
---

## Phase -1: Sprint Directory Setup (NEW)

BEFORE any other work:

1. **Validate sprint argument format**:
   - Must match pattern `sprint-N` where N is a positive integer
   - Example valid: `sprint-1`, `sprint-2`, `sprint-10`
   - Example invalid: `sprint-one`, `sprint`, `1`, `google-workspace`

2. **Validate sprint exists in docs/sprint.md**:
   - Parse docs/sprint.md for sprint section
   - Confirm the sprint number exists in the plan

3. **Create sprint directory if needed**:
   ```
   if docs/a2a/{sprint-name}/ does not exist:
       mkdir docs/a2a/{sprint-name}/
   ```

4. **Set working paths for this session**:
   - REVIEWER_PATH = docs/a2a/{sprint-name}/reviewer.md
   - FEEDBACK_PATH = docs/a2a/{sprint-name}/engineer-feedback.md
   - AUDIT_PATH = docs/a2a/{sprint-name}/auditor-sprint-feedback.md

## Phase 0: Check for Security Audit Feedback
- Check {AUDIT_PATH} instead of docs/a2a/auditor-sprint-feedback.md
- (rest of phase unchanged, just use new path)

## Phase 1: Check for Previous Feedback
- Check {FEEDBACK_PATH} instead of docs/a2a/engineer-feedback.md
- (rest of phase unchanged, just use new path)

## Phase 4: Generate Report
- Write to {REVIEWER_PATH} instead of docs/a2a/reviewer.md
- (rest of phase unchanged, just use new path)

## Phase 5: Update Index (NEW)
After generating/updating the report:
1. Update docs/a2a/index.md with current sprint status
2. Set sprint status to "IN_PROGRESS" if not already tracked
```

---

### 2. `/review-sprint sprint-N`

**Changes to review-sprint.md:**

```markdown
---
description: Launch the senior technical lead reviewer to validate sprint implementation
args: <sprint-name> [background]
---

## Phase -1: Sprint Validation (NEW)

1. **Validate sprint argument**:
   - Must match `sprint-N` format
   - Sprint directory must exist: docs/a2a/{sprint-name}/

2. **Validate reviewer.md exists**:
   - docs/a2a/{sprint-name}/reviewer.md must exist
   - If not, abort with error: "No implementation report found for {sprint-name}"

3. **Set working paths**:
   - REVIEWER_PATH = docs/a2a/{sprint-name}/reviewer.md
   - FEEDBACK_PATH = docs/a2a/{sprint-name}/engineer-feedback.md

## Existing phases use new paths...

## On Approval (OPTION A):
- Write "All good" to {FEEDBACK_PATH}
- Update docs/sprint.md with checkmarks
- Update docs/a2a/index.md status
- DO NOT create COMPLETED marker yet (security audit pending)
```

---

### 3. `/audit-sprint sprint-N`

**Changes to audit-sprint.md:**

```markdown
---
description: Launch the paranoid-auditor to perform security audit of sprint implementation
args: <sprint-name> [background]
---

## Phase -1: Sprint Validation (NEW)

1. **Validate sprint argument**:
   - Must match `sprint-N` format
   - Sprint directory must exist: docs/a2a/{sprint-name}/

2. **Validate prerequisites**:
   - docs/a2a/{sprint-name}/reviewer.md must exist
   - docs/a2a/{sprint-name}/engineer-feedback.md must contain "All good"

3. **Set working paths**:
   - REVIEWER_PATH = docs/a2a/{sprint-name}/reviewer.md
   - FEEDBACK_PATH = docs/a2a/{sprint-name}/engineer-feedback.md
   - AUDIT_PATH = docs/a2a/{sprint-name}/auditor-sprint-feedback.md

## Existing phases use new paths...

## On Approval (OPTION B - APPROVED):
- Write approval to {AUDIT_PATH}
- Create docs/a2a/{sprint-name}/COMPLETED marker file
- Update docs/a2a/index.md:
  - Set sprint status to "COMPLETED"
  - Add completion timestamp
- Inform user: "Sprint {N} security audit APPROVED. Sprint is now COMPLETED."
```

---

## Backwards Compatibility

For projects with existing flat structure:

```markdown
## Backwards Compatibility Check

If the sprint argument is provided AND docs/a2a/{sprint-name}/ exists:
    Use new sprint-specific paths

Else if legacy files exist (docs/a2a/reviewer.md, etc.):
    WARN: "Legacy flat structure detected. Consider migrating to sprint directories."
    Continue with legacy paths for this session

Else:
    Create new sprint directory structure
```

---

## COMPLETED Marker File

**Purpose**: Signal that a sprint has passed all gates (implementation, review, security audit)

**Content** (docs/a2a/sprint-N/COMPLETED):
```
Sprint: sprint-N
Completed: 2025-12-12T14:30:00Z
Security Audit: APPROVED
Final Approver: paranoid-auditor
```

**Creation**: Only by `/audit-sprint` when verdict is "APPROVED - LETS FUCKING GO"

---

## Migration Script

Create `scripts/migrate-sprint-history.sh`:

```bash
#!/bin/bash
# Migrate existing A2A files to sprint directories

# Check if legacy files exist
if [ -f "docs/a2a/reviewer.md" ]; then
    # Determine current sprint from docs/sprint.md or git history
    # Move files to appropriate sprint directory
    # Update index.md
fi
```

---

## Implementation Order

1. **Phase 1**: Update implement.md
   - Add sprint validation
   - Add directory creation
   - Update all file paths

2. **Phase 2**: Update review-sprint.md
   - Add sprint argument requirement
   - Update all file paths

3. **Phase 3**: Update audit-sprint.md
   - Add sprint argument requirement
   - Add COMPLETED marker creation
   - Update all file paths

4. **Phase 4**: Create index.md template
   - Design auto-generation logic
   - Add to all three commands

5. **Phase 5**: Update CLAUDE.md
   - Document new structure
   - Update workflow examples

6. **Phase 6**: Migration
   - Create migration script
   - Migrate sprint-1, sprint-2 from git history
   - Generate initial index.md

---

## Testing Checklist

- [ ] `/implement sprint-1` creates docs/a2a/sprint-1/ if not exists
- [ ] `/implement sprint-1` writes to docs/a2a/sprint-1/reviewer.md
- [ ] `/implement sprint-1` reads feedback from docs/a2a/sprint-1/engineer-feedback.md
- [ ] `/review-sprint sprint-1` requires sprint argument
- [ ] `/review-sprint sprint-1` writes to docs/a2a/sprint-1/engineer-feedback.md
- [ ] `/audit-sprint sprint-1` creates COMPLETED marker on approval
- [ ] Index.md updated after each command
- [ ] Legacy flat structure still works with warning
- [ ] Invalid sprint format rejected with clear error

---

## Approval

- [x] Sprint naming: Enforce `sprint-N` format
- [x] Backwards compatibility: Yes
- [x] Index file: Yes, `docs/a2a/index.md`
- [x] Archival marker: Yes, `COMPLETED` file

**Ready for implementation.**
