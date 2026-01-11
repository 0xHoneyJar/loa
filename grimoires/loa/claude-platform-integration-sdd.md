# Software Design Document: Claude Platform Integration

**Version:** 1.0.0
**Status:** Ready for Sprint Planning
**Date:** 2026-01-11
**Author:** Architecture Designer Agent

---

## Document Information

| Field | Value |
|-------|-------|
| PRD Reference | `grimoires/loa/claude-platform-integration-prd.md` v1.0.0 |
| Architecture Pattern | Adapter Pattern with Runtime Generation |
| Primary Language | Bash (POSIX-compatible), JSON Schema |
| Target Platforms | Linux (GNU), macOS (BSD), Claude Code, claude.ai, Claude API |

---

## 1. Executive Summary

This document describes the technical architecture for integrating Loa with Claude's platform features: Agent Skills, Structured Outputs, Extended Thinking, Tool Search, and Context Management.

**Key Design Decisions:**

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Skill Format | Hybrid (runtime generation) | No migration, preserve Loa-specific metadata |
| Schema Location | `.claude/schemas/` | Centralized, framework-owned, CI/CD friendly |
| Thinking Traces | Trajectory logging | Consistent with existing audit system |
| Tool Search | Adapter over MCP registry | Leverage existing infrastructure |
| Context Compaction | Protocol extension | Integrate with Lossless Ledger |

> **Sources**: claude-platform-integration-prd.md:124-172, Architecture Q1-Q3

---

## 2. System Architecture

### 2.1 High-Level Component Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Loa Framework v0.11.0                              │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                     Claude Platform Adapter Layer                      │   │
│  │                                                                        │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │   │
│  │  │ Skills      │  │ Schema      │  │ Thinking    │  │ Tool Search │  │   │
│  │  │ Adapter     │  │ Validator   │  │ Logger      │  │ Adapter     │  │   │
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  │   │
│  └─────────│────────────────│────────────────│────────────────│─────────┘   │
│            │                │                │                │              │
│            ▼                ▼                ▼                ▼              │
│  ┌─────────────────┐ ┌─────────────┐ ┌─────────────────┐ ┌─────────────┐    │
│  │ .claude/skills/ │ │ .claude/    │ │ grimoires/loa/   │ │ .claude/    │    │
│  │ (index.yaml +   │ │ schemas/    │ │ a2a/trajectory/ │ │ mcp-registry│    │
│  │  SKILL.md)      │ │ (JSON)      │ │ (JSONL)         │ │ .yaml       │    │
│  └─────────────────┘ └─────────────┘ └─────────────────┘ └─────────────┘    │
│                                                                              │
└───────────────────────────────────────────────│──────────────────────────────┘
                                                │
                                                │ Claude API
                                                ▼
                                    ┌─────────────────────┐
                                    │   Claude Platform   │
                                    │  - Agent Skills API │
                                    │  - Structured Out   │
                                    │  - Extended Think   │
                                    │  - Tool Search      │
                                    └─────────────────────┘
```

### 2.2 Component Responsibilities

| Component | Responsibility | New/Existing |
|-----------|---------------|--------------|
| **Skills Adapter** | Generates Claude Agent Skills format from index.yaml | NEW |
| **Schema Validator** | Validates outputs against JSON schemas | NEW |
| **Thinking Logger** | Logs extended thinking traces to trajectory | NEW |
| **Tool Search Adapter** | Bridges Claude tool search with MCP registry | NEW |
| **Context Manager** | Integrates client-side compaction with Lossless Ledger | NEW (extension) |

> **Sources**: PRD:124-280

### 2.3 Data Flow: Agent Skills Generation

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                     Agent Skills Format Generation                            │
└──────────────────────────────────────────────────────────────────────────────┘

1. Skill Invocation (e.g., /plan-and-analyze)
   │
   ▼
2. Read index.yaml (Loa-native format)
   │  name, version, description, triggers, examples, protocols...
   │
   ▼
3. Skills Adapter transforms to Claude Agent Skills format
   │  - Extract: name, description, triggers
   │  - Generate: YAML frontmatter block
   │  - Preserve: SKILL.md body unchanged
   │
   ▼
4. Output: Virtual SKILL.md with frontmatter
   │
   │  ---
   │  name: "discovering-requirements"
   │  description: "Product Manager agent..."
   │  version: "2.0.0"
   │  triggers:
   │    - "/plan-and-analyze"
   │    - "create PRD"
   │  ---
   │  [Original SKILL.md content]
   │
   ▼
5. Claude processes as Agent Skill
   - Level 1: Frontmatter (~100 tokens, always loaded)
   - Level 2: SKILL.md body (~2-5k tokens, on trigger)
   - Level 3: resources/ (on-demand)
```

