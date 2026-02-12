# Hive Onboarding Analysis: Lessons for Loa

**Source**: [adenhq/hive](https://github.com/adenhq/hive) (Apache 2.0, YC-backed, 7K+ stars)
**Date**: 2026-02-12
**Status**: Living Document
**Purpose**: Competitive analysis of Hive's user onboarding flows to identify actionable improvements for Loa.

---

## Executive Summary

Hive is a goal-driven, self-improving agent framework built by Aden (YC). While architecturally different from Loa (Hive builds autonomous agents; Loa enhances developer workflows), both frameworks solve the same meta-problem: **getting a new user from zero to productive inside an AI-augmented coding environment**.

Hive's onboarding has 5 notable patterns Loa doesn't have: an interactive quickstart with dependency/credential setup, a meta-orchestrator menu as the primary entry point, a dedicated credential management skill, use-case qualification ("is this the right tool?"), and multi-IDE skill mirroring. Loa's onboarding has 4 patterns Hive doesn't: visual journey tracking ("you are here"), auto-state detection across commands, enforced quality gates, and multi-model adversarial review.

**Key takeaway**: Loa's _navigation_ UX (Golden Path) is superior, but Hive's _first-5-minutes_ UX (quickstart, credential setup, immediate menu) is more polished. The highest-ROI improvements are: (1) interactive quickstart with LLM key validation, (2) AskUserQuestion menu in `/loa`, and (3) a `/loa setup` credential wizard.

---

## Framework Comparison

### Identity

| Dimension | Hive | Loa |
|-----------|------|-----|
| **Purpose** | Build autonomous, self-improving AI agents | Enhance developer workflows with AI agents |
| **User** | Agent builders (deploy agents for business processes) | Developers (plan, build, review, ship code) |
| **Primary interface** | 7 slash commands + CLI (`hive tui/run`) | 5 Golden Path + 43 truename commands |
| **Architecture** | Goal -> Graph -> Nodes -> Edges -> Judge loop | PRD -> SDD -> Sprint -> Implement -> Review -> Audit |
| **Language** | Python 3.11+ | Shell/YAML (framework), any (app code) |
| **License** | Apache 2.0 | AGPL-3.0 |
| **IDE support** | Claude Code, Cursor, Opencode | Claude Code only |
| **Model support** | Any via LiteLLM | Claude (primary), GPT (Flatline review) |

### Onboarding Flow Comparison

```
HIVE                                    LOA
────                                    ───
quickstart.sh (interactive)             curl mount-loa.sh (silent)
  ├── Check Python 3.11+                 ├── Check git repo
  ├── Install uv + deps                  ├── Fetch .claude/ from upstream
  ├── Configure LLM keys (interactive)   ├── Create grimoires/loa/
  ├── Set up credential store            ├── Generate .loa.config.yaml
  └── Verify everything works            └── Show next-steps message

/hive (AskUserQuestion menu)            /loa (status + journey bar)
  ├── Build a new agent                   ├── Health check
  ├── Test existing agent                 ├── State detection
  ├── Learn concepts                      ├── "You are here" visualization
  ├── Optimize design                     └── Suggested next command
  ├── Set up credentials
  └── Debug failing agent

/hive-create (step-by-step wizard)      /plan (3-phase auto-chain)
  ├── Choose: scratch vs template         ├── /plan-and-analyze (PRD)
  ├── Qualify use case                    ├── /architect (SDD)
  ├── Define goal + criteria              └── /sprint-plan (sprints)
  ├── Add nodes (with tool validation)
  ├── Connect edges
  └── Finalize + export

/hive-test (iterative loop)             /build + /review
  ├── Generate test scenarios             ├── /implement sprint-N
  ├── Execute                             ├── /review-sprint
  ├── Analyze failures                    ├── /audit-sprint
  ├── Fix                                 └── Loop until approved
  └── Resume from checkpoint

/hive-credentials (dedicated)           (no equivalent)
  ├── Detect missing creds
  ├── OAuth / API key / Advanced
  ├── Health check endpoints
  └── Encrypted store
```

---

## What Loa Can Learn

### 1. Interactive Quickstart with Credential Setup

**What Hive does**: `quickstart.sh` is a 900+ line interactive script that checks Python version, installs dependencies, prompts for LLM API keys, validates them, sets up an encrypted credential store, and verifies everything works. Uses colored output, progress indicators, and `prompt_yes_no`/`prompt_choice` helpers.

**What Loa does**: `mount-loa.sh` is a silent curl-pipe-bash installer that fetches files from upstream and creates directories. No dependency validation beyond git. No credential setup. No verification step.

**Gap**: A user who runs Loa's mount has no idea if their environment is ready. They must separately configure API keys, discover `/loa doctor`, and hope things work.

**Recommendation**: HIGH PRIORITY
- Add dependency checking to mount (jq, yq, git, optionally br)
- Add optional LLM key validation (`ANTHROPIC_API_KEY` health check)
- Add post-mount verification step that runs `/loa doctor` equivalent
- Keep it fast (< 30 seconds) — Hive's quickstart takes 2-5 minutes which is too long

**Effort**: Medium (extend mount-loa.sh + add health-check.sh)

---

### 2. Meta-Orchestrator Menu in `/loa`

**What Hive does**: `/hive` immediately shows an `AskUserQuestion` with 7 options (Build, Test, Learn, Optimize, Credentials, Debug, Other). Routes to the appropriate sub-skill. No status display — just an action menu.

**What Loa does**: `/loa` shows a status dashboard (health, journey bar, progress) and suggests the next command. But the user must manually type the suggested command.

**Gap**: Loa shows you what to do next but makes you type it yourself. Hive gives you a clickable menu. Loa's status display is more informative, but Hive's menu is more actionable.

**Recommendation**: MEDIUM PRIORITY
- Add an `AskUserQuestion` menu to `/loa` with context-aware options
- Keep the status dashboard (Loa's journey bar is genuinely better than anything Hive has)
- Options should be dynamic based on state: if no PRD, show "Plan a project"; if sprints exist, show "Build current sprint"; etc.
- Always include "Other" for power users

**Example**:
```yaml
questions:
  - question: "What would you like to do?"
    header: "Next step"
    options:
      - label: "Build sprint-2 (Recommended)"
        description: "Continue implementing the current sprint"
      - label: "Review sprint-1"
        description: "Run code review + security audit"
      - label: "Check status"
        description: "View detailed progress and health"
    multiSelect: false
```

**Effort**: Low (extend `/loa` command with AskUserQuestion)

---

### 3. Credential / Environment Setup Wizard

**What Hive does**: `/hive-credentials` is a dedicated skill that:
- Auto-detects which credentials are missing (via MCP tool)
- Offers 3 auth methods per credential (OAuth, API key, advanced)
- Runs health checks against endpoints (Anthropic, Brave, GitHub, etc.)
- Stores credentials in an encrypted store (`~/.hive/credentials`)
- Handles migration from deprecated credential systems

**What Loa does**: Nothing. There is no credential management. Users must configure `ANTHROPIC_API_KEY` themselves. The config file (`.loa.config.yaml`) is documented but not wizard-driven.

**Gap**: Credential setup is the #1 friction point for any AI tool. Loa assumes users know how to set environment variables.

**Recommendation**: MEDIUM PRIORITY
- Create `/loa setup` command that walks through initial configuration
- Check for `ANTHROPIC_API_KEY` and validate it
- Optionally configure `.loa.config.yaml` interactively (enable Flatline? enable beads?)
- Store nothing sensitive — just validate and guide

**Effort**: Medium (new command + validation script)

---

### 4. Use-Case Qualification ("Is This Right for You?")

**What Hive does**: `/hive-create` includes a "Good, Bad, Ugly" qualification matrix before building:
- **Good**: Multi-step research, CRM workflows, content pipelines
- **Bad**: Single API calls, simple CRUD
- **Ugly**: Real-time trading, safety-critical systems

This prevents users from building agents that won't work well, saving frustration.

**What Loa does**: `/plan-and-analyze` accepts any project without qualification. There's no guidance on what Loa is good/bad at.

**Gap**: New users may try to use Loa for projects where it adds overhead instead of value (e.g., a 10-line script).

**Recommendation**: LOW PRIORITY
- Add a brief qualification step to `/plan` for new users (first cycle only)
- Frame as "Loa works best for..." not "Loa doesn't work for..."
- Skip for returning users (detect existing cycles in ledger)

**Effort**: Low (add conditional check to /plan)

---

### 5. Multi-IDE Skill Mirroring

**What Hive does**: Identical skills exist in `.claude/skills/`, `.cursor/skills/`, and `.opencode/skills/`. Same SKILL.md content, different directory conventions.

**What Loa does**: Claude Code only. All skills are in `.claude/skills/`.

**Gap**: Users of Cursor or Opencode cannot use Loa.

**Recommendation**: LOW PRIORITY (strategic, not urgent)
- Loa's architecture (shell scripts, YAML configs, markdown protocols) is already IDE-agnostic
- The coupling is in `.claude/` directory conventions and Claude Code hooks
- If Cursor/Opencode adopt similar conventions, mirroring becomes trivial
- Monitor Hive's approach — if multi-IDE becomes table stakes, invest here

**Effort**: High (requires understanding each IDE's extension model)

---

### 6. Post-Tool Hooks for Auto-Formatting

**What Hive does**: `.claude/settings.json` includes a `PostToolUse` hook that runs `ruff check --fix && ruff format` on every file touched by Edit/Write/NotebookEdit. Code is always formatted.

**What Loa does**: Has `PreCompact` and `UserPromptSubmit` hooks for context recovery, but no auto-formatting hooks.

**Gap**: Users working on Python projects get no auto-formatting. Loa could ship recommended hooks for common languages.

**Recommendation**: LOW PRIORITY
- Add formatting hooks to constructs registry (opt-in, not default)
- Python: ruff, JS/TS: prettier, Go: gofmt, Rust: rustfmt
- Don't ship in core — language-specific, belongs in constructs

**Effort**: Low (construct pack, not framework change)

---

### 7. Template/Recipe Starter System

**What Hive does**: `examples/templates/` has 2 full agent templates (deep research, tech news reporter). `examples/recipes/` has 15 business process stubs. `/hive-create` can initialize from templates.

**What Loa does**: `/constructs` registry provides packs for extending capabilities. But there are no "project starter templates" — Loa always starts from a blank PRD.

**Gap**: Users starting similar projects (REST API, CLI tool, library) repeat the same planning decisions.

**Recommendation**: MEDIUM PRIORITY
- Add project archetypes to `/plan`: "What kind of project?" (API, CLI, Library, Frontend, Full-stack)
- Pre-populate context from archetype templates (common requirements, tech stack suggestions)
- NOT full project scaffolding — just planning accelerators

**Effort**: Medium (archetype templates + /plan integration)

---

### 8. Checkpoint-Based Test Resume

**What Hive does**: `/hive-test` saves state at node boundaries. When a test fails, users fix the code and resume from the last clean checkpoint (skipping expensive early steps).

**What Loa does**: `/review` and `/audit` re-run from scratch each time. The eval framework runs full trial sets with no mid-trial checkpointing.

**Gap**: For expensive operations (LLM-based evals, long test suites), re-running from scratch wastes time and money.

**Recommendation**: LOW PRIORITY (aligns with Eileen feedback FR-8)
- Eval framework already has early stopping (Wald SPRT proposed)
- Checkpoint-based resume is more relevant for agent evals (future scope)
- Current framework evals are fast (< 15 seconds) — checkpointing adds complexity without benefit

**Effort**: High (would require eval result caching + replay)

---

## What Hive Can Learn from Loa

For completeness, patterns Loa has that Hive lacks:

| Loa Pattern | Hive Equivalent | Advantage |
|-------------|----------------|-----------|
| Golden Path (5 commands) | 7 commands (no hierarchy) | Loa's porcelain/plumbing model is more intuitive |
| Visual journey bar | None | Users always know where they are in the lifecycle |
| Auto-state detection | Manual command selection | Loa commands figure out what to do; Hive requires explicit routing |
| Enforced quality gates | Judge system (per-node) | Loa enforces review+audit at sprint level; Hive judges at node level |
| Multi-model adversarial review | None | Flatline Protocol catches issues no single model would find |
| Sprint ledger + cross-cycle tracking | Session management | Loa tracks history across development cycles |
| Three-zone model | No file ownership model | Clear boundaries prevent framework/user file conflicts |
| `.gitattributes` protection | None | Safe framework updates without downstream breakage |
| Persistent memory (NOTES.md) | Shared memory (per-session) | Loa's memory persists across sessions; Hive's is session-scoped |
| Eval sandbox with CI | `/hive-test` (manual) | Loa has automated regression detection; Hive tests are manual |

---

## Priority Matrix

| # | Improvement | Effort | Impact | Priority |
|---|------------|--------|--------|----------|
| 1 | Interactive quickstart with validation | Medium | High | **P0** |
| 2 | AskUserQuestion menu in `/loa` | Low | High | **P0** |
| 3 | `/loa setup` credential wizard | Medium | Medium | **P1** |
| 7 | Project archetype templates for `/plan` | Medium | Medium | **P1** |
| 4 | Use-case qualification in `/plan` | Low | Low | **P2** |
| 6 | Auto-formatting hooks (constructs) | Low | Low | **P2** |
| 5 | Multi-IDE skill mirroring | High | Medium | **P3** |
| 8 | Checkpoint-based test resume | High | Low | **P3** |

---

## Architectural Observations

### Hive's MCP-First Approach

Hive uses MCP (Model Context Protocol) extensively:
- Agent-builder operations are MCP tools (`create_session`, `set_goal`, `add_node`, `validate_graph`)
- 102 MCP tools for agent capabilities (web search, file ops, APIs)
- Skills call MCP tools rather than shell scripts

**Implication for Loa**: As Claude Code's MCP support matures, Loa could benefit from wrapping key operations as MCP servers. This would enable:
- Structured tool calls instead of shell script execution
- Better error handling (JSON responses vs exit codes)
- IDE-agnostic tool discovery

### Hive's Judge Pattern vs Loa's Quality Gates

Hive uses a "Judge" system that evaluates every node's output (ACCEPT/RETRY/ESCALATE). This is the sole acceptance mechanism — no ad-hoc framework gating.

Loa uses sequential quality gates: review -> audit -> deploy. Each gate produces markdown feedback.

**Observation**: Hive's approach is more granular (per-node) but less transparent (judge decisions are internal). Loa's approach is more auditable (feedback documents are human-readable) but coarser (per-sprint). Neither is strictly better — they optimize for different use cases.

### Hive's Self-Improvement Loop

Hive's differentiator is the evolution loop: execute -> evaluate -> diagnose -> regenerate. When agents fail, the framework captures structured failure data, a coding agent rewrites the graph, and a new version deploys.

**Implication for Loa**: This aligns with Eileen's Suggestion 7 (Critic/Reviser Loop). Loa could adopt a similar pattern for eval tasks: when a regression is detected, automatically diagnose and propose a fix. This is Sprint 5 in the current Eileen roadmap.

---

## Appendix: Hive Skill Architecture

### Skill Inventory

| Skill | Trigger | Purpose | Comparable Loa Command |
|-------|---------|---------|----------------------|
| `/hive` | Entry point | Menu-based routing to sub-skills | `/loa` |
| `/hive-concepts` | Learning | Architecture and concepts reference | `/rtfm` |
| `/hive-create` | Building | Step-by-step agent creation wizard | `/plan` + `/build` |
| `/hive-patterns` | Optimization | Best practices and design patterns | `.claude/protocols/` |
| `/hive-credentials` | Setup | Credential management and validation | (none) |
| `/hive-test` | Testing | Iterative test-fix-resume loop | `/review` + `/audit` |
| `/hive-debugger` | Debugging | Log analysis and fix recommendations | `/bug` |
| `/triage-issue` | Maintenance | GitHub issue analysis and response | (GitHub Actions) |

### Onboarding Quiz Innovation

Hive includes gamified onboarding quizzes (`docs/quizzes/`) with point systems and passing scores. The "Getting Started" quiz (50 points, 30 min) includes community engagement (star/fork), README scavenger hunts, and creative challenges (propose an agent idea).

**Assessment**: Likely a recruitment funnel (submissions go to `careers@adenhq.com`) rather than pure onboarding. However, the quiz format itself is interesting for framework education. Could inspire a `/loa tutorial` command that walks users through building something real.

---

## Methodology

This analysis was conducted by:
1. Fetching the full adenhq/hive repo tree and README
2. Reading all 8 Claude Code skill SKILL.md files
3. Reading quickstart.sh, getting-started.md, environment-setup.md, configuration.md
4. Reading onboarding quizzes
5. Comparing against Loa's mount, golden path, /loa, /plan, /build, /review, /ship flows
6. Cross-referencing with Eileen's eval feedback (PR #282) for alignment opportunities
