# SDD: Bridgebuilder Constellation — From Pipeline to Deliberation

> **Cycle**: 046
> **Created**: 2026-02-28
> **PRD**: `grimoires/loa/prd.md`
> **Target**: `.claude/` System Zone (scripts, skills, data) + `.loa.config.yaml` + `grimoires/loa/lore/`

---

## 1. System Architecture

### 1.1 Component Map

```
┌─────────────────────────────────────────────────────────────┐
│                    Run Mode Loop                             │
│                                                             │
│  implement → review → audit → RED_TEAM_CODE → COMPLETE      │
│                │        │          │                          │
│                │        │          ▼                          │
│                │        │   --prior-findings  (NEW — FR-2)   │
│                │        │   ├── engineer-feedback.md          │
│                │        │   └── auditor-sprint-feedback.md    │
│                │        │                                    │
│                ▼        ▼                                    │
│         engineer-   auditor-                                 │
│         feedback    feedback                                 │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                 Pipeline Self-Review  (NEW — FR-3)           │
│                                                             │
│  bridge iteration start →                                    │
│    detect_pipeline_changes() →                               │
│      if .claude/ files changed:                              │
│        resolve_pipeline_sdd() →                              │
│        red-team-code-vs-design.sh \                          │
│          --sdd <pipeline-sdd> \                              │
│          --diff <pipeline-diff>                              │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│              Compliance Gate Profiles (NEW — FR-4)            │
│                                                             │
│  .loa.config.yaml:                                          │
│    compliance_gates:                                         │
│      security:                                               │
│        keywords: [Security, Auth*, Validation, ...]          │
│        prompt_template: security-comparison                  │
│      accessibility:  (future)                                │
│        keywords: [Accessibility, ARIA, ...]                  │
│        prompt_template: a11y-comparison                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 Data Flow: Deliberative Council

```
                 ┌──────────────┐
                 │   implement  │
                 └──────┬───────┘
                        │
                        ▼
                 ┌──────────────┐
                 │   /review    │──→ engineer-feedback.md
                 └──────┬───────┘
                        │
                        ▼
                 ┌──────────────┐
                 │   /audit     │──→ auditor-feedback.md
                 └──────┬───────┘
                        │
                        ▼
              ┌─────────────────────┐
              │ RED_TEAM_CODE gate  │
              │  --sdd <sdd-path>  │
              │  --diff <code>     │
              │  --prior-findings  │◄── engineer-feedback.md
              │    <feedback-path> │◄── auditor-feedback.md
              └─────────┬──────────┘
                        │
                        ▼
              Findings informed by
              ALL prior stage context
```

## 2. Detailed Design

### 2.1 FR-1: Code Quality Polish

Six surgical fixes, each isolated to a single file.

#### 2.1.1 JSON-Safe Encoding (flatline-orchestrator.sh)

**Before:**
```bash
--argjson tertiary_model "$(if [[ -n "${tertiary_model_output:-}" ]]; then printf '"%s"' "$tertiary_model_output"; else echo 'null'; fi)"
```

**After:**
```bash
--argjson tertiary_model "$(if [[ -n "${tertiary_model_output:-}" ]]; then jq -n --arg m "$tertiary_model_output" '$m'; else echo 'null'; fi)"
```

Rationale: `jq -n --arg` handles all JSON-special characters (quotes, backslashes, control chars). The `printf '"%s"'` pattern only works for strings without those characters.

#### 2.1.2 Redundant rm -f Removal (red-team-code-vs-design.sh)

Remove lines 313 and 316 (`rm -f "$prompt_file"`). The `trap 'rm -f "$prompt_file"' EXIT` on line 262 handles all exit paths.

#### 2.1.3 Stderr Capture on Failure (red-team-code-vs-design.sh)

**Pattern:**
```bash
local stderr_tmp
stderr_tmp=$(mktemp)
trap 'rm -f "$prompt_file" "$stderr_tmp"' EXIT

model_output=$("$MODEL_ADAPTER" ... 2>"$stderr_tmp") || exit_code=$?
if [[ $exit_code -ne 0 ]]; then
    local stderr_tail
    stderr_tail=$(tail -5 "$stderr_tmp" 2>/dev/null || echo "(no stderr)")
    error "Model invocation failed (exit $exit_code): $stderr_tail"
    exit 1