---

## 3. Technology Stack

### 3.1 Languages & Tools

| Layer | Technology | Justification |
|-------|------------|---------------|
| Scripts | Bash (POSIX) | Consistent with existing Loa scripts |
| Schemas | JSON Schema Draft-07 | Industry standard, Claude compatible |
| Config | YAML | Consistent with .loa.config.yaml |
| Logging | JSONL | Consistent with trajectory format |

### 3.2 Dependencies

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| `yq` | 4.x | YAML parsing (existing) | Yes |
| `jq` | 1.6+ | JSON processing (existing) | Yes |
| `ajv-cli` | 5.x | JSON Schema validation | Optional (fallback to jq) |

> **Sources**: Existing script dependencies

---

## 4. Component Design

### 4.1 Skills Adapter

**Purpose**: Transform Loa's index.yaml + SKILL.md format into Claude Agent Skills format at runtime.

**Location**: `.claude/scripts/skills-adapter.sh`

#### 4.1.1 Interface

```bash
# Generate Claude Agent Skills frontmatter for a skill
skills-adapter.sh generate <skill-name>

# List all skills in Claude Agent Skills format
skills-adapter.sh list

# Upload skill to Claude API workspace
skills-adapter.sh upload <skill-name>

# Sync all skills with Claude API
skills-adapter.sh sync
```

#### 4.1.2 Mapping: index.yaml → Agent Skills Frontmatter

| index.yaml Field | Agent Skills Field | Transformation |
|------------------|-------------------|----------------|
| `name` | `name` | Direct copy |
| `description` | `description` | First line or full |
| `version` | `version` | Direct copy |
| `triggers` | `triggers` | Direct copy as array |
| `model` | (not mapped) | Loa-specific |
| `protocols` | (not mapped) | Loa-specific |
| `parallel_execution` | (not mapped) | Loa-specific |
| `inputs` | (not mapped) | Loa-specific |
| `outputs` | (not mapped) | Loa-specific |

#### 4.1.3 Generation Algorithm

```bash
generate_frontmatter() {
    local skill_dir="$1"
    local index_yaml="${skill_dir}/index.yaml"
    local skill_md="${skill_dir}/SKILL.md"

    # Extract fields from index.yaml
    local name=$(yq -r '.name' "$index_yaml")
    local version=$(yq -r '.version' "$index_yaml")
    local description=$(yq -r '.description' "$index_yaml" | head -1)
    local triggers=$(yq -r '.triggers | @json' "$index_yaml")

    # Generate frontmatter
    cat <<EOF
---
name: "${name}"
description: "${description}"
version: "${version}"
triggers: ${triggers}
---

EOF

    # Append original SKILL.md content
    cat "$skill_md"
}
```

#### 4.1.4 API Upload Interface

```bash
# Upload requires Claude API credentials
upload_skill() {
    local skill_name="$1"
    local api_key="${CLAUDE_API_KEY:-}"

    if [ -z "$api_key" ]; then
        echo "ERROR: CLAUDE_API_KEY not set" >&2
        exit 1
    fi

    # Generate combined content
    local content=$(generate_frontmatter ".claude/skills/${skill_name}")

    # Upload via Claude Skills API
    curl -X POST "https://api.anthropic.com/v1/skills" \
        -H "x-api-key: ${api_key}" \
        -H "anthropic-version: 2024-01-01" \
        -H "content-type: application/json" \
        -d "{\"name\":\"${skill_name}\",\"content\":$(echo "$content" | jq -Rs .)}"
}
```

### 4.2 Schema Validator

**Purpose**: Validate agent outputs against JSON schemas before writing to State Zone.

