# SDD: Compassionate Excellence — Bridgebuilder Deep Review Integration

> **Cycle**: 047
> **Created**: 2026-02-28
> **PRD**: `grimoires/loa/prd.md`
> **Target**: `.claude/` System Zone (scripts, skills, data, lib) + `.loa.config.yaml` + `grimoires/loa/lore/`

---

## 1. System Architecture

### 1.1 Component Map

```
┌─────────────────────────────────────────────────────────────┐
│                    Shared Libraries  (NEW — FR-3)            │
│                                                             │
│  .claude/scripts/lib/                                       │
│  ├── findings-lib.sh    ← extract_prior_findings()          │
│  ├── compliance-lib.sh  ← extract_sections_by_keywords()    │
│  └── (sourced by red-team-*.sh, pipeline-self-review.sh,    │
│       bridge-orchestrator.sh)                                │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│              Constitutional SDD Map  (NEW — FR-2)            │
│                                                             │
│  pipeline-sdd-map.json:                                     │
│    forward:  implementation → governing SDD                  │
│    reverse:  SDD → governed implementations  (NEW)          │
│    change:   triggers self-review + human flag               │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│              Deliberation Observability (NEW — FR-1)         │
│                                                             │
│  Each Red Team invocation logs:                              │
│    { input_channels: [...], char_counts: {...},              │
│      token_budget: N, prior_findings_used: [...] }          │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│              Lore Lifecycle  (NEW — FR-2)                    │
│                                                             │
│  patterns.yaml entries gain:                                 │
│    status: Active | Challenged | Deprecated | Superseded    │
│    challenges: [{date, source, description}]                 │
│    lineage: <id of predecessor pattern>                      │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│          Compliance Gate Separation  (NEW — FR-3)            │
│                                                             │
│  Gate = Extraction (keywords → sections)                    │
│       + Evaluation (prompt_template → model → findings)     │
│  Currently conflated; Sprint 3 separates them               │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 Data Flow: Shared Library Integration

```
red-team-code-vs-design.sh          pipeline-self-review.sh
         │                                    │
         ├── source lib/findings-lib.sh ──────┤
         ├── source lib/compliance-lib.sh ────┤
         │                                    │
         ▼                                    ▼
  extract_prior_findings()          extract_sections_by_keywords()
  extract_sections_by_keywords()    load_compliance_profile()
  log_deliberation_metadata()
```

## 2. Detailed Design

### 2.1 FR-1: Verification + Defensive Hardening

#### 2.1.1 Gemini Participation Investigation

Trace the Gemini path through the Flatline Protocol:

1. Config: `.loa.config.yaml` → `flatline_protocol.models.tertiary: gemini-2.5-pro`
2. Orchestrator: `flatline-orchestrator.sh` → `get_model_tertiary()` function
3. Model adapter: `.claude/scripts/model-adapter.sh` → `MODEL_PROVIDERS[gemini-2.5-pro]`
4. API call: Verify the adapter actually invokes Gemini API (not silently skipping)

Acceptance: Either confirm Gemini works end-to-end, or identify and fix the break point.

#### 2.1.2 Red Team Simstim Documentation

The Red Team code-vs-design gate is wired into the run-mode SKILL.md (step 7) but gated by config. In simstim workflow, `red_team.simstim.auto_trigger: false`. Document this explicitly in:

- simstim SKILL.md — add "Red Team Integration" section
- `.loa.config.yaml.example` — document the red_team.simstim keys

#### 2.1.3 F-004 Glob Boundary Fix

The `*` → `.*` regex conversion matches across `/` boundaries. For git diff output (flat paths like `.claude/scripts/foo.sh`), this works because paths contain no internal structure ambiguity. However, for robustness:

```bash
# Option A: Document the flat-path assumption (minimal change)
# The glob-to-regex is only applied to git diff --name-only output,
# which always produces full relative paths without trailing slashes.

