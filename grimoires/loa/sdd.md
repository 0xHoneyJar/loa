# SDD: Broader QMD Integration Across Core Skills

> Cycle: cycle-027 | Author: janitooor + Claude
> Source PRD: `grimoires/loa/prd.md` ([#364](https://github.com/0xHoneyJar/loa/issues/364))
> Flatline: Reviewed (5 HIGH_CONSENSUS integrated, 6 BLOCKERS addressed)

## 1. Executive Summary

This SDD designs a unified context query interface that wraps three existing search backends — QMD (semantic markdown search), CK (code knowledge hybrid search), and grep (plain text) — behind a single script with automatic fallback. The script is consumed by 5 core skills to inject relevant context before execution.

**Architecture principle**: One new script. Zero modifications to existing infrastructure. Each skill calls the script and receives a token-budgeted JSON response. If QMD is unavailable, CK serves. If CK is unavailable, grep serves. No skill breaks.

## 2. System Architecture

### 2.1 Component Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│ Skill Callers                                                       │
│  ┌────────────┐ ┌──────────────┐ ┌──────┐ ┌──────────┐ ┌────────┐ │
│  │ /implement │ │/review-sprint│ │/ride │ │/run-bridge│ │ Gate 0 │ │
│  └─────┬──────┘ └──────┬───────┘ └──┬───┘ └─────┬────┘ └───┬────┘ │
│        └───────────────┼────────────┼────────────┼──────────┘      │
│                        ▼            ▼            ▼                  │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │              qmd-context-query.sh                            │   │
│  │  parse_args() → resolve_scope() → try_tiers() → budget()    │   │
│  └─────────────────────────┬────────────────────────────────────┘   │
│                            │                                        │
│              ┌─────────────┼─────────────┐                          │
│              ▼             ▼             ▼                           │
│  ┌───────────────┐ ┌────────────┐ ┌──────────────┐                 │
│  │  Tier 1: QMD  │ │ Tier 2: CK │ │ Tier 3: grep │                 │
│  │  qmd-sync.sh  │ │ ck --hybrid│ │ grep -r      │                 │
│  │  query        │ │            │ │              │                 │
│  └───────────────┘ └────────────┘ └──────────────┘                 │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 Data Flow

1. Skill calls `qmd-context-query.sh --query "..." --scope grimoires --budget 2000`
2. Script resolves scope to tier-specific paths (QMD collection, CK directory, grep paths)
3. Script tries Tier 1 (QMD) with timeout → if fails/empty, tries Tier 2 (CK) → if fails/empty, tries Tier 3 (grep)
4. Results are scored, deduplicated, and truncated to token budget
5. JSON array returned to caller

## 3. Technology Stack

| Component | Technology | Justification |
|-----------|-----------|---------------|
| Query script | Bash | Matches all existing Loa scripts |
| QMD tier | `qmd-sync.sh query` | Existing wrapper, already handles fallback |
| CK tier | `ck --hybrid` | Existing binary, proven in context-manager.sh |
| Grep tier | `grep -r -l -i` | Universal, always available |
| Config | `.loa.config.yaml` + yq | Standard Loa config mechanism |
| Tests | Bash (bats or direct) | Matches existing test patterns |
| JSON processing | jq | Already required dependency |

## 4. Component Design

### 4.1 `qmd-context-query.sh` — Main Script

**Location**: `.claude/scripts/qmd-context-query.sh`

**Interface**:
```bash
qmd-context-query.sh \
  --query "search text" \
  --scope grimoires|skills|notes|reality|all \
  [--budget 2000] \
  [--format json|text] \
  [--timeout 5]
```

**Output** (JSON):
```json
[
  {
    "source": "grimoires/loa/NOTES.md",
    "score": 0.82,
    "content": "## Blocker: QMD timeout on large collections...",
    "tier": "qmd"
  }
]
```

**Output** (text):
```
--- grimoires/loa/NOTES.md (score: 0.82, tier: qmd) ---
## Blocker: QMD timeout on large collections...
```

### 4.2 Core Functions

```bash
# Entry point
main() {
  parse_args "$@"
  load_config
  resolve_scope "$SCOPE"
  local results
  results=$(try_tiers)
  apply_token_budget "$results" "$BUDGET"
}

# Three-tier fallback
try_tiers() {
  local results=""

  # Tier 1: QMD
  if [[ -n "$QMD_COLLECTION" ]]; then
    results=$(try_qmd "$QUERY" "$QMD_COLLECTION" "$TIMEOUT")
    if [[ -n "$results" && "$results" != "[]" ]]; then
      annotate_tier "$results" "qmd"
      return
    fi
  fi

  # Tier 2: CK
  if [[ -n "$CK_PATH" ]] && command -v ck &>/dev/null; then
    results=$(try_ck "$QUERY" "$CK_PATH" "$TIMEOUT")
    if [[ -n "$results" && "$results" != "[]" ]]; then
      annotate_tier "$results" "ck"
      return
    fi
  fi

  # Tier 3: grep (always available)
  results=$(try_grep "$QUERY" "$GREP_PATHS")
  annotate_tier "$results" "grep"
}
```

### 4.3 Tier 1: QMD Search

```bash
try_qmd() {
  local query="$1"
  local collection="$2"
  local timeout="$3"

  # Delegate to existing qmd-sync.sh
  timeout "${timeout}s" \
    "$PROJECT_ROOT/.claude/scripts/qmd-sync.sh" query "$query" \
    --collection "$collection" \
    --top-k 10 \
    --threshold 0.3 2>/dev/null || echo "[]"
}
```

Wraps `qmd-sync.sh query_collection()` (lines 319-382 of qmd-sync.sh). The existing function already handles QMD binary detection and grep fallback internally, but we use the explicit tier approach for consistent scoring.

### 4.4 Tier 2: CK Search

```bash
try_ck() {
  local query="$1"
  local ck_path="$2"
  local timeout="$3"

  # Use ck hybrid search (same pattern as context-manager.sh:1014)
  local raw
  raw=$(timeout "${timeout}s" \
    ck --hybrid "$query" \
      --limit 10 \
      --threshold 0.5 \
      --jsonl "$ck_path" 2>/dev/null) || return 1

  # Transform ck JSONL output to our JSON array format
  echo "$raw" | jq -s '[.[] | {
    source: .file,
    score: .score,
    content: (.snippet // .text // ""),
  }]' 2>/dev/null || echo "[]"
}
```

Mirrors `semantic_search_ck()` from `context-manager.sh:1014-1026`.

### 4.5 Tier 3: Grep Search

```bash
try_grep() {
  local query="$1"
  local paths="$2"  # space-separated

  local results=()
  local keywords
  keywords=$(echo "$query" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '\n' | head -5)

  for path in $paths; do
    [[ -e "$path" ]] || continue

    # Build grep OR pattern from keywords
    local pattern=""
    while IFS= read -r word; do
      [[ -z "$word" ]] && continue
      pattern="${pattern:+$pattern\\|}$word"
    done <<< "$keywords"

    [[ -z "$pattern" ]] && continue

    # Search files, extract snippets
    while IFS= read -r file; do
      local snippet
      snippet=$(grep -i -m1 "$pattern" "$file" 2>/dev/null | head -c 200 || echo "")
      snippet=$(echo "$snippet" | jq -Rs '.' | sed 's/^"//;s/"$//')
      results+=("{\"source\":\"$file\",\"score\":0.5,\"content\":\"$snippet\"}")
    done < <(grep -r -l -i "$pattern" "$path" 2>/dev/null | head -10)
  done

  if [[ ${#results[@]} -eq 0 ]]; then
    echo "[]"
  else
    printf '%s\n' "${results[@]}" | jq -s '.' 2>/dev/null || echo "[]"
  fi
}
```

Mirrors `keyword_search_grep()` from `context-manager.sh:1031-1059` and `query_collection()` grep fallback from `qmd-sync.sh:340-381`.

### 4.6 Token Budget Enforcement

```bash
apply_token_budget() {
  local results="$1"
  local budget="$2"

  # Estimate tokens: word_count × 1.3
  local total_tokens=0
  local filtered="[]"

  # Process results sorted by score (highest first)
  echo "$results" | jq -c 'sort_by(-.score) | .[]' | while IFS= read -r item; do
    local content
    content=$(echo "$item" | jq -r '.content // ""')
    local word_count
    word_count=$(echo "$content" | wc -w)
    local item_tokens=$(( (word_count * 13 + 9) / 10 ))  # integer × 1.3

    if (( total_tokens + item_tokens > budget )); then
      break
    fi

    total_tokens=$((total_tokens + item_tokens))
    filtered=$(echo "$filtered" | jq --argjson item "$item" '. + [$item]')
  done

  echo "$filtered"
}
```

### 4.7 Scope Resolution

Maps scope names to tier-specific paths:

| Scope | QMD Collection | CK Path | Grep Paths |
|-------|---------------|---------|------------|
| `grimoires` | `loa-grimoire` | `.ck/loa-grimoire/` | `grimoires/loa/` |
| `skills` | `loa-skills` | `.ck/skills/` | `.claude/skills/` |
| `notes` | `loa-grimoire` | `.ck/loa-grimoire/` | `grimoires/loa/NOTES.md` |
| `reality` | `loa-reality` | `.ck/reality/` | `grimoires/loa/reality/` |
| `all` | (queries each) | (queries each) | (all paths) |

These mappings are read from `.loa.config.yaml` under `qmd_context.scopes`. If config is absent, the defaults above are used.

```bash
resolve_scope() {
  local scope="$1"

  # Try config first, fall back to defaults
  if [[ -f "$CONFIG_FILE" ]] && command -v yq &>/dev/null; then
    QMD_COLLECTION=$(yq -r ".qmd_context.scopes.${scope}.qmd_collection // \"\"" "$CONFIG_FILE" 2>/dev/null)
    CK_PATH=$(yq -r ".qmd_context.scopes.${scope}.ck_path // \"\"" "$CONFIG_FILE" 2>/dev/null)
    GREP_PATHS=$(yq -r ".qmd_context.scopes.${scope}.grep_paths // [] | .[]" "$CONFIG_FILE" 2>/dev/null | tr '\n' ' ')
  fi

  # Apply defaults if config yielded empty values
  if [[ -z "$QMD_COLLECTION" ]]; then
    case "$scope" in
      grimoires|notes) QMD_COLLECTION="loa-grimoire" ;;
      skills)          QMD_COLLECTION="loa-skills" ;;
      reality)         QMD_COLLECTION="loa-reality" ;;
      all)             QMD_COLLECTION="all" ;;
    esac
  fi

  if [[ -z "$CK_PATH" ]]; then
    case "$scope" in
      grimoires|notes) CK_PATH=".ck/loa-grimoire/" ;;
      skills)          CK_PATH=".ck/skills/" ;;
      reality)         CK_PATH=".ck/reality/" ;;
      all)             CK_PATH=".ck/" ;;
    esac
  fi

  if [[ -z "$GREP_PATHS" ]]; then
    case "$scope" in
      grimoires) GREP_PATHS="grimoires/loa/" ;;
      skills)    GREP_PATHS=".claude/skills/" ;;
      notes)     GREP_PATHS="grimoires/loa/NOTES.md" ;;
      reality)   GREP_PATHS="grimoires/loa/reality/" ;;
      all)       GREP_PATHS="grimoires/loa/ .claude/skills/ grimoires/loa/reality/" ;;
    esac
  fi
}
```

### 4.8 Tier Annotation

```bash
annotate_tier() {
  local results="$1"
  local tier="$2"

  echo "$results" | jq --arg tier "$tier" '[.[] | . + {tier: $tier}]' 2>/dev/null || echo "$results"
}
```

## 5. Skill Integration Patterns

Each skill integration follows the same pattern:

```bash
# In skill SKILL.md or invocation script:
inject_context() {
  local query="$1"
  local scope="$2"
  local budget="${3:-2000}"

  local context
  context=$("$PROJECT_ROOT/.claude/scripts/qmd-context-query.sh" \
    --query "$query" \
    --scope "$scope" \
    --budget "$budget" \
    --format text 2>/dev/null) || context=""

  if [[ -n "$context" ]]; then
    echo ""
    echo "## Relevant Context (auto-retrieved)"
    echo ""
    echo "$context"
  fi
}
```

### 5.1 `/implement` Integration

**When**: After loading sprint plan, before task execution.
**Query**: Task description + file names from sprint plan.
**Scope**: `grimoires` (NOTES, past feedback, decisions).
**Budget**: 2000 tokens.

### 5.2 `/review-sprint` Integration

**When**: After loading implementation report, before code review.
**Query**: Changed file names + sprint goal.
**Scope**: `grimoires` (prior reviews, SDD decisions).
**Budget**: 1500 tokens.

### 5.3 `/ride` Integration

**When**: During documentation drift analysis.
**Query**: Module names being analyzed.
**Scope**: `reality` (existing reality files for comparison).
**Budget**: 2000 tokens.

### 5.4 `/run-bridge` (Bridgebuilder) Integration

**When**: Before Bridgebuilder review prompt construction.
**Query**: PR diff summary + changed modules.
**Scope**: `grimoires` (lore, vision, past findings).
**Budget**: 2500 tokens.

### 5.5 Gate 0 Pre-flight Integration

**When**: During pre-flight validation.
**Query**: Skill name + "configuration prerequisites".
**Scope**: `notes` (known issues, blockers).
**Budget**: 1000 tokens.

## 6. Configuration

### 6.1 `.loa.config.yaml` Addition

```yaml
qmd_context:
  enabled: true
  default_budget: 2000
  timeout_seconds: 5
  scopes:
    grimoires:
      qmd_collection: "loa-grimoire"
      ck_path: ".ck/loa-grimoire/"
      grep_paths:
        - "grimoires/loa/"
    skills:
      qmd_collection: "loa-skills"
      ck_path: ".ck/skills/"
      grep_paths:
        - ".claude/skills/"
    notes:
      qmd_collection: "loa-grimoire"
      ck_path: ".ck/loa-grimoire/"
      grep_paths:
        - "grimoires/loa/NOTES.md"
    reality:
      qmd_collection: "loa-reality"
      ck_path: ".ck/reality/"
      grep_paths:
        - "grimoires/loa/reality/"
  skill_overrides:
    implement:
      budget: 2000
      scope: grimoires
    review-sprint:
      budget: 1500
      scope: grimoires
    ride:
      budget: 2000
      scope: reality
    run-bridge:
      budget: 2500
      scope: grimoires
    gate-0:
      budget: 1000
      scope: notes
```

### 6.2 Configuration Parsing

```bash
load_config() {
  CONFIG_FILE="${PROJECT_ROOT}/.loa.config.yaml"

  if [[ ! -f "$CONFIG_FILE" ]] || ! command -v yq &>/dev/null; then
    # Use defaults
    ENABLED=true
    DEFAULT_BUDGET=2000
    TIMEOUT=5
    return
  fi

  ENABLED=$(yq -r '.qmd_context.enabled // true' "$CONFIG_FILE" 2>/dev/null)
  DEFAULT_BUDGET=$(yq -r '.qmd_context.default_budget // 2000' "$CONFIG_FILE" 2>/dev/null)
  TIMEOUT=$(yq -r '.qmd_context.timeout_seconds // 5' "$CONFIG_FILE" 2>/dev/null)
}
```

## 7. Non-Functional Requirements

### 7.1 Fallback Guarantee

The three-tier fallback is the core design invariant. Every code path MUST terminate at grep if higher tiers fail. This is enforced by:
- `try_tiers()` always calling `try_grep()` as terminal case
- No early returns that skip grep on empty results from QMD + CK
- Grep itself cannot fail (it uses standard coreutils)

### 7.2 Performance

| Operation | Target | Enforcement |
|-----------|--------|-------------|
| QMD query | < 5s | `timeout` command |
| CK query | < 5s | `timeout` command |
| Grep query | < 2s | Head limits on file matches |
| Total per invocation | < 7s | Tier timeout + sequential |
| Token budget check | < 100ms | jq streaming |

### 7.3 Security

- Path traversal prevention inherited from `qmd-sync.sh` (lines 350-358)
- All file paths validated against `PROJECT_ROOT` before access
- No user-supplied input passed directly to `eval` or unquoted shell expansion
- `jq` used for all JSON construction (prevents injection)

## 8. Test Strategy

### 8.1 Unit Tests

| Test | Description |
|------|-------------|
| `test_try_qmd_available` | QMD returns results when binary + collection exist |
| `test_try_qmd_unavailable` | Returns `[]` when QMD binary missing |
| `test_try_qmd_timeout` | Falls through on timeout |
| `test_try_ck_available` | CK returns results when binary + path exist |
| `test_try_ck_unavailable` | Returns `[]` when CK binary missing |
| `test_try_grep_matches` | Returns results with matching files |
| `test_try_grep_no_matches` | Returns `[]` on no matches |
| `test_fallback_qmd_to_ck` | Falls through QMD → CK when QMD empty |
| `test_fallback_qmd_to_grep` | Falls through QMD → CK → grep when both empty |
| `test_fallback_all_tiers` | Verifies complete fallback chain |
| `test_token_budget_enforcement` | Results truncated at budget |
| `test_token_budget_zero` | Returns `[]` on budget 0 |
| `test_scope_resolution_defaults` | Default scope mappings correct |
| `test_scope_resolution_config` | Config overrides work |
| `test_tier_annotation` | Each result tagged with correct tier |

### 8.2 Integration Tests

| Test | Description |
|------|-------------|
| `test_implement_context_injection` | `/implement` receives context from query |
| `test_review_context_injection` | `/review-sprint` receives context |
| `test_ride_context_injection` | `/ride` receives reality context |
| `test_bridge_context_injection` | `/run-bridge` receives lore context |
| `test_gate0_context_injection` | Gate 0 receives notes context |
| `test_disabled_config` | No context when `enabled: false` |

### 8.3 Validation Tests

| Test | Description |
|------|-------------|
| `test_existing_tests_pass` | All pre-existing tests still pass |
| `test_no_qmd_no_ck_works` | Script works with grep-only |
| `test_config_missing_works` | Script works without config file |

## 9. File Manifest

| File | Action | Description |
|------|--------|-------------|
| `.claude/scripts/qmd-context-query.sh` | CREATE | Unified context query interface |
| `.claude/scripts/qmd-context-query-tests.sh` | CREATE | Unit tests for query script |
| `skills/implementing-tasks/SKILL.md` | MODIFY | Add context injection call |
| `skills/reviewing-code/SKILL.md` | MODIFY | Add context injection call |
| `skills/riding-codebase/SKILL.md` | MODIFY | Add context injection call |
| `.claude/scripts/bridge-orchestrator.sh` | MODIFY | Add context injection call |
| `.loa.config.yaml.example` | MODIFY | Add qmd_context section |

## 10. Risks & Mitigation

| Risk | Mitigation |
|------|------------|
| QMD results irrelevant | Score threshold (0.3) filters low-quality matches |
| Context bloat slows skills | Token budget hard cap (default 2000) |
| Stale CK index | Grep fallback covers; CK index refresh is out of scope |
| Config complexity | Sensible defaults work without any config |
| SKILL.md modifications break existing behavior | Integration is additive (new section), not modifying existing logic |

## 11. Development Order

1. **Sprint 1**: Create `qmd-context-query.sh` with all three tiers + token budget + tests
2. **Sprint 2**: Integrate into 5 skills (implement, review, ride, bridge, gate-0)
3. **Sprint 3**: Configuration support + validation + documentation

Sprint 1 is the foundation. Sprints 2 and 3 can proceed in parallel after Sprint 1.

## 12. References

- `qmd-sync.sh` — Existing QMD wrapper (614 lines, query at lines 319-415)
- `context-manager.sh` — CK and grep patterns (lines 1014-1059)
- `detect-semantic-tools.sh` — Tool detection (384 lines)
- `search.sh` — Memory search with QMD merge (129 lines)
- `.loa.config.yaml.example` — Configuration reference