**Location**: `.claude/scripts/schema-validator.sh`

#### 4.2.1 Interface

```bash
# Validate a file against its schema
schema-validator.sh validate <file> [--schema <schema>]

# Validate with specific mode (strict/warn/disabled)
schema-validator.sh validate <file> --mode warn

# List available schemas
schema-validator.sh list
```

#### 4.2.2 Schema Registry

| Output Type | Schema File | Validated By |
|-------------|-------------|--------------|
| PRD | `.claude/schemas/prd.schema.json` | `/plan-and-analyze` |
| SDD | `.claude/schemas/sdd.schema.json` | `/architect` |
| Sprint | `.claude/schemas/sprint.schema.json` | `/sprint-plan` |
| Audit Report | `.claude/schemas/audit-report.schema.json` | `/audit-sprint` |
| Trajectory Entry | `.claude/schemas/trajectory-entry.schema.json` | All agents |

#### 4.2.3 Validation Modes

| Mode | Behavior | Exit Code |
|------|----------|-----------|
| `strict` | Fail on any violation | 1 on error |
| `warn` | Log warnings, continue | 0 with warnings |
| `disabled` | Skip validation | 0 |

#### 4.2.4 Integration with Commands

```bash
# In command implementation
if [ "$VALIDATE_SCHEMA" = "true" ]; then
    schema-validator.sh validate "$OUTPUT_FILE" --mode "${VALIDATION_MODE:-warn}"
fi
```

### 4.3 Thinking Logger

**Purpose**: Capture and log extended thinking traces for audit trails.

**Location**: `.claude/scripts/thinking-logger.sh`

#### 4.3.1 Interface

```bash
# Log thinking trace for an agent action
thinking-logger.sh log <agent> <action> <trace>

# Query thinking traces
thinking-logger.sh query --agent <agent> --since <timestamp>
```

#### 4.3.2 Trajectory Entry Format

```jsonl
{
  "ts": "2026-01-11T15:30:00Z",
  "agent": "auditing-security",
  "phase": "extended_thinking",
  "action": "vulnerability_assessment",
  "thinking_trace": {
    "steps": [
      {"thought": "Examining input validation in auth module..."},
      {"thought": "Checking for SQL injection vectors..."},
      {"conclusion": "No SQL injection found, uses parameterized queries"}
    ],
    "duration_ms": 2500,
    "token_count": 850
  },
  "grounding": {
    "type": "code_reference",
    "refs": ["${PROJECT_ROOT}/src/auth/validate.ts:45-67"]
  }
}
```

#### 4.3.3 Integration with Extended Thinking Agents

```yaml
# In skill index.yaml
extended_thinking:
  enabled: true
  log_to_trajectory: true
  max_tokens: 5000
```

### 4.4 Tool Search Adapter

**Purpose**: Bridge Claude's tool search with Loa's MCP registry.

**Location**: `.claude/scripts/tool-search-adapter.sh`

#### 4.4.1 Interface

```bash
# Search for tools matching query
tool-search-adapter.sh search <query>

# Auto-discover available tools
tool-search-adapter.sh discover

# Cache management
tool-search-adapter.sh cache list
tool-search-adapter.sh cache clear
```

#### 4.4.2 Discovery Flow

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        Tool Discovery Flow                                    │
└──────────────────────────────────────────────────────────────────────────────┘

1. Claude issues tool search query
   │
   ▼
2. Tool Search Adapter receives query
   │
   ▼
3. Check cache (TTL: 24 hours)
   │
   ├─ Cache hit → Return cached results
   │
   └─ Cache miss → Continue
       │
       ▼
4. Query MCP Registry (.claude/mcp-registry.yaml)
   │
   ├─ Match by name
   ├─ Match by description
   └─ Match by scopes
       │
       ▼
5. Query Loa Constructs (if enabled)
   │
   └─ Check .claude/constructs/ for registry skills with tools
       │
       ▼
6. Combine and deduplicate results
   │
   ▼
7. Cache results, return to Claude
```

#### 4.4.3 Cache Structure

```
~/.loa/cache/tool-search/
├── index.json           # Cache index with timestamps
├── queries/
│   ├── <hash>.json      # Cached query results
│   └── ...
└── mcp-servers/
    ├── <server>.json    # Cached server capabilities
    └── ...
