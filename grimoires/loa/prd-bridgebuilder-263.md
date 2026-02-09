# PRD: Bridgebuilder v2 — Loa-Aware Filtering, Progressive Truncation & Persona Packs

**Version**: 1.1.0 (Flatline-hardened)
**Status**: Draft (revised per Flatline Protocol review)
**Author**: Discovery Phase (plan-and-analyze)
**Date**: 2026-02-09
**Issue**: #263
**Dependencies**: #257 (--pr fix, merged), #260 (token budgets, merged)

---

## Flatline Protocol Review Summary

| Metric | Value |
|--------|-------|
| Models | Claude Opus 4.6 + GPT-5.2 |
| Agreement | 100% |
| HIGH_CONSENSUS integrated | 4 (IMP-001, IMP-002, IMP-003, IMP-004) |
| BLOCKERS accepted | 5 (SKP-001, SKP-002, SKP-003, SKP-004, SKP-007) |
| DISPUTED | 0 |

| ID | Finding | Integration |
|----|---------|-------------|
| IMP-001 | Define Loa detection validation contract | FR-1: Detection Contract section |
| IMP-002 | Specify token estimation methodology | FR-2: Token Estimation section |
| IMP-003 | Define minimum output quality per truncation level | FR-2: Minimum Output Quality table |
| IMP-004 | Define empty-diff behavior after Loa filtering | FR-1: Empty Diff Behavior section |
| SKP-001 | Robust Loa detection with schema validation + override | FR-1: Detection Contract section |
| SKP-002 | Two-tier exclusion to protect security-sensitive Loa files | FR-1: Security-Aware Exclusion section |
| SKP-003 | Deterministic file priority rules for truncation | FR-2: Deterministic Priority Rules |
| SKP-004 | Hunk-based truncation instead of file-head truncation | FR-2: Hunk-Based Truncation section |
| SKP-007 | Clarify persona precedence (CLI-wins model) | FR-3: Persona Loading Precedence |

---

## 1. Problem Statement

Bridgebuilder v1 (shipped Feb 2026) handles the happy path well: small PRs on standard repos get quality reviews. But three classes of failure emerged from real-world usage on Loa-heavy repositories:

1. **Framework file bloat**: A 392-commit PR on `apdao-auction-house` was 95% Loa mount commits (`.claude/`, `grimoires/`, `.beads/`). Bridgebuilder spent its entire token budget on framework scaffolding and skipped the actual 75-file application change with `prompt_too_large`.

2. **Hard skip on budget overflow**: When a prompt exceeds `maxInputTokens`, Bridgebuilder skips the PR entirely. No progressive truncation is attempted — the user gets zero review rather than a partial review.

3. **One-size-fits-all persona**: The default BEAUVOIR.md persona covers 4 generic dimensions (security, quality, test coverage, operational readiness). Users want domain-specific review voices (e.g., security-focused for audits, DX-focused for SDK work, architecture-focused for system design), selectable without editing files.

### Impact

| Problem | Impact | Frequency |
|---------|--------|-----------|
| Framework file bloat | Zero review on Loa-mounted repos | Every PR with Loa mount history |
| Hard skip | Zero review on large PRs | ~20% of PRs on repos >50 files |
| Generic persona | Low-signal reviews for domain-specific work | All reviews |

### Root Cause Analysis

| Problem | Root Cause | Evidence |
|---------|-----------|----------|
| Framework bloat | `excludePatterns` defaults to `[]` — no framework awareness | `config.ts:21` |
| Hard skip | `reviewer.ts:190` returns `skipResult("prompt_too_large")` with no retry | Single code path, no progressive strategy |
| Generic persona | Single `BEAUVOIR.md` file, no pack system | `main.ts:26-43` loads one file |

---

## 2. Goals & Success Metrics

### Goals

| # | Goal | Measurement |
|---|------|-------------|
| G-1 | Bridgebuilder succeeds on Loa-mounted repos without manual config | Review posted on PR with >100 `.claude/` files in diff |
| G-2 | Large PRs get partial reviews instead of zero reviews | `prompt_too_large` skip rate drops >80% |
| G-3 | Users can select review persona without editing files | CLI flag or config selects from built-in packs |

