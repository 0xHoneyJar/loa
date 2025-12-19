# Context Injector Library

This library provides patterns for spawning parallel research agents to query Hivemind content and inject organizational context into Loa phases.

---

## Overview

The context injector enables Loa to leverage organizational memory from Hivemind OS during phase execution. It uses parallel research agents to search ADRs, experiments, Learning Memos, and technical references, then synthesizes results for injection into agent prompts.

---

## Prerequisites

Before using context injection, verify:

```bash
# Check Hivemind connection
if [ -L ".hivemind" ] && [ -d ".hivemind/library" ]; then
    echo "HIVEMIND_STATUS:connected"
else
    echo "HIVEMIND_STATUS:not_connected"
fi
```

If not connected, context injection returns empty results and proceeds without blocking.

---

## Parallel Research Agent Pattern

When context injection is needed, spawn these agents in parallel using the Task tool:

### Agent 1: @decision-archaeologist

**Purpose**: Find relevant architectural decision records (ADRs)

**Search Paths**:
- `.hivemind/library/decisions/`
- `.hivemind/library/decisions/ADR-*.md`

**Input**: Keywords extracted from problem statement, project type

**Return Format**:
```markdown
## Relevant ADRs

### ADR-042: {Title}
- **Status**: Accepted
- **Summary**: {Brief description}
- **Relevance**: {Why this matters for current context}
- **Reference**: `.hivemind/library/decisions/ADR-042.md`

### ADR-015: {Title}
...
```

### Agent 2: @timeline-navigator

**Purpose**: Find past experiments and event records (ERRs)

**Search Paths**:
- `.hivemind/library/timeline/`
- `.hivemind/laboratory/experiments/`
- `.hivemind/library/timeline/ERR-*.md`

**Input**: Similar experiment types, domain keywords

**Return Format**:
```markdown
## Related Experiments

### ERR-2024-CubQuests-Beta
- **Outcome**: {Success/Partial/Failed}
- **Key Learning**: {What was discovered}
- **Relevance**: {How this applies to current work}
- **Reference**: `.hivemind/laboratory/experiments/ERR-2024-CubQuests-Beta.md`
```

### Agent 3: @technical-reference-finder

**Purpose**: Find architectural context, Learning Memos, ecosystem documentation

**Search Paths**:
- `.hivemind/library/ecosystem/`
- `.hivemind/library/knowledge/`
- `.hivemind/library/knowledge/Learning-Memos/`

**Input**: Technical domain keywords, component names

**Return Format**:
```markdown
## Technical References

### Learning Memo: {Title}
- **Pattern**: {Pattern description}
- **Context**: {When to apply}
- **Evidence**: {Supporting data}
- **Reference**: `.hivemind/library/knowledge/Learning-Memos/{file}.md`

### Ecosystem Doc: {Title}
- **Overview**: {Brief description}
- **Reference**: `.hivemind/library/ecosystem/{file}.md`
```

---

## Spawning Pattern

Use the Task tool to spawn parallel research agents:

```markdown
## Context Injection - Parallel Research

Spawn 3 parallel Explore agents to gather organizational context:

### Agent 1: Decision Archaeologist
Search `.hivemind/library/decisions/` for ADRs matching keywords: {keywords}
Return: List of relevant ADRs with summaries and references

### Agent 2: Timeline Navigator
Search `.hivemind/library/timeline/` and `.hivemind/laboratory/experiments/` for past experiments matching: {domain}
Return: List of related ERRs with outcomes and learnings

### Agent 3: Technical Reference Finder
Search `.hivemind/library/ecosystem/` and `.hivemind/library/knowledge/` for docs matching: {technical_keywords}
Return: List of Learning Memos and ecosystem docs with summaries
```

---

## Result Synthesis

After parallel agents return, synthesize results:

### Step 1: Deduplicate
- Remove duplicate references across agents
- Keep the most specific mention of each document

