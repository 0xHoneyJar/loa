# SDD: Vision Registry Graduation — Query API, Lifecycle, Spiral Integration

**Issue**: #486
**Cycle**: 069
**PRD**: `grimoires/loa/prd.md`
**Date**: 2026-04-14

---

## 1. System Architecture

### 1.1 Component Overview

```
┌─────────────────────────────────────────────────────────┐
│                    CLI Layer (new)                       │
│  vision-query.sh          vision-lifecycle.sh            │
│  (filter/format/rebuild)  (promote/archive/reject/etc)   │
└────────────┬─────────────────────┬──────────────────────┘
             │   sources           │   sources
             ▼                     ▼
┌─────────────────────────────────────────────────────────┐
│                 Library Layer (existing)                  │
│  vision-lib.sh                                           │
│  (11 functions: load, match, validate, sanitize,         │
│   update_status, atomic_write, lore elevation, etc.)     │
│  + modified: Archived/Rejected status support            │
└────────────┬─────────────────────┬──────────────────────┘
             │   reads/writes      │
             ▼                     ▼
┌─────────────────────────────────────────────────────────┐
│                   Data Layer (existing)                   │
│  grimoires/loa/visions/                                  │
│  ├── index.md            (pipe-delimited table)          │
│  └── entries/            (vision-NNN.md files)           │
│                                                          │
│  grimoires/loa/lore/discovered/visions.yaml (elevation)  │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│              Integration Layer (modified)                 │
│  spiral-orchestrator.sh  seed_phase() full mode          │
│  bridge-vision-capture.sh  octal bug fix                 │
└─────────────────────────────────────────────────────────┘
```

### 1.2 File Inventory

| File | Action | Zone | Authorization |
|------|--------|------|---------------|
| `.claude/scripts/vision-query.sh` | **New** | System | PRD cycle-069 |
| `.claude/scripts/vision-lifecycle.sh` | **New** | System | PRD cycle-069 |
| `.claude/scripts/vision-lib.sh` | **Modify** | System | PRD cycle-069 |
| `.claude/scripts/bridge-vision-capture.sh` | **Modify** | System | PRD FR-4 |
| `.claude/scripts/spiral-orchestrator.sh` | **Modify** | System | PRD FR-3 |
| `grimoires/loa/visions/index.md` | **Rebuild** | State | Standard |
| `.loa.config.yaml` | **Modify** | State | PRD FR-6 |
| `tests/unit/vision-query.bats` | **New** | App | Standard |
| `tests/unit/vision-lifecycle.bats` | **New** | App | Standard |
| `tests/unit/vision-seed-full.bats` | **New** | App | Standard |

## 2. Data Model

### 2.1 Vision Entry Schema (Canonical — Flatline IMP-008)

```markdown
# Vision: <TITLE>

**ID**: vision-NNN
**Source**: <free-text source reference>
**PR**: #<number> | (omitted)
**Date**: <ISO-8601 UTC timestamp>
**Status**: Captured|Exploring|Proposed|Implemented|Deferred|Archived|Rejected
**Tags**: [comma-separated, lowercase-hyphenated]
**Archived-Reason**: <text>       (present only when Status=Archived)
**Rejected-Reason**: <text>       (present only when Status=Rejected)

## Insight
<Content — this section is the only text extracted for context injection>

## Potential
<Exploration opportunities>

## Connection Points
- <Provenance references>
```

### 2.2 Frontmatter Parser Contract

The parser extracts key-value pairs from `**Key**: Value` lines between the H1 header and the first `## ` section heading. Rules:

- Keys: case-sensitive exact match (`**ID**:`, `**Status**:`, etc.)
- Values: everything after `: ` to end of line, trimmed
- Tags: strip `[]`, split on `,`, trim each, lowercase
- Missing optional fields (`PR`, `Archived-Reason`, `Rejected-Reason`): omitted from output, not null
- Malformed entries: quarantined (`parse_error: true` in JSON output), not fatal
- Invalid status values: quarantined

### 2.3 Seed Context Schema (Flatline IMP-004)

