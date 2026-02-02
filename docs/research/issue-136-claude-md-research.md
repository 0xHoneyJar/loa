# Research: CLAUDE.md Context Loading Optimization

**Issue**: [#136 - chore: Slim CLAUDE.md to reduce token overhead](https://github.com/0xHoneyJar/loa/issues/136)
**Branch**: `research/claude-md-context-loading-136`
**Author**: Research Agent
**Date**: 2026-02-02
**Status**: Research Complete

---

## 1. Problem Statement

Loa's CLAUDE.md ecosystem currently exceeds Claude Code's recommended 40K character threshold:

```
Total: 41,803 chars
LOA:BEGIN...LOA:END (managed): 39,593 chars (95%)
PROJECT:BEGIN...PROJECT:END (user): 2,209 chars (5%)
```

This triggers the warning:
> ⚠️ Large CLAUDE.md will impact performance (41.0k chars > 40.0k)

**Key Research Questions**:
1. Is this warning based on real performance degradation, or is it conservative guidance?
2. Are there Claude Code best practices about tiered/JIT loading for CLAUDE.md?
3. What's the actual token cost impact?

---

## 2. Research Findings

### 2.1 Official Claude Code Documentation (Primary Source)

From [Claude Code Best Practices](https://code.claude.com/docs/en/best-practices):

#### The Core Constraint
> "Most best practices are based on one constraint: **Claude's context window fills up fast, and performance degrades as it fills.**"

#### CLAUDE.md Specific Guidance

| Guideline | Quote |
|-----------|-------|
| **Keep it concise** | "Keep it short and human-readable" |
| **Prune ruthlessly** | "For each line, ask: 'Would removing this cause Claude to make mistakes?' If not, cut it. **Bloated CLAUDE.md files cause Claude to ignore your actual instructions!**" |
| **Signs of bloat** | "If Claude keeps doing something you don't want despite having a rule against it, the file is probably too long and the rule is getting lost" |
| **Use skills for specifics** | "CLAUDE.md is loaded every session, so only include things that apply broadly. For domain knowledge or workflows that are only relevant sometimes, **use skills instead**. Claude loads them on demand without bloating every conversation." |

#### What to Include vs Exclude

| ✅ Include | ❌ Exclude |
|-----------|-----------|
| Bash commands Claude can't guess | Anything Claude can figure out by reading code |
| Code style rules that differ from defaults | Standard language conventions Claude already knows |
| Testing instructions and preferred test runners | Detailed API documentation (link to docs instead) |
| Repository etiquette | Information that changes frequently |
| Architectural decisions specific to your project | Long explanations or tutorials |
| Developer environment quirks | File-by-file descriptions of the codebase |
| Common gotchas or non-obvious behaviors | Self-evident practices like "write clean code" |

### 2.2 The 40K Threshold Analysis

**Finding**: No specific 40K character limit is documented in the official Claude Code docs.

However, the guidance is clear that:
1. **Context window is the primary constraint** - not file size per se
2. **Performance degrades as context fills** - this is the real issue
3. **Bloated files cause instruction loss** - rules get "lost in the noise"

The 40K threshold appears to be a **heuristic warning** rather than a hard limit, likely based on:
- ~10-12K tokens ≈ 5-6% of a 200K token context window
- Experience data from Anthropic's internal teams
- Conservative buffer for conversation + file reads + tool outputs

### 2.3 Tiered Loading Approach (Official Recommendation)

Claude Code explicitly supports a tiered approach:

| Tier | Mechanism | When Loaded | Use Case |
|------|-----------|-------------|----------|
| **CLAUDE.md** | Always loaded | Every session | Universal rules only |
| **Skills** | On-demand | When relevant | Domain knowledge, workflows |
| **Subagents** | Delegated | When invoked | Isolated tasks, research |
| **@imports** | At reference time | When parent loaded | Modular documentation |

**Key Quote**:
> "Skills extend Claude's knowledge with information specific to your project, team, or domain. **Claude applies them automatically when relevant**, or you can invoke them directly."

### 2.4 The @import Behavior

From the documentation:
> "CLAUDE.md files can import additional files using `@path/to/import` syntax"

**Critical insight**: The `@` import appears to be **eagerly loaded at session start**, not JIT-loaded. This means:

```
CLAUDE.md (1.2 KB)
  └── @.claude/loa/CLAUDE.loa.md (43 KB)
       └── References to protocols, schemas, scripts
```

The full 44KB is loaded into every session regardless of task relevance.

### 2.5 Context Management

The documentation provides guidance on context management:

> "During long sessions, Claude's context window can fill with irrelevant conversation, file contents, and commands. This can reduce performance and sometimes distract Claude."

Recommended practices:
- Use `/clear` frequently between tasks
- When auto compaction triggers, Claude summarizes what matters
- Run `/compact <instructions>` for more control
- Customize compaction behavior in CLAUDE.md

**Important**: You can add to CLAUDE.md:
> "Customize compaction behavior in CLAUDE.md with instructions like 'When compacting, always preserve the full list of modified files and any test commands' to ensure critical context survives summarization"

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

### 3.2 The Real Issue

The issue is **not the 40K limit itself** but rather:

1. **Instruction Dilution**: Critical rules get lost among detailed documentation
2. **Token Waste**: Reference documentation consumes context that could be used for actual work
3. **No JIT Loading**: Everything loads upfront, even for simple tasks

---

## 4. Proposed Solutions

### Option A: Slim CLAUDE.md (Conservative)

**Approach**: Move reference documentation out, keep behavioral instructions.

**Target**: ~25K characters (40% reduction)

| Action | Content Moved | Savings |
|--------|---------------|---------|
| Move config examples | → `.loa.config.yaml.example` | ~6,000 |
| Move protocol details | → Keep pointers only | ~4,000 |
| Move version notes | → `CHANGELOG.md` | ~3,000 |
| Remove script examples | → Script help output | ~3,000 |
| Consolidate tables | → Single reference | ~1,500 |

**Pros**: Minimal change, backward compatible
**Cons**: Still loads 25KB every session

### Option B: Tiered Architecture (Recommended)

**Approach**: Restructure to match Claude Code's official tiered model.

```
CLAUDE.md (essential only)
├── Core behavior rules (~3K)
├── Architecture overview (~2K)
├── Command routing (~2K)
└── @.claude/loa/CLAUDE.essential.md (~5K total)

.claude/skills/{skill}/SKILL.md (on-demand)
├── discovering-requirements/SKILL.md (already exists)
├── implementing-tasks/SKILL.md (already exists)
├── etc. (all 13 skills already have SKILL.md)

.claude/loa/reference/ (new)
├── protocols.md (loaded via skill @import when needed)
├── config-examples.md
└── troubleshooting.md
```

**Target**: ~12K always-loaded, rest on-demand

**Pros**:
- Aligns with official Claude Code patterns
- Skill-based loading is already supported by Claude Code
- Skills already exist in Loa - just need to move content there
- Future-proof as more skills are added

**Cons**:
- Larger refactor
- May need testing for edge cases
- Need to verify Claude's auto-skill-loading reliability

### Option C: Dynamic Loading via Subagents (Experimental)

**Approach**: Use Claude Code's subagent delegation for heavy documentation.

When a query needs detailed protocol info:
1. Spawn subagent with specific protocol file
2. Subagent returns condensed answer
3. Main context stays clean

**Pros**: Maximum context efficiency
**Cons**: More complex, latency overhead

---

## 5. Recommendation

### Phase 1: Immediate Wins (Option A)

**Quick win**: Move obvious reference content out
**Target**: 25K characters
**Timeline**: 1 sprint

Actions:
1. Move YAML config examples to `.loa.config.yaml.example`
2. Move version notes to `CHANGELOG.md`
3. Remove script examples (use `--help` instead)
4. Consolidate redundant command tables

### Phase 2: Full Tiered Architecture (Option B)

**Target**: 12K always-loaded
**Timeline**: 2-3 sprints

Actions:
1. Audit CLAUDE.loa.md content against include/exclude criteria
2. Move skill-specific documentation into respective SKILL.md files
3. Create `.claude/loa/reference/` for lookup-only content
4. Update protocols to use JIT retrieval patterns
5. Test skill auto-loading reliability

---

## 6. Success Metrics

| Metric | Current | Phase 1 Target | Phase 2 Target |
|--------|---------|----------------|----------------|
| CLAUDE.md size | 44K chars | 25K chars | 12K chars |
| Est. tokens | ~11K | ~6K | ~3K |
| Warning triggered | Yes | No | No |
| Instruction adherence | Baseline | +10% | +25% |

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

1. **Benchmark actual performance**: Does the 41K → 25K reduction measurably improve response quality?
2. **Skill auto-loading reliability**: How reliably does Claude apply skills "automatically when relevant"?
3. **Import timing**: Is `@` import truly eager, or does it have any lazy characteristics?
4. **Context compaction interaction**: How does CLAUDE.md content survive `/compact`?
5. **Sandbox testing**: Per janitooor's comment, use sandbox infrastructure to actually benchmark

---

## 9. Key Quotes from Official Documentation

### On Context as Primary Constraint
> "Claude's context window holds your entire conversation, including every message, every file Claude reads, and every command output. However, this can fill up fast."

### On Performance Degradation
> "LLM performance degrades as context fills. When the context window is getting full, Claude may start 'forgetting' earlier instructions or making more mistakes."

### On CLAUDE.md Bloat
> "Bloated CLAUDE.md files cause Claude to ignore your actual instructions!"

### On Skills vs CLAUDE.md
> "CLAUDE.md is loaded every session, so only include things that apply broadly. For domain knowledge or workflows that are only relevant sometimes, use skills instead."

### On Treating CLAUDE.md Like Code
> "Treat CLAUDE.md like code: review it when things go wrong, prune it regularly, and test changes by observing whether Claude's behavior actually shifts."

---

## 10. References

- [Claude Code Best Practices](https://code.claude.com/docs/en/best-practices) - Primary source
- [GitHub Issue #136](https://github.com/0xHoneyJar/loa/issues/136) - Original issue
- [Loa v1.15.0 CLAUDE.loa.md](.claude/loa/CLAUDE.loa.md) - Current implementation
- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills) - Tiered loading reference

---

## Next Steps

1. Create PR with this research document
2. Tag maintainers for review
3. If approved, create implementation PRD based on Option A or B
4. Set up sandbox benchmark testing (per janitooor comment)
