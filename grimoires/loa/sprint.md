# Sprint Plan: Bridge Findings Fix — Iteration 4

**Source**: Bridge review iteration 3 findings (9 findings, score: 10)
**Bridge ID**: bridge-20260212-626561
**PR**: #293
**Branch**: `feature/run-bridge-cycle-005`

## Overview

Iteration 3 review found 4 MEDIUM + 2 LOW + 3 VISION findings. Score dropped from 72 → 10 (93% reduction). All remaining findings are minor hardening — no CRITICAL or HIGH issues remain. This sprint addresses all 6 actionable findings in a single sprint.

## Sprint 1: Final Hardening (MEDIUM + LOW)

### Task 1.1: Sanitize ITERATION and BRIDGE_ID in vision-capture sed command
- **Finding**: MEDIUM-1
- **File**: `.claude/scripts/bridge-vision-capture.sh`
- **Change**: Apply `sed 's/[\\/&]/\\\\&/g'` sanitization to `$ITERATION` and `$BRIDGE_ID` before interpolating into the sed command that updates index.md.
- **Why**: Defense-in-depth — even though these values are controlled, all sed-interpolated variables should be sanitized consistently.

### Task 1.2: Add trap for temp file cleanup in findings-parser
- **Finding**: MEDIUM-2
- **File**: `.claude/scripts/bridge-findings-parser.sh`
- **Change**: Add `trap "rm -f '$tmp_findings'" EXIT` after the `mktemp` call to ensure cleanup on error paths.
- **Why**: With `set -euo pipefail`, any failure skips the `rm -f` at the end, leaking temp files.

### Task 1.3: Fix fixture severity_weighted_score math
- **Finding**: MEDIUM-3
- **File**: `tests/unit/bridge-golden-path.bats`
- **Change**: Update all fixtures that show `severity_weighted_score: 26` with `by_severity: {critical: 1, high: 2, medium: 3, low: 2, vision: 2}` to use the correct score of 28.
- **Why**: Fixture data should match the actual weight calculation to avoid confusion.

### Task 1.4: Improve orchestrator resume test to exercise actual resume path
- **Finding**: MEDIUM-4
- **File**: `tests/unit/bridge-orchestrator.bats`
- **Change**: Rename the test to "state file records iteration count for resume" or restructure to actually invoke `--resume` flag and verify the orchestrator reads the correct iteration.
- **Why**: The current test verifies state file data, not the resume logic itself.

### Task 1.5: Validate bridge_id format at construction time
- **Finding**: LOW-1
- **File**: `.claude/scripts/bridge-state.sh`
- **Change**: Add a regex check `[[ "$bridge_id" =~ ^bridge-[0-9]{8}-[0-9a-f]{6}$ ]]` in `init_bridge_state()` to reject malformed bridge IDs before they can corrupt downstream commands.
- **Why**: Input validation at the source prevents issues in all downstream consumers.

### Task 1.6: Document depth limit change in NOTES.md
- **Finding**: LOW-2
- **File**: `grimoires/loa/NOTES.md`
- **Change**: Add a note in the blockers/warnings section that max bridge depth was changed from 10 to 5 in v1.34.0.
- **Why**: Users with existing configs expecting depth > 5 need to know about the limit change.
