# Attention Budget Protocol

> **Version**: 1.0 (v0.9.0 Lossless Ledger Protocol)
> **Paradigm**: Clear, Don't Compact
> **Mode**: Advisory (not blocking)

## Purpose

Monitor context window usage and provide advisory recommendations for proactive `/clear` cycles. This protocol implements **advisory monitoring**, not blocking enforcement.

## Attention Budget Model

```
CONTEXT WINDOW AS BUDGET:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  HIGH-VALUE TOKENS                    LOW-VALUE TOKENS          │
│  ┌─────────────────────────┐         ┌─────────────────────┐   │
│  │ • Current task focus    │         │ • Raw tool outputs  │   │
│  │ • Active reasoning      │         │ • Processed results │   │
│  │ • Grounded citations    │         │ • Historical context│   │
│  │ • User requirements     │         │ • Verbose logs      │   │
│  └─────────────────────────┘         └─────────────────────┘   │
│                                                                  │
│  GOAL: Maximize high-value token density                        │
│        Aggressively decay low-value tokens                      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Threshold Levels

| Level | Token Range | Status | Action |
|-------|-------------|--------|--------|
| **Green** | 0-5,000 | Normal | Continue working |
| **Yellow** | 5,000-10,000 | Moderate | Delta-Synthesis (partial persist) |
| **Orange** | 10,000-15,000 | Filling | Recommend `/clear` to user |
| **Red** | 15,000+ | High | Strong recommendation |

**IMPORTANT**: All thresholds are **advisory, not blocking**. The synthesis checkpoint is the enforcement point, not the attention budget.

## Threshold Actions

### Green Zone (0-5,000 tokens)

```
STATUS: Normal operation

ACTIONS:
• Continue working normally
• No special actions required
• Store lightweight identifiers as you go
• Update Decision Log with findings
```

### Yellow Zone (5,000-10,000 tokens)

```
STATUS: Attention budget moderate

ACTIONS:
• Trigger Delta-Synthesis protocol
• Partial persist to ledgers (survives crashes)
• DO NOT clear context yet
• Continue working

DELTA-SYNTHESIS:
1. Append recent findings to NOTES.md Decision Log
2. Update active Bead with progress-to-date
3. Log trajectory: {"phase":"delta_sync","tokens":5000}
4. Continue reasoning with partial safety net
```

### Orange Zone (10,000-15,000 tokens)

```
STATUS: Context filling

ACTIONS:
• Display recommendation to user
• Message: "Context is filling. Consider /clear when ready."
• Continue working if user doesn't clear
• Ensure all decisions are logged

USER MESSAGE:
"⚠️ Attention budget at Orange (10k+ tokens).
 Consider /clear when you reach a good stopping point.
 Your work is persisted in NOTES.md and Beads."
```

### Red Zone (15,000+ tokens)

```
STATUS: Attention budget high

ACTIONS:
• Display strong recommendation
• Message: "Attention budget high. Recommend /clear."
• Continue working (advisory, not blocking)
• Synthesis checkpoint will enforce quality on /clear

USER MESSAGE:
"🔴 Attention budget high (15k+ tokens).
 Recommend /clear to restore full attention.
 Run synthesis checkpoint before clearing."
```

## Delta-Synthesis Protocol

Triggered automatically at Yellow threshold (5,000 tokens).

### Purpose

Ensure work survives if:
- Session crashes
- User closes terminal
- System timeout
- Network interruption

### Protocol Steps

```
DELTA-SYNTHESIS SEQUENCE:
┌─────────────────────────────────────────────────────────────────┐
│ 1. NOTES.md Update                                               │
│    └── Append recent decisions to Decision Log                   │
│                                                                  │
│ 2. Bead Update                                                   │
│    └── Update active Bead with progress, decisions[]            │
│                                                                  │
│ 3. Trajectory Log                                                │
│    └── Log: {"phase":"delta_sync","tokens":5000,...}            │
│                                                                  │
│ 4. Continue (no context clear)                                   │
│    └── Resume work with partial safety net                      │
└─────────────────────────────────────────────────────────────────┘
```

### Trajectory Log Format

```jsonl
{"ts":"2024-01-15T12:00:00Z","agent":"implementing-tasks","phase":"delta_sync","tokens":5000,"decisions_persisted":3,"bead_updated":true,"notes_updated":true}
```

### Recovery from Delta-Sync

If session terminates after Delta-Synthesis:

```
1. New session starts
2. br ready -> identify in-progress task
3. br show <id> -> load decisions[] (includes delta-synced)
4. NOTES.md -> includes delta-synced decisions
5. Some work lost (since last delta-sync)
6. Most work preserved via partial persist
```

## Advisory vs Blocking

### This Protocol (Advisory)

```
ADVISORY THRESHOLDS:
• Yellow: Trigger Delta-Synthesis (automatic)
• Orange: Recommend /clear (user message)
• Red: Strong recommendation (user message)