```json
{
  "mode": "full",
  "query": {
    "tags": ["security", "architecture"],
    "statuses": ["Captured", "Exploring", "Proposed"],
    "limit": 10
  },
  "visions": [
    {
      "id": "vision-009",
      "title": "Audit-Mode Context Filtering",
      "tags": ["security", "epistemic-enforcement"],
      "status": "Captured",
      "date": "2026-02-19T...",
      "insight_excerpt": "First 200 chars...",
      "relevance_score": 0.8
    }
  ],
  "total_bytes": 1234,
  "budget_bytes": 4096,
  "truncated": false
}
```

### 2.4 Status Lifecycle State Machine

```
                 ┌──────────┐
                 │ Captured │
                 └────┬─────┘
                      │ explore
                      ▼
                 ┌──────────┐
                 │ Exploring│
                 └────┬─────┘
                      │ propose
                      ▼
                 ┌──────────┐
           ┌─────│ Proposed │─────┐
           │     └──────────┘     │
           │ (implement)          │ defer
           ▼                      ▼
    ┌─────────────┐        ┌──────────┐
    │ Implemented │        │ Deferred │
    └─────────────┘        └──────────┘
         (terminal)

    From ANY non-terminal state:
    ├── promote ──→ Implemented (shortcut, creates lore entry)
    ├── archive ──→ Archived    (terminal, reason optional)
    └── reject  ──→ Rejected    (terminal, reason required)

    Terminal states: Implemented, Archived, Rejected
    No transitions out of terminal states (exit code 5).
```

## 3. Component Design

### 3.1 `vision-query.sh` — Query CLI

**Location**: `.claude/scripts/vision-query.sh`

**Dependencies**: sources `vision-lib.sh`, `bootstrap.sh`

**Flow**:
1. Parse CLI flags into filter variables
2. If `--rebuild-index`: call `_rebuild_index()`, exit
3. Scan `grimoires/loa/visions/entries/vision-*.md` (glob, not index)
4. For each file: parse frontmatter via `_parse_entry()`
5. Apply filters (AND-combined): tags, status, source, date range, min-refs
6. Sort by date descending (default)
7. Apply `--limit`
8. Format output per `--format` flag

**Key functions**:

```bash
_parse_entry() {
  # Input: $1=entry_file_path
  # Output: JSON object to stdout, or empty on parse failure
  # Extracts: id, title, source, pr, date, status, tags[], insight_excerpt
  # Uses awk for frontmatter extraction, jq --arg for JSON construction
}

_match_filters() {
  # Input: JSON entry on stdin, filter variables from environment
  # Output: entry JSON if matches, empty if not
  # Status: comma-split, case-insensitive match
  # Tags: ANY-match (vision has at least one of the query tags)
  # Source: grep -i pattern match
  # Date: ISO string comparison (lexicographic works for ISO-8601)
  # Min-refs: numeric comparison
}

_rebuild_index() {
  # Scan all entry files, parse, generate pipe-delimited table
  # Regenerate statistics section
  # Atomic write via vision_atomic_write()
  # Idempotent: deterministic output from same inputs
  # If --dry-run: diff current index vs rebuilt, report discrepancies, don't write
  #   (Bridgebuilder HIGH-2: visibility into what changed before overwriting)
  #
  # Scan-time consistency (Flatline IMP-005): rebuild takes a snapshot of all
  # entry files at scan start. Files modified during scan are detected via
  # mtime comparison (pre-scan vs post-parse). If any entry was modified
  # during the scan, log a warning but proceed (single-user model makes
  # this vanishingly rare). The global lifecycle lock prevents concurrent
  # lifecycle ops from modifying entries during rebuild.
}
```

**Exit codes** (per PRD IMP-001):

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | No results (empty JSON array on stdout) |
| 2 | Invalid arguments |
| 3 | Parse error (entry quarantined, non-strict mode continues) |
| 4 | I/O error |

### 3.2 `vision-lifecycle.sh` — Lifecycle CLI

**Location**: `.claude/scripts/vision-lifecycle.sh`

**Dependencies**: sources `vision-lib.sh`, `bootstrap.sh`

**Commands**:

