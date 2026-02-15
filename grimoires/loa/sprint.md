# Sprint Plan: BUTTERFREEZONE Cross-Repo Agent Legibility — Machine-Readable Excellence

> Cycle: cycle-017 (extended)
> Source: [PR #336 Deep Bridgebuilder Review](https://github.com/0xHoneyJar/loa/pull/336), [#43](https://github.com/0xHoneyJar/loa/issues/43), [#316](https://github.com/0xHoneyJar/loa/issues/316)
> Branch: `feat/cycle-017-butterfreezone-excellence`
> Cross-repo context: [loa-finn #31](https://github.com/0xHoneyJar/loa-finn/issues/31), [loa-finn #66](https://github.com/0xHoneyJar/loa-finn/issues/66), [loa-hounfour PR #2](https://github.com/0xHoneyJar/loa-hounfour/pull/2), [arrakis #62](https://github.com/0xHoneyJar/arrakis/issues/62)

## Overview

Four sprints implementing the architectural proposals from Bridgebuilder's deep review of PR #336. These changes transform BUTTERFREEZONE from a per-repo inventory into the connective tissue of a multi-repo, multi-model ecosystem. Every field added is machine-parseable, deterministically generated, and model-independent.

**Design constraint**: Zero LLM inference. All generation uses `grep`, `sed`, `awk`, `jq`, `git`. Any model routed by any Hounfour pool can consume the output.

**Team**: 1 engineer (autonomous)
**Dependencies**: Loa repo only — cross-repo schemas are defined here, consumed elsewhere

---

## Sprint 1: Ecosystem Discovery — Cross-Repo Navigation Graph

**Goal**: Add the `ecosystem` field to AGENT-CONTEXT so agents can traverse the loa/loa-finn/loa-hounfour/arrakis graph from any entry point. Addresses [SPECULATION-1](https://github.com/0xHoneyJar/loa/pull/336#issuecomment-3903498503) and [#43](https://github.com/0xHoneyJar/loa/issues/43).

**FAANG parallel**: Google Service Discovery — every service registers itself with repo, role, interface, and protocol version. Netflix service lineage — upstream/downstream contract declarations.

### Task 1.1: Define ecosystem schema in `.loa.config.yaml`

**File**: `.loa.config.yaml`, `.loa.config.yaml.example`

**Description**: Add an `ecosystem` block to the Loa config that declares related repositories. This is the source of truth — `butterfreezone-gen.sh` reads it; agents consume the generated AGENT-CONTEXT.

```yaml
butterfreezone:
  ecosystem:
    - repo: 0xHoneyJar/loa-finn
      role: runtime
      interface: hounfour-router
      protocol: loa-hounfour@4.6.0
    - repo: 0xHoneyJar/loa-hounfour
      role: protocol
      interface: npm-package
      protocol: loa-hounfour@4.6.0
    - repo: 0xHoneyJar/arrakis
      role: distribution
      interface: jwt-auth
      protocol: loa-hounfour@4.6.0
```

Schema per entry:
- `repo` (required): GitHub slug — machine-resolvable via `gh repo view`
- `role` (required): semantic relationship — `runtime`, `protocol`, `distribution`, `billing`, `client`, `library`
- `interface` (required): how this repo connects — the integration surface
- `protocol` (optional): shared contract version from a common package

**Acceptance Criteria**:
- [ ] `.loa.config.yaml` has `butterfreezone.ecosystem` block with 3 entries for loa
- [ ] `.loa.config.yaml.example` documents the schema with inline comments
- [ ] `yq '.butterfreezone.ecosystem' .loa.config.yaml` returns valid YAML array

### Task 1.2: Generate ecosystem field in `extract_agent_context()`

**File**: `.claude/scripts/butterfreezone-gen.sh` — `extract_agent_context()`

**Description**: Read `butterfreezone.ecosystem` from `.loa.config.yaml` and emit it as a YAML block inside the AGENT-CONTEXT HTML comment. Use `yq` to read the config (already a dependency).

```yaml
<!-- AGENT-CONTEXT
name: loa
type: framework
purpose: Loa is an agent-driven development framework for Claude Code (Anthropic's official CLI).
key_files: [CLAUDE.md, .claude/loa/CLAUDE.loa.md, .loa.config.yaml, .claude/scripts/, .claude/skills/]
interfaces: [/auditing-security, /autonomous-agent, /bridgebuilder-review, /browsing-constructs, /bug-triaging]
dependencies: [git, jq, yq]
ecosystem:
  - repo: 0xHoneyJar/loa-finn
    role: runtime
    interface: hounfour-router
    protocol: loa-hounfour@4.6.0
  - repo: 0xHoneyJar/loa-hounfour
    role: protocol
    interface: npm-package
    protocol: loa-hounfour@4.6.0
  - repo: 0xHoneyJar/arrakis
    role: distribution
    interface: jwt-auth
    protocol: loa-hounfour@4.6.0
version: v1.39.1
trust_level: grounded
-->
```

Implementation:
1. Check if `butterfreezone.ecosystem` exists in config: `yq '.butterfreezone.ecosystem // null' .loa.config.yaml`
2. If non-null, serialize each entry as indented YAML inside the AGENT-CONTEXT block
3. If null/missing, omit the `ecosystem:` field entirely (backward compatible)

**Acceptance Criteria**:
- [ ] AGENT-CONTEXT includes `ecosystem:` block when config has entries
- [ ] AGENT-CONTEXT omits `ecosystem:` when config has no entries
- [ ] Each ecosystem entry has `repo`, `role`, `interface` fields
- [ ] `protocol` field is included when present in config

### Task 1.3: Validate ecosystem field in `butterfreezone-validate.sh`

**File**: `.claude/scripts/butterfreezone-validate.sh`

**Description**: Add `validate_ecosystem()` as an advisory (WARN, not FAIL) check:
1. If `ecosystem:` is present in AGENT-CONTEXT, validate each entry has `repo` and `role` fields
2. Validate `repo` format matches `owner/name` pattern
3. If config has `butterfreezone.ecosystem` but AGENT-CONTEXT does not, emit WARN (stale generation)

**Acceptance Criteria**:
- [ ] Malformed ecosystem entries (missing repo/role) produce WARN
- [ ] Valid ecosystem entries produce PASS
- [ ] Missing ecosystem when config declares one produces WARN
- [ ] No ecosystem in config + no ecosystem in AGENT-CONTEXT produces silent PASS

### Task 1.4: Document ecosystem field in PROCESS.md standard

**File**: `PROCESS.md`

**Description**: Update the BUTTERFREEZONE standard section to include `ecosystem` in the AGENT-CONTEXT contract table. Add it as a recommended (not required) field with description: "Cross-repo discovery graph — declares related repositories with roles and interfaces."

Add a new subsection "### Cross-Repo Discovery" explaining:
- The ecosystem field enables agent navigation across repository boundaries
- Each entry declares repo (GitHub slug), role (semantic relationship), interface (integration surface), protocol (shared contract)
- Agents can fetch linked repos' BUTTERFREEZONE.md to build a complete capability graph

**Acceptance Criteria**:
- [ ] PROCESS.md AGENT-CONTEXT table includes `ecosystem` as recommended field
- [ ] Cross-repo discovery subsection explains the navigation pattern
- [ ] Example AGENT-CONTEXT in PROCESS.md shows ecosystem field

---

## Sprint 2: Capability Contracts — Requirements + Protocol Verification

**Goal**: Add `capability_requirements` to AGENT-CONTEXT for Hounfour pool-skill compatibility validation, and add a `## Verification` section for protocol maturity trust signals. Addresses [SPECULATION-2](https://github.com/0xHoneyJar/loa/pull/336#issuecomment-3903498503), [SPECULATION-3](https://github.com/0xHoneyJar/loa/pull/336#issuecomment-3903498503), and [RFC #31 §5.2](https://github.com/0xHoneyJar/loa-finn/issues/31).

**FAANG parallel**: AWS IAM resource policies — declare what permissions a resource requires. TLS certificate verification levels (DV/OV/EV) — trust signals beyond identity.

### Task 2.1: Extract capability requirements from SKILL.md files

**File**: `.claude/scripts/butterfreezone-gen.sh`

**Description**: Add a new helper `extract_skill_capabilities()` that reads each SKILL.md and infers capability requirements from workflow descriptions. The capabilities vocabulary:

| Capability | Meaning | Detection |
|-----------|---------|-----------|
| `filesystem:read` | Reads files | SKILL.md mentions "Read", "codebase", "source files" |
| `filesystem:write` | Writes/creates files | SKILL.md mentions "Write", "Create", "Generate" |
| `git:read` | Reads git history | SKILL.md mentions "git", "diff", "log", "branch" |
| `git:write` | Creates commits/branches | SKILL.md mentions "commit", "push", "branch" |
| `github_api:read` | Reads GitHub API | SKILL.md mentions "PR", "issue", "gh " |
| `github_api:write` | Writes to GitHub API | SKILL.md mentions "create PR", "post comment" |
| `shell:execute` | Runs shell commands | SKILL.md mentions "bash", "shell", "execute", "run" |
| `network:read` | Fetches URLs | SKILL.md mentions "fetch", "API call", "HTTP" |

Implementation: For each skill directory, `grep -ciE` the SKILL.md for detection keywords. If ≥2 matches for a capability, include it. Aggregate across all skills to produce a union set for the AGENT-CONTEXT.

Output format in AGENT-CONTEXT:
```yaml
capability_requirements:
  - filesystem: read
  - filesystem: write
  - git: read_write
  - shell: execute
  - github_api: read_write
```

**Acceptance Criteria**:
- [ ] Top 5 skills (implementing-tasks, reviewing-code, riding-codebase, bug-triaging, planning-sprints) produce accurate capability lists
- [ ] Aggregate union set emitted in AGENT-CONTEXT `capability_requirements`
- [ ] Skills with no SKILL.md produce no requirements (graceful fallback)
- [ ] Output is valid YAML within HTML comment block

### Task 2.2: Add `## Verification` section generation

**File**: `.claude/scripts/butterfreezone-gen.sh`

**Description**: Add a new extractor `extract_verification()` that generates a `## Verification` section with provenance `CODE-FACTUAL`. This section provides trust signals beyond the version number.

Extraction strategy:
1. **Test count**: Count test files across all known patterns (`*.test.*`, `*.spec.*`, `*_test.*`, `.bats`, plus files in `tests/`, `test/`, `spec/`, `__tests__/`, `e2e/` directories). Count test suites (directories with test files).
2. **CI presence**: Check `.github/workflows/`, `.gitlab-ci.yml`, `Jenkinsfile`, `.circleci/`
3. **Type safety**: Check for `tsconfig.json`, `mypy.ini`, `pyrightconfig.json`, `rustfmt.toml`
4. **Linter presence**: Check for `.eslintrc*`, `.flake8`, `clippy.toml`, `.golangci.yml`
5. **Formal properties**: Check for `fast-check`, `hypothesis`, `proptest`, `quickcheck` in dependency files
6. **Security scanning**: Check for `gitleaks.toml`, `.trivyignore`, `SECURITY.md`

Output:
```markdown
## Verification
<!-- provenance: CODE-FACTUAL -->
- 142 test files across 8 suites
- CI/CD: GitHub Actions (3 workflows)
- Type safety: TypeScript strict mode
- Linting: ESLint configured
- Security: gitleaks configured, SECURITY.md present
```

If no verification signals are found, omit the section entirely (don't emit an empty section).

**Acceptance Criteria**:
- [ ] Loa repo generates Verification section with accurate test count
- [ ] Section only appears when ≥1 verification signal exists
- [ ] Provenance tag is `CODE-FACTUAL`
- [ ] Test count matches reality (cross-check with `find` output)

### Task 2.3: Validate capability_requirements and verification

**File**: `.claude/scripts/butterfreezone-validate.sh`

**Description**: Add advisory validation:
1. `validate_capability_requirements()`: If `capability_requirements:` is in AGENT-CONTEXT, check each entry matches known capability vocabulary
2. `validate_verification_section()`: If `## Verification` section exists, check it has provenance tag and ≥1 metric line

Both are WARN-level (advisory), not FAIL — these are new optional fields.

**Acceptance Criteria**:
- [ ] Malformed capabilities produce WARN
- [ ] Valid capabilities produce PASS
- [ ] Verification section without provenance tag produces WARN
- [ ] Missing sections produce silent skip (no WARN for optional sections)

### Task 2.4: Document capability contracts in PROCESS.md

**File**: `PROCESS.md`

**Description**: Add subsection "### Capability Contracts" under the BUTTERFREEZONE standard:
- Explain `capability_requirements` bridges BUTTERFREEZONE to Hounfour pool routing (RFC #31 §5.2)
- Document the capability vocabulary table
- Explain that `## Verification` provides protocol maturity trust signals
- Add `capability_requirements` and `verification` to the AGENT-CONTEXT recommended fields table

**Acceptance Criteria**:
- [ ] Capability vocabulary table in PROCESS.md matches implementation
- [ ] RFC #31 §5.2 connection documented
- [ ] Verification section documented as optional with CODE-FACTUAL provenance

---

## Sprint 3: Self-Describing Agents + Cross-Model Verification

**Goal**: Enable persona.md files to carry AGENT-CONTEXT blocks (self-describing agents), record Flatline Protocol consensus as BUTTERFREEZONE verification metadata, and add domain-specific convention patterns. Addresses Bridgebuilder "What I Would Build Next" proposals 3, 4, and the billing convention gap from Section VI.

### Task 3.1: Add AGENT-CONTEXT support for persona.md files

**File**: `.claude/scripts/butterfreezone-gen.sh`

**Description**: Add a new extractor `extract_persona_agents()` that scans `.claude/data/*-persona.md` files and generates a "## Agents" section listing each persona with its AGENT-CONTEXT metadata.

For each persona file:
1. Extract the `# {Name}` heading
2. Extract the `## Identity` section first sentence
3. Extract the `## Voice` section first sentence
4. Check for existing AGENT-CONTEXT block; if missing, synthesize one from headings

Output format:
```markdown
## Agents
<!-- provenance: DERIVED -->
The project defines N specialized agent personas.

| Agent | Identity | Voice |
|-------|----------|-------|
| Bridgebuilder | Autonomous PR reviewer with iterative excellence model | Technical prose with FAANG parallels and architectural metaphors |
```

If no persona files exist, omit the section.

**Acceptance Criteria**:
- [ ] Loa repo generates Agents section with Bridgebuilder persona
- [ ] Each persona shows Identity and Voice summaries
- [ ] Section omitted when no persona.md files exist
- [ ] Provenance tag is DERIVED

### Task 3.2: Record Flatline consensus in BUTTERFREEZONE metadata

**File**: `.claude/scripts/butterfreezone-gen.sh` — `generate_meta_footer()`

**Description**: Extend the `ground-truth-meta` footer to include Flatline verification data when available. Check for Flatline run manifests in `.flatline/runs/` and extract the most recent consensus summary.

New metadata fields in the footer:
```markdown
<!-- ground-truth-meta
head_sha: abc123...
generated_at: 2026-02-15T07:07:36Z
generator: butterfreezone-gen v1.0.0
flatline_verified: true
flatline_models: [opus-4.6, gpt-5.2]
flatline_consensus: 4/4 HIGH_CONSENSUS
flatline_last_run: 2026-02-15T06:00:00Z
sections:
  ...
-->
```

Implementation:
1. Find most recent `.flatline/runs/*.json` manifest
2. Extract `models` array, `status`, `metrics.high_consensus` count
3. If no Flatline runs exist, omit the `flatline_*` fields (backward compatible)

**Acceptance Criteria**:
- [ ] Footer includes `flatline_verified`, `flatline_models`, `flatline_consensus` when runs exist
- [ ] Footer omits flatline fields when no runs directory or no manifests
- [ ] Existing meta footer fields unchanged
- [ ] SHA checksums for sections still computed correctly

### Task 3.3: Add domain-specific convention patterns for `infer_module_purpose()`

**File**: `.claude/scripts/butterfreezone-gen.sh` — `infer_module_purpose()`

**Description**: Extend the directory name convention map (Strategy 2) with domain-specific patterns for billing, fintech, auth, and infrastructure codebases. This ensures arrakis and similar projects get accurate module purposes.

New convention entries:
```bash
billing|payments|pay) purpose="Billing and payment processing" ;;
ledger|credits|wallet) purpose="Financial ledger and credit management" ;;
auth|authentication|oauth) purpose="Authentication and authorization" ;;
themes|sietch) purpose="Theme-based runtime configuration" ;;
gateway|gatekeeper) purpose="API gateway and access control" ;;
webhooks|hooks) purpose="Webhook handlers and event processing" ;;
subscriptions|plans|tiers) purpose="Subscription management" ;;
crypto|web3|blockchain) purpose="Blockchain and cryptocurrency integration" ;;
discord|telegram|slack) purpose="Chat platform integration" ;;
sessions|session) purpose="Session management" ;;
jobs|workers|queue) purpose="Background job processing" ;;
cache|redis) purpose="Caching layer" ;;
monitoring|metrics|telemetry) purpose="Observability and monitoring" ;;
deploy|infra|terraform) purpose="Infrastructure and deployment" ;;
```

**Acceptance Criteria**:
- [ ] `billing` directory produces "Billing and payment processing"
- [ ] `themes` directory produces "Theme-based runtime configuration"
- [ ] Existing convention patterns unchanged
- [ ] Strategy priority (README > convention > file type > name) preserved

### Task 3.4: Add INSTALLATION.md reference to BUTTERFREEZONE standard

**File**: `INSTALLATION.md`

**Description**: Per [PRAISE-3](https://github.com/0xHoneyJar/loa/pull/336#issuecomment-3903498503), add a brief note to INSTALLATION.md so new adopters understand that BUTTERFREEZONE.md is generated, not authored.

Add after the installation steps section:
```markdown
## Generated Files

After installation, Loa generates `BUTTERFREEZONE.md` — the machine-readable agent-API
interface for your project. This file is regenerated automatically during `/run-bridge`
and post-merge automation. See `PROCESS.md` for the BUTTERFREEZONE standard.
```

**Acceptance Criteria**:
- [ ] INSTALLATION.md mentions BUTTERFREEZONE.md as a generated file
- [ ] References PROCESS.md for the standard
- [ ] Does not duplicate PROCESS.md content (just a pointer)

---

## Sprint 4: BUTTERFREEZONE Mesh + Cultural Layer + Self-Hosting

**Goal**: Create the cross-repo aggregation script (BUTTERFREEZONE Mesh), add the Cultural BUTTERFREEZONE section, and perform final self-hosting regeneration with all new features. Addresses Bridgebuilder "What I Would Build Next" proposals 1 and 5, plus [#247](https://github.com/0xHoneyJar/loa/issues/247).

### Task 4.1: Create BUTTERFREEZONE Mesh aggregation script

**File**: `.claude/scripts/butterfreezone-mesh.sh` (new)

**Description**: Create a script that reads the `ecosystem` entries from a project's BUTTERFREEZONE.md AGENT-CONTEXT and fetches linked repositories' BUTTERFREEZONE.md files to build a cross-repo capability graph.

```bash
#!/usr/bin/env bash
# butterfreezone-mesh.sh — Cross-repo capability graph aggregation
# Reads ecosystem entries from local BUTTERFREEZONE.md, fetches linked repos'
# BUTTERFREEZONE.md via GitHub API, outputs a unified capability index.
#
# Usage: butterfreezone-mesh.sh [--output mesh.json] [--format json|markdown]
# Dependencies: gh, jq, yq
```

Workflow:
1. Parse `ecosystem:` entries from local BUTTERFREEZONE.md AGENT-CONTEXT
2. For each entry, use `gh api repos/{repo}/contents/BUTTERFREEZONE.md` to fetch content
3. Parse each remote BUTTERFREEZONE.md's AGENT-CONTEXT block
4. Output a unified mesh as JSON:

```json
{
  "mesh_version": "1.0.0",
  "generated_at": "2026-02-15T18:00:00Z",
  "root_repo": "0xHoneyJar/loa",
  "nodes": [
    {
      "repo": "0xHoneyJar/loa",
      "name": "loa",
      "type": "framework",
      "purpose": "...",
      "version": "v1.39.1",
      "interfaces": [...],
      "capabilities": [...]
    },
    {
      "repo": "0xHoneyJar/loa-finn",
      "name": "loa-finn",
      "type": "runtime",
      "purpose": "...",
      "version": "...",
      "interfaces": [...],
      "capabilities": [...]
    }
  ],
  "edges": [
    {
      "from": "0xHoneyJar/loa",
      "to": "0xHoneyJar/loa-finn",
      "role": "runtime",
      "interface": "hounfour-router",
      "protocol": "loa-hounfour@4.6.0"
    }
  ]
}
```

Also support `--format markdown` for human-readable output.

**Acceptance Criteria**:
- [ ] Script reads ecosystem from local BUTTERFREEZONE.md
- [ ] Fetches remote BUTTERFREEZONE.md via `gh api`
- [ ] Produces valid JSON mesh with nodes and edges
- [ ] Gracefully handles missing BUTTERFREEZONE.md in linked repos (WARN, continue)
- [ ] `--format markdown` produces a readable capability table
- [ ] Script is executable and has help text (`--help`)

### Task 4.2: Add Cultural BUTTERFREEZONE section generation

**File**: `.claude/scripts/butterfreezone-gen.sh`

**Description**: Add a new extractor `extract_culture()` that generates an optional `## Culture` section with provenance `OPERATIONAL`. This section communicates the project's principles, naming conventions, and methodology — "what the system believes."

Source data:
1. Check for `PRINCIPLES.md`, `PHILOSOPHY.md`, `CODE_OF_CONDUCT.md`
2. Check `.loa.config.yaml` for `butterfreezone.culture` block:
   ```yaml
   butterfreezone:
     culture:
       naming_etymology: "Vodou terminology as cognitive hooks for framework concepts"
       principles:
         - "Think Before Coding — Karpathy"
         - "Simplicity First — avoid over-engineering"
         - "Surgical Changes — minimal diff, maximum impact"
       methodology: "Agent-driven development with iterative excellence loops"
   ```
3. If config has culture block, emit it as prose
4. If no culture data exists, omit the section

Output:
```markdown
## Culture
<!-- provenance: OPERATIONAL -->
**Naming**: Vodou terminology as cognitive hooks for framework concepts.

**Principles**: Think Before Coding (Karpathy), Simplicity First, Surgical Changes, Goal-Driven Development.

**Methodology**: Agent-driven development with iterative excellence loops.
```

**Acceptance Criteria**:
- [ ] Culture section generated when config has `butterfreezone.culture`
- [ ] Section omitted when no culture data exists
- [ ] Provenance tag is OPERATIONAL
- [ ] Free-text principles preserved accurately (no truncation)

### Task 4.3: Add culture configuration to `.loa.config.yaml`

**File**: `.loa.config.yaml`, `.loa.config.yaml.example`

**Description**: Add the culture block to Loa's own config and document in example.

```yaml
butterfreezone:
  culture:
    naming_etymology: "Vodou terminology (Loa, Grimoire, Hounfour, Simstim) as cognitive hooks for agent framework concepts"
    principles:
      - "Think Before Coding — plan and analyze before implementing"
      - "Simplicity First — minimum complexity for the current task"
      - "Surgical Changes — minimal diff, maximum impact"
      - "Goal-Driven — every action traces to acceptance criteria"
    methodology: "Agent-driven development with iterative excellence loops (Simstim, Run Bridge, Flatline Protocol)"
```

**Acceptance Criteria**:
- [ ] `.loa.config.yaml` has `butterfreezone.culture` block
- [ ] `.loa.config.yaml.example` documents culture schema with inline comments
- [ ] `yq '.butterfreezone.culture' .loa.config.yaml` returns valid YAML

### Task 4.4: Self-hosting — Full regeneration with all new features

**Description**: Run the modified generator on the Loa repo with all Sprint 1-4 changes and verify comprehensive output quality.

1. Run `.claude/scripts/butterfreezone-gen.sh --verbose`
2. Run `.claude/scripts/butterfreezone-validate.sh --strict`
3. Verify all new sections:
   - AGENT-CONTEXT includes `ecosystem`, `capability_requirements`
   - `## Verification` section with accurate test count
   - `## Agents` section with Bridgebuilder persona
   - `## Culture` section with principles and methodology
   - `ground-truth-meta` footer includes flatline fields (if runs exist)
4. Run `butterfreezone-mesh.sh --format json` and verify mesh output
5. Verify word count, validator checks, no regressions

**Acceptance Criteria**:
- [ ] All validator checks pass (strict mode)
- [ ] AGENT-CONTEXT has ecosystem, capability_requirements fields
- [ ] Verification section shows accurate test/CI data
- [ ] Agents section lists personas
- [ ] Culture section reflects config
- [ ] Mesh script produces valid JSON (or graceful error if no `gh` auth)
- [ ] Word count ≥900 (increased from 800 due to new sections)
- [ ] No regressions in existing sections (capabilities, architecture, interfaces, module map)