### Success Metrics

| Metric | Current | Target |
|--------|---------|--------|
| PRs skipped as `prompt_too_large` | ~20% on large repos | <5% |
| Manual exclude_patterns config needed for Loa repos | Always | Never (auto-detected) |
| Persona options available out of box | 1 (generic) | 4+ (domain-specific) |

---

## 3. User & Stakeholder Context

### Primary User: Loa Framework Users

Developers using Loa on brownfield repos. Their PRs contain both application code and Loa framework files from `/mount`. They run `bridgebuilder --pr N` and expect reviews focused on their application changes, not framework scaffolding.

### Secondary User: Power Users

Teams customizing review dimensions for specific workflows (security audits, SDK releases, infrastructure changes). They want persona selection without file-system editing.

---

## 4. Functional Requirements

### FR-1: Loa-Aware Default Exclude Patterns

**Priority**: P0 (blocks all Loa-mounted repo reviews)

When Bridgebuilder detects it's running on a Loa-mounted repo, automatically prepend Loa framework paths to `excludePatterns`:

```
.claude/*
grimoires/*
.beads/*
.loa-version.json
.loa.config.yaml
.loa.config.yaml.example
```

**Loa Detection Contract** (SKP-001):
- Read `.loa-version.json` and validate it contains a `framework_version` key with a valid semver string
- If file exists but is malformed/empty, treat as non-Loa repo (log warning)
- Explicit override: `loa_aware: true` forces Loa mode; `loa_aware: false` disables it regardless of file presence
- When Loa-aware mode is active, include a banner in the review: `[Loa-aware: N framework files excluded (M KB saved)]`

**Security-Aware Exclusion** (SKP-002):
- Two-tier exclude strategy:
  - **Tier 1 (content-excluded)**: Markdown, images, lock files under Loa paths — diff content excluded, name + stats only
  - **Tier 2 (summary-included)**: Executable/config-sensitive files (`.sh`, `.js`, `.ts`, `.py`, `.yml`, `.yaml`, `.json`, `.toml`) under Loa paths — include a summarized diff (first hunk + stats) to catch supply-chain or prompt-injection changes
- High-risk Loa files (matching existing `SECURITY_PATTERNS` in truncation.ts) are NEVER excluded — always get full diff treatment

**Empty Diff Behavior** (IMP-004):
- If all files are excluded by Loa-aware filtering (zero application files remain), do NOT post an empty review
- Instead, post a summary comment: `"All changes in this PR are Loa framework files. No application code changes to review. Override with loa_aware: false to review framework changes."`
- Skip reason: `all_files_excluded`

**General Behavior**:
- Patterns prepended to (not replacing) user-configured `excludePatterns`
- Logging: log excluded file count and bytes saved to stderr
- Files excluded still appear in the "excluded files" section of the review prompt (name + stats only, no diff content)

**Integration point**: `truncation.ts:truncateFiles()` — prepend Loa patterns before Step 1.

### FR-2: Progressive Truncation on Budget Overflow

**Priority**: P1 (eliminates zero-review outcomes)

When `estimatedTokens > maxInputTokens`, instead of immediately skipping, attempt progressive truncation:

| Level | Strategy | Token Savings |
|-------|----------|---------------|
| 1 | Remove low-priority files using deterministic rules (see below) | ~30-50% |
| 2 | Truncate remaining patches by diff hunks with reduced context window | ~50-70% |
| 3 | Include only file names + stats (no diff content) | ~90% |

**Deterministic Priority Rules** (SKP-003):
Level 1 file retention priority (highest to lowest):
1. Files matching `SECURITY_PATTERNS` (auth, crypto, secrets, permissions) — always keep
2. Test files adjacent to changed application code — keep
3. Entry points and config files — keep
4. Files with highest change size (additions + deletions) — keep
5. Remaining files — remove first, smallest changes removed first

Tie-breaker: alphabetical by filename for stable ordering across runs.

**Hunk-Based Truncation** (SKP-004):
Level 2 does NOT truncate by file head (first N lines). Instead:
- Keep all changed hunks from the diff
- Reduce context window around each hunk (default: 3 lines → 1 line → 0 lines)
- If still over budget after context reduction, drop hunks from lowest-priority files first
- Label output: `[N of M hunks included]` per file