### Step 2: Rank by Relevance
- Prioritize ADRs that directly address the problem domain
- Weight experiments with similar scope higher
- Consider recency for Learning Memos

### Step 3: Format for Injection

```markdown
## Organizational Context

Based on Hivemind organizational memory:

### Relevant Decisions
- **ADR-042** establishes that {summary}. This informs {aspect of current work}.
- **ADR-015** recommends {pattern}. Consider applying to {context}.

### Past Experiments
- Previous experiment **ERR-2024-XXX** showed that {learning}.
  Success metric: {metric achieved}.

### Proven Patterns
- Learning Memo "{title}" suggests {pattern} when {condition}.
  Evidence: {brief evidence}.

### Technical Context
- {Ecosystem doc} provides foundation for {component}.

---
*Context injected from Hivemind OS. References verified at {timestamp}.*
```

---

## Integration Points

### Phase: PRD (`/plan-and-analyze`)

**When**: Before discovery questions
**Keywords**: From user's initial description, project type
**Injection Point**: PRD architect prompt prefix

```markdown
You are the PRD Architect...

## Organizational Context (Injected from Hivemind)

{Synthesized context}

---

Now proceed with discovery questions...
```

### Phase: Architecture (`/architect`)

**When**: Before design decisions
**Keywords**: From PRD technical requirements, component names
**Injection Point**: Architecture designer prompt prefix

### Phase: Implementation (`/implement`)

**When**: Before coding starts
**Keywords**: From sprint task descriptions, technical stack
**Injection Point**: Implementation engineer prompt prefix

### Phase: Review (`/review-sprint`)

**When**: Before code review
**Keywords**: Security patterns, past audit findings
**Injection Point**: Senior tech lead prompt prefix

---

## Graceful Fallback

The context injector is designed to fail gracefully in all scenarios. Phases should NEVER be blocked by context injection issues.

### Fallback Decision Tree

```
Check Hivemind Connection
         │
         ├─► Connected & Valid
         │      │
         │      └─► Proceed with context injection
         │             │
         │             ├─► Query succeeds → Inject context
         │             │
         │             └─► Query fails/times out
         │                    │
         │                    └─► Return empty results
         │                         Show: "Context unavailable"
         │                         Continue phase normally
         │
         ├─► Symlink Exists but Broken
         │      │
         │      └─► Show: "Hivemind symlink broken"
         │           Suggest: `/setup` to reconnect
         │           Return empty results
         │           Continue phase normally
         │
         └─► Not Connected
                │
                └─► Show: "Hivemind not connected"
                     Suggest: `/setup` to connect
                     Return empty results
                     Continue phase normally
```

### Connection Check Pattern

Before any context injection, run this check:

```bash
# Full connection validation
check_hivemind_connection() {
    # Check symlink exists
    if [ ! -L ".hivemind" ]; then
        echo "HIVEMIND_STATUS:not_connected"
        return 1
    fi

    # Check symlink target is valid
    if [ ! -d ".hivemind/library" ]; then
        echo "HIVEMIND_STATUS:broken_symlink"
        return 1
    fi

    # Check we can read content
    if [ ! -r ".hivemind/library" ]; then
        echo "HIVEMIND_STATUS:permission_denied"
        return 1
    fi

    echo "HIVEMIND_STATUS:connected"
    return 0
}
```

### Fallback Messages

**Not Connected**:
```markdown
**Notice**: Hivemind OS is not connected.

Proceeding without organizational context injection.

To enable context injection:
1. Run `/setup`
2. Select "Connect to Hivemind OS"
3. Provide path to hivemind-library

This phase will continue normally.
```

**Broken Symlink**:
```markdown
**Warning**: Hivemind symlink appears broken.

The `.hivemind/` symlink exists but the target is missing or invalid.

To fix:
1. Run `/setup` to reconfigure Hivemind connection
2. Or manually fix: `rm .hivemind && ln -s /path/to/hivemind-library .hivemind`

Proceeding without organizational context.
```

