# Sprint Plan: BUTTERFREEZONE Post-Convergence Hardening — Cross-Repo Agent Excellence

> Cycle: cycle-017 (phase 2 — post-convergence)
> Source: [PR #336 Post-Convergence Field Report](https://github.com/0xHoneyJar/loa/pull/336#issuecomment-3903665687), Section IX Critical Assessment
> Branch: `feat/cycle-017-butterfreezone-excellence`
> Prior sprints: 1-4 (global 102-109) — COMPLETED, bridge FLATLINED
> Cross-repo schemas: [loa-finn #31](https://github.com/0xHoneyJar/loa-finn/issues/31), [loa-hounfour PR #2](https://github.com/0xHoneyJar/loa-hounfour/pull/2), [arrakis #62](https://github.com/0xHoneyJar/arrakis/issues/62), [loa #43](https://github.com/0xHoneyJar/loa/issues/43)

## Overview

Three sprints addressing the 4 critical criticisms from Bridgebuilder Section IX, the remaining HIGH/MEDIUM actionable items from the post-convergence deep review, and the cross-repo interface schemas that connect BUTTERFREEZONE to Hounfour pool routing, trust classification, and billing legibility.

**Phase 1** (sprints 102-109): Output quality, ecosystem discovery, capability contracts, mesh script, culture layer. **DONE — bridge flatlined at iteration 2.**

**Phase 2** (sprints 110-112): Defensive hardening, scoped capabilities with trust gradient, ecosystem verification with mesh evolution. **THIS PLAN.**

**Design constraint**: Same as phase 1 — zero LLM inference. All generation uses `grep`, `sed`, `awk`, `jq`, `yq`, `git`. Cross-repo schemas are defined here in loa, consumed by loa-finn, loa-hounfour, arrakis.

**Team**: 1 engineer (autonomous)

---

## Sprint 5: Defensive Hardening — Section IX Critical Fixes

**Global ID**: sprint-110
**Goal**: Address all 4 critical criticisms from Bridgebuilder Section IX: config staleness, keyword false positives, mesh forward-compatibility, and culture incompleteness. These are the known failure modes in the current implementation.

**FAANG parallel**: Google's "Fix What's Broken Before Building What's New" — Chrome team's rule that P0/P1 bugs block feature work. Netflix Chaos Engineering — systematically identify and fix failure modes before they compound. The 4 criticisms are the equivalent of known failure injection points.

### Task 5.1: Config Staleness Detection in Validator

**File**: `.claude/scripts/butterfreezone-validate.sh`

**Description**: Add `validate_ecosystem_staleness()` that detects when `.loa.config.yaml` ecosystem entries have diverged from the generated BUTTERFREEZONE.md AGENT-CONTEXT. This addresses Section IX Criticism 1: "What happens when loa-finn changes its role from `runtime` to `platform` but `.loa.config.yaml` still says `runtime`?"

Implementation:
1. Read `butterfreezone.ecosystem` from `.loa.config.yaml` via `yq`
2. Read `ecosystem:` block from BUTTERFREEZONE.md AGENT-CONTEXT
3. Compare entry count and repo slugs
4. If mismatch, emit WARN with specific drift details
5. Also check if config has ecosystem but AGENT-CONTEXT does not (stale generation)
6. Check if AGENT-CONTEXT has ecosystem but config does not (orphaned generation)

```bash
validate_ecosystem_staleness() {
    local config=".loa.config.yaml"
    [[ ! -f "$config" ]] && return 0

    local config_count bfz_count
    config_count=$(yq '.butterfreezone.ecosystem | length' "$config" 2>/dev/null) || config_count=0
    bfz_count=$(sed -n '/<!-- AGENT-CONTEXT/,/-->/p' "$FILE" 2>/dev/null | \
        grep -c '^\s*- repo:') || bfz_count=0

    if [[ "$config_count" -gt 0 && "$bfz_count" -eq 0 ]]; then
        log_warn "eco_stale" "Config has $config_count ecosystem entries but AGENT-CONTEXT has none (stale generation)" "stale"
    elif [[ "$config_count" -eq 0 && "$bfz_count" -gt 0 ]]; then
        log_warn "eco_stale" "AGENT-CONTEXT has ecosystem entries but config has none (orphaned)" "orphaned"
    elif [[ "$config_count" -ne "$bfz_count" ]]; then
        log_warn "eco_stale" "Config has $config_count ecosystem entries but AGENT-CONTEXT has $bfz_count (count mismatch)" "mismatch"
    else
        log_pass "eco_stale" "Ecosystem entry count matches config ($config_count entries)"
    fi

    # Check specific repo slugs match
    if [[ "$config_count" -gt 0 && "$bfz_count" -gt 0 ]]; then
        local config_repos bfz_repos
        config_repos=$(yq '.butterfreezone.ecosystem[].repo' "$config" 2>/dev/null | sort)
        bfz_repos=$(sed -n '/<!-- AGENT-CONTEXT/,/-->/p' "$FILE" 2>/dev/null | \
            grep '^\s*- repo:' | sed 's/.*repo: *//' | sort)
        if [[ "$config_repos" != "$bfz_repos" ]]; then
            log_warn "eco_stale" "Ecosystem repo slugs differ between config and AGENT-CONTEXT" "slug_drift"
        fi
    fi
}
```

**Acceptance Criteria**:
- [ ] Config with 3 entries + AGENT-CONTEXT with 3 matching entries → PASS
- [ ] Config with 3 entries + AGENT-CONTEXT with 0 entries → WARN "stale generation"
- [ ] Config with 0 entries + AGENT-CONTEXT with 3 entries → WARN "orphaned"
- [ ] Config with 3 entries + AGENT-CONTEXT with 2 entries → WARN "count mismatch"
- [ ] Repo slug drift detected and reported
- [ ] Validator still passes when no config file exists (external repos)

### Task 5.2: Negative-Keyword Filtering for Capability Inference

**File**: `.claude/scripts/butterfreezone-gen.sh` — `extract_skill_capabilities()`

**Description**: Address Section IX Criticism 2: "The grep-based keyword detection for capability_requirements has no negative filtering — a SKILL.md that says 'This skill does NOT write files' would still match `filesystem:write`." Add negative-keyword exclusion patterns.

Implementation:
1. For each capability detection, check if the match occurs in a negative context
2. Negative patterns: `not`, `never`, `without`, `no `, `disable`, `readonly`, `read-only`, `read only`
3. Extract the full line containing the match, check for negative proximity (within 5 words before the keyword)
4. Only count positive matches toward the threshold

```bash
# Replace simple grep -ciE with context-aware matching
count_positive_matches() {
    local skill_content="$1"
    local keywords="$2"
    local count=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Check for negative context within the line
        if grep -qiE "(not|never|without|no |disable|readonly|read-only|doesn.t|won.t|cannot)" <<< "$line"; then
            continue  # Skip lines with negative context
        fi
        count=$((count + 1))
    done < <(grep -iE "$keywords" <<< "$skill_content" 2>/dev/null || true)

    echo "$count"
}
```

Also add a suppression mechanism via `.loa.config.yaml`:
```yaml
butterfreezone:
  capability_overrides:
    suppress:
      - "network:read"  # Suppress false positive
    add:
      - "custom:capability"  # Force inclusion
```

**Acceptance Criteria**:
- [ ] SKILL.md containing "This skill does NOT write files" does NOT produce `filesystem:write`
- [ ] SKILL.md containing "Write implementation code" DOES produce `filesystem:write`
- [ ] Lines with "never", "without", "no ", "disable" are excluded from match count
- [ ] Capability overrides from config are respected (suppress and add)
- [ ] Existing capability detection still works for positive matches
- [ ] Test: Loa's own capability_requirements are accurate after change

### Task 5.3: Mesh Schema Versioning and Forward Compatibility

**File**: `.claude/scripts/butterfreezone-mesh.sh`

**Description**: Address Section IX Criticism 3: "The mesh JSON output has no schema version field — when we inevitably add `capabilities` to nodes or `trust_level` to edges, consumers have no way to detect the format change." Add schema versioning with forward-compatible design.

Implementation:
1. Add `schema_version` field to mesh output (currently `mesh_version` exists for script version)
2. Define schema contract:
   - `schema_version: "1.0"` — current: nodes have repo/name/type/purpose/version/interfaces; edges have from/to/role/interface/protocol
   - Future `schema_version: "1.1"` — adds `capabilities` to nodes, `trust_level` to edges
   - Consumers MUST ignore unknown fields (forward compatibility)
3. Add `--schema` flag to output schema documentation
4. Update `mesh_version` to track script version separately from schema version

```json
{
  "schema_version": "1.0",
  "mesh_version": "1.1.0",
  "generated_at": "2026-02-15T18:00:00Z",
  "root_repo": "0xHoneyJar/loa",
  "schema_contract": "Consumers MUST ignore unknown fields for forward compatibility",
  "nodes": [...],
  "edges": [...]
}
```

Also add `--schema` flag:
```bash
--schema)
    cat <<'SCHEMA'
BUTTERFREEZONE Mesh Schema v1.0

Nodes: { repo, name, type, purpose, version, interfaces }
Edges: { from, to, role, interface, protocol }

Forward compatibility: consumers MUST ignore unknown fields.
Planned v1.1 additions: nodes.capabilities, edges.trust_level
SCHEMA
    exit 0
    ;;
```

**Acceptance Criteria**:
- [ ] Mesh JSON output includes `schema_version: "1.0"`
- [ ] `mesh_version` tracks script version (separate from schema)
- [ ] `schema_contract` field documents forward compatibility requirement
- [ ] `--schema` flag outputs human-readable schema documentation
- [ ] Existing mesh output structure unchanged (additive only)

### Task 5.4: Complete Cultural BUTTERFREEZONE — Generative Culture from #247

**File**: `.claude/scripts/butterfreezone-gen.sh` — `extract_culture()`, `.loa.config.yaml`

**Description**: Address Section IX Criticism 4: "The Cultural BUTTERFREEZONE captures institutional culture (naming, principles) but misses generative culture — the free jazz methodology, TAZ references, study group pedagogy from #247 that makes Loa distinctive." Extend the culture section to include both institutional and generative dimensions.

Implementation:
1. Extend `.loa.config.yaml` culture block with `generative` subsection:
```yaml
butterfreezone:
  culture:
    naming_etymology: "Vodou terminology (Loa, Grimoire, Hounfour, Simstim) as cognitive hooks for agent framework concepts"
    principles:
      - "Think Before Coding — plan and analyze before implementing"
      - "Simplicity First — minimum complexity for the current task"
      - "Surgical Changes — minimal diff, maximum impact"
      - "Goal-Driven — every action traces to acceptance criteria"
    methodology: "Agent-driven development with iterative excellence loops (Simstim, Run Bridge, Flatline Protocol)"
    generative:
      description: "Creative methodology drawing from cyberpunk fiction, free jazz improvisation, and temporary autonomous zones"
      references:
        - "Neuromancer (Gibson) — Simstim as shared consciousness metaphor"
        - "Flatline Protocol — adversarial multi-model review as creative tension"
        - "TAZ (Hakim Bey) — temporary spaces for autonomous agent exploration"
      study_groups: "Knowledge production through collective inquiry — Flatline as multi-model study group"
```

2. Update `extract_culture()` to emit both institutional and generative sections:
```markdown
## Culture
<!-- provenance: OPERATIONAL -->
**Naming**: Vodou terminology (Loa, Grimoire, Hounfour, Simstim) as cognitive hooks for agent framework concepts.

**Principles**: Think Before Coding — plan and analyze before implementing, Simplicity First — minimum complexity for the current task, Surgical Changes — minimal diff, maximum impact, Goal-Driven — every action traces to acceptance criteria.

**Methodology**: Agent-driven development with iterative excellence loops (Simstim, Run Bridge, Flatline Protocol).
```

3. Only emit the generative subsection when config has it (backward compatible)

**Acceptance Criteria**:
- [ ] Culture section includes both institutional (naming, principles, methodology) and generative dimensions when configured
- [ ] Generative subsection omitted when config lacks `butterfreezone.culture.generative`
- [ ] #247 references (TAZ, free jazz, study groups) appear in Loa's own BUTTERFREEZONE
- [ ] Existing culture output unchanged for repos without generative config
- [ ] `yq '.butterfreezone.culture.generative' .loa.config.yaml` returns valid YAML

---

## Sprint 6: Scoped Capabilities & Trust Gradient — Permission Scape Foundation

**Global ID**: sprint-111
**Goal**: Evolve `capability_requirements` from flat labels to scoped capabilities that connect to the Three-Zone Model, and implement the Trust Gradient L1-L4 vocabulary that bridges BUTTERFREEZONE verification to Hounfour trust classification. Define cross-repo interface schemas consumed by loa-finn, loa-hounfour, and arrakis.

**FAANG parallel**: AWS IAM scoped policies — `s3:PutObject` scoped to `arn:aws:s3:::my-bucket/*` rather than `s3:*`. Google's Binary Authorization — trust levels (attested, verified, signed) gate deployment. Stripe's capability-based billing — each API key has scoped capabilities tied to pricing tiers. These three patterns converge in our Permission Scape: BUTTERFREEZONE declares scoped needs, Hounfour provides trust-verified pools, arrakis maps capabilities to costs.

### Task 6.1: Scoped Capability Inference with Three-Zone Awareness

**File**: `.claude/scripts/butterfreezone-gen.sh` — `extract_skill_capabilities()`

**Description**: Extend capability_requirements from flat labels (`filesystem: write`) to scoped labels (`filesystem: write (scope: state)`) that align with the Three-Zone Model. This is the foundation of the Permission Scape — skills declare not just WHAT they need, but WHERE they need it.

Scope vocabulary (derived from Three-Zone Model):

| Scope | Zone | Path Pattern | Meaning |
|-------|------|-------------|---------|
| `system` | System | `.claude/` | Framework-managed files (NEVER for app code) |
| `state` | State | `grimoires/`, `.beads/`, `.ck/`, `.run/` | Project artifacts and memory |
| `app` | App | `src/`, `lib/`, `app/` | Developer-owned application code |
| `external` | — | GitHub API, network | External service access |

Implementation:
1. For each SKILL.md, detect not just capability keywords but zone context
2. Zone detection heuristics:
   - Mentions `grimoires`, `sprint.md`, `prd.md`, `sdd.md`, `.run/`, `.beads/` → `state`
   - Mentions `src/`, `lib/`, `app/`, "application code", "source code" → `app`
   - Mentions `.claude/`, "framework", "scripts" → `system`
   - Mentions `gh `, `GitHub`, `PR`, `issue` → `external`
3. Aggregate: if a skill needs `filesystem:write` in both `state` and `app` zones, emit both
4. Output format:

```yaml
capability_requirements:
  - filesystem: read
  - filesystem: write (scope: state)
  - filesystem: write (scope: app)
  - git: read_write
  - shell: execute
  - github_api: read_write (scope: external)
```

5. Backward compatibility: consumers that don't understand `(scope: ...)` can strip the parenthetical and get the flat capability

**Acceptance Criteria**:
- [ ] `/implementing-tasks` SKILL.md produces `filesystem: write (scope: app)` and `filesystem: write (scope: state)`
- [ ] `/reviewing-code` SKILL.md produces `filesystem: read` (no write scope needed)
- [ ] `/riding-codebase` SKILL.md produces `filesystem: write (scope: state)` (writes grimoire artifacts, not app code)
- [ ] Flat capabilities still work when no scope is detectable
- [ ] Scope vocabulary matches Three-Zone Model exactly
- [ ] Parenthetical scope is strippable for backward-compatible consumers

### Task 6.2: Trust Gradient L1-L4 Verification Vocabulary

**File**: `.claude/scripts/butterfreezone-gen.sh` — `extract_verification()`

**Description**: Extend the `## Verification` section to compute and emit a trust level (L1-L4) based on verification depth. This bridges BUTTERFREEZONE to Hounfour's trust classification system (per loa-hounfour PR #2's safety/liveness property model).

Trust Gradient Vocabulary:

| Level | Name | Criteria | Hounfour Trust |
|-------|------|----------|---------------|
| L1 | Tests Present | ≥1 test file exists | `basic` |
| L2 | CI Verified | Tests + CI pipeline configured + passing badge | `verified` |
| L3 | Property-Based | L2 + property-based/behavioral tests detected (fast-check, hypothesis, proptest) | `hardened` |
| L4 | Formal | L3 + formal temporal properties OR safety/liveness proofs detected | `proven` |

Implementation:
1. After existing verification signal extraction, compute trust level:
```bash
compute_trust_level() {
    local level=0
    local test_count="$1"
    local has_ci="$2"
    local has_property_tests="$3"
    local has_formal="$4"

    [[ "$test_count" -gt 0 ]] && level=1
    [[ "$level" -ge 1 && "$has_ci" == "true" ]] && level=2
    [[ "$level" -ge 2 && "$has_property_tests" == "true" ]] && level=3
    [[ "$level" -ge 3 && "$has_formal" == "true" ]] && level=4

    echo "$level"
}
```

2. Detect property-based tests: grep dependency files for `fast-check`, `hypothesis`, `proptest`, `quickcheck`, `jqwik`
3. Detect formal properties: grep for `safety_properties`, `liveness_properties`, `temporal_logic`, `model_check`, or dedicated `*.property.ts` / `*.property.py` files
4. Emit in both AGENT-CONTEXT and Verification section:

```yaml
<!-- AGENT-CONTEXT
...
trust_level: L2-verified
-->
```

```markdown
## Verification
<!-- provenance: CODE-FACTUAL -->
- Trust Level: **L2 — CI Verified**
- 142 test files across 1 suite
- CI/CD: GitHub Actions (10 workflows)
- Security: SECURITY.md present
```

5. For cross-repo mesh: include `trust_level` in mesh node data when fetching remote BFZ

**Acceptance Criteria**:
- [ ] Loa repo computes L2 (has tests + CI, no property-based tests yet)
- [ ] loa-hounfour (if BFZ exists) would compute L3 or L4 (has 6 safety + 3 liveness properties per PR #2)
- [ ] Trust level appears in both AGENT-CONTEXT `trust_level` field and `## Verification` section
- [ ] Level computation is monotonic (can't skip levels)
- [ ] Mesh nodes include `trust_level` field

### Task 6.3: Cross-Repo Capability Schema Definition

**File**: `docs/architecture/capability-schema.md` (new)

**Description**: Define the formal schema that bridges BUTTERFREEZONE capability_requirements to loa-finn's Hounfour pool routing (RFC #31 §5.2), arrakis's billing (PR #63), and loa-hounfour's trust classification (PR #2). This is an interface contract — loa defines it, other repos consume it.

Schema definition:

```yaml
# BUTTERFREEZONE Capability Schema v1.0
# Defined in: 0xHoneyJar/loa
# Consumed by: loa-finn (pool routing), arrakis (billing), loa-hounfour (trust)

capability_vocabulary:
  filesystem:
    actions: [read, write]
    scopes: [system, state, app]
    hounfour_pool_hint: null  # filesystem ops don't require specific model pools
    billing_weight: 0  # no API cost for local filesystem

  git:
    actions: [read, write, read_write]
    scopes: [local, remote]
    hounfour_pool_hint: null
    billing_weight: 0

  github_api:
    actions: [read, write, read_write]
    scopes: [external]
    hounfour_pool_hint: null
    billing_weight: 1  # GitHub API calls have rate limits

  shell:
    actions: [execute]
    scopes: [local]
    hounfour_pool_hint: null
    billing_weight: 0

  network:
    actions: [read, write]
    scopes: [external]
    hounfour_pool_hint: null
    billing_weight: 1  # external HTTP calls

  model:
    actions: [invoke]
    scopes: [cheap, fast_code, reviewer, reasoning, architect]
    hounfour_pool_hint: "{scope}"  # scope IS the pool name
    billing_weight: 3  # model invocations are the primary cost driver

trust_gradient:
  L1:
    name: "Tests Present"
    criteria: "≥1 test file exists"
    hounfour_trust: "basic"
    min_pool_access: [cheap, fast_code]
  L2:
    name: "CI Verified"
    criteria: "Tests + CI pipeline configured"
    hounfour_trust: "verified"
    min_pool_access: [cheap, fast_code, reviewer]
  L3:
    name: "Property-Based"
    criteria: "L2 + property-based/behavioral tests"
    hounfour_trust: "hardened"
    min_pool_access: [cheap, fast_code, reviewer, reasoning]
  L4:
    name: "Formal"
    criteria: "L3 + formal temporal properties/proofs"
    hounfour_trust: "proven"
    min_pool_access: [cheap, fast_code, reviewer, reasoning, architect]

# Cross-repo consumption pattern:
# 1. loa-finn reads BFZ capability_requirements
# 2. Maps scoped capabilities to required pool access
# 3. Trust level gates which pools are available
# 4. arrakis maps pool usage to billing weight
```

Also add section to PROCESS.md referencing this schema.

**Acceptance Criteria**:
- [ ] Schema defines all capabilities in the existing vocabulary with scopes
- [ ] Each capability maps to hounfour_pool_hint and billing_weight
- [ ] Trust gradient maps to hounfour trust levels and min pool access
- [ ] Schema is machine-parseable YAML (not just documentation)
- [ ] PROCESS.md references the capability schema document
- [ ] Cross-repo consumption pattern is documented

### Task 6.4: Update PROCESS.md with Trust Gradient and Scoped Capabilities

**File**: `PROCESS.md`

**Description**: Extend the BUTTERFREEZONE standard section in PROCESS.md to document:
1. Scoped capabilities and their relationship to the Three-Zone Model
2. Trust Gradient L1-L4 vocabulary and what each level means
3. Cross-repo capability schema location and consumption pattern
4. Permission Scape concept (BUTTERFREEZONE declares needs → Hounfour provides pools → arrakis maps costs)

**Acceptance Criteria**:
- [ ] Scoped capability vocabulary table in PROCESS.md
- [ ] Trust gradient L1-L4 table in PROCESS.md
- [ ] Permission Scape flow diagram (text-based) in PROCESS.md
- [ ] Reference to `docs/architecture/capability-schema.md`
- [ ] Existing PROCESS.md content preserved

---

## Sprint 7: Ecosystem Verification & Mesh Evolution + Self-Hosting

**Global ID**: sprint-112
**Goal**: Add live ecosystem verification to the validator, evolve the mesh script with caching and multi-format output, and perform comprehensive self-hosting regeneration with all phase 1 + phase 2 features. Final validation gate.

**FAANG parallel**: Kubernetes liveness/readiness probes — periodic validation that declared dependencies are actually alive and healthy. Terraform plan — diff between declared state and actual state before applying changes. CNCF's Artifact Hub — multi-format package metadata (JSON, OCI, Helm) for cross-tool consumption. Our ecosystem verification is the liveness probe for the cross-repo dependency graph.

### Task 7.1: Live Ecosystem Verification in Validator

**File**: `.claude/scripts/butterfreezone-validate.sh`

**Description**: Add `validate_ecosystem_live()` that optionally checks whether declared ecosystem repos actually exist and have BUTTERFREEZONE.md files. This is an advisory check (WARN, not FAIL) that runs only when `--live` flag is passed (requires `gh` auth).

Implementation:
```bash
validate_ecosystem_live() {
    # Only run with --live flag (requires network + gh auth)
    [[ "$LIVE_CHECK" != "true" ]] && return 0

    if ! gh auth status &>/dev/null 2>&1; then
        log_warn "eco_live" "gh not authenticated — skipping live ecosystem check" "no_auth"
        return 0
    fi

    local eco_repos
    eco_repos=$(sed -n '/<!-- AGENT-CONTEXT/,/-->/p' "$FILE" 2>/dev/null | \
        grep '^\s*- repo:' | sed 's/.*repo: *//')

    [[ -z "$eco_repos" ]] && return 0

    local total=0 found=0 missing=0 no_bfz=0
    while IFS= read -r repo; do
        [[ -z "$repo" ]] && continue
        total=$((total + 1))

        # Check repo exists
        if ! gh repo view "$repo" &>/dev/null 2>&1; then
            log_warn "eco_live" "Ecosystem repo not found: $repo" "missing_repo"
            missing=$((missing + 1))
            continue
        fi

        # Check BUTTERFREEZONE.md exists
        if ! gh api "repos/${repo}/contents/BUTTERFREEZONE.md" &>/dev/null 2>&1; then
            log_warn "eco_live" "No BUTTERFREEZONE.md in: $repo" "no_bfz"
            no_bfz=$((no_bfz + 1))
            continue
        fi

        found=$((found + 1))
    done <<< "$eco_repos"

    if [[ "$missing" -eq 0 && "$no_bfz" -eq 0 ]]; then
        log_pass "eco_live" "All $total ecosystem repos verified with BUTTERFREEZONE.md"
    fi
}
```

Add `--live` flag to argument parsing:
```bash
--live) LIVE_CHECK="true"; shift ;;
```

**Acceptance Criteria**:
- [ ] Without `--live` flag, check is silently skipped (no output)
- [ ] With `--live` and valid ecosystem, all repos verified → PASS
- [ ] With `--live` and missing repo → WARN with repo slug
- [ ] With `--live` and repo without BFZ → WARN with repo slug
- [ ] With `--live` and no gh auth → WARN about auth, skip gracefully
- [ ] Validator exit code unchanged by advisory WARNs

### Task 7.2: Mesh Response Caching

**File**: `.claude/scripts/butterfreezone-mesh.sh`

**Description**: Add local caching for remote BUTTERFREEZONE.md fetches to avoid redundant `gh api` calls during repeated mesh generation. Cache to `.run/mesh-cache/` with TTL-based expiry.

Implementation:
1. Cache directory: `.run/mesh-cache/`
2. Cache key: repo slug with `/` replaced by `_` (e.g., `0xHoneyJar_loa-finn.json`)
3. Cache entry: `{ "fetched_at": "...", "ttl_seconds": 3600, "content": "..." }`
4. On fetch: check cache first, use if within TTL
5. Add `--no-cache` flag to force fresh fetches
6. Add `--cache-ttl N` flag to override default TTL (default: 3600 seconds / 1 hour)

```bash
fetch_remote_bfz_cached() {
    local repo="$1"
    local cache_dir=".run/mesh-cache"
    local cache_key="${repo//\//_}.json"
    local cache_file="${cache_dir}/${cache_key}"

    mkdir -p "$cache_dir"

    # Check cache
    if [[ "$NO_CACHE" != "true" && -f "$cache_file" ]]; then
        local fetched_at now ttl age
        fetched_at=$(jq -r '.fetched_at' "$cache_file" 2>/dev/null) || fetched_at=0
        now=$(date +%s)
        ttl="${CACHE_TTL:-3600}"
        age=$((now - fetched_at))

        if [[ "$age" -lt "$ttl" ]]; then
            jq -r '.content' "$cache_file" 2>/dev/null
            return 0
        fi
    fi

    # Fetch fresh
    local content
    content=$(fetch_remote_bfz "$repo")

    # Cache result
    if [[ -n "$content" ]]; then
        jq -n \
            --arg content "$content" \
            --arg fetched_at "$(date +%s)" \
            '{fetched_at: ($fetched_at | tonumber), content: $content}' \
            > "$cache_file"
    fi

    echo "$content"
}
```

**Acceptance Criteria**:
- [ ] First mesh run fetches from GitHub API (cache miss)
- [ ] Second mesh run within TTL uses cache (no API call)
- [ ] `--no-cache` flag forces fresh fetch
- [ ] `--cache-ttl 0` disables caching
- [ ] Cache files stored in `.run/mesh-cache/` (gitignored)
- [ ] Cache entries are valid JSON with fetched_at timestamp

### Task 7.3: Multi-Format Mesh Output

**File**: `.claude/scripts/butterfreezone-mesh.sh`

**Description**: Extend mesh output beyond JSON and markdown to include Mermaid diagram format. This enables embedding the ecosystem graph in documentation and PR descriptions.

Add `--format mermaid` option:
```bash
elif [[ "$FORMAT" == "mermaid" ]]; then
    local mermaid="graph LR\n"

    # Add nodes
    local node_count
    node_count=$(echo "$nodes_json" | jq 'length')
    for i in $(seq 0 $((node_count - 1))); do
        local node_name node_type
        node_name=$(echo "$nodes_json" | jq -r ".[$i].name")
        node_type=$(echo "$nodes_json" | jq -r ".[$i].type")
        mermaid="${mermaid}    ${node_name}[\"${node_name}<br/>${node_type}\"]\n"
    done

    # Add edges
    local edge_count
    edge_count=$(echo "$edges_json" | jq 'length')
    for i in $(seq 0 $((edge_count - 1))); do
        local from_name to_name role
        local from_repo to_repo
        from_repo=$(echo "$edges_json" | jq -r ".[$i].from")
        to_repo=$(echo "$edges_json" | jq -r ".[$i].to")
        role=$(echo "$edges_json" | jq -r ".[$i].role")
        from_name=$(basename "$from_repo")
        to_name=$(basename "$to_repo")
        mermaid="${mermaid}    ${from_name} -->|${role}| ${to_name}\n"
    done

    if [[ -n "$OUTPUT" ]]; then
        printf '%b' "$mermaid" > "$OUTPUT"
        echo "Mermaid diagram written to: $OUTPUT" >&2
    else
        printf '%b' "$mermaid"
    fi
fi
```

Update format validation:
```bash
if [[ "$FORMAT" != "json" && "$FORMAT" != "markdown" && "$FORMAT" != "mermaid" ]]; then
    echo "ERROR: --format must be 'json', 'markdown', or 'mermaid'" >&2
    exit 1
fi
```

**Acceptance Criteria**:
- [ ] `--format mermaid` produces valid Mermaid graph LR syntax
- [ ] Node names are human-readable (basename, not full slug)
- [ ] Edge labels show role (runtime, protocol, distribution)
- [ ] Output embeddable in markdown code blocks
- [ ] Existing JSON and markdown formats unchanged
- [ ] Invalid `--format` values produce error message

### Task 7.4: Self-Hosting — Comprehensive Regeneration and Validation

**Description**: Run the full generator with ALL phase 1 + phase 2 features on the Loa repo and validate comprehensive output quality. This is the final acceptance gate for cycle-017.

Steps:
1. Run `.claude/scripts/butterfreezone-gen.sh --verbose`
2. Run `.claude/scripts/butterfreezone-validate.sh --strict`
3. Run `.claude/scripts/butterfreezone-validate.sh --strict --live` (with gh auth)
4. Run `.claude/scripts/butterfreezone-mesh.sh --format json`
5. Run `.claude/scripts/butterfreezone-mesh.sh --format mermaid`

Verify all sections in generated BUTTERFREEZONE.md:

| Section | Expected Content |
|---------|-----------------|
| AGENT-CONTEXT | ecosystem, capability_requirements (scoped), trust_level: L2-verified |
| Header | Rich narrative description, correct version |
| Key Capabilities | ≤15 entries with descriptions and file:line provenance |
| Architecture | Three-zone narrative + Mermaid diagram + directory tree |
| Interfaces | Skill commands with descriptions from SKILL.md |
| Module Map | All modules with Purpose filled, documentation links |
| Verification | Trust Level L2, test count, CI count, security signals |
| Agents | Bridgebuilder persona with Identity and Voice |
| Culture | Institutional + generative dimensions |
| Quick Start | Prerequisites + installation + golden path commands |

Validator checks:
- All 16+ checks PASS in strict mode
- Ecosystem staleness check PASS (config matches AGENT-CONTEXT)
- Live ecosystem check PASS (all repos verified)
- Word count ≥1000 (increased from 900 due to culture generative subsection)
- No regressions from phase 1

Mesh validation:
- JSON mesh has correct schema_version, forward-compatibility contract
- Mermaid output produces valid diagram syntax
- Cached fetches work on second run

**Acceptance Criteria**:
- [ ] All validator checks pass (strict mode) — zero FAIL
- [ ] Live ecosystem verification passes — all 3 repos found with BFZ (or graceful WARN if repos don't have BFZ yet)
- [ ] Mesh JSON includes `schema_version: "1.0"` and `schema_contract`
- [ ] Mesh Mermaid produces embeddable graph
- [ ] AGENT-CONTEXT has scoped capability_requirements
- [ ] AGENT-CONTEXT trust_level is `L2-verified`
- [ ] Culture section has generative dimension
- [ ] Word count ≥1000
- [ ] No regressions in capabilities, architecture, interfaces, module map sections
- [ ] Negative-keyword filtering produces accurate capabilities (manual spot check)
- [ ] Config staleness detection works (test by temporarily modifying config)
