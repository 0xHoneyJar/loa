# Context Engineering Reference

Reference documentation for Loa's context management features.

## Effort Parameter (v1.13.0)

Anthropic's extended thinking with budget control. Uses `thinking.budget_tokens` (integer) for computational intensity.

| Level | Budget Range | Token Reduction | Use Case |
|-------|--------------|-----------------|----------|
| **low** | 1K-4K | Baseline | Simple queries, translations |
| **medium** | 8K-16K | 76% fewer tokens | Standard implementation |
| **high** | 24K-32K | 48% fewer tokens | Complex architecture, security audit |

**Source**: [Anthropic Claude Opus 4.6 Announcement](https://www.anthropic.com/news/claude-opus-4-6)

See `.loa.config.yaml.example` for configuration.

---

## Context Editing (v1.13.0)

Anthropic's automatic context compaction for long-running agentic workflows. Achieves **84% token reduction** in 100-turn evaluations.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Loa Layer                            │
│  Defines: WHAT to compact, WHEN to trigger, priorities      │
├─────────────────────────────────────────────────────────────┤
│                      Runtime Layer                          │
│  Executes: Token counting, API calls, actual compaction     │
│  (Claude Code, Clawdbot, or custom runtime)                 │
├─────────────────────────────────────────────────────────────┤
│                        API Layer                            │
│  Anthropic: context-management-2025-06-27 beta header       │
└─────────────────────────────────────────────────────────────┘
```

### Compaction Triggers

- **Threshold-based**: When context reaches 80% of limit
- **Phase-based**: After initialization, implementation, testing phases
- **Attention budget**: Per-operation and session limits

### Clearing Priority (lowest first)

1. Stale tool results
2. Completed phase details
3. Superseded file reads
4. Intermediate outputs
5. Verbose debug logs

### Always Preserved (NEVER cleared)

- `trajectory_events` - Audit trail for decisions
- `quality_gate_results` - Gate pass/fail evidence
- `decision_records` - Architecture rationale
- `notes_session_continuity` - Recovery anchor
- `active_beads` - Current task state

**Source**: [Anthropic Context Management Blog](https://claude.com/blog/context-management)

**Protocol**: See `.claude/protocols/context-editing.md`

---

## Memory Schema (v1.13.0)

Persistent cross-session knowledge using grimoire-based storage. Achieves **39% performance improvement** when combined with context editing.

### Memory Categories

| Category | TTL | Min Confidence | Purpose |
|----------|-----|----------------|---------|
| `fact` | permanent | >=0.8 | Stable project truths |
| `decision` | permanent | >=0.9 | Architecture decisions |
| `learning` | 90d | >=0.7 | Extracted patterns |
| `error` | 30d | >=0.6 | Error-solution pairs |
| `preference` | permanent | >=0.5 | User preferences |

### Storage Location

```
grimoires/loa/memory/
├── facts.yaml          # Stable project facts
├── decisions.yaml      # Architecture decisions
├── learnings.yaml      # Extracted patterns
├── errors.yaml         # Error-solution pairs
├── preferences.yaml    # User preferences
└── archive/            # Expired/superseded memories
```

### Memory Entry Format

```yaml
- id: MEM-20260201-001
  category: decision
  content: |
    Use PostgreSQL for database due to JSONB support.
  summary: PostgreSQL selected over SQLite
  confidence: 0.95
  source:
    session_id: abc123
    agent: designing-architecture
    timestamp: 2026-02-01T10:30:00Z
  ttl: permanent
  tags: [database, architecture]
```

### Effectiveness Tracking (for learnings)

```yaml
effectiveness:
  applications: 5      # Times retrieved
  successes: 4         # Successful outcomes
  score: 80            # Effectiveness (0-100)
  last_applied: 2026-02-01T18:00:00Z
```

**Source**: [Anthropic Memory Tool Documentation](https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool)

**Schema**: See `.claude/schemas/memory.schema.json`

**Protocol**: See `.claude/protocols/memory.md`

---

## Attention Budget Enforcement (v1.11.0)

High-search skills include `<attention_budget>` sections with:
- Token thresholds (2K single, 5K accumulated, 15K session)
- Skill-specific clearing triggers
- Compliance checklists for audit-heavy operations
- Semantic decay stages for long-running sessions

**Skills with attention budgets**: auditing-security, implementing-tasks, discovering-requirements, riding-codebase, reviewing-code, planning-sprints, designing-architecture

**Protocol**: See `.claude/protocols/tool-result-clearing.md`

---

## Recursive JIT Context (v0.20.0)

Context optimization for multi-subagent workflows, leveraging RLM research patterns.

| Component | Script | Purpose |
|-----------|--------|---------|
| Semantic Cache | `cache-manager.sh` | Cross-session result caching |
| Condensation | `condense.sh` | Result compression (~20-50 tokens) |
| Early-Exit | `early-exit.sh` | Parallel subagent coordination |
| Semantic Recovery | `context-manager.sh --query` | Query-based section selection |

### Usage Examples

```bash
# Cache audit results
key=$(cache-manager.sh generate-key --paths "src/auth.ts" --query "audit")
cache-manager.sh set --key "$key" --condensed '{"verdict":"PASS"}'

# Condense large results
condense.sh condense --strategy structured_verdict --input result.json

# Coordinate parallel subagents
early-exit.sh signal session-123 agent-1
```

**Protocol**: See `.claude/protocols/recursive-context.md`, `.claude/protocols/semantic-cache.md`
