# SDD: Bridgebuilder v2 — Loa-Aware Filtering, Progressive Truncation & Persona Packs

**Version**: 1.1.0 (Flatline-hardened)
**Status**: Draft (revised per Flatline Protocol review)
**Author**: Architecture Phase (designing-architecture)
**Date**: 2026-02-09
**Issue**: #263
**PRD Reference**: `grimoires/loa/prd-bridgebuilder-263.md` (v1.1.0 Flatline-hardened)

---

## Flatline Protocol Review Summary

| Metric | Value |
|--------|-------|
| Models | Claude Opus 4.6 + GPT-5.2 |
| Agreement | 100% |
| HIGH_CONSENSUS integrated | 5 (IMP-001, IMP-002, IMP-003, IMP-004, IMP-005) |
| BLOCKERS accepted | 4 (SKP-001, SKP-002, SKP-003, SKP-004) |
| DISPUTED | 0 |

| ID | Finding | Integration |
|----|---------|-------------|
| IMP-001 | Define SECURITY_PATTERNS explicitly | Section 3.6: Security Patterns Registry |
| IMP-002 | Specify CI/Actions deployment mode | Section 3.1: Deployment Mode Contract |
| IMP-003 | Clarify lock/retry interaction | Section 3.3: Lock-Aware Retry |
| IMP-004 | Define truncation→prompt template binding | Section 3.7: Truncation-Prompt Contract |
| IMP-005 | Add E2E golden integration fixtures | Section 7.3: E2E Golden Fixtures |
| SKP-001 | Loa detection source of truth in CI | Section 3.1: Deployment Mode Contract |
| SKP-002 | Pattern exclusion semantics & negation | Section 3.8: Pattern Matching Contract |
| SKP-003 | SECURITY_PATTERNS coverage gaps | Section 3.6: Security Patterns Registry |
| SKP-004 | Token estimation adaptive retry | Section 3.3: Adaptive LLM Retry |

---

## 1. Executive Summary

Bridgebuilder v2 extends the existing hexagonal architecture with three new capabilities: Loa-aware diff filtering (FR-1), progressive truncation on budget overflow (FR-2), persona pack selection (FR-3), and an `--exclude` CLI flag (FR-4). All changes modify existing modules — no new external dependencies, no new port interfaces, no new adapters. The design preserves the current 25+ test suite and port/adapter contracts while adding ~15 new test cases.

### Architecture Principle

**Additive, not structural.** Every change slots into an existing code path. The pipeline flow remains: preflight → change detection → truncation → prompt → token guard → LLM → sanitize → post. We add logic within stages, never between them.

---

## 2. System Architecture

### 2.1 Current Pipeline (Unchanged)

```
main.ts → config.ts → adapters → ReviewPipeline.run()
                                    ├── preflight (GitHub quota)
                                    ├── resolveItems (fetch PRs)
                                    └── for each item:
                                        ├── changeDetection
                                        ├── existingReviewCheck
                                        ├── claimLock
                                        ├── buildPrompt (template.ts)
                                        │   └── truncateFiles (truncation.ts)  ← FR-1, FR-2
                                        ├── tokenGuard                         ← FR-2
                                        ├── llmGenerate
                                        ├── validateResponse
                                        ├── sanitize
                                        ├── classifyEvent
                                        ├── recheckGuard
                                        └── postReview
```

### 2.2 Change Points

| Component | Current | v2 Addition |
|-----------|---------|-------------|
| `truncation.ts` | Pattern exclusion → risk sort → byte budget | **Loa detection → two-tier exclusion → progressive truncation** |
| `reviewer.ts:155-191` | Single token check → skip if over | **Progressive retry loop (3 levels)** |
| `config.ts` | 5-level precedence, `--repo`/`--pr` flags | **`--persona`, `--exclude`, `loaAware` fields** |
| `main.ts:26-43` | Load single persona file | **Pack directory resolution with precedence chain** |
| `types.ts` | Config + Result interfaces | **New fields: `loaAware`, `persona`, `excludePatterns` (CLI)** |

### 2.3 Data Flow (FR-1 + FR-2 Combined)

```
files[] from GitHub API
    │
    ▼
[1] Loa Detection (new)
    │ Read .loa-version.json → validate framework_version semver
    │ Result: { isLoa: boolean, version?: string }
    │
    ▼
[2] Pattern Exclusion (modified)
    │ loaPatterns (if Loa) + user excludePatterns (config) + CLI excludePatterns
    │ Prepend order: Loa defaults → YAML config → CLI --exclude
    │
    ▼
[3] Two-Tier Loa Exclusion (new, only if Loa detected)
    │ For files matching Loa paths:
    │   Tier 1 (content-excluded): .md, images, .lock → name + stats only
    │   Tier 2 (summary-included): .sh, .js, .ts, .py, .yml, .yaml, .json, .toml
    │     → first hunk + stats (supply-chain protection)
    │   Exception: SECURITY_PATTERNS → never excluded, full diff
    │
    ▼
[4] Risk Classification (unchanged)
    │ highRisk vs normal via isHighRisk()
    │
    ▼
[5] Priority Sort + File Cap (unchanged)
    │
    ▼
[6] Byte Budget Loop (unchanged)
    │
    ▼
[7] Token Estimation (unchanged)
    │ Math.ceil(content.length / 4) with 95% safety margin
    │
    ▼
[8] Progressive Truncation (new, replaces hard skip)
    │ If estimatedTokens > budget * 0.95:
    │   Level 1: Drop low-priority files (deterministic rules)
    │   Level 2: Hunk-based truncation (reduce context window)
    │   Level 3: File names + stats only
    │   Each level: re-estimate → check budget → proceed or escalate
    │
    ▼
[9] LLM Generation (with truncation-level disclaimer injected)
```

---

## 3. Component Design

### 3.1 Loa Detection Module