```bash
vision-lifecycle.sh promote <vision-id>
vision-lifecycle.sh archive <vision-id> [--reason <text>]
vision-lifecycle.sh reject  <vision-id> --reason <text>
vision-lifecycle.sh explore <vision-id>
vision-lifecycle.sh propose <vision-id>
vision-lifecycle.sh defer   <vision-id> [--reason <text>]
```

**Promote flow** (ordered writes per SKP-002 override):

```
1. Validate: vision exists, not in terminal state
2. Generate lore entry → vision_generate_lore_entry()
3. Append to lore YAML → vision_append_lore_entry()  [idempotent]
4. Update status → vision_update_status() to "Implemented"  [flock atomic]
5. Rebuild index → vision-query.sh --rebuild-index  [idempotent]
6. Log trajectory → "vision_promoted" event
```

Recovery: if crash after step 3 but before step 4, lore has the entry but status is stale. Running promote again: step 3 is idempotent (vision_id check), step 4 updates status. Running `--rebuild-index` fixes any index drift.

**Lore path resolution** (Bridgebuilder CRITICAL-1): The promote flow delegates lore file path to `vision_append_lore_entry()` which reads from `$PROJECT_ROOT/.claude/data/lore/discovered/visions.yaml`. The CLI script MUST NOT hardcode this path — it calls the library function which owns path resolution.

**Archive/Reject flow**:

```
1. Validate: vision exists, not in terminal state
2. Sanitize reason text: strip |, newlines, control chars (SKP-005)
3. Add Archived-Reason/Rejected-Reason to entry frontmatter
4. Update status via vision_update_status()  [flock atomic]
5. Rebuild index
6. Log trajectory
```

**Input sanitization** (Flatline SKP-005):

```bash
_sanitize_reason() {
  local text="$1"
  # Strip pipe chars (break markdown tables)
  text="${text//|/-}"
  # Strip newlines (break frontmatter)
  text=$(echo "$text" | tr '\n' ' ')
  # Strip control characters
  text=$(echo "$text" | tr -d '\000-\037')
  # Trim
  echo "$text" | xargs
}
```

**Lifecycle lock scope** (Flatline IMP-001): Each lifecycle command acquires a global registry lock (`grimoires/loa/visions/.lifecycle.lock`) via flock before beginning the multi-step flow. This prevents concurrent promote + archive from interleaving. The lock wraps the entire command (validate → write → rebuild → log), not individual steps.

```bash
_with_lifecycle_lock() {
  local lock_file="${VISIONS_DIR}/.lifecycle.lock"
  (
    flock -w 10 200 || { echo "ERROR: Could not acquire lifecycle lock" >&2; exit 1; }
    "$@"
  ) 200>"$lock_file"
}
```

**Exit codes**: Same as vision-query.sh, plus code 5 for invalid transition.

### 3.3 `vision-lib.sh` Modifications

**Changes to existing code**:

1. **`vision_update_status()` (line 447)**: Add `Archived` and `Rejected` to the valid status case statement
2. **`vision_validate_entry()` (line 414)**: Add `Archived` and `Rejected` to valid statuses
3. **`vision_load_index()` (line 210)**: Add `Archived` and `Rejected` to valid statuses
4. **`vision_regenerate_index_stats()` (line 705-708)**: Add Archived and Rejected counts

**No new functions added to vision-lib.sh** — the CLI scripts handle their own logic and call existing library functions.

**Note** (Bridgebuilder MEDIUM-2): `vision_load_index()` remains for backward compatibility (used by `bridge-orchestrator.sh`) but is eventually-consistent with respect to lifecycle transitions. Between status update (step 4) and index rebuild (step 5) in promote flow, index readers see stale data. Callers needing current data should use `vision-query.sh` (file-scan) instead.

### 3.4 `bridge-vision-capture.sh` Octal Fix

**Line 227** — current:
```bash
next_number=$((local_max + 1))
```

**Fixed**:
```bash
next_number=$((10#$local_max + 1))
```

Forces base-10 interpretation. `009` → decimal 9 → `next_number=10`.

### 3.5 `spiral-orchestrator.sh` — seed_phase() Full Mode

**Location**: Lines 515-520 (current demotion fallback), inside `seed_phase()`.

