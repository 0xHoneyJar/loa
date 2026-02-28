# Sprint Plan: Community Feedback — Review Pipeline Hardening

**Cycle**: cycle-048
**PRD**: grimoires/loa/prd.md
**SDD**: grimoires/loa/sdd.md
**Created**: 2026-02-28
**Sprints**: 4 (global IDs: 98-101)
**Total FRs**: 6

## Sprint Overview

Six targeted fixes to the review pipeline, driven by community feedback (Issues #425, #426, #427, #430). All changes are in the `.claude/scripts/` System Zone (authorized for this cycle). The sprint order follows dependency chains: curl guard → error surfacing → verdict normalization, with TypeScript and independent scripts interleaved for balanced sizing.

| Sprint | Label | FRs | Dependency |
|--------|-------|-----|------------|
| 1 | Foundation — Curl Guard, Error Surfacing, YAML Regex | FR-6, FR-4, FR-2 | None |
| 2 | Verdict Centralization & Flatline Readiness | FR-1, FR-3 | Sprint 1 (FR-4 before FR-1) |
| 3 | Timeout Consolidation & Migration | FR-5 | None |
| 4 | Integration Testing, CI Lint, Protocol Docs | Cross-cutting | Sprints 1-3 |

---

## Sprint 1: Foundation — Curl Guard, Error Surfacing, YAML Regex

**Global ID**: 98
**FRs**: FR-6, FR-4, FR-2
**Rationale**: FR-6 (curl guard) is a dependency for FR-4 (error surfacing uses the same curl pipeline). FR-2 (TypeScript regex) is isolated and placed early to minimize dist/ merge conflicts with concurrent PRs.

### Tasks

| ID | Task | Acceptance Criteria |
|----|------|---------------------|
| T1.1 | Create `write_curl_auth_config()` in lib-security.sh (FR-6) | Function in `.claude/scripts/lib-security.sh`. Rejects keys containing CR/LF/null/backslash with clear error. Escapes double quotes. Uses `mktemp` + `chmod 600` + `printf`. Accepts valid base64 chars (+, /, =). Returns config file path on stdout. |
| T1.2 | Migrate curl config sites to `write_curl_auth_config()` (FR-6) | **10 sites** migrated across 7 files: `lib-curl-fallback.sh` (211-215), `constructs-auth.sh` (156-159), `constructs-browse.sh` (117-120, 179-182), `flatline-proposal-review.sh` (169-170, 232), `flatline-validate-learning.sh` (256-257, 321), `flatline-learning-extractor.sh` (307-308), `flatline-semantic-similarity.sh` (186-187). All use centralized helper. Existing functionality preserved. _(Flatline SPR-01: expanded from 4 to 10 sites)_ |
| T1.3 | Write curl config guard BATS tests (FR-6) | `tests/unit/curl-config-guard.bats` created. Tests: valid key, CR rejection, LF rejection, null rejection, backslash rejection, quote escaping, base64 chars accepted, file permissions 0600. All pass in isolation. |
| T1.4 | Surface API error messages in 401 handler (FR-4) | `lib-curl-fallback.sh` `call_api()` 401 handler extracts `.error.message` from response. Error passed through `redact_log_output()` (positional arg). Non-JSON bodies fall back gracefully. Uses if/else (specific OR generic, not both). |
| T1.5 | Write API error surfacing BATS tests (FR-4) | `tests/unit/api-error-surfacing.bats` created. Tests: JSON error body, HTML body fallback, empty body fallback, key fragment redaction, JSON without `.error` fallback. All pass in isolation. |
| T1.6 | Fix bridgebuilder YAML parser regex (FR-2) | config.ts line 189 regex inner capture: `\s+` → `[ \t]+`. `bridgebuilder_design_review:` NOT matched by `bridgebuilder:` regex. Existing config.test.ts passes. |
| T1.7 | Add `loadYamlConfig()` tests for section ordering (FR-2) | New tests in config.test.ts call `loadYamlConfig()` directly. Tests: bridgebuilder before/after red_team, `bridgebuilder_design_review:` not captured. All tests pass. |
| T1.8 | Rebuild dist/ and commit (FR-2) | `npm run build` succeeds. Built dist/ committed alongside TypeScript changes. |

---

## Sprint 2: Verdict Centralization & Flatline Readiness

**Global ID**: 99
**FRs**: FR-1, FR-3
**Rationale**: FR-1 depends on FR-4 being complete (both modify lib-curl-fallback.sh). FR-3 is independent but grouped here for balanced sprint sizing.

### Tasks

| ID | Task | Acceptance Criteria |
|----|------|---------------------|
| T2.1 | Create `extract_verdict()` in normalize-json.sh (FR-1) | Function in `.claude/scripts/lib/normalize-json.sh`. Accepts JSON via positional arg or stdin. Returns `.verdict` (priority) or `.overall_verdict` fallback. Exit 1 if neither present. |
| T2.2 | Migrate verdict check sites to `extract_verdict()` (FR-1) | **10 sites** migrated across 6 files: `gpt-review-api.sh` (116, 131), `lib-curl-fallback.sh` (318), `lib-route-table.sh` (202, 581), `normalize-json.sh` (250), `post-pr-audit.sh` (370, 491), `cache-manager.sh` (580, 581). `condense.sh` left unchanged (triple-fallback). **Semantic migration notes**: Sites using `jq -e '.verdict'` (exit code check) must change to `if verdict=$(extract_verdict "$json")` pattern. `cache-manager.sh:581` uses `"stored"` default — use `verdict=$(extract_verdict "$json") || verdict="stored"` pattern. Each site needs individual exit-code semantic verification. _(Flatline SPR-07: semantic migration risk)_ |
| T2.3 | Update existing BATS test assertions (FR-1) | 22 assertion locations across `test-gpt-review-integration.bats`, `test-gpt-review-codex-adapter.bats`, `test-gpt-review-multipass.bats` updated to test both `.verdict` and `.overall_verdict` response shapes. |
| T2.4 | Write `extract_verdict()` BATS tests (FR-1) | `tests/unit/extract-verdict.bats` created. Tests: `.verdict` present, `.overall_verdict` present, both present (`.verdict` wins), neither (exit 1), null verdict (exit 1). All pass in isolation. |
| T2.5 | Create `flatline-readiness.sh` (FR-3) | `.claude/scripts/flatline-readiness.sh` created (executable). Reads models from config via yq. Maps models→providers→env vars. Exit codes: 0=READY, 1=DISABLED, 2=NO_API_KEYS, 3=DEGRADED. GEMINI_API_KEY alias with deprecation warning. `--json` and `--quick` flags. `PROJECT_ROOT` override. |
| T2.6 | Write flatline readiness BATS tests (FR-3) | `tests/unit/flatline-readiness.bats` created. Tests: READY, DISABLED, NO_API_KEYS, DEGRADED, GEMINI_API_KEY alias, --json structure, PROJECT_ROOT override. All pass in isolation. |
| T2.7 | Integrate `flatline-readiness.sh` into simstim preflight (FR-3) | `simstim-orchestrator.sh` Phase 0 calls `flatline-readiness.sh --json`. Status logged to trajectory JSONL. DEGRADED triggers warning but does not block. DISABLED/NO_API_KEYS logged with recommendation. _(Flatline SPR-12: missing integration task)_ |

---

## Sprint 3: Timeout Consolidation & Migration

**Global ID**: 100
**FRs**: FR-5
**Rationale**: Independent of other FRs. Involves migration of 3 existing ad-hoc implementations to a canonical helper.

### Tasks

| ID | Task | Acceptance Criteria |
|----|------|---------------------|
| T3.1 | Add canonical `run_with_timeout()` to compat-lib.sh (FR-5) | Function in `.claude/scripts/compat-lib.sh`. Fallback: `timeout` → `gtimeout` → `perl` alarm (using fork+exec pattern, NOT bare exec, to preserve exit 124 convention) → warn and run without. Runtime detection (not cached). Array-based execution (`"$@"`). **Note**: bare `exec @ARGV` in perl replaces the process image and loses the `$SIG{ALRM}` handler — must use `system()` or fork+waitpid pattern instead. _(Flatline SPR-11: perl alarm exit code fix)_ |
| T3.2 | Migrate `post-pr-orchestrator.sh` timeout (FR-5) | Local `run_with_timeout()` at lines 104-133 removed. Sources `compat-lib.sh`. Calls canonical helper. Behavior preserved. |
| T3.3 | Migrate `post-pr-e2e.sh` timeout (FR-5) | Local timeout logic at lines 103-142 removed. `validate_command()` security allowlist preserved separately. Sources `compat-lib.sh` for timeout. Behavior preserved. |
| T3.4 | Migrate `golden-path.sh` bare `timeout` (FR-5) | Bare `timeout 2` at line 403 replaced with `run_with_timeout 2`. Sources `compat-lib.sh`. Works on macOS via fallback. |
| T3.6 | Migrate `butterfreezone-gen.sh` and `mount-loa.sh` bare `timeout` (FR-5) | `butterfreezone-gen.sh:345` (`timeout 30 grep`) and `mount-loa.sh:1706` (`timeout 5 git ls-remote`) migrated to `run_with_timeout`. Both source `compat-lib.sh`. _(Flatline SPR-02: 2 additional migration sites)_ |
| T3.5 | Write timeout helper BATS tests (FR-5) | `tests/unit/run-with-timeout.bats` created. Tests via PATH manipulation: timeout available, only gtimeout, only perl, none (warning). Tests: timeout fires, exit code preserved. All pass in isolation. |

---

## Sprint 4: Integration Testing, CI Lint, Protocol Docs

**Global ID**: 101
**FRs**: Cross-cutting (all FRs)
**Rationale**: Final sprint validates all FRs work together, adds CI regression prevention, and documents new patterns.

### Tasks

| ID | Task | Acceptance Criteria |
|----|------|---------------------|
| T4.1 | Create review pipeline integration test | `tests/unit/review-pipeline-integration.bats` created. Flow: curl config (FR-6) → mock 401 with JSON error (FR-4) → mock success with `.overall_verdict` (FR-1). Verifies error surfaced with redaction, verdict extracted, config validated. Passes in isolation. |
| T4.2 | Add CI lint for bare `timeout` usage (FR-5) | Lint rule flags bare `timeout` command invocations (pattern: `^\s*timeout [0-9]` or `\btimeout [0-9]` with word boundary) in `.claude/scripts/*.sh` excluding compat-lib.sh. Must NOT false-positive on `--timeout` flags, variable names, or comments. Added to CI workflow. _(Flatline SPR-02: tightened regex)_ |
| T4.3 | Add CI lint for raw curl config patterns (FR-6) | Lint rule flags raw `Authorization.*Bearer` in `.claude/scripts/*.sh` excluding lib-security.sh and comments. Added to CI workflow. |
| T4.4 | Update cross-platform-shell.md protocol (FR-5, FR-6) | `.claude/protocols/cross-platform-shell.md` documents `run_with_timeout()` (usage, fallbacks, migration) and `write_curl_auth_config()` (usage, validation, SHELL-002 ref). |
| T4.5 | Update SKILL.md with flatline readiness warning (FR-3) | Simstim SKILL.md documents fresh-per-cycle validation, references `flatline-readiness.sh` and exit codes, documents DEGRADED behavior. |

---

## Bridge Sprint 5: Bridgebuilder Iteration 1 Fixes

**Global ID**: N/A (bridge iteration)
**Source**: Bridgebuilder review iteration 1 (PR #435 comment)
**Rationale**: 3 MEDIUM + 3 LOW findings from Bridgebuilder review.

### Tasks

| ID | Task | Acceptance Criteria |
|----|------|---------------------|
| T5.1 | Fix perl alarm race condition (medium-1) | `compat-lib.sh` perl fallback: move `alarm()` after `fork()` so `$pid` is initialized before the handler can fire. Guard handler with `if $pid`. Existing tests pass. |
| T5.2 | Validate header_name in write_curl_auth_config() (medium-2) | `lib-security.sh` `write_curl_auth_config()` validates header_name against `[A-Za-z0-9-]+` pattern. Rejects names with CR/LF/special chars. Add BATS test for header name validation. |
| T5.3 | Migrate constructs-install.sh curl config sites (medium-3) | `constructs-install.sh` lines 438 and 769 migrated to `write_curl_auth_config()`. CI lint catches if missed. |
| T5.4 | Document condense.sh verdict divergence (low-1) | Add comment at `condense.sh` lines 217 and 352 explaining intentional non-migration. |
| T5.5 | Fix flatline-readiness.sh JSON construction (low-2) | Replace string interpolation with `jq -n --arg/--argjson` for providers object. |
| T5.6 | Fix null byte detection comment (low-3) | Update comment at `lib-security.sh:270-277` to correctly describe byte vs char comparison. |

---

## Flatline Sprint Review Log

**Phase**: Sprint plan review (cycle-048 Phase 6)
**Findings**: 15 total (5 HIGH, 7 MEDIUM, 1 LOW, 2 PRAISE)
**HIGH_CONSENSUS**: 5 findings auto-integrated:
- SPR-01: Curl config migration expanded from 4 to 10 sites (T1.2)
- SPR-02: Bare timeout migration expanded by 2 sites + CI lint regex tightened (T3.6, T4.2)
- SPR-07: Verdict extraction semantic migration notes added per-site (T2.2)
- SPR-11: Perl alarm fork+exec pattern noted to preserve exit 124 (T3.1)
- SPR-12: Missing simstim integration task added (T2.7)
**DISPUTED**: 0
**BLOCKERS**: 0 (SPR-01/SPR-02 resolved by scope expansion)