**File**: `truncation.ts` (new function, ~30 lines)

```typescript
interface LoaDetectionResult {
  isLoa: boolean;
  version?: string;
  source: "file" | "config_override";
}

function detectLoa(config: BridgebuilderConfig): LoaDetectionResult
```

**Logic**:
1. If `config.loaAware === false` → return `{ isLoa: false, source: "config_override" }`
2. If `config.loaAware === true` → return `{ isLoa: true, source: "config_override" }`
3. If `config.loaAware === undefined` (auto-detect):
   - Read `.loa-version.json` via synchronous `fs.existsSync` + `fs.readFileSync`
   - Parse JSON, validate `framework_version` key exists and matches semver pattern `/^\d+\.\d+\.\d+/`
   - If valid → `{ isLoa: true, version, source: "file" }`
   - If file missing → `{ isLoa: false, source: "file" }`
   - If file exists but malformed → `{ isLoa: false, source: "file" }` + log warning

**Loa Default Patterns** (constant):
```typescript
const LOA_EXCLUDE_PATTERNS = [
  ".claude/*",
  "grimoires/*",
  ".beads/*",
  ".loa-version.json",
  ".loa.config.yaml",
  ".loa.config.yaml.example",
];
```

**Design Decision**: Detection runs once per `truncateFiles()` call, not per-file. Result is cached for the invocation via closure.

**Why synchronous I/O**: `truncateFiles()` is currently synchronous. Converting to async would break the port contract and all callers. The detection reads a single small JSON file (<1KB), so sync I/O is acceptable.

**Deployment Mode Contract** (SKP-001 + IMP-002):

Loa detection reads local filesystem, but in CI/Actions the working directory may not contain the PR's `.loa-version.json` (sparse checkout, API-based file retrieval, different checkout than the PR being reviewed).

Source of truth contract:
- **Local mode** (default): Read `.loa-version.json` from `process.cwd()`. Assumes the repo is checked out at (or near) the PR's head SHA. This is the standard Bridgebuilder invocation from a developer terminal or a CI job with `actions/checkout`.
- **CI mode**: If `process.cwd()` does not contain `.loa-version.json` AND the PR diff contains `.loa-version.json` as a changed file, log warning: `"Loa detection: .loa-version.json not found locally but present in PR diff. Using loa_aware: true in config to force Loa mode in CI."` This prevents silent misclassification.
- **Explicit override**: `loa_aware: true` / `loa_aware: false` in config always takes precedence, bypassing filesystem detection entirely. This is the recommended CI configuration.

Required contract: detection MUST be based on the same revision as the diff. In practice, this means:
1. If running after `actions/checkout` with the PR branch → local detection is accurate
2. If running without checkout (API-only) → explicit `loa_aware` config is required
3. If workspace is stale (different branch) → explicit `loa_aware` config is required

Test cases for CI mode:
- No `.loa-version.json` locally, no config override → `isLoa: false` (safe default)
- No `.loa-version.json` locally, `loa_aware: true` → `isLoa: true` (explicit)
- Stale `.loa-version.json` (wrong version) → still detected as Loa (version mismatch is non-fatal, only semver validation)

### 3.2 Two-Tier Loa Exclusion

**File**: `truncation.ts` (new function, ~45 lines)

```typescript
interface LoaExclusionResult {
  contentExcluded: Array<{ filename: string; stats: string }>;
  summaryIncluded: Array<{ filename: string; stats: string; firstHunk: string }>;
  fullIncluded: PullRequestFile[];
  excludedBytes: number;
  excludedCount: number;
}

function applyLoaTierExclusion(
  files: PullRequestFile[],
  loaPatterns: string[],
): LoaExclusionResult
```

**Tier Classification**:

| Tier | Extensions | Treatment |
|------|-----------|-----------|
| Tier 1 (content-excluded) | `.md`, `.png`, `.jpg`, `.gif`, `.svg`, `.ico`, `.lock`, `.woff`, `.woff2`, `.ttf`, `.eot` | Name + `+N -M` stats only |
| Tier 2 (summary-included) | `.sh`, `.js`, `.ts`, `.py`, `.yml`, `.yaml`, `.json`, `.toml`, `.mjs`, `.cjs` | First hunk + stats |
| Exception | Matches `SECURITY_PATTERNS` | Full diff (never excluded) |

**First Hunk Extraction**:
```typescript
function extractFirstHunk(patch: string): string {
  // Split patch by @@ markers, return first hunk only
  const hunks = patch.split(/^(@@[^@]*@@)/m);
  if (hunks.length >= 3) {
    return hunks[1] + hunks[2]; // header + content
  }
  return patch; // Single hunk, return as-is
}
```

**Integration**: Called within `truncateFiles()` AFTER Loa detection, BEFORE pattern exclusion. Loa tier-excluded files are removed from the main pipeline and tracked in the exclusion list with tier annotations.

### 3.3 Progressive Truncation Engine

**File**: `reviewer.ts` (new function, ~80 lines, replaces hard skip at lines 155-191)

```typescript
interface TruncationLevel {
  level: 1 | 2 | 3;
  strategy: string;
  disclaimer: string;
}

interface ProgressiveTruncationResult {
  success: boolean;
  level?: TruncationLevel;
  truncatedFiles: PullRequestFile[];
  excludedFiles: Array<{ filename: string; stats: string }>;
  estimatedTokens: number;
}

function progressiveTruncate(
  files: PullRequestFile[],
  currentEstimate: number,
  budget: number,
  config: BridgebuilderConfig,
): ProgressiveTruncationResult
```

**Level 1 — Drop Low-Priority Files**:

Deterministic priority rules (highest retention priority first):
1. Files matching `SECURITY_PATTERNS` — always keep
2. Test files adjacent to changed application code — keep
3. Files with highest change size (additions + deletions) — keep
4. Remaining files — remove, smallest changes first

