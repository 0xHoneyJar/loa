# Product Requirements Document: Claude Platform Integration

**Version:** 1.0.0
**Status:** Ready for Architecture
**Date:** 2026-01-11
**Author:** Product Discovery Agent

---

## Document Information

| Field | Value |
|-------|-------|
| Project | Claude Platform Integration for Loa v0.11.0 |
| Primary Users | Framework Maintainers & Loa End Users (equal priority) |
| Scope | Integration with Claude Agent Skills, Structured Outputs, Extended Thinking, Tool Search, Context Management |
| Success Criteria | All 8 agents compatible with Claude Agent Skills API, validated output schemas, improved reasoning quality |

> **Sources**: CLAUDE_SKILLS_INTEGRATION_REPORT.md:1-426, Discovery interview responses

**Related PRD**: `grimoires/loa/prd.md` (Loa Registry Integration) - complementary scope

---

## 1. Problem Statement

Anthropic has released significant Claude platform updates (October-November 2025) that could enhance Loa's agent capabilities, but the framework doesn't currently leverage these features:

- **Agent Skills Framework** (Oct 16, 2025) - Modular capabilities with progressive disclosure
- **Structured Outputs** (Nov 14, 2025) - Guaranteed JSON schema conformance
- **Extended Thinking** (May 22, 2025) - Internal reasoning for complex tasks
- **Tool Search** (Nov 24, 2025) - Dynamic tool discovery
- **Context Management** (Oct-Nov 2025) - Client-side compaction and clearing

**Core Problem**: Loa's existing skills architecture is compatible with Claude's Agent Skills but not optimized for it. Without integration, Loa misses opportunities for:
- Automatic skill discoverability across Claude products
- Guaranteed output consistency via schemas
- Improved reasoning for security audits and code reviews
- Reduced token usage through progressive disclosure

> **Sources**: CLAUDE_SKILLS_INTEGRATION_REPORT.md:10-21, 27-76

---

## 2. Goals & Success Metrics

### 2.1 Primary Goals

| Goal | Description |
|------|-------------|
| G1 | Refactor 8 Loa agents as Claude Agent Skills with proper metadata |
| G2 | Implement structured output validation for PRD, SDD, and sprint.md |
| G3 | Enable extended thinking for security, architecture, and code review agents |
| G4 | Integrate tool search with MCP registry for dynamic capability discovery |
| G5 | Enhance Lossless Ledger Protocol with client-side compaction |

> **Sources**: CLAUDE_SKILLS_INTEGRATION_REPORT.md:193-307

### 2.2 Success Metrics (Soft Targets)

| Metric | Target | Type | Measurement |
|--------|--------|------|-------------|
| SM1 | All 8 agents discoverable via Agent Skills API | Required | Functional test |
| SM2 | Skills work in claude.ai, Claude Code, and Claude API | Required | Cross-platform test |
| SM3 | Token usage reduction | -15% | Soft target | Benchmark comparison |
| SM4 | Tool discovery latency | -80% (~100ms) | Soft target | Performance benchmark |
| SM5 | Agent reasoning quality improvement | +10-15% | Soft target | Quality review |
| SM6 | Zero schema violations in test suite | Required | CI/CD validation |
| SM7 | 95%+ test coverage for new features | Required | Coverage report |

> **Sources**: CLAUDE_SKILLS_INTEGRATION_REPORT.md:337-364, Discovery Q3 response

### 2.3 Non-Goals (Explicit)

| Non-Goal | Rationale |
|----------|-----------|
| Replace existing skill structure | Agent Skills format is additive, not replacing `.claude/skills/` |
| Auto-update skills | Pull-based updates only (consistent with Registry PRD) |
| Hard performance requirements | Soft targets allow iterative improvement |
| Breaking changes to CLI | All existing commands remain unchanged |

> **Sources**: CLAUDE_SKILLS_INTEGRATION_REPORT.md:367-375

---

## 3. User & Stakeholder Context

### 3.1 Primary User: Framework Maintainer

| Attribute | Description |
|-----------|-------------|
| Role | Developer maintaining/extending Loa framework |
| Team Size | 2-4 people (THJ team) |
| Technical Level | Expert - familiar with YAML, JSON Schema, framework internals |
| Primary Need | Integrate Claude platform features while maintaining backward compatibility |

### 3.2 Primary User: Loa End User

| Attribute | Description |
|-----------|-------------|
| Role | Developer using Loa framework for product development |
| Technical Level | Intermediate to advanced |
| Primary Need | Better agent quality, faster execution, consistent outputs |
| Expected Benefits | Improved PRD/SDD quality, more thorough security audits |

