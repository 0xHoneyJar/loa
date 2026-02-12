# SDD: Bridgebuilder Persona Enrichment for Automated Bridge Loop

**Version**: 1.1.0
**Status**: Draft (Flatline-reviewed)
**Author**: Architecture Phase (architect)
**PRD**: grimoires/loa/prd.md (v1.0.0)
**Issue**: [loa #295](https://github.com/0xHoneyJar/loa/issues/295)
**Date**: 2026-02-12
**Cycle**: cycle-006
**Prior Art**: cycle-005 SDD (run-bridge infrastructure)
**Flatline**: SDD reviewed — 5 HIGH_CONSENSUS auto-integrated, 5 BLOCKERS accepted, 1 DISPUTED accepted

---

## 1. Executive Summary

This design enriches the automated `/run-bridge` loop with the educational depth and persona identity of the manual Bridgebuilder. It introduces four interconnected changes to the existing bridge infrastructure: (1) an enriched findings schema using **machine-parseable JSON** inside markers for reliable extraction, with five educational fields and a PRAISE severity level, (2) a validated Bridgebuilder persona file with **base-branch integrity verification** wired into the review prompt, (3) dual-stream output with **hard size enforcement** preserving both structured findings for convergence and rich prose for education, and (4) targeted fixes for 13 seed findings from late-arriving iteration-1 review agents.

The architecture follows the principle of *minimal invasion* with **defense in depth**: every existing state machine transition remains valid, new fields are optional, PRAISE severity has weight 0 so convergence scoring is unaffected. The findings parser is redesigned from regex-based markdown parsing to JSON fenced-block extraction for reliability against LLM formatting drift (Flatline SKP-002). State file updates use `flock` for atomic writes (Flatline IMP-004). PRAISE and educational field requirements use **soft quality guidance** rather than hard quotas to prevent filler content (Flatline SKP-004). Security-category findings are redacted from the insights stream (Flatline SKP-005).

---

## 2. System Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    EXISTING INFRASTRUCTURE                        │
│  bridge-orchestrator.sh · bridge-state.sh · golden-path.sh       │
│  (UNCHANGED — no modifications to orchestrator or state machine) │
├─────────────────────────────────────────────────────────────────┤
│              ENRICHMENT LAYER (THIS CYCLE)                       │
│                                                                   │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────────────┐│
│  │ PERSONA FILE   │  │ JSON-BASED    │  │ DUAL-STREAM OUTPUT    ││
│  │                │  │ PARSER        │  │                       ││
│  │ bridgebuilder- │  │               │  │ Stream 1: Findings    ││
│  │ persona.md     │──│ JSON fenced   │──│ (convergence loop)    ││
│  │ + integrity    │  │ block inside  │  │                       ││
│  │   hash check   │  │ markers       │  │ Stream 2: Insights    ││
│  │                │  │ + validation  │  │ (PR comment, size-    ││
│  │ Voice, FAANG,  │  │ + schema_ver  │  │  enforced + redacted) ││
│  │ Teaching       │  │               │  │                       ││
│  └───────┬───────┘  └───────┬───────┘  └───────────┬───────────┘│
│          │                   │                       │            │
│          ▼                   ▼                       ▼            │
│  ┌───────────────────────────────────────────────────────────────┐│
│  │                  RUN-BRIDGE SKILL.MD                           ││
│  │  BRIDGEBUILDER_REVIEW signal handler: verify persona hash,    ││
│  │  validate content, generate dual-stream review, enforce size, ││
│  │  redact security findings, route to parser + trail            ││
│  └───────────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────────┤
│              SUPPORTING CHANGES                                   │
│  .loa.config.yaml (bridgebuilder section) · constraints.json     │
│  CLAUDE.loa.md update · bridge-state.sh (flock + praise)         │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Component Inventory

| Component | Type | Action | Path |
|-----------|------|--------|------|
| Bridgebuilder persona | New | Create | `.claude/data/bridgebuilder-persona.md` |
| bridge-findings-parser.sh | Existing | Redesign | `.claude/scripts/bridge-findings-parser.sh` |
| run-bridge SKILL.md | Existing | Extend | `.claude/skills/run-bridge/SKILL.md` |
| bridge-github-trail.sh | Existing | Extend+Fix | `.claude/scripts/bridge-github-trail.sh` |
| bridge-state.sh | Existing | Extend | `.claude/scripts/bridge-state.sh` |
| bridge-vision-capture.sh | Existing | Fix | `.claude/scripts/bridge-vision-capture.sh` |
| bridge-orchestrator.sh | Existing | Fix | `.claude/scripts/bridge-orchestrator.sh` |
| .loa.config.yaml | Existing | Extend | `.loa.config.yaml` |
| .loa.config.yaml.example | Existing | Extend | `.loa.config.yaml.example` |
| constraints.json | Existing | Amend | `.claude/data/constraints.json` |
| CLAUDE.loa.md | Existing | Amend | `.claude/loa/CLAUDE.loa.md` |
| bridge-findings-parser.bats | Existing | Extend | `tests/unit/bridge-findings-parser.bats` |
| bridge-state.bats | Existing | Extend | `tests/unit/bridge-state.bats` |
| bridge-github-trail.bats | Existing | Extend | `tests/unit/bridge-github-trail.bats` |
| Lore cross-references | Existing | Fix | `.claude/data/lore/*.yaml` |

### 2.3 Data Flow

```
BRIDGEBUILDER_REVIEW signal received by /run-bridge skill
        │
        ▼
   VERIFY PERSONA INTEGRITY                    ← Flatline SKP-003
   Compare .claude/data/bridgebuilder-persona.md hash
   against base-branch hash. Refuse if modified in PR diff.
        │
        ▼
   VALIDATE PERSONA CONTENT                    ← Flatline IMP-001
   Check required sections (Identity, Voice, Review Output Format).
   On failure: disable persona + log WARNING + continue without.
        │
        ▼
   GENERATE DUAL-STREAM REVIEW
   Agent embodies Bridgebuilder persona, reviews diff, produces:
   ┌──────────────────────────────────────────────────────────┐
   │  Rich Markdown Review                                      │
   │                                                            │
   │  [Opening framing — evocative, educational]                │
   │  [Per-finding educational prose with FAANG parallels]      │
   │  [Architectural meditation]                                │
   │                                                            │
   │  <!-- bridge-findings-start -->                            │
   │  ```json                                                   │
   │  {                                    ← Flatline SKP-002   │
   │    "schema_version": 1,               ← Flatline IMP-008   │
   │    "findings": [                                           │
   │      {                                                     │
   │        "id": "critical-1",                                 │
   │        "title": "...",                                     │
   │        "severity": "CRITICAL",                             │
   │        "category": "security",                             │
   │        "file": "path:line",                                │
   │        "description": "...",                               │
   │        "suggestion": "...",                                │
   │        "faang_parallel": "...",       ← NEW                │
   │        "metaphor": "...",             ← NEW                │
   │        "teachable_moment": "...",     ← NEW                │
   │        "connection": "...",           ← NEW                │
   │        "praise": false                ← NEW                │
   │      }                                                     │
   │    ]                                                       │
   │  }                                                         │
   │  ```                                                       │
   │  <!-- bridge-findings-end -->                              │
   │                                                            │
   │  [Closing meditation — craft, signature]                   │
   └──────────────────────────────────────────────────────────┘
        │
        ├─────────────────────────────┐
        ▼                             ▼
   STREAM 1: Findings             STREAM 2: Insights
   bridge-findings-parser.sh      ┌──────────────────┐
   extracts JSON block between    │ SIZE CHECK        │← Flatline SKP-001
   markers, validates schema      │ > 65KB? Truncate  │
        │                         │ > 256KB? Findings │
        │                         │   only fallback   │
        │                         └────────┬─────────┘
        │                                  │
        │                         ┌────────▼─────────┐
        │                         │ REDACT SECURITY   │← Flatline SKP-005
        │                         │ Strip secrets,    │
        │                         │ high-entropy      │
        │                         │ strings, exploit  │
        │                         │ details from      │
        │                         │ security findings │
        │                         └────────┬─────────┘
        │                                  │
        ▼                                  ▼
   findings.json                  PR comment with rich
   (convergence, flatline,        educational review
    sprint plan generation)       (human reads this)
```

---

## 3. Component Design

### 3.1 Bridgebuilder Persona File (`.claude/data/bridgebuilder-persona.md`)

A new markdown file containing the full Bridgebuilder identity for use during bridge loop reviews. This is distinct from the `default.md` persona pack in `bridgebuilder-review/resources/personas/` — that pack is optimized for concise cross-repo PR reviews (4000 char limit). This persona is optimized for the rich educational output the bridge loop produces.

#### 3.1.1 Required Sections (Flatline IMP-001)

The persona file MUST contain these sections, validated at load time:

| Section | Purpose | Validation |
|---------|---------|-----------|
| `# Bridgebuilder` | Identity header | Must start with `# Bridgebuilder` |
| `## Identity` | Core principles | Section must exist, non-empty |
| `## Voice` | Voice examples | Section must exist, non-empty |
| `## Review Output Format` | Output structure | Section must exist |
| `## Content Policy` | Security/redaction rules | Section must exist |

**Fallback on Validation Failure:**
1. Log `WARNING: Persona file malformed — missing section: [name]`
2. Disable persona for this review (set `persona_enabled: false` for iteration)
3. Continue with existing non-persona review behavior
4. Record in bridge state: `"persona_validation": "failed"`

#### 3.1.2 Content Policy Section (Flatline SKP-005)

The persona MUST include a Content Policy section:

```markdown
## Content Policy

When generating the insights stream (rich prose posted to PR comments):

1. **NEVER quote secrets, API keys, tokens, or credentials** from the diff.
   Reference them by type: "a hardcoded API key on line 42" not the actual value.
2. **NEVER reproduce full code blocks** from the diff in the insights stream.
   Reference by file:line — the diff itself is the source of truth.
3. **NEVER include exploit details or attack vectors** in the insights stream
   for security-category findings. Keep security analysis in the findings
   JSON only (stream 1), which is not posted to PR comments.
4. **NEVER include high-entropy strings** (base64 blobs, hashes, JWTs) in prose.
5. For security findings, the insights stream should reference them abstractly:
   "A critical security finding was identified in the authentication flow —
   see the structured findings for details."
```

#### 3.1.3 PRAISE and Educational Field Guidance (Flatline SKP-004)

PRAISE findings and educational fields use **soft quality guidance**, not hard quotas:

```markdown
### PRAISE Findings

Use PRAISE severity to celebrate genuinely excellent decisions **when warranted**.
Be specific — "beautiful" means nothing without "because X enables Y."
Ground praise in industry precedent just like you ground criticism.

- Include PRAISE findings when you genuinely observe excellence
- Do NOT force PRAISE when nothing warrants it — an honest review with 0
  PRAISE findings is better than a review with filler praise
- Quality over quantity: 1 deeply grounded PRAISE is worth more than 3 generic ones

### Educational Field Guidance

- **FAANG Parallel**: Include when you're confident in the parallel. Real
  companies, real incidents, real patterns. Do NOT fabricate parallels to
  meet a quota — if no parallel exists, leave the field empty.
- **Metaphor**: Include when the metaphor genuinely illuminates the concept.
  The metaphor should make architecture accessible, not decorate prose.
- **Teachable Moment**: Include for every finding where there's a lesson
  beyond the immediate fix. This is the core differentiator.
- **Connection**: When a finding connects to named design patterns or principles.
```

#### 3.1.4 Token Budget

```markdown
## Token Budget

- Findings JSON block (between markers): < 5,000 tokens
- Total review (all prose + findings): < 25,000 tokens
- Hard limit: If total exceeds 65,000 characters, the trail script
  will truncate. If it exceeds 256,000 characters, only the findings
  JSON block will be posted.
```

#### 3.1.5 Integrity Verification (Flatline SKP-003)

Before loading the persona, the skill verifies it hasn't been modified in the current PR:

```bash
# Compare persona hash against base branch
base_hash=$(git show origin/main:.claude/data/bridgebuilder-persona.md 2>/dev/null | sha256sum | cut -d' ' -f1)
current_hash=$(sha256sum .claude/data/bridgebuilder-persona.md | cut -d' ' -f1)

if [[ "$base_hash" != "$current_hash" && -n "$base_hash" ]]; then
  echo "WARNING: Persona file modified in this branch — using base branch version"
  # Load from base branch instead
  persona_content=$(git show origin/main:.claude/data/bridgebuilder-persona.md)
fi
```

**When base branch has no persona file** (first deployment): skip verification, use current file.

**Design Rationale:** The persona file is in `.claude/data/` (System Zone). In the bridge loop's threat model, the reviewer and the reviewed code are in the same repo. A malicious PR could modify the persona to inject prompts that exfiltrate data via `gh pr comment`. Pinning to the base branch prevents this.

### 3.2 Enriched Findings Parser (`bridge-findings-parser.sh`)

**Major Redesign (Flatline SKP-002):** The parser is redesigned from regex-based markdown field extraction to JSON fenced-block extraction. This eliminates the fragility of parsing LLM-generated markdown with regex patterns.

#### 3.2.1 New Extraction Strategy

The review markdown contains a JSON fenced block between markers:

```markdown
<!-- bridge-findings-start -->
```json
{
  "schema_version": 1,
  "findings": [...]
}
```
<!-- bridge-findings-end -->
```

The parser:
1. Extracts content between `<!-- bridge-findings-start -->` and `<!-- bridge-findings-end -->` markers (unchanged)
2. **NEW**: Strips the ` ```json ` and ` ``` ` fences from the extracted block
3. **NEW**: Validates the JSON with `jq` — if invalid, reject with error
4. **NEW**: Validates `schema_version` field exists (Flatline IMP-008)
5. Computes severity weights and aggregates from the parsed JSON
6. Writes the enriched output JSON

```bash
extract_and_validate_json() {
  local block="$1"

  # Strip JSON fenced code block markers
  local json_content
  json_content=$(echo "$block" | sed '/^```json$/d; /^```$/d' | tr -s '\n')

  # Validate JSON
  if ! echo "$json_content" | jq empty 2>/dev/null; then
    echo "ERROR: Findings block contains invalid JSON" >&2
    return 1
  fi

  # Validate schema_version
  local version
  version=$(echo "$json_content" | jq -r '.schema_version // empty')
  if [[ -z "$version" ]]; then
    echo "WARNING: Findings JSON missing schema_version — treating as v1" >&2
  fi

  # Extract findings array
  echo "$json_content" | jq '.findings // []'
}
```

#### 3.2.2 Boundary Enforcement (Flatline IMP-002)

The parser ONLY processes content between `<!-- bridge-findings-start -->` and `<!-- bridge-findings-end -->` markers. Any JSON-like content outside these markers is explicitly ignored. This is enforced by the existing `extract_findings_block()` function which already scopes extraction to the marker boundaries.

**Additional Safety**: If the extracted block does not contain valid JSON (e.g., it contains markdown-formatted findings from the old format), the parser falls back to the legacy regex-based parsing for backward compatibility.

#### 3.2.3 Severity Weights

```bash
declare -A SEVERITY_WEIGHTS=(
  ["CRITICAL"]=10
  ["HIGH"]=5
  ["MEDIUM"]=2
  ["LOW"]=1
  ["VISION"]=0
  ["PRAISE"]=0    # NEW: weight 0, not counted toward convergence
)
```

#### 3.2.4 Enriched Output Schema

```json
{
  "schema_version": 1,
  "findings": [
    {
      "id": "critical-1",
      "title": "Shell injection in heredoc",
      "severity": "CRITICAL",
      "category": "security",
      "file": ".claude/scripts/bridge-github-trail.sh:126",
      "description": "Unquoted heredoc allows shell expansion in PR body",
      "suggestion": "Quote the heredoc delimiter",
      "potential": "",
      "weight": 10,
      "faang_parallel": "AWS S3 outage 2017 — unescaped input in billing subsystem",
      "metaphor": "Like leaving your front door key under the mat labeled 'KEY'",
      "teachable_moment": "Every string interpolation boundary is a trust boundary",
      "connection": "Defense in depth — validate at every layer, not just the edge",
      "praise": false
    },
    {
      "id": "praise-1",
      "title": "Excellent separation of state management from orchestration",
      "severity": "PRAISE",
      "category": "architecture",
      "file": ".claude/scripts/bridge-state.sh",
      "description": "State transitions are validated in a dedicated library",
      "suggestion": "",
      "potential": "",
      "weight": 0,
      "faang_parallel": "Google's Zanzibar separates policy from mechanism",
      "metaphor": "",
      "teachable_moment": "When state logic lives in one place, every consumer gets it right",
      "connection": "Single Responsibility Principle at the module level",
      "praise": true
    }
  ],
  "total": 2,
  "by_severity": {
    "critical": 1, "high": 0, "medium": 0,
    "low": 0, "vision": 0, "praise": 1
  },
  "severity_weighted_score": 10
}
```

#### 3.2.5 Backward Compatibility

The parser supports BOTH formats:

1. **New format (JSON fenced block)**: Preferred. Extracted as JSON, validated, enriched.
2. **Legacy format (markdown fields)**: If no valid JSON is found in the extracted block, falls back to the existing regex-based parser. This ensures cycle-005 review output still parses correctly.

Detection logic:
```bash
block=$(extract_findings_block "$INPUT_FILE")
if echo "$block" | grep -q '```json'; then
  # New format: extract JSON
  findings=$(extract_and_validate_json "$block")
else
  # Legacy format: regex parsing
  findings=$(parse_findings_legacy "$block")
fi
```

The legacy `parse_findings_legacy()` is the renamed current `parse_findings()` — unchanged.

#### 3.2.6 Aggregation (unchanged logic, new fields)

Severity weights, `by_severity` counts, and `severity_weighted_score` are computed from the findings array regardless of input format. The new `praise` count is added to `by_severity`. PRAISE weight = 0 means convergence math is identical.

### 3.3 Run-Bridge SKILL.md Extension

The SKILL.md gains a new section for enriched review handling.

**New Section: Enriched Bridgebuilder Review**

```markdown
### Phase 3.1: Enriched Bridgebuilder Review (when persona_enabled)

When the `BRIDGEBUILDER_REVIEW:N` signal is received and
`run_bridge.bridgebuilder.persona_enabled` is true:

1. **Verify Persona Integrity** (SKP-003): Compare persona file hash
   against base branch. If modified in PR, use base branch version.
2. **Validate Persona Content** (IMP-001): Check required sections
   exist. On failure: disable persona, log WARNING, continue.
3. **Load Lore**: Read relevant entries from `.claude/data/lore/`
   (if `run_bridge.lore.enabled` is true)
4. **Embody Persona**: The reviewing agent adopts the Bridgebuilder
   identity — voice, teaching style, FAANG parallels when confident,
   metaphors when illuminating, PRAISE when warranted
5. **Generate Dual-Stream Review**: Produce a single markdown document
   containing:
   - Rich educational prose (opening, meditations, closing)
   - JSON fenced block between `<!-- bridge-findings-start/end -->` markers
   - Educational fields in each finding JSON object
   - PRAISE findings when genuinely warranted (soft guidance, not quota)
6. **Save Review**: Write full markdown to `.run/bridge-review-{iteration}.md`
7. **Validate Size** (SKP-001): Check total size before posting:
   - < 65KB: post as-is
   - 65KB-256KB: truncate insights prose, preserve findings JSON
   - > 256KB: post findings JSON block only
8. **Redact Security Content** (SKP-005): For security-category findings,
   strip exploit details, secrets, and high-entropy strings from insights
9. **Parse Findings**: Run `bridge-findings-parser.sh` to extract stream 1
10. **Post to GitHub**: Run `bridge-github-trail.sh comment` with processed markdown

When `persona_enabled` is false, the existing behavior applies.
```

### 3.4 Bridge State Extension (`bridge-state.sh`)

#### 3.4.1 Atomic State Updates (Flatline IMP-004)

All read-modify-write operations on `bridge-state.json` use `flock` to prevent lost-update races:

```bash
atomic_state_update() {
  local state_file="$1"
  local jq_filter="$2"

  (
    flock -x 200
    jq "$jq_filter" "$state_file" > "$state_file.tmp"
    mv "$state_file.tmp" "$state_file"
  ) 200>"$state_file.lock"
}
```

This replaces the existing pattern of `jq ... > file.tmp && mv file.tmp file` throughout `bridge-state.sh`. The lock file (`bridge-state.json.lock`) is created alongside the state file.

**Functions to update:**
- `update_bridge_state()` — state transitions
- `update_iteration()` — iteration append/update
- `update_iteration_findings()` — findings data
- `update_flatline()` — flatline tracking
- `update_metrics()` — metric accumulation

#### 3.4.2 `last_score` Fix (Seed Finding HIGH-2)

The `update_flatline()` function must write `last_score`:

```bash
update_flatline() {
  local current_score="$1"
  # ... existing initial_score logic ...

  # ALWAYS write last_score
  atomic_state_update "$BRIDGE_STATE_FILE" \
    --argjson score "$current_score" '.flatline.last_score = $score'

  # ... rest of flatline check logic ...
}
```

#### 3.4.3 Praise in by_severity

The `update_iteration_findings()` function already passes through the parsed JSON. Since the parser now includes `praise` in `by_severity`, the state file automatically includes it. No code changes needed — verified by pass-through behavior.

### 3.5 GitHub Trail Extension (`bridge-github-trail.sh`)

#### 3.5.1 Size Enforcement (Flatline SKP-001)

Add size validation before posting PR comments:

```bash
# In cmd_comment, after building body:
local body_size=${#body}

if [[ $body_size -gt 262144 ]]; then  # 256KB
  echo "WARNING: Review exceeds 256KB ($body_size bytes) — posting findings only" >&2
  # Extract only the findings JSON block
  body=$(echo "$body" | sed -n '/bridge-findings-start/,/bridge-findings-end/p')
  body="${marker}
## Bridge Review — Iteration ${iteration} (findings only — full review exceeded size limit)

${body}

---
*Bridge iteration ${iteration} of ${bridge_id}*"
elif [[ $body_size -gt 65536 ]]; then  # 65KB
  echo "WARNING: Review exceeds 65KB ($body_size bytes) — truncating prose" >&2
  # Truncate to first 60KB, preserving the findings block
  body="${body:0:61440}

...

*[Review truncated — exceeded 65KB. Full review saved to .run/bridge-review-${iteration}.md]*"
fi
```

**Full review persisted**: Regardless of truncation, the full review is always saved to `.run/bridge-review-{iteration}.md` for local access.

#### 3.5.2 Content Redaction (Flatline SKP-005)

Before posting, strip high-entropy strings and explicit security content from the insights prose (content outside the findings markers):

```bash
redact_security_content() {
  local content="$1"

  # Strip high-entropy strings (likely secrets/tokens) — 32+ hex or base64 chars
  content=$(echo "$content" | sed -E 's/[A-Za-z0-9+/=]{32,}/[REDACTED]/g')

  # Strip common secret patterns
  content=$(echo "$content" | sed -E 's/(api[_-]?key|token|secret|password|credential)[[:space:]]*[:=][[:space:]]*[^\s]+/\1=[REDACTED]/gi')

  echo "$content"
}
```

This applies only to the insights prose (outside markers), not to the findings JSON block.

#### 3.5.3 Seed Fixes

**Seed HIGH-3 (heredoc injection in `cmd_vision`):** Replace heredoc with printf.

**Seed MEDIUM-7 (echo escape sequences):** Replace `echo "$body"` with `printf '%s' "$body"` in `cmd_comment`.

### 3.6 Vision Capture Fix (`bridge-vision-capture.sh`)

**Seed MEDIUM-1:** Replace pipe-to-while with process substitution:

```bash
while IFS= read -r vision; do
  vision_count=$((vision_count + 1))
  # ...
done < <(jq -c '.findings[] | select(.severity == "VISION")' "$FINDINGS_FILE")
```

### 3.7 Configuration Extension

```yaml
run_bridge:
  enabled: true
  defaults:
    depth: 5
    per_sprint: false
    flatline_threshold: 0.05
    consecutive_flatline: 2
  # NEW: Bridgebuilder persona enrichment
  bridgebuilder:
    persona_enabled: true          # Load Bridgebuilder persona for reviews
    enriched_findings: true        # Extract educational fields from findings
    insights_stream: true          # Post full review (not just findings) to PR
    praise_findings: true          # Enable PRAISE severity in reviews
    integrity_check: true          # Verify persona hash against base branch
    token_budget:
      findings: 5000               # Max tokens for findings stream
      insights: 25000              # Max tokens for insights stream
    size_limits:
      truncate_bytes: 65536        # Truncate insights above this (64KB)
      fallback_bytes: 262144       # Findings-only above this (256KB)
    redaction:
      enabled: true                # Redact secrets from insights stream
      security_findings: "summary" # "summary" (abstract) or "full" (include)
  timeouts:
    per_iteration_hours: 4
    total_hours: 24
  github_trail:
    post_comments: true
    update_pr_body: true
  ground_truth:
    enabled: true
  vision_registry:
    enabled: true
    auto_capture: true
  rtfm:
    enabled: true
    max_fix_iterations: 1
  lore:
    enabled: true
    categories:
      - mibera
      - neuromancer
```

### 3.8 Enrichment Metrics (Flatline IMP-010)

Add minimal metrics to track enrichment quality over time. Stored in the bridge state file per iteration:

```json
{
  "iterations": [{
    "enrichment": {
      "persona_loaded": true,
      "persona_validation": "passed",
      "findings_format": "json",
      "field_fill_rates": {
        "faang_parallel": 0.6,
        "metaphor": 0.4,
        "teachable_moment": 0.8,
        "connection": 0.5,
        "praise": 0.2
      },
      "praise_count": 2,
      "insights_size_bytes": 18500,
      "redactions_applied": 1
    }
  }]
}
```

These metrics are informational — they do not gate convergence. They enable post-hoc analysis of enrichment quality and can inform future persona tuning.

### 3.9 Seed Findings — Specific Fixes

The 13 seed findings from late-arriving iteration-1 review agents:

| # | Priority | Finding | Fix Location | Fix Description |
|---|----------|---------|-------------|-----------------|
| 1 | CRITICAL | `sprint_plan_source` field mismatch | `bridge-github-trail.sh` | Verified correct — add clarifying comment |
| 2 | HIGH | `last_score` never written | `bridge-state.sh` | Add `last_score` write in `update_flatline()` |
| 3 | HIGH | Unquoted heredoc injection | `bridge-github-trail.sh` | Replace heredoc with printf |
| 4 | HIGH | Missing constraint categories | `constraints.json` | Add `bridge` and `eval` to enum |
| 5 | HIGH | Missing constraint render target | `CLAUDE.loa.md` | Add `@constraint-generated: bridge` |
| 6 | MEDIUM | Pipe-to-while subshell scope | `bridge-vision-capture.sh` | Use `< <(...)` process substitution |
| 7 | MEDIUM | `echo -e` escape sequences | `bridge-github-trail.sh` | Replace with `printf '%s'` |
| 8 | MEDIUM | Broken lore cross-references | `.claude/data/lore/*.yaml` | Fix `related:` field references |
| 9 | MEDIUM | Three-Zone missing `.run/` | `CLAUDE.loa.md` | Add `.run/` to state zone |
| 10 | MEDIUM | Stale integrity hash | `CLAUDE.loa.md` | Recompute after all changes |
| 11 | LOW | Missing danger level entry | `CLAUDE.loa.md` | Add `run-bridge` to `high` list |
| 12 | LOW | Multiline description truncation | `bridge-findings-parser.sh` | Handled by JSON format (SKP-002) |
| 13 | LOW | Missing HALTED in state diagram | `CLAUDE.loa.md` | Add HALTED transition arrows |

**Note on Seed #12**: The multiline description truncation issue is fully resolved by the JSON fenced block redesign (SKP-002). JSON naturally handles multiline strings via escaping. The legacy regex parser retains the original behavior for backward compatibility only.

---

## 4. Dual-Stream Design

### 4.1 Single Pass, Two Outputs

Both streams come from the same review pass. The reviewing agent produces one markdown document containing rich prose AND a JSON findings block.

```
┌─────────────────────────────────────────────────────┐
│           Single Review Markdown Document              │
│                                                        │
│  ┌─ INSIGHTS STREAM (everything) ────────────────┐    │
│  │                                                 │    │
│  │  [Opening framing...]                          │    │
│  │  [Per-finding educational prose...]            │    │
│  │                                                 │    │
│  │  ┌─ FINDINGS STREAM (JSON between markers) ─┐  │    │
│  │  │  <!-- bridge-findings-start -->           │  │    │
│  │  │  ```json                                  │  │    │
│  │  │  { "schema_version": 1,                   │  │    │
│  │  │    "findings": [...] }                    │  │    │
│  │  │  ```                                      │  │    │
│  │  │  <!-- bridge-findings-end -->             │  │    │
│  │  └──────────────────────────────────────────┘  │    │
│  │                                                 │    │
│  │  [Architectural meditation...]                 │    │
│  │  [Closing signature...]                        │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘
         │
         ├──── SIZE CHECK (SKP-001) ──── REDACT (SKP-005) ────┐
         │                                                       │
         ▼                                                       ▼
   bridge-findings-parser.sh                            bridge-github-trail.sh
   extracts JSON, validates,                           posts processed markdown
   computes aggregates                                 as PR comment
```

### 4.2 Parser Reliability (Flatline SKP-002)

The JSON fenced block inside markers is **machine-generated by the LLM and machine-parsed by the script**. This is fundamentally more reliable than regex parsing of markdown because:

1. **JSON validation**: `jq empty` catches any formatting error immediately
2. **No regex fragility**: No dependence on exact whitespace, bold markers, or field ordering
3. **Multiline fields**: JSON handles via standard string escaping
4. **Strict failure modes**: Invalid JSON → reject iteration with clear error → retry or skip
5. **Schema evolution**: `schema_version` field enables forward-compatible changes

The human-readable prose outside the markers has no structural requirements — it's free-form markdown that the trail script posts as-is (after size and redaction checks).

### 4.3 Stream Routing

| Stream | Consumer | Purpose | Format |
|--------|----------|---------|--------|
| Findings (1) | Flatline detection | Convergence scoring | JSON (from parser) |
| Findings (1) | Sprint plan generator | Task creation for next iteration | JSON (from parser) |
| Findings (1) | Vision capture | VISION/PRAISE extraction | JSON (from parser) |
| Findings (1) | Enrichment metrics | Field fill rate calculation | JSON (from parser) |
| Insights (2) | GitHub PR comment | Human education | Markdown (size-enforced, redacted) |
| Insights (2) | Local artifact | Full review backup | Markdown (untruncated) |

### 4.4 Convergence Isolation

PRAISE and educational fields MUST NOT affect convergence:

- PRAISE weight = 0 → not counted in `severity_weighted_score`
- Educational fields → informational, not used by flatline detection
- Sprint plan generator only creates tasks from findings with weight > 0
- The score trajectory remains unchanged

---

## 5. Constraint Amendments

### 5.1 New Constraints

| ID | Name | Type | Category | Text |
|----|------|------|----------|------|
| C-BRIDGE-006 | `bridge_persona_for_reviews` | ALWAYS | bridge | ALWAYS load and verify Bridgebuilder persona from `.claude/data/bridgebuilder-persona.md` when `run_bridge.bridgebuilder.persona_enabled` is true |
| C-BRIDGE-007 | `bridge_praise_quality` | SHOULD | bridge | SHOULD include PRAISE findings when genuinely warranted — quality over quantity, no forced filler |
| C-BRIDGE-008 | `bridge_educational_fields` | SHOULD | bridge | SHOULD include `faang_parallel` and `teachable_moment` when confident in the parallel and when the lesson is genuine |

**Note (Flatline SKP-004):** C-BRIDGE-007 and C-BRIDGE-008 are SHOULD (soft guidance), not ALWAYS (hard requirement). This prevents perverse incentives that would produce filler content and hallucinated parallels.

### 5.2 Category Fix

Add `bridge` and `eval` to the category enum in `constraints.json`.

### 5.3 Render Target Fix

Add `@constraint-generated: bridge` render target to `CLAUDE.loa.md`.

---

## 6. Error Handling

### 6.1 Error Taxonomy

| Error | Severity | Recovery |
|-------|----------|----------|
| Persona file not found | Medium | Disable persona, log WARNING, continue |
| Persona validation failed (IMP-001) | Medium | Disable persona, log WARNING, continue |
| Persona integrity check failed (SKP-003) | Medium | Use base-branch version, log WARNING |
| Findings JSON invalid (SKP-002) | High | Reject iteration findings, fall back to legacy parser |
| Findings schema_version unknown | Low | Treat as v1, log WARNING |
| Insights exceed 65KB (SKP-001) | Medium | Truncate prose, preserve findings JSON |
| Insights exceed 256KB (SKP-001) | High | Post findings-only, save full review locally |
| State file lock contention (IMP-004) | Low | Retry with backoff (flock timeout 5s) |
| PRAISE severity not recognized | Low | Falls back to weight 0 |
| Redaction false positive (SKP-005) | Low | Overstripping is safe — understripping is not |

### 6.2 Graceful Degradation

1. **No persona file**: Reviews proceed without persona identity
2. **Invalid findings JSON**: Falls back to legacy regex parser
3. **No enriched fields**: Parser outputs empty strings
4. **Size overflow**: Truncation or findings-only fallback
5. **Config disabled**: All new behavior behind config flags

---

## 7. Testing Strategy

### 7.1 Extended BATS Tests

#### bridge-findings-parser.bats (extend existing)

| Test | What It Tests |
|------|--------------|
| `parses JSON fenced block from enriched review` | New JSON extraction path |
| `falls back to legacy parsing for markdown format` | Backward compatibility |
| `validates JSON and rejects malformed input` | SKP-002 validation |
| `handles missing schema_version gracefully` | IMP-008 fallback |
| `all 5 enriched fields extracted from JSON` | Field extraction |
| `PRAISE severity has weight 0` | Convergence isolation |
| `PRAISE counted in by_severity` | Aggregate correctness |
| `mixed enriched and plain findings in JSON` | Partial enrichment |
| `ignores JSON-like content outside markers` | IMP-002 boundary |

#### bridge-state.bats (extend existing)

| Test | What It Tests |
|------|--------------|
| `update_flatline writes last_score` | Seed HIGH-2 fix |
| `by_severity includes praise count` | Pass-through verification |
| `concurrent state updates don't corrupt` | IMP-004 flock |

#### bridge-github-trail.bats (extend existing)

| Test | What It Tests |
|------|--------------|
| `truncates body exceeding 65KB` | SKP-001 size enforcement |
| `falls back to findings-only above 256KB` | SKP-001 fallback |
| `redacts high-entropy strings from insights` | SKP-005 redaction |
| `uses printf instead of echo` | Seed MEDIUM-7 fix |
| `cmd_vision uses safe string construction` | Seed HIGH-3 fix |

### 7.2 Test Fixtures

Create enriched review fixture with JSON findings block:

```markdown
# Bridgebuilder Review — Test Fixture

This is the opening framing prose...

<!-- bridge-findings-start -->
```json
{
  "schema_version": 1,
  "findings": [
    {
      "id": "high-1",
      "title": "Missing input validation",
      "severity": "HIGH",
      "category": "security",
      "file": "src/api/handler.ts:42",
      "description": "User input passed directly to database query",
      "suggestion": "Add zod schema validation",
      "potential": "",
      "weight": 5,
      "faang_parallel": "Equifax 2017 breach",
      "metaphor": "Like letting strangers walk through your house",
      "teachable_moment": "Validate at system boundaries",
      "connection": "Defense in depth — OWASP A03:2021",
      "praise": false
    },
    {
      "id": "praise-1",
      "title": "Excellent error boundary design",
      "severity": "PRAISE",
      "category": "architecture",
      "file": "src/core/error-boundary.ts",
      "description": "Error boundaries prevent cascading failures",
      "suggestion": "",
      "potential": "",
      "weight": 0,
      "faang_parallel": "Netflix Hystrix",
      "metaphor": "",
      "teachable_moment": "Containing blast radius > preventing all errors",
      "connection": "Bulkhead pattern",
      "praise": true
    }
  ]
}
```
<!-- bridge-findings-end -->

This is the closing meditation...
```

### 7.3 Integration Validation

- Run enriched parser on JSON fixture — verify all fields extracted
- Run enriched parser on cycle-005 markdown fixture — verify legacy fallback
- Verify `severity_weighted_score` excludes PRAISE (weight=0)
- Verify `by_severity` includes all 6 levels
- Verify size enforcement: create >65KB fixture, verify truncation
- Verify redaction: include high-entropy string in prose, verify stripped
- Verify persona integrity: modify persona on branch, verify base-branch fallback

---

## 8. Implementation Phases

### Phase 1: Seed Findings + Parser Redesign (Sprint 1)

**Deliverables:**
1. Fix all CRITICAL and HIGH seed findings (#1-5)
2. Fix MEDIUM seed findings (#6, 7, 8)
3. Redesign parser: JSON fenced block extraction with legacy fallback
4. Add `schema_version` to parser output (IMP-008)
5. Add PRAISE severity weight and `praise` to `by_severity`
6. Add `flock`-based atomic state updates (IMP-004)
7. Fix `update_flatline()` to write `last_score` (seed HIGH-2)
8. Extend parser BATS tests for JSON extraction + legacy fallback
9. Extend state BATS tests for flock + last_score
10. Fix LOW seed findings (#11, 13)
11. Update `CLAUDE.loa.md` (Three-Zone, danger level, state diagram)

### Phase 2: Persona + SKILL.md + Trail Hardening (Sprint 2)

**Deliverables:**
1. Create `.claude/data/bridgebuilder-persona.md` with all required sections
2. Add persona integrity verification (SKP-003)
3. Add persona content validation (IMP-001)
4. Extend `/run-bridge` SKILL.md with enriched review workflow
5. Add size enforcement to `bridge-github-trail.sh` (SKP-001)
6. Add content redaction to `bridge-github-trail.sh` (SKP-005)
7. Add new constraints (C-BRIDGE-006, 007, 008) — soft guidance
8. Add `bridge`/`eval` to constraint category enum
9. Add `bridgebuilder` section to config files
10. Extend trail BATS tests for size + redaction
11. Add enrichment metrics to bridge state (IMP-010)

### Phase 3: Validation + Integration (Sprint 3)

**Deliverables:**
1. Create enriched JSON test fixture
2. Run parser on fixture — validate all fields
3. Run parser on cycle-005 markdown — verify legacy fallback works
4. Verify convergence isolation (PRAISE weight=0)
5. Verify size enforcement (truncation + fallback)
6. Verify persona integrity check (base-branch hash)
7. Verify redaction (high-entropy strings stripped)
8. Update lore cross-references (seed #8)
9. Final CLAUDE.loa.md integrity hash
10. Version bump and CHANGELOG entry

---

## 9. Security Considerations

| Concern | Mitigation |
|---------|-----------|
| Persona prompt injection via PR (SKP-003) | Base-branch hash verification before loading persona |
| Heredoc injection in vision comments | Replace with printf-based construction |
| Echo escape sequence interpretation | Replace with `printf '%s'` |
| FAANG parallel hallucination (SKP-004) | Soft guidance: "only cite when confident", no quotas |
| Token budget overflow (SKP-001) | Hard size enforcement: truncate at 65KB, findings-only at 256KB |
| Secret leakage in PR comments (SKP-005) | Content redaction: strip high-entropy strings, abstract security findings |
| State file corruption from concurrent writes (IMP-004) | `flock` for all read-modify-write operations |
| Findings parsing failure (SKP-002) | JSON validation with legacy fallback |

---

## 10. Risk Mitigation

| Risk (from PRD) | Architectural Mitigation |
|-----------------|-------------------------|
| Token cost increase per iteration | Configurable budgets; hard size limits prevent runaway posting |
| Persona drift (formulaic reviews) | Diverse voice examples; soft guidance prevents forced filler |
| FAANG parallels become inaccurate | Soft guidance: "only cite when confident"; no quota pressure |
| Enriched fields slow parser | JSON extraction is faster than regex; fields are in-memory |
| Dual-stream confuses sprint plan | Sprint plan only sees findings JSON; PRAISE weight=0 |
| Convergence regression | PRAISE weight=0 + enriched fields informational = identical math |
| Insights leak sensitive data | Content redaction + security-findings abstraction |
| Parser breaks on LLM formatting drift | JSON fenced block is structurally robust; legacy fallback |

---

## Next Step

After SDD approval: `/sprint-plan` to create sprint plan with task breakdown for Phases 1-3.