Tie-breaker: alphabetical by filename.

"Adjacent test file" detection:
```typescript
function isAdjacentTest(testFile: string, appFiles: string[]): boolean {
  // src/auth/login.ts → src/auth/login.test.ts, __tests__/login.test.ts
  const base = testFile.replace(/\.(test|spec)\.(ts|js|tsx|jsx)$/, "");
  return appFiles.some(f => f.startsWith(base) || base.includes(path.basename(f, path.extname(f))));
}
```

**Level 2 — Hunk-Based Truncation**:

```typescript
function truncateToHunks(
  files: PullRequestFile[],
  contextLines: number,
): PullRequestFile[]
```

Strategy:
1. Parse each file's patch into hunks (split on `@@` markers)
2. Reduce context window: 3 lines → 1 line → 0 lines per pass
3. If still over budget after context=0, drop hunks from lowest-priority files first
4. Annotate each file: `[N of M hunks included]`

Context reduction implementation:
```typescript
function reduceHunkContext(hunk: string, targetContext: number): string {
  // Parse @@ -a,b +c,d @@ header
  // Keep changed lines (starting with + or -)
  // Keep only `targetContext` unchanged lines around each change
}
```

**Level 3 — Stats Only**:

Replace all file patches with empty strings, keeping only filename and stats. Produces a structural overview: `filename: +N -M` for every file.

**Budget Check**: After each level, re-estimate tokens using `Math.ceil(content.length / 4)`. Target: 95% of `maxInputTokens` (safety margin for estimation variance). If within budget, stop and proceed.

**Disclaimer Injection**: Each truncation level adds a disclaimer to the review prompt:

| Level | Disclaimer |
|-------|-----------|
| 1 | `[Partial Review: N low-priority files excluded]` |
| 2 | `[Partial Review: patches truncated to changed hunks]` |
| 3 | `[Summary Review: diff content unavailable, reviewing file structure only]` |

**Integration in reviewer.ts**:

Replace the current hard-skip block (lines 155-191) with:

```typescript
// Current (v1):
if (estimatedTokens > config.maxInputTokens) {
  return skipResult(item, "prompt_too_large");
}

// New (v2):
const budget = Math.floor(config.maxInputTokens * 0.95);
if (estimatedTokens > budget) {
  const result = progressiveTruncate(files, estimatedTokens, budget, config);
  if (!result.success) {
    logger.warn(`Progressive truncation failed: ${estimatedTokens} tokens after all 3 levels`);
    return skipResult(item, "prompt_too_large_after_truncation");
  }
  logger.info(`Truncated to level ${result.level.level}: ${result.estimatedTokens} tokens`);
  // Rebuild prompt with truncated files and disclaimer
  // Continue pipeline with modified files
}
```

**New skip reason**: `prompt_too_large_after_truncation` — differentiates "never tried" from "tried all 3 levels".

**Lock-Aware Retry** (IMP-003):

Progressive truncation introduces retry-like behavior (3 re-estimation passes). This interacts with the existing claim lock in `reviewer.ts:143-147`:

- **Lock scope**: The claim lock is acquired BEFORE prompt building (line 143) and held through `finalizeReview()` (line 277). Progressive truncation happens within this lock scope.
- **Lock duration**: The existing `IContextStore.claimReview()` is a NoOp in local mode (always returns `true`). In distributed mode (R2 backend, future), lock TTL must exceed the maximum progressive truncation time (~300ms for 3 passes + LLM call).
- **No extra retries on lock**: Progressive truncation does NOT release and re-acquire the lock between levels. The 3 passes are deterministic string operations (<100ms total), well within any reasonable lock TTL.
- **Idempotency**: Each truncation level produces a deterministic output for the same input. If the pipeline crashes mid-truncation and retries, the same level will produce the same prompt.
- **Re-check guard**: The existing race-condition recheck (lines 240-255) runs AFTER LLM generation, which is after all truncation is complete. No interaction.

**Adaptive LLM Retry** (SKP-004):

The `char/4` token estimation is deliberately conservative but can still be inaccurate for UTF-8 heavy content, code with many symbols, or diff markup. v2 adds a post-failure adaptive retry:

```typescript
// After LLM generation attempt:
if (llmError.code === "prompt_too_large" || llmError.message.includes("maximum context length")) {
  // The LLM rejected the prompt despite our estimation passing.
  // Drop to next truncation level and retry ONCE.
  if (currentLevel < 3) {
    logger.warn(`LLM rejected prompt at level ${currentLevel}, retrying at level ${currentLevel + 1}`);
    const nextResult = progressiveTruncate(files, estimatedTokens, budget * 0.85, config, currentLevel + 1);
    if (nextResult.success) {
      // Rebuild prompt and retry LLM call
    }
  }
}
```

Key constraints:
- Adaptive retry happens at most ONCE per PR (prevent retry loops)
- On retry, budget is reduced to 85% (compensates for estimation error)
- Logs actual prompt size metrics: `estimated={N}, actual_rejection_at={M}, ratio={N/M}` for future calibration
- Per-model coefficients stored as constant (can be tuned without code changes):

```typescript
const TOKEN_ESTIMATION_COEFFICIENTS: Record<string, number> = {
  "claude-sonnet-4-5-20250929": 4.0,  // default
  "claude-opus-4-6": 3.8,             // Opus tokenizes slightly differently
  // Add new models as calibration data accumulates
};
```

Future improvement path: if calibration data shows consistent per-model ratios, replace `char/4` with `char/coefficient[model]`.

### 3.4 Persona Pack System

**File**: `main.ts` (modify `loadPersona()`, ~40 lines), `config.ts` (new fields)

**Directory Structure**:
```
resources/
  personas/
    default.md      ← current BEAUVOIR.md content (renamed/copied)
    security.md
    dx.md
    architecture.md
    quick.md
  BEAUVOIR.md       ← kept for backward compatibility (loads default.md)
```