> **Sources**: Discovery Q1 response (Both equally)

### 3.3 Compatibility with Registry Integration

| Integration Point | Description |
|-------------------|-------------|
| Skill Loading Priority | Registry skills can also be Claude Agent Skills |
| Constructs Upload | Registry skills can be uploaded to Claude API workspace |
| License Validation | Unchanged - applies before skill loading |

> **Sources**: Coordination with grimoires/loa/prd.md

---

## 4. Functional Requirements

### 4.1 Agent Skills Refactoring (Phase 1)

**FR-SKILL-01**: Convert all 8 Loa agents to Claude Agent Skills format.

| Agent | Current Location | Target Format |
|-------|------------------|---------------|
| discovering-requirements | `.claude/skills/discovering-requirements/` | YAML frontmatter + SKILL.md |
| designing-architecture | `.claude/skills/designing-architecture/` | YAML frontmatter + SKILL.md |
| planning-sprints | `.claude/skills/planning-sprints/` | YAML frontmatter + SKILL.md |
| implementing-tasks | `.claude/skills/implementing-tasks/` | YAML frontmatter + SKILL.md |
| reviewing-code | `.claude/skills/reviewing-code/` | YAML frontmatter + SKILL.md |
| auditing-security | `.claude/skills/auditing-security/` | YAML frontmatter + SKILL.md |
| deploying-infrastructure | `.claude/skills/deploying-infrastructure/` | YAML frontmatter + SKILL.md |
| translating-for-executives | `.claude/skills/translating-for-executives/` | YAML frontmatter + SKILL.md |

> **Sources**: CLAUDE_SKILLS_INTEGRATION_REPORT.md:46-68, 197-201

**FR-SKILL-02**: Add YAML frontmatter with required Claude Agent Skills metadata.

```yaml
---
name: "discovering-requirements"
description: "Product Manager agent for PRD generation through structured discovery"
version: "1.0.0"
triggers:
  - "/plan-and-analyze"
  - "create PRD"
  - "product requirements"
---
```

**FR-SKILL-03**: Implement 3-level progressive disclosure.

| Level | Content | Token Cost | Load Condition |
|-------|---------|------------|----------------|
| 1 | YAML frontmatter metadata | ~100 tokens | Always loaded |
| 2 | SKILL.md instructions | ~2-5k tokens | When triggered |
| 3 | resources/, scripts/ | Variable | On-demand |

> **Sources**: CLAUDE_SKILLS_INTEGRATION_REPORT.md:38-42

**FR-SKILL-04**: Create `constructs-upload.sh` script for Skills API integration.

| Command | Description |
|---------|-------------|
| `upload <skill>` | Upload skill to Claude API workspace |
| `list` | List uploaded skills |
| `sync` | Sync local skills with API workspace |
| `version` | Check skill version compatibility |

> **Sources**: CLAUDE_SKILLS_INTEGRATION_REPORT.md:203-207

### 4.2 Structured Outputs (Phase 2)

