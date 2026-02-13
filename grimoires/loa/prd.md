# PRD: Harness Engineering Lit Review — Trail of Bits + OpenAI Adaptations

> Source: [#297](https://github.com/0xHoneyJar/loa/issues/297) — Trail of Bits and OpenAI harness engineering lit review
> Author: Literature review + gap analysis
> Cycle: cycle-011

## 1. Problem Statement

Issue #297 asks: "check to see if there is anything that loa can learn from, adopt, adapt, or tweak our current harness" based on two external sources:

1. **[Trail of Bits — claude-code-config](https://github.com/trailofbits/claude-code-config)**: Opinionated defaults, sandboxing, hooks, deny rules, and workflow patterns for Claude Code in professional environments.
2. **[OpenAI — Harness Engineering](https://openai.com/index/harness-engineering/)**: How OpenAI built an internal product with zero manually-written code using Codex agents across 1M lines and 1,500 PRs.

Loa already implements many patterns these sources describe (structured memory, architectural constraints, quality gates, autonomous execution), but gaps exist in **safety hooks**, **deny rules**, **premature-exit detection**, **CLAUDE.md token efficiency**, and **mechanical invariant enforcement**.

> Sources: Issue #297 body, Trail of Bits README, OpenAI harness engineering blog, OpenAI AGENTS.md documentation

## 2. Literature Review Summary

### 2.1 Trail of Bits — Key Patterns

| Pattern | Description | Loa Status |
|---------|-------------|------------|
| **3-Layer Sandboxing** | `/sandbox` + deny rules + devcontainer | No sandboxing guidance |
| **PreToolUse Safety Hooks** | Block `rm -rf`, force-push, push to main | Loa has ICE but not hook-based |
| **Deny Rules** | Block reads/writes to `.ssh`, `.aws`, `.kube`, credentials | Not implemented |
| **Stop Hook** | Detect premature exit rationalizations | Not implemented |
| **Visual Status Line** | Context %, cost, model, branch, cache hit % | Not implemented |
| **PostToolUse Audit Log** | Timestamp, action, command, exit status | Partial (trajectory, but not tool-level) |
| **Toolchain Enforcement** | Hooks enforce correct package manager, linters | Not hook-based |
| **CLAUDE.md Conciseness** | "Only unexpected things"; layered global + project | Loa's is 757 lines (could optimize) |
| **`cleanupPeriodDays: 365`** | Keep conversation history longer for `/insights` | Not configured |
| **Function Length Limits** | <50 lines (Python), <80 (JS/TS), complexity <5 | Not enforced |

### 2.2 OpenAI Harness Engineering — Key Patterns

| Pattern | Description | Loa Status |
|---------|-------------|------------|
| **AGENTS.md as Map** | ~100 lines, pointers to deeper sources | Loa uses @import but still large |
| **Architectural Invariants** | Custom linters enforce dependency directions, naming, file size | constraints.json exists but limited |
| **Repository-Local Context** | All context legible to agents within repo | Loa does this well (grimoire) |
| **Depth-First Building** | Break goals into building blocks | Loa does this (sprint decomposition) |
| **Continuous Refactoring** | Automated refactoring PRs, reviewed in <1 min | Not implemented |
| **Mechanical Enforcement** | Golden principles enforced by linters/tests | Partial (constraints.json) |
| **Automerge Refactoring** | Low-risk PRs merged automatically | Not implemented |

### 2.3 Shared Insights (Both Sources)

| Insight | Detail |
|---------|--------|
| **Hooks > System Prompt** | Blocking at decision points is more reliable than instructions alone |
| **Context is a Resource** | Monitor and manage actively; split when approaching limits |
| **Documentation = Map** | Point to sources of truth, don't replicate them |
| **Enforce Mechanically** | Rules without enforcement become suggestions |
| **Audit Everything** | Log mutations for post-session review |

## 3. Gap Analysis — What Loa Should Adopt

### Priority 1: ADOPT — Safety Hooks (High Impact, Low Effort)

**Source**: Trail of Bits `hooks/` directory

Loa has hook infrastructure (`.claude/hooks/`) but only uses it for post-compact recovery and memory. Trail of Bits uses hooks for safety:

| Hook | Event | Purpose |
|------|-------|---------|
| `block-rm-rf.sh` | `PreToolUse:Bash` | Block `rm -rf` — suggest `trash` instead |
| `block-force-push.sh` | `PreToolUse:Bash` | Block `git push --force` to main/master |
| `block-reset-hard.sh` | `PreToolUse:Bash` | Block `git reset --hard` without confirmation |
| `audit-mutations.sh` | `PostToolUse:Bash` | Log destructive commands to `.run/audit.jsonl` |

**Why**: Loa's `run-mode-ice.sh` provides some protection during autonomous mode, but hooks provide defense-in-depth that works in ALL modes (interactive, autonomous, simstim). Hooks are structured prompt injection at decision points — more reliable than system prompt instructions.

**Loa adaptation**: Add to `.claude/hooks/` and reference from `settings.hooks.json`. Users opt-in during `/mount` or `/loa setup`.

### Priority 2: ADOPT — Deny Rules for Sensitive Files (High Impact, Low Effort)

**Source**: Trail of Bits `settings.json`

Block agent access to credential stores and sensitive configuration:

```json
{
  "permissions": {
    "deny": [
      "Read(~/.ssh/**)", "Edit(~/.ssh/**)",
      "Read(~/.aws/**)", "Edit(~/.aws/**)",
      "Read(~/.kube/**)", "Edit(~/.kube/**)",
      "Read(~/.gnupg/**)", "Edit(~/.gnupg/**)",
      "Read(~/.npmrc)", "Edit(~/.npmrc)",
      "Read(~/.git-credentials)", "Edit(~/.git-credentials)",
      "Edit(~/.bashrc)", "Edit(~/.zshrc)"
    ]
  }
}
```

**Why**: Loa agents operate in autonomous mode for extended periods. A single hallucinated `cat ~/.ssh/id_rsa` could expose private keys. Deny rules are the ultimate backstop — they operate at the Claude Code platform level, not the prompt level.

**Loa adaptation**: Ship recommended deny rules in `.claude/hooks/settings.hooks.json` (or a new `settings.deny.json`). `/mount` and `/loa setup` offer to install them.

### Priority 3: ADAPT — Stop Hook for Premature Exit Detection (Medium Impact, Medium Effort)

**Source**: Trail of Bits Stop hook pattern

Add a `Stop` hook that detects when the agent rationalizes incomplete work:

```bash
# Patterns to detect:
# "I'll defer to a follow-up"
# "This can be addressed in a future sprint"
# "The remaining work is minimal"
# etc.
```

**Why**: In `/run sprint-plan` and `/run-bridge`, the agent sometimes declares completion when work is partially done. A Stop hook could inject a reminder: "Check your acceptance criteria before stopping."

**Loa adaptation**: The hook checks `.run/sprint-plan-state.json` — if state is `RUNNING` and current sprint is not null, inject a reminder to verify completion before allowing stop.

### Priority 4: ADAPT — CLAUDE.md Token Optimization (Medium Impact, Medium Effort)

**Source**: Both — Trail of Bits "only unexpected things", OpenAI "navigable map ~100 lines"

Loa's `CLAUDE.loa.md` is 757 lines. Trail of Bits and OpenAI both emphasize conciseness:

> *"You want to put things that are 'unexpected', surprising or otherwise unknowable to the AI model."* — OpenAI community

> *"Documentation should function as a navigable map rather than a manual."* — OpenAI harness engineering

**Current structure**: CLAUDE.loa.md contains full protocol descriptions, configuration examples, and detailed explanations that could live in reference files.

**Proposal**: Reduce CLAUDE.loa.md to ~200-300 lines by:
1. Moving detailed config examples to `.claude/loa/reference/`
2. Converting verbose protocol descriptions to "see: `.claude/protocols/X.md`" pointers
3. Keeping only: constraints, zone model, workflow commands, and "unexpected" rules
4. Measuring token impact before/after

### Priority 5: ADAPT — PostToolUse Audit Logging (Medium Impact, Low Effort)

**Source**: Trail of Bits `PostToolUse` hooks

Log tool mutations to `.run/audit.jsonl` for post-session review:

```json
{"ts":"2026-02-13T10:05:00Z","tool":"Bash","command":"git push","exit":0,"cwd":"/home/user/repo"}
{"ts":"2026-02-13T10:05:01Z","tool":"Write","file":"src/auth.ts","bytes":1234}
```

**Why**: Loa has trajectory files but they track skill-level events, not individual tool calls. During autonomous mode, knowing exactly what commands ran and what files were written provides an audit trail for post-session review.

**Loa adaptation**: Add `PostToolUse:Bash` and `PostToolUse:Write` hooks that append to `.run/audit.jsonl`. Readable via `/run-status` or post-session review.

### Priority 6: TWEAK — Mechanical Invariant Enforcement (Low Impact, High Effort)

**Source**: OpenAI's architectural invariants + custom linters

Loa has `constraints.json` and NEVER/ALWAYS rules in CLAUDE.md, but these are prompt-level only. OpenAI enforces invariants with custom linters and structural tests.

**Proposal**: Add a `.claude/scripts/lint-invariants.sh` that mechanically validates:
- No application code outside of `/implement` skill invocation directories
- No `.claude/` files modified (except overrides)
- constraint.json rules have corresponding test coverage
- CLAUDE.loa.md hash matches expected (integrity check already exists)

**Why**: Rules without mechanical enforcement become suggestions. This is the "golden principles" pattern from OpenAI — opinionated rules enforced by tools, not just instructions.

## 4. Out of Scope

| Item | Reason |
|------|--------|
| **Sandboxing guidance** | Platform-level concern; Loa is a framework, not a runtime |
| **Local model support** | Interesting but orthogonal to harness improvements |
| **MCP server recommendations** | Already covered by Loa's existing MCP patterns |
| **Automerge for refactoring** | Requires CI/CD integration beyond Loa's scope |
| **Continuous automated refactoring** | Novel concept but too large for one cycle |
| **Function length/complexity limits** | Project-specific; should be in project CLAUDE.md not framework |

## 5. Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Safety hooks installed | 4 hooks shipping in `.claude/hooks/` | File count |
| Deny rules template | 1 settings template with recommended rules | File exists |
| CLAUDE.loa.md token reduction | 30-50% fewer tokens | `wc -w` before/after |
| Audit log coverage | Bash + Write mutations logged | Hook fires on tool use |
| Stop hook prevents premature exits | Tested in /run mode | Manual validation |

## 6. Risks

| Risk | Mitigation |
|------|------------|
| Hooks slow down interactive mode | Hooks are lightweight shell scripts (<10ms); benchmark before shipping |
| Deny rules block legitimate operations | Ship as recommended, not required; `/loa setup` asks before installing |
| CLAUDE.md optimization loses critical context | Measure token impact; keep all content accessible via reference files |
| Stop hook false positives | Only activate when `.run/sprint-plan-state.json` state=RUNNING |

## 7. References

- [Trail of Bits — claude-code-config](https://github.com/trailofbits/claude-code-config) — Opinionated Claude Code defaults
- [OpenAI — Harness Engineering](https://openai.com/index/harness-engineering/) — Agent-first development with Codex
- [OpenAI — AGENTS.md Custom Instructions](https://developers.openai.com/codex/guides/agents-md/) — Hierarchical agent configuration
- [Parallel.ai — What is an Agent Harness](https://parallel.ai/articles/what-is-an-agent-harness) — Formal definition and components
