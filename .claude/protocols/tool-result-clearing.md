# Tool Result Clearing Protocol

The live rule is the 6-line `context_discipline` summary inlined in each SKILL.md. This file holds the shared detail those summaries point to.

## Thresholds

| Context Type | Threshold | Action |
|--------------|-----------|--------|
| Single search result | 2,000 tokens | Apply clearing if exceeded |
| Accumulated results | 5,000 tokens | MANDATORY clearing |
| Full file load | 3,000 tokens | Single file only, synthesize immediately |
| Session total | 15,000 tokens | STOP and synthesize to NOTES.md |

## 4-Step Clearing Process

1. **Extract** high-signal findings: ≤10 files, ≤20 words each, absolute `file:line` references, relevance note.
2. **Synthesize** to `grimoires/loa/NOTES.md`:

   ```markdown
   ## Context Load: {ISO timestamp}
   **Task**: {what you were doing} · **Search**: {query} · **Results**: {N found, M high-signal}
   **Key Files**:
   - `/abs/path/file.ts:45-67` - {why it matters}
   **Patterns Found**: {one line} · **Ready to implement**: {Yes/No}
   ```

3. **Clear** raw output from working memory — do NOT keep or pass raw results onward; reason from the synthesis.
4. **Keep a one-line summary** in context: `Search complete: 47 results → 3 high-signal → synthesized to NOTES.md`.

## Edge Cases

1. **Zero high-signal results** (all scores <0.4): extract nothing; log "X results, 0 high-signal" to trajectory; reformulate the query or flag a potential Ghost Feature (see `citations.md` Negative Grounding); clear everything.
2. **Single large file** (>1000 lines): never load whole; `Read` with offset/limit, synthesize only the relevant ≤50 lines.
3. **Repeated similar searches**: check NOTES.md for an existing synthesis BEFORE searching; append rather than duplicate; >3 similar searches in a session is a confusion signal — log it.

## Related Protocols

- **Session Continuity** (`.claude/protocols/session-continuity.md`) - Recovery from NOTES.md synthesis
- **Synthesis Checkpoint** (`.claude/protocols/synthesis-checkpoint.md`) - Pre-clear validation
- **Trajectory Evaluation** (`.claude/protocols/trajectory-evaluation.md`) - Intent logging before search
- **Citations** (`.claude/protocols/citations.md`) - Citation format, self-audit checkpoint, negative grounding

## Provenance

v2.0 shrink in cycle-121 removed the semantic-decay timers, token-estimation bash, before/after comparisons and validation sections; the live rule is unchanged.