**Current full mode path** (demotion):
```bash
log "WARNING: Full SEED mode requires Vision Registry (issue #486)"
log_trajectory "seed_mode_transition" '...'
seed_mode="degraded"
```

**Replacement logic**:

1. Extract tags from HARVEST sidecar (`cycle-outcome.json`) via deterministic mapping (Section 7.2)
2. **Sidecar validation** (Flatline IMP-006): Before extracting categories, validate sidecar has expected structure: `jq -e '.findings | type == "array"'`. If missing or wrong type, log warning and fall back to default tags (not hard fail — sidecar schema may evolve across cycles)
3. Fallback to `spiral.seed.default_tags` config if no sidecar or no mappable categories
3. Query registry: `vision-query.sh --tags <tags> --status Captured,Exploring,Proposed --format json --limit <max>`
4. Zero results → cold start with `seed_cold` trajectory event (not demotion to degraded)
5. Results found → build seed context JSON per schema (Section 2.3), write to `seed-context.md`
6. Budget enforcement: if JSON exceeds 4KB, drop lowest-relevance visions from end of array until under budget
7. Log `seed_full` trajectory event with query parameters and result stats

**Relevance scoring** (Bridgebuilder MEDIUM-1 + Flatline IMP-002): `vision_match_tags()` returns integer overlap count. Normalize to 0.0-1.0 float via jq arithmetic (bash integer division truncates to 0):
```bash
relevance=$(jq -n --argjson overlap "$overlap" --argjson total "$total_tags" \
  'if $total == 0 then 0 else ($overlap / $total) end')
```
**Zero-tag edge case**: If query has zero tags (empty default_tags config), all visions score 0.0. Sort falls through to date-only ordering (most recent first). This is correct behavior — no tags means no relevance signal, so recency is the only discriminator.

Sort descending by relevance score, then by date descending (tiebreaker).

## 4. Security Design

### 4.1 Input Sanitization

| Input | Sanitization | Target format |
|-------|-------------|---------------|
| `--reason` text | Strip `\|`, newlines, control chars | Markdown frontmatter |
| `--tags` filter | Validate `^[a-z][a-z0-9_-]*$` per tag | CLI argument |
| `--source` filter | Fixed-string match via `grep -Fi --` (Flatline SKP-004: no regex injection) | grep -Fi argument |
| `--status` filter | Validate against enum, case-insensitive | CLI argument |
| `--since`/`--before` | Validate ISO-8601 UTC format `^\d{4}-\d{2}-\d{2}`. Dates stored and compared as UTC only (Flatline SKP-005: lexicographic comparison correct for same-format UTC ISO-8601) | String comparison |
| Vision content → seed | `vision_sanitize_text()` (existing allowlist) | JSON via jq --arg |
| Lore YAML content | `jq --arg` for all values (existing pattern) | YAML via jq template |

### 4.2 Trust Boundaries

- Seed context from registry: marked `"machine-generated, advisory only"` (same as degraded mode)
- Vision entry content: only `## Insight` section extracted via `vision_sanitize_text()` allowlist
- Instruction injection patterns stripped by existing secondary defense in `vision_sanitize_text()`
- No shell expansion of any user-provided or vision-derived content

## 5. Error Handling

### 5.1 Ordered Write Recovery (SKP-002)

For multi-file lifecycle operations (promote):

| Step | File | Recovery |
|------|------|----------|
| 1. Lore append | `discovered/visions.yaml` | Idempotent (vision_id check) |
| 2. Status update | `entries/vision-NNN.md` | Flock atomic (tmp+mv) |
| 3. Index rebuild | `index.md` | Idempotent (deterministic from entries) |
| 4. Trajectory log | JSONL | Append-only, no rollback needed |

If crash between steps: re-run the lifecycle command. Idempotent steps skip, pending steps execute.

### 5.2 Parse Error Quarantine

When `_parse_entry()` encounters a malformed vision file:

- **Non-strict mode** (default): log warning, set `parse_error: true` in JSON output, continue
- **Strict mode** (`--strict`): log error, exit with code 3 after processing all files (report all errors, not just first)
- Quarantined entries included in `--format json` output with `parse_error: true` field
- Quarantined entries excluded from `--format table` output (clean display)
- `--rebuild-index` skips quarantined entries with warning

