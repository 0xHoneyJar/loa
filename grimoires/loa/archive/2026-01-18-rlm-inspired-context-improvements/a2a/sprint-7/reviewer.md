# Sprint 7: Probe Infrastructure - Implementation Report

## Sprint Information
- **Sprint ID**: sprint-1 (local) / sprint-7 (global)
- **Cycle**: cycle-002 "RLM-Inspired Context Improvements"
- **Focus**: Probe-Before-Load infrastructure for context management

## Implementation Summary

### Completed Tasks

#### 1. Core Probe Functions (context-manager.sh)

**context_probe_file()** - Lines 339-377
- Probes file metadata without loading content
- Returns JSON with: file path, line count, size in bytes, file type, extension, estimated tokens
- Handles missing files gracefully with error JSON

**context_probe_dir()** - Lines 379-391 (+ helper)
- Probes directory for file inventory
- Returns up to 100 files sorted by line count (descending)
- Calculates total lines for codebase size assessment
- Categorizes codebase: small (<10K), medium (10K-50K), large (>50K)

**context_check_relevance()** - Lines 393-428
- Calculates 0-10 relevance score based on code keyword occurrences
- Configurable keywords from `.loa.config.yaml`
- Default keywords: export, class, interface, function, async, api, route, handler
- Caps contribution per keyword to prevent single-keyword dominance

**context_should_load()** - Lines 430-510
- Determines load strategy: `load` (full read), `excerpt` (grep excerpts), `skip`
- Decision logic:
  - Files under threshold (default 500 lines): always load
  - Large files with low relevance (<3): skip
  - Large files with medium relevance (3-6): excerpt
  - Large files with high relevance (>=6): load
- Returns structured JSON with decision, reason, relevance score, and probe data

#### 2. CLI Commands Added

| Command | Description |
|---------|-------------|
| `probe <path>` | Probe file or directory metadata |
| `should-load <file>` | Get loading decision for a file |
| `relevance <file>` | Get relevance score (0-10) |

All commands support `--json` flag for structured output.

#### 3. Configuration Options (.loa.config.yaml)

```yaml
context_management:
  # Probe-Before-Load (RLM Pattern) - v0.14.0
  probe_before_load: true
  max_eager_load_lines: 500
  require_relevance_check: true
  relevance_keywords:
    - export
    - class
    - interface
    - function
    - async
    - api
    - route
    - handler
  exclude_patterns:
    - "*.test.ts"
    - "*.spec.ts"
    - "node_modules/**"
    - "dist/**"
    - "build/**"
    - ".git/**"
  token_budget:
    small_codebase: 30000
    medium_codebase: 150000
    large_codebase: 500000
```

#### 4. Unit Tests (tests/unit/context-manager.bats)

Added 18 new tests covering:
- Probe command: single file, directory, missing paths, token estimation, human-readable output
- Should-load command: small files, large low-relevance, large high-relevance, missing files, argument validation
- Relevance command: high score, low score, missing files, score capping, argument validation

**Total tests**: 53 (35 existing + 18 new)

## Bug Fixes During Implementation

### Issue: `set -e` Killing Command Substitution

**Symptom**: `should-load` command produced no output for large files

**Root Cause**: The `context_should_load` function ends with `[[ "$decision" == "load" ]]` to set exit code. With `set -euo pipefail`, when decision was "skip", the exit code 1 caused the entire command substitution `result=$(context_should_load "$file")` to fail before capturing output.

**Fix**: Changed pattern from:
```bash
result=$(context_should_load "$file")
exit_code=$?
```
to:
```bash
result=$(context_should_load "$file") || exit_code=$?
```

Also converted implicit exit code (`[[ "$decision" == "load" ]]`) to explicit return statements for clarity.

### Issue: grep Count Parsing

**Symptom**: `[[: 0\n0: syntax error` in relevance calculation

**Root Cause**: `grep -c` output contained trailing whitespace/newlines

**Fix**: Added `| tr -d '[:space:]'` and validation:
```bash
count=$(grep -c "$keyword" "$file" 2>/dev/null | tr -d '[:space:]' || echo "0")
[[ -z "$count" || ! "$count" =~ ^[0-9]+$ ]] && count=0
```

## Files Modified

| File | Changes |
|------|---------|
| `.claude/scripts/context-manager.sh` | +~250 lines: probe functions, CLI commands, usage text |
| `.loa.config.yaml` | +35 lines: probe-before-load configuration |
| `tests/unit/context-manager.bats` | +18 tests for probe functionality |
| `grimoires/loa/ledger.json` | Updated sprint-1 status to in_progress |

## Verification

```bash
# All 53 tests pass
/tmp/bats-core/bin/bats tests/unit/context-manager.bats

# Manual verification
.claude/scripts/context-manager.sh probe src/
.claude/scripts/context-manager.sh should-load src/large-file.ts --json
.claude/scripts/context-manager.sh relevance src/api/handler.ts
```

## Next Steps (Sprint 2)

Per sprint.md, Sprint 2 focuses on "Integration & Workflow":
- Task 2.1: Integrate probe into Read tool recommendations
- Task 2.2: Create skill that uses probe infrastructure
- Task 2.3: Document workflow patterns

## Grounding

| Claim | Source |
|-------|--------|
| RLM probe-before-load pattern | PRD FR-10.1, SDD Section 3.1 |
| Default 500 line threshold | SDD Component Detail 3.1.1 |
| Relevance scoring 0-10 scale | SDD Component Detail 3.1.2 |
| Test coverage requirement | Sprint.md acceptance criteria |

---
*Implementation completed: 2026-01-17*
*Total implementation time: 1 session*
*Tests: 53/53 passing*