ENFORCEMENT POINT: synthesis-checkpoint.sh (on /clear)
```

### Why Advisory?

1. **User autonomy**: Users decide when to clear
2. **Natural stopping points**: Work has logical breakpoints
3. **Flexibility**: Some tasks need more context temporarily
4. **Quality gate**: Synthesis checkpoint enforces quality, not timing

### Blocking Enforcement

The **synthesis checkpoint** (not attention budget) provides blocking enforcement:

- Grounding ratio >= 0.95 (BLOCKING)
- Negative grounding verified (BLOCKING in strict mode)
- Ledger sync complete (NON-BLOCKING)

See: `.claude/protocols/synthesis-checkpoint.md`

## Integration with Session Continuity

### Continuous Flow

```
SESSION LIFECYCLE WITH ATTENTION BUDGET:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  Session Start (0 tokens)                                        │
│       │                                                          │
│       ▼                                                          │
│  Work (Green: 0-5k) ──────────────────────┐                     │
│       │                                    │                     │
│       ▼                                    │ Continuous          │
│  Work (Yellow: 5-10k) → Delta-Synthesis   │ synthesis           │
│       │                                    │ to ledgers          │
│       ▼                                    │                     │
│  Work (Orange: 10-15k) → Recommend /clear │                     │
│       │                                    │                     │
│       ▼                                    │                     │
│  Work (Red: 15k+) → Strong recommendation ┘                     │
│       │                                                          │
│       ▼                                                          │
│  User: /clear                                                    │
│       │                                                          │
│       ▼                                                          │
│  Synthesis Checkpoint (BLOCKING)                                 │
│       │                                                          │
│       ▼                                                          │
│  Context cleared, session recovery                               │
│       │                                                          │
│       ▼                                                          │
│  New cycle (Green: 0 tokens)                                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Token Tracking

Agents should track approximate token usage:

```markdown
### Token Budget Status
| Phase | Tokens | Status |
|-------|--------|--------|
| Recovery | 100 | Green |
| Task context | 500 | Green |
| JIT retrieval x3 | 150 | Green |
| Reasoning | 2000 | Green |
| Tool outputs | 3000 | Yellow (delta-sync) |
| More work | 5000 | Orange |
```

## User Communication

### Message Templates

**Yellow (automatic, no user message)**:
```
[Internal: Delta-synthesis triggered at 5k tokens]
```

**Orange**:
```
⚠️ Context is filling (~10k tokens).
Consider /clear when you reach a good stopping point.
Your work is safely persisted in NOTES.md and Beads.
```

**Red**:
```
🔴 Attention budget high (~15k tokens).
Recommend /clear to restore full attention.
All decisions are persisted - run /clear when ready.
```

### User Override

Users can continue working past any threshold. The attention budget is informational, helping users understand context state.

## Configuration

See `.loa.config.yaml`:

```yaml
attention_budget:
  yellow: 5000    # Delta-synthesis trigger
  orange: 10000   # Recommend /clear
  red: 15000      # Strong recommendation

  # All thresholds are advisory
  blocking: false
```

## Monitoring Without Token Counter

Since exact token count isn't always available:

### Heuristics

| Indicator | Approximate Tokens |
|-----------|-------------------|
| Level 1 recovery | ~100 |
| Each JIT retrieval | ~50 |
| Tool output (small) | ~200 |
| Tool output (large) | ~1000+ |
| Reasoning paragraph | ~100-200 |
| Code block (50 lines) | ~500 |

### Estimation

```
ESTIMATION FORMULA:
tokens ≈ (level1_recovery)
       + (jit_retrievals × 50)
       + (tool_outputs × estimated_size)
       + (reasoning × paragraphs × 150)
```

### When to Estimate

1. After Level 1 recovery: ~100 tokens
2. After each JIT retrieval: +50 tokens
3. After large tool output: +500-1000 tokens
4. Periodically during reasoning: +100-200 per significant thought

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|--------------|------------------|
| Ignore threshold warnings | Acknowledge, plan for /clear |
| Clear at Yellow | Wait for natural stopping point |
| Never clear at Red | Consider user recommendation seriously |
| Skip Delta-Synthesis | Always run at Yellow threshold |
| Block user at thresholds | Advisory only, user decides |

---

**Document Version**: 1.0
**Protocol Version**: v2.2 (Production-Hardened)
**Paradigm**: Clear, Don't Compact
**Mode**: Advisory (enforcement via synthesis-checkpoint)
