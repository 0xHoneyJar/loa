# Research: CLAUDE.md Context Loading Optimization

**Issue**: [#136 - chore: Slim CLAUDE.md to reduce token overhead](https://github.com/0xHoneyJar/loa/issues/136)
**Branch**: `research/claude-md-context-loading-136`
**Author**: Research Agent
**Date**: 2026-02-02
**Status**: Research Complete (v2 - Citations Corrected)

---

## 1. Problem Statement

Loa's CLAUDE.md ecosystem currently triggers a size warning:

```
Total: 41,803 chars
LOA:BEGIN...LOA:END (managed): 39,593 chars (95%)
PROJECT:BEGIN...PROJECT:END (user): 2,209 chars (5%)
```

This triggers the warning:
> ⚠️ Large CLAUDE.md will impact performance (41.0k chars > 40.0k)

**40K Threshold Origin**: This warning appears to originate from **Claude Code CLI output** (not official documentation). The exact source should be verified by examining Claude Code's source or CLI behavior. No official Anthropic documentation specifies a 40K character limit.

**Key Research Questions**:
1. Is this warning based on real performance degradation, or is it conservative guidance?
2. Are there Claude Code best practices about tiered/JIT loading for CLAUDE.md?
3. What's the actual token cost impact?

---

## 2. Research Findings

### 2.1 Official Claude Code Documentation

**Primary Sources**:
- [Claude Code Best Practices (Blog)](https://www.anthropic.com/engineering/claude-code-best-practices)
- [Claude Code Costs/Optimization](https://docs.anthropic.com/en/docs/claude-code/costs)
- [Effective Context Engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)

#### The Core Constraint (✅ Verified)

From the [Best Practices blog](https://www.anthropic.com/engineering/claude-code-best-practices):
> "During long sessions, Claude's context window can fill with irrelevant conversation, file contents, and commands. This can reduce performance and sometimes distract Claude."

#### CLAUDE.md Specific Guidance

| Guideline | Source | Status |
|-----------|--------|--------|
| Keep CLAUDE.md concise and human-readable | [Best Practices Blog](https://www.anthropic.com/engineering/claude-code-best-practices) | ✅ Verified |
| Aim for ~500 lines by including only essentials | [Costs Docs](https://docs.anthropic.com/en/docs/claude-code/costs) | ✅ Verified |
| CLAUDE.md loaded at session start | [Costs Docs](https://docs.anthropic.com/en/docs/claude-code/costs) | ✅ Verified |
| Skills load on-demand when invoked | [Costs Docs](https://docs.anthropic.com/en/docs/claude-code/costs) | ✅ Verified |

**Official Quote** (from [Costs Docs](https://docs.anthropic.com/en/docs/claude-code/costs)):
> "Your CLAUDE.md file is loaded into context at session start. If it contains detailed instructions for specific workflows (like PR reviews or database migrations), those tokens are present even when you're doing unrelated work."

> "Skills load on-demand only when invoked, so moving specialized instructions into skills keeps your base context smaller."

> "Aim to keep CLAUDE.md under ~500 lines by including only essentials."

#### What to Include (✅ Verified from Blog)

The [Best Practices blog](https://www.anthropic.com/engineering/claude-code-best-practices) mentions good candidates:
- Bash commands Claude can't guess
- Code style rules that differ from defaults
- Testing instructions and preferred test runners
- Repository etiquette (branch naming, PR conventions)
- Developer environment quirks (required env vars)

#### What to Exclude (⚠️ Recommended Practice - Not Official)

The following "exclude" items are **reasonable inferences** based on the "concise" guidance, but are not explicitly listed in official docs:

| ❌ Exclude (Recommended) | Rationale |
|--------------------------|-----------|
| Anything Claude can figure out by reading code | Redundant context |
| Standard language conventions | Claude already knows these |
| Detailed API documentation | Link to docs instead |
| Information that changes frequently | Maintenance burden |
| Long explanations or tutorials | Use skills for this |
| File-by-file descriptions | Redundant with code |

### 2.2 The 40K Threshold Analysis

**Finding**: No official Anthropic documentation specifies a 40K character limit.

The official guidance uses **~500 lines** as the recommendation (from [Costs Docs](https://docs.anthropic.com/en/docs/claude-code/costs)).

The 40K character threshold likely originates from:
- Claude Code CLI warning output (needs verification)
- Heuristic: ~500 lines × ~80 chars/line = ~40K chars
- Internal Anthropic guidelines not publicly documented

**Recommendation**: The **~500 lines** metric from official docs is more authoritative than the 40K character count.

### 2.3 Tiered Loading Approach (✅ Verified)

Claude Code explicitly supports a tiered approach:

| Tier | Mechanism | When Loaded | Use Case | Source |
|------|-----------|-------------|----------|--------|
| **CLAUDE.md** | Always loaded | Every session | Universal rules only | [Costs Docs](https://docs.anthropic.com/en/docs/claude-code/costs) |
| **Skills** | On-demand | When invoked | Domain knowledge, workflows | [Costs Docs](https://docs.anthropic.com/en/docs/claude-code/costs) |
| **Subagents** | Delegated | When invoked | Isolated tasks, research | [Subagents Docs](https://docs.anthropic.com/en/docs/claude-code/sub-agents) |

**Official Quote** (from [Costs Docs](https://docs.anthropic.com/en/docs/claude-code/costs)):
> "Skills load on-demand only when invoked, so moving specialized instructions into skills keeps your base context smaller."

**Official Quote** (from [Subagents Docs](https://docs.anthropic.com/en/docs/claude-code/sub-agents)):
> "Each subagent operates in its own context, preventing pollution of the main conversation and keeping it focused on high-level objectives."

### 2.4 The @import Behavior

**Status**: ⚠️ Not explicitly documented

The `@` import behavior is not clearly documented regarding eager vs lazy loading. Empirical verification recommended.

**Working assumption**: Imports are eagerly loaded when the parent file is loaded.

### 2.5 Context Management (✅ Verified)

From [Best Practices blog](https://www.anthropic.com/engineering/claude-code-best-practices):
> "During long sessions, Claude's context window can fill with irrelevant conversation, file contents, and commands. This can reduce performance and sometimes distract Claude."

From [Costs Docs](https://docs.anthropic.com/en/docs/claude-code/costs):
> "Clear between tasks: Use /clear to start fresh when switching to unrelated work. Stale context wastes tokens on every subsequent message."

**Custom Compaction** (from [Costs Docs](https://docs.anthropic.com/en/docs/claude-code/costs)):
> "Add custom compaction instructions: /compact Focus on code samples and API usage tells Claude what to preserve during summarization."

### 2.6 Compaction Behavior (✅ Verified)

From [Effective Context Engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents):
> "Compaction is the practice of taking a conversation nearing the context window limit, summarizing its contents, and reinitiating a new context window with the summary."

---

## 3. Root Cause Analysis

### 3.1 Why Loa's CLAUDE.md is Large

| Content Category | Est. Chars | % of Total | Required Every Session? |
|------------------|------------|------------|------------------------|
| Architecture overview | ~5,000 | 12% | ✅ Necessary for routing |
| Skill descriptions (13 skills) | ~8,000 | 19% | ❌ Should be skill-based |
| Protocol documentation | ~6,000 | 14% | ❌ Reference only |
| YAML config examples | ~6,000 | 14% | ❌ Should be in example file |
| Version notes (v1.x.0) | ~3,000 | 7% | ❌ Should be in changelog |
| Script documentation | ~4,000 | 10% | ❌ Help output exists |
| Command tables | ~3,000 | 7% | ⚠️ Partially necessary |
| Other | ~6,000 | 14% | Mixed |

**Line Count**: ~44K chars ÷ ~80 chars/line ≈ **550 lines** (exceeds ~500 line recommendation)

### 3.2 The Real Issue

Based on verified official guidance, the issues are:

1. **Instruction Dilution**: Large files make important rules harder to follow (reasonable inference from "concise" guidance)
2. **Token Waste**: Reference documentation consumes context that could be used for actual work (verified)
3. **No JIT Loading**: Skills should be used for workflow-specific instructions (verified)

---

## 4. Proposed Solutions

### Option A: Slim CLAUDE.md (Conservative)

**Approach**: Move reference documentation out, keep behavioral instructions.

**Target**: ~300 lines (~25K characters)

| Action | Content Moved | Savings |
|--------|---------------|---------|
| Move config examples | → `.loa.config.yaml.example` | ~6,000 |
| Move protocol details | → Keep pointers only | ~4,000 |
| Move version notes | → `CHANGELOG.md` | ~3,000 |
| Remove script examples | → Script help output | ~3,000 |
| Consolidate tables | → Single reference | ~1,500 |

**Pros**: Minimal change, backward compatible
**Cons**: Still loads 25KB every session, still above ~500 line target

### Option B: Tiered Architecture (Recommended)

**Approach**: Restructure to match Claude Code's official tiered model.

```
CLAUDE.md (essential only)
├── Core behavior rules (~3K)
├── Architecture overview (~2K)
├── Command routing (~2K)
└── @.claude/loa/CLAUDE.essential.md (~5K total, ~150 lines)

.claude/skills/{skill}/SKILL.md (on-demand)
├── discovering-requirements/SKILL.md (already exists)
├── implementing-tasks/SKILL.md (already exists)
├── etc. (all 13 skills already have SKILL.md)

.claude/loa/reference/ (new)
├── protocols.md (loaded via skill @import when needed)
├── config-examples.md
└── troubleshooting.md
```

**Target**: ~150 lines always-loaded (well under ~500 line recommendation)

**Pros**:
- Aligns with official Claude Code patterns
- Skill-based loading is explicitly recommended in docs
- Skills already exist in Loa - just need to move content there
- Future-proof as more skills are added

**Cons**:
- Larger refactor
- May need testing for edge cases
- Need to verify Claude's skill auto-loading reliability

### Option C: Dynamic Loading via Subagents (Experimental)

**Approach**: Use Claude Code's subagent delegation for heavy documentation.

When a query needs detailed protocol info:
1. Spawn subagent with specific protocol file
2. Subagent returns condensed answer
3. Main context stays clean

**Pros**: Maximum context efficiency (verified: subagents have isolated context)
**Cons**: More complex, latency overhead

---

## 5. Recommendation

### Phase 1: Immediate Wins (Option A)

**Quick win**: Move obvious reference content out
**Target**: ~300 lines
**Timeline**: 1 sprint

Actions:
1. Move YAML config examples to `.loa.config.yaml.example`
2. Move version notes to `CHANGELOG.md`
3. Remove script examples (use `--help` instead)
4. Consolidate redundant command tables
5. Add custom compaction instructions to preserve critical context

### Phase 2: Full Tiered Architecture (Option B)

**Target**: ~150 lines always-loaded
**Timeline**: 2-3 sprints

Actions:
1. Audit CLAUDE.loa.md content against official include criteria
2. Move skill-specific documentation into respective SKILL.md files
3. Create `.claude/loa/reference/` for lookup-only content
4. Update protocols to use JIT retrieval patterns
5. Test skill auto-loading reliability

---

## 6. Success Metrics

| Metric | Current | Phase 1 Target | Phase 2 Target |
|--------|---------|----------------|----------------|
| CLAUDE.md lines | ~550 | ~300 | ~150 |
| CLAUDE.md size | 44K chars | 25K chars | 12K chars |
| Est. tokens | ~11K | ~6K | ~3K |
| Below ~500 line recommendation | No | Yes | Yes |
| Instruction adherence | Baseline | Measure | Measure |

**Note**: "Instruction adherence" improvement claims require benchmark methodology to verify.

---

## 7. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Behavior regression | Comprehensive test suite before/after |
| Information loss | All content preserved, just relocated |
| User confusion | Clear migration guide |
| Skill loading failures | Fallback to inline content |
| Auto-loading unreliable | Test extensively, document manual invocation |

---

## 8. Open Questions for Follow-up

1. **Benchmark actual performance**: Does the reduction measurably improve response quality?
2. **Skill auto-loading reliability**: How reliably does Claude apply skills automatically?
3. **Import timing**: Is `@` import truly eager, or does it have any lazy characteristics?
4. **Context compaction interaction**: How does CLAUDE.md content survive `/compact`?
5. **Sandbox testing**: Per janitooor's comment, use sandbox infrastructure to actually benchmark
6. **40K source**: Document the exact CLI output or source that generates the 40K warning

---

## 9. Key Quotes from Official Documentation

### On CLAUDE.md Loading (✅ Verified)
> "Your CLAUDE.md file is loaded into context at session start. If it contains detailed instructions for specific workflows (like PR reviews or database migrations), those tokens are present even when you're doing unrelated work."
> — [Costs Docs](https://docs.anthropic.com/en/docs/claude-code/costs)

### On Line Limit (✅ Verified)
> "Aim to keep CLAUDE.md under ~500 lines by including only essentials."
> — [Costs Docs](https://docs.anthropic.com/en/docs/claude-code/costs)

### On Skills for Specialization (✅ Verified)
> "Skills load on-demand only when invoked, so moving specialized instructions into skills keeps your base context smaller."
> — [Costs Docs](https://docs.anthropic.com/en/docs/claude-code/costs)

### On Subagent Isolation (✅ Verified)
> "Each subagent operates in its own context, preventing pollution of the main conversation and keeping it focused on high-level objectives."
> — [Subagents Docs](https://docs.anthropic.com/en/docs/claude-code/sub-agents)

### On Context Degradation (✅ Verified)
> "During long sessions, Claude's context window can fill with irrelevant conversation, file contents, and commands. This can reduce performance and sometimes distract Claude."
> — [Best Practices Blog](https://www.anthropic.com/engineering/claude-code-best-practices)

### On Compaction (✅ Verified)
> "Compaction is the practice of taking a conversation nearing the context window limit, summarizing its contents, and reinitiating a new context window with the summary."
> — [Effective Context Engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)

---

## 10. References

### Primary Sources (✅ Verified URLs)
- [Claude Code Best Practices (Blog)](https://www.anthropic.com/engineering/claude-code-best-practices)
- [Claude Code Costs/Optimization](https://docs.anthropic.com/en/docs/claude-code/costs)
- [Claude Code Skills](https://docs.anthropic.com/en/docs/claude-code/skills)
- [Claude Code Subagents](https://docs.anthropic.com/en/docs/claude-code/sub-agents)

### Context Engineering
- [Effective Context Engineering for AI Agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- [Building with Agent SDK](https://www.anthropic.com/engineering/building-agents-with-the-claude-agent-sdk)

### Project References
- [GitHub Issue #136](https://github.com/0xHoneyJar/loa/issues/136) - Original issue
- [Loa CLAUDE.loa.md](.claude/loa/CLAUDE.loa.md) - Current implementation

---

## 11. Verification Status

This document was verified against official Anthropic documentation on 2026-02-02.

| Claim | Status | Action Taken |
|-------|--------|--------------|
| 40K character threshold | ⚠️ Unverified | Noted as CLI warning, not official docs |
| ~500 line recommendation | ✅ Verified | Added as primary metric |
| Skills load on-demand | ✅ Verified | Cited with source |
| CLAUDE.md loads at session start | ✅ Verified | Cited with source |
| Subagents have isolated context | ✅ Verified | Cited with source |
| Context degrades as it fills | ✅ Verified | Cited with source |
| Source URLs | 🔴 Fixed | Updated to correct URLs |
| Include/Exclude table | ⚠️ Partial | Marked exclude column as "Recommended" |

---

## Next Steps

1. ✅ Create PR with this research document
2. ✅ Citation corrections applied (v2)
3. Maintainer review
4. If approved, create implementation PRD based on Option A or B
5. Set up sandbox benchmark testing (per janitooor comment)