**Token Estimation Methodology** (IMP-002):
- Use `chars / 4` conservative estimate (existing approach)
- On `prompt_too_large`, log: estimated tokens, budget, and which truncation level would be needed
- After each truncation level, re-estimate and check budget
- Safety margin: target 95% of `maxInputTokens` to account for estimation variance

**Minimum Output Quality** (IMP-003):
| Level | Expected Quality | Disclaimer |
|-------|-----------------|------------|
| 1 | Full review on retained files | `[Partial Review: N low-priority files excluded]` |
| 2 | Hunk-level review, may miss cross-file context | `[Partial Review: patches truncated to changed hunks]` |
| 3 | File-list-only, structural observations | `[Summary Review: diff content unavailable, reviewing file structure only]` |

**Behavior**:
- Each level re-estimates tokens after truncation
- If any level fits within budget, proceed with review
- Log truncation level, files affected, hunks retained
- If even Level 3 exceeds budget, skip with `prompt_too_large_after_truncation`
- Differentiate `prompt_too_large` (no truncation attempted — zero files) from `prompt_too_large_after_truncation` (tried all 3 levels)

**Integration point**: `reviewer.ts:processItem()` — wrap token check in progressive retry loop.

### FR-3: Persona Pack System

**Priority**: P2 (quality-of-life improvement)

Ship 4 built-in personas alongside the default:

| Pack | Focus | Use Case |
|------|-------|----------|
| `default` | Security + Quality + Tests + Ops | General PR review |
| `security` | Deep security analysis, OWASP, crypto | Security audits, auth changes |
| `dx` | API design, developer experience, docs | SDK/library PRs |
| `architecture` | System design, coupling, scalability | Architecture changes |
| `quick` | High-severity only, brief output | Quick triage, CI gating |

**Behavior**:
- CLI: `--persona security` or `--persona dx`
- Config: `persona: security` in bridgebuilder YAML section
- Personas stored in `resources/personas/` directory within the skill
- Unknown persona name: error with list of available packs

**Persona Loading Precedence** (SKP-007 — clarified, CLI-wins model):

Precedence follows the existing 5-level config resolution (CLI > env > YAML > auto > default):

1. `--persona <name>` CLI flag — **always wins** (explicit user intent)
2. `persona: <name>` YAML config (built-in pack selection)
3. `persona_path: <path>` YAML config (custom file path)
4. `grimoires/bridgebuilder/BEAUVOIR.md` (repo-level default override, if exists)
5. `resources/personas/default.md` (built-in default)

**Key rule**: CLI flags always take precedence over repo-level files. If a repo has `grimoires/bridgebuilder/BEAUVOIR.md` but user passes `--persona security`, the security pack is used.

**Warning behavior**: When repo override exists AND CLI flag is passed, log: `"Using --persona security (repo override at grimoires/bridgebuilder/BEAUVOIR.md ignored)"`

**Integration point**: `main.ts:loadPersona()` — expand to check pack directory.

### FR-4: Exclude Pattern CLI Flag

**Priority**: P2 (convenience)

Add `--exclude <pattern>` CLI flag (repeatable) to add exclude patterns from command line:

```bash
bridgebuilder --pr 42 --exclude ".claude/*" --exclude "grimoires/*"
```

**Integration point**: `config.ts:parseCLIArgs()` — add `excludePatterns` to CLIArgs.

---

## 5. Technical & Non-Functional Requirements

### NFR-1: Zero New Dependencies

All features must be implementable with existing dependencies (Node.js stdlib only). No new npm packages.

### NFR-2: Backward Compatibility

- Existing `.loa.config.yaml` configs must continue working
- Default behavior (no config) must remain unchanged for non-Loa repos
- Loa-aware filtering only activates when `.loa-version.json` is detected

### NFR-3: Performance

- Progressive truncation adds at most 3 re-estimation passes (< 100ms each)
- Persona pack loading adds one filesystem read (< 10ms)
- Loa detection is a single `fs.existsSync()` call

### NFR-4: Test Coverage

- Each FR must have unit tests covering:
  - Happy path
  - Edge cases (empty files, all files excluded, persona not found)
  - Integration with existing truncation/review pipeline
