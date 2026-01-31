# Memory Protocol

## Purpose

Formalize Loa's grimoire-based memory system with structured schemas, lifecycle management, and cross-session retrieval. Based on concepts from Anthropic's memory tool but implemented via grimoire files.

**Key insight**: Anthropic's memory tool achieves 39% performance improvement when combined with context editing. Loa's grimoire system provides similar benefits through structured persistence.

## Memory Categories

| Category | TTL | Confidence | Purpose |
|----------|-----|------------|---------|
| `fact` | permanent | ≥0.8 | Stable truths about the project |
| `decision` | permanent | ≥0.9 | Architecture/implementation decisions |
| `learning` | 90d | ≥0.7 | Extracted patterns from experience |
| `error` | 30d | ≥0.6 | Error-solution pairs |
| `preference` | permanent | ≥0.5 | User/project preferences |

## Storage Locations

```
grimoires/loa/memory/
├── facts.yaml          # Stable project facts
├── decisions.yaml      # Architecture decisions (PR #86)
├── learnings.yaml      # Extracted patterns (PR #67)
├── errors.yaml         # Error-solution pairs
├── preferences.yaml    # User preferences
└── archive/            # Expired/superseded memories
```

## Security

**NEVER store in memory entries:**
- API keys or tokens
- Passwords or credentials
- Private keys or secrets
- PII (personally identifiable information)

Memory files are git-tracked and should contain only project knowledge, not secrets.

## Memory Entry Format

```yaml
# Example: decisions.yaml
- id: MEM-20260201-001
  category: decision
  content: |
    Use PostgreSQL for the database layer due to JSONB support
    and existing team expertise. SQLite considered but rejected
    for multi-user concurrency requirements.
  summary: PostgreSQL selected over SQLite for database
  confidence: 0.95
  source:
    session_id: abc123
    agent: designing-architecture
    phase: architecture
    timestamp: 2026-02-01T10:30:00Z
  ttl: permanent
  tags: [database, architecture, postgresql]
```

## When to Save Memories

### Facts
- Project configuration discovered
- Technology stack identified
- Team conventions established
- External service dependencies confirmed

### Decisions
- Architecture choices made (with rationale)
- Technology selections (with alternatives considered)
- Design patterns adopted
- Trade-off resolutions

### Learnings
- Non-obvious solutions discovered
- Debugging patterns that worked
- Performance optimizations found
- Testing strategies that improved coverage

### Errors
- Bugs encountered with solutions
- Configuration issues resolved
- Integration problems fixed
- Edge cases handled

### Preferences
- User workflow preferences
- Output format preferences
- Communication style preferences
- Tool/integration preferences

## Memory Lifecycle

### Creation

```yaml
# When creating a memory:
1. Generate ID: MEM-{YYYYMMDD}-{sequence}
2. Determine category based on content type
3. Extract summary (one-line)
4. Set confidence based on evidence strength
5. Record source (session, agent, phase, timestamp)
6. Calculate expiration (if not permanent)
7. Add relevant tags
```

### Retrieval

```yaml
# When retrieving memories:
1. Query by category, tags, or semantic similarity
2. Filter by minimum confidence threshold
3. Exclude expired memories (check expires_at)
4. Apply recency weighting if configured
5. Return up to max_per_query results
```

### Update

```yaml
# Memories are immutable - create new entries that supersede:
1. Create new memory with updated content
2. Set supersedes: <old-memory-id>
3. Update old memory: superseded_by: <new-memory-id>
4. Old memory remains for audit trail
```

### Archival

```yaml
# When archiving memories:
1. Check expiration (ttl vs current date)
2. Move to archive directory
3. Set archived: true, archived_at, archive_reason
4. Retain for configurable period
```

## Integration Points

### Oracle Integration (PR #89)

Memories are queryable via the oracle system:

```bash
# Query memories via oracle
.claude/scripts/anthropic-oracle.sh query "auth pattern" --scope loa

# Memory entries in learnings.yaml are indexed and searchable
```

### Decision Protocol (PR #86)

Decisions from `grimoires/loa/decisions.yaml` follow this schema.
Auto-capture enabled when `memory_schema.auto_capture.decisions: true`.

### Compound Learning (PR #67)

Learnings from compound analysis populate `learnings.yaml`.
Auto-capture enabled when `memory_schema.auto_capture.learnings: true`.

### Context Editing (Issue #95)

Memory files are NEVER cleared during context editing.
They exist outside the context window by design.

## Effectiveness Tracking

For learnings, track application outcomes:

```yaml
effectiveness:
  applications: 5      # Times this learning was retrieved
  successes: 4         # Times it led to successful outcome
  score: 80            # Computed effectiveness (0-100)
  last_applied: 2026-02-01T18:00:00Z
```

Effectiveness tiers:
- **High (≥80)**: Increase retrieval priority
- **Medium (50-79)**: Normal retrieval
- **Low (20-49)**: Flag for review
- **Ineffective (<20)**: Queue for archival

## Configuration

```yaml
# .loa.config.yaml
memory_schema:
  enabled: true
  storage_dir: grimoires/loa/memory

  auto_capture:
    decisions: true
    errors: true
    learnings: true

  retrieval:
    max_per_query: 10
    min_confidence: 0.6
    recency_weight: 0.2
    integrate_with_oracle: true

  lifecycle:
    auto_archive: true
    archive_dir: grimoires/loa/memory/archive
    check_on_session_start: true
    warn_before_archive_days: 7
```

### Lifecycle Implementation Notes

**Important**: The `lifecycle` settings are configuration flags that runtime implementers should honor:

- `check_on_session_start: true` - Runtime should check for expired memories at session start
- `auto_archive: true` - Runtime should move expired memories to archive directory

Loa defines WHAT should happen and WHEN (configuration). Runtime implements HOW (actual file operations). This follows Loa's three-layer architecture where Loa is the policy layer, not the execution layer.

**For runtime implementers**: See `docs/integration/runtime-contract.md` for the memory schema handling contract.

## Comparison with Anthropic's Memory Tool

| Aspect | Anthropic Memory Tool | Loa Memory System |
|--------|----------------------|-------------------|
| Storage | File-based via tool calls | Grimoire YAML files |
| Access | Tool calls (create/read/update/delete) | Direct file read/write |
| Persistence | Directory managed by developer | Git-tracked grimoires |
| Schema | Unstructured | JSON Schema validated |
| Lifecycle | Manual | Auto-archival with TTL |
| Integration | API-level | Oracle, compound learning |

Both approaches achieve the goal: **persistent cross-session knowledge that improves agent performance**.

## Related

- Schema: `.claude/schemas/memory.schema.json`
- Decision Protocol: `.claude/protocols/decision-capture.md`
- Compound Learning: `.claude/commands/compound.md`
- Oracle: `.claude/scripts/anthropic-oracle.sh`

## Sources

- [Anthropic Context Management](https://claude.com/blog/context-management)
- [Memory Tool Documentation](https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool)