**Persona Loading Precedence** (CLI-wins model):

```typescript
async function loadPersona(
  config: BridgebuilderConfig,
  cliPersona?: string,
): Promise<{ content: string; source: string }>
```

Resolution order:
1. `--persona <name>` CLI flag → load `resources/personas/<name>.md`
2. `persona: <name>` YAML config → load `resources/personas/<name>.md`
3. `persona_path: <path>` YAML config → load custom file path
4. `grimoires/bridgebuilder/BEAUVOIR.md` (repo-level override) → load if exists
5. `resources/personas/default.md` (built-in default)

**Warning behavior**: When repo override exists AND CLI flag is passed:
```
logger.warn("Using --persona security (repo override at grimoires/bridgebuilder/BEAUVOIR.md ignored)")
```

**Unknown persona**: If pack name doesn't match any file in `resources/personas/`:
```
Error: Unknown persona "foo". Available: default, security, dx, architecture, quick
```

Available packs discovered via `fs.readdirSync("resources/personas/")`, filtering `.md` files, stripping extension.

### 3.6 Security Patterns Registry (IMP-001 + SKP-003)

**File**: `truncation.ts` (expanded constant, ~40 lines)

`SECURITY_PATTERNS` is the critical control that prevents excluding security-relevant diffs. The existing implementation (`truncation.ts:6-18`) uses path-segment-aware regex. v2 expands this with explicit coverage for supply-chain, CI/IaC, and dependency surfaces.

**Complete Pattern Registry**:

```typescript
const SECURITY_PATTERNS: Array<{ pattern: RegExp; category: string; rationale: string }> = [
  // --- Existing (v1) ---
  { pattern: /(?:^|\/)auth/i,           category: "auth",        rationale: "Authentication/authorization logic" },
  { pattern: /(?:^|\/)crypto/i,         category: "crypto",      rationale: "Cryptographic operations" },
  { pattern: /(?:^|\/)secret/i,         category: "secrets",     rationale: "Secret management" },
  { pattern: /(?:^|\/)permission/i,     category: "auth",        rationale: "Permission/RBAC logic" },
  { pattern: /(?:^|\/)acl/i,            category: "auth",        rationale: "Access control lists" },
  { pattern: /\.pem$/i,                 category: "crypto",      rationale: "X.509 certificates" },
  { pattern: /\.key$/i,                 category: "crypto",      rationale: "Private key files" },
  { pattern: /\.env/i,                  category: "secrets",     rationale: "Environment variable files" },

  // --- New: Supply-chain (SKP-003) ---
  { pattern: /(?:^|\/)\.github\/workflows\//i, category: "ci",   rationale: "GitHub Actions workflows (code execution)" },
  { pattern: /(?:^|\/)\.github\/actions\//i,   category: "ci",   rationale: "Custom GitHub Actions (code execution)" },
  { pattern: /(?:^|\/)Dockerfile/i,     category: "infra",       rationale: "Container build (code execution, base image)" },
  { pattern: /(?:^|\/)docker-compose/i, category: "infra",       rationale: "Container orchestration" },
  { pattern: /(?:^|\/)Makefile/i,       category: "build",       rationale: "Build system (code execution)" },
  { pattern: /(?:^|\/)Jenkinsfile/i,    category: "ci",          rationale: "Jenkins pipeline (code execution)" },
  { pattern: /(?:^|\/)\.gitlab-ci/i,    category: "ci",          rationale: "GitLab CI pipeline" },

  // --- New: Infrastructure-as-Code (SKP-003) ---
  { pattern: /(?:^|\/)terraform\//i,    category: "infra",       rationale: "Terraform infrastructure definitions" },
  { pattern: /(?:^|\/)helm\//i,         category: "infra",       rationale: "Helm chart templates" },
  { pattern: /(?:^|\/)k8s\//i,          category: "infra",       rationale: "Kubernetes manifests" },
  { pattern: /\.tf$/i,                  category: "infra",       rationale: "Terraform files" },

  // --- New: Dependency lockfiles (SKP-003) ---
  { pattern: /package-lock\.json$/i,    category: "deps",        rationale: "npm dependency lockfile (supply-chain)" },
  { pattern: /yarn\.lock$/i,            category: "deps",        rationale: "Yarn dependency lockfile" },
  { pattern: /pnpm-lock\.yaml$/i,       category: "deps",        rationale: "pnpm dependency lockfile" },
  { pattern: /go\.sum$/i,              category: "deps",        rationale: "Go module checksums" },
  { pattern: /Gemfile\.lock$/i,         category: "deps",        rationale: "Ruby dependency lockfile" },
  { pattern: /poetry\.lock$/i,          category: "deps",        rationale: "Python dependency lockfile" },
  { pattern: /Cargo\.lock$/i,           category: "deps",        rationale: "Rust dependency lockfile" },
  { pattern: /package\.json$/i,         category: "deps",        rationale: "npm manifest (scripts, dependencies)" },
  { pattern: /go\.mod$/i,              category: "deps",        rationale: "Go module definition" },

  // --- New: Security policy ---
  { pattern: /SECURITY\.md$/i,          category: "policy",      rationale: "Security disclosure policy" },
  { pattern: /CODEOWNERS$/i,            category: "policy",      rationale: "Required reviewers" },
];
```

**Matching semantics**:
- Each pattern is tested against the full file path from GitHub API (e.g., `src/auth/login.ts`)
- A file matching ANY pattern is classified as high-risk
- The `category` field is for logging/reporting only (not used in matching logic)
- Patterns use path-segment-aware regex (`(?:^|\/)`) to avoid false positives (e.g., `tsconfig.json` does not match `/config/`)