fi
```

Update the trap to clean both temp files.

#### 2.1.4 Robust Fence Stripping (red-team-code-vs-design.sh)

**Pattern:** Two-pass approach:
1. If output starts with `` ```json `` or `` ``` ``, extract content between fences using awk range pattern
2. Fallback to current sed for edge cases

```bash
strip_code_fences() {
    local input="$1"
    if echo "$input" | head -1 | grep -qE '^\s*```'; then
        echo "$input" | awk '/^\s*```/{if(f){exit}else{f=1;next}} f'
    else
        echo "$input"
    fi
}
```

#### 2.1.5 Version Tag Fix (simstim SKILL.md)

Replace `(v1.45.0)` with `(cycle-045)` on the line referencing the dynamic phase count computation.

#### 2.1.6 Hounfour Seam Comment (flatline-orchestrator.sh)

Add above `get_model_tertiary()`:
```bash
# Provisional resolution — will be replaced by Hounfour router capability
# query when ModelPort interface is available (see loa-finn #31).
# The function signature is the durable contract; the config lookup is temporary.
```

### 2.2 FR-2: Deliberative Council — Prior Findings Integration

#### 2.2.1 New Flag: --prior-findings

Add to red-team-code-vs-design.sh argument parsing:

```bash
--prior-findings)
    shift
    prior_findings_path="$1"
    ;;
```

Multiple paths supported via repeated `--prior-findings` flags or comma-separated.

#### 2.2.2 Token Budget Rebalancing

When `--prior-findings` is provided, rebalance the token budget:

| Component | Without prior findings | With prior findings |
|-----------|----------------------|---------------------|
| SDD sections | 50% | 33% |
| Code diff | 50% | 33% |
| Prior findings | 0% | 33% |

Implementation: `max_section_chars = token_budget * 4 / N` where N is the number of active input channels.

#### 2.2.3 Prior Findings Extraction

Read each prior findings file and extract a summary:
```bash
extract_prior_findings() {
    local path="$1"
    local max_chars="$2"

    if [[ ! -f "$path" ]]; then
        return
    fi

    # Extract findings sections (## Findings, ## Issues, ## Changes Required)
    local content
    content=$(grep -A 100 "## Findings\|## Issues\|## Changes Required\|## Security" "$path" | head -c "$max_chars")

    echo "$content"
}
```

#### 2.2.4 Prompt Integration

Insert prior findings into the model prompt between the SDD sections and code diff:

```
=== PRIOR REVIEW FINDINGS ===
The following findings were identified by earlier review stages. Use these
to focus your design compliance analysis on areas already flagged as concerns.

[prior findings content]

=== CODE DIFF ===
[code diff content]
```

#### 2.2.5 Run Mode SKILL.md Wiring

Update step 7 (RED_TEAM_CODE gate) to pass prior findings:

```bash
.claude/scripts/red-team-code-vs-design.sh \
    --sdd grimoires/loa/sdd.md \
    --diff - \
    --prior-findings grimoires/loa/a2a/sprint-{N}/engineer-feedback.md \
    --prior-findings grimoires/loa/a2a/sprint-{N}/auditor-sprint-feedback.md \
    --output grimoires/loa/a2a/sprint-{N}/red-team-code-findings.json \
    --sprint sprint-{N}
