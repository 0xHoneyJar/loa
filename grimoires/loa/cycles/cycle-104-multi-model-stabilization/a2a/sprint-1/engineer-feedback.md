# Sprint 1 Senior Lead Review

**Sprint**: cycle-104 Sprint 1 (Framework Archival Hygiene + BB Dist Drift Gate)
**Branch**: `feature/cycle-104-sprint-1-archive-hygiene`
**Commits**: `aab8f82d` (kickoff) → `84771cef` (archive-cycle fix) → `d66c66f0` (BB dist gate)
**Reviewer**: Senior Tech Lead (cycle-104 reviewing-code skill, 2026-05-12)

---

## Verdict

**All good (with noted concerns)**

Sprint 1 ships. 19/19 net-new bats tests pass, ACs verified with file:line evidence, #848 reproduction resolved (`archive-cycle.sh --cycle 103 --dry-run` now enumerates per-cycle subdir artifacts; was empty pre-fix). Concerns below are non-blocking — documented for follow-up but do not gate the merge.

---

## AC Verification Cross-Check

I re-walked every AC against the actual code (not just trusting the report). Findings:

| AC | Status | Verification |
|----|--------|-------------|
| AC-1.1 | ✓ Met | `_resolve_cycle_id` at `.claude/scripts/archive-cycle.sh:81-87` + `_resolve_cycle_artifact_root` at L95-130 confirmed correct; 6 bats tests pin behavior |
| AC-1.2 | ✓ Met | Realpath canonicalization at L113-121 handles relative-vs-absolute. Legacy path falls back at L129. |
| AC-1.3 | ✓ Met | `RETENTION_FROM_CLI` flag at L48-52 + `load_config` gate at L72. Tests pin 5 vs 50 vs 0 explicitly. |
| AC-1.4 | ✓ Met | Modern subdirs at L196-198; legacy compound at L201-203 |
| AC-1.5 | ✓ Met | `check-bb-dist-fresh.sh:149-187` produces all 4 outcomes; 8 bats tests verify |
| AC-1.6 | ✓ Met | Content-hash via `sha256sum` at `tools/check-bb-dist-fresh.sh:91`; `AC-1.6: touching source file without changing content does NOT trigger drift` test confirms mtime-immunity |
| AC-1.7 | ⚠ Partial — ACCEPTED | Runbook landed at canonical path. Cross-link from CLAUDE.md/PROCESS.md deferred (PROCESS.md doesn't exist; CLAUDE.md cross-link can land in feedback iteration if explicitly requested). **I accept this as ACCEPTED-DEFERRED**. See concern #3 below for follow-up. |
| AC-1.8 | ✓ Met | Runbook L48-58 explicit on keep-newest-N semantics |

---

## Adversarial Analysis

### Concerns Identified

#### 1. `find -printf` is GNU-only — macOS operators will hit silent failure (NON-BLOCKING)

**Location**: `.claude/scripts/archive-cycle.sh:260`

```bash
find "$ARCHIVE_DIR" -maxdepth 1 -mindepth 1 -type d \
  \( -name "cycle-*" -o -name "20[0-9][0-9]-*" \) -printf '%T@\t%p\n' 2>/dev/null \
```

`-printf` is a GNU find extension. BSD/macOS find lacks it. The `2>/dev/null` redirect swallows the error, the pipeline produces an empty stream, the archives array stays empty, and the script silently reports "Nothing to delete" regardless of actual archive count. CI runs on `ubuntu-latest` so this won't surface in pipeline runs, but operators on macOS workstations would see broken `--retention` semantics. No-op silent failure is the worst-of-both-worlds — same shape as the original #848 bug class.

**Suggested follow-up** (NOT blocking this sprint, but file an issue and address in Sprint 2 or a sprint-bug):
- Detect with `uname -s`, branch to `stat -c %Y / stat -f %m`, or use Python one-liner
- Document Linux-only constraint explicitly in runbook + script header
- Add a portability bats test (skip on macOS or vice-versa)

This pattern-matches **`feedback_scanner_glob_blindness.md`** from project memory — silent extension-class failures.

#### 2. Initial `dist/.build-manifest.json` baseline pins current source-vs-dist state without verifying freshness (NON-BLOCKING)

**Location**: `.claude/skills/bridgebuilder-review/dist/.build-manifest.json` (committed in `d66c66f0`)

The manifest hashes SOURCE files only. It writes "this is what `resources/**/*.ts` looked like at write time." It does NOT verify that the committed `dist/` actually corresponds to that source. If the BB dist tree was already stale relative to source at commit time (a possibility — cycle-103 nearly shipped exactly this case), the baseline manifest LOCKS IN that stale relationship. The CI gate only catches FUTURE drift.

**Suggested follow-up** (NOT blocking, but worth a Sprint 1 amendment commit if reviewer agrees):
- Run `npm run build` before committing the manifest as a final pre-merge step
- Confirm `git diff dist/` shows zero changes after the build
- Then commit the freshly-generated manifest

If the build produces dist diffs, that's important to know NOW (during this sprint), not as a surprise on first BB PR after merge. **The engineer's note in reviewer.md "Known Limitations §2" acknowledges this** — I'm escalating the suggestion: do this BEFORE final merge, not as a post-merge fix.

#### 3. AC-1.7 PROCESS.md gap is real but defensible (NON-BLOCKING)

PROCESS.md genuinely does not exist in this repo. CLAUDE.md edits are cycle-scope authorized. The runbook lives at the canonical path. **Acceptable closure path**: link from the existing `grimoires/loa/runbooks/` directory README (if one exists) or add a one-line reference in `grimoires/loa/NOTES.md` under a "Runbooks" section. Either path is sub-5-minute work and avoids the CLAUDE.md edit. Recommend doing this BEFORE final merge as an amendment commit. ALTERNATIVELY accept as deferred and add a Decision Log entry in NOTES.md.

### Assumptions Challenged

#### Assumption: "Linux-only deployment is acceptable for archive-cycle.sh"

The engineer assumed (implicitly) that GNU find is universally available. This is true for CI but not operator workstations. Cycle-099 PR #727 contributor zksoju was on macOS per the upstream-extraction PR history. Future contributors may be too.

**Risk if wrong**: Operators on macOS see silent breakage of `--retention` semantics. Same UX impact as the original #848 bug ("doesn't respect retention count").

**Recommendation**: Make portability explicit. Either:
- (a) Document Linux-only at script header + runbook (operator-side workaround: run script in Docker / WSL)
- (b) Add BSD branch (file follow-up sprint task; not blocking Sprint 1 close)

#### Assumption: "Engineer-side `npm run build` produces deterministic dist output"

The drift gate assumes that running `npm run build` on the engineer's machine produces byte-identical output to running it on CI. TypeScript compilation can be sensitive to:
- Node version (engine declares >=20 — but >=20.0.0 vs >=20.10.0 differ)
- TypeScript version (5.9.3 pinned in `devDependencies` ✓ good)
- `tsconfig.json` `incremental` cache state
- Platform-specific line endings (especially if Windows contributor edits source)

**Risk if wrong**: Engineer regenerates dist locally → CI re-checks and finds different dist → gate fails on PR with no actionable diff. False-positive cycle.

**Recommendation**: This is a known TypeScript-build-determinism problem and likely accepted scope-out (mirrors cycle-099 sprint-1A `gen-bb-registry:check` precedent). But worth a note in the runbook: "If gate fails after `npm run build`, check Node version matches CI's matrix entry."

### Alternatives Not Considered

#### Alternative: Reorder `load_config` BEFORE `parse_args` instead of adding `RETENTION_FROM_CLI` flag

**Approach**: Move `load_config` call before `parse_args` in `main()`. Then `parse_args` naturally wins because it runs last.

**Tradeoff**:
- Simpler: removes the explicit flag, removes the conditional in `load_config`
- BUT: violates "principle of least surprise" for future maintainers — yaml-then-CLI is the canonical config-cascade pattern; reversing it would be surprising
- Also: it's a heavier diff for the same outcome, and future config sources (env vars, other yaml keys) would need the same reverse-cascade

**Verdict**: Current approach (RETENTION_FROM_CLI flag) is more explicit and extensible. JUSTIFIED.

#### Alternative: Use `python3 -c` for portability instead of `find -printf`

**Approach**: Drop in a 5-line python invocation that lists dir entries with mtimes.

**Tradeoff**:
- Cross-platform (Linux + macOS + Windows under WSL)
- Adds python3 as a runtime dep (already present in repo per `tools/check-no-direct-llm-fetch.sh` which uses Python for canonicalization)
- 5-line python is harder to grep than a single `find` invocation

**Verdict**: Either is defensible. Current `find -printf` is simpler-looking but less portable. RECOMMEND follow-up issue for portability fix (see Concern #1).

---

## Documentation Verification

| Item | Status | Notes |
|------|--------|-------|
| CHANGELOG entry | ✓ N/A | Cycle-104 mid-sprint commits per cycle-103 precedent — CHANGELOG entries land at cycle close (v1.131.0 named-release pattern) |
| CLAUDE.md for new commands | ✓ N/A | No new commands added |
| `archive-cycle.sh` runbook | ✓ Met | `grimoires/loa/runbooks/cycle-archive.md` (198 LOC) |
| Code comments | ✓ Met | Helper functions, cleanup, and the RETENTION_FROM_CLI fix all have load-bearing comments explaining the why |

---

## Code Quality Notes

### Strengths
- **Realpath canonicalization fix is well-reasoned** (L113-121). The "resolved is relative, GRIMOIRE_DIR is absolute" insight is the kind of edge case that bites engineers months after the fact. Comment explains it.
- **Bats test pattern documented in reviewer.md** — `LOA_REPO_ROOT` + `unset PROJECT_ROOT` should propagate to future hermetic bats tests. Recommend extracting to `.claude/rules/bats-hermetic-tests.md` in a follow-up.
- **`|| true` defensive markers on conditional echoes** (L174-179) — technically overkill (set -e doesn't trip on `&&`-list left side per bash manual), but they document operator intent clearly.
- **JSON output mode for the drift gate** is good agent-ergonomic design — CI workflows + future automation can parse `outcome` directly without text-matching.

### Minor Inefficiencies (non-blocking)
- `tools/check-bb-dist-fresh.sh:97-105` (`compute_source_hash`) and `:119-125` (manifest writer's files-list construction) re-enumerate `list_source_files` and re-hash each file. With 41 BB source files this is negligible (<1s extra). With 1000s of files, it'd be slow. Not worth fixing unless BB source grows materially.
- `cleanup_old_archives` reads the entire archives array into memory before iterating. Fine for the current ~50-archive scale. Pre-existing pattern.

### Pre-existing issues NOT introduced this sprint (worth a future sprint-bug)
- `get_current_cycle()` (L132-139) returns `.cycles | length` which is the ARRAY LENGTH (37 today), not the actual cycle number. When `--cycle` is absent, the script attempts to archive cycle-37, which isn't a real cycle id. Pre-existing bug; not regressed; but the new resolver makes it more visible (script will say "Cycle id: (not found in ledger)" instead of silently producing empty archive).

---

## Previous Feedback Status

N/A — first review iteration for Sprint 1.

---

## Sprint Status

Sprint 1 acceptance criteria summary (per sprint.md §Sprint 1):

- [x] AC-1.1 — per-cycle-subdir resolution (modern cycles ≥098)
- [x] AC-1.2 — legacy fallback (cycles ≤097)
- [x] AC-1.3 — --retention N honored (the load-bearing #848 fix)
- [x] AC-1.4 — modern subdirs (handoffs/a2a/flatline) + legacy compound copied
- [x] AC-1.5 — BB dist drift gate pass/fail outcomes
- [x] AC-1.6 — content-hash (not timestamp) false-positive defense
- [x] AC-1.7 — runbook landed (cross-link deferred — accepted)
- [x] AC-1.8 — keep-newest-N semantics documented

Sprint 1 closes G6 (framework archival hygiene) + G7 (BB dist build hygiene). Cycle-104's own ship-time archive depends on Sprint 1 holding.

---

## Next Steps for /run Orchestrator

1. **Optional pre-audit amendment**: Address Concern #2 (run `npm run build` to verify dist freshness, commit any resulting dist diff + regenerated manifest as a 4th commit).
2. **Proceed to `/audit-sprint sprint-1`** — security/quality audit gate.
3. **Concerns #1 (macOS portability) + Pre-existing `get_current_cycle` bug** should be filed as cycle-104 follow-up sprint-bug tasks OR pushed to a future cycle. They're non-blocking for Sprint 1 close.

---

🤖 Reviewed by Senior Tech Lead (cycle-104 reviewing-code), 2026-05-12