**Interaction with Loa two-tier exclusion**: Files matching `SECURITY_PATTERNS` are NEVER excluded by Loa-aware filtering, even if they fall under Loa paths (e.g., `.claude/scripts/deploy.sh` matches both `.claude/*` and `Makefile`-equivalent patterns). The security check runs BEFORE tier classification.

**Regression tests** (required):
- `.github/workflows/deploy.yml` under `.claude/` → full diff (not excluded)
- `package-lock.json` under `grimoires/` → full diff (not excluded)
- `.claude/scripts/auth-setup.sh` → full diff (matches auth + .sh)
- `grimoires/loa/README.md` → Tier 1 excluded (no security pattern match)

### 3.7 Truncation-Prompt Contract (IMP-004)

**File**: `template.ts` (modified), `reviewer.ts` (modified)

The truncation output must map deterministically into prompt variables and disclaimers. This contract defines the binding:

```typescript
interface TruncationPromptBinding {
  // From TruncationResult → template variables
  includedFiles: string;          // Formatted diff content for included files
  excludedSummary: string;        // "Excluded files:\n- filename (+N -M)\n..."
  loaBanner: string | null;       // "[Loa-aware: N files excluded (M KB)]" or null
  truncationDisclaimer: string | null;  // Level disclaimer or null
  summaryIncluded: string | null; // Tier 2 first-hunk summaries or null
}

function buildPromptFromTruncation(
  truncResult: TruncationResult,
  truncLevel: TruncationLevel | null,
): TruncationPromptBinding
```

**Template variable injection** (in `template.ts:buildPrompt()`):

```
SYSTEM: {persona}
USER:
  {loaBanner}                    ← null if no Loa detection
  {truncationDisclaimer}         ← null if no progressive truncation

  ## PR Metadata
  {title, author, base, labels}

  ## Changed Files (Reviewed)
  {includedFiles}                ← full diffs or hunk-truncated diffs

  ## Summary-Only Files          ← new section, null if no Tier 2
  {summaryIncluded}              ← first-hunk summaries for Loa executables

  ## Excluded Files
  {excludedSummary}              ← names + stats only
```

**Acceptance examples**:
- No truncation: `loaBanner=null`, `truncationDisclaimer=null`, `summaryIncluded=null`
- Loa-aware only: `loaBanner="[Loa-aware: 45 files excluded (120 KB)]"`, `summaryIncluded` has Tier 2 entries
- Progressive Level 2: `truncationDisclaimer="[Partial Review: patches truncated to changed hunks]"`, `includedFiles` has `[3 of 7 hunks included]` annotations

### 3.8 Pattern Matching Contract (SKP-002)

**File**: `truncation.ts` (documented, not new code — clarifies existing behavior)

The existing pattern matcher in `truncateFiles()` (lines 62-74) uses a custom glob implementation. This section defines its exact semantics:

**Matcher implementation** (existing, unchanged):
```typescript
function matchesPattern(filename: string, pattern: string): boolean {
  // 1. Suffix match: "*.json" → filename.endsWith(".json")
  // 2. Prefix match: "dist/*" → filename.startsWith("dist/")
  // 3. Substring match: ".env" → filename.includes(".env")
  // 4. Contains-glob: "*before*after*" → split on *, check sequential indexOf
  // 5. Exact match: "package-lock.json" → filename === pattern
}
```

**Semantics**:
- Patterns are POSIX-style (forward slash `/` only, no backslash normalization)
- `*` matches any sequence of characters EXCEPT `/` (single-segment)
- `**` is NOT supported (no recursive glob)
- Dotfiles are matched normally (no special hidden-file behavior)
- Pattern list is order-independent (any match excludes the file)
- No negation (`!pattern`) support — to override Loa defaults, use `loa_aware: false`