# Option B: Use [^/]* instead of .* for non-** globs
gsub("\\*\\*"; ".*") | gsub("\\*"; "[^/]*")
```

Decision: Option B (more defensive) since `**` patterns may appear in future SDD map entries.

#### 2.1.4 F-007 Fence Stripping Hardening

When models return preamble text before JSON (e.g., "Here is the analysis:\n```json\n{...}"), the current `strip_code_fences()` only activates if the first line is a fence. Add pre-JSON detection:

```bash
strip_code_fences() {
    local input="$1"
    # Check if FIRST line is a fence
    if echo "$input" | head -1 | grep -qE '^[[:space:]]*```'; then
        echo "$input" | awk '/^[[:space:]]*```/{if(f){exit}else{f=1;next}} f'
    # Check if ANY line starts a fence (preamble case)
    elif echo "$input" | grep -qE '^[[:space:]]*```'; then
        echo "$input" | awk '/^[[:space:]]*```/{if(f){exit}else{f=1;next}} f'
    else
        echo "$input"
    fi
}
```

#### 2.1.5 Deliberation Observability

Add metadata logging to each Red Team invocation in `red-team-code-vs-design.sh`:

```bash
log_deliberation_metadata() {
    local output_dir="$1"
    local sdd_chars="$2"
    local diff_chars="$3"
    local prior_chars="$4"
    local input_channels="$5"
    local token_budget="$6"

    local meta_file="${output_dir}/deliberation-metadata.json"
    jq -n \
        --argjson sdd "$sdd_chars" \
        --argjson diff "$diff_chars" \
        --argjson prior "$prior_chars" \
        --argjson channels "$input_channels" \
        --argjson budget "$token_budget" \
        '{
            timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
            input_channels: $channels,
            char_counts: {sdd: $sdd, diff: $diff, prior_findings: $prior},
            token_budget: $budget,
            budget_per_channel: ($budget / $channels)
        }' > "$meta_file"
}
```

### 2.2 FR-2: Constitutional Architecture

#### 2.2.1 Pipeline SDD Map Constitutional Promotion

Add `pipeline-sdd-map.json` to the pipeline-sdd-map.json itself (self-referential governance):

```json
{
    "glob": ".claude/data/pipeline-sdd-map.json",
    "sdd": ".claude/skills/run-bridge/SKILL.md",
    "sections": ["Pipeline Self-Review", "SDD Mapping", "Governance"],
    "constitutional": true
}
```

The `constitutional: true` flag causes pipeline-self-review.sh to emit a `CONSTITUTIONAL_CHANGE` marker in findings, which the bridge orchestrator surfaces as requiring human attention.

#### 2.2.2 Reverse Mapping

Add a `resolve_governed_implementations()` function to pipeline-self-review.sh:

```bash
resolve_governed_implementations() {
    local sdd_path="$1"
    local map_file="${2:-.claude/data/pipeline-sdd-map.json}"

    jq -r --arg sdd "$sdd_path" \
        '.patterns[] | select(.sdd == $sdd) | .glob' \
        "$map_file"
}
```

This enables: "when run-bridge/SKILL.md changes, which implementation files does it govern?"

#### 2.2.3 Lore Lifecycle Schema

Extend `grimoires/loa/lore/patterns.yaml` schema:

```yaml
- id: governance-isomorphism
  term: Governance Isomorphism
  short: "..."
  context: |
    ...
  source: "bridge-20260228-170473 deep-review / PR #429"
  tags: [architecture, governance, cross-repo, pattern]
  # NEW lifecycle fields
  status: Active  # Active | Challenged | Deprecated | Superseded
  challenges: []  # [{date: "2026-02-28", source: "bridge-xyz", description: "..."}]
  lineage: null    # ID of predecessor pattern, if this evolved from another
  superseded_by: null  # ID of successor pattern, if deprecated
