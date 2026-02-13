# PRD: Bridgebuilder Loa-Aware Filtering — 3 Leakage Gaps

> Source: [#309](https://github.com/0xHoneyJar/loa/issues/309) — Bridgebuilder: Loa-aware filtering has 3 gaps causing framework file leakage
> Author: @zkSoju (report), @janitooor (prioritization)
> Cycle: cycle-010

## 1. Problem Statement

The Bridgebuilder's Loa-aware filtering system (`detectLoa()`, `applyLoaTierExclusion()`, `LOA_EXCLUDE_PATTERNS`) was implemented in a prior cycle to prevent ~80% token waste on framework files. However, three gaps cause framework files to leak through the filter, wasting review tokens on system zone files (`.claude/`, `evals/`, `grimoires/`) instead of application code.

**Discovered while**: Running `/bridgebuilder-review` on `0xHoneyJar/midi-interface` PR #49 — the review posted `REQUEST_CHANGES` with findings almost entirely about Loa framework files rather than the actual application code changes.

> Sources: Issue #309 body, Issue #303 (prior partial fix)

## 2. Root Cause Analysis

All code is in `.claude/skills/bridgebuilder-review/resources/core/truncation.ts`.

### Bug 1: Missing Paths in `LOA_EXCLUDE_PATTERNS`

**Location**: `truncation.ts:156-163`

The `LOA_EXCLUDE_PATTERNS` array excludes `.claude/**`, `grimoires/**`, `.beads/**`, and 3 config files, but is missing several Loa-managed paths:

| Path | Status | Impact |
|------|--------|--------|
| `evals/**` | **MISSING** | Eval suites (~1000 files) pass through unfiltered |
| `.run/**` | **MISSING** | Bridge state, sprint-plan state leak into reviews |
| `tests/**` | **Consider** | Loa test suites may confuse app-code reviews |
| `skills/**` | **Consider** | Loa skills directory (if present at root) |
| `PROCESS.md` | **MISSING** | Loa workflow docs pass through |
| `BUTTERFREEZONE.md` | **MISSING** | Agent-grounded README treated as app code |
| `INSTALLATION.md` | **MISSING** | Loa installation docs |

**Current patterns** (truncation.ts:156-163):
```typescript
export const LOA_EXCLUDE_PATTERNS = [
  ".claude/**",
  "grimoires/**",
  ".beads/**",
  ".loa-version.json",
  ".loa.config.yaml",
  ".loa.config.yaml.example",
];
```

### Bug 2: Security Pattern Exceptions Bypass Loa Exclusion

**Location**: `truncation.ts:286-310` — `classifyLoaFile()`

Files matched by `LOA_EXCLUDE_PATTERNS` can be immediately un-excluded if they also match a `SECURITY_PATTERNS` regex. The security check runs FIRST in `classifyLoaFile()`, returning `"exception"` before tier classification.

**Problematic pattern-to-file matches**:

| Security Pattern | Intended Target | Loa Files Leaked |
|-----------------|----------------|------------------|
| `/(?:^|\/)security/i` | App security modules | `.claude/protocols/security-hardening.md`, audit skill files |
| `/(?:^|\/)secret/i` | App secret management | `.claude/scripts/detect-secrets.sh` |
| `/(?:^|\/)\.github\/workflows\//i` | App CI/CD pipelines | Loa automation workflows (`daily-synthesis.yml`) |
| `/(?:^|\/)\.env/i` | App environment files | `.env.example` templates under `.claude/` |
| `/(?:^|\/)Makefile/i` | App build systems | Any Makefile under Loa paths |
| `/(?:^|\/)crypto/i` | App crypto operations | Any Loa path containing "crypto" |

**Current flow** (truncation.ts:286-290):
```typescript
export function classifyLoaFile(filename: string): LoaTier {
  if (isHighRisk(filename)) {
    return "exception";  // Bypasses Loa exclusion entirely
  }
  // ... tier classification never reached
}
```

**Design tension**: Security files genuinely should be reviewed even under Loa paths (e.g., `.github/workflows/` with secret access). The fix must distinguish between "security-relevant app files under Loa paths" (rare, should review) and "Loa framework files that happen to match security patterns" (common, should exclude).

### Bug 3: `repoRoot` Never Populated in Config

**Location**: `config.ts` — `resolveConfig()` function

The `BridgebuilderConfig` type declares `repoRoot?: string` (types.ts:23), but `resolveConfig()` never sets it. Neither `CLIArgs` nor `EnvVars` interfaces include `repoRoot`. The `DEFAULTS` object omits it entirely.

**Effect**: `detectLoa()` and `loadReviewIgnore()` always fall back to `process.cwd()`:
```typescript
const root = config.repoRoot ?? process.cwd();
if (!config.repoRoot) {
  process.stderr.write("[bridgebuilder] WARN: repoRoot not set...\n");
}
```

This warning fires on every run. In multi-repo or nested-repo scenarios, `cwd()` may differ from the actual repo root, causing Loa detection to fail silently.

> Sources: truncation.ts:156-163, truncation.ts:286-310, config.ts:262-397, types.ts:23

## 3. Goals & Success Metrics

### Goals

1. **Eliminate framework file leakage** — Loa-managed files must not appear as review targets
2. **Preserve security review for genuine app security files** — Don't over-exclude
3. **Resolve repoRoot fragility** — Auto-detect repo root, eliminate warning noise
4. **Maintain backward compatibility** — Existing `.reviewignore` files continue to work

### Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Framework files in review | 0 | Run on midi-interface PR #49, count `.claude/` / `evals/` / `grimoires/` findings |
| Security file coverage | 100% of genuine app security files | Run on a PR with `.github/workflows/` and `auth/` changes |
| repoRoot warning | 0 occurrences | Check stderr output across 10 review runs |
| Existing test suite | All passing | `npm test` in bridgebuilder-review |
| Token savings | >60% reduction vs unfiltered | Compare token count with/without fix on a Loa-mounted repo |

## 4. User & Stakeholder Context

### Primary Persona: Loa-Mounted Repo Developer

A developer using the Bridgebuilder to review PRs on a Loa-mounted repository. They expect reviews to focus on their application code changes, not on Loa framework internals. Currently ~80% of review tokens are wasted on framework files.

### Secondary Persona: Cross-Repo Reviewer

A developer running Bridgebuilder across multiple repos (some Loa-mounted, some not). They need Loa detection to work reliably regardless of working directory.

> Sources: Issue #309 reproduction steps, Issue #303 original report

## 5. Functional Requirements

### FR-1: Expand `LOA_EXCLUDE_PATTERNS`

Add missing Loa-managed paths to the exclusion array:

```typescript
export const LOA_EXCLUDE_PATTERNS = [
  // Existing
  ".claude/**",
  "grimoires/**",
  ".beads/**",
  ".loa-version.json",
  ".loa.config.yaml",
  ".loa.config.yaml.example",
  // New — Bug 1 fix
  "evals/**",
  ".run/**",
  "tests/**",
  "skills/**",
  "PROCESS.md",
  "BUTTERFREEZONE.md",
  "INSTALLATION.md",
  "NOTES.md",
  ".flatline/**",
];
```

**Acceptance Criteria**:
- All listed paths are excluded when Loa is detected
- Files not under these paths pass through unchanged
- `.reviewignore` patterns merge correctly with expanded set
- No duplicate patterns in merged set

### FR-2: Fix Security-Loa Precedence in `classifyLoaFile()`

Redesign the classification to prevent security patterns from overriding Loa exclusion for framework files. Two approaches (choose in SDD):

**Option A — Loa-Path Guard Before Security Check**:
```typescript
export function classifyLoaFile(filename: string): LoaTier {
  // If file is under a known Loa system zone, never promote to exception
  // unless it's in an explicitly allowed exception path
  if (isLoaSystemZone(filename) && !isLoaSecurityException(filename)) {
    // Apply tier classification, skip security promotion
  }
  // ... existing logic for non-system-zone files
}
```

**Option B — Tier 2 for Loa Security Matches**:
Instead of full passthrough (`"exception"`), demote Loa security matches to Tier 2 (summary-only):
```typescript
if (isHighRisk(filename) && isUnderLoaPath(filename)) {
  return "tier2";  // Summary instead of full diff
}
```

**Acceptance Criteria**:
- `.claude/protocols/security-hardening.md` is NOT promoted to exception
- `.claude/scripts/detect-secrets.sh` is NOT promoted to exception
- App-level `src/auth/login.ts` IS still promoted to exception (unchanged behavior)
- `.github/workflows/deploy.yml` (NOT under `.claude/`) IS still promoted to exception
- Loa workflows like `.claude/` prefixed workflow references are excluded

### FR-3: Auto-Resolve `repoRoot` in Config

Populate `repoRoot` in `resolveConfig()` using git:

```typescript
// In resolveConfig():
const repoRoot = resolveRepoRoot(cliArgs, envVars);
// ...
return { ...config, repoRoot };

function resolveRepoRoot(cli: CLIArgs, env: EnvVars): string | undefined {
  // 1. CLI flag (highest priority)
  if (cli.repoRoot) return cli.repoRoot;
  // 2. Environment variable
  if (env.BRIDGEBUILDER_REPO_ROOT) return env.BRIDGEBUILDER_REPO_ROOT;
  // 3. Git auto-detection
  try {
    return execSync("git rev-parse --show-toplevel", { encoding: "utf-8" }).trim();
  } catch {
    return undefined; // Not a git repo — fall back to cwd
  }
}
```

**Acceptance Criteria**:
- `repoRoot` is set automatically when running inside a git repo
- Warning message no longer fires in normal operation
- CLI override (`--repo-root`) takes precedence
- Environment variable (`BRIDGEBUILDER_REPO_ROOT`) takes precedence over git detection
- Non-git-repo scenario falls back to `cwd()` gracefully (with warning)

### FR-4: Test Coverage for All Fixes

Each fix must have corresponding test cases:

| Fix | Test Cases Required |
|-----|-------------------|
| FR-1 | `evals/suites/foo.ts` excluded, `.run/state.json` excluded, `PROCESS.md` excluded |
| FR-2 | `.claude/protocols/security-hardening.md` → tier1/tier2 (not exception), `src/auth/login.ts` → exception (unchanged) |
| FR-3 | `repoRoot` resolved from git, CLI override, env override, non-git fallback |

**Acceptance Criteria**:
- All existing 432+ tests continue to pass
- New tests cover every added pattern and every security-Loa interaction
- Integration test: run Bridgebuilder on a mock Loa-mounted repo and verify zero framework file findings

## 6. Technical & Non-Functional Requirements

### NFR-1: Performance

- Pattern matching must remain O(n) per file (no regex compilation per-call)
- `repoRoot` detection must cache result (one `execSync` per review run, not per file)

### NFR-2: Backward Compatibility

- Existing `.reviewignore` files continue to work
- Non-Loa repos are completely unaffected
- `loaAware: false` config override still disables all Loa filtering

### NFR-3: Zone Definition — System Zone

The code currently doesn't define what constitutes a "Loa system zone" explicitly. This needs a clear definition:

```
System Zone: .claude/**, grimoires/**, .beads/**, evals/**, .run/**, tests/**, skills/**
Config Zone: .loa-version.json, .loa.config.yaml, .loa.config.yaml.example, PROCESS.md, BUTTERFREEZONE.md, INSTALLATION.md, NOTES.md
```

Files in the System Zone are always excluded (Tier 1/2). Files in Config Zone are always excluded (Tier 1). The distinction helps with future extensibility.

## 7. Scope & Prioritization

### In Scope (This Cycle)

1. Expand `LOA_EXCLUDE_PATTERNS` with missing paths (Bug 1)
2. Fix security-Loa precedence in `classifyLoaFile()` (Bug 2)
3. Auto-resolve `repoRoot` in `resolveConfig()` (Bug 3)
4. Add CLI `--repo-root` flag and `BRIDGEBUILDER_REPO_ROOT` env var
5. Test coverage for all fixes
6. Rebuild dist/ artifacts

### Out of Scope

- `.reviewignore` UI/editor support
- Custom per-repo zone definitions
- Bridgebuilder persona changes
- Review output format changes
- Performance optimization beyond caching

## 8. Risks & Dependencies

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Over-excluding — hiding app files that happen to be under `tests/` or `skills/` | Medium | Medium | Only exclude when Loa is detected; `tests/` exclusion is Loa-specific |
| Under-excluding — missing a Loa path we don't know about yet | Low | Low | `.reviewignore` provides user-level escape hatch |
| `git rev-parse` failure in CI environments | Low | Low | Graceful fallback to `cwd()` with warning |
| Security file review loss — genuine security files under Loa paths not reviewed | Medium | High | Tier 2 approach (summary-only) instead of full exclusion |

### Dependencies

- Node.js `child_process.execSync` for `git rev-parse` (already available)
- Existing test infrastructure (`vitest` + test fixtures)
- No external dependencies added

## 9. File Map

| File | Change Type | Description |
|------|-------------|-------------|
| `.claude/skills/bridgebuilder-review/resources/core/truncation.ts` | Modify | FR-1 (patterns), FR-2 (classifyLoaFile) |
| `.claude/skills/bridgebuilder-review/resources/config.ts` | Modify | FR-3 (repoRoot resolution) |
| `.claude/skills/bridgebuilder-review/resources/core/types.ts` | Modify | Add CLIArgs.repoRoot, EnvVars.BRIDGEBUILDER_REPO_ROOT |
| `.claude/skills/bridgebuilder-review/resources/__tests__/truncation.test.ts` | Modify | FR-1 + FR-2 test cases |
| `.claude/skills/bridgebuilder-review/resources/__tests__/loa-detection.test.ts` | Modify | FR-2 + FR-3 test cases |
| `.claude/skills/bridgebuilder-review/resources/__tests__/config.test.ts` | Modify | FR-3 config resolution tests |
| `.claude/skills/bridgebuilder-review/dist/**` | Rebuild | Compiled output |
