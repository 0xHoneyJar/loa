# PRD: BUTTERFREEZONE — Agent-Grounded README Standard

**Version**: 1.1.0
**Status**: Draft (Flatline-reviewed)
**Author**: Discovery Phase (plan-and-analyze)
**Source Issue**: [#304](https://github.com/0xHoneyJar/loa/issues/304)
**Cycle**: cycle-009

> Sources: Issue #304, loa-finn README reference, Issue #292 (Run Bridge RFC), Issue #281 (cross-repo context), Issue #81 (feedback routing), Issue #43 (ecosystem mapping), Issue #247 (cultural framework), loa-finn#31 (Hounfour RFC)

---

## 1. Problem Statement

Agents reading codebases lack a standardized, token-efficient, truth-grounded entry point. Human READMEs are optimized for human consumption — they include marketing language, badges, narrative exposition, and installation instructions that waste agent context windows. Meanwhile, the ground truth about what code actually does lives scattered across source files.

Loa already has Ground Truth infrastructure (`ground-truth-gen.sh`, `/ride`, reality files) but no standard output document that serves as the **agent-API for a codebase**. The loa-finn project pioneered a provenance-tagged README format with `AGENT-CONTEXT` metadata and `ground-truth-meta` checksums, but this is a one-off implementation not available to other Loa-managed codebases.

Cross-repo context gaps (Issue #281) compound the problem — agents make confident claims about related codebases they can't read. A standardized agent-facing document at each repo's root would provide the topology and capability surface needed for multi-repo reasoning.

> Source: Issue #304 — "purely about capability and deterministically evaluated to be rooted in code"

---

## 2. Vision & Mission

**Vision**: Every Loa-managed codebase maintains a `BUTTERFREEZONE.md` — a provenance-tagged, checksum-verified, token-efficient document that agents can trust as ground truth about the codebase's capabilities, interfaces, and architecture.

**Mission**: Build an on-by-default skill that generates and maintains `BUTTERFREEZONE.md` at the end of autonomous workflows, ensuring the document stays synchronized with code reality through deterministic evaluation.

**Why "BUTTERFREEZONE"**: A playful insider reference to the OpenClaws movement — agents are lobsters who don't like butter. The name signals: *this document is stripped of hype, marketing butter, and ungrounded claims. Only verified capability lives here.*

> Source: Issue #304 — "BUTTERFREEZONE is a reference to openclaws agents being lobsters who don't like butter"

---

## 3. Goals & Success Metrics

### Primary Goals

| Goal | Metric | Target |
|------|--------|--------|
| G1: Agent trust | Provenance coverage | 100% of sections have provenance tags |
| G2: Token efficiency | Document size | < 800 words (index) + < 3200 words (full) — approx 2000+8000 tokens using ~2.5 words/token heuristic |
| G3: Truth grounding | Reference verification | All factual claims cite `file:symbol` or `file:line` with advisory checksums |
| G4: Freshness | Staleness detection | Auto-regenerated within 1 workflow of code changes |
| G5: Ecosystem adoption | On-by-default | Generated for all Loa codebases unless explicitly opted out |

### Secondary Goals

| Goal | Metric | Target |
|------|--------|--------|
| G6: Cross-repo routing | Topology section | Each BUTTERFREEZONE.md lists related repos with capability summaries |
| G7: Deterministic eval | RTFM pass rate | 100% of claims pass RTFM validation — stable sort, canonical formatting, timestamp excluded from checksums |
| G8: Lore integration | Cultural enrichment | Lore entries for butterfreezone/lobster concepts |

---

## 4. User & Stakeholder Context

### Primary Consumer: AI Agents

Agents are the primary reader of BUTTERFREEZONE.md. They need:
- **Fast orientation**: What does this codebase do? What are its interfaces?
- **Trust signals**: Which claims are code-verified vs. derived vs. operational?
- **Token budget**: Minimal tokens to understand capability surface
- **Navigation**: Where to look for specific functionality

### Secondary Consumer: Human Developers

Developers benefit from:
- **Honest capability listing**: No marketing, just what the code does
- **Architecture overview**: Grounded in actual file structure
- **Cross-repo context**: Understanding ecosystem relationships

### Stakeholders

| Stakeholder | Interest |
|-------------|----------|
| Loa framework users | Automatic, maintained documentation |
| Multi-repo operators | Cross-repo agent routing and context |
| CI/CD pipelines | Deterministic validation of documentation |
| OpenClaws community | Standard adoption across agent-driven projects |

---

## 5. Functional Requirements

### FR-1: BUTTERFREEZONE.md Document Format

The generated document follows the loa-finn README pattern with these sections:

```markdown
<!-- AGENT-CONTEXT
name: {project-name}
type: {library|service|framework|cli|...}
purpose: {one-line purpose}
key_files: [{critical file paths}]
interfaces: [{public API surface}]
dependencies: [{runtime dependencies}]
version: {semver}
trust_level: {grounded|derived|operational}
model_hints: {relevant model config}
-->

# {Project Name}

<!-- provenance: CODE-FACTUAL -->
{Capability description grounded in source code analysis}

## Key Capabilities
<!-- provenance: CODE-FACTUAL -->
{Bullet list with source file:line references}

## Architecture
<!-- provenance: DERIVED -->
{High-level architecture from code structure analysis}

## Interfaces
<!-- provenance: CODE-FACTUAL -->
{Public API surface, endpoints, exports}

## Module Map
<!-- provenance: CODE-FACTUAL -->
{Table: Module | Purpose | Key Files}

## Ecosystem
<!-- provenance: OPERATIONAL -->
{Related repositories, cross-repo dependencies, topology}

## Known Limitations
<!-- provenance: CODE-FACTUAL -->
{Architectural constraints with file references}

## Quick Start
<!-- provenance: OPERATIONAL -->
{Minimal operational instructions}

<!-- ground-truth-meta
head_sha: {git HEAD sha}
generated_at: {ISO timestamp}
generator: butterfreezone-gen v{version}
sections:
  agent_context: {sha256}
  capabilities: {sha256}
  architecture: {sha256}
  interfaces: {sha256}
  module_map: {sha256}
  ecosystem: {sha256}
  limitations: {sha256}
  quick_start: {sha256}
-->
```

**Acceptance Criteria**:
- AC-1.1: Every section tagged with provenance (`CODE-FACTUAL`, `DERIVED`, `OPERATIONAL`, `EXTERNAL-REFERENCE`)
- AC-1.2: `AGENT-CONTEXT` metadata block at document top
- AC-1.3: `ground-truth-meta` checksums at document bottom (advisory, `generated_at` excluded from checksum inputs)
- AC-1.4: All `CODE-FACTUAL` claims cite references using `file:symbol` (preferred, stable across refactors) or `file:line` (fallback, best-effort display). References are relative to repo root.
- AC-1.5: Total document < 3,200 words (~8,000 tokens). Measurement uses word count (model-agnostic, `wc -w` equivalent).
- AC-1.6: Index section (AGENT-CONTEXT + first paragraph) < 800 words (~2,000 tokens)
- AC-1.7: `CODE-FACTUAL` sections with `file:symbol` refs validated by checking symbol exists in file (grep). `file:line` refs validated by checking file exists (line may drift — advisory).

> **Flatline IMP-002/IMP-004 integration**: Token budgets use word-count approximation (model-agnostic). Citations use symbol-level references as primary, line numbers as best-effort display. This resolves tokenizer dependency and line-number fragility concerns.

### FR-2: Provenance Tagging System

Each content block carries a provenance tag indicating trust level:

| Tag | Meaning | Verification |
|-----|---------|-------------|
| `CODE-FACTUAL` | Directly verified from source code | `file:symbol` or `file:line` reference; checksums are advisory (staleness signal, not hard gate) |
| `DERIVED` | Inferred from code structure analysis | Cites analysis method and source files |
| `OPERATIONAL` | Runtime/deployment information | May change without code changes |
| `EXTERNAL-REFERENCE` | References external documentation | URL with access timestamp |

**Acceptance Criteria**:
- AC-2.1: Parser can extract provenance tags from BUTTERFREEZONE.md
- AC-2.2: RTFM validation checks provenance tags exist for all sections
- AC-2.3: `CODE-FACTUAL` sections fail validation if cited files are missing. Checksum mismatch triggers staleness warning (not hard failure) since checksums are advisory.

> **Flatline SKP-002 resolution**: Checksums serve as staleness signals, not hard gates. Symbol-level references (`file:function_name`) are resilient to line number churn from formatting/refactoring. Regeneration on next workflow run fixes drift automatically.

### FR-3: Generation Skill (`butterfreezone-gen`)

A new skill that generates/regenerates `BUTTERFREEZONE.md`:

**Inputs** (tiered — uses best available):
- **Tier 1 (preferred)**: Reality files from `/ride` (`grimoires/loa/reality/`)
- **Tier 2 (fallback)**: Direct codebase scan — file structure, package.json/Cargo.toml/pyproject.toml, export analysis, README.md extraction
- **Tier 3 (bootstrap)**: Minimal stub with `AGENT-CONTEXT` from config and directory listing only (tagged `DERIVED`, no `CODE-FACTUAL` claims)
- Existing `BUTTERFREEZONE.md` (for incremental update / manual section preservation)
- `.loa.config.yaml` configuration

**Extraction Methodology**: Content extraction is **LLM-driven** — the `riding-codebase` skill generates reality files which BUTTERFREEZONE.md consumes. When reality files are unavailable, the Tier 2 fallback uses **static analysis** (file tree, dependency manifests, exported symbols via language-specific tooling like `grep -r "^export"`, `grep -r "^pub fn"`, endpoint route patterns). No hallucinated claims — Tier 2 sections are tagged `DERIVED` with explicit "source: file-scan" markers.

**Process**:
1. **Input detection**: Check for reality files → direct scan → bootstrap stub (tiered fallback)
2. Extract capability surface from reality files OR dependency manifests
3. Map modules to purpose from code structure (directory tree + naming conventions)
4. Identify public interfaces (exports, endpoints, CLI commands) via static patterns
5. Detect ecosystem relationships (package.json deps, imports, config refs)
6. Apply provenance tags based on evidence strength (Tier 1 → `CODE-FACTUAL`, Tier 2 → `DERIVED`, Tier 3 → `OPERATIONAL`)
7. **Merge with existing**: Preserve manually-added `OPERATIONAL` sections using `<!-- manual-start -->` / `<!-- manual-end -->` sentinel markers
8. Enforce word-count budgets per-section (truncate with priority: security/auth > interfaces > capabilities > architecture > module map > ecosystem > quick start)
9. Generate `ground-truth-meta` checksums (per-section SHA-256, `generated_at` excluded from checksum)
10. Validate against RTFM rules
11. Atomic write: Write to `.butterfreezone.tmp` then `mv` to `BUTTERFREEZONE.md`

> **Flatline SKP-001 resolution**: /ride is NOT required for MVP. Tiered input with direct-scan fallback ensures generation works on any repo, even those where /ride has never run. Bootstrap stub (Tier 3) ensures BUTTERFREEZONE.md always exists, even if minimal.

> **Flatline SKP-005 resolution**: Extraction methodology is explicitly tiered — LLM-driven via reality files when available, static analysis via file patterns when not. No hallucinated claims; evidence tier determines provenance tag.

> **Flatline IMP-003 resolution**: Atomic writes prevent partial-write corruption. Per-step status tracked internally. Consumers detect failed/missing sections via provenance tags and ground-truth-meta (missing section = missing checksum entry).

**Acceptance Criteria**:
- AC-3.1: `butterfreezone-gen` can be invoked standalone: `/butterfreezone`
- AC-3.2: Incremental updates preserve manually-added `OPERATIONAL` sections via sentinel markers (`<!-- manual-start -->` / `<!-- manual-end -->`)
- AC-3.3: Tiered input detection: reality files → direct scan → bootstrap stub
- AC-3.4: Word-count budget enforced per-section and total (truncation follows priority order)
- AC-3.5: Generated document passes RTFM validation
- AC-3.6: Atomic write prevents partial-write corruption
- AC-3.7: Bootstrap stub generated for repos with no reality files or source analysis available

### FR-4: Autonomous Workflow Integration (On-by-Default)

BUTTERFREEZONE generation hooks into autonomous workflows with phased rollout:

**MVP hooks** (this cycle):

| Workflow | Hook Point | Trigger |
|----------|-----------|---------|
| `/run-bridge` | FINALIZING phase (after GT update) | On-by-default |
| `/butterfreezone` | Standalone invocation | Manual |

**Phase 2 hooks** (next cycle, after stability proven):

| Workflow | Hook Point | Trigger |
|----------|-----------|---------|
| `/run sprint-plan` | After consolidated PR creation | On-by-default |
| Post-merge CI | `gt_regen` phase in post-merge-orchestrator | On-by-default |
| `/ship` | Before archive | On-by-default |

**Future hooks** (after cross-workflow stability):

| Workflow | Hook Point | Trigger |
|----------|-----------|---------|
| `/autonomous` | Post-completion | On-by-default |
| `/ride` | After reality generation | On-by-default |

> **Flatline SKP-004 resolution**: MVP starts with a single autonomous hook (`/run-bridge` FINALIZING) plus standalone invocation. This limits blast radius while proving stability. Expansion to other workflows follows in subsequent cycles after the generator has been battle-tested.

**Acceptance Criteria**:
- AC-4.1: BUTTERFREEZONE.md regenerated at end of `/run-bridge` FINALIZING phase
- AC-4.2: Opt-out via config: `butterfreezone.enabled: false`
- AC-4.3: No regeneration if code hasn't changed since last generation (HEAD SHA check)
- AC-4.4: Regeneration failure is non-blocking (warning logged to stderr, workflow continues)
- AC-4.5: Regeneration adds BUTTERFREEZONE.md to the PR diff when running in PR context
- AC-4.6: Generation failures logged with structured output for monitoring (not silently swallowed)

### FR-5: RTFM Validation Extension

Extend RTFM validation to cover BUTTERFREEZONE.md:

| Check | Rule |
|-------|------|
| Existence | `BUTTERFREEZONE.md` exists in project root |
| Freshness | `generated_at` within configured staleness window |
| Provenance | All sections have valid provenance tags |
| Checksums | `ground-truth-meta` per-section checksums match (advisory — mismatch = staleness warning, not hard failure) |
| References | All `file:symbol` citations resolve (symbol grep in file). `file:line` refs check file exists only. |
| Word budget | Document within configured word-count limits |

**Acceptance Criteria**:
- AC-5.1: RTFM includes BUTTERFREEZONE checks by default
- AC-5.2: Stale BUTTERFREEZONE.md (checksum mismatch or age > staleness window) triggers warning (not failure)
- AC-5.3: Missing file references (file doesn't exist) trigger failure
- AC-5.4: Missing symbol references (symbol not found in file) trigger warning
- AC-5.5: Missing provenance tags trigger failure

### FR-6: Cross-Repo Ecosystem Section

The `Ecosystem` section of BUTTERFREEZONE.md provides agent routing context:

```markdown
## Ecosystem
<!-- provenance: OPERATIONAL -->

| Repo | Type | Relationship | Capabilities |
|------|------|-------------|-------------|
| loa-finn | service | downstream consumer | OpenCode server runtime, persistent sessions |
| mibera-contracts | contracts | dependency | On-chain vault, loan, rebate logic |
| mibera-interface | frontend | sibling | React UI consuming contracts |
```

**Acceptance Criteria**:
- AC-6.1: Ecosystem section auto-populated from detected dependencies
- AC-6.2: Manual entries preserved across regeneration
- AC-6.3: Cross-repo BUTTERFREEZONE.md references use consistent naming

### FR-7: Lore Integration

Add BUTTERFREEZONE concepts to the Mibera lore knowledge base:

| Entry | Category | Content |
|-------|----------|---------|
| `butterfreezone` | mibera/glossary | "The zone where only truth survives — no butter, no hype" |
| `lobster` | mibera/glossary | "Agent that rejects marketing butter — demands code-grounded facts" |
| `grounding` | mibera/rituals | "The ritual of binding claims to checksums — truth made verifiable" |

**Acceptance Criteria**:
- AC-7.1: Lore entries added to `.claude/data/lore/mibera/glossary.yaml`
- AC-7.2: Bridgebuilder persona can reference BUTTERFREEZONE lore in reviews
- AC-7.3: Teaching moments in reviews can cite lobster/butter metaphors

---

## 6. Technical & Non-Functional Requirements

### NFR-1: Size Efficiency (Word-Count Based)

Budgets use word count (`wc -w` equivalent) — model-agnostic, deterministic, enforceable in shell.
Approximate token equivalence: 1 word ≈ 2.5 tokens (conservative heuristic).

| Section | Word Budget | ~Token Equiv |
|---------|------------|-------------|
| AGENT-CONTEXT metadata | 80 words | ~200 tokens |
| Index (first paragraph) | 120 words | ~300 tokens |
| Key Capabilities | 600 words | ~1,500 tokens |
| Architecture | 400 words | ~1,000 tokens |
| Interfaces | 800 words | ~2,000 tokens |
| Module Map | 600 words | ~1,500 tokens |
| Ecosystem | 200 words | ~500 tokens |
| Known Limitations | 200 words | ~500 tokens |
| Quick Start | 200 words | ~500 tokens |
| **Total** | **3,200 words max** | **~8,000 tokens** |

For large codebases (monorepos, >100 modules), the generator may produce a hierarchical output: `BUTTERFREEZONE.md` (index, ~800 words) + `BUTTERFREEZONE-detail.md` (full sections, up to 6,400 words). Agents read the index first and fetch detail on demand.

> **Flatline IMP-002/SKP-003 resolution**: Word count replaces token count. Model-agnostic, deterministic, enforceable via `wc -w` in shell scripts. No tokenizer dependency.

### NFR-2: Generation Performance

- Full generation: < 60 seconds on a typical codebase
- Incremental update: < 15 seconds when only checksums change
- Staleness check: < 2 seconds

### NFR-3: Backward Compatibility

- Existing codebases with a human README.md are unaffected
- BUTTERFREEZONE.md is a separate file, not a replacement for README.md
- Opt-out is a single config flag

### NFR-4: Determinism

Two runs of `butterfreezone-gen` on the same commit with the same config MUST produce identical output (excluding `generated_at` timestamp):

- Stable sort: modules, capabilities, interfaces sorted alphabetically
- Canonical markdown: consistent heading levels, list formatting, table alignment
- Locale/timezone normalization: all timestamps in UTC ISO-8601
- `generated_at` excluded from per-section checksum inputs
- Truncation algorithm: deterministic priority ordering (security > interfaces > capabilities > ...)
- No LLM involvement in `CODE-FACTUAL` sections when using Tier 2 (static analysis) — only Tier 1 (reality files from /ride) may contain LLM-derived content

> **Flatline SKP-determinism resolution**: Determinism guaranteed for Tier 2/3 generation (pure static analysis). Tier 1 (reality files) may have LLM-derived content but is pre-computed and cached, so BUTTERFREEZONE.md generation itself is deterministic given fixed inputs.

### NFR-5: Security

- No secrets, API keys, or credentials in BUTTERFREEZONE.md
- Same security redaction as Bridgebuilder reviews (gitleaks patterns)
- `file:line` references must not expose sensitive file contents

---

## 7. Scope & Prioritization

### MVP (This Cycle)

| Priority | Feature | Rationale |
|----------|---------|-----------|
| P0 | BUTTERFREEZONE.md format specification | Foundation for everything |
| P0 | `butterfreezone-gen.sh` generation script | Mechanical generation |
| P0 | `/butterfreezone` skill for standalone invocation | Developer-facing command |
| P0 | `/run-bridge` FINALIZING hook (single MVP hook) | Proves stability before wider rollout |
| P1 | RTFM validation extension | Quality gate |
| P1 | Lore entries | Cultural integration |

### Future Scope (Not This Cycle)

| Feature | Rationale |
|---------|-----------|
| Additional workflow hooks (/run sprint-plan, post-merge CI, /ship) | Phase 2 after MVP stability proven |
| Cross-repo BUTTERFREEZONE federation | Requires topology infrastructure (#43) |
| `/ride` integration for initial generation | Depends on ride modernization |
| BUTTERFREEZONE diff in PR comments | Enhancement after base is stable |
| NotebookLM knowledge tier for BUTTERFREEZONE | Optional quality enrichment |
| BUTTERFREEZONE as llms.txt hub spoke | Aligns with reality skill pattern |
| Hierarchical output for monorepos | BUTTERFREEZONE.md index + BUTTERFREEZONE-detail.md |

### Explicitly Out of Scope

- Replacing README.md (BUTTERFREEZONE.md is additive)
- Cross-repo fetching (agents read local BUTTERFREEZONE.md only in MVP)
- Interactive generation (fully autonomous, no user prompts)
- Translating BUTTERFREEZONE to natural language (that's `/translate`)

---

## 8. Risks & Dependencies

### Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Word budget exceeded for large codebases | Medium | Low | Per-section truncation with priority ordering; hierarchical output for monorepos |
| No /ride reality files on first run | High | Medium | Tiered fallback: direct scan (Tier 2) or bootstrap stub (Tier 3) |
| RTFM validation too strict blocks autonomous workflows | Low | High | Non-blocking mode; checksums advisory, not hard gates |
| File:symbol references break on refactors | Medium | Low | Advisory checksums detect staleness; regeneration on next workflow fixes |
| Generator bug corrupts multiple workflows | Low | High | MVP limited to single hook point (/run-bridge); structured failure logging |
| Non-deterministic output causes CI flapping | Low | Medium | Stable sorts, canonical formatting, timestamp excluded from checksums |

### Dependencies

| Dependency | Status | Risk |
|------------|--------|------|
| Ground Truth infrastructure (`ground-truth-gen.sh`) | Exists (scaffolded) | Low |
| Bridge orchestrator FINALIZING phase | Exists (v1.34.0) | Low |
| RTFM validation scripts | Exist | Low |
| Post-merge orchestrator | Exists (v1.33.0) | Low |
| `/ride` analysis | Exists | Low — can use cached reality |
| Lore knowledge base | Exists | Low |

### External Dependencies

| Dependency | Status |
|------------|--------|
| loa-finn README as format reference | Available (read-only reference) |
| OpenClaws cultural context | Informational only, no code dependency |

---

## 9. Architecture Hints

### Generation Pipeline

```
Input Detection (tiered):
  Tier 1: reality/ files exist? → Use them (CODE-FACTUAL)
  Tier 2: package.json/Cargo.toml/source files? → Direct scan (DERIVED)
  Tier 3: Nothing useful? → Bootstrap stub (OPERATIONAL)
    ↓
butterfreezone-gen.sh
    ├── Detect input tier
    ├── Extract AGENT-CONTEXT from manifests / config
    ├── Extract capabilities (reality OR static grep patterns)
    ├── Extract architecture from directory structure
    ├── Extract interfaces (exports, routes, CLI commands)
    ├── Build module map (directory tree + naming conventions)
    ├── Detect ecosystem (deps, imports, config refs)
    ├── Apply provenance tags (tier determines tag)
    ├── Merge with existing manual sections (sentinel markers)
    ├── Enforce word-count budgets (wc -w, priority truncation)
    ├── Deterministic sort (alphabetical modules, stable formatting)
    ├── Generate ground-truth-meta checksums (exclude generated_at)
    ├── Security redaction (gitleaks patterns)
    └── Atomic write (.butterfreezone.tmp → BUTTERFREEZONE.md)
    ↓
RTFM validation (advisory checksums)
    ↓
Commit (if in autonomous workflow)
```

### Hook Integration Points (MVP)

```
bridge-orchestrator.sh FINALIZING phase:
  existing: GROUND_TRUTH_UPDATE → RTFM_GATE → FINAL_PR_UPDATE
  new:      GROUND_TRUTH_UPDATE → BUTTERFREEZONE_GEN → RTFM_GATE → FINAL_PR_UPDATE
```

Phase 2 hooks (future):
```
post-merge-orchestrator.sh:  gt_regen → butterfreezone_gen → rtfm → tag → release
run-sprint-plan:             create_plan_pr → butterfreezone_gen → cleanup_context
```

### Config Schema Addition

```yaml
butterfreezone:
  enabled: true                    # On by default
  output_path: BUTTERFREEZONE.md   # Project root
  word_budget:
    total: 3200                    # ~8000 tokens
    per_section: 800               # ~2000 tokens
  staleness_days: 7
  hooks:
    run_bridge: true               # MVP: only hook enabled
    run_sprint_plan: false         # Phase 2
    post_merge: false              # Phase 2
    ride: false                    # Future
    ship: false                    # Phase 2
  rtfm:
    check_enabled: true
    strict_mode: false             # Advisory checksums, not hard gates
  ecosystem:
    auto_detect: true
    manual_entries: []
  manual_sections:
    sentinel_start: "<!-- manual-start -->"
    sentinel_end: "<!-- manual-end -->"
```

---

## 10. Open Questions (Resolved)

| Question | Resolution |
|----------|-----------|
| Should BUTTERFREEZONE.md replace README.md? | No — additive, separate file |
| Where does BUTTERFREEZONE.md live? | Project root (same level as README.md) |
| Is generation blocking or non-blocking? | Non-blocking — failures log warnings |
| Default on or off? | On by default, opt-out via config |
| Should it hook into /ride? | Yes, in future scope (not MVP) |

---

---

## Appendix A: Flatline Review Integration Log

**Flatline Run**: simstim-20260213-c009bfz, Phase 2
**Cost**: ~39 cents (3/4 Phase 1 calls, 2/2 Phase 2 calls)
**Model Agreement**: 100%

### HIGH_CONSENSUS (5 — auto-integrated)

| ID | Finding | Score | Resolution |
|----|---------|-------|-----------|
| IMP-001 | Bootstrap/cold-start behavior for repos without reality files | 885 | Added tiered input (Tier 1/2/3) to FR-3 |
| IMP-002 | Define tokenizer for token budget enforcement | 860 | Switched to word-count (wc -w) in NFR-1 |
| IMP-003 | Partial-write semantics and failure detection | 765 | Added atomic write + per-step status to FR-3 |
| IMP-004 | Precise file:line citation format | 840 | Added file:symbol primary + file:line fallback to FR-1 |
| IMP-008 | Manual OPERATIONAL section preservation | 740 | Added sentinel markers to FR-3 |

### BLOCKERS (7 — resolved with rationale)

| ID | Concern | Score | Resolution |
|----|---------|-------|-----------|
| SKP-001 | /ride circular dependency | 850 | Tiered input removes /ride dependency from MVP |
| SKP-002 | Checksum/file:line fragility | 820 | Advisory checksums + symbol-level refs |
| SKP-determinism | Non-deterministic output | 900 | NFR-4 determinism requirements added |
| SKP-003 | Token counting in shell | 750 | Word count (wc -w) replaces token count |
| SKP-004 | Blast radius of 6+ hooks | 720 | MVP limited to single hook (/run-bridge) |
| SKP-005 | Extraction methodology unspecified | 710 | Explicit tiered methodology in FR-3 |
| SKP-token-realism | Token budgets unrealistic for large repos | 760 | Hierarchical output option for monorepos |

---

*PRD generated for cycle-009 (Flatline-reviewed). Next: `/architect` for SDD.*