```

Update `grimoires/loa/lore/index.yaml` to include lifecycle metadata for filtering.

#### 2.2.4 Lore Discoverability in Bridge Reviews

During bridge review, the orchestrator queries the lore index for entries tagged with relevant domains:

```bash
discover_relevant_lore() {
    local changed_files="$1"
    local lore_file="grimoires/loa/lore/patterns.yaml"

    if [[ ! -f "$lore_file" ]]; then return; fi

    # Extract tags from changed file paths
    local domains=""
    if echo "$changed_files" | grep -q "scripts/"; then
        domains="$domains|pipeline|review"
    fi
    if echo "$changed_files" | grep -q "lore/"; then
        domains="$domains|governance|architecture"
    fi

    # Query lore for matching tags where status is Active
    yq ".[].tags[]" "$lore_file" 2>/dev/null | sort -u
}
```

### 2.3 FR-3: Shared Library Extraction

#### 2.3.1 findings-lib.sh

Extract from `red-team-code-vs-design.sh` to `.claude/scripts/lib/findings-lib.sh`:

```bash
#!/usr/bin/env bash
# findings-lib.sh — Shared functions for extracting and processing review findings
# Sourced by: red-team-code-vs-design.sh, pipeline-self-review.sh, bridge-orchestrator.sh

extract_prior_findings() {
    local path="$1"
    local max_chars="${2:-20000}"

    if [[ ! -f "$path" ]]; then
        return
    fi

    local content
    content=$(grep -iE "^## (Findings|Issues|Changes Required|Security|SEC-)" "$path" \
        | head -c "$max_chars")

    if [[ -z "$content" ]]; then
        # Fallback: extract everything after first ## heading
        content=$(sed -n '/^## /,$p' "$path" | head -c "$max_chars")
    fi

    echo "$content"
}

strip_code_fences() {
    local input="$1"
    if echo "$input" | grep -qE '^[[:space:]]*```'; then
        echo "$input" | awk '/^[[:space:]]*```/{if(f){exit}else{f=1;next}} f'
    else
        echo "$input"
    fi
}
```

#### 2.3.2 compliance-lib.sh

Extract from `red-team-code-vs-design.sh` to `.claude/scripts/lib/compliance-lib.sh`:

```bash
#!/usr/bin/env bash
# compliance-lib.sh — Shared functions for compliance gate extraction and evaluation

# Load compliance profile keywords from config
load_compliance_keywords() {
    local profile="${1:-security}"
    local config_file="${2:-.loa.config.yaml}"
    local default_keywords="Security|Authentication|Authorization|Validation|Error.Handling|Access.Control|Secrets|Encryption|Input.Sanitiz"

    if command -v yq &>/dev/null && [[ -f "$config_file" ]]; then
        local config_keywords
        config_keywords=$(yq ".red_team.compliance_gates.${profile}.keywords // [] | join(\"|\")" "$config_file" 2>/dev/null || echo "")
        if [[ -n "$config_keywords" ]]; then
            echo "$config_keywords"
            return
        fi
    fi

    echo "$default_keywords"
}

# Extract SDD sections matching keyword pattern
extract_sections_by_keywords() {
    local file_path="$1"
    local max_chars="${2:-20000}"
    local keywords="${3:-$(load_compliance_keywords)}"

    # ... extraction logic with parameterized keywords ...
}

# Load prompt template for a compliance gate profile
load_prompt_template() {
    local profile="${1:-security}"
    local config_file="${2:-.loa.config.yaml}"

    if command -v yq &>/dev/null && [[ -f "$config_file" ]]; then
        local template
        template=$(yq ".red_team.compliance_gates.${profile}.prompt_template // \"\"" "$config_file" 2>/dev/null || echo "")
        if [[ -n "$template" ]]; then
            echo "$template"
            return
        fi
    fi

    echo "security-comparison"  # Default
}
```

#### 2.3.3 Gate Separation: Extraction vs Evaluation

The compliance gate currently conflates extraction (finding relevant SDD sections) with evaluation (comparing code against those sections). Separate them:

```
┌─────────────┐     ┌──────────────┐     ┌────────────────┐
│ Extraction   │ ──→ │ Sections     │ ──→ │ Evaluation     │
│ (keywords)   │     │ (text)       │     │ (model prompt) │
└─────────────┘     └──────────────┘     └────────────────┘
```

The `red-team-code-vs-design.sh` prompt currently includes both. After refactoring:

1. `compliance-lib.sh::extract_sections_by_keywords()` handles extraction
2. `compliance-lib.sh::load_prompt_template()` returns the evaluation template name
3. `red-team-code-vs-design.sh` assembles the prompt using both components

#### 2.3.4 Prompt Template Support

Add `prompt_template` field to compliance gate config:

```yaml
compliance_gates:
  security:
    keywords: [Security, Authentication, ...]
    prompt_template: "security-comparison"
  # Future:
  # api_contract:
  #   keywords: [Interface, Export, Contract, Protocol]
  #   prompt_template: "contract-comparison"