```

### 2.3 FR-3: Pipeline Self-Review

#### 2.3.1 Pipeline Change Detection

Function in bridge-orchestrator.sh:

```bash
detect_pipeline_changes() {
    local base_branch="${1:-main}"
    local pipeline_files
    pipeline_files=$(git diff --name-only "$base_branch"...HEAD -- \
        '.claude/scripts/' \
        '.claude/skills/' \
        '.claude/data/' \
        '.claude/protocols/' \
        2>/dev/null || echo "")

    if [[ -n "$pipeline_files" ]]; then
        echo "$pipeline_files"
        return 0
    fi
    return 1
}
```

#### 2.3.2 Pipeline SDD Mapping

Static mapping of pipeline scripts to their governing specifications:

```bash
# .claude/data/pipeline-sdd-map.json
{
    "patterns": [
        {
            "glob": ".claude/scripts/flatline-*.sh",
            "sdd": ".claude/skills/flatline-review/SKILL.md",
            "sections": ["Protocol", "Phases", "Scoring", "Consensus"]
        },
        {
            "glob": ".claude/scripts/red-team-*.sh",
            "sdd": ".claude/skills/red-team/SKILL.md",
            "sections": ["Architecture", "Security", "Input", "Output"]
        },
        {
            "glob": ".claude/scripts/bridge-*.sh",
            "sdd": ".claude/skills/run-bridge/SKILL.md",
            "sections": ["Workflow", "Review", "Findings", "State"]
        },
        {
            "glob": ".claude/scripts/simstim-*.sh",
            "sdd": ".claude/skills/simstim-workflow/SKILL.md",
            "sections": ["Phases", "State", "Flatline", "Resume"]
        }
    ]
}
```

#### 2.3.3 Self-Review Trigger in Bridge Orchestrator

Add as optional phase in bridge-orchestrator.sh, before the standard Bridgebuilder review:

```bash
if [[ "$(read_config '.run_bridge.pipeline_self_review.enabled' 'false')" == "true" ]]; then
    local pipeline_changes
    if pipeline_changes=$(detect_pipeline_changes); then
        log "Pipeline changes detected — running self-review"
        run_pipeline_self_review "$pipeline_changes"
    fi
fi
```

The self-review produces findings in the same schema as code-vs-design findings, posted as a separate PR comment section.

### 2.4 FR-4: Governance Isomorphism Lore + Compliance Generalization

#### 2.4.1 Lore Entry

Create `grimoires/loa/lore/patterns.yaml` entry:

```yaml
- id: governance-isomorphism
  term: Governance Isomorphism
  short: "Governed access to scarce resources through multi-perspective evaluation with fail-closed semantics"
  context: |
    The structural pattern that recurs across economic, knowledge, review, and social
    governance in the THJ stack. Instances: loa-freeside conservation invariant
    (committed + reserved + available = limit), loa-dixie ResourceGovernor<T>,
    loa-hounfour evaluateEconomicBoundary(), loa review pipeline
    (review + audit + red-team). Conway's Law operating at the protocol level.
  source: "bridge-20260228-170473 deep-review / PR #429"
  tags: [architecture, governance, cross-repo, pattern]
```

#### 2.4.2 Compliance Gate Config Schema

```yaml
# .loa.config.yaml addition
red_team:
  compliance_gates:
    security:
      enabled: true
      keywords:
        - Security
        - Authentication
        - Authorization
        - Validation
        - "Error.Handling"
        - "Access.Control"
        - Secrets
        - Encryption
        - "Input.Sanitiz"
      prompt_template: "security-comparison"
    # Future gates can be added:
    # accessibility:
    #   enabled: false
    #   keywords: [Accessibility, ARIA, "Screen.Reader", ...]
    #   prompt_template: "a11y-comparison"
```

#### 2.4.3 Parameterized Header Keywords

Modify `extract_security_sections()` to accept keywords as parameter:

```bash
extract_sections_by_keywords() {
    local sdd_path="$1"
    local max_chars="$2"
    local keywords="$3"  # pipe-separated: "Security|Auth|..."

    # Same logic as current extract_security_sections()
    # but with parameterized regex
    local header_pattern="^#{1,3}\s.*(${keywords})"
    ...
}
```

Default keywords loaded from config, falling back to current hardcoded list.

## 3. Security Considerations

- Prior findings may contain security-sensitive information — apply the same redaction rules as bridge review content
- Pipeline SDD mapping is a static file in `.claude/data/` — changes require System Zone access (lead-only)
- Compliance gate profiles should not be modifiable by teammates in Agent Teams mode

## 4. Testing Strategy

| Test | Type | Validates |
|------|------|-----------|
| JSON encoding safety | Unit (bash) | FR-1.1: jq -n --arg handles special chars |
| --prior-findings flag | Integration | FR-2.1: flag parsed, content included in prompt |
| Token budget rebalancing | Unit | FR-2.2: 3-way split when prior findings present |
| Pipeline change detection | Unit | FR-3.1: detects .claude/ file changes |
| Compliance gate keywords from config | Unit | FR-4.2: config keywords override defaults |
