# Loa Lore Knowledge Base

Cultural and philosophical context for agent skills. Each entry provides naming context, architectural metaphors, and philosophical grounding that enriches AI agent interactions.

## Naming Lineage

The framework's Vodou terminology originates from William Gibson's Sprawl trilogy (*Neuromancer*, *Count Zero*, *Mona Lisa Overdrive*), which adapted Haitian Vodou through the anthropological work of Robert Tallant (*Voodoo in New Orleans*, 1946) and likely Maya Deren (*Divine Horsemen*, 1953). This is **narrative architecture** — coherent memetic frameworks that help humans and agents form consistent mental models as the ecosystem scales. See [docs/ecosystem-architecture.md](../../docs/ecosystem-architecture.md#naming--the-scholarly-chain) for the complete scholarly chain.

## Structure

```
.claude/data/lore/
├── index.yaml           # Registry with categories and tags
├── mibera/              # Network mysticism, Mibera cosmology
│   ├── core.yaml        # Core concepts: kaironic time, cheval, network mysticism
│   ├── cosmology.yaml   # Naming universe: Milady/Mibera duality, BGT triskelion
│   ├── rituals.yaml     # Processes as rituals: bridge loop, sprint ceremonies
│   └── glossary.yaml    # Term definitions for agent consumption
├── neuromancer/          # Gibson's Sprawl Trilogy
│   ├── concepts.yaml    # ICE, jacking in, cyberspace, the matrix
│   └── mappings.yaml    # Concept → Loa feature mappings
└── README.md            # This file
```

## Entry Schema

Every lore entry follows this schema:

```yaml
entries:
  - id: kebab-case-id        # Unique identifier
    term: "Display Name"      # Human-readable name
    short: "< 20 tokens"      # Inline reference (for PR comments, status messages)
    context: |                 # < 200 tokens — full understanding
      Multi-line description with philosophical
      and technical context.
    source: "provenance"       # Where this comes from (issue, article, RFC)
    tags: [tag1, tag2]         # From index.yaml tags list
    related: [other-id]        # Cross-references to other entries
    loa_mapping: "feature"     # Optional: what this maps to in Loa
```

## How to Reference Lore in Skills

### Loading Pattern

```
1. Read .claude/data/lore/index.yaml
2. Filter entries by relevant tags (e.g., "architecture" for /architect)
3. Load matching entries from category files
4. Use `short` field for inline references
5. Use `context` field when teaching or explaining
```

### Examples

**In PR reviews** (Bridgebuilder):
> This circuit breaker pattern embodies kaironic time — work ends when insight
> is exhausted, not when a timer expires.

**In status messages** (/loa):
> Bridge Loop: Iteration 2/3 — the refinement ceremony deepens.

**In PRD discovery** (/plan):
> The three-zone model reflects the Milady/Mibera duality — accessible
> surface, protected depth.

### Guidelines

- Use `short` field for casual inline references
- Use `context` field only when the user asks "why?" or when teaching
- Never force lore references — they should feel natural, not ornamental
- Prefer lore that illuminates engineering decisions over pure decoration
- Each skill should reference lore only when contextually appropriate