```

### 4.5 Context Manager Extension

**Purpose**: Integrate client-side compaction with Lossless Ledger Protocol.

**Location**: `.claude/protocols/context-compaction.md` (protocol), `.claude/scripts/context-manager.sh` (implementation)

#### 4.5.1 Integration Points

| Lossless Ledger Component | Compaction Integration |
|---------------------------|------------------------|
| NOTES.md Session Continuity | **PRESERVED** - Never compacted |
| Decision Log | **PRESERVED** - Permanent record |
| Trajectory entries | **PRESERVED** - Audit trail |
| Tool results | **COMPACTABLE** - Summarize after use |
| Thinking blocks | **COMPACTABLE** - Log to trajectory first |

#### 4.5.2 Preservation Rules

```yaml
# Context compaction rules
compaction:
  preserve:
    - pattern: "## Session Continuity"
      reason: "Recovery anchor"
    - pattern: "## Decision Log"
      reason: "Permanent record"
    - pattern: "NOTES.md"
      reason: "Structured memory"

  compact:
    - type: "tool_results"
      after: "used"
      summarize: true
    - type: "thinking_blocks"
      after: "logged_to_trajectory"
      summarize: false
```

#### 4.5.3 Simplified Checkpoint Protocol

**Current (7 steps) → Target (3 steps)**

| Step | Current | Target |
|------|---------|--------|
| 1 | Grounding verification | **Automated** - Continuous |
| 2 | Negative grounding | **Automated** - Continuous |
| 3 | Update Decision Log | **Manual** - Still required |
| 4 | Update Bead | **Manual** - Still required |
| 5 | Log trajectory | **Automated** - Continuous |
| 6 | Decay to identifiers | **Automated** - Compaction handles |
| 7 | Verify EDD | **Manual** - Still required |

**Simplified checkpoint**:
1. Verify Decision Log updated
2. Verify Bead updated
3. Verify EDD test scenarios

---

## 5. Data Architecture

### 5.1 Schema Storage

```
.claude/schemas/
├── prd.schema.json              # PRD validation schema
├── sdd.schema.json              # SDD validation schema
├── sprint.schema.json           # Sprint plan validation schema
├── audit-report.schema.json     # Security audit report schema
├── trajectory-entry.schema.json # Trajectory log entry schema
└── README.md                    # Schema documentation
```

### 5.2 PRD Schema Definition

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://loa.dev/schemas/prd.schema.json",
  "title": "Product Requirements Document",
  "type": "object",
  "required": ["version", "status", "problem_statement", "goals", "functional_requirements"],
  "properties": {
    "version": {
      "type": "string",
      "pattern": "^[0-9]+\\.[0-9]+\\.[0-9]+$",
      "description": "Semantic version"
    },
    "status": {
      "type": "string",
      "enum": ["Draft", "Ready for Architecture", "Approved", "Archived"],
      "description": "Document status"
    },
    "date": {
      "type": "string",
      "format": "date",
      "description": "Document date"
    },
    "problem_statement": {
      "type": "string",
      "minLength": 100,
      "description": "Core problem being solved"
    },
    "goals": {
      "type": "array",
      "minItems": 1,
      "items": {
        "type": "object",
        "required": ["id", "description"],
        "properties": {
          "id": { "type": "string", "pattern": "^G[0-9]+$" },
          "description": { "type": "string", "minLength": 10 }
        }
      }
    },
    "success_metrics": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "target", "measurement"],
        "properties": {
          "id": { "type": "string", "pattern": "^SM[0-9]+$" },
          "target": { "type": "string" },
          "type": { "type": "string", "enum": ["Required", "Soft target"] },
          "measurement": { "type": "string" }
        }
      }
    },
    "functional_requirements": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "description"],
        "properties": {
          "id": { "type": "string", "pattern": "^FR-[A-Z]+-[0-9]+$" },
          "description": { "type": "string" },
          "priority": { "type": "string", "enum": ["P0", "P1", "P2"] }
        }
      }
    },
    "user_stories": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "story", "acceptance_criteria"],
        "properties": {
          "id": { "type": "string", "pattern": "^US-[A-Z]+-[0-9]+$" },
          "story": { "type": "string" },
          "acceptance_criteria": {
            "type": "array",
            "items": { "type": "string" }
          }
        }
      }
    },
    "risks": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "risk": { "type": "string" },
          "likelihood": { "type": "string", "enum": ["Low", "Medium", "High"] },
          "impact": { "type": "string", "enum": ["Low", "Medium", "High"] },
          "mitigation": { "type": "string" }
        }
      }
    }
  }
}
```