**FR-SCHEMA-01**: Define JSON Schema for PRD output.

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "version": {"type": "string", "pattern": "^[0-9]+\\.[0-9]+\\.[0-9]+$"},
    "status": {"type": "string", "enum": ["Draft", "Ready for Architecture", "Approved"]},
    "problem_statement": {"type": "string", "minLength": 100},
    "goals": {"type": "array", "items": {"type": "object"}, "minItems": 1},
    "success_metrics": {"type": "array", "items": {"type": "object"}, "minItems": 1},
    "functional_requirements": {"type": "array", "items": {"type": "object"}},
    "user_stories": {"type": "array", "items": {"type": "object"}},
    "risks": {"type": "array", "items": {"type": "object"}}
  },
  "required": ["version", "status", "problem_statement", "goals", "functional_requirements"]
}
```

> **Sources**: CLAUDE_SKILLS_INTEGRATION_REPORT.md:234-246

**FR-SCHEMA-02**: Define JSON Schema for SDD output.

**FR-SCHEMA-03**: Define JSON Schema for sprint.md output.

**FR-SCHEMA-04**: Define JSON Schema for security audit report.

**FR-SCHEMA-05**: Add `--validate-schema` flag to relevant commands.

| Command | Schema |
|---------|--------|
| `/plan-and-analyze --validate-schema` | PRD schema |
| `/architect --validate-schema` | SDD schema |
| `/sprint-plan --validate-schema` | Sprint schema |
| `/audit-sprint --validate-schema` | Audit report schema |

> **Sources**: CLAUDE_SKILLS_INTEGRATION_REPORT.md:257-265

### 4.3 Extended Thinking (Phase 2)

**FR-THINK-01**: Enable extended thinking for complex reasoning agents.

| Agent | Use Case | Benefit |
|-------|----------|---------|
| reviewing-code | Complex code analysis | Better architectural review |
| auditing-security | Vulnerability assessment | Thorough security analysis |
| designing-architecture | Design trade-offs | Well-reasoned architecture |

> **Sources**: CLAUDE_SKILLS_INTEGRATION_REPORT.md:107-113, 252-255

**FR-THINK-02**: Add `--enable-thinking` flag to relevant commands.

| Command | Description |
|---------|-------------|
| `/review-sprint --enable-thinking` | Enable extended thinking for code review |
| `/audit-sprint --enable-thinking` | Enable extended thinking for security audit |
| `/architect --enable-thinking` | Enable extended thinking for architecture design |

**FR-THINK-03**: Log thinking traces to trajectory for audit trail.

### 4.4 Tool Search & MCP Enhancement (Phase 3)

**FR-TOOL-01**: Integrate Claude tool search with MCP registry.

| Enhancement | Description |
|-------------|-------------|
| Auto-discovery | Discover available MCP servers automatically |
| Lazy loading | Load tools on-demand instead of upfront |
| Caching | Cache discovered tools for performance |

> **Sources**: CLAUDE_SKILLS_INTEGRATION_REPORT.md:273-285

**FR-TOOL-02**: Enhance `.claude/scripts/mcp-registry.sh` with tool search.

| New Command | Description |
|-------------|-------------|
| `search <query>` | Search for tools matching query |
| `discover` | Auto-discover available tools |
| `cache` | Manage tool cache |

**FR-TOOL-03**: Connect Loa Constructs registry with Claude tool search.

### 4.5 Context Management Optimization (Phase 4)

**FR-CTX-01**: Integrate client-side compaction with Lossless Ledger Protocol.

| Integration Point | Description |
|-------------------|-------------|
| SDK Configuration | Enable context editing by default |
| NOTES.md | Preserve structured memory during compaction |
| Synthesis Checkpoint | Combine with client-side compaction triggers |

> **Sources**: CLAUDE_SKILLS_INTEGRATION_REPORT.md:293-306

**FR-CTX-02**: Reduce manual checkpoint burden.

| Current | Target |
|---------|--------|
| 7-step synthesis checkpoint | Automated + 3-step manual |
| Manual context clearing | Automatic with overrides |
| Full trajectory logging | Selective logging |

**FR-CTX-03**: Monitor and benchmark token usage improvements.

### 4.6 Configuration

**FR-CFG-01**: Add Claude platform configuration to `.loa.config.yaml`.

```yaml
agent_skills:
  enabled: true
  load_mode: "dynamic"  # "dynamic" | "eager"
  api_upload: true      # Upload to Claude API workspace

structured_outputs:
  enabled: true
  validation_mode: "warn"  # "strict" | "warn" | "disabled"

extended_thinking:
  enabled: true
  agents:
    - reviewing-code
    - auditing-security
    - designing-architecture

tool_search:
  enabled: true
  auto_discover: true
  cache_ttl_hours: 24

context_management:
  client_compaction: true
  preserve_notes_md: true

claude_models:
  default: "claude-opus-4-5-20251101"
  fallback: "claude-sonnet-4-5-20251101"
  cost_sensitive: "claude-haiku-4-5-20251015"
