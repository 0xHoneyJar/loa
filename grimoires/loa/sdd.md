# SDD: Bridge Inquiry Infrastructure — Active Discovery, Research Mode & Temporal Lore

> Cycle: cycle-030 | Author: Claude (Architect)
> PRD: [grimoires/loa/prd.md](grimoires/loa/prd.md)
> Source: [PR #392 Post-Bridge Inquiry](https://github.com/0xHoneyJar/loa/pull/392)

---

## 1. Executive Summary

This SDD describes five infrastructure enhancements to the bridge review system that transform it from a convergent quality loop into a dual-mode system supporting both convergent QA and divergent architectural inquiry. The changes extend 4 existing scripts, add 1 new script, and extend 2 data schemas.

**Scope**: 4 scripts modified, 1 script created, 2 YAML schemas extended, config schema extended.

**Guiding principle**: Every enhancement is additive. The convergent bridge loop is untouched. Research mode, vision activation, cross-repo queries, and inquiry mode are layered alongside existing behavior with opt-in defaults and graceful degradation.

---

## 2. System Architecture

### 2.1 Component Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    bridge-orchestrator.sh                         │
│                                                                   │
│  State Machine (extended):                                        │
│  PREFLIGHT → JACK_IN → ITERATING ↔ RESEARCHING → FINALIZING     │
│                                      ↕                            │
│                                   EXPLORING                       │
│                                      ↓                            │
│                                   JACKED_OUT                      │
│                                                                   │
│  NEW: cross_repo_pattern_query()    ◄── FR-1                    │
│  NEW: check_relevant_visions()      ◄── FR-3                    │
│  NEW: RESEARCHING state handler     ◄── FR-2                    │
│                                                                   │
│  Integration points:                                              │
│  ├─ cross-repo-query.sh (NEW)       ◄── FR-1 extraction         │
│  ├─ bridge-vision-capture.sh (MOD)  ◄── FR-3 activation         │
│  ├─ lore-discover.sh (MOD)          ◄── FR-5 temporal tracking   │
│  └─ flatline-orchestrator.sh (MOD)  ◄── FR-4 inquiry mode       │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Data Flow

```
Pre-Review Phase (NEW):
  ecosystem config ──→ cross-repo-query.sh ──→ pattern matches (JSON)
  visions/index.md ──→ check_relevant_visions() ──→ relevant visions

Convergent Iteration (EXISTING — unchanged):
  diff + context ──→ Bridgebuilder review ──→ findings JSON ──→ sprint plan

Research Iteration (NEW):
  cross-repo context + lore + visions ──→ SPECULATION findings ──→ lore expansion
  (optional) cross-repo + doc ──→ flatline inquiry mode ──→ ensemble insights

Post-Review Phase (EXTENDED):
  findings ──→ lore-discover.sh ──→ update_lore_reference() ──→ lifecycle metadata
  findings ──→ bridge-vision-capture.sh ──→ reference count increment
```

---

## 3. Component Design

### 3.1 Cross-Repository Pattern Query (FR-1)

**New script**: `.claude/scripts/cross-repo-query.sh`

This script extracts structural patterns from ecosystem reality files and matches them against the current PR diff.

#### 3.1.1 Interface

```bash
cross-repo-query.sh \
  --diff <diff_file_or_stdin> \
  --ecosystem <config_path> \
  --output json|markdown \
  [--budget <max_tokens>] \
  [--max-repos <N>]
```

**Output** (JSON):
```json
{
  "query_timestamp": "2026-02-20T12:00:00Z",
  "repos_queried": 3,
  "repos_skipped": 0,
  "matches": [
    {
      "repo": "0xHoneyJar/loa-hounfour",
      "pattern": "priority-ordered fallback chain",
      "similarity_type": "structural",
      "local_file": ".claude/scripts/butterfreezone-gen.sh",
      "remote_context": "pool-router uses 4-tier model selection cascade",
      "confidence": "high"
    }
  ],
  "warnings": []
}
```

#### 3.1.2 Pattern Extraction Algorithm

```
1. Parse PR diff → extract:
   - New/modified function names
   - File paths touching architectural patterns (orchestrator, router, cascade)
   - Import/require statements referencing ecosystem packages

2. For each ecosystem repo in config:
   a. Resolve local checkout path (sibling directory convention: ../<repo-name>)
   b. If local checkout exists:
      - Read grimoires/loa/reality/ files (checksums.json, index.md)
      - Run qmd-context-query.sh --scope reality --query <extracted_patterns>
   c. If local checkout missing:
      - Attempt butterfreezone-mesh.sh fetch (GitHub API) for AGENT-CONTEXT
      - Extract interface descriptions from AGENT-CONTEXT block
   d. If both fail: skip with warning

3. Match extracted patterns against reality data:
   - Function name similarity (exact or fuzzy via grep -i)
   - Architectural keyword overlap (cascade, fallback, router, handler, guard)
   - Protocol version references (loa-hounfour@N.N.N)

4. Deduplicate matches, sort by confidence (high → medium → low)
```

#### 3.1.3 Repo Resolution Strategy

```bash
resolve_ecosystem_repo() {
  local repo_slug="$1"  # e.g., "0xHoneyJar/loa-hounfour"
  local repo_name="${repo_slug##*/}"  # e.g., "loa-hounfour"

  # Priority 1: Sibling directory (co-located checkouts)
  local sibling="../${repo_name}"
  if [[ -d "$sibling/.git" ]]; then
    echo "$sibling"
    return 0
  fi

  # Priority 2: Configurable override
  local override
  override=$(yq ".butterfreezone.ecosystem_paths.${repo_name} // \"\"" .loa.config.yaml 2>/dev/null)
  if [[ -n "$override" && -d "$override/.git" ]]; then
    echo "$override"
    return 0
  fi

  # Priority 3: GitHub API fallback (remote-only, limited)
  echo "REMOTE:${repo_slug}"
  return 0
}
```

#### 3.1.4 Integration with Bridge Orchestrator

In `bridge-orchestrator.sh`, before each Bridgebuilder review signal:

```bash
# Pre-review cross-repo query (FR-1)
if [[ "$(yq '.run_bridge.cross_repo_query.enabled // true' .loa.config.yaml)" == "true" ]]; then
  local cross_repo_context=""
  cross_repo_context=$(.claude/scripts/cross-repo-query.sh \
    --diff <(git diff "${BASE_BRANCH}...HEAD") \
    --ecosystem .loa.config.yaml \
    --output markdown \
    --budget 1500 2>/dev/null) || true

  if [[ -n "$cross_repo_context" ]]; then
    # Inject into bridge review prompt context
    echo "<!-- cross-repo-context -->"
    echo "$cross_repo_context"
    echo "<!-- /cross-repo-context -->"
  fi
fi
```

**Performance constraint**: 5s timeout per repo, 15s total. Filesystem-based queries only for local checkouts.

---

### 3.2 Research Mode for Bridge Iterations (FR-2)

#### 3.2.1 State Machine Extension

Add `RESEARCHING` state between ITERATING cycles:

```
ITERATING(N) → [if research_mode enabled && N == 1 && not already researched]
             → RESEARCHING
             → ITERATING(N+1)

ITERATING(N) → [if flatline or max depth]
             → EXPLORING (if vision sprint enabled)
             → FINALIZING
```

The RESEARCHING state is inserted **after iteration 1** (the first convergent review provides baseline context). It runs at most once per bridge run.

#### 3.2.2 Research Iteration Behavior

```bash
handle_researching_state() {
  local bridge_id="$1"
  local iteration="$2"

  # Guard: only once per run
  local research_done
  research_done=$(jq -r '.research_iterations_completed // 0' .run/bridge-state.json)
  if [[ "$research_done" -ge "$MAX_RESEARCH_PER_RUN" ]]; then
    return 0  # Skip, already researched
  fi

  update_bridge_state "RESEARCHING"

  # Compose research prompt with:
  # 1. Cross-repo context (FR-1 output)
  # 2. Lore entries (all categories, sorted by references desc)
  # 3. Relevant visions (FR-3 output)
  # 4. Previous iteration findings (for connection-finding)

  # Signal skill layer to run research review
  echo "SIGNAL:RESEARCH_ITERATION"
  # Skill layer produces SPECULATION-only findings
  # Score = N/A (not tracked in flatline trajectory)

  # Save output
  local output_file=".run/bridge-reviews/${bridge_id}-research-${iteration}.md"
  # ... save review content ...

  # Update state
  jq '.research_iterations_completed += 1' .run/bridge-state.json > .run/bridge-state.json.tmp
  mv .run/bridge-state.json.tmp .run/bridge-state.json

  # Run lore discovery on research output
  if [[ "$(yq '.run_bridge.lore_discovery.enabled // false' .loa.config.yaml)" == "true" ]]; then
    .claude/scripts/lore-discover.sh --bridge-id "$bridge_id" --research-only
  fi

  # Optionally trigger inquiry mode (FR-4)
  if [[ "$(yq '.run_bridge.research_mode.inquiry_enabled // false' .loa.config.yaml)" == "true" ]]; then
    echo "SIGNAL:INQUIRY_MODE"
  fi

  update_bridge_state "ITERATING"
}
```

#### 3.2.3 Score Exclusion

Research iterations are explicitly excluded from flatline detection:

```bash
# In flatline check logic (bridge-state.sh)
check_flatline() {
  # Filter out research iterations from score trajectory
  local convergent_scores
  convergent_scores=$(jq '[.iterations[] | select(.type != "research") | .score]' \
    .run/bridge-state.json)

  # Apply flatline threshold only to convergent scores
  # ...
}
```

#### 3.2.4 Bridge State Extension

```json
{
  "iterations": [
    {"number": 1, "type": "convergent", "score": 5.0, "findings": 3},
    {"number": 2, "type": "research", "score": null, "findings": 0, "speculations": 4},
    {"number": 3, "type": "convergent", "score": 0.0, "findings": 0}
  ],
  "research_iterations_completed": 1,
  "research_mode": {
    "enabled": true,
    "triggered_after_iteration": 1,
    "speculations_generated": 4,
    "lore_entries_created": 1,
    "visions_referenced": ["vision-004"]
  }
}
```

---

### 3.3 Vision Registry Activation (FR-3)

#### 3.3.1 Vision Relevance Check

New function in bridge orchestrator, called before each review:

```bash
check_relevant_visions() {
  local diff_file="$1"
  local visions_dir="${2:-grimoires/loa/visions}"
  local min_tag_overlap="${3:-2}"

  local index_file="${visions_dir}/index.md"
  [[ -f "$index_file" ]] || return 0

  # Extract PR change categories from diff
  local pr_tags=()
  # Map file paths to tags:
  # .claude/scripts/*orchestrator* → architecture
  # .claude/scripts/*security* → security
  # .claude/data/constraints* → constraints
  # tests/* → testing
  # .claude/scripts/flatline* → multi-model
  pr_tags=($(extract_pr_tags "$diff_file"))

  local relevant_visions=()

  # Parse index.md for Captured/Exploring visions
  while IFS='|' read -r _ id title source status tags refs _; do
    status=$(echo "$status" | xargs)
    [[ "$status" == "Captured" || "$status" == "Exploring" ]] || continue

    # Parse vision tags
    local vision_tags
    vision_tags=$(echo "$tags" | tr ',' ' ' | xargs)

    # Count tag overlap
    local overlap=0
    for vtag in $vision_tags; do
      for ptag in "${pr_tags[@]}"; do
        [[ "$vtag" == "$ptag" ]] && ((overlap++))
      done
    done

    if [[ $overlap -ge $min_tag_overlap ]]; then
      local vid=$(echo "$id" | xargs)
      relevant_visions+=("$vid")
    fi
  done < <(grep '| vision-' "$index_file")

  # Output relevant vision IDs
  printf '%s\n' "${relevant_visions[@]}"
}
```

#### 3.3.2 Vision Activation Flow

```
1. check_relevant_visions() returns list of vision IDs

2. For each relevant vision:
   a. Read vision entry file (entries/vision-NNN.md)
   b. If status == Captured → transition to Exploring
      - Call: update_vision_status vision-NNN Exploring
   c. Increment reference count
      - Call: record_reference vision-NNN $BRIDGE_ID
   d. Include vision content in research iteration context

3. After bridge completes:
   - If vision was explored with >=2 SPECULATION findings referencing it:
     - Log suggestion: "Consider promoting vision-NNN to Proposed"
     - (No auto-promotion — human decision)
```

#### 3.3.3 Modifications to bridge-vision-capture.sh

Extend `record_reference()` to also log the reference in bridge state:

```bash
# Existing: increment Refs count in index.md
# NEW: also record in bridge-state.json
record_reference() {
  local vision_id="$1"
  local bridge_id="$2"
  local visions_dir="${3:-grimoires/loa/visions}"

  # ... existing reference counting logic ...

  # NEW: Record in bridge state for research iteration context
  if [[ -f .run/bridge-state.json ]]; then
    jq --arg vid "$vision_id" --arg bid "$bridge_id" '
      .visions_referenced = ((.visions_referenced // []) + [$vid] | unique)
    ' .run/bridge-state.json > .run/bridge-state.json.tmp
    mv .run/bridge-state.json.tmp .run/bridge-state.json
  fi
}
```

---

### 3.4 Multi-Model Architectural Inquiry (FR-4)

#### 3.4.1 Inquiry Mode in Flatline Orchestrator

Add a new mode `inquiry` alongside the existing `adversarial` mode in `flatline-orchestrator.sh`.

**Key difference**: Inquiry mode is **collaborative** (models explore different angles), not **adversarial** (models challenge each other).

```bash
# Mode selection
case "$MODE" in
  adversarial)
    run_adversarial_review "$@"  # Existing: Phase 1 → Phase 2 → Consensus
    ;;
  inquiry)
    run_inquiry_review "$@"  # NEW: 3 parallel collaborative queries
    ;;
esac
```

#### 3.4.2 Inquiry Review Architecture

```bash
run_inquiry_review() {
  local doc="$1"
  local phase="$2"
  local context="$3"
  local timeout="$4"
  local budget="$5"

  local run_dir=".flatline/runs/inquiry-$(date +%s)"
  mkdir -p "$run_dir"

  # 3 parallel queries with distinct prompts
  # Use primary and secondary models, alternating assignment

  # Query 1: Structural isomorphisms (primary model)
  call_model "$PRIMARY_MODEL" "inquiry-structural" "$doc" "$phase" \
    "Identify structural isomorphisms between this change and patterns in: ${context}" \
    "$timeout" &
  local pid_structural=$!

  # Query 2: Historical precedents (secondary model)
  call_model "$SECONDARY_MODEL" "inquiry-historical" "$doc" "$phase" \
    "What precedents in Linux kernel, Kubernetes, npm, or other blue-chip projects parallel this approach?" \
    "$timeout" &
  local pid_historical=$!

  # Query 3: Governance implications (primary model, different prompt)
  call_model "$PRIMARY_MODEL" "inquiry-governance" "$doc" "$phase" \
    "What governance, economic, or commons-management implications does this architectural choice have?" \
    "$timeout" &
  local pid_governance=$!

  # Wait for all queries
  wait $pid_structural $pid_historical $pid_governance

  # Synthesize results (not cross-score — combine)
  synthesize_inquiry_results "$run_dir"
}
```

#### 3.4.3 Synthesis (Not Scoring)

Unlike adversarial mode which cross-scores for consensus, inquiry mode **synthesizes** perspectives:

```json
{
  "mode": "inquiry",
  "phase": "bridge-research",
  "document": "path/to/doc",
  "timestamp": "2026-02-20T12:00:00Z",
  "perspectives": {
    "structural": {
      "model": "opus",
      "insights": [
        {
          "pattern": "priority-ordered fallback chain",
          "isomorphism": "Hounfour pool routing uses identical 4-tier cascade",
          "significance": "Both systems solve capability selection with same algorithm shape"
        }
      ]
    },
    "historical": {
      "model": "gpt-5.2",
      "insights": [
        {
          "precedent": "npm scoped packages (@org/pkg)",
          "parallel": "Provenance classification mirrors npm's flat→scoped transition",
          "significance": "npm's transition took 3 years and required backward compatibility"
        }
      ]
    },
    "governance": {
      "model": "opus",
      "insights": [
        {
          "framework": "Ostrom commons governance",
          "mapping": "Provenance = Principle 1 (clearly defined boundaries)",
          "significance": "Without boundary definition, commons governance collapses"
        }
      ]
    }
  },
  "synthesis": "Combined architectural narrative connecting all three perspectives",
  "metrics": {
    "total_latency_ms": 12000,
    "cost_cents": 180
  }
}
```

#### 3.4.4 Manual Invocation

```bash
# Via /flatline-review skill
/flatline-review --inquiry grimoires/loa/sdd.md

# Direct script invocation
.claude/scripts/flatline-orchestrator.sh \
  --doc grimoires/loa/sdd.md \
  --phase sdd \
  --mode inquiry \
  --context "$(cat .run/cross-repo-context.json)" \
  --json
```

---

### 3.5 Temporal Depth in Lore System (FR-5)

#### 3.5.1 Schema Extension

Extend the lore entry YAML schema with an optional `lifecycle` block:

```yaml
entries:
  - id: graceful-degradation-cascade
    term: "Graceful Degradation Cascade"
    short: "Multi-step fallback pipeline..."
    context: |
      The normalize_json_response() function...
    source: "Bridge review bridge-20260214-e8fa94 / PR #324"
    source_model: "claude-opus-4"
    tags: [discovered, architecture]
    loa_mapping: ".claude/scripts/lib/normalize-json.sh"
    # NEW — all fields optional, added lazily on first reference
    lifecycle:
      created: "2026-02-14"
      references: 3
      last_seen: "2026-02-20"
      seen_in:
        - "bridge-20260214-e8fa94 / PR #324"
        - "bridge-20260219-16e623 / PR #368"
        - "bridge-20260220-5ac44d / PR #392"
      repos:
        - loa
        - loa-hounfour
      significance: "recurring"
```

**Backward compatibility**: Missing `lifecycle` block is treated as:
```yaml
lifecycle:
  created: null
  references: 0
  last_seen: null
  seen_in: []
  repos: []
  significance: "one-off"
```

#### 3.5.2 Reference Tracking Function

New function in `lore-discover.sh`:

```bash
update_lore_reference() {
  local entry_id="$1"
  local bridge_id="$2"
  local repo_name="$3"
  local lore_file="$4"
  local today
  today=$(date -u +"%Y-%m-%d")

  # Check for duplicate (same bridge ID already recorded)
  local already_seen
  already_seen=$(yq -e ".entries[] | select(.id == \"${entry_id}\") | .lifecycle.seen_in[] | select(. == \"*${bridge_id}*\")" \
    "$lore_file" 2>/dev/null) || true
  if [[ -n "$already_seen" ]]; then
    return 0  # Idempotent: skip duplicate
  fi

  # Update lifecycle fields atomically via yq
  local idx
  idx=$(yq ".entries | to_entries | .[] | select(.value.id == \"${entry_id}\") | .key" "$lore_file")

  [[ -z "$idx" ]] && return 1  # Entry not found

  # Initialize lifecycle block if missing
  yq -i ".entries[${idx}].lifecycle.created //= \"${today}\"" "$lore_file"
  yq -i ".entries[${idx}].lifecycle.references = ((.entries[${idx}].lifecycle.references // 0) + 1)" "$lore_file"
  yq -i ".entries[${idx}].lifecycle.last_seen = \"${today}\"" "$lore_file"
  yq -i ".entries[${idx}].lifecycle.seen_in += [\"${bridge_id}\"]" "$lore_file"

  # Add repo if not already present
  if [[ -n "$repo_name" ]]; then
    local repo_exists
    repo_exists=$(yq ".entries[${idx}].lifecycle.repos[] | select(. == \"${repo_name}\")" "$lore_file" 2>/dev/null) || true
    if [[ -z "$repo_exists" ]]; then
      yq -i ".entries[${idx}].lifecycle.repos += [\"${repo_name}\"]" "$lore_file"
    fi
  fi

  # Auto-classify significance
  local ref_count
  ref_count=$(yq ".entries[${idx}].lifecycle.references" "$lore_file")
  local repo_count
  repo_count=$(yq ".entries[${idx}].lifecycle.repos | length" "$lore_file")

  local significance="one-off"
  if [[ "$ref_count" -ge 6 ]] || [[ "$repo_count" -ge 3 ]]; then
    significance="foundational"
  elif [[ "$ref_count" -ge 2 ]]; then
    significance="recurring"
  fi
  yq -i ".entries[${idx}].lifecycle.significance = \"${significance}\"" "$lore_file"
}
```

#### 3.5.3 Reference Scanning

During bridge review processing, scan findings and insights for lore term matches:

```bash
scan_for_lore_references() {
  local review_file="$1"
  local bridge_id="$2"
  local repo_name="$3"

  # Load all lore entry IDs and terms
  local lore_files=(.claude/data/lore/discovered/patterns.yaml .claude/data/lore/discovered/visions.yaml)

  for lore_file in "${lore_files[@]}"; do
    [[ -f "$lore_file" ]] || continue

    # Extract entry IDs and terms
    local entries
    entries=$(yq '.entries[] | .id + "|" + .term' "$lore_file" 2>/dev/null) || continue

    while IFS='|' read -r entry_id entry_term; do
      [[ -z "$entry_id" ]] && continue

      # Check if the review references this entry (by ID or term)
      if grep -qiF "$entry_id" "$review_file" 2>/dev/null || \
         grep -qiF "$entry_term" "$review_file" 2>/dev/null; then
        update_lore_reference "$entry_id" "$bridge_id" "$repo_name" "$lore_file"
      fi
    done <<< "$entries"
  done
}
```

#### 3.5.4 Query Extension

Extend `memory-query.sh` with lore-aware queries:

```bash
# New flags
memory-query.sh --lore                          # List all lore entries
memory-query.sh --lore --sort-by references     # Top referenced patterns
memory-query.sh --lore --significance foundational  # Filter by significance
memory-query.sh --lore --repo loa-hounfour      # Cross-repo filter
```

Implementation: read lore YAML files, apply filters, output in existing memory-query format (index / summary / full).

---

## 4. Configuration Schema

### 4.1 New Config Keys

```yaml
run_bridge:
  # Existing keys preserved...

  # FR-1: Cross-repo pattern query
  cross_repo_query:
    enabled: true                    # Default: true (low cost)
    timeout_per_repo_seconds: 5      # Per-repo query timeout
    total_timeout_seconds: 15        # Total cross-repo query timeout
    max_repos: 5                     # Maximum repos to query
    min_confidence: "medium"         # Minimum match confidence to include

  # FR-2: Research mode
  research_mode:
    enabled: false                   # Default: false (opt-in)
    max_per_run: 1                   # Maximum research iterations per run
    trigger_after_iteration: 1       # Run research after this convergent iteration
    inquiry_enabled: false           # Trigger FR-4 inquiry during research

  # FR-3: Vision registry activation
  vision_registry:
    activation_enabled: true         # Default: true (low cost)
    min_tag_overlap: 2               # Minimum tag overlap for relevance
    auto_explore: true               # Auto-transition Captured → Exploring

  # FR-5: Lore temporal depth (no separate config — always active)
  lore_discovery:
    enabled: true                    # Existing key
    track_references: true           # NEW: enable reference tracking

# FR-4: Flatline inquiry mode
flatline_protocol:
  # Existing keys preserved...
  inquiry:
    enabled: false                   # Default: false (manual via /flatline-review --inquiry)
    perspectives:
      - structural
      - historical
      - governance
    budget_cents: 300                # Budget for inquiry mode
```

### 4.2 Config Validation

All new keys have defaults. Missing keys fall back to defaults via `yq '... // <default>'`. No config migration required.

---

## 5. Data Architecture

### 5.1 Bridge State Extension

`.run/bridge-state.json` gains new fields:

```json
{
  "schema_version": 2,
  "bridge_id": "bridge-20260220-abc123",
  "state": "ITERATING",
  "iterations": [
    {
      "number": 1,
      "type": "convergent",
      "score": 5.0,
      "findings": 3,
      "cross_repo_matches": 2,
      "visions_checked": 7,
      "visions_relevant": 1
    },
    {
      "number": 2,
      "type": "research",
      "score": null,
      "speculations": 4,
      "lore_entries_referenced": 2,
      "lore_entries_created": 1,
      "inquiry_mode": true
    }
  ],
  "research_iterations_completed": 1,
  "visions_referenced": ["vision-004"],
  "lore_references_recorded": 5,
  "cross_repo_query": {
    "repos_queried": 3,
    "matches_found": 4,
    "last_query_ms": 2100
  }
}
```

**Schema migration**: Version 1 → 2 is additive. Missing new fields treated as defaults (0, null, empty). No migration script needed.

### 5.2 Lore Schema Extension

See Section 3.5.1. The `lifecycle` block is optional and backward-compatible. Existing lore consumers that don't read `lifecycle` are unaffected.

### 5.3 Cross-Repo Context Cache

`.run/cross-repo-context.json` — cached per bridge run, refreshed if stale:

```json
{
  "generated_at": "2026-02-20T12:00:00Z",
  "bridge_id": "bridge-20260220-abc123",
  "repos": [
    {
      "repo": "0xHoneyJar/loa-hounfour",
      "resolved_path": "../loa-hounfour",
      "resolution": "sibling",
      "reality_age_days": 2,
      "matches": [...]
    }
  ]
}
```

---

## 6. Integration Points

### 6.1 Bridge Orchestrator Signal Extensions

| Signal | Phase | Handler |
|--------|-------|---------|
| `SIGNAL:CROSS_REPO_QUERY` | Pre-review | Run `cross-repo-query.sh`, cache results |
| `SIGNAL:VISION_CHECK` | Pre-review | Run `check_relevant_visions()` |
| `SIGNAL:RESEARCH_ITERATION` | Post-iteration-1 | Compose research prompt, run SPECULATION review |
| `SIGNAL:INQUIRY_MODE` | During research | Run `flatline-orchestrator.sh --mode inquiry` |
| `SIGNAL:LORE_REFERENCE_SCAN` | Post-review | Run `scan_for_lore_references()` |

### 6.2 Existing Signal Compatibility

All existing signals (`SIGNAL:BRIDGEBUILDER_REVIEW`, `SIGNAL:VISION_CAPTURE`, `SIGNAL:LORE_DISCOVERY`, `SIGNAL:GROUND_TRUTH_UPDATE`, etc.) continue unchanged. New signals are additive.

---

## 7. Security Architecture

### 7.1 Cross-Repo Query Security

- **Filesystem only**: No network calls for local checkouts. GitHub API fallback uses existing `gh` authentication.
- **Path traversal prevention**: `resolve_ecosystem_repo()` validates resolved path is a git repository before reading.
- **No write access**: Cross-repo query is strictly read-only.

### 7.2 Lore YAML Injection Prevention

- All YAML writes use `yq -i` (structured update), not string concatenation.
- Bridge IDs and repo names are validated against `[a-zA-Z0-9._-]` pattern before insertion.
- `seen_in` entries are strings, not structured data — no nested injection risk.

### 7.3 Inquiry Mode Content Safety

- Inquiry mode reuses existing Flatline content redaction (`redact_security_content()` from SDD 3.5.2).
- All model outputs pass through the same post-redaction safety check as adversarial mode.

---

## 8. Testing Strategy

### 8.1 Unit Tests

| Test File | Coverage |
|-----------|----------|
| `tests/test_cross_repo_query.sh` | Pattern extraction, repo resolution, match scoring |
| `tests/test_lore_lifecycle.sh` | Reference tracking, significance classification, idempotency |
| `tests/test_vision_activation.sh` | Tag matching, status transitions, reference counting |
| `tests/test_research_mode.sh` | State machine transitions, score exclusion, guard logic |

### 8.2 Integration Tests

| Test | Validates |
|------|-----------|
| Bridge run with research mode | Full ITERATING → RESEARCHING → ITERATING flow |
| Lore reference accumulation across iterations | `seen_in` grows, `significance` auto-classifies |
| Vision activation during bridge | Captured → Exploring transition, reference increment |
| Cross-repo query with missing repos | Graceful degradation, warning output |

### 8.3 Test Data

- Mock ecosystem repos with minimal reality files
- Pre-populated lore entries with known IDs for reference testing
- Vision registry with mixed statuses for activation testing

---

## 9. Deployment & Migration

### 9.1 No Breaking Changes

All features are additive. Existing bridge runs continue unchanged. New config keys have safe defaults.

### 9.2 Feature Enablement Order

1. **Lore temporal depth** (FR-5) — always active when `lore_discovery.enabled: true`
2. **Vision activation** (FR-3) — active by default (`activation_enabled: true`)
3. **Cross-repo query** (FR-1) — active by default (`enabled: true`)
4. **Research mode** (FR-2) — opt-in (`enabled: false`)
5. **Inquiry mode** (FR-4) — opt-in (`inquiry.enabled: false`)

### 9.3 Rollback

Each feature can be disabled independently via config. No database migrations. No schema-breaking changes. Disabling a feature simply skips its execution path.

---

## 10. Technical Risks & Mitigation

| Risk | Severity | Mitigation |
|------|----------|------------|
| `yq` version incompatibility for lifecycle YAML writes | Medium | Require yq v4+ (already a project dependency) |
| Research mode creating noise in bridge reviews | Low | Default off, max 1 per run, SPECULATION-only |
| Cross-repo query timeout blocking bridge | Medium | Hard 15s total timeout, non-blocking (skip on failure) |
| Inquiry mode cost exceeding budget | Low | Separate budget config, bounded by `budget_cents` |
| Vision reference count inflation from loose matching | Low | Deduplicate by bridge ID, require exact ID or term match |
| State file schema v1 → v2 incompatibility | Low | Additive fields only, missing = defaults, no migration needed |