### 5.3 Trajectory Entry Schema (Extended)

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://loa.dev/schemas/trajectory-entry.schema.json",
  "title": "Trajectory Log Entry",
  "type": "object",
  "required": ["ts", "agent", "phase"],
  "properties": {
    "ts": {
      "type": "string",
      "format": "date-time"
    },
    "agent": {
      "type": "string",
      "enum": [
        "discovering-requirements",
        "designing-architecture",
        "planning-sprints",
        "implementing-tasks",
        "reviewing-code",
        "auditing-security",
        "deploying-infrastructure",
        "translating-for-executives"
      ]
    },
    "phase": {
      "type": "string",
      "enum": [
        "session_start",
        "extended_thinking",
        "decision",
        "delta_sync",
        "synthesis_checkpoint",
        "session_handoff",
        "fork_detected"
      ]
    },
    "action": { "type": "string" },
    "thinking_trace": {
      "type": "object",
      "properties": {
        "steps": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "thought": { "type": "string" },
              "conclusion": { "type": "string" }
            }
          }
        },
        "duration_ms": { "type": "integer" },
        "token_count": { "type": "integer" }
      }
    },
    "grounding": {
      "type": "object",
      "properties": {
        "type": {
          "type": "string",
          "enum": ["citation", "code_reference", "assumption", "user_input"]
        },
        "refs": {
          "type": "array",
          "items": { "type": "string" }
        }
      }
    }
  }
}
```

---

## 6. API Design

### 6.1 Skills Adapter API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `skills-adapter.sh generate <skill>` | CLI | Generate Agent Skills format |
| `skills-adapter.sh upload <skill>` | CLI | Upload to Claude API |
| `skills-adapter.sh sync` | CLI | Sync all skills |
| `skills-adapter.sh list` | CLI | List skills with status |

### 6.2 Schema Validator API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `schema-validator.sh validate <file>` | CLI | Validate file against schema |
| `schema-validator.sh list` | CLI | List available schemas |

### 6.3 Tool Search Adapter API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `tool-search-adapter.sh search <query>` | CLI | Search for tools |
| `tool-search-adapter.sh discover` | CLI | Auto-discover tools |
| `tool-search-adapter.sh cache clear` | CLI | Clear cache |

---

## 7. Security Architecture

### 7.1 Extended Thinking Security

| Concern | Mitigation |
|---------|------------|
| Sensitive data in thinking traces | Redact before logging, configurable |
| Thinking trace storage | Same permissions as trajectory (~600) |
| Cross-session leakage | Thinking traces scoped to task/session |

### 7.2 Tool Search Security

| Concern | Mitigation |
|---------|------------|
| Unauthorized tool discovery | Respect MCP server permissions |
| Cache poisoning | Validate cache integrity on read |
| Malicious tool injection | Only load from trusted registries |

### 7.3 Schema Validation Security

| Concern | Mitigation |
|---------|------------|
| Schema injection | Schemas are framework-owned, read-only |
| Bypass attempts | Validation in "warn" mode still logs |
| Denial of service | Timeout on validation (5s default) |

---

## 8. Integration Points

### 8.1 Existing Loa Components

| Component | Integration | Changes Required |
|-----------|-------------|------------------|
| Skill Loader | Call Skills Adapter for format conversion | Minor hook |
| MCP Registry | Tool Search Adapter queries registry | No changes |
| Trajectory Logger | Extended with thinking traces | Schema addition |
| Session Continuity | Context Manager extension | Protocol addition |
| Commands | Add `--validate-schema` and `--enable-thinking` flags | Flag parsing |

### 8.2 Claude Platform APIs

| API | Purpose | Authentication |
|-----|---------|----------------|
| Agent Skills API | Upload/sync skills | `CLAUDE_API_KEY` |
| Structured Outputs | Schema validation | API header |
| Extended Thinking | Enable thinking mode | API parameter |
| Tool Search | Dynamic tool discovery | Built-in |

### 8.3 Registry Integration (Coordination with Registry PRD)

| Integration Point | Coordination |
|-------------------|--------------|
| Constructs skills | Can be uploaded to Claude API workspace |
| License validation | Runs before Skills Adapter |
| Skill loading priority | Same priority order applies |

---

## 9. Scalability & Performance

### 9.1 Performance Targets (Soft)

| Metric | Target | Mechanism |
|--------|--------|-----------|
| Token usage | -15% | Progressive skill disclosure |
| Tool discovery | ~100ms | Caching, lazy loading |
| Schema validation | <500ms | Local validation, ajv-cli |
| Context efficiency | +20% | Client-side compaction |

### 9.2 Caching Strategy

| Cache | TTL | Location | Invalidation |
|-------|-----|----------|--------------|
| Tool search results | 24h | `~/.loa/cache/tool-search/` | Manual or TTL |
| Generated frontmatter | Session | Memory | Session end |
| MCP capabilities | 24h | `~/.loa/cache/tool-search/mcp-servers/` | Manual or TTL |

### 9.3 Lazy Loading

| Resource | Load Condition |
|----------|----------------|
| Skill Level 2 (SKILL.md) | On trigger match |
| Skill Level 3 (resources/) | On explicit request |
| Tool capabilities | On first search |
| Schema files | On validation request |

---

## 10. Deployment Architecture

### 10.1 File Additions

| Path | Type | Purpose |
|------|------|---------|
| `.claude/scripts/skills-adapter.sh` | Script | Agent Skills format generation |
| `.claude/scripts/schema-validator.sh` | Script | Output validation |
| `.claude/scripts/thinking-logger.sh` | Script | Extended thinking logging |
| `.claude/scripts/tool-search-adapter.sh` | Script | Tool search bridge |
| `.claude/scripts/context-manager.sh` | Script | Compaction integration |
| `.claude/schemas/*.json` | Schema | Output validation schemas |
| `.claude/protocols/context-compaction.md` | Protocol | Compaction rules |

### 10.2 Configuration Additions

```yaml
# .loa.config.yaml additions

agent_skills:
  enabled: true
  load_mode: "dynamic"        # "dynamic" | "eager"
  api_upload: false           # Requires CLAUDE_API_KEY

structured_outputs:
  enabled: true
  validation_mode: "warn"     # "strict" | "warn" | "disabled"
  timeout_ms: 5000

extended_thinking:
  enabled: true
  log_to_trajectory: true
  redact_sensitive: true
  agents:
    - reviewing-code
    - auditing-security
    - designing-architecture

tool_search:
  enabled: true
  auto_discover: true
  cache_ttl_hours: 24
  include_constructs: true

context_management:
  client_compaction: true
  preserve_notes_md: true
  simplified_checkpoint: true

claude_models:
  default: "claude-opus-4-5-20251101"
  fallback: "claude-sonnet-4-5-20251101"
  cost_sensitive: "claude-haiku-4-5-20251015"
```

### 10.3 Environment Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `CLAUDE_API_KEY` | Skills API authentication | (none) |
| `LOA_SCHEMA_MODE` | Override validation mode | (config) |
| `LOA_THINKING_ENABLED` | Override thinking enable | (config) |
| `LOA_TOOL_CACHE_TTL` | Override cache TTL | 24 |

---

## 11. Development Workflow

### 11.1 Testing Strategy

| Test Type | Tool | Coverage Target |
|-----------|------|-----------------|
| Unit tests | bats | 95% script functions |
| Schema tests | ajv-cli | All schemas valid |
| Integration tests | bats | Cross-component flows |
| E2E tests | Manual | Cross-platform (Linux/macOS) |

### 11.2 Test Files

```
tests/
├── unit/
│   ├── skills-adapter.bats
│   ├── schema-validator.bats
│   ├── thinking-logger.bats
│   └── tool-search-adapter.bats
├── integration/
│   ├── skills-generation.bats
│   ├── output-validation.bats
│   └── context-management.bats
└── fixtures/
    ├── sample-index.yaml
    ├── valid-prd.md
    ├── invalid-prd.md
    └── sample-trajectory.jsonl
```

### 11.3 CI/CD Integration

```yaml
# .github/workflows/platform-integration.yml
jobs:
  test:
    steps:
      - name: Run unit tests
        run: bats tests/unit/*.bats

      - name: Validate schemas
        run: |
          for schema in .claude/schemas/*.json; do
            ajv compile -s "$schema"
          done

      - name: Run integration tests
        run: bats tests/integration/*.bats
```

---

## 12. Technical Risks & Mitigation

### 12.1 Risk Matrix

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Claude API changes | Low | High | Version pin, feature flags |
| Schema too strict | Medium | Medium | Start with "warn" mode |
| Thinking token costs | Medium | Medium | Monitor usage, make opt-in |
| Tool search conflicts | Medium | Low | Fallback to manual MCP |
| Compaction data loss | Low | High | Preserve critical sections |

### 12.2 Fallback Strategies

| Component | Fallback |
|-----------|----------|
| Skills Adapter | Return original format (no frontmatter) |
| Schema Validator | Skip validation, log warning |
| Thinking Logger | Log to standard trajectory (no trace) |
| Tool Search | Use existing mcp-registry.sh |
| Context Manager | Use current 7-step checkpoint |

---

## 13. Future Considerations

### 13.1 Deferred Features

| Feature | Version | Rationale |
|---------|---------|-----------|
| Multi-workspace skills | v0.12.0 | Single workspace sufficient for v0.11.0 |
| Schema versioning | v0.12.0 | Static schemas sufficient initially |
| Thinking trace UI | v0.12.0 | CLI sufficient for v0.11.0 |
| Auto-compaction | v0.12.0 | Manual triggers in v0.11.0 |

### 13.2 Technical Debt

| Item | Priority | Plan |
|------|----------|------|
| Schema redundancy | Low | Consolidate common fields |
| Cache invalidation | Medium | Add smart invalidation in v0.12.0 |
| Test coverage gaps | High | Address during sprint implementation |

---

## 14. Appendices

### Appendix A: Skill Format Comparison

| Aspect | Loa Format | Claude Agent Skills | Adaptation |
|--------|------------|---------------------|------------|
| Metadata location | index.yaml | SKILL.md frontmatter | Generate frontmatter |
| Description | Multi-line YAML | Single line | Extract first line |
| Triggers | Array | Array | Direct map |
| Protocols | Supported | Not supported | Loa-only |
| Parallel execution | Supported | Not supported | Loa-only |
| Inputs/Outputs | Supported | Not supported | Loa-only |

### Appendix B: Command Flag Reference

| Command | New Flags |
|---------|-----------|
| `/plan-and-analyze` | `--validate-schema` |
| `/architect` | `--validate-schema`, `--enable-thinking` |
| `/sprint-plan` | `--validate-schema` |
| `/review-sprint` | `--enable-thinking` |
| `/audit-sprint` | `--validate-schema`, `--enable-thinking` |

### Appendix C: Configuration Defaults

```yaml
# Default configuration (applied if not specified)
agent_skills:
  enabled: true
  load_mode: "dynamic"
  api_upload: false

structured_outputs:
  enabled: true
  validation_mode: "warn"
  timeout_ms: 5000

extended_thinking:
  enabled: true
  log_to_trajectory: true
  redact_sensitive: true
  agents:
    - reviewing-code
    - auditing-security
    - designing-architecture

tool_search:
  enabled: true
  auto_discover: true
  cache_ttl_hours: 24
  include_constructs: true

context_management:
  client_compaction: true
  preserve_notes_md: true
  simplified_checkpoint: true
```

---

## 15. Sign-Off

| Role | Name | Date | Status |
|------|------|------|--------|
| Architecture Designer | AI Agent | 2026-01-11 | Complete |
| Framework Maintainer | | | Pending |

---

**Next Step**: `/sprint-plan` to break down work into sprints
