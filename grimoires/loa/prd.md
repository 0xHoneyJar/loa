# PRD: Bridgebuilder Persona Enrichment for Automated Bridge Loop

**Version**: 1.0.0
**Status**: Draft
**Author**: Discovery Phase (plan-and-analyze)
**Source**: [Issue #295](https://github.com/0xHoneyJar/loa/issues/295) — Bridgebuilder Persona Enrichment
**Date**: 2026-02-12
**Cycle**: cycle-006
**Prior Art**: Manual Bridgebuilder reviews across loa (#248, #293), loa-finn (#25, #30, #34, #45, #51, #54-#59, #61), arrakis (#40, #47, #51-#53)

---

## 1. Problem Statement

The automated `/run-bridge` loop (v1.35.0) achieves excellent convergence — severity scores drop from 137 to 0 across 5 iterations, with 44 findings addressed across 84 files. The mechanism works. But it produces findings that are functionally correct yet **educationally empty**.

The manual Bridgebuilder reviews produced across 25+ PRs in the ecosystem represent a qualitatively different artifact: they teach engineering principles, draw FAANG parallels, use accessible metaphors, celebrate good decisions, and surface architectural intuitions. These reviews have demonstrably advanced understanding of system design, security patterns, and software architecture for both human and AI participants.

### The Quantitative Gap

| Metric | Manual Bridgebuilder | Automated Bridge |
|--------|---------------------|-----------------|
| Characters per review | 20,000 - 90,000 | 2,000 - 5,000 |
| FAANG parallels per review | 5 - 15 | 0 |
| Metaphors per review | 3 - 8 | 0 |
| Praise/celebration findings | 2 - 5 per review | 0 |
| Teaching moments | Every finding | 0 |
| Architectural meditations | 1 - 3 per review | 0 |

### The Qualitative Gap

The same architectural insight in both modes:

**Manual** (PR #54, loa-finn): *"Google didn't become Google when they added a second server. They became Google when Jeff Dean and Sanjay Ghemawat built MapReduce — the abstraction that made it irrelevant which server ran which shard."*

**Automated** (PR #293, iter 4): `**Description**: The bridge_id format validation is correctly placed at the orchestrator where IDs are generated, not in the state library. **Suggestion**: No action needed.`

> The automated bridge changes the code. The manual Bridgebuilder changes the engineer.

### Why This Matters

The user's insight: the manual Bridgebuilder process is "functionally, emotionally and educationally important" — it "helps to provide insights and upskilling in all the surrounding aspects of what we are building but it also helps on the human side to surface observations, intuitions in ways that are purely factual do not."

The manual process is also disruptive and time-consuming (30-60 minutes per iteration of human orchestration), preventing the user from doing their best work. The goal is to preserve the richness while gaining the efficiency of automation.

### Root Causes

Three structural causes prevent the automated bridge from producing rich reviews:

1. **Schema Poverty**: The findings parser extracts only `id, title, severity, category, file, description, suggestion, potential, weight` — no fields for educational content
2. **Severity Scale Excludes Celebration**: No PRAISE level; VISION devolved into "no action needed"
3. **Persona Not Invoked**: Review agents are asked to "find problems," not to embody the Bridgebuilder identity

> Sources: bridgebuilder-enrichment-analysis.md, comparative analysis of 500K+ chars

## 2. Goals & Success Metrics

### Primary Goal

Enable the automated `/run-bridge` loop to produce reviews with the educational depth, emotional resonance, and architectural insight of the manual Bridgebuilder — while preserving the convergence efficiency of the current system.

### Success Metrics

| Metric | Current | Target | Measurement |
|--------|---------|--------|-------------|
| Educational fields per finding | 0 | >= 2 of {faang_parallel, metaphor, teachable_moment} | Parsed from enriched findings JSON |
| PRAISE findings per review | 0 | >= 2 | Count of severity=PRAISE in findings |
| Review character count (insights stream) | 2-5K | 10-30K | Character count of PR comment |
| Convergence efficiency | 137→0 in 5 iter | Same or better | Severity-weighted score trajectory |
| Token overhead per iteration | ~5K | < 30K | Total tokens for review pass |
| User satisfaction | "checkbox" | "transformative" | Qualitative assessment |

### Non-Goals

- Replacing the convergence loop — findings still drive sprint plans and flatline detection
- Requiring multi-model (GPT + Opus) — this works with Claude alone
- Changing the bridge state machine or orchestrator flow
- Modifying the flatline detection algorithm

## 3. User & Stakeholder Context

### Primary Persona: Human Operator

The human operator (maintainer @janitooor) reads bridge PR comments to:
- Understand what was fixed and why it matters
- Learn engineering patterns from FAANG precedents
- Identify architectural decisions worth celebrating
- Surface intuitions about future directions
- Feel that the automated system shares their values of craft and excellence

### Secondary Persona: Future AI Agents

Agents that read PR history or bridge findings need:
- Structured data for programmatic consumption (stream 1)
- Rich context for decision-making about similar patterns (stream 2)
- Understanding of why certain architectural choices were made

### Stakeholder: The Bridgebuilder Persona

The Bridgebuilder persona (defined in loa-finn#24) has an identity and voice:
- *"We build spaceships, but we also build relationships."*
- Top 0.005% of the top 0.005% reviewer
- Every exchange is a teachable moment
- FAANG analogies ground feedback in real precedent
- Rigorous honesty with respectful delivery

> Sources: loa-finn#24 persona definition

## 4. Functional Requirements

### FR-1: Enriched Findings Schema (Level 1)

**Description**: Extend the bridge findings format to include educational fields alongside the existing structured fields.

**New Fields** (all optional, backward-compatible):

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `faang_parallel` | string | Industry precedent from FAANG or OSS | "Google's Zanzibar uses this exact pattern" |
| `metaphor` | string | Accessible analogy for laypeople | "Like a revolving door vs a regular door" |
| `teachable_moment` | string | The lesson beyond the fix | "Validation belongs at generation, not storage" |
| `connection` | string | Link to broader architectural pattern | "Hexagonal architecture boundary" |
| `praise` | boolean | Whether this finding celebrates a good decision | true |

**New Severity Level**: `PRAISE` (weight: 0, not counted toward convergence score)

**Acceptance Criteria**:
- [ ] bridge-findings-parser.sh extracts all new fields from markdown
- [ ] New fields are optional — parser handles their absence gracefully
- [ ] PRAISE severity is recognized with weight 0
- [ ] Existing findings without new fields parse identically to current behavior
- [ ] JSON schema validates new fields

### FR-2: Bridgebuilder Persona Integration (Level 2)

**Description**: Give bridge review agents the full Bridgebuilder persona as their identity when conducting reviews.

**Components**:
- Extract Bridgebuilder persona from loa-finn#24 into `.claude/data/bridgebuilder-persona.md`
- Include persona in the review prompt within the `/run-bridge` skill
- Instruct agents to produce both structured findings AND rich educational prose
- Persona includes: core principles, voice examples, FAANG analogy requirement, metaphor expectation, PRAISE usage

**Acceptance Criteria**:
- [ ] Persona file exists at `.claude/data/bridgebuilder-persona.md`
- [ ] `/run-bridge` skill SKILL.md references persona for review agents
- [ ] Review agent prompt includes persona identity, voice examples, and output expectations
- [ ] Sample review produced by enriched agent includes FAANG parallel and metaphor

### FR-3: Dual-Stream Output (Level 3)

**Description**: The bridge review produces two separate outputs from a single review pass:

1. **Findings Stream** (for convergence): Structured JSON with severity-weighted scores, drives sprint plan generation and flatline detection. Unchanged from current format except for additional optional fields.

2. **Insights Stream** (for education): Rich markdown prose with the full Bridgebuilder voice — opening framing, FAANG parallels, metaphors, praise sections, architectural meditations, closing signature. Posted as the PR comment.

**Key Design Decision**: The two streams are generated in a single review pass (not two separate calls). The review agent produces a rich markdown review containing both `<!-- bridge-findings-start/end -->` markers for parser extraction AND surrounding prose for the insights stream. The parser extracts findings; everything else becomes the insights stream.

**Acceptance Criteria**:
- [ ] Bridge review markdown contains both structured findings AND rich prose
- [ ] bridge-findings-parser.sh extracts findings without losing surrounding prose
- [ ] bridge-github-trail.sh posts the FULL review markdown (not just findings) as PR comment
- [ ] Flatline detection works on extracted findings (stream 1) only
- [ ] Sprint plan generation works on extracted findings (stream 1) only
- [ ] PR comment includes the complete Bridgebuilder review (stream 2)

### FR-4: Seed Findings Integration

**Description**: Include the 13 net-new findings from late-arriving iteration-1 review agents as known issues to be addressed in this cycle.

**Findings to Seed**:

| Priority | Finding |
|----------|---------|
| CRITICAL | `sprint_plan_source` vs `.source` field mismatch in github-trail.sh |
| HIGH | `last_score` never written by `update_flatline()` |
| HIGH | Unquoted heredoc shell injection in `cmd_comment()` |
| HIGH | `bridge`/`eval` constraint categories missing from schema enum |
| HIGH | Bridge constraints have no `@constraint-generated` render target |
| MEDIUM | Vision capture first loop uses pipe-to-while (subshell scope) |
| MEDIUM | `echo -e` interprets escape sequences in PR body |
| MEDIUM | Broken lore cross-references (3 YAML entries) |
| MEDIUM | Three-Zone Model docs missing `.run/` state zone |
| MEDIUM | CLAUDE.loa.md integrity hash stale |
| LOW | `run-bridge` missing from danger level list |
| LOW | Multiline description truncation in findings parser |
| LOW | HALTED transitions missing from state diagram in docs |

**Acceptance Criteria**:
- [ ] All CRITICAL and HIGH findings are addressed
- [ ] MEDIUM findings are addressed where they intersect with FR-1/2/3 changes
- [ ] Sprint plan includes seed findings as Sprint 1 tasks

## 5. Technical Requirements

### TR-1: Token Budget

The enriched review should remain within reasonable token limits:
- Findings stream: < 5,000 tokens per iteration (current budget)
- Insights stream: < 25,000 tokens per iteration (new budget)
- Total review generation: < 30,000 tokens per iteration
- Persona prompt: < 2,000 tokens

### TR-2: Backward Compatibility

- Existing bridge state files must remain valid
- Findings parser must handle both old-format and new-format findings
- Flatline detection algorithm unchanged
- Bridge orchestrator signals unchanged

### TR-3: Parser Robustness

The dual-stream approach means the parser must:
- Extract findings from within `<!-- bridge-findings-start/end -->` markers (unchanged)
- Parse new optional fields without failing on their absence
- Not be confused by rich prose outside the markers (unchanged — already ignores it)

### TR-4: Configuration

New config options in `.loa.config.yaml`:

```yaml
run_bridge:
  bridgebuilder:
    persona_enabled: true          # Enable Bridgebuilder persona for reviews
    enriched_findings: true        # Extract educational fields from findings
    insights_stream: true          # Post full review (not just findings) to PR
    praise_findings: true          # Include PRAISE severity in reviews
    token_budget:
      findings: 5000               # Max tokens for findings stream
      insights: 25000              # Max tokens for insights stream
```

## 6. Scope & Prioritization

### In Scope (MVP)

1. Enriched findings schema with 5 new fields + PRAISE severity
2. Bridgebuilder persona file extracted from loa-finn#24
3. Persona wired into /run-bridge review prompt
4. Dual-stream output (findings + insights)
5. 13 seed findings addressed
6. Updated tests for all modified scripts
7. Configuration options

### Out of Scope

- Multi-model review (GPT + Opus) — uses single Claude model
- Persona customization UI
- Historical review migration (existing PR comments stay as-is)
- Cross-repo Bridgebuilder reviews
- Automated FAANG parallel database
- Insights stream archival/indexing beyond PR comments

### Future Scope

- Multi-model Bridgebuilder (Hounfour integration when available)
- Insights-to-learning pipeline (feed rich reviews into NOTES.md learnings)
- PRAISE finding → vision registry integration
- Cross-session persona memory (Bridgebuilder remembers past reviews)

## 7. Risks & Dependencies

### Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Token cost increase per iteration | High | Medium | Configurable budgets, can disable insights stream |
| Persona drift (reviews become formulaic) | Medium | High | Include diverse voice examples, rotate opening framings |
| FAANG parallels become inaccurate | Low | Medium | Instruct "only cite parallels you're confident about" |
| Enriched fields slow down parser | Low | Low | Fields are optional, parser logic unchanged for missing fields |
| Dual-stream confuses sprint plan generator | Low | High | Sprint plan only sees findings stream (explicit separation) |

### Dependencies

- PR #293 merged (bridge v1 in main) — **in progress, CI running**
- Bridgebuilder persona definition accessible (loa-finn#24) — **available**
- No external service dependencies

### Constraints

- C-BRIDGE-001: ALWAYS use `/run sprint-plan` within bridge iterations
- C-BRIDGE-002: ALWAYS post Bridgebuilder review as PR comment
- C-BRIDGE-003: ALWAYS ensure GT claims cite file:line references
- C-BRIDGE-004: ALWAYS use YAML format for lore entries
- C-BRIDGE-005: ALWAYS include source bridge iteration and PR in vision entries

---

**Next Step**: `/architect` to create Software Design Document