```

> **Sources**: CLAUDE_SKILLS_INTEGRATION_REPORT.md:209-220

---

## 5. Technical & Non-Functional Requirements

### 5.1 Compatibility Requirements

**NFR-COMPAT-01**: Full backward compatibility with existing `.claude/skills/` structure.

| Guarantee | Description |
|-----------|-------------|
| Existing skills work | No changes required to existing Loa projects |
| CLI unchanged | All existing commands work identically |
| Config optional | New config sections are opt-in |

> **Sources**: CLAUDE_SKILLS_INTEGRATION_REPORT.md:367-375

**NFR-COMPAT-02**: Support Claude Opus 4.5, Sonnet 4.5, and Haiku 4.5 models.

**NFR-COMPAT-03**: Skills work across claude.ai, Claude Code, and Claude API.

### 5.2 Performance Requirements (Soft Targets)

**NFR-PERF-01**: Token usage reduction target: -15%.

| Metric | Baseline | Target |
|--------|----------|--------|
| Discovery phase tokens | 100% | 85% |
| Mechanism | Progressive skill disclosure |

**NFR-PERF-02**: Tool discovery latency target: -80%.

| Metric | Baseline | Target |
|--------|----------|--------|
| Tool discovery | ~500ms | ~100ms |
| Mechanism | Tool search tool |

**NFR-PERF-03**: Context window efficiency target: +20%.

| Metric | Baseline | Target |
|--------|----------|--------|
| Context efficiency | 100% | 120% |
| Mechanism | Client-side compaction |

> **Sources**: CLAUDE_SKILLS_INTEGRATION_REPORT.md:383-389, Discovery Q3 (Soft targets)

### 5.3 Quality Requirements

**NFR-QUAL-01**: 95%+ test coverage for all new features.

**NFR-QUAL-02**: Zero schema violations in test suite.

**NFR-QUAL-03**: Agent reasoning quality improvement: +10-15% (measured by review).

### 5.4 Security Requirements

**NFR-SEC-01**: Extended thinking traces may contain sensitive reasoning - handle appropriately.

**NFR-SEC-02**: Tool search must respect MCP server permissions.

---

## 6. Scope & Prioritization

### 6.1 MVP Definition (v0.11.0 - All 4 Phases)

| Phase | Features | Priority |
|-------|----------|----------|
| 1 | Agent Skills refactoring, Skills API integration | P0 |
| 2 | Structured outputs schemas, Extended thinking | P0 |
| 3 | Tool search, MCP enhancement | P1 |
| 4 | Context management optimization | P1 |

> **Sources**: Discovery Q2 response (All 4 phases)

### 6.2 Feature Breakdown

| Feature | Phase | Priority | Status |
|---------|-------|----------|--------|
| Convert 8 agents to Agent Skills format | 1 | P0 | Required |
| YAML frontmatter metadata | 1 | P0 | Required |
| 3-level progressive disclosure | 1 | P0 | Required |
| `constructs-upload.sh` script | 1 | P0 | Required |
| PRD JSON Schema | 2 | P0 | Required |
| SDD JSON Schema | 2 | P0 | Required |
| Sprint JSON Schema | 2 | P0 | Required |
| `--validate-schema` flag | 2 | P0 | Required |
| Extended thinking for 3 agents | 2 | P0 | Required |
| `--enable-thinking` flag | 2 | P1 | Required |
| Tool search integration | 3 | P1 | Required |
| MCP registry enhancement | 3 | P1 | Required |
| Constructs registry connection | 3 | P2 | Nice-to-have |
| Client-side compaction | 4 | P1 | Required |
| Reduce checkpoint burden | 4 | P1 | Required |
| Performance benchmarks | All | P1 | Required |
| Documentation updates | All | P0 | Required |

### 6.3 Out of Scope

| Item | Rationale |
|------|-----------|
| Breaking changes to existing skills | Backward compatibility required |
| Auto-push skill updates | Explicit design decision - pull only |
| Hard performance requirements | Soft targets allow iteration |
| New skill creation | Focus is on refactoring existing 8 |

---

## 7. Risks & Dependencies

### 7.1 Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Agent Skills API changes | Low | High | Version pin, monitor Claude docs |
| Extended thinking token costs | Medium | Medium | Monitor usage, make opt-in |
| Tool search MCP conflicts | Medium | Medium | Comprehensive testing |
| Schema validation strictness | Low | Medium | Start with "warn" mode |
| Context compaction data loss | Low | High | Preserve NOTES.md, test thoroughly |

> **Sources**: CLAUDE_SKILLS_INTEGRATION_REPORT.md:310-331

### 7.2 External Dependencies

| Dependency | Type | Risk Level | Mitigation |
|------------|------|------------|------------|
| Claude Agent Skills API | Runtime | Medium | Feature flag to disable |
| Structured outputs beta | Runtime | Low | Fallback to unvalidated |
| Extended thinking API | Runtime | Low | Feature flag |
| Tool search API | Runtime | Low | Fallback to manual MCP |

### 7.3 Integration Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Registry integration overlap | Medium | Low | Clear interface contracts |
| Lossless Ledger conflicts | Low | Medium | Test compaction with NOTES.md |
| Cross-platform skill compatibility | Medium | Medium | Test on claude.ai, Code, API |

---

## 8. User Stories

### 8.1 Framework Maintainer Stories

**US-FM-01**: As a framework maintainer, I want to convert Loa agents to Claude Agent Skills format so that they are discoverable across Claude products.

**Acceptance Criteria:**
- [ ] All 8 agents have YAML frontmatter with name, description, triggers
- [ ] 3-level progressive disclosure implemented
- [ ] Skills discoverable in claude.ai and Claude Code
- [ ] Backward compatibility with existing projects verified

**US-FM-02**: As a framework maintainer, I want to define output schemas so that agent outputs are guaranteed consistent.

**Acceptance Criteria:**
- [ ] PRD, SDD, sprint.md schemas defined in JSON Schema format
- [ ] `--validate-schema` flag added to relevant commands
- [ ] Schema validation integrated into CI/CD
- [ ] Validation errors provide actionable feedback

**US-FM-03**: As a framework maintainer, I want to enable extended thinking for complex agents so that reasoning quality improves.

**Acceptance Criteria:**
- [ ] Extended thinking enabled for reviewing-code, auditing-security, designing-architecture
- [ ] `--enable-thinking` flag available on relevant commands
- [ ] Thinking traces logged to trajectory for audit
- [ ] Token usage monitored and reported

### 8.2 End User Stories

**US-EU-01**: As a Loa user, I want consistent PRD/SDD outputs so that document quality is reliable.

**Acceptance Criteria:**
- [ ] PRDs follow defined schema structure
- [ ] SDDs follow defined schema structure
- [ ] Validation warnings help fix issues
- [ ] No breaking changes to existing workflows

**US-EU-02**: As a Loa user, I want more thorough security audits so that vulnerabilities are caught.

**Acceptance Criteria:**
- [ ] Security audits use extended thinking
- [ ] Audit reports show reasoning trace (optional)
- [ ] Audit quality measurably improved
- [ ] No significant increase in audit time

**US-EU-03**: As a Loa user, I want faster tool discovery so that MCP integrations work seamlessly.

**Acceptance Criteria:**
- [ ] Tool search finds relevant MCP servers automatically
- [ ] Discovered tools cached for performance
- [ ] Fallback to manual MCP if search fails
- [ ] No changes required to existing MCP configs

**US-EU-04**: As a Loa user, I want reduced context management overhead so that long sessions work smoothly.

**Acceptance Criteria:**
- [ ] Client-side compaction enabled by default
- [ ] NOTES.md preserved during compaction
- [ ] Manual checkpoint steps reduced from 7 to 3
- [ ] No loss of important context

---

## 9. Appendices

### Appendix A: Claude Agent Skills Format Reference

```
skill-name/
├── SKILL.md                 # YAML frontmatter + instructions
│   ---
│   name: "skill-name"
│   description: "Skill description"
│   version: "1.0.0"
│   triggers:
│     - "/command"
│     - "natural language trigger"
│   ---
│   # Skill Instructions
│   ...
├── REFERENCE.md            # Optional reference material
├── scripts/                # Optional scripts
│   └── helper.sh
└── resources/              # Optional resources
    └── template.md