```

The template name maps to a prompt construction pattern in the Red Team script. For now, only "security-comparison" exists (the current default behavior). The extensibility point is the template name field — future templates can be added without changing the extraction logic.

### 2.4 FR-4: Adaptive Intelligence + Ecosystem Design

#### 2.4.1 Adaptive Token Budget

Design for future implementation (not active by default):

```bash
compute_adaptive_budget() {
    local total_budget="$1"
    local sdd_size="$2"
    local diff_size="$3"
    local prior_size="$4"

    local total_input=$((sdd_size + diff_size + prior_size))
    if [[ $total_input -eq 0 ]]; then
        echo "$total_budget $total_budget $total_budget"
        return
    fi

    # Weight by content size (larger inputs get proportionally more budget)
    local sdd_budget=$((total_budget * sdd_size / total_input))
    local diff_budget=$((total_budget * diff_size / total_input))
    local prior_budget=$((total_budget * prior_size / total_input))

    # Floor: minimum 4000 chars per channel
    local floor=4000
    sdd_budget=$((sdd_budget > floor ? sdd_budget : floor))
    diff_budget=$((diff_budget > floor ? diff_budget : floor))
    prior_budget=$((prior_budget > floor ? prior_budget : floor))

    echo "$sdd_budget $diff_budget $prior_budget"
}
```

Gated by config: `red_team.adaptive_budget.enabled: false` (default).

#### 2.4.2 Cost Tracking

Add inference cost metadata to bridge state:

```json
{
  "iterations": [{
    "red_team_invocations": 2,
    "estimated_input_tokens": 45000,
    "estimated_output_tokens": 3000,
    "sdd_patterns_matched": 5,
    "cost_estimate_usd": 0.12
  }]
}
```

Uses token estimation from char counts (1 token ~ 4 chars) and model pricing from model-adapter.sh `COST_INPUT`/`COST_OUTPUT` arrays.

#### 2.4.3 Cross-Repo Governance Protocol Design

Design document only (extends T4.5 from cycle-046). Key addition: **specification change notification**.

When an SDD changes in repo A and repo B has implementations governed by that SDD:
1. Repo A CI emits a `spec-changed` event with SDD path and diff
2. Repo B's bridge orchestrator detects the event and triggers Red Team review of affected implementations
3. Findings are posted as cross-repo PR comments

This requires: shared SDD index (T4.5), event transport (GitHub webhooks or A2A protocol), and cross-repo auth (existing JWT through Arrakis).

## 3. Security Considerations

- Shared libraries in `.claude/scripts/lib/` are System Zone — not editable by teammates in Agent Teams mode
- Constitutional change markers must not be suppressible by config — they are hardcoded
- Cost tracking metadata may reveal inference provider pricing — keep in `.run/` (ephemeral, not committed)

## 4. Testing Strategy

| Test | Type | Validates |
|------|------|-----------|
| Gemini model adapter call | Integration | FR-1.1: Gemini actually receives and responds to API calls |
| Glob boundary matching | Unit | FR-1.3: `[^/]*` vs `.*` behavior difference |
| Fence stripping with preamble | Unit | FR-1.4: JSON extracted even with model commentary before fences |
| Reverse SDD mapping | Unit | FR-2.2: given SDD path, returns correct globs |
| Lore lifecycle field validation | Unit | FR-2.3: schema validates with new fields |
| Library sourcing | Integration | FR-3.1-2: red-team and pipeline-self-review source shared libs correctly |
| Compliance gate extraction/evaluation split | Integration | FR-3.3: extraction returns raw sections, evaluation uses template |
| Adaptive budget computation | Unit | FR-4.1: larger inputs get proportionally more budget, floor enforced |
