# PRD: Onboarding UX — Hive-Inspired Improvements

**Version**: 1.0.0
**Status**: Draft
**Author**: Discovery Phase (plan-and-analyze)
**Source**: [PR #290](https://github.com/0xHoneyJar/loa/pull/290) — Hive Onboarding Analysis
**Date**: 2026-02-12
**Cycle**: cycle-004
**Prior Art**: [adenhq/hive](https://github.com/adenhq/hive) competitive analysis

---

## 1. Problem Statement

Loa's **navigation UX** is superior to competitors — the Golden Path (5 commands), visual journey bar, auto-state detection, and enforced quality gates give experienced users a seamless workflow. But Loa's **first-5-minutes UX** has friction that prevents new users from reaching that workflow.

Competitive analysis of [adenhq/hive](https://github.com/adenhq/hive) (YC-backed, 7K+ stars, Apache 2.0) revealed specific gaps in Loa's onboarding flow:

### Gap 1: Silent Installation

`mount-loa.sh` fetches files and creates directories, but provides no post-install verification. Users must separately discover `/loa doctor` to know if their environment is ready. Hive's `quickstart.sh` checks dependencies, validates API keys, and verifies the install interactively.

**Current flow**:
```
curl mount-loa.sh | bash → Files created → "Run /loa" message → ??? → User hopes it works
```

**Desired flow**:
```
curl mount-loa.sh | bash → Deps checked → Keys validated → Health verified → User confident
```

### Gap 2: Status Without Action

`/loa` shows a rich status dashboard (health, journey bar, progress, next command) but the user must manually type the suggested command. The AskUserQuestion menu at the end offers only 3 static options: "Run suggested", "Show all commands", "Run doctor".

Hive's `/hive` immediately presents a **context-aware action menu** with 7 options that route to sub-skills. The menu IS the interface — no typing required.

**Current `/loa` output**:
```
[Status dashboard with journey bar]
Suggested: /build
→ AskUserQuestion: "Run suggested" | "Show all commands" | "Run doctor"
```

**Desired `/loa` output**:
```
[Status dashboard with journey bar]
→ AskUserQuestion: "Build sprint-2 (Recommended)" | "Review sprint-1" | "View bug status" | "Plan new feature"
```

### Gap 3: No Guided Setup

There is no credential or environment setup wizard. Users must configure `ANTHROPIC_API_KEY` themselves, manually edit `.loa.config.yaml`, and figure out optional tools (beads, ck) without guidance. Hive has a dedicated `/hive-credentials` skill with endpoint health checks.

### Gap 4: Cold Start for Common Projects

`/plan-and-analyze` starts from a blank slate every time. Users building common project types (REST API, CLI tool, library) repeat the same planning decisions. Hive's templates pre-populate context for common patterns.

> Sources: [PR #290](https://github.com/0xHoneyJar/loa/pull/290) — `grimoires/loa/research/hive-onboarding-analysis.md`

---

## 2. Goals & Success Metrics

### Goals

| # | Goal | Measurable Outcome |
|---|------|-------------------|
| G1 | **Actionable Entry Point**: `/loa` routes users to their next action with one click | 100% of `/loa` invocations end with a context-aware AskUserQuestion menu |
| G2 | **Verified Installation**: Post-mount health check confirms environment readiness | `mount-loa.sh` exits with pass/fail verification summary |
| G3 | **Guided Setup**: New users can configure environment interactively | `/loa setup` validates API keys, configures options, checks optional tools |
| G4 | **Faster Planning**: Common project types get pre-populated context | `/plan` offers archetype selection for first-time projects |

### Success Criteria

| Metric | Target | Measurement |
|--------|--------|-------------|
| Menu routing coverage | All 5 golden commands reachable from `/loa` menu | Manual test — every workflow state produces relevant options |
| Post-mount verification | Health check runs automatically after mount | Run mount-loa.sh on fresh repo, observe output |
| Setup wizard completion | All 4 checks pass (API key, jq, yq, optional tools) | Run `/loa setup`, verify each check |
| Archetype template count | 4+ project archetypes (API, CLI, Library, Frontend) | Count template files in `.claude/data/archetypes/` |
| Time to first `/plan` | < 3 minutes from mount to PRD generation started | Stopwatch test on fresh repo |
| Onboarding activation | Baseline: measure % of mounts that reach first `/plan` | Event boundary: mount completion → first `/plan` invocation |

---

## 3. Users & Stakeholders

### Primary Users

| Persona | Role | Key Needs |
|---------|------|-----------|
| **New User** | First-time Loa adopter | "I mounted Loa. Now what? Is everything working?" |
| **Returning User** | Regular Loa developer | "I want to start my next task with one click from `/loa`" |
| **Team Lead** | Onboards developers onto Loa-powered repos | "My team needs to be productive within 5 minutes of cloning" |

### Secondary Users

| Persona | Role | Key Needs |
|---------|------|-----------|
| **CI Pipeline** | Automated workflows | Mount verification must be scriptable (`--json` output) |
| **Framework Maintainer** | Maintains Loa upstream | Archetypes and setup wizard must be low-maintenance |

---

## 4. Functional Requirements

### FR-1: Context-Aware Action Menu in `/loa` (P0)

**What**: Replace the static 3-option AskUserQuestion in `/loa` with a dynamic, state-aware menu that routes to the correct golden command.

**Current behavior** (`loa.md` L350-380):
```yaml
# Static menu regardless of state
questions:
  - question: "What would you like to do?"
    options:
      - label: "Run suggested"           # Always the same 3 options
      - label: "Show all commands"
      - label: "Run doctor"
```

**New behavior**: Menu options change based on workflow state from `golden-path.sh`:

| State | Option 1 (Recommended) | Option 2 | Option 3 |
|-------|----------------------|----------|----------|
| `initial` | "Plan a new project" | "Run setup wizard" | "View all commands" |
| `prd_created` | "Continue planning (architecture)" | "Start over" | "View PRD" |
| `sdd_created` | "Continue planning (sprints)" | "View architecture" | "View all commands" |
| `sprint_planned` | "Build sprint-1" | "Review sprint plan" | "View all commands" |
| `implementing` | "Build sprint-N" | "Check status" | "View all commands" |
| `reviewing` | "Review sprint-N" | "Build next sprint" | "View all commands" |
| `complete` | "Ship this release" | "Plan new cycle" | "View all commands" |
| `bug_active` | "Fix bug: {title}" | "Return to sprint" | "View all commands" |

**Routing**: When user selects an option, `/loa` invokes the corresponding skill directly (not just echoing a command name). The selection maps to skill invocations:

| Selection | Invokes |
|-----------|---------|
| "Plan a new project" | `/plan` |
| "Continue planning (architecture)" | `/plan --from architect` |
| "Build sprint-N" | `/build` |
| "Review sprint-N" | `/review` |
| "Ship this release" | `/ship` |
| "Fix bug: {title}" | `/build` (with bug context) |
| "Run setup wizard" | `/loa setup` |
| "View all commands" | Display command reference |

**Menu option prioritization algorithm** (resolves 4-option AskUserQuestion limit):
1. **Slot 1** (always): Recommended next action from `golden_detect_*` — labeled "(Recommended)"
2. **Slot 2** (contextual): Secondary action based on state (e.g., "Review sprint-1" when implementing sprint-2)
3. **Slot 3** (contextual): Tertiary action OR "Run setup wizard" for `initial` state
4. **Slot 4** (always): "View all commands" — escape hatch for power users

When state detection returns ambiguous results (e.g., multiple incomplete sprints), prefer the lowest-numbered incomplete sprint. If bug mode is active AND a sprint is in progress, bug fix takes Slot 1 and sprint takes Slot 2.

**Routing mechanism**: When user selects an option, the `/loa` command file instructs the agent to invoke the corresponding skill using Claude Code's Skill tool. This is the same mechanism used by `/plan` to chain `/plan-and-analyze` → `/architect` → `/sprint-plan`. **Fallback**: If skill invocation fails or is denied, display the exact command as a copyable code block so the user can type it manually.

**Acceptance Criteria**:
- [ ] Menu options are dynamic based on `golden_detect_*` functions
- [ ] Prioritization algorithm documented and deterministic for all states
- [ ] Recommended option is always first and labeled "(Recommended)"
- [ ] Selection routes to correct skill invocation via Skill tool
- [ ] Fallback: on invocation failure, display command as copyable code block
- [ ] Bug mode detected and surfaced when active
- [ ] "View all commands" always available as Slot 4
- [ ] `/loa --json` still works (no menu in scripting mode)
- [ ] Destructive options ("Start over") gated behind confirmation

### FR-2: Interactive Post-Mount Verification (P0)

**What**: Add a post-mount health check to `mount-loa.sh` that validates the installation before presenting the user with next steps.

**Current behavior** (`mount-loa.sh` L1100+):
```bash
# After mounting, just prints a message
echo "Loa mounted successfully. Run /loa to get started."
```

**New behavior**: After file sync completes, run a verification sequence:

```
[VERIFY] Post-mount health check...
  ✓ Framework files: 47 files synced
  ✓ Configuration: .loa.config.yaml created
  ✓ Dependencies: jq ✓, yq ✓, git ✓
  ⚠ Optional: beads not installed (recommended — run: curl -fsSL <url> | bash)
  ⚠ Optional: ck not installed (semantic search — see INSTALLATION.md)

[READY] Loa v1.33.1 mounted successfully.

  Next steps:
  1. Start Claude Code:  claude
  2. Check health:       /loa doctor
  3. Start planning:     /plan
```

**Verification checks**:

| Check | Pass | Warn | Fail |
|-------|------|------|------|
| Framework files exist | `.claude/commands/loa.md` present | — | Missing (mount failed) |
| Config created | `.loa.config.yaml` exists | — | Missing |
| jq available | `jq --version` succeeds | — | Not found (required) |
| yq available | `yq --version` succeeds | — | Not found (required) |
| git configured | `git config user.name` set | — | Not set (already checked in preflight) |
| beads available | `br --version` succeeds | Not installed | — |
| ck available | `ck --version` succeeds | Not installed | — |
| ANTHROPIC_API_KEY | Variable is set | Not set (will need for Claude Code) | — |

**Flags**:
- `--quiet`: Skip verification (for CI/scripting)
- `--json`: Output verification as JSON

**Acceptance Criteria**:
- [ ] Verification runs automatically after successful mount
- [ ] Required deps (jq, yq) shown as errors; optional deps (beads, ck) shown as warnings
- [ ] ANTHROPIC_API_KEY check is advisory only (warn, not fail)
- [ ] `--quiet` flag suppresses verification for scripted installs
- [ ] `--json` flag outputs structured verification results
- [ ] Exit code: 0=success (including warnings), 1=mount failed. Warnings communicated via `warnings_count` in JSON output, not via exit code (exit 2 breaks CI tools that treat non-zero as failure)
- [ ] `--strict` flag available to convert warnings to non-zero exit (opt-in for strict CI)
- [ ] Total time added < 2 seconds (no network calls in verification)

### FR-3: Setup Wizard — `/loa setup` (P1)

**What**: New command that walks users through initial environment configuration with validation.

**Implementation model**: `/loa setup` is a **markdown command file** (`.claude/commands/loa-setup.md`) that instructs the agent to run validation shell scripts and present results interactively. The heavy lifting (dependency checks, key format validation) is done by a **shell script** (`.claude/scripts/loa-setup-check.sh`) that the command file invokes. This matches the existing pattern where `/loa doctor` calls `loa-doctor.sh`.

**Invocation**:
```
/loa setup          # Full interactive setup
/loa setup --check  # Non-interactive validation only (calls loa-setup-check.sh --json)
```

**Wizard flow**:

```
Step 1/4: API Key Validation
─────────────────────────────
Checking ANTHROPIC_API_KEY...
  ✓ Key present (set in environment)
  ✓ Key format valid

Step 2/4: Required Dependencies
────────────────────────────────
  ✓ jq v1.7.1
  ✓ yq v4.40.5
  ✓ git v2.43.0

Step 3/4: Optional Tools
─────────────────────────
  ⚠ beads not found
    → Task tracking for sprint lifecycle
    → Install: curl -fsSL <url> | bash
  ✓ ck v0.3.0 (semantic search available)

Step 4/4: Configuration
────────────────────────
[AskUserQuestion]
  "Which features would you like to enable?"
  - Flatline Protocol (multi-model review)
  - Persistent Memory (cross-session recall)
  - Invisible Prompt Enhancement
  - Auto-formatting hooks
```

**Implementation**: The wizard reads and optionally updates `.loa.config.yaml` for feature toggles. It NEVER writes secrets to disk — only validates they exist in the environment.

**Acceptance Criteria**:
- [ ] 4-step wizard: API key, required deps, optional tools, config
- [ ] API key validation checks format only (no network call)
- [ ] Required deps show version numbers when found
- [ ] Optional tools show install instructions when missing
- [ ] Feature toggle step uses AskUserQuestion with multiSelect
- [ ] `--check` mode runs all validations without prompts, outputs pass/warn/fail
- [ ] Never writes secrets to disk or logs
- [ ] Updates `.loa.config.yaml` only with user consent
- [ ] Works on both macOS and Linux (existing compat patterns)

### FR-4: Project Archetype Templates for `/plan` (P1)

**What**: When `/plan` detects a first-time project (no existing PRD, no cycles in ledger), offer project archetype selection to pre-populate planning context.

**Current behavior**: `/plan-and-analyze` starts with a blank Phase 1 interview every time.

**New behavior**: Before Phase 1, detect first-time project and offer archetypes:

```
[AskUserQuestion]
"What kind of project are you building?"
  - REST API (Recommended)     → Pre-populates: auth, CRUD, OpenAPI, testing patterns
  - CLI Tool                   → Pre-populates: arg parsing, help text, exit codes, config
  - Library / Package          → Pre-populates: API design, docs, packaging, versioning
  - Full-Stack Application     → Pre-populates: frontend+backend, routing, state management
```

**Archetype template files** (new, in `.claude/data/archetypes/`):

```yaml
# .claude/data/archetypes/rest-api.yaml
name: REST API
description: "Backend API service with authentication, CRUD operations, and documentation"
context:
  technical:
    - "RESTful API design with versioned endpoints"
    - "Authentication (JWT or session-based)"
    - "Input validation and error handling"
    - "OpenAPI/Swagger documentation"
    - "Database migrations"
  non_functional:
    - "Response time < 200ms p95"
    - "Rate limiting"
    - "CORS configuration"
    - "Structured logging"
  testing:
    - "Integration tests for all endpoints"
    - "Auth flow tests"
    - "Error response format tests"
  common_risks:
    - "SQL injection via unvalidated input"
    - "Broken authentication"
    - "Mass assignment vulnerabilities"
```

**Integration point**: Archetype context is injected into `grimoires/loa/context/` as `archetype.md` before Phase 1 interview begins. The existing context ingestion pipeline (Phase 0) picks it up automatically.

**Skip conditions**:
- User selects "Other" → standard blank-slate interview
- Existing PRD → skip archetype selection entirely
- Existing cycles in ledger → skip (returning user)

**Acceptance Criteria**:
- [ ] 4 archetype templates: REST API, CLI Tool, Library, Full-Stack
- [ ] Templates are YAML files in `.claude/data/archetypes/`
- [ ] Selection shown only for first-time projects (no PRD, no prior cycles)
- [ ] Selected archetype written to `grimoires/loa/context/archetype.md`
- [ ] Context ingestion pipeline picks up archetype automatically
- [ ] "Other" option bypasses archetypes entirely
- [ ] Archetypes accelerate planning, not replace it — they seed context, not skip phases

### FR-5: Use-Case Qualification in `/plan` (P2)

**What**: For first-time projects, show a brief qualification step that helps users understand what Loa is best at.

**Display** (shown once, before archetype selection):

```
Loa works best for:
  ✓ Multi-sprint projects with review requirements
  ✓ Projects needing security audit trails
  ✓ Team codebases with quality gates

Consider simpler tools for:
  ⚠ One-off scripts (< 100 lines)
  ⚠ Quick prototypes without review needs
  ⚠ Projects where you'll skip review/audit

[AskUserQuestion]
  "Continue with Loa?"
  - "Yes, plan my project (Recommended)"
  - "Show me what Loa adds"
```

**Skip conditions**: Same as FR-4 — only for first-time projects.

**Acceptance Criteria**:
- [ ] Qualification shown before archetype selection
- [ ] Only shown for first-time projects
- [ ] "Show me what Loa adds" displays feature comparison (Golden Path, quality gates, memory)
- [ ] Never blocks the user — always allows continuing

### FR-6: Auto-Formatting Hooks as Construct Pack (P2)

**What**: Ship recommended PostToolUse formatting hooks as an installable construct pack, not as framework default.

**Pack structure**:
```
loa-constructs/packs/auto-format/
├── manifest.yaml
├── hooks/
│   ├── python-format.sh    # ruff check --fix && ruff format
│   ├── js-format.sh        # prettier --write
│   ├── go-format.sh        # gofmt -w
│   └── rust-format.sh      # rustfmt
└── README.md
```

**Installation**: Via existing `/constructs` command.

**Acceptance Criteria**:
- [ ] Pack available in constructs registry
- [ ] Installs PostToolUse hooks into `.claude/settings.json`
- [ ] Language-specific: only hooks for detected languages
- [ ] Non-destructive: doesn't overwrite existing hooks
- [ ] Documented in pack README

---

## 5. Non-Functional Requirements

| # | Requirement | Target |
|---|------------|--------|
| NFR-1 | Mount verification speed | < 2 seconds (no network calls) |
| NFR-2 | `/loa` menu responsiveness | Menu appears within 1 second of invocation |
| NFR-3 | Setup wizard duration | < 60 seconds for full wizard |
| NFR-4 | Archetype file size | < 50 lines per template YAML |
| NFR-5 | Cross-platform | All changes work on macOS and Linux (existing compat patterns) |
| NFR-6 | Backward compatibility | Existing `/loa` flags (`--json`, `--version`, `--help`) unchanged |
| NFR-7 | No new required dependencies | All new features use existing deps (jq, yq, bash) |
| NFR-8 | Credential redaction | Zero key material in any output — no prefixes, no suffixes, no partial values, no length. All outputs (console, JSON, logs) must only show boolean presence ("set" / "not set"). All scripts must be grep-safe for `sk-` patterns. |

---

## 6. Technical Constraints

| Constraint | Implication |
|------------|------------|
| `/loa` is a markdown command file | Menu logic must be expressed as agent instructions, not shell code |
| `mount-loa.sh` runs before Claude Code | Verification must be pure shell, not skill invocations |
| `.loa.config.yaml` is user-owned | Setup wizard updates via `yq` with explicit consent |
| AskUserQuestion limit: 4 options max | Menu must be curated to max 4 context-aware options |
| Constructs registry is separate repo | FR-6 pack ships independently from this cycle |
| Three-zone model | New files in `.claude/data/archetypes/` (System Zone), context output in `grimoires/` (State Zone) |

---

## 7. Scope & Prioritization

### In Scope (This Cycle)

| Priority | Feature | FRs | Effort |
|----------|---------|-----|--------|
| **P0** | Context-aware action menu in `/loa` | FR-1 | Low |
| **P0** | Interactive post-mount verification | FR-2 | Medium |
| **P1** | Setup wizard `/loa setup` | FR-3 | Medium |
| **P1** | Project archetype templates | FR-4 | Medium |
| **P2** | Use-case qualification | FR-5 | Low |
| **P2** | Auto-formatting construct pack | FR-6 | Low |

### Out of Scope

| Item | Reason |
|------|--------|
| Multi-IDE skill mirroring (Cursor, Opencode) | High effort, low urgency — monitor Hive's approach first |
| Checkpoint-based test resume | Aligns with Eileen FR-8 (cycle-003), not onboarding |
| Encrypted credential store | Loa should validate keys, not store them — Claude Code handles auth |
| Onboarding quiz / gamification | Hive uses this as a recruitment funnel, not genuine onboarding value |
| Network-based API key validation | Too fragile for install-time; format validation sufficient |
| Auto-install of optional tools | Users should decide; just show instructions |

### Build Order

```
Sprint 1: FR-1 (context-aware /loa menu) — Highest ROI, lowest effort
Sprint 2: FR-2 (post-mount verification) — Install confidence
Sprint 3: FR-3 + FR-4 (setup wizard + archetypes) — Guided first experience
Sprint 4: FR-5 + FR-6 (qualification + formatting pack) — Polish
```

Sprint 1 is independent. Sprint 2 is independent. Sprint 3 builds on Sprint 2 (setup wizard references the same validation checks). Sprint 4 is independent polish.

---

## 8. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| AskUserQuestion 4-option limit constrains menu expressiveness | High | Low | Curate options per state; always include "View all commands" as escape hatch |
| Mount verification adds friction for CI/scripted installs | Medium | Medium | `--quiet` flag suppresses verification; exit codes differentiate errors from warnings |
| Archetype templates become stale or opinionated | Medium | Low | Templates seed context only — planning interview still runs; community can contribute archetypes |
| Setup wizard modifies `.loa.config.yaml` incorrectly | Low | High | Dry-run preview before writes; explicit consent via AskUserQuestion |
| `/loa` menu routing breaks when skills change | Low | Medium | Menu maps to golden commands (stable) not truenames (may evolve) |
| Format hook construct breaks user's existing hooks | Low | High | Construct install checks for existing hooks; merge, don't overwrite |

---

## 9. Dependencies

| Dependency | Status | Impact if Unavailable |
|------------|--------|----------------------|
| `golden-path.sh` state detection | Exists (558 lines) | FR-1 depends on `golden_detect_*` functions |
| `mount-loa.sh` installation | Exists (1226 lines) | FR-2 extends existing post-mount section |
| `.loa.config.yaml` config system | Exists | FR-3 reads/writes config |
| `grimoires/loa/context/` ingestion | Exists in `/plan-and-analyze` | FR-4 depends on context pipeline |
| AskUserQuestion tool | Claude Code built-in | FR-1, FR-3, FR-4, FR-5 all use it |
| Constructs registry | Separate repo | FR-6 ships there, not here |

---

## 10. Research Traceability Matrix

| # | Hive Research Finding | FR Mapping | Status |
|---|----------------------|-----------|--------|
| 1 | Interactive quickstart with credential setup | FR-2, FR-3 | Covered (split: mount verification + setup wizard) |
| 2 | Meta-orchestrator menu in `/loa` | FR-1 | Covered |
| 3 | Credential/environment setup wizard | FR-3 | Covered |
| 4 | Use-case qualification | FR-5 | Covered |
| 5 | Multi-IDE skill mirroring | — | Out of scope (P3, monitor) |
| 6 | Post-tool auto-formatting hooks | FR-6 | Covered (as construct pack) |
| 7 | Template/recipe starter system | FR-4 | Covered (as archetypes) |
| 8 | Checkpoint-based test resume | — | Out of scope (aligns with cycle-003) |

**Research top-2 P0 items**:
1. "AskUserQuestion menu in `/loa`" → **FR-1** (Sprint 1)
2. "Interactive quickstart with dependency checking and API key validation" → **FR-2** (Sprint 2)

Both are addressed as the first two sprints.

> Sources: [PR #290](https://github.com/0xHoneyJar/loa/pull/290), `grimoires/loa/research/hive-onboarding-analysis.md`
