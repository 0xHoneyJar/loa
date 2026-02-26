# SDD: Vision-Aware Planning — Creative Agency for AI Peers

**Version**: 1.1 (post-Flatline review)
**Cycle**: cycle-041
**PRD**: `grimoires/loa/prd.md`

---

## 1. Architecture Overview

This feature adds a **Vision Integration Layer** between the existing Vision Registry (write side, populated by bridge reviews) and the Planning Workflow (read side, `/plan-and-analyze`). The layer consists of:

1. **`vision-lib.sh`** — Shared library extracted from `bridge-vision-capture.sh`
2. **`vision-registry-query.sh`** — Query script for programmatic vision filtering
3. **Configuration** — New `vision_registry` section in `.loa.config.yaml`
4. **SKILL.md integration** — Vision-aware context loading in `discovering-requirements`
5. **Shadow mode** — Silent logging pipeline before active presentation

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  Bridge Reviews   │────▶│  Vision Registry  │────▶│  Planning Phase   │
│  (Bridgebuilder)  │     │  grimoires/loa/   │     │  /plan-and-analyze │
│                   │     │  visions/          │     │                   │
│  WRITES entries   │     │  index.md          │     │  READS + filters  │
│  via capture.sh   │     │  entries/*.md      │     │  via query.sh     │
└──────────────────┘     └──────────────────┘     └──────────────────┘
                                                          │
                              ┌────────────────────────────┤
                              ▼                            ▼
                     ┌──────────────┐            ┌──────────────┐
                     │ Shadow Mode   │            │ Active Mode   │
                     │ Log to JSONL  │            │ Present to    │
                     │ (silent)      │            │ user + track  │
                     └──────────────┘            └──────────────┘
```

### Design Principle: Extraction, Not Duplication

All shared logic lives in `vision-lib.sh`. Both the write side (`bridge-vision-capture.sh`) and read side (`vision-registry-query.sh`) source this library. No function is duplicated.

## 2. Component Design

### 2.1 `vision-lib.sh` — Shared Library

**Path**: `.claude/scripts/vision-lib.sh`
**Sourced by**: `bridge-vision-capture.sh`, `vision-registry-query.sh`

```bash
#!/usr/bin/env bash
# vision-lib.sh — Shared vision registry functions
# Version: 1.0.0

# Functions extracted from bridge-vision-capture.sh:
# - vision_load_index()     — parse index.md into structured output
# - vision_match_tags()     — tag overlap matching
# - vision_record_ref()     — atomic reference counting
# - vision_validate_entry() — schema validation
# - vision_sanitize_text()  — content sanitization for context injection
# - vision_update_status()  — lifecycle transitions
# - vision_extract_tags()   — file-path-to-tag mapping
```

#### Key Functions

**`vision_load_index()`**
```bash
# Parse index.md table into JSON array
# Input: $1=visions_dir
# Output: JSON array to stdout
# [{"id":"vision-001","title":"...","source":"...","status":"Captured","tags":["a","b"],"refs":3}]
vision_load_index() {
  local visions_dir="${1:?}"
  local index_file="$visions_dir/index.md"

  [[ -f "$index_file" ]] || { echo "[]"; return 0; }

  # Parse markdown table rows into JSON
  grep '^| vision-' "$index_file" 2>/dev/null | while IFS= read -r line; do
    local id title source status tags_raw refs
    id=$(echo "$line" | awk -F'|' '{print $2}' | xargs)
    title=$(echo "$line" | awk -F'|' '{print $3}' | xargs)
    source=$(echo "$line" | awk -F'|' '{print $4}' | xargs)
    status=$(echo "$line" | awk -F'|' '{print $5}' | xargs)
    tags_raw=$(echo "$line" | awk -F'|' '{print $6}' | xargs)
    refs=$(echo "$line" | awk -F'|' '{print $7}' | xargs)

    # Validate required fields (skip malformed)
    [[ -n "$id" && -n "$status" ]] || continue

    # Parse tags
    local tags_json
    tags_json=$(echo "$tags_raw" | tr -d '[]' | tr ',' '\n' | \
      xargs -I{} echo {} | jq -R . | jq -s .)

    jq -n --arg id "$id" --arg title "$title" --arg source "$source" \
      --arg status "$status" --argjson tags "$tags_json" \
      --argjson refs "${refs:-0}" \
      '{id:$id, title:$title, source:$source, status:$status, tags:$tags, refs:$refs}'
  done | jq -s '.'
}
```

**`vision_match_tags()`**
```bash
# Match work context tags against vision tags
# Input: $1=work_tags (comma-separated), $2=vision_tags_json, $3=min_overlap
# Output: overlap count to stdout
vision_match_tags() {
  local work_tags="$1"
  local vision_tags_json="$2"
  local min_overlap="${3:-2}"

  local overlap=0
  for wtag in $(echo "$work_tags" | tr ',' ' '); do
    if echo "$vision_tags_json" | jq -e --arg t "$wtag" 'index($t) != null' >/dev/null 2>&1; then
      overlap=$((overlap + 1))
    fi
  done
  echo "$overlap"
}
```

**`vision_sanitize_text()`**
```bash
# Sanitize vision text for safe context injection (SKP-002)
# Strips instruction patterns, truncates, extracts structured fields only
# Input: $1=text
# Output: sanitized text to stdout
vision_sanitize_text() {
  local text="$1"
  local max_chars="${2:-500}"

  # Strip instruction-like patterns
  text=$(echo "$text" | sed -E '
    s/<system[^>]*>[^<]*<\/system[^>]*>//g
    s/<prompt[^>]*>[^<]*<\/prompt[^>]*>//g
    s/```[^`]*```//g
  ')

  # Truncate to max chars
  text="${text:0:$max_chars}"

  # Strip trailing partial word
  text=$(echo "$text" | sed 's/ [^ ]*$//')

  echo "$text"
}
```

**`vision_record_ref()`** — Extracted from existing `record_reference()` with atomic write:
```bash
vision_record_ref() {
  local vid="$1" bridge_id="$2"
  local visions_dir="${3:-${PROJECT_ROOT}/grimoires/loa/visions}"
  local index_file="$visions_dir/index.md"

  # ... existing logic from bridge-vision-capture.sh:75-121 ...
  # Key change: all sed writes use tmp+mv (already the case)
  # This is the atomic write pattern required by SKP-003
}
```

### 2.2 `vision-registry-query.sh` — Query Script

**Path**: `.claude/scripts/vision-registry-query.sh`

```bash
#!/usr/bin/env bash
# vision-registry-query.sh — Query vision registry for planning integration
# Version: 1.0.0
#
# Usage:
#   vision-registry-query.sh \
#     --tags "architecture,multi-model" \
#     --status "Captured,Exploring" \
#     --min-overlap 2 \
#     --max-results 3 \
#     --json
#
# Exit Codes:
#   0 - Success (even if no results)
#   1 - Error
#   2 - Missing arguments

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/vision-lib.sh"

# Dependency check (IMP-003)
for cmd in jq yq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: $cmd is required but not installed" >&2
    echo "Install: brew install $cmd (macOS) or apt-get install $cmd (Linux)" >&2
    exit 2
  fi
done
```

**Arguments:**

| Argument | Description | Default |
|----------|-------------|---------|
| `--tags` | Comma-separated work context tags | Required |
| `--status` | Comma-separated status filter | `Captured,Exploring` |
| `--min-overlap` | Minimum tag overlap | 2 |
| `--max-results` | Maximum results returned | 3 |
| `--visions-dir` | Vision registry path | `grimoires/loa/visions` |
| `--json` | Output JSON (default is human-readable) | false |
| `--include-text` | Include sanitized insight text | false |

**Output (JSON mode):**
```json
[
  {
    "id": "vision-003",
    "title": "Constitutional Governance for Agent Economies",
    "status": "Captured",
    "tags": ["architecture", "constraints"],
    "refs": 4,
    "score": 7,
    "matched_tags": ["architecture", "constraints"],
    "insight": "Configuration governance across model selection..."
  }
]
```

**Scoring algorithm** (per IMP-001):
```
score = (tag_overlap * 3) + (refs * 2) + recency_bonus
recency_bonus = 1 if Date field exists AND within last 30 days, else 0
```
*(IMP-004)*: The `Date` field in vision entries is optional in the schema. When absent, `recency_bonus` defaults to 0 (no bonus). This ensures scoring is deterministic regardless of whether Date is populated.

### 2.3 Configuration Schema

**New section in `.loa.config.yaml`:**

```yaml
# Vision Registry Integration (v1.42.0)
vision_registry:
  enabled: false           # Master switch — default OFF, opt-in
  shadow_mode: true        # Log matches silently before presenting
  shadow_cycles_before_prompt: 2
  status_filter:
    - Captured
    - Exploring
  min_tag_overlap: 2
  max_visions_per_session: 3
  ref_elevation_threshold: 3
  propose_requirements: false  # Experimental — behind feature flag
```

**Config reading pattern** (consistent with existing Loa config style):
```bash
vr_enabled=$(yq eval '.vision_registry.enabled // false' .loa.config.yaml 2>/dev/null || echo "false")
vr_shadow=$(yq eval '.vision_registry.shadow_mode // true' .loa.config.yaml 2>/dev/null || echo "true")
vr_min_overlap=$(yq eval '.vision_registry.min_tag_overlap // 2' .loa.config.yaml 2>/dev/null || echo "2")
vr_max=$(yq eval '.vision_registry.max_visions_per_session // 3' .loa.config.yaml 2>/dev/null || echo "3")
```

### 2.4 SKILL.md Integration

**File**: `.claude/skills/discovering-requirements/SKILL.md`

**Addition to Phase 0 (Context Synthesis)**, after reality file loading:

```markdown
### Step 0.5: Vision Registry Loading (v1.42.0)

If `vision_registry.enabled: true` in `.loa.config.yaml`:

1. Derive work context tags from:
   - Sprint plan file paths (if exists)
   - PRD keywords (if this is a fresh start)
   - User's original request text (mapped through extract_pr_tags patterns)

2. **Tag derivation rules** *(IMP-001)*: Work context tags are derived in priority order:
   - From sprint plan: extract file paths, map through `vision_extract_tags()` path-to-tag rules
   - From user request text: keyword matching against controlled vocabulary (`architecture`, `security`, `constraints`, `multi-model`, `testing`, `philosophy`, `orchestration`)
   - From PRD sections: section headers mapped to tags (e.g., "Security" → `security`)
   - Tags are deduplicated and sorted before matching

3. Run vision query:
   ```bash
   visions=$(.claude/scripts/vision-registry-query.sh \
     --tags "$work_tags" \
     --status "$(yq eval '.vision_registry.status_filter | join(",")' .loa.config.yaml)" \
     --min-overlap "$(yq eval '.vision_registry.min_tag_overlap // 2' .loa.config.yaml)" \
     --max-results "$(yq eval '.vision_registry.max_visions_per_session // 3' .loa.config.yaml)" \
     --include-text \
     --json)
   ```

3. **Shadow mode** (`shadow_mode: true`):
   - Log results to `grimoires/loa/a2a/trajectory/vision-shadow-{date}.jsonl`
   - Do NOT present to user
   - Increment shadow cycle counter

4. **Active mode** (`shadow_mode: false`):
   - Present matched visions per FR-2 template
   - Record references via `vision_record_ref()`
   - Wait for user decision per vision (Explore/Defer/Skip)
```

### 2.5 Shadow Mode Pipeline

**Shadow log format** (`grimoires/loa/a2a/trajectory/vision-shadow-{date}.jsonl`):
```json
{
  "timestamp": "2026-02-26T14:00:00Z",
  "cycle": "cycle-041",
  "phase": "plan-and-analyze",
  "work_tags": ["architecture", "philosophy"],
  "matches": [
    {
      "vision_id": "vision-003",
      "score": 7,
      "matched_tags": ["architecture"],
      "would_have_shown": true
    }
  ],
  "shadow_cycle_number": 1,
  "total_shadow_cycles": 2
}
```

**Shadow cycle counter** *(IMP-002)*: Stored in a separate state file (NOT in `.loa.config.yaml` which is user-edited config):

**File**: `grimoires/loa/visions/.shadow-state.json`
```json
{
  "shadow_cycles_completed": 1,
  "last_shadow_run": "2026-02-26T14:00:00Z",
  "matches_during_shadow": 3
}
```
Updates use atomic write (tmp+mv) to prevent corruption from concurrent sessions.

**Graduation check**: After each shadow cycle, if `_shadow_cycles_completed >= shadow_cycles_before_prompt`, the next `/plan-and-analyze` invocation presents the shadow summary and asks the user to graduate to active mode.

## 3. Data Flow

### 3.1 Write Path (Existing — No Changes)

```
Bridge Review → VISION findings → bridge-vision-capture.sh → vision entry files + index.md
```

`bridge-vision-capture.sh` will be refactored to source `vision-lib.sh` for shared functions, but its external behavior and arguments are unchanged.

### 3.2 Read Path (New)

```
/plan-and-analyze Phase 0
  → Read .loa.config.yaml (vision_registry section)
  → If disabled: skip entirely
  → Derive work_context_tags from request/sprint context
  → Call vision-registry-query.sh
    → Sources vision-lib.sh
    → vision_load_index() — parse index.md
    → Filter by status
    → vision_match_tags() — score each vision
    → Sort by score, take top N
    → If --include-text: vision_sanitize_text() on each
    → Output JSON
  → If shadow_mode:
    → Log to trajectory JSONL
    → Increment counter
    → Check graduation
  → If active_mode:
    → Present to user
    → vision_record_ref() for each shown
    → Process user decisions (Explore/Defer/Skip)
```

### 3.3 Refactoring `bridge-vision-capture.sh`

The existing script keeps all its current entry points and arguments. The change is internal — functions move to `vision-lib.sh`:

| Function | Current Location | New Location |
|----------|-----------------|-------------|
| `update_vision_status()` | capture.sh:32-66 | vision-lib.sh |
| `record_reference()` | capture.sh:75-121 | vision-lib.sh |
| `extract_pr_tags()` | capture.sh:129-152 | vision-lib.sh |
| `check_relevant_visions()` | capture.sh:157-207 | vision-lib.sh |

`bridge-vision-capture.sh` adds at top: `source "$SCRIPT_DIR/vision-lib.sh"` and removes the inline function definitions.

## 4. Vision Registry Schema (FR-1.5)

### Index Format

**File**: `grimoires/loa/visions/index.md`

```markdown
<!-- schema_version: 1 -->
# Vision Registry

| ID | Title | Source | Status | Tags | Refs |
|----|-------|--------|--------|------|------|
| vision-001 | Example Vision | Bridge iter 2, PR #100 | Captured | architecture, security | 0 |
```

### Entry Format

**File**: `grimoires/loa/visions/entries/vision-001.md`

Required fields (validated by `vision_validate_entry()`):
- `**ID**:` — must match filename
- `**Source**:` — bridge iteration and PR
- `**Status**:` — one of: Captured, Exploring, Proposed, Implemented, Deferred
- `**Tags**:` — bracket-enclosed, comma-separated
- `## Insight` section — the vision description
- `## Potential` section — why it matters

Optional fields:
- `**PR**:` — PR number
- `**Date**:` — ISO 8601
- `## Connection Points` — links to related findings

### Validation

```bash
vision_validate_entry() {
  local entry_file="$1"
  local errors=()

  [[ -f "$entry_file" ]] || { echo "SKIP: file not found"; return 1; }

  grep -q '^\*\*ID\*\*:' "$entry_file" || errors+=("missing ID field")
  grep -q '^\*\*Source\*\*:' "$entry_file" || errors+=("missing Source field")
  grep -q '^\*\*Status\*\*:' "$entry_file" || errors+=("missing Status field")
  grep -q '^\*\*Tags\*\*:' "$entry_file" || errors+=("missing Tags field")
  grep -q '^## Insight' "$entry_file" || errors+=("missing Insight section")

  if [[ ${#errors[@]} -gt 0 ]]; then
    echo "INVALID: ${errors[*]}" >&2
    return 1
  fi
  return 0
}
```

## 5. Security Design

### Content Sanitization (SKP-002, SKP-003-blocker)

Vision text passes through a **strict allowlist extraction** pipeline before entering any planning context:

1. **Structured field extraction** (primary defense): Parse entry file, extract ONLY the text between `## Insight` and the next `##` heading. Discard all other content. This is allowlist-based — only known-safe sections are loaded, everything else is dropped.
2. **Normalization**: Decode HTML entities, strip zero-width characters, normalize whitespace
3. **Pattern stripping** (secondary defense): Remove `<system>`, `<prompt>`, code fences, and instruction-like patterns from the extracted text
4. **Length truncation**: 500 chars max per vision insight
5. **Context boundary**: Vision text is presented as quoted markdown block with explicit delimiters, never as system instructions

**Adversarial test corpus**: Tests include entries with `<system>` tags, encoded instructions, nested markdown, and indirect prompt patterns. See `tests/fixtures/vision-registry/entry-injection.md`.

### Concurrency Safety (SKP-003, SKP-002)

File mutations use `flock` for mutual exclusion plus atomic write (tmp+mv):

```bash
vision_atomic_write() {
  local target_file="$1"
  local lock_file="${target_file}.lock"
  local tmp_file="${target_file}.tmp"

  # flock around read-modify-write to prevent lost updates
  (
    flock -w 5 200 || { echo "ERROR: Could not acquire lock on $lock_file" >&2; return 1; }
    # Caller's modification runs here with exclusive access
    "$@"
  ) 200>"$lock_file"
}
```

- `vision_record_ref()` — flock + tmp+mv on index.md
- `vision_update_status()` — flock + tmp+mv on index.md and entry files
- Shadow state writes — flock + tmp+mv on `.shadow-state.json`
- In Agent Teams mode, vision writes additionally serialized through team lead
- `_require_flock()` from `compat-lib.sh` checks portability (macOS: `brew install util-linux`)

### No External API Calls

Vision processing is entirely local. No vision content is sent to external models. The Flatline Protocol reviews the PRD (which may reference visions), but vision text itself stays in the local planning context.

## 6. Testing Strategy

### Unit Tests

**File**: `tests/unit/vision-lib.bats`

| Test | Description |
|------|-------------|
| `vision_load_index empty registry` | Returns `[]` for empty/missing index |
| `vision_load_index parses table` | Correctly extracts all fields from markdown table |
| `vision_load_index skips malformed` | Skips rows with missing required fields |
| `vision_match_tags overlap counting` | Correct overlap count for various inputs |
| `vision_match_tags zero overlap` | Returns 0 when no tags match |
| `vision_sanitize_text strips instructions` | Removes `<system>` and similar patterns |
| `vision_sanitize_text truncates` | Respects max character limit |
| `vision_validate_entry valid` | Returns 0 for well-formed entry |
| `vision_validate_entry missing fields` | Returns 1 with specific error messages |

**File**: `tests/unit/vision-registry-query.bats`

| Test | Description |
|------|-------------|
| `query empty registry` | Returns `[]`, exit 0 |
| `query with matches` | Returns correctly scored and sorted results |
| `query respects max-results` | Caps output to N entries |
| `query respects min-overlap` | Excludes below-threshold visions |
| `query status filter` | Only returns matching statuses |
| `query --include-text` | Includes sanitized insight text |
| `query scoring algorithm` | Verifies weight formula produces expected ranking |

### Integration Tests

**File**: `tests/integration/vision-planning-integration.bats`

| Test | Description |
|------|-------------|
| `shadow mode logs to trajectory` | Vision matches written to JSONL, not shown |
| `shadow graduation prompt` | After N cycles, summary appears |
| `active mode presents visions` | Matched visions shown in Phase 0 output |
| `ref counter increments` | Surfaced visions get ref count bumped |
| `config disabled = no change` | When `enabled: false`, zero vision code runs |
| `bridge-vision-capture still works` | Refactored capture script produces identical output |

### Fixtures

**Directory**: `tests/fixtures/vision-registry/`

| Fixture | Purpose |
|---------|---------|
| `index-empty.md` | Empty registry (header only) |
| `index-three-visions.md` | 3 visions with various statuses and tags |
| `index-malformed.md` | Contains rows with missing columns |
| `entry-valid.md` | Well-formed vision entry |
| `entry-malformed.md` | Missing required sections |
| `entry-injection.md` | Contains `<system>` tags and code fences |

## 7. File Inventory

### New Files

| File | Purpose |
|------|---------|
| `.claude/scripts/vision-lib.sh` | Shared vision library |
| `.claude/scripts/vision-registry-query.sh` | Query script |
| `tests/unit/vision-lib.bats` | Library unit tests |
| `tests/unit/vision-registry-query.bats` | Query unit tests |
| `tests/integration/vision-planning-integration.bats` | Integration tests |
| `tests/fixtures/vision-registry/*.md` | Test fixtures |

### Modified Files

| File | Change |
|------|--------|
| `.claude/scripts/bridge-vision-capture.sh` | Source `vision-lib.sh`, remove inline functions |
| `.claude/skills/discovering-requirements/SKILL.md` | Add Step 0.5 vision loading |
| `.loa.config.yaml.example` | Add `vision_registry` section |
| `.loa.config.yaml` | Add `vision_registry` section (user's config) |

### Unchanged Files

| File | Why |
|------|-----|
| `.claude/data/bridgebuilder-persona.md` | VISION generation is already correct |
| `.claude/data/constraints.json` | C-PERM-002 already permits vision exploration |
| `.claude/scripts/flatline-orchestrator.sh` | No vision awareness needed in Flatline |

## 8. Migration & Backward Compatibility

### Zero-Impact Default

When `vision_registry.enabled` is absent or `false`:
- No vision code executes during `/plan-and-analyze`
- No new files created
- No behavioral change whatsoever

### Bootstrap for Existing Registries

If `grimoires/loa/visions/index.md` doesn't exist but `grimoires/loa/visions/entries/` has files:
- `vision_load_index()` returns `[]` (no crash)
- A one-time bootstrap can be run: `vision-registry-query.sh --bootstrap` to generate index from entries

### `bridge-vision-capture.sh` Refactoring

The refactoring to source `vision-lib.sh` is backward compatible:
- All existing entry points (`--check-relevant`, `--record-reference`, `--update-status`, main capture mode) work identically
- The `source` directive adds ~0ms to script startup
- If `vision-lib.sh` is missing, capture script exits with error code 2 and a clear message: `"ERROR: vision-lib.sh not found at $SCRIPT_DIR/vision-lib.sh — run /update-loa to restore"` *(IMP-009)*. No silent fallback to inline functions, as that would diverge behavior between write and read paths