**Override mechanism**:
- Loa default patterns cannot be selectively negated (by design — they're framework files)
- To review Loa framework files: set `loa_aware: false` in config
- To add more exclusions: use `exclude_patterns` in YAML or `--exclude` in CLI
- CLI `--exclude` is additive (appends to existing patterns, never removes)

**Test cases for pattern clarity**:
- `"*.json"` matches `package.json` and `src/config.json` but not `json-utils.ts`
- `".claude/*"` matches `.claude/SKILL.md` but not `.clauderc`
- `"grimoires/*"` matches `grimoires/loa/prd.md` (prefix match on `grimoires/`)

### 3.5 Configuration Extensions

**File**: `config.ts`, `types.ts`

**New fields in `BridgebuilderConfig`**:
```typescript
interface BridgebuilderConfig {
  // ... existing fields ...
  loaAware?: boolean;       // true=force, false=disable, undefined=auto-detect
  persona?: string;         // Pack name (e.g., "security", "dx")
  personaPath: string;      // Custom path (existing field, expanded usage)
}
```

**New fields in `CLIArgs`**:
```typescript
interface CLIArgs {
  // ... existing fields ...
  persona?: string;
  exclude?: string[];       // Repeatable --exclude patterns
}
```

**New fields in `YamlConfig`**:
```typescript
interface YamlConfig {
  // ... existing fields ...
  loa_aware?: boolean;
  persona?: string;
  persona_path?: string;
  exclude_patterns?: string[];
}
```

**CLI Parsing** (additions to `parseCLIArgs()`):
```
--persona <name>     → cliArgs.persona = name
--exclude <pattern>  → cliArgs.exclude.push(pattern) (repeatable)
```

**Config Resolution** (additions to `resolveConfig()`):

| Field | CLI | Env | YAML | Default |
|-------|-----|-----|------|---------|
| `loaAware` | — | — | `loa_aware` | `undefined` (auto-detect) |
| `persona` | `--persona` | — | `persona` | `undefined` (use precedence chain) |
| `excludePatterns` | `--exclude` (appended) | — | `exclude_patterns` | `[]` |

**Exclude pattern merging order**:
1. Loa default patterns (if Loa detected) — prepended
2. YAML `exclude_patterns` — from config
3. CLI `--exclude` — appended

This ensures Loa patterns are applied first, user config refines, and CLI overrides are additive.

---

## 4. Persona Content Design

### 4.1 default.md

Current BEAUVOIR.md content verbatim. 4 dimensions: Security, Quality, Test Coverage, Operational Readiness. Under 4000 chars.

### 4.2 security.md

**Focus**: Deep security analysis, OWASP Top 10, cryptographic review.

**Dimensions**: Authentication & Authorization, Input Validation & Injection, Cryptography & Secrets Management, Data Privacy & Compliance.

**Voice**: Paranoid but precise. Treats every input as hostile, every boundary as a potential attack surface. Cites CVEs and CWEs where relevant.

**Output format**: Same structure (Summary → Findings → Callouts) with security-specific severity calibration (critical = exploitable, high = weakness, medium = defense-in-depth gap, low = hardening opportunity).

### 4.3 dx.md

**Focus**: API design, developer experience, documentation quality.

**Dimensions**: API Ergonomics, Error Messages & Debugging, Documentation & Examples, Backward Compatibility.

**Voice**: Developer advocate. Evaluates from the consumer's perspective. Asks "would I enjoy using this?"

### 4.4 architecture.md

**Focus**: System design, coupling, scalability.

**Dimensions**: Component Boundaries, Data Flow & Coupling, Scalability & Performance, Technical Debt Trajectory.

**Voice**: Systems thinker. Evaluates structural decisions against long-term maintainability. References design patterns and anti-patterns by name.

### 4.5 quick.md

**Focus**: High-severity only, brief output.

**Dimensions**: Security (critical/high only), Correctness (obvious bugs only).

**Voice**: Triage mode. 2-3 findings maximum. Under 1500 chars. Designed for CI gating where speed matters.

---

## 5. Empty Diff Handling

**File**: `truncation.ts` (new logic within `truncateFiles()`)

When Loa-aware filtering removes ALL files (zero application files remain):

```typescript
interface TruncationResult {
  // ... existing fields ...
  allExcluded: boolean;              // New: true if Loa filtering removed everything
  loaBanner?: string;                // New: banner text for review comment
  loaStats?: {                       // New: stats for logging
    excludedCount: number;
    excludedBytes: number;
    version?: string;
  };
}
```

**Pipeline behavior** (in `reviewer.ts`):
- If `truncationResult.allExcluded === true`:
  - Post a summary comment (not a review): `"All changes in this PR are Loa framework files. No application code changes to review. Override with loa_aware: false to review framework changes."`
  - Skip reason: `all_files_excluded`
  - Do NOT call LLM (saves tokens)

**Banner injection** (when Loa files excluded but application files remain):
- Prepend to review: `[Loa-aware: N framework files excluded (M KB saved)]`

---

## 6. Error Handling & Logging

### 6.1 New Error Codes

| Code | Category | Retryable | Source |
|------|----------|-----------|--------|
| `E_LOA_DETECTION` | permanent | false | pipeline |

This error only fires if `.loa-version.json` exists, is readable, but causes a JSON parse crash (shouldn't happen with try-catch, but defense-in-depth).

### 6.2 New Skip Reasons

| Reason | Meaning |
|--------|---------|
| `prompt_too_large_after_truncation` | All 3 progressive levels failed to fit budget |
| `all_files_excluded` | Loa filtering removed all files |

### 6.3 Logging Additions

All new log lines go to stderr (existing convention):

| Event | Level | Content |
|-------|-------|---------|
| Loa detection result | info | `Loa detected: v{version} ({source})` or `Loa not detected` |
| Loa exclusion stats | info | `Loa-aware: excluded {N} files ({M} KB saved)` |
| Two-tier stats | debug | `Tier 1: {N} content-excluded, Tier 2: {M} summary-included, {K} security-kept` |
| Progressive truncation | info | `Progressive truncation: level {L}, {N} tokens ({pct}% of budget)` |
| Persona loaded | info | `Persona: {name} from {source}` |
| Persona warning | warn | `Using --persona {name} (repo override at {path} ignored)` |

---

## 7. Test Strategy

### 7.1 New Test Cases

**File**: `__tests__/truncation.test.ts` (add ~10 tests)

| Test | Description |
|------|-------------|
| `detectLoa: valid .loa-version.json` | Returns `isLoa: true` with version |
| `detectLoa: missing file` | Returns `isLoa: false` |
| `detectLoa: malformed JSON` | Returns `isLoa: false`, warns |
| `detectLoa: config override true` | Forces Loa mode |
| `detectLoa: config override false` | Disables Loa mode |
| `Loa exclusion: Tier 1 md files` | Content-excluded, stats only |
| `Loa exclusion: Tier 2 ts files` | Summary-included, first hunk |
| `Loa exclusion: security files never excluded` | Auth files under .claude/ get full diff |
| `Loa exclusion: all files excluded` | Returns `allExcluded: true` |
| `Loa patterns prepend to user patterns` | Loa defaults + user patterns both applied |

**File**: `__tests__/reviewer.test.ts` (add ~5 tests)

| Test | Description |
|------|-------------|
| `progressive: Level 1 fits budget` | Drops low-priority files, proceeds |
| `progressive: Level 2 fits budget` | Hunk truncation, proceeds |
| `progressive: Level 3 fits budget` | Stats only, proceeds |
| `progressive: all levels fail` | Returns `prompt_too_large_after_truncation` |
| `progressive: disclaimer injected` | Truncation level appears in prompt |

**File**: `__tests__/config.test.ts` (add ~5 tests)

| Test | Description |
|------|-------------|
| `parseCLIArgs: --persona flag` | Parses persona name |
| `parseCLIArgs: --exclude repeatable` | Accumulates patterns |
| `resolveConfig: persona precedence` | CLI > YAML > default |
| `resolveConfig: exclude merging` | Loa + YAML + CLI merged in order |
| `resolveConfig: loaAware from yaml` | Passes through loa_aware field |

### 7.2 E2E Golden Fixtures (IMP-005)

**File**: `__tests__/integration.test.ts` (expanded, ~6 new fixtures)

Unit tests for individual components won't catch integration regressions where filtering + truncation + persona + prompt rendering interact. Add golden E2E fixtures:

| Fixture | Scenario | Expected Outcome |
|---------|----------|-----------------|
| `loa-repo-small-pr` | 10 files, 5 under `.claude/`, `.loa-version.json` present | 5 app files reviewed, 5 Loa files excluded with banner |
| `loa-repo-all-framework` | 20 files, all under `.claude/` or `grimoires/` | `all_files_excluded` skip, summary comment posted |
| `large-pr-level1` | 100 files, 200K tokens estimated | Level 1 truncation, security files retained |
| `large-pr-level3` | 500 files, 1M tokens estimated | Level 3 stats-only, disclaimer in prompt |
| `security-in-loa-path` | `.claude/scripts/auth-setup.sh` in diff | File NOT excluded despite `.claude/*` pattern |
| `persona-cli-override` | `--persona security`, repo has `BEAUVOIR.md` override | Security persona used, warning logged |

Each fixture provides:
- Input: mock `PullRequestFile[]` array + config
- Expected: `TruncationResult` shape, prompt content assertions, skip reason (if any)
- Golden output: stored as `.json` files in `__tests__/fixtures/` for snapshot comparison

Implementation approach: fixtures run the full pipeline (truncation → prompt build → token check) with a mock LLM that returns a fixed response. Assertions validate the prompt content that would be sent to the LLM.

### 7.3 Existing Test Preservation

All 25+ existing tests continue to pass unchanged because:
- `detectLoa()` returns `isLoa: false` when no `.loa-version.json` exists (test environment)
- Progressive truncation only activates when `estimatedTokens > budget` (existing tests use small payloads)
- Default persona resolution falls through to existing `BEAUVOIR.md` path
- New config fields are optional with backward-compatible defaults

---

## 8. File Inventory

### 8.1 Modified Files

| File | Lines Changed (est.) | Changes |
|------|---------------------|---------|
| `resources/core/truncation.ts` | +120 | `detectLoa()`, `applyLoaTierExclusion()`, Loa pattern constant, TruncationResult extension |
| `resources/core/reviewer.ts` | +90 | `progressiveTruncate()`, replace hard-skip block, new skip reasons |
| `resources/core/types.ts` | +8 | `loaAware`, `persona` fields, `allExcluded`, `loaBanner`, `loaStats` |
| `resources/config.ts` | +45 | `--persona`, `--exclude` parsing, YAML fields, exclude merging |
| `resources/main.ts` | +35 | Persona pack loading with precedence chain |
| `resources/__tests__/truncation.test.ts` | +120 | 10 new test cases |
| `resources/__tests__/reviewer.test.ts` | +60 | 5 new test cases |
| `resources/__tests__/config.test.ts` | +50 | 5 new test cases |

### 8.2 New Files

| File | Purpose |
|------|---------|
| `resources/personas/default.md` | Current BEAUVOIR.md content |
| `resources/personas/security.md` | Security-focused persona |
| `resources/personas/dx.md` | Developer experience persona |
| `resources/personas/architecture.md` | Architecture-focused persona |
| `resources/personas/quick.md` | Triage/CI persona |

### 8.3 Unchanged Files

All port interfaces (`ports/*`), all adapters (`adapters/*`), `template.ts`, `context.ts`, `BEAUVOIR.md` — no changes needed. The hexagonal architecture absorbs the new features within existing boundaries.

---

## 9. Sprint Mapping

### Sprint 1 (MVP): FR-1 + FR-2

| Task | File(s) | Dependency |
|------|---------|------------|
| 1.1 Loa detection function | `truncation.ts` | None |
| 1.2 Loa default exclude patterns | `truncation.ts`, `types.ts` | 1.1 |
| 1.3 Two-tier Loa exclusion | `truncation.ts` | 1.2 |
| 1.4 Empty diff handling | `truncation.ts`, `reviewer.ts` | 1.3 |
| 1.5 Loa banner injection | `truncation.ts`, `reviewer.ts` | 1.2 |
| 1.6 Loa detection tests | `truncation.test.ts` | 1.1 |
| 1.7 Two-tier exclusion tests | `truncation.test.ts` | 1.3 |
| 2.1 Progressive truncation Level 1 | `reviewer.ts` | None |
| 2.2 Progressive truncation Level 2 (hunk-based) | `reviewer.ts` | 2.1 |
| 2.3 Progressive truncation Level 3 (stats only) | `reviewer.ts` | 2.2 |
| 2.4 New skip reason differentiation | `reviewer.ts`, `types.ts` | 2.3 |
| 2.5 Disclaimer injection in prompt | `reviewer.ts` | 2.1 |
| 2.6 Progressive truncation tests | `reviewer.test.ts` | 2.3 |

### Sprint 2: FR-3 + FR-4

| Task | File(s) | Dependency |
|------|---------|------------|
| 3.1 Create persona pack files | `resources/personas/*.md` | None |
| 3.2 Persona loading with precedence | `main.ts` | 3.1 |
| 3.3 `--persona` CLI flag | `config.ts` | None |
| 3.4 `persona` YAML config field | `config.ts` | None |
| 3.5 Persona config resolution | `config.ts` | 3.3, 3.4 |
| 3.6 Unknown persona error handling | `main.ts` | 3.2 |
| 3.7 Persona tests | `config.test.ts` | 3.5 |
| 4.1 `--exclude` CLI flag (repeatable) | `config.ts` | None |
| 4.2 Exclude pattern merging | `config.ts`, `truncation.ts` | 4.1 |
| 4.3 Exclude CLI tests | `config.test.ts` | 4.1 |

---

## 10. Non-Functional Requirements

### NFR-1: Zero New Dependencies

All implementations use Node.js stdlib only:
- `fs.existsSync`, `fs.readFileSync` for Loa detection
- `path.extname` for tier classification
- `String.split`, regex for hunk parsing
- `fs.readdirSync` for persona discovery

### NFR-2: Performance

| Operation | Budget | Implementation |
|-----------|--------|---------------|
| Loa detection | <5ms | Single `fs.existsSync` + `fs.readFileSync` |
| Two-tier classification | <10ms | Extension lookup in Set, no regex |
| Progressive truncation (3 passes) | <100ms | String operations only, no I/O |
| Persona pack loading | <10ms | Single `fs.readFileSync` |
| Persona discovery (error case) | <20ms | `fs.readdirSync` on small directory |

### NFR-3: Backward Compatibility

- Non-Loa repos: `detectLoa()` returns false, no behavior change
- No config: all new fields are optional with undefined defaults
- Existing `excludePatterns` config: continues working, Loa patterns prepended (not replacing)
- Existing `personaPath` config: continues working at precedence level 3
- Existing `BEAUVOIR.md` project override: continues working at precedence level 4

### NFR-4: Security

- Loa detection validates JSON structure, doesn't execute content
- Two-tier exclusion NEVER excludes files matching `SECURITY_PATTERNS`
- Persona files are static markdown — no template execution, no variable interpolation
- `--exclude` patterns are glob-only (no regex injection surface)
- Progressive truncation preserves security-file priority (Level 1 keeps SECURITY_PATTERNS files)

---

## 11. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Loa detection false positive on non-Loa `.loa-version.json` | Low | Medium | Validate `framework_version` semver + explicit override flag |
| Loa detection stale in CI (SKP-001) | Medium | High | Deployment Mode Contract: explicit `loa_aware` config required for API-only CI; warning when file absent but present in diff |
| Two-tier exclusion misses supply-chain attack in .md file | Low | High | Tier 2 includes first hunk for executables; SECURITY_PATTERNS never excluded |
| SECURITY_PATTERNS incomplete (SKP-003) | Medium | High | Expanded registry with 30+ patterns covering CI, IaC, lockfiles, policy files. Regression tests for each category |
| Progressive truncation produces low-quality review | Medium | Medium | Disclaimers at each level; Level 3 clearly labeled as "Summary Review" |
| Token estimation causes false overflow/underflow (SKP-004) | Medium | Medium | Adaptive LLM retry (drop one level on rejection), per-model coefficients, 85% retry budget |
| Hunk parsing breaks on unusual diff format | Low | Low | Graceful fallback: if hunk parsing fails, include full patch |
| Pattern semantics confuse users (SKP-002) | Low | Medium | Documented contract (single-segment `*`, no `**`, no negation), `loa_aware: false` as escape hatch |
| Persona pack content diverges from quality baseline | Low | Low | All packs share output format contract (Summary → Findings → Callouts) |
| Regex YAML parser breaks with new config fields | Low | Medium | New fields follow same flat key-value pattern; test coverage |
| Truncation output doesn't map to prompt correctly (IMP-004) | Low | High | TruncationPromptBinding contract with explicit variable mapping and acceptance examples |
| Lock TTL exceeded during progressive retry (IMP-003) | Low | Medium | 3 truncation passes are <100ms (well within any TTL); adaptive retry adds one LLM call max |

---

## 12. Decision Log

| Decision | Rationale | Alternatives Considered |
|----------|-----------|------------------------|
| Synchronous Loa detection | `truncateFiles()` is sync; async would break port contract | Async detection in reviewer.ts before truncation (rejected: splits detection from usage) |
| Two-tier exclusion (not binary) | Binary exclude/include misses supply-chain changes in executable Loa files | Full exclude (faster but security risk), Full include (defeats purpose) |
| 3-level progressive truncation | Covers the spectrum from partial → hunk → structural | 2 levels (insufficient granularity), 5 levels (over-engineered) |
| Hunk-based Level 2 (not file-head) | File-head truncation discards changed code; hunks preserve the actual changes | First-N-lines (SKP-004 rejected this), Random sampling (non-deterministic) |
| CLI-wins persona precedence | Explicit user intent should override implicit repo config | Last-write-wins (confusing), Merge (personas don't compose) |
| 95% safety margin on token budget | Char/4 estimation has ±20% variance; 5% margin prevents false fits | 90% (too conservative, wastes budget), 100% (risks prompt_too_large from LLM) |
| Static persona files (not templates) | Zero execution surface, no injection risk, simple to add/edit | Jinja/Handlebars templates (attack surface), JSON config (less readable) |
| Explicit SECURITY_PATTERNS registry (SKP-003) | Denylist with rationale enables audit and prevents silent omissions | Heuristic-only (shebang, executable bit) — unreliable on GitHub API data |
| Deployment Mode Contract for Loa detection (SKP-001) | CI environments may not have local checkout; explicit config is safer than guessing | Always API-fetch `.loa-version.json` (adds GitHub API call per PR), Require local checkout (breaks API-only CI) |
| No pattern negation (SKP-002) | Negation adds complexity and attack surface; `loa_aware: false` is a simpler escape hatch | `!pattern` negation (complex precedence), Allow/deny lists (over-engineered for current use case) |
| Adaptive LLM retry on token rejection (SKP-004) | Model tokenizer may disagree with char/4 estimate; one retry at next level is cheap and prevents false skips | Require tiktoken (~2MB dependency), Multiple retries (risk of rate limiting) |
| Explicit truncation→prompt contract (IMP-004) | Integration seam between truncation and template must be deterministic or features can't compose | Implicit binding (fragile, no tests), Prompt string builder (monolithic, hard to test) |
