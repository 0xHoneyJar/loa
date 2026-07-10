# Persistent Memory Reference

> Extracted from CLAUDE.loa.md for token efficiency. See: `.claude/loa/CLAUDE.loa.md` for inline summary.

## How It Works (v1.28.0)

> **EXPERIMENTAL — not wired, do not rely on.** As of cycle-115 the
> semantic-memory recall pipeline described below (Memory Writer Hook,
> observations capture, progressive-disclosure query) is **not active**:
> the `memory-inject.sh` / `memory-writer.sh` hooks are unregistered, the
> vector DB is empty, and `observations.jsonl` holds a single hand-authored
> entry (zero hook-generated entries). Treat this section as a design
> sketch of an unrevived subsystem, not a feature you can depend on. The
> `v1.28.0` / `v1.40.0` stamps below are historical provenance only.

Session-spanning observation storage with progressive disclosure for cross-session recall.

1. **Memory Writer Hook**: Captures observations from tool outputs when learning signals detected
2. **Observations File**: Stored in `grimoires/loa/memory/observations.jsonl`
3. **Progressive Disclosure**: Query at different detail levels to manage token budget

## Learning Signals

Automatically captured: discovered, learned, fixed, resolved, pattern, insight

## Query Interface

```bash
# Token-efficient index (~50 tokens per entry)
.claude/scripts/memory-query.sh --index

# Summary view (~200 tokens per entry)
.claude/scripts/memory-query.sh --summary --limit 5

# Full details (~500 tokens)
.claude/scripts/memory-query.sh --full obs-1234567890-abc123

# Filter by type
.claude/scripts/memory-query.sh --type learning

# Free-text search
.claude/scripts/memory-query.sh "authentication pattern"
```

## Ownership Boundary (v1.40.0)

Loa has two memory systems with distinct ownership. Neither should duplicate the other's scope.

| Scope | System | Storage | Owner |
|-------|--------|---------|-------|
| User preferences | Auto-memory | `~/.claude/projects/.../memory/` | Claude Code |
| Working style | Auto-memory | `~/.claude/projects/.../memory/` | Claude Code |
| Project structure | Auto-memory | `~/.claude/projects/.../memory/` | Claude Code |
| Tooling preferences | Auto-memory | `~/.claude/projects/.../memory/` | Claude Code |
| Framework patterns | observations.jsonl | `grimoires/loa/memory/` | Loa hooks |
| Anti-patterns | observations.jsonl | `grimoires/loa/memory/` | Loa hooks |
| Debugging discoveries | observations.jsonl | `grimoires/loa/memory/` | Loa hooks |
| Cross-session technical context | observations.jsonl | `grimoires/loa/memory/` | Loa hooks |

**Decision rule**: If the observation is about *how the user works* → auto-memory. If it's about *how the framework/code works* → observations.jsonl.

> **Reality (cycle-115):** the `Loa hooks` owner in the table above is
> aspirational. `observations.jsonl` is
> **hand-authored, zero hook-generated entries** — the `memory-writer.sh`
> capture hook is unregistered, so nothing
> is written automatically. The ownership boundary describes the intended
> design, not current behavior.

The `memory-writer.sh` hook has a skip-list (`SKIP_PATTERNS`) to avoid writing observations that belong to auto-memory scope.

## Configuration

```yaml
memory:
  enabled: true
  max_observations: 10000
  capture:
    discoveries: true
    errors: true
```
