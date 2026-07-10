# Vision Registry Templates

Literal presentation specimens relocated verbatim from the discovering-requirements SKILL.md body. The branching logic, gates, and decision tables remain in SKILL.md; these are the fill-in templates.

## Vision Presentation Template (Active Mode)

For each matched vision, present:

```markdown
---
### Relevant Vision: [title]
**Source**: [source field — e.g., "Bridge iteration 2, PR #100"]
**Relevance**: Matched on tags: [matched_tags joined by ", "]
**Score**: [score] (overlap: [overlap], references: [refs])

> [sanitized insight text — max 500 chars, from vision_sanitize_text()]

**What would you like to do with this vision?**
- **Explore**: Mark for deeper analysis — may inspire requirements
- **Defer**: Interesting but not relevant to current work
- **Skip**: Not useful
---
```

## Shadow Graduation Prompt (Step 0.5b)

When the query script returns `graduation.ready: true`:

```markdown
## Vision Registry — Shadow Period Complete

Over **N shadow cycles**, **M visions** matched your work context.

The Vision Registry has been silently logging relevance matches during your
planning sessions. Here's what was found:

[summary of top matches from shadow logs]

**Would you like to:**
1. **Enable active mode** — Start seeing relevant visions during planning
2. **Adjust thresholds** — Change tag overlap or max results settings
3. **Keep shadow mode** — Continue silent logging for more data
4. **Disable** — Turn off vision registry entirely
```

## Vision-Inspired Proposals (Step 7.5 — Present Proposals)

```markdown
---
## Vision-Inspired Requirements (Experimental)

The following requirements are inspired by architectural visions captured during
previous bridge reviews. These are proposals — accept, modify, or reject each one.

### Proposal 1: [short title]
**Source**: [VISION-INSPIRED: vision-NNN] — "[vision title]"
**Rationale**: [1-2 sentences connecting the vision insight to the current work context]

> **Proposed Requirement**: [specific requirement text]

**Decision**: Accept / Modify / Reject

### Proposal 2: [short title]
...
---
```

## Vision-Inspired Requirements PRD Section (Step 7.5 — PRD Integration)

Accepted/modified proposals go in a dedicated PRD section:

```markdown
## 9. Vision-Inspired Requirements

> These requirements were proposed by the Vision Registry based on patterns
> observed in previous development cycles. Each traces to a source vision.

### VR-1: [requirement title]
**Source**: [VISION-INSPIRED: vision-NNN]
[requirement text]

> Sources: vision-NNN (bridge iteration N, PR #NNN), Phase X confirmation
```