- Existing 25+ test suite must continue passing

---

## 6. Scope & Prioritization

### MVP (Sprint 1)

| FR | Feature | Rationale |
|----|---------|-----------|
| FR-1 | Loa-aware exclude patterns | Unblocks all Loa-mounted repos |
| FR-2 | Progressive truncation | Eliminates zero-review outcomes |

### Sprint 2

| FR | Feature | Rationale |
|----|---------|-----------|
| FR-3 | Persona pack system | Quality-of-life, user-requested |
| FR-4 | Exclude pattern CLI flag | Convenience for ad-hoc usage |

### Out of Scope

| Item | Reason |
|------|--------|
| Multi-model review (GPT + Claude) | Separate architecture decision |
| R2/Cloudflare distributed state | Already exists, no changes needed |
| GitHub App integration | Different deployment model |
| PR auto-approval | Security risk, explicitly forbidden by persona |
| NotebookLM knowledge integration | Separate feature (Flatline Protocol) |

---

## 7. Risks & Dependencies

### Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Loa detection false positive | Low | Medium | Validate `framework_version` key in JSON, explicit override (SKP-001) |
| Excluded Loa paths hide security changes | Medium | High | Two-tier exclusion: summary for executables, never exclude high-risk files (SKP-002) |
| Progressive truncation drops important context | Medium | Medium | Deterministic priority rules, hunk-based truncation, level disclaimers (SKP-003/SKP-004) |
| Persona packs diverge from default quality | Low | Low | All packs share output format, reviewed by same author |
| Persona precedence confusion | Low | Low | CLI-wins model, warning when repo override is ignored (SKP-007) |

### Dependencies

| Dependency | Status | Risk |
|------------|--------|------|
| #257 (--pr flag fix) | Merged | None |
| #260 (token budget fix) | Merged | None |
| Anthropic API stability | Stable | Low |
| `gh` CLI availability | Required | Low (existing dependency) |

---

## 8. Appendix: Code Integration Points

### Files to Modify

| File | Changes |
|------|---------|
| `resources/core/truncation.ts` | FR-1: Add Loa detection + default patterns |
| `resources/core/reviewer.ts` | FR-2: Progressive truncation loop |
| `resources/core/types.ts` | FR-1/FR-3: Add `loaAware` and `persona` config fields |
| `resources/config.ts` | FR-1/FR-3/FR-4: New config fields, CLI flags, persona resolution |
| `resources/main.ts` | FR-3: Persona pack loading precedence |

### New Files

| File | Purpose |
|------|---------|
| `resources/personas/default.md` | Current BEAUVOIR.md (renamed) |
| `resources/personas/security.md` | Security-focused persona |
| `resources/personas/dx.md` | Developer experience persona |
| `resources/personas/architecture.md` | Architecture-focused persona |
| `resources/personas/quick.md` | Triage/CI persona |

### Existing Code Hooks

| Hook | Location | What Changes |
|------|----------|-------------|
| Exclude pattern enforcement | `truncation.ts:62` | Prepend Loa patterns before user patterns |
| Token budget check | `reviewer.ts:181` | Wrap in progressive retry loop |
| Persona loading | `main.ts:26` | Expand to check pack directory |
| CLI parsing | `config.ts:56` | Add `--persona` and `--exclude` flags |
| Config resolution | `config.ts:330` | Add `loaAware` and `persona` fields |

---

## 9. Appendix: Audit Methodology

### Codebase Grounding

This PRD was generated from direct code analysis of the bridgebuilder skill at:
- `.claude/skills/bridgebuilder-review/resources/` (TypeScript source)
- `.claude/skills/bridgebuilder-review/dist/` (compiled JavaScript)

### Issue Context

Issue #263 was submitted via `/feedback` command on 2026-02-08. User tested on `0xHoneyJar/apdao-auction-house` with a 392-commit PR where ~95% of diff was Loa mount commits.

### Related Issues

| Issue | Status | Relationship |
|-------|--------|-------------|
| #257 | Merged (PR #258) | `--pr` flag fix — prerequisite |
| #260 | Merged (PR #262) | Token budget fix — prerequisite |
| #263 | Open | This PRD's source issue |
