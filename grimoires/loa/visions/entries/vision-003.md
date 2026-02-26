# Vision: Context Isolation as Prompt Injection Defense

**ID**: vision-003
**Source**: Bridge iteration 1 of bridge-20260214-e8fa94
**PR**: #324
**Date**: 2026-02-14T00:00:00Z
**Status**: Exploring
**Tags**: [security, prompt-injection, context-isolation]

## Insight

When merging persona instructions with system-provided context (reference documents, specs, code), the system content must be explicitly delimited and de-authorized to prevent prompt injection. A "context isolation wrapper" pattern achieves this:

1. **Persona directives first** — establishes the agent's identity and authority
2. **Delimiter** — visual and semantic boundary
3. **De-authorization header** — marks content as reference material only
4. **System content** — wrapped within the de-authorized section
5. **Authority reinforcement** — restates persona precedence after the context block

## Potential

Any multi-agent system where agents receive context from external sources (documents, APIs, user uploads) and agent personas define behavioral contracts. Particularly relevant for Flatline Protocol reviewer agents, Bridgebuilder review, and any RAG-augmented agent architecture.

## Connection Points

- Bridgebuilder finding: vision-003, severity 9/10
- Bridge: bridge-20260214-e8fa94, iteration 1
- FAANG parallel: Google Gemini grounding sections, OpenAI system prompt delimiters
- Active exploration: cycle-042 FR-4