```

> **Sources**: CLAUDE_SKILLS_INTEGRATION_REPORT.md:60-68

### Appendix B: Current Loa Skill Structure

```
.claude/skills/{skill-name}/
├── index.yaml              # Metadata
├── SKILL.md                # Instructions
└── resources/              # Optional
```

### Appendix C: Model Recommendations

| Use Case | Model | Model ID |
|----------|-------|----------|
| Primary/Complex | Claude Opus 4.5 | `claude-opus-4-5-20251101` |
| Standard | Claude Sonnet 4.5 | `claude-sonnet-4-5-20251101` |
| Cost-sensitive | Claude Haiku 4.5 | `claude-haiku-4-5-20251015` |

> **Sources**: CLAUDE_SKILLS_INTEGRATION_REPORT.md:180-186

### Appendix D: Performance Projections

| Metric | Current | Projected | Improvement |
|--------|---------|-----------|-------------|
| Token usage (discovery) | 100% | 85% | -15% |
| Context efficiency | 100% | 120% | +20% |
| Tool discovery latency | ~500ms | ~100ms | -80% |
| Agent reasoning quality | Baseline | +10-15% | Improved |

> **Sources**: CLAUDE_SKILLS_INTEGRATION_REPORT.md:383-389

---

## 10. Sign-Off

| Role | Name | Date | Status |
|------|------|------|--------|
| Product Discovery | AI Agent | 2026-01-11 | Complete |
| Framework Maintainer | | | Pending |

---

**Next Step**: `/architect` to create Software Design Document
