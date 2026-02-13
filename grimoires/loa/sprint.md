# Sprint Plan: Bridgebuilder Loa-Aware Filtering — 3 Leakage Gaps

> Cycle: cycle-010 | Source: Issue [#309](https://github.com/0xHoneyJar/loa/issues/309)
> SDD: grimoires/loa/sdd.md

## Sprint 1: Pattern Expansion + Security-Loa Precedence

**Goal**: Fix Bug 1 (missing patterns) and Bug 2 (security bypass) in `truncation.ts`. These are the core filtering fixes that eliminate ~80% of the token waste.

### Task 1.1: Expand `LOA_EXCLUDE_PATTERNS`

**File**: `.claude/skills/bridgebuilder-review/resources/core/truncation.ts` (lines 156-163)

Add missing Loa-managed paths to the exclude array:
- `evals/**`, `.run/**`, `.flatline/**` (state & runtime)
- `PROCESS.md`, `BUTTERFREEZONE.md`, `INSTALLATION.md`, `NOTES.md` (docs)

**Acceptance Criteria**:
- `LOA_EXCLUDE_PATTERNS` contains all 13 patterns (6 existing + 7 new)
- Patterns use `**` glob syntax consistent with existing entries
- No duplicate patterns

### Task 1.2: Add `LOA_SYSTEM_ZONE_PREFIXES` and `isLoaSystemZone()`

**File**: `.claude/skills/bridgebuilder-review/resources/core/truncation.ts`

Add new constant and exported helper function (SDD 4.2):
```typescript
const LOA_SYSTEM_ZONE_PREFIXES = [".claude/", "grimoires/", ".beads/", "evals/", ".run/", ".flatline/"];
export function isLoaSystemZone(filename: string): boolean { ... }
```

**Acceptance Criteria**:
- Function exported for testing
- Returns `true` for all system zone prefixes
- Returns `false` for root-level files and app paths

### Task 1.3: Fix `classifyLoaFile()` Security-Loa Precedence

**File**: `.claude/skills/bridgebuilder-review/resources/core/truncation.ts` (lines 286-310)

Modify to check `isLoaSystemZone()` when `isHighRisk()` is true. System zone files get `"tier2"` instead of `"exception"`. Non-system-zone files keep `"exception"`.

**Acceptance Criteria**:
- `.claude/protocols/security-hardening.md` → `"tier2"` (was `"exception"`)
- `.claude/scripts/detect-secrets.sh` → `"tier2"` (was `"exception"`)
- `src/auth/login.ts` → `"exception"` (unchanged)
- `SECURITY.md` → `"exception"` (unchanged, not in system zone)
- `CODEOWNERS` → `"exception"` (unchanged, not in system zone)

### Task 1.4: Test Coverage for Fix 1 + Fix 2

**Files**:
- `.claude/skills/bridgebuilder-review/resources/__tests__/truncation.test.ts`
- `.claude/skills/bridgebuilder-review/resources/__tests__/loa-detection.test.ts`

Add test cases per SDD 3.4 and 4.5:
- 7 new pattern match tests (evals, .run, .flatline, PROCESS.md, BUTTERFREEZONE.md, NOTES.md, INSTALLATION.md)
- 3 non-match tests (src/, tests/, app/)
- 7 classifyLoaFile precedence tests (system zone demotion + non-zone exception)
- 3 isLoaSystemZone unit tests

**Acceptance Criteria**:
- All existing tests pass (117 loa-detection + 41 truncation)
- 20+ new test cases pass
- `npm test` green

### Task 1.5: Verify All Tests Pass

Run the full test suite:
```bash
cd .claude/skills/bridgebuilder-review && npm test
```

**Acceptance Criteria**:
- All existing tests pass without modification
- All new tests pass
- No regressions

---

## Sprint 2: Config Resolution + Integration + Build

**Goal**: Fix Bug 3 (repoRoot never populated), add integration test, rebuild dist/.

### Task 2.1: Add `repoRoot` to CLIArgs and EnvVars

**Files**:
- `.claude/skills/bridgebuilder-review/resources/config.ts` — CLIArgs interface + EnvVars interface

Add `repoRoot?: string` to CLIArgs. Add `BRIDGEBUILDER_REPO_ROOT?: string` to EnvVars.

**Acceptance Criteria**:
- CLIArgs has `repoRoot` optional field
- EnvVars has `BRIDGEBUILDER_REPO_ROOT` optional field
- Type checks pass

### Task 2.2: Add CLI `--repo-root` Flag Parsing

**File**: `.claude/skills/bridgebuilder-review/resources/config.ts` (argument parsing switch, ~lines 68-117)

Add case for `--repo-root` with value validation.

**Acceptance Criteria**:
- `--repo-root /path/to/repo` sets `cliArgs.repoRoot`
- Missing value after `--repo-root` throws error
- `--help` output updated (if help text exists)

### Task 2.3: Implement `resolveRepoRoot()` Function

**File**: `.claude/skills/bridgebuilder-review/resources/config.ts`

New function per SDD 5.4: CLI > env > `git rev-parse --show-toplevel` > undefined.

**Acceptance Criteria**:
- CLI flag takes highest precedence
- Env var takes second precedence
- Git auto-detection works in git repos
- Non-git repos return `undefined` (no crash, no hang)
- 5-second timeout on `execSync`

### Task 2.4: Integrate `repoRoot` in `resolveConfig()`

**File**: `.claude/skills/bridgebuilder-review/resources/config.ts` (~line 354)

Call `resolveRepoRoot()` and include result in returned config object.

**Acceptance Criteria**:
- `config.repoRoot` is set when in a git repo
- `detectLoa()` receives `repoRoot` from config
- Warning message only fires in non-git scenarios

### Task 2.5: Test Coverage for Fix 3

**Files**:
- `.claude/skills/bridgebuilder-review/resources/__tests__/config.test.ts`
- `.claude/skills/bridgebuilder-review/resources/__tests__/loa-detection.test.ts`

Add test cases per SDD 5.7:
- CLI override test
- Env override test
- CLI > env precedence test
- Git auto-detect test (mock `execSync`)
- Non-git fallback test
- No-warning-when-resolved test

**Acceptance Criteria**:
- 6+ new test cases pass
- All existing config tests pass
- `npm test` green

### Task 2.6: Rebuild Dist and Verify

```bash
cd .claude/skills/bridgebuilder-review && npm run build
```

**Acceptance Criteria**:
- `dist/` directory updated with compiled output
- No TypeScript compilation errors
- Full test suite passes after rebuild
