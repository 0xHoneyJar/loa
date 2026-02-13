# SDD: Bridgebuilder Loa-Aware Filtering — 3 Leakage Gaps

> Source: PRD cycle-010, Issue [#309](https://github.com/0xHoneyJar/loa/issues/309)
> Cycle: cycle-010

## 1. Executive Summary

Three surgical fixes to the Bridgebuilder's Loa-aware filtering in `truncation.ts` and `config.ts`. All changes are confined to the existing `.claude/skills/bridgebuilder-review/resources/` TypeScript codebase. No new files, no new dependencies, no architectural changes — just closing gaps in the existing system.

## 2. Architecture Context

### Current Data Flow

```
main.ts → resolveConfig() → ReviewPipeline → template.buildPrompt()
  → truncateFiles(files, config)
    → detectLoa(config)           // Is this repo Loa-mounted?
    → loadReviewIgnore(repoRoot)  // Merge LOA_EXCLUDE_PATTERNS + .reviewignore
    → applyLoaTierExclusion()     // Two-tier exclusion: tier1 (stats) / tier2 (summary) / exception
      → matchesExcludePattern()   // Glob matching against patterns
      → classifyLoaFile()         // Security check → tier classification
    → [user excludePatterns]      // Additional user-defined patterns
    → [risk sort + budget]        // High-risk first, byte budget cap
```

### Files To Modify

| File | Lines | Change |
|------|-------|--------|
| `core/truncation.ts` | 961 | Fix 1 (patterns), Fix 2 (classifyLoaFile) |
| `config.ts` | ~400 | Fix 3 (repoRoot resolution) |
| `core/types.ts` | ~90 | Add CLIArgs.repoRoot, EnvVars field |
| `__tests__/truncation.test.ts` | ~430 | New test cases for Fix 1 |
| `__tests__/loa-detection.test.ts` | ~380 | New test cases for Fix 2 + Fix 3 |
| `__tests__/config.test.ts` | ~300 | New test cases for Fix 3 |

All paths relative to `.claude/skills/bridgebuilder-review/resources/`.

## 3. Fix 1: Expand `LOA_EXCLUDE_PATTERNS`

### 3.1 Design

Add missing Loa-managed paths to the existing array at `truncation.ts:156-163`.

### 3.2 Implementation

```typescript
// truncation.ts:156-163 → expand to:
export const LOA_EXCLUDE_PATTERNS = [
  // Core framework (existing)
  ".claude/**",
  "grimoires/**",
  ".beads/**",
  ".loa-version.json",
  ".loa.config.yaml",
  ".loa.config.yaml.example",
  // State & runtime (new — Bug 1)
  "evals/**",
  ".run/**",
  ".flatline/**",
  // Docs & config (new — Bug 1)
  "PROCESS.md",
  "BUTTERFREEZONE.md",
  "INSTALLATION.md",
  "NOTES.md",
];
```

### 3.3 Decision: `tests/**` and `skills/**`

**Not included** in `LOA_EXCLUDE_PATTERNS`. Rationale:

- `tests/` and `skills/` are common directory names that could exist in any project. Including them would over-exclude in non-Loa contexts where the user happens to have a `.loa-version.json`.
- The existing `evals/` directory is Loa-specific (no standard project uses `evals/`). `tests/` is generic.
- Users can add `tests/**` to `.reviewignore` if their Loa tests are not relevant to reviews.

### 3.4 Test Cases

| Test | Input | Expected |
|------|-------|----------|
| evals file excluded | `evals/suites/basic.ts` | Matched by `evals/**` |
| .run state excluded | `.run/sprint-plan-state.json` | Matched by `.run/**` |
| .flatline excluded | `.flatline/runs/abc.json` | Matched by `.flatline/**` |
| PROCESS.md excluded | `PROCESS.md` | Exact match |
| BUTTERFREEZONE.md excluded | `BUTTERFREEZONE.md` | Exact match |
| NOTES.md excluded | `NOTES.md` | Exact match |
| INSTALLATION.md excluded | `INSTALLATION.md` | Exact match |
| src/ NOT excluded | `src/index.ts` | No match |
| tests/ NOT excluded | `tests/unit/foo.test.ts` | No match (intentional) |
| app/ NOT excluded | `app/page.tsx` | No match |

## 4. Fix 2: Security-Loa Precedence in `classifyLoaFile()`

### 4.1 Design Decision: Tier 2 Demotion for System Zones

**Chosen approach**: Option B from PRD — demote security matches to Tier 2 (summary-only) when the file is in a Loa system zone. This preserves visibility (the file appears in the summary) without wasting tokens on full diffs of framework files.

**Why not Option A (full exclusion)**: Security files under Loa paths might occasionally contain relevant changes (e.g., `.claude/scripts/detect-secrets.sh` patterns updated). Tier 2 gives the reviewer a first-hunk summary to assess relevance.

### 4.2 System Zone Definition

```typescript
// New constant in truncation.ts
const LOA_SYSTEM_ZONE_PREFIXES = [
  ".claude/",
  "grimoires/",
  ".beads/",
  "evals/",
  ".run/",
  ".flatline/",
];

function isLoaSystemZone(filename: string): boolean {
  return LOA_SYSTEM_ZONE_PREFIXES.some(prefix => filename.startsWith(prefix));
}
```

### 4.3 Modified `classifyLoaFile()`

```typescript
// truncation.ts:286-310 → modify to:
export function classifyLoaFile(filename: string): LoaTier {
  if (isHighRisk(filename)) {
    // Bug 2 fix: Loa system zone files capped at tier2, not exception
    if (isLoaSystemZone(filename)) {
      return "tier2";
    }
    return "exception";
  }

  // ... rest unchanged (lines 292-310)
}
```

### 4.4 Behavior Matrix

| File | isHighRisk | isLoaSystemZone | Result | Rationale |
|------|-----------|----------------|--------|-----------|
| `.claude/protocols/security-hardening.md` | Yes (`/security/i`) | Yes | **tier2** (was exception) | Framework doc, not app security |
| `.claude/scripts/detect-secrets.sh` | Yes (`/secret/i`) | Yes | **tier2** (was exception) | Framework script, summary sufficient |
| `src/auth/login.ts` | Yes (`/auth/i`) | No | **exception** (unchanged) | App code, not under Loa path |
| `.github/workflows/deploy.yml` | Yes (`/workflows/i`) | No | **exception** (unchanged) | Not under Loa path at all |
| `grimoires/loa/security-notes.md` | Yes (`/security/i`) | Yes | **tier2** (was exception) | Grimoire content |
| `SECURITY.md` | Yes (`/SECURITY.md/i`) | No | **exception** (unchanged) | Root-level policy file |

Note: `.github/workflows/` files are NOT in `LOA_EXCLUDE_PATTERNS`, so they never reach `classifyLoaFile()` — they're handled by the normal truncation pipeline. This is correct behavior.

### 4.5 Test Cases

| Test | Input | Expected |
|------|-------|----------|
| Loa security → tier2 | `.claude/protocols/security-hardening.md` | `"tier2"` |
| Loa secret → tier2 | `.claude/scripts/detect-secrets.sh` | `"tier2"` |
| Loa crypto → tier2 | `.claude/adapters/crypto-utils.ts` | `"tier2"` |
| App security → exception | `src/security/middleware.ts` | `"exception"` |
| App auth → exception | `lib/auth/oauth.ts` | `"exception"` |
| CODEOWNERS → exception | `CODEOWNERS` | `"exception"` (not in system zone) |
| Root SECURITY.md → exception | `SECURITY.md` | `"exception"` (not in system zone) |

### 4.6 Export `isLoaSystemZone` for Testing

Export the helper function so tests can verify zone membership directly:

```typescript
export function isLoaSystemZone(filename: string): boolean {
  return LOA_SYSTEM_ZONE_PREFIXES.some(prefix => filename.startsWith(prefix));
}
```

## 5. Fix 3: Auto-Resolve `repoRoot` in Config

### 5.1 Design

Add `repoRoot` resolution to `resolveConfig()` with 3-level precedence:
1. CLI flag `--repo-root` (highest)
2. Environment variable `BRIDGEBUILDER_REPO_ROOT`
3. Git auto-detection via `git rev-parse --show-toplevel`

### 5.2 Type Changes

```typescript
// types.ts — CLIArgs (add to existing interface, wherever it's defined in config.ts)
repoRoot?: string;

// config.ts — EnvVars interface (add field)
BRIDGEBUILDER_REPO_ROOT?: string;
```

### 5.3 CLI Parsing

Add to the argument parsing switch in `config.ts` (around lines 68-117):

```typescript
case "--repo-root":
  if (i + 1 >= args.length) throw new Error("--repo-root requires a value");
  cliArgs.repoRoot = args[++i];
  break;
```

### 5.4 Resolution Function

```typescript
// New function in config.ts
import { execSync } from "node:child_process";

function resolveRepoRoot(cli: CLIArgs, env: EnvVars): string | undefined {
  // 1. CLI flag (highest priority)
  if (cli.repoRoot) return cli.repoRoot;

  // 2. Environment variable
  if (env.BRIDGEBUILDER_REPO_ROOT) return env.BRIDGEBUILDER_REPO_ROOT;

  // 3. Git auto-detection
  try {
    return execSync("git rev-parse --show-toplevel", {
      encoding: "utf-8",
      timeout: 5000,
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
  } catch {
    // Not a git repo or git not available — fall back to cwd
    return undefined;
  }
}
```

### 5.5 Integration in `resolveConfig()`

Add near the top of the returned config object (around line 354):

```typescript
const repoRoot = resolveRepoRoot(cliArgs, envVars);

return {
  // ... existing fields ...
  repoRoot,  // Add this field
};
```

### 5.6 Warning Behavior Change

With `repoRoot` auto-resolved, the warning in `detectLoa()` (truncation.ts:220-223) will only fire when:
- Not in a git repo AND no CLI/env override
- This is expected behavior — the warning becomes useful instead of noisy

### 5.7 Test Cases

| Test | Setup | Expected |
|------|-------|----------|
| CLI override | `--repo-root /custom/path` | `config.repoRoot === "/custom/path"` |
| Env override | `BRIDGEBUILDER_REPO_ROOT=/env/path` | `config.repoRoot === "/env/path"` |
| CLI > env precedence | Both set | CLI value wins |
| Git auto-detect | In a git repo, no overrides | `config.repoRoot === git rev-parse result` |
| Non-git fallback | Not in git repo, no overrides | `config.repoRoot === undefined` |
| No warning when resolved | repoRoot set | No stderr warning from detectLoa() |

### 5.8 Caching

`resolveRepoRoot()` is called once per `resolveConfig()` invocation, which happens once per review run. The result is stored in the config object and passed through the pipeline. No additional caching needed.

## 6. Build & Dist

After all changes, rebuild the compiled output:

```bash
cd .claude/skills/bridgebuilder-review
npm run build
```

The `dist/` directory must be committed with the source changes. This is the existing pattern — the skill runs from compiled JS.

## 7. Sprint Estimation

| Sprint | Scope | Estimated Effort |
|--------|-------|-----------------|
| Sprint 1 | Fix 1 (patterns) + Fix 2 (classifyLoaFile) + tests | Medium |
| Sprint 2 | Fix 3 (repoRoot) + config tests + integration test + build | Medium |

Two sprints to separate the truncation-only changes (no new imports) from the config changes (requires `child_process` import and CLI parsing changes).

## 8. Risk Assessment

| Risk | Mitigation |
|------|------------|
| Over-excluding `evals/` in non-Loa repos | `evals/` only excluded when `detectLoa()` returns `isLoa: true` |
| `execSync` hanging in CI | 5-second timeout, stdio piped to prevent TTY issues |
| Tier 2 demotion hiding real security issues | Tier 2 includes first hunk summary — reviewer still sees context |
| Compiled dist/ drift | Build step included in sprint plan; CI shell lint validates |