**Query Timeout**:
```markdown
**Notice**: Context query timed out.

Hivemind is connected but context queries took too long.
This may indicate a large knowledge base or slow filesystem.

Proceeding without organizational context.
Consider running `/ask` directly in Hivemind for detailed queries.
```

**Query Returns Empty**:
```markdown
**Info**: No relevant organizational context found.

Searched Hivemind for: {keywords}
No matching ADRs, experiments, or Learning Memos found.

This is normal for:
- New project domains
- Novel problem spaces
- First experiments in an area

Proceeding with PRD discovery.
```

### Return Value Pattern

Context injection should always return a result object:

```json
{
  "status": "connected|disconnected|error",
  "context_injected": true|false,
  "adrs_found": 0,
  "experiments_found": 0,
  "learnings_found": 0,
  "message": "Human-readable status message",
  "context_block": "## Organizational Context\n...|null"
}
```

When not connected or on error:
```json
{
  "status": "disconnected",
  "context_injected": false,
  "adrs_found": 0,
  "experiments_found": 0,
  "learnings_found": 0,
  "message": "Hivemind not connected. Proceeding without context.",
  "context_block": null
}
```

### Non-Blocking Guarantee

**CRITICAL**: Context injection must NEVER block phase execution.

```markdown
## Implementation Rule

1. Set timeout for all Hivemind queries (30 seconds max)
2. Catch all errors and return empty results
3. Log warnings but don't throw exceptions
4. Phase continues regardless of injection outcome
5. User sees notice but workflow proceeds

## Error Handling

try:
    context = inject_hivemind_context(keywords)
except TimeoutError:
    log_warning("Context injection timed out")
    context = empty_context_result()
except FileNotFoundError:
    log_warning("Hivemind path not found")
    context = empty_context_result()
except Exception as e:
    log_warning(f"Context injection failed: {e}")
    context = empty_context_result()

# Phase ALWAYS continues
proceed_with_phase(context)
```

### Repair Suggestions

When fallback is triggered, suggest repair steps:

| Issue | Suggestion |
|-------|------------|
| Not connected | Run `/setup` and enable Hivemind |
| Broken symlink | Run `/setup` to reconfigure, or fix manually |
| Permission denied | Check filesystem permissions on hivemind-library |
| Query timeout | Try `/ask` directly in Hivemind for complex queries |
| Empty results | Normal for new domains; proceed with discovery |

---

## Usage Example

```markdown
## Before Phase Start

1. Check Hivemind connection status
2. If connected:
   a. Extract keywords from current context
   b. Spawn parallel research agents
   c. Wait for results (with timeout)
   d. Synthesize and inject context
3. If not connected:
   a. Log notice
   b. Continue without context injection

## Keyword Extraction

From problem statement:
- Extract noun phrases (technical terms)
- Include project type
- Include experiment hypothesis keywords (if linked)

Example:
- Input: "Design quest system for Set & Forgetti vault integration"
- Keywords: ["quest", "Set & Forgetti", "vault", "integration", "game-design"]
```

---

## Keyword Extraction

Keyword extraction is critical for effective context queries. Extract relevant terms from multiple sources to build a comprehensive query.

### Extraction Sources

#### 1. Problem Statement (PRD Phase)

Extract from user's initial description or existing PRD:

```markdown
## Problem Statement Keyword Extraction

Input: "{user_description}"

Steps:
1. Identify noun phrases (technical terms, product names, features)
2. Extract action verbs (integrate, design, build, migrate)
3. Identify domain indicators (vault, quest, contract, indexer)
4. Filter common words (the, a, an, is, are, to, for, with)

Example:
- Input: "Design a quest system that rewards users for staking in Set & Forgetti vaults"
- Extracted: ["quest", "rewards", "staking", "Set & Forgetti", "vaults", "game-design"]
```

#### 2. Project Type

Always include project type as a keyword:

| Project Type | Additional Keywords |
|--------------|---------------------|
| `frontend` | UI, component, design system, user experience |
| `contracts` | smart contract, solidity, security, audit |
| `indexer` | Envio, subgraph, events, blockchain data |
| `game-design` | quest, badge, activity, XP, engagement |
| `backend` | API, server, database, authentication |
| `cross-domain` | integration, ecosystem, multi-system |

#### 3. Experiment Context (If Linked)

If an experiment is linked in `integration-context.md`:

```markdown
## Experiment Keyword Extraction

From linked experiment:
- Hypothesis keywords: {extract key terms from hypothesis}
- Success criteria keywords: {extract measurable terms}
- User Truth Canvas themes: {extract user problem themes}

Example:
- Hypothesis: "Adding vault-based quests will increase S&F TVL by 20%"
- Keywords: ["vault", "quests", "TVL", "engagement", "DeFi"]
```

#### 4. Technical Stack

Extract from existing context or PRD:

```markdown
## Technical Stack Keywords

From project configuration:
- Framework: Next.js, React, Solidity
- Infrastructure: Envio, Supabase, Vercel
- Protocols: Berachain, ERC-20, ERC-721

These inform technical reference searches.
```

### Keyword Filtering

Remove low-value terms:

```markdown
## Stop Words (Filter Out)

Common words to exclude:
- Articles: the, a, an
- Prepositions: to, for, with, from, in, on, at
- Conjunctions: and, or, but
- Verbs (generic): is, are, was, were, be, have, has, do, does
- Pronouns: it, this, that, we, they, I, you

Keep domain-specific terms even if common in English:
- "contract" (smart contract context)
- "state" (application state)
- "event" (blockchain event)
```

### Keyword Weighting

Prioritize keywords for query relevance:

```markdown
## Keyword Priority

High Priority (use in all agent queries):
- Brand names: CubQuests, Set & Forgetti, Henlo, Mibera
- Domain terms: quest, vault, contract, indexer
- Action terms: integrate, migrate, design

Medium Priority (use in specific agents):
- Technical terms: API, component, handler
- Pattern names: hooks, state management

Low Priority (background context):
- Generic tech: frontend, backend, database
- Common patterns: CRUD, REST, GraphQL
```

### Keyword Combination Strategy

```markdown
## Query Construction

For @decision-archaeologist:
- Primary: Domain keywords + Action keywords
- Example: "quest integration vault"

For @timeline-navigator:
- Primary: Brand names + Domain keywords
- Example: "CubQuests Set & Forgetti"

For @technical-reference-finder:
- Primary: Technical keywords + Pattern keywords
- Example: "Envio indexer handler events"
```

### Implementation Pattern

```markdown
## Keyword Extraction Flow

1. **Gather Sources**
   - Read user description / problem statement
   - Read project type from `integration-context.md`
   - Read experiment details (if linked)
   - Identify technical stack mentions

2. **Extract Raw Keywords**
   - Parse each source for noun phrases
   - Identify technical terms
   - Collect brand/product names

3. **Filter and Deduplicate**
   - Remove stop words
   - Merge duplicates
   - Normalize case (lowercase for matching)

4. **Categorize and Weight**
   - Assign priority levels
   - Group by agent target

5. **Return Keyword Set**
   ```json
   {
     "high_priority": ["quest", "vault", "Set & Forgetti"],
     "medium_priority": ["integration", "rewards", "staking"],
     "low_priority": ["frontend", "Next.js"],
     "brands": ["CubQuests", "Set & Forgetti"],
     "domains": ["game-design", "DeFi"]
   }
   ```
```

---

## Configuration

Context injection behavior can be influenced by `integration-context.md`:

```markdown
## Context Injection Settings

- **Max Results Per Agent**: 5
- **Query Timeout**: 30 seconds
- **Fallback Behavior**: Continue without blocking
- **Priority Sources**: ADRs > Experiments > Learning Memos
```

---

*Library maintained by Loa Framework*
*Pattern based on Hivemind `/ask` command*