## 6. Testing Strategy

### 6.1 Test Files

| File | Coverage |
|------|----------|
| `tests/unit/vision-query.bats` | FR-1: filter combinations, multi-status, date range, format output, exit codes, rebuild, quarantine |
| `tests/unit/vision-lifecycle.bats` | FR-2: promote flow, archive/reject with reasons, terminal state blocking, input sanitization |
| `tests/unit/vision-seed-full.bats` | FR-3: tag derivation, query integration, budget truncation, cold-start fallback |
| `tests/unit/vision-octal.bats` | FR-4: octal bug fix for IDs 008, 009, 010+ |

### 6.2 Key Test Cases

**Query**:
- `--tags security` returns only security-tagged visions
- `--status Captured,Exploring` returns both statuses (comma-list)
- `--since 2026-04-01` filters by date
- `--format json` output validates with `jq .`
- `--format table` produces pipe-delimited rows
- `--rebuild-index` regenerates index matching entries
- Malformed entry quarantined in non-strict, error in strict

**Lifecycle**:
- `promote vision-003` creates lore entry + updates status + rebuilds index
- `promote` on terminal state exits with code 5
- `reject` without `--reason` exits with code 2
- `archive --reason "stale"` adds Archived-Reason to frontmatter
- Reason text with `|` and newlines is sanitized
- Double-promote is idempotent (lore append checks vision_id)

**Seed Full Mode**:
- With HARVEST sidecar: tags derived from findings categories
- Without HARVEST sidecar: falls back to configured default_tags
- Zero query results: cold-start (not degraded)
- Budget exceeded: lowest-ranked visions dropped, `truncated: true`
- Output validates against seed context schema

**Octal**:
- `local_max` of `007`: next = 8 (no issue)
- `local_max` of `008`: next = 9 (was octal error, now fixed)
- `local_max` of `009`: next = 10 (was octal error, now fixed)
- `local_max` of `099`: next = 100 (3-digit boundary)

## 7. Configuration

### 7.1 New Config Keys

```yaml
# .loa.config.yaml additions
vision_registry:
  enabled: true                     # Graduate: false → true

spiral:
  seed:
    mode: "full"                    # Graduate: "degraded" → "full"
    default_tags:                   # Fallback when no HARVEST context
      - architecture
      - security
    max_seed_visions: 10            # Max visions in seed context
```

### 7.2 HARVEST Category → Vision Tag Mapping (Flatline IMP-002)

| HARVEST category | Vision tag |
|-----------------|------------|
| `security` | `security` |
| `architecture` | `architecture` |
| `performance` | `performance` |
| `reliability` | `reliability` |
| `testing` | `testing` |
| `code-quality` | `code-quality` |
| `documentation` | `documentation` |
| (unmapped) | Skipped with warning |

Mapping hardcoded in `seed_phase()`. Future cycle can externalize to config if more categories emerge.

## 8. Architectural Pattern

**Append-Only Log with Decisions Layer** (Bridgebuilder REFRAME): The Vision Registry is structurally an append-only log (vision entries are captured, never mutated) with a decisions layer (lifecycle transitions annotate entries with outcomes). This is the same shape as the event bus DLQ pattern and the `append-only-queue-with-decisions-journal` lore pattern. The query CLI reads the log; the lifecycle CLI records decisions about log entries. Future systems needing this shape (e.g., DLQ entry management, lore pattern lifecycle) can inherit this architecture rather than reinventing it.

## 9. Implementation Order

1. **FR-4**: Octal bug fix (1 line, low-risk warm-up)
2. **vision-lib.sh**: Add Archived/Rejected states to existing functions
3. **FR-1**: `vision-query.sh` (core query + parser, tests)
4. **FR-5**: Index rebuild via `--rebuild-index` (depends on query parser)
5. **FR-2**: `vision-lifecycle.sh` (depends on query for rebuild)
6. **FR-3**: `seed_phase()` full mode (depends on query CLI)
7. **FR-6**: Config updates
8. Integration tests across components
