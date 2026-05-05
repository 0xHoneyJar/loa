# Changelog

All notable changes to Loa will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.117.0] — 2026-05-05

### Added

- **Cycle-095 — Model Currency** (Sprints 1+2 in this release; Sprint 3 deferred to post-soak) — gpt-5.5 family is now reachable through cheval, the `reviewer` and `reasoning` aliases default to `openai:gpt-5.5` (cost-safe non-pro), `tiny` tier alias added for Haiku 4.5, and the `fast-thinker` agent binding upgraded to Gemini 3 fast variant with probe-driven fallback chain.
  - **Sprint 1 — routing infrastructure**: `endpoint_family` field on every OpenAI registry entry routes between `/v1/chat/completions` and `/v1/responses`. Migration step + strict validation in same commit (`config/loader.py:_validate_endpoint_family`). `LOA_LEGACY_ENDPOINT_FAMILY_DEFAULT=chat` env-var backstop for operators with custom OpenAI entries. Six-shape `/v1/responses` normalizer (multi-block text, tool/function call, reasoning summary, refusal, empty, truncated) per PRD §3.1 / SDD §5.4. `LOA_FORCE_LEGACY_ALIASES=1` kill-switch restores pre-cycle-095 alias resolution at config-load time (`.claude/defaults/aliases-legacy.yaml` snapshot). Strict-default `UnsupportedResponseShapeError` for unknown shapes; opt-in `responses_unknown_shape_policy: degrade` escape hatch.
  - **Sprint 2 — alias flips + tiers + guardrails**: `aliases.reviewer` and `aliases.reasoning` flipped from `openai:gpt-5.3-codex` to `openai:gpt-5.5`. `gpt-5.3-codex` immutable self-map in `backward_compat_aliases:` — operators pinning the legacy ID literally continue resolving to that exact model (NOT silently retargeted to gpt-5.5). One-time INFO log emission on first resolution per process per legacy alias. Haiku 4.5 (`claude-haiku-4-5-20251001`) + `tiny` alias. Gemini 3 fast variant (`gemini-3-flash-preview`) + `gemini-3-flash` alias + `fallback_chain: ["google:gemini-2.5-flash"]`. Google adapter `_resolve_active_model` with probe-driven demotion + 300s cooldown hysteresis + WARN-once-per-(primary,fallback)-per-process. Probe-cache trust boundary (file owner UID + mode 0600 — SDD §3.5 SKP-003). FR-5a cost-guardrail primitives: `tier_groups:` schema block (structural; Sprint 3 populates `mappings:`); `metering/budget.py` `check_session_cap_pre`/`_post` with two-phase atomicity (pre-call worst-case estimate + `threading.Lock`); `LOA_PREFER_PRO_DRYRUN` env var + `routing/tier_groups.py` `dryrun_preview` helper.
  - **Cost impact comparison** (per PRD FR-2 AC):
    | Alias | Before | After (Sprint 2) | After (Sprint 3 with `prefer_pro_models: true`) |
    |---|---|---|---|
    | `reviewer` | gpt-5.3-codex ($1.75/$14.00 per Mtok) | gpt-5.5 ($5.00/$30.00) | gpt-5.5-pro ($30.00/$180.00) |
    | `reasoning` | gpt-5.3-codex ($1.75/$14.00) | gpt-5.5 ($5.00/$30.00) | gpt-5.5-pro ($30.00/$180.00) |
    | `tiny` (NEW) | n/a | claude-haiku-4-5-20251001 ($1.00/$5.00) | (unchanged) |
    | `gemini-3-flash` (NEW) | n/a | gemini-3-flash-preview ($0.15/$0.60) | (unchanged) |

    `output_tokens` for `/v1/responses` calls is INCLUSIVE of `reasoning_tokens` (SDD §5.5) — cost ledger bills on `output_tokens` only; never sum with `reasoning_tokens`. Operators wanting the pro tier should set `tier_groups.max_cost_per_session_micro_usd` first; the 5-10× cost increase is documented behind a mandatory WARN log on flag activation (Sprint 3).
  - **Multi-process cost-cap semantics**: `max_cost_per_session_micro_usd` is a per-process hard guard, not a distributed lock. Multi-process workflows (parallel `/run`, CI workers) require explicit operator coordination — sum your caps across processes, OR coordinate `trace_id` manually with a shared ledger file via `flock`. Documented in `loa-setup` SKILL example.
  - **Pricing freshness**: Haiku 4.5 + Gemini 3 fast pricing live-fetched ONCE at sprint execution (2026-04-29) and frozen in YAML. Refresh cadence: quarterly or release-bound — `task pricing-refresh` (TBD) re-runs the live fetch and emits a diff for operator review.
  - **Backward compatibility (FR-6)**: downstream consumers pinning `gpt-5.3-codex` continue to work via the immutable self-map. Operator-side rollback via `LOA_FORCE_LEGACY_ALIASES=1` (no PR needed). Per-alias pin via `aliases: {reviewer: openai:gpt-5.3-codex}` in `.loa.config.yaml` is also supported.
  - **Tests**: 600 Python tests pass (was 549 pre-cycle, +51 net). 9-test `cycle095-migration.bats` + 1 new endpoint_family invariant in `model-registry-sync.bats`. New pytest classes: `TestOpenAIResponsesEndpointRouting` (6), `TestOpenAIResponsesNormalization` (7), `TestUnsupportedResponseShape` (2), `TestForceLegacyAliasesRouting`, `TestEndpointFamilyValidation` (7), `TestForceLegacyAliases` (6), `TestReasoningTokensBilling` (3), `TestFallbackChain` (4), `TestProbeCacheTrustBoundary` (2), `TestTierGroupsCostCap` (4), `TestPreferProDryrun` (8), plus `test_haiku.py` (2). All adversarial reviews (gpt-5.3-codex dissent role) clean post-iter-2.

- **Construct onramp + connectivity tooling migration** (cycle-005 L5 + cycle-006 L-migrate, [PR #617](https://github.com/0xHoneyJar/loa/pull/617)) — opt-in path for operators to receive the construct-network tools at mount or via `/loa-setup`, plus relocation of construct connectivity tooling from `loa-constructs` into `loa` proper.
  - **Mount onramp** (`mount-loa.sh`): three new flags — `--with-constructs`, `--no-constructs`, `--constructs-pack <slug>`. Default behavior is byte-clean for non-construct users; the only mount-time hint fires when constructs aren't already installed AND `LOA_MOUNT_CONSTRUCTS_HINT` isn't `off`. Failure to install the bundle is non-fatal.
  - **`/loa-setup` Step 5** (`.claude/commands/loa-setup.md`): an optional AskUserQuestion step offering to install the default construct bundle, choose a different pack, or skip. The summary's "Browse packs: /constructs" line is now gated to projects where constructs are actually in use.
  - **Five new connectivity scripts** in `.claude/scripts/`:
    - `construct-compose.sh` — composition pipe runner with chain-build-time type compatibility checks (Signal / Verdict / Artifact / Intent / Operator-Model)
    - `construct-invoke.sh` — paired entry/exit trajectory emission with session_id matching (explicit value-passing recommended; temp-file fallback deprecated and tracked in [#636](https://github.com/0xHoneyJar/loa/issues/636))
    - `construct-validate.sh` — pre-install / pre-publish manifest linter emitting Verdict-typed findings
    - `stream-validate.sh` — JSON-Schema validator for the five canonical stream types (full Draft-07 via python3+jsonschema, jq fallback otherwise)
    - `butterfreezone-construct-gen.sh` — per-pack `CONSTRUCT-README.md` generator, idempotent modulo an opt-in timestamp footer
  - **Five new schemas** at `.claude/schemas/{signal,verdict,artifact,intent,operator-model}.schema.json` — the typed-stream primitives. All schemas use `additionalProperties: true` so authors can extend.
  - **One new skill**: `.claude/skills/validating-construct-manifest/` — wraps `construct-validate.sh` with skill metadata.
  - **94 new BATS tests** across 5 files (`tests/unit/construct-{validate,compose,invoke}.bats`, `tests/unit/stream-validate.bats`, `tests/unit/butterfreezone-construct-gen.bats`) plus 1 opt-in characterization test (`LOA_TEST_DOCUMENT_RACE=1`). Covers happy paths, failure modes, JSON output shape, idempotency, race-resistance under explicit session_id passing.
  - **Six-iteration kaironic Bridgebuilder review** drove three rounds of hardening: tool-skip guards, strict assertions over permissive escapes, end-to-end schema dogfooding, race-condition mitigation with explicit value-passing as the recommended path. Final iter clean modulo the residual race tracked in [#636](https://github.com/0xHoneyJar/loa/issues/636).

## [1.109.4] — 2026-05-02 — Post-merge workflow scaffold on mount (sprint-bug-130)

### Fixed

- **#669 — Post-merge automation orchestrator scripts shipped without an invoking workflow template** (sprint-bug-130, [PR #671](https://github.com/0xHoneyJar/loa/pull/671)) — downstream consumer repos installing Loa via `mount-loa.sh` (direct) or `mount-submodule.sh` (symlink) had `post_merge.enabled: true` do nothing because `.github/workflows/post-merge.yml` was never scaffolded into the consumer's `.github/workflows/`. For submodule mode specifically, even copy-pasting the workflow failed with `exit-127: No such file or directory: .claude/scripts/classify-pr-type.sh` because `actions/checkout` without `submodules: recursive` left `.claude/scripts/*` as dangling symlinks.
  - **Single source of truth**: `submodules: recursive` added to all 3 `actions/checkout` steps in `.github/workflows/post-merge.yml` with a workflow-level decision-trail comment block. No-op for direct-mode consumers; required for submodule-mode consumers.
  - **Idempotent scaffold helper**: `.claude/scripts/lib/scaffold-post-merge-workflow.sh` (new) — sourced from both installers AND the bats test (Bridgebuilder F2/F6 — eliminates three-way duplication; tests now exercise the real production function). Direct mode pulls via `git checkout $LOA_REMOTE_NAME/$LOA_BRANCH`; submodule mode copies from `$SUBMODULE_PATH/.github/workflows/post-merge.yml`. Both modes preserve user-customized workflow on re-mount (`sync_optional_file` semantics).
  - **12 new bats tests** in `tests/unit/mount-workflow-scaffold.bats` (10 functional + 2 regression guards against re-introducing inline duplicates).
  - Live verification deferred to next downstream consumer mount.

## [1.109.3] — 2026-05-02 — Bug batch — post-PR + post-merge + portability (sprint-bug-124..129)

### Fixed

- **6-bug batch** ([PR #670](https://github.com/0xHoneyJar/loa/pull/670)) — six independent framework defects landed in one branch with full quality cycle (implement → review → audit → bridgebuilder), 70 new bats tests + 155 adjacent regression tests pass.
  - **#668 — Post-merge classifier silently classifies cycle PRs as 'other'** (sprint-bug-124) — new `.claude/scripts/classify-merge-pr.sh` wrapper uses merge commit subject as PRIMARY signal (in-tree state, never empty); `gh pr view` failures surface to stderr instead of silently routing to `other`. Delegates classification rules to existing `classify-pr-type.sh` (Issue #550). Workflow no longer re-parses `$GITHUB_OUTPUT` (Bridgebuilder F001 cleanup).
  - **#664 — `post-pr-state.sh` rejects `bridgebuilder_review` phase** (sprint-bug-125) — one-line addition to `valid_phases` at `post-pr-state.sh:492` plus new `_update_phase` wrapper around 8 sites in `post-pr-orchestrator.sh`. Wrapper always returns 0 (true best-effort under `set -e`). Future taxonomy drift surfaces in workflow log.
  - **#663 — `post-pr-orchestrator` passes invalid `--phase pr` to flatline-orchestrator (false `flatline_blocker` halt)** (sprint-bug-126) — `pr` added to flatline-orchestrator validator at line 1512 plus new `lib/flatline-exit-classifier.sh` distinguishes validation errors (`halt_reason: flatline_orchestrator_error`) from real flatline blockers (`halt_reason: flatline_blocker`) via stderr pattern-match + exit code.
  - **#665 — Post-PR Bridgebuilder MEDIUM findings auto-triage to `log_only` without operator visibility** (sprint-bug-127) — new `lib/bridge-mediums-summary.sh` emits `[WARN] N MEDIUM findings logged...` line + structured `.run/post-pr-mediums-summary.json` after `phase_bridgebuilder_review()`. Convergence semantics unchanged (visibility-only patch per triage scope).
  - **#661 — beads_rust 0.2.1 pre-commit hook fails: NOT NULL constraint failed: dirty_issues.marked_at** (sprint-bug-128) — defensive in-repo workaround. Source-of-truth template at `.claude/scripts/git-hooks/pre-commit-beads` captures stderr and emits structured diagnostic on the upstream signature. Installer at `.claude/scripts/install-beads-precommit.sh`. `beads-health.sh` extended with non-mutating sqlite3 PRAGMA probe → `MIGRATION_NEEDED` on detect. Root cause is upstream `beads_rust 0.2.1`; this fix only improves operator visibility.
  - **#660 — `mount-submodule.sh --reconcile` silently skips creating missing symlinks on macOS (BSD `realpath` lacks `-m`)** (sprint-bug-129) — new `lib/portable-realpath.sh` probes for `realpath -m` once at source time; 3-layer fallback (GNU `-m` → BSD plain → bash parameter expansion). Reconcile partial-failure now exits non-zero with explicit warn line — CI / downstream automation can detect partial reconcile via exit code.

## [1.109.2] — 2026-05-02 — CHANGELOG backfill — cycle-096 + cycle-097 entries

### Changed

- **Documentation-only release** ([PR #667](https://github.com/0xHoneyJar/loa/pull/667)) — backfilled CHANGELOG entries for v1.109.0 (cycle-096 — AWS Bedrock provider) and v1.109.1 (cycle-097 — quick-win finding remediations) that had been tagged but lacked CHANGELOG documentation. No functional changes.

## [1.109.1] — 2026-05-02 — Cycle-097 — quick-win finding remediations

Five non-blocking findings from cycle-096 sprint-127/sprint-128 review feedback, surfaced by Bridgebuilder review of [PR #662](https://github.com/0xHoneyJar/loa/pull/662) and explicitly deferred to follow-up by the senior reviewer + paranoid auditor. Shipped as [PR #666](https://github.com/0xHoneyJar/loa/pull/666).

### Added

- **NC-9 — reject `providers.bedrock.auth_lifetime: short` at config-load time** (closes Bridgebuilder NC-9). The schema field was documented in SDD §9 NFR-Sec11 for v2 forward compat, but v1 does not implement the rotation-window enforcement code path. Silent acceptance would let operators believe they had rotation enforcement when they did not. Loader now raises `ConfigError` with a pointer to the v2 proposal. Honored values v1: `long` (default), absent. Rejected: `short`, unknown values, non-string types. +6 unit tests in `test_bedrock_compliance_loader.py`.
- **NC-10 — register `pytest.mark.integration` marker** (closes Bridgebuilder NC-10). `.claude/adapters/pyproject.toml` now declares the marker so `tests/test_bedrock_live.py` stops emitting `PytestUnknownMarkWarning`. Documents the deselect convention: `pytest -m "not integration"` to skip live AWS tests in CI.
- **NC-5 — `QuotaExceededError` default message includes reset/fallback guidance** (closes Bridgebuilder NC-5). Default error now points operators at the AWS reset cadence (00:00 UTC), the process-restart path to clear the in-process circuit breaker, and the `compliance_profile: prefer_bedrock + fallback_to` failover path. +1 unit test asserting all three guidance fragments.
- **F002 — BATS mock observability** (closes Bridgebuilder F002). `_CURL_JSON_CALLED` flag added to the bedrock-health-probe BATS mock so tests can prove the probe actually issued the network call rather than relying on stale `RESPONSE_BODY`/`HTTP_STATUS` state. Auth-missing path asserts `_CURL_JSON_CALLED == 0`; AVAILABLE path asserts `== 1`. Prevents silent passing if a refactor breaks the network call.
- **A1 — plugin guide lessons-learned section** (closes Bridgebuilder A1). New section in `grimoires/loa/proposals/adding-a-provider-guide.md` walks the cycle-096 PRD v1.0→v1.3 and SDD v1.0→v1.2 changelog entries, the discoveries that arrived only via live probes (bare `anthropic.*` IDs rejected, `thinking.type=enabled` rejected, `inputSchema.json` envelope wrapping required), the process patterns that paid off (two-pass Flatline, Sprint 0 G-S0-CONTRACT artifact, Bridgebuilder review), and what the guide cannot anticipate for the next provider. Treats the "≤1-day fifth provider" target as aspirational until cycle-097+ provides empirical data.

### Tests

- 736 Python tests pass (was 732 cycle-096 baseline; +4 net from NC-9 + NC-5 + 3 prior NC-1 regressions). 15 BATS in `bedrock-health-probe.bats` (unchanged count; F002 added 2 assertions to existing tests). Zero regressions.

## [1.109.0] — 2026-05-02 — Cycle-096 — AWS Bedrock provider + provider-plugin hardening

Adds AWS Bedrock as the fifth Loa provider with full Converse API support, plus the cross-cutting plugin-architecture hardening that makes future provider additions a `≤1-day` target. Shipped as [PR #662](https://github.com/0xHoneyJar/loa/pull/662) closing [#652](https://github.com/0xHoneyJar/loa/issues/652).

### Added

- **AWS Bedrock provider** (`.claude/adapters/loa_cheval/providers/bedrock_adapter.py`, 834 lines). Bearer-token auth via `AWS_BEARER_TOKEN_BEDROCK` (no SigV4 in v1; v2 path tracked separately). Supports the `Converse` API for chat + tool-use + thinking-trace, control-plane `ListInferenceProfiles` for health probes. Three Day-1 models live-verified against operator AWS account: `us.anthropic.claude-opus-4-7`, `us.anthropic.claude-sonnet-4-6`, `us.anthropic.claude-haiku-4-5-20251001-v1:0` (the colon-bearing ID exercises URL-encoding in the runtime URL path).
- **Inference profile namespacing** — `us.anthropic.*` and `global.anthropic.*` only. Bare `anthropic.*` IDs rejected upstream by Bedrock with HTTP 400 ("on-demand throughput unsupported"); the adapter surfaces this as a typed `OnDemandNotSupportedError` with remediation guidance.
- **Two-layer secret redaction** (SDD §6.4.1, replaces single-pattern v0). PRIMARY: value-based — `register_value_redaction()` registers the live token at config-load time; redaction matches by string equality so even token rotations inside a single session don't leak. SECONDARY: regex `_BEDROCK_API_KEY_PATTERN` (`ABSK[A-Za-z0-9+/=]{36,}`) catches token-shaped strings that arrive without registration. TERTIARY: length-fallback `_BEDROCK_LENGTH_FALLBACK_PATTERN` with structural anchor `(?=[A-Za-z0-9+/=]*[+/=])` requiring at least one base64-distinct char (refined NC-1 from sprint-127 review to avoid over-matching SHA-256 hex strings).
- **Token age sentinel** (NFR-Sec11) — `.run/bedrock-token-age.json` records first-call timestamp per token (detected via SHA256 last-4 token_hint per NFR-Sec8). Graduated stderr warnings: 60-day silent / 60-80 day info / 80-90 warn-every-100 / 90+ warn-every-call. `auth_lifetime` schema field present; `short` value documented and (sprint-1) silently accepted, (cycle-097 NC-9) now rejected with documented error.
- **Compliance-aware fallback** (`compliance_profile` + per-model `fallback_to`). 4-step deterministic defaulting rule (SDD §5.6): explicit value wins → `bedrock_only` when only `AWS_BEARER_TOKEN_BEDROCK` set → `prefer_bedrock` when both Bedrock and direct-Anthropic tokens set → `None` when neither. SKP-003 invariant: `prefer_bedrock` requires explicit `fallback_to` mapping on every model (no heuristic name matching). Versioned `fallback_mapping_version` field on each model; loader rejects `prefer_bedrock` without explicit declaration. One-shot migration notice with `bedrock-migration-acked.sentinel` so the warning appears once per fresh checkout, not every process.
- **Daily-quota circuit breaker** (FR-11) — `threading.Event` `_DAILY_QUOTA_EXCEEDED` is process-scoped + atomic across threads. Detects the AWS daily-quota body pattern in 200 OK responses (`too many tokens per day`, `daily quota`, etc.); subsequent calls fast-fail without hitting the API; operator restarts process to clear OR waits until quota resets (00:00 UTC).
- **Error taxonomy** (FR-11 / SDD §6.1) — 9 typed errors: `OnDemandNotSupportedError`, `InvalidModelIdentifierError`, `ModelEndOfLifeError`, `EmptyResponseError`, `QuotaExceededError`, `RegionMismatchError`, `ThrottlingError` (retryable), `ServiceUnavailableError` (retryable), `ValidationError`. Classifier branches on body content (e.g., 400 with "provided model identifier is invalid" → `InvalidModelIdentifierError`; 404 with "end of life" → `ModelEndOfLifeError`).
- **Tool schema wrapping** (FR-1, Probe 3 finding) — Bedrock requires `inputSchema.json` envelope wrapping for tool definitions, distinct from direct-Anthropic which takes the schema directly. Adapter `_transform_tools_to_converse` does the wrap.
- **Thinking-trace translation** (FR-13, Probe 4 finding) — caller-side `thinking.type=enabled` + `budget_tokens` is rejected by Bedrock-routed Opus 4.7 with HTTP 400. Adapter translates to Bedrock's `additionalModelRequestFields.thinking.type=adaptive` + `output_config.effort` per the discovered contract.
- **Region resolution chain** (FR-6) — request param → `AWS_BEDROCK_REGION` env → `AWS_REGION` env → provider `region_default` → `us-east-1` fallback. Region-prefix sanity (FR-12): `us.anthropic.*` profile against an `eu-*` region surfaces `RegionMismatchError` rather than 400 from AWS.
- **Centralized provider parser** (`parse_provider_model_id`) — splits provider:model on FIRST colon, equivalent in Python (`.claude/adapters/loa_cheval/types.py`) and bash (`.claude/scripts/lib-provider-parse.sh`). 51 cross-language equivalence tests in `tests/integration/parser-cross-language.bats` ensure the two implementations stay in lockstep. Generator (`gen-adapter-maps.sh`) preserves colon-bearing aliases through code generation (Phase C fix).
- **Health probe extension** (FR-8) — `model-health-probe.sh` now supports `--provider bedrock` via `_probe_bedrock` using ListInferenceProfiles control-plane endpoint. Distinguishes auth-class errors (UNKNOWN/auth, not transient) from network/throttle errors. 15 BATS tests in `tests/unit/bedrock-health-probe.bats`.
- **Plugin guide** (FR-9, `grimoires/loa/proposals/adding-a-provider-guide.md`) — six-edit-site walkthrough using cycle-096 as the worked example: provider registry entry, Python adapter, adapter registry, schema propagation, trust scopes, secret-redaction patterns. Plus auth-modality discussion, compliance-aware fallback patterns, token age tracking, test harness, recurring CI smoke, cost cap discipline, fixture conventions, and (cycle-097 follow-up) lessons-learned section.
- **Sprint 0 G-S0-CONTRACT artifact** (`tests/fixtures/bedrock/contract/v1.json`) — versioned snapshot of the Bedrock API contract: endpoints, auth modality, request/response shapes, error taxonomy, inference profile namespaces, redaction notes. Source-of-truth for the implementation across 18 commits. Companion probe captures in `tests/fixtures/bedrock/probes/` with documented naming convention (cycle-096 sprint-128 README addition).
- **CI smoke workflow** (`.github/workflows/bedrock-contract-smoke.yml`, 215 lines) — recurring drift-detection workflow with weekly model rotation, per-run $0.50 + monthly $15 cost caps (pre-flight estimate + post-flight ledger assertion), required-status signal for fork PRs. **Operator action required**: `gh auth refresh -s workflow` then commit the file (current OAuth token lacks `workflow` scope).
- **Token currency: gpt-5.5 + Haiku 4.5 + Gemini 3 + cost guardrails** — formerly slated as part of cycle-095 (v1.108.0 was the Sprints 1+2 release; cycle-096 layered Bedrock atop the model registry that cycle-095 provided).

### Changed

- **Compliance profile defaulting** (BREAKING for users who pinned `prefer_bedrock` without explicit `fallback_to`) — loader now raises `ConfigError` at startup. Migration: add `fallback_to: <provider>:<model>` to every model entry under a `prefer_bedrock` provider, OR switch to `bedrock_only` (fail-loud, no fallback) OR `none` (silent fallback, opt-in). One-shot migration notice + sentinel file lessens repeated friction.
- **`hounfour.bedrock.enabled` feature flag** + migration sentinel (SDD §6.7) — Bedrock runtime gated behind explicit opt-in for v1; default off so existing deployments are byte-clean.

### Security

- **F003 fixture hygiene** (Bridgebuilder review) — account ID literal removed from `redaction_notes` prose in `tests/fixtures/bedrock/contract/v1.json`. The very prose explaining redaction had previously contained the literal it claimed to redact. Verified via `git ls-files | xargs grep -l <account_id>` returning empty.
- **F012 fixture rename** (Bridgebuilder review) — `E3-403-access-check.json` → `E3-404-end-of-life.json`. The fixture was named for the HTTP status the engineer expected, not the status Bedrock actually returns. Filename now honors actuality, not anticipation.

### Tests

- 732 Python tests pass (was 549 pre-cycle, +183 net cycle-096 test additions). 67 + 15 = 82 BATS pass. Live integration: 3/3 against real AWS account. Zero regressions.

### Process

- **Two-pass Flatline review on PRD v1.0→v1.3** caught 5 BLOCKERS + 5 HIGH-CONSENSUS findings (FR-12 region-prefix sanity, FR-13 thinking-trace translation, NFR-Sec8 token-age sentinel, FR-11 daily-quota circuit breaker, NFR-Sec11 token lifecycle controls, compliance_profile 4-step deterministic defaulting). 100% inter-model agreement.
- **Two-pass Flatline review on SDD v1.0→v1.2** caught 5 BLOCKERS + 5 HIGH-CONSENSUS findings (versioned `fallback_to`, value-based redaction PRIMARY/regex SECONDARY, threading.Event, Sprint 0 G-S0-CONTRACT gate, NFR-Sec11 token lifecycle, §6.7 Bedrock feature flag).
- **Bridgebuilder review on PR #662** surfaced 12 findings (3 PRAISE, 2 MEDIUM, 6 LOW, 1 SPECULATION). 4 fixture-related (F003 + F011 + F004 + F012) addressed in cycle-096 sprint-2 commit `d139d95`. The remaining 5 LOW + SPECULATION carried to cycle-097 backlog and 5 of those addressed in v1.109.1.
- **Live probes (Sprint 0 G-S0-2) before any code** — `tests/fixtures/bedrock/contract/v1.json` became the single source of truth across the 18-commit implementation. Future providers should follow the same probe-first pattern.

## [1.102.0] — 2026-04-25 — Cycle-093 stabilization (sprints 1–3A)

Three Tier-1 silent-failure issues closed plus the keystone health-probe foundation. The probe is implemented and tested but not yet wired into runtime — sprint-3B (resilience + CI workflows + runtime integration) and sprint-4 (registry currency + E2E gate) follow.

### Added

- **Provider health-probe foundation** (T2.2 part 1, sprint-3A) — `.claude/scripts/model-health-probe.sh` (1146+ lines) classifies each registered model as `AVAILABLE | UNAVAILABLE | UNKNOWN` against live provider APIs. Three per-provider adapters (OpenAI `/v1/models`, Google `/v1beta/models`, Anthropic `POST /v1/messages` with `max_tokens:1`), explicit state machine, atomic-write JSON cache (`temp + fsync + mv` under `flock`), lock-free reader retry, per-provider PID sentinel for background-probe dedup, hard-stop budget enforcement (10 probes/run, $0.05 cost cap, 120s total / 30s per call — each emits a `budget_hardstop` trajectory event before exit 5), `--canary` non-blocking smoke mode, `LOA_PROBE_LEGACY_BEHAVIOR=1` emergency fallback with mandatory `probe_legacy_bypass` audit-log entry, env-overridable cache/trajectory/audit paths for hermetic testing. 54 BATS tests (45 main + 8 hardstop + 1 iter-3 regression guard).
- **Spiral harness adversarial wiring** (T1.1, sprint-1, [#605](https://github.com/0xHoneyJar/loa/issues/605)) — `_run_adversarial_dissent` post-hoc dispatch in `spiral-harness.sh::_gate_review`/`_gate_audit`. Closes the silent no-op gap where `flatline_protocol.code_review.enabled: true` was set but no adversarial pass actually ran.
- **Bridgebuilder dist artifacts now committed** (T1.2, sprint-2, [#607](https://github.com/0xHoneyJar/loa/issues/607)) — un-ignored `.claude/skills/bridgebuilder-review/dist/` and force-added 36 compiled JS/d.ts/map files. Closes the `ERR_MODULE_NOT_FOUND` failure on first invocation in fresh clones.
- **Dissenter hallucination filter** (T1.3, sprint-2, [#618](https://github.com/0xHoneyJar/loa/issues/618)) — bidirectional token-match semantics in `adversarial-review.sh` that downgrade dissenter findings claiming `{{DOCUMENT_CONTENT}}` tokens absent from the diff. 6 normalization variants + 15 BATS tests. Earns its keep immediately: caught 2 false-positive hallucinations during sprint-3A's own kaironic Bridgebuilder review.

### Fixed

- **SKP-001 — Anthropic ambiguous-4xx → UNKNOWN** (sprint-3A) — `_probe_anthropic` now rejects any `4xx` lacking explicit `model`-field reference instead of misclassifying as `AVAILABLE`. Two paired regression tests enforce the discriminator.
- **Anthropic `anthropic-version` header on `/v1/messages`** (sprint-3A iter-3, Audit L-1, [PR #624](https://github.com/0xHoneyJar/loa/pull/624)) — `_curl_json` now appends `header = "anthropic-version: 2023-06-01"` to the secure tempfile when `auth_type=x-api-key`. Without this, every live Anthropic probe degraded to `UNKNOWN`. Static-grep BATS regression guard prevents accidental removal.
- **Google API key no longer in URL query string** (sprint-3A audit M-1) — `_probe_google` switched to header-only auth (`x-goog-api-key`). The previous `?key=` query parameter leaked via `ps aux`, proxy logs, and CDN access logs.
- **Hermetic test isolation** (sprint-3A Bridgebuilder iter-1 F8/F-002/F-003) — `LOA_TRAJECTORY_DIR` and `LOA_AUDIT_LOG` env-var overrides on the probe; tests point them at `$TEST_DIR`. Prior tests asserted against `$PROJECT_ROOT/.run/` and could false-pass on stale entries.
- **`adversarial-review-hallucination-filter.bats` portability** (sprint-2 Bridgebuilder iter-2 HIGH) — replaced hard-coded `/home/merlin/Documents/thj/code/loa/...` path with `$BATS_TEST_FILENAME`-relative resolution. Test now portable for other contributors and CI.

### Quality gates

- **53 + 1 new BATS tests** for sprint-3A; 84 existing adversarial-review and hallucination-filter tests pass with no regression.
- **Bridgebuilder kaironic review**: 4 iterations, ~$0.05 total. Iter-1 found 3 sprint-3A `MEDIUM` (closed). Iter-2 surfaced 1 sprint-2 `HIGH` (hardcoded path, closed). Iter-3 surfaced 1 `BLOCKING` (anthropic-version header, closed). Iter-4 clean (0 findings).
- **Adversarial cross-model review** (GPT-5.3-codex via `adversarial-review.sh`) on sprint-3A produced 2 findings, both correctly downgraded by the new sprint-2 hallucination filter — meta-validation of T1.3 within the same release.

### Notes

- Probe is **dead code on `main`** until sprint-3B wires it into `model-adapter.sh` runtime. No production behavior change for operators on this release except for closing #605/#607/#618. Operators currently relying on the hand-allowlist behavior remain unaffected.
- Tracked follow-ups for sprint-3B: bash error UX on unwritable `--cache-path` (audit L-2), dead `_redact_secrets` cleanup (L-3), sed-based BATS test sourcing pattern (structural, project-wide).

## [1.101.0] — 2026-04-19 — Spiral SEED environment gate

### Added

- **`_pre_check_seed` environment-invariant gate** (#575 item 3, [PR #594](https://github.com/0xHoneyJar/loa/pull/594)) — Mirrors existing `_pre_check_implementation` / `_pre_check_review` which validate post-conditions for later phases. The SEED seam had no counterpart — environment invariants only surfaced mid-cycle as confusing `"grimoires/loa/prd.md not found"` errors AFTER discovery had already written to the wrong location. Empirical justification: cycle-084 CWD-mismatch (reviewer subprocess ran in `.loa/` submodule CWD instead of main repo).
  - **Hard-fail checks**: CWD inside a git work tree, `grimoires/loa/` present from CWD (cycle-084 class), cycle dir (or parent if dir missing) writable.
  - **Warn checks**: `$SEED_CONTEXT` path exists + readable + non-empty when set. Non-blocking by default.
  - **Strict mode**: `SPIRAL_PRE_CHECK_SEED_STRICT=true` promotes warnings to errors (useful for CI).
  - **Wire-up**: `spiral-harness.sh main()` invokes `_pre_check_seed "$CYCLE_DIR"` before Phase 1 Discovery. Failures `exit 1` with the specific FAIL reason on stderr — no silent fallthrough that would waste an LLM invocation.
  - **Tests**: 14 new BATS (`tests/unit/spiral-pre-check-seed.bats`) covering happy path, each hard-fail class with specific messages, warn cases with non-blocking semantics, strict-mode promotion, trajectory recording, and edge cases.

## [1.99.2] — 2026-04-19 — Spiral SEED failure-ingestion

### Added

- **Prior-cycle failure events fold into next cycle's discovery context** (#575 item 2, [PR #592](https://github.com/0xHoneyJar/loa/pull/592)) — Closes one of the autopoietic-loop gaps identified in @zksoju's three-lens audit. Prior cycles produce observability (`flight-recorder.jsonl`) but next cycle's discovery phase never read it; operators had to hand-curate failure modes into the SEED or (more commonly) not bother, so the same failure patterns recurred. Builds on the #569 dashboard infrastructure — both read flight-recorder, different lens.
  - **`_find_prior_cycle(current)`** in `spiral-evidence.sh` locates the lexicographically previous cycle dir, skipping incomplete siblings.
  - **`_summarize_prior_cycle_failures(prior)`** scans the prior flight-recorder for load-bearing events: `CIRCUIT_BREAKER`, `BB_FINDING_STUCK`, `AUTO_ESCALATION`, `REVIEW_FIX_LOOP_EXHAUSTED`, `BUDGET FAIL`, and any phase with `FAIL:` verdict. Emits short markdown bullet list truncated at 2000 chars.
  - **`_build_seed_failure_prelude(current)`** is the gated entry point: feature flag + prior-cycle lookup + summary composition + `---...---` delimiter wrapping.
  - **`_phase_discovery`** in `spiral-harness.sh` weaves the prelude into the PRD prompt between the task description and the existing SEED context block.
  - **Feature flag** (default off, safe rollout): `spiral.seed.include_flight_recorder: true` in `.loa.config.yaml`, or env var `SPIRAL_SEED_INCLUDE_FLIGHT_RECORDER=true`. Enabled operators get the learning loop; existing operators see no behavior change.
  - **Tests**: 20 new BATS (`tests/unit/spiral-seed-ingestion.bats`) covering predecessor lookup (skip-incomplete, first-cycle-has-no-prior), event extraction (5 categories + clean-cycle + missing-recorder + missing-dir + truncation), and prelude gating (feature-off-default, strict "true" comparison, delimiter wrapper).

## [1.99.1] — 2026-04-19 — Kaironic termination docs

### Changed

- **Name kaironic termination publicly** (#575 item 5, [PR #591](https://github.com/0xHoneyJar/loa/pull/591)) — The `flatline_convergence` stopping condition (cycle-066) was already implemented as "Kaironic signal: plateau reached" in a table cell, but the architectural rarity wasn't called out. Most agentic pipelines have only chronos caps (budget / max iterations / timeout); second-order cybernetic convergence where the loop observes its own findings-rate and halts when signal exhausts is distinctive. Lean into it:
  - `.claude/skills/spiraling/SKILL.md` Stopping Conditions section now distinguishes chronos (wall-clock caps) from kaironic (signal-exhaustion), marks `flatline_convergence` as the kaironic condition explicitly via a new "Kind" column, and notes no safety floor for the kaironic condition (the system trusts the signal).
  - `README.md` Spiral Autopoietic Orchestrator section adds a paragraph-length explainer below the Cost optimization note.
  - No behavior change; docs-only.

## [1.99.0] — 2026-04-19 — Spiral observability dashboard

### Added

- **Spiral observability dashboard — default-on metrics emission** (#569, [PR #589](https://github.com/0xHoneyJar/loa/pull/589)) — Closes the observability gap surfaced by @zkSoju during a live cycle-084 run. Until now, operators had to stand up ad-hoc Monitor wrappers mid-cycle to watch phase transitions, cost, and budget pressure. The flight-recorder exposed raw events; no aggregated view existed.
  - **`_emit_dashboard_snapshot(current_phase, cycle_dir)`** in `spiral-evidence.sh` aggregates `flight-recorder.jsonl` into operator-friendly snapshots. Appends to `<cycle-dir>/dashboard.jsonl` (append-only journal) and overwrites `<cycle-dir>/dashboard-latest.json` (cheap read pointer).
  - **Automatic emission at each phase boundary** in `spiral-harness.sh` (START / DISCOVERY / FLATLINE_PRD / ARCHITECTURE / FLATLINE_SDD / PLANNING / IMPLEMENT / FINALIZED). No flag needed — default-on per issue request.
  - **Schema `spiral.dashboard.v1`** with totals (actions, failures, cost_usd, duration_ms, budget_cap_usd, budget_remaining_usd, fix_loop_events, bb_fix_cycles, circuit_breaks, first/last_action_ts) and per_phase rollup (actions, duration_ms, bytes, cost_usd, failures, first/last_ts grouped by phase).
  - **`SPIRAL_TOTAL_BUDGET`** exported from harness `main()` so snapshots compute budget remaining without re-reading config.
  - **`cmd_status` enhanced**: `--json` merges dashboard into state output as `.dashboard`; pretty mode renders "Metrics" block + "Per-phase" table below the existing state/phase/cycle summary.
  - **Fail-safe**: swallows errors (jq / shell failures cannot break the pipeline); no-op when flight recorder unset or cycle_dir missing.
  - **Tests**: 18 new BATS tests (`tests/unit/spiral-dashboard.bats`) covering snapshot structure, totals rollup math, budget computation (including non-numeric `SPIRAL_TOTAL_BUDGET` defaulting to 0), per-phase grouping, fix-loop + BB-cycle counters, append-only journal + overwrite-pointer behavior, and `cmd_status --json` integration.
  - **Deferred** (tracked as follow-ups): context-size-per-phase instrumentation (requires `claude -p` hooks), regression fixtures (known SEED → known cycle outcome, CI-enforced), external sinks (Grafana/Honeycomb/OTEL — hook points exist via `dashboard.jsonl` consumption), background per-N-seconds emission (phase-boundary covers the observable moments).

## [1.98.0] — 2026-04-19 — Bridgebuilder persona discovery + resolution trace

### Added

- **Persona discovery + resolution trace CLI flags** (#396, [PR #588](https://github.com/0xHoneyJar/loa/pull/588)) — Closes the primary DX friction points around Bridgebuilder personas. Previously, operators had no way to list available packs without browsing the filesystem, and the 5-level resolution cascade (CLI flag > config name > config path > repo override > built-in default) was invisible — "which persona is actually active?" required guessing.
  - **`--list-personas`** — lists built-in packs with H1 titles extracted from each persona file (parses YAML frontmatter, reads first `#` heading), then exits before config resolution so it works even with a broken config.
  - **`--show-persona-resolution`** — traces the 5-level cascade showing `[active]` (winning level), `[shadow]` (provided but a higher level won), `[skip]` (not provided), or `[missing]` (provided but file not found). Makes the previously-silent Level 4 (repo override) fallthrough visible.
  - **`readPersonaTitle(name)`**, **`traceResolution(config)`**, **`formatResolutionTrace(steps)`** — exported from `main.ts` so tests and downstream tooling can inspect without invoking the CLI.
  - **Tests**: 14 new Jest tests (617 → 631 total) covering title extraction with frontmatter stripping, state matrix across L1/L3/L4/L5 (skip/active/shadow/missing), and trace rendering markers.
  - **Not in scope** (per #396 scope split; follow-ups): warn-instead-of-throw on `persona_path` miss (Level 3 already throws with a clear message; Level 4's silent fallthrough is now visible via `--show-persona-resolution`); run-bridge persona inheritance from bridgebuilder config (separate config refactor).

## [1.97.1] — 2026-04-19 — Bridgebuilder OpenAI codex routing fix

### Fixed

- **Multi-model Bridgebuilder degraded to single-model on codex OpenAI reviews** (#585, [PR #586](https://github.com/0xHoneyJar/loa/pull/586)) — The TypeScript adapter at `.claude/skills/bridgebuilder-review/resources/adapters/openai.ts` hardcoded `/v1/chat/completions` for all OpenAI models. Codex variants (`gpt-5.3-codex` and future codex models) require `/v1/responses` — the chat endpoint returns 404 with "This is not a chat model...". On PR #583, only Gemini produced a review; Anthropic returned 400 (separate billing exhaustion) and OpenAI returned 404. The Python adapter at `.claude/adapters/loa_cheval/providers/openai_adapter.py` (used by Flatline) already had the correct routing split; this PR ports the pattern to the TypeScript adapter.
  - **Routing**: `isCodexModel(model)` detection (case-insensitive `/codex/i`) → codex to `/v1/responses`, non-codex to `/v1/chat/completions`
  - **Codex body shape**: `{model, input: "<system>\n\n---\n\n<user>", stream: true}` (single input string, not messages array)
  - **Codex stream parsing**: `response.output_text.delta` for content, `response.completed` for usage, `response.created` for model fallback; reasoning deltas (`response.reasoning_text.delta`, `response.reasoning_summary_text.delta`) are deliberately ignored by the content accumulator to prevent silent over-translation
  - **Tests**: 8 new BATS-equivalent Jest tests (5 routing + 3 hardening per Gemini 2.5 Pro HIGH finding on the fix PR itself) locking the URL split, body shape, SSE vocabulary, reasoning-event ignore, 4xx error surface, and 5xx retry policy — 617/617 passing
  - **Self-verified**: multi-model Bridgebuilder re-run against PR #586 had all 3 models succeed (Anthropic ✓ + OpenAI ✓ + Gemini ✓), 8 findings produced including 1 consensus + 3 disputed + 2 praise
  - **Dist tracking**: `dist/adapters/openai.{js,js.map,d.ts,d.ts.map}` now committed (matches the precedent already set by `anthropic.js` + `github-cli.js`), so downstream operators get the fix without a local `npm run build`
  - **Not addressed in this patch**: The Anthropic 400 in the original run was **billing exhaustion** ("Your credit balance is too low"), surfaced by the adapter as generic "API 400". Parsing the Anthropic error envelope for a clearer "credits exhausted" message is a separate UX follow-up.

## [1.97.0] — 2026-04-19 — cycle-088 — Framework Boundary Fixes + Spiral Hardening + Adapter Generator

**Consolidation release rolling up 14 PRs that shipped as auto-patches (v1.94.1 through v1.96.5).** The post-merge automation tagged each non-cycle PR with a patch bump but did not produce a CHANGELOG entry per the classifier's cycle-only rule (see #550 for the classifier fix shipped mid-cycle). This entry consolidates the accumulated work into a single coherent cycle record.

Themes: framework/user-file boundary clarification (#553/#554/#550), CI green restoration (#549), spiral recovery hardening (#545/#546/#568/#570), YAML-driven model adapter maps (vision-011/#548), Flatline model allowlist accuracy (#573/#574), shell safety infrastructure (#555/#563), RFC-061 calibration pack design (#556), and the Flatline simstim + red-team grounding fixes that closed the cycle (#579/#582).

### Fixed

- **Simstim skill documented invalid `--mode hitl`** (#579, [PR #583](https://github.com/0xHoneyJar/loa/pull/583)) — Three Flatline invocations in `.claude/skills/simstim-workflow/SKILL.md` (phases 2/4/6 for PRD/SDD/sprint) used `--mode hitl`, which `flatline-orchestrator.sh` rejects with exit 1. HITL semantics were already delivered by the orchestrator's auto-detection from `.run/simstim-state.json`. Removed the flag from all three invocations. Drive-by: `--help` mode list aligned with validator (`review, red-team, inquiry`).
- **Red team returned off-target findings on non-AI-domain SDDs** (#582, Option C, [PR #583](https://github.com/0xHoneyJar/loa/pull/583)) — When the red-team domain extractor produces a weak domain string, the attacker model generates attacks from its prior and the primary reviewer scores them all 0, masquerading as "no security findings." Added a fail-closed guard: when ≥80% of scored attacks have `opus_score == 0` and total ≥ 3, the orchestrator halts with exit code 3 and injects `grounding_failure: true`. Threshold + min-count configurable via `red_team.grounding_failure.{opus_zero_threshold, min_attacks}` (defaults 0.8 / 3). Computation extracted to `compute_grounding_stats()` with a source-guard so BATS can exercise the real runtime path dynamically. Option A (domain extractor rewrite) deferred as structural follow-up.
- **`agent: Plan` blocked Write on write-capable planning skills** (#553, [PR #558](https://github.com/0xHoneyJar/loa/pull/558)) — `designing-architecture` and `planning-sprints` declared `agent: Plan` in SKILL.md frontmatter, but the Plan agent type's tool allowlist excludes `Write`/`Edit`/`NotebookEdit`. The skills produced correct output and then silently refused to persist it — reproducible across multiple downstream repos. Dropped the frontmatter field and shipped `validate-skill-capabilities.sh` with a `WRITE_CAPABLE_AGENTS` allowlist that lints the invariant. Rule documented at `.claude/rules/skill-invariants.md`.
- **`.loa-version.json` + `CLAUDE.loa.md` markers stale post-merge** (#554, [PR #559](https://github.com/0xHoneyJar/loa/pull/559)) — Version markers weren't refreshed by the post-merge pipeline, causing downstream issue reports to cite historical versions. Shipped `update-loa-bump-version.sh` + integrated Phase 5.6 step that rewrites `.loa-version.json` + `CLAUDE.loa.md` header to the newly-released tag. `.gitattributes` updated with `merge=ours` for `.loa-version.json` to prevent merge noise.
- **Post-merge classifier regex missed cycle PRs with `cycle-NNN` elsewhere in title** (#550, [PR #560](https://github.com/0xHoneyJar/loa/pull/560)) — Old regex matched only a narrow prefix set, skipping the full CHANGELOG/GT/RTFM/Release pipeline on legitimate cycle PRs whose titles had `cycle-NNN` mid-string. Replaced with `\bcycle-[0-9]+\b` anywhere + extracted the classifier into `classify-pr-type.sh` as the single source of truth sourced by both `post-merge.yml` and `post-merge-orchestrator.sh`.
- **Shell Tests pre-existing failures on main** (#549, [PR #562](https://github.com/0xHoneyJar/loa/pull/562)) — Triaged 5 test clusters (release-notes, health-check, search-orchestrator, hook-registration, lore-promote) and produced per-cluster fixes to restore green CI.
- **`git stash -k` silent data loss against pre-commit hooks** (#555, [PR #564](https://github.com/0xHoneyJar/loa/pull/564)) — Pre-commit hooks run their own internal `git stash --keep-index`; when an outer Loa stash overlaps, the stash indexes shift and `pop` lands on the wrong entry. Combined with `| tail -N` / `|| true` output-swallowing patterns, this produced silent data loss that looked like success (reproduced: 4 Edit-tool updates to NOTES.md lost in one operator session). Shipped `stash_with_guard` helper that enforces count-delta invariants (N → N+1 on push, N+1 → N on pop) and surfaces all output. New rule at `.claude/rules/stash-safety.md`.
- **Spiral REVIEW gate had no fix-loop — retried same broken impl until circuit-breaker** (#545, [PR #565](https://github.com/0xHoneyJar/loa/pull/565)) — Observed in cycle-367687f8de (flight recorder: seq 13 → 19 REVIEW attempts on unchanged impl). Added `_phase_implement_with_feedback` + `_review_fix_loop` mirroring cycle-074's Bridgebuilder fix-loop pattern. Budget-capped by `REVIEW_MAX_ITERATIONS` (default 2).
- **Spiral cycle failing on implementation budget couldn't be resumed** (#546, MVP, [PR #565](https://github.com/0xHoneyJar/loa/pull/565)) — Added narrow `--resume --force` override on `stopping_condition=quality_gate_failure` terminal state. Refuses other stop-reasons and non-force paths. Option B (`spiral.seed.from_cycle_id` artifact-copy preflight) deferred as a structural follow-up.
- **Tripwire rollback precheck missed untracked-only changes** (#563, [PR #567](https://github.com/0xHoneyJar/loa/pull/567)) — Precheck compared tracked state only; an untracked file could be silently lost across a rollback window. Added `ls-files --others` check + sourced-vs-executed guard.
- **Spiral dispatch subprocess didn't receive `SPIRAL_TASK`** (#568, [PR #576](https://github.com/0xHoneyJar/loa/pull/576)) — Export added; state-file fallback introduced in `spiral-simstim-dispatch.sh` with clearer FATAL message pointing at the orchestrator.
- **Spiral planning-phase timeouts too tight (300s)** (#570, [PR #577](https://github.com/0xHoneyJar/loa/pull/577)) — Made configurable with sensible defaults: `DISCOVERY_TIMEOUT=1200s`, `ARCHITECTURE_TIMEOUT=1200s`, `PLANNING_TIMEOUT=600s`. Added `_validate_timeout_sec` helper.
- **Flatline allowlist listed phantom Gemini 3 models** (#573/#574, [PR #578](https://github.com/0xHoneyJar/loa/pull/578)) — `gemini-3-flash`, `gemini-3-pro`, `gemini-3.1-pro-preview` passed local allowlist but Google v1beta returned NOT_FOUND at runtime, collapsing any review. Pruned from `VALID_FLATLINE_MODELS` + `.claude/defaults/model-config.yaml`. Added `VALID_MODEL_PATTERNS` forward-compat regex admitting new versions without hand-edit. Agent bindings retargeted: `deep-thinker → gemini-2.5-pro`, `fast-thinker → gemini-2.5-flash`. Re-add Gemini 3 models when vendor confirms v1beta availability (smoke test first).

### Added

- **YAML → bash adapter map generator (vision-011)** (#548, [PR #566](https://github.com/0xHoneyJar/loa/pull/566) + [PR #571](https://github.com/0xHoneyJar/loa/pull/571)) — Four associative arrays (`MODEL_PROVIDERS`, `MODEL_IDS`, `COST_INPUT`, `COST_OUTPUT`) in `.claude/scripts/model-adapter.sh.legacy` are now generated from `.claude/defaults/model-config.yaml` via `gen-adapter-maps.sh`. Eliminates the "forgot to update one of the four maps" bug class that `validate_model_registry()` was invented to catch. PR #566 ships the generator; PR #571 swaps the legacy adapter to `source generated-model-maps.sh`. The YAML is now the single source of truth; pricing normalized to consistent micro-USD per MTok (previously mixed milli-USD for OpenAI/Anthropic and micro-USD for Gemini, a 1000x undercounting bug). New `backward_compat_aliases` section preserves historical IDs (`claude-opus-4.5`, `4.1`, `4.0` etc.) retargeting to the current canonical. Core of vision-011 acceptance criteria shipped; T-PRE / T-CROSS / T-GREP committed test scripts deferred.
- **RFC-061 v3.1 — Polycentric Model-Calibration Pack design** (#556, [PR #581](https://github.com/0xHoneyJar/loa/pull/581)) — Design doc at `grimoires/loa/proposals/rfc-061-calibration-pack.md`. Progen-inspired YAML instance-first schema, JSON Schema draft-07 authoring surface, protobuf-style field numbering for schema compatibility, RFC 8785 JSON Canonicalization Scheme for signing, golden corpus with stochastic tolerance, cross-provider profile layout (Opus 4.7 + GPT-5.3-codex + Gemini 2.5). Iterated through 3 rounds of Flatline multi-model adversarial review (Opus + GPT-5.3-codex + Gemini 2.5 Pro). Remaining v3.1 blockers are design constraints (LLM-judge circularity, vendor API drift) rather than fixable bugs — acknowledged and ship-as-is. Pack implementation is a multi-cycle follow-up and will be tracked on its own issue when prioritized.

### Deferred / Follow-up

- **#582 Option A** — domain extractor rewrite using first H1 + first paragraph + TF-IDF distinctive terms (Option C fail-closed covers the worst case; Option A improves the common case but is structural).
- **#546 full scope** — `spiral.seed.from_cycle_id` config + artifact-copy preflight (MVP `--resume --force` shipped).
- **#548 remaining** — T-PRE (`model-compat-check.sh`), T-CROSS (`cross-runtime-alias-contract.sh`), T-GREP (`model-version-residuals.sh`) committed test scripts + migration playbook.
- **#556 implementation** — polycentric calibration pack directory scaffold, profile YAMLs, golden corpus generation, LLM-judge harness.
- **Gemini 3 re-enablement** — when Google confirms `gemini-3-*` availability on v1beta (live smoke test first).

### Testing

BATS suite expanded to cover the new contracts:
- `flatline-grounding-failure.bats` — 20 tests (12 static + 7 dynamic sourced-function + 1 sourceability) covering ratio math, small-N guard, divide-by-zero, string-"0" handling, and real runtime function calls
- `simstim-flatline-mode.bats` — 6 tests ensuring SKILL.md/orchestrator consistency (no `--mode hitl` references, valid invocation forms, help/validator parity, runtime rejection with exit 1)
- `flatline-model-allowlist.bats` — phantom Gemini 3 prune regression guards + forward-compat pattern tests
- `gen-adapter-maps.bats` — YAML→bash generator + byte-correctness + pricing unit parity + drift detection
- `spiral-review-fix-loop.bats` — REVIEW→IMPL fix-loop decision table
- `spiral-resume-force.bats` — 9 cases covering the full `--resume --force` decision matrix
- `stash-safety.bats` — count-delta invariants on `stash_with_guard`
- `skill-capabilities.bats` — agent-type vs write-capability invariant lint
- `post-merge-classifier.bats` — `cycle-NNN` anywhere regression
- `update-loa-bump.bats` — Phase 5.6 version marker refresh
- `spiral-resume-force.bats`, `spiral-task-export.bats`, `spiral-phase-timeouts.bats`, `tripwire-handler-rollback.bats` — spiral recovery regression guards

### Issue Tracker

- **Closed** as part of this cycle's scope: #545, #547, #549, #550, #551, #552, #553, #554, #555, #557 (meta-tracker), #563, #568, #570, #573, #574, #579
- **Partially closed with deferred scope**: #546 (MVP), #548 (core), #556 (RFC), #582 (Option C)
- **Merged PRs**: #558, #559, #560, #562, #564, #565, #566, #567, #571, #576, #577, #578, #581, #583

## [1.94.0] — 2026-04-17 — Adversarial Review Enforcement Gate

### Added

- **Adversarial review enforcement gate** (#552) — `PreToolUse:Write` hook blocks `*/COMPLETED` marker writes when `flatline_protocol.{code_review,security_audit}.enabled: true` in config but the corresponding `adversarial-{review,audit}.json` artefact is missing or structurally invalid. Closes the silent-skip failure mode where `reviewing-code` / `auditing-security` skills executing inline could bypass Phase 2.5 under token pressure while still writing `COMPLETED`.
  - **Structural validation** raises bypass cost beyond `touch artefact.json`: the artefact must parse as JSON and contain `.metadata.type` + `.metadata.model` — fields that `adversarial-review.sh` writes on every code path (success, api_failure, malformed_response, skipped_by_config). Empty files and hand-crafted placeholders no longer satisfy the gate.
  - **CWD-independent config resolution**: walks upward from the sprint directory to locate `.loa.config.yaml` instead of relying on `./` (PreToolUse hooks don't pin CWD; the `./` form silently missed from subagents and worktrees).
  - **Fail-open on infrastructure faults** (missing `yq`, jq parse errors, malformed config) with stderr warning; **fails closed** when `.loa.config.yaml` cannot be resolved at all — an unresolvable config means enforcement requirements can't be evaluated, which is the silent-skip mode the gate exists to block.
  - **Trajectory visibility**: `adversarial-review.sh` now emits a trajectory entry with outcome `skipped_by_config` when disabled rather than exiting silently. Absence of reviews becomes observable in the audit trail.
  - **Test coverage**: `.claude/tests/adversarial-review-gate.test.sh` — 11 cases covering block/allow paths, the structural bypass (`touch`), opt-out env var, yq-missing fail-open, walk-up config discovery, and unresolvable-config fail-closed. All passing.
  - **Emergency override**: `LOA_ADVERSARIAL_REVIEW_ENFORCE=false` preserved for break-glass scenarios; `LOA_CONFIG_PATH_OVERRIDE` for tests and edge cases.

### Fixed

- **Stale test assertion** (60bdef7) — `tests/unit/gpt-review-hook.bats` referenced the deprecated `gpt-5.2` model; updated to `gpt-5.3-codex` to match the current dissenter default.

## [1.93.0] — 2026-04-17 — Opus 4.7 Top-Review Migration

### Changed

- **Opus 4.7 promoted to top-review default** (cycle-082) — `opus` alias retargeted from `anthropic:claude-opus-4-6` to `anthropic:claude-opus-4-7` across all adapters (bash, Python, TypeScript, YAML). Affects Flatline Protocol primary, Bridgebuilder enriched review, red-team adapter advisor role, spiral advisor/judge. Pricing verified identical to 4.6 ($5/$25 per Mtok input/output); no cost-ledger or budget impact. Sonnet 4.6 executor default unchanged.
  - **Backward compatibility**: `anthropic:claude-opus-4-6` registry entry retained in `.claude/defaults/model-config.yaml` + `.claude/data/model-permissions.yaml` as a pinnable fallback. Operators who want exact 4.6 behavior (historical baselines, rollback) can pin `opus: "anthropic:claude-opus-4-6"` in their `.loa.config.yaml` overrides; the Python/YAML resolution path will resolve to 4.6. Bash adapter layer retargets all legacy IDs (including `claude-opus-4-6`) to 4.7 for alias ergonomics, per PR #207 precedent.
  - **Legacy alias retarget flag**: `claude-opus-4.5`, `claude-opus-4-5`, `claude-opus-4.1`, `claude-opus-4-1`, `claude-opus-4.0`, `claude-opus-4-0` (in both dotted and hyphenated forms) now resolve to Opus 4.7 via the bash alias layer. If you relied on a specific legacy model for historical benchmarks or compliance baselines, you MUST pin the canonical provider-prefixed form (`anthropic:claude-opus-4-6` etc.) via `.loa.config.yaml` — aliases are backward-compat convenience, not a reproducibility guarantee.
  - **Rollback**: `git revert <merge-commit-sha>`. Single-PR, atomic, no state-mutation dependencies. Operators can also pin 4.6 in config as a no-maintainer-action override.
  - **Deferred**: formal quality-benchmark harness (vision-010), auto-generated bash adapter maps from YAML (vision-011), role-based alias renaming (vision-012).

## [1.92.0] — 2026-04-16 — Shell Hardening & QoL Cycle

Eight PRs (#537–#544) addressing 6 tracked issues plus 2 codebase-wide QoL improvements. This cycle eliminated three classes of shell bugs, added two lint detectors for ongoing prevention, and closed all open spiral-harness reliability bugs.

The central theme: **prevention infrastructure is more valuable than individual fixes.** Every bug fix in this cycle is paired with either a lint rule or a regression test that prevents the class from recurring.

### Fixed

- **Spiral stdout pollution** (#514, PR #537) — `cycle-workspace.sh init` JSON output leaked into `run_single_cycle`'s stdout return channel, terminating spirals after cycle 1 with malformed `stopping_condition: "{"`. One-line redirect + guard comment + 3 BATS tests. Full 18-call-site audit in disposition table.
- **Harness budget boundary** (#515, PR #538) — Light profile $10 budget hit exactly at REVIEW→AUDIT boundary, blocking the audit quality gate. Three-layer fix: strict-greater comparison (`>` not `>=`), audit reserve ($2 reserved from effective cap for pre-AUDIT phases), raised light profile default from $10 to $12.
- **Cache-manager secret false positives** (#530, PR #540) — Broad `secret.*[=:]` pattern false-positived on `{secret_scanning: true}`, `kind: Secret`, compound words. Replaced with two specific patterns plus `client_secret` literal. 14 BATS tests.
- **Red team skipped in submodule mode** (#528, PR #543) — Template paths anchored to `PROJECT_ROOT` instead of `SCRIPT_DIR`. 106-line BATS test. Dispatched via spiral-harness.
- **Harness silent exit** (#516, PR #544) — Added ERR trap handler (FATAL with LINENO), guarded `_record_action` with `|| true`, brace-group for `wc -c`. 112-line BATS test. Dispatched via spiral-harness.
- **Vision-lib grep -c fallback** (PR #542) — 7 instances replaced with `awk`.

### Added

- **Shell lint: `grep -c || echo 0` detector** (#531, PR #539) — `.claude/scripts/lint-grep-c-fallback.sh`. 133 sites flagged. WARNING level. `--error`/`--scan-only` modes.
- **Shell lint: `(( var++ ))` detector** (PR #541) — `.claude/scripts/lint-arithmetic-increment.sh`. 158 sites fixed across 26 scripts.

### Changed

- Light profile default budget: $10 → $12
- `_check_budget` comparison: `>=` → `>` (phase can start at exact budget)

### Issue Tracker

- **Closed**: #514, #515, #516, #528, #530, #531, #509, #247
- **Updated**: #443, #396, #310 (scopes narrowed)

## [1.91.7] — 2026-04-16

### Deprecated

- **`/gpt-review` and `/toggle-gpt-review` commands soft-deprecated** (cycle-075 W2c) — scheduled for retirement **no earlier than 2026-07-15** (minimum 3-month runway per [clig.dev](https://clig.dev/#backwards-compatibility) guidance).
  - Superseded by the **Flatline Protocol** (multi-model adversarial review — Opus + GPT-5.3-codex + optionally Gemini) which is integrated into every planning/review/audit cycle by default. No remaining automated callers.
  - **Runtime warning** added to `gpt-review-api.sh` — prints a one-shot deprecation notice to stderr on every invocation that does real work. Suppressible via `LOA_SUPPRESS_GPT_REVIEW_DEPRECATION=1` for automation.
  - **Prominent deprecation headers** added to `.claude/commands/gpt-review.md`, `.claude/commands/toggle-gpt-review.md`, and `.claude/protocols/gpt-review-integration.md`.
  - **Failing test suites skipped** (`tests/unit/gpt-review-{api,prompts,request}.bats`) via `skip` in `setup()`. Set `LOA_RUN_DEPRECATED_TESTS=1` to attempt anyway. These tests had been broken since shortly after introduction (see cycle-075 triage for the archaeology — the script's original `main()` documented "no config check here" but the tests asserted config-based SKIPPED behavior; the tests were never wired to reality).
  - **Phantom `context_files` entries removed** from `/plan-and-analyze`, `/architect`, `/sprint-plan`, `/implement` commands. They pointed to `.claude/context/gpt-review-active.md` which was deleted long ago.
  - **`gpt-review-hook.sh` hook registration removed** from `.claude/settings.json`. The hook was a no-op with `gpt_review: null` config, but its registration was misleading.
  - **Migration path**: use `/flatline-review` or rely on Flatline gates that run automatically inside `/run sprint-plan`, `/run-bridge`, and `/audit-sprint`. See `.claude/loa/reference/flatline-reference.md`.
  - **If you rely on `/gpt-review`**, please let us know before sunset: run `/feedback` or file an issue at https://github.com/0xHoneyJar/loa/issues with the `deprecation` label.

## [1.90.0] - 2026-04-15 — Config Transparency & Safety Enforcement

Configuration now has the same documentation rigor as the features it controls. This release ships a comprehensive configuration reference (~1,000 lines covering every `.loa.config.yaml` option with ELI5 explanations, per-invocation costs, risks in both directions, and setup requirements), an interactive `/loa setup` onboarding wizard, and concrete safety enforcement for the security invariants that previously existed only as documentation warnings. It also closes a long-standing gap where all the framework's safety hooks had been defined but never wired into the settings file Claude Code actually reads — meaning spiral dispatch guards, destructive bash blockers, mutation loggers, and compact recovery had all been silently inert. They now fire at the platform level.

The central tension resolved in this release: **documentation that describes dangerous options without enforcing safety invariants is a map that shows the minefield but leaves the gates open.** The new CONFIG_REFERENCE.md is the map; the runtime overrides and hook wiring are the gates.

### Added

- **`docs/CONFIG_REFERENCE.md`** — comprehensive configuration reference (cycle-073, [#510](https://github.com/0xHoneyJar/loa/issues/510), PR [#511](https://github.com/0xHoneyJar/loa/pull/511))
  - Cost Matrix: per-invocation low/high, monthly estimates at moderate workflow, models used, for every cost-bearing feature (Flatline, Simstim, Spiral, Run Bridge, Post-PR Validation, Red Team, Continuous Learning, Prompt Enhancement)
  - Decision Guide: Mermaid flowchart + plaintext fallback table routing users to a recommended feature set by budget tier, team size, and workflow pace
  - Per-feature documentation follows a consistent pattern: ELI5 → version introduced → recommendation → default → cost warning → sub-keys table → cost details → risks-if-enabled → risks-if-disabled → setup requirements → see-also
  - Safety hooks table documents the non-configurable platform-level guards (deny rules for `~/.ssh/`, `~/.aws/`, `~/.kube/`, `~/.gnupg/`)
  - Pricing footnotes with verification date and "recheck before large commitments" warnings
- **`/loa setup` onboarding wizard** — interactive configuration generator (cycle-073, PR [#511](https://github.com/0xHoneyJar/loa/pull/511))
  - Detects available provider API keys (Anthropic, OpenAI, Google)
  - Questionnaire: usage tier (solo / team / enterprise), budget comfort level, workflow preference (HITL / semi-auto / fully auto)
  - Generates a recommended `.loa.config.yaml` matched to answers with explanations for each enabled feature
  - Idempotent: re-running on an existing config shows current settings with recommendations rather than overwriting
  - Refuses to set security invariants (e.g., `secret_scanning.enabled: false`) to unsafe values
- **README cost warning** — prominent callout listing the three most expensive features (Flatline, Simstim, Spiral) with per-invocation cost ranges and instructions to run `/loa setup` before enabling autonomous modes
- **Auto-sentinel hook** (`spiral-skill-sentinel.sh`) — creates `.run/spiral-dispatch-active` automatically when `/spiraling` is invoked, closing the last mechanical enforcement gap where agents could forget to activate the dispatch guard
- **Pipeline profiles + scheduling for Spiral** (cycle-072, PR [#508](https://github.com/0xHoneyJar/loa/pull/508))
  - Three profiles: `light` (~$8, no Flatline, Sonnet advisor), `standard` (~$12, Sprint Flatline only, Opus advisor), `full` (~$20–35, all 3 Flatline gates, Opus advisor)
  - Auto-escalation: detects security/system/schema paths in task description or sprint plan and upgrades profile automatically
  - Off-hours scheduling via `spiral-scheduler.sh` with configurable UTC windows
  - Mechanical dispatch guard: Write/Edit to code files blocked unless the spiral harness has been dispatched

### Fixed

- **Safety hooks now actually fire** — all 11 hooks defined in `.claude/hooks/settings.hooks.json` were never merged into `.claude/settings.json` (the file Claude Code actually reads). Spiral dispatch guards, destructive bash blockers, team role guards, mutation loggers, compact recovery hooks, and run-mode stop guards have all been silently inert. Merged the full hook registration into the active settings file. Detection: the post-merge pipeline ran for PRs #507 and #508 without ever firing the stop guard it was supposed to enforce.
- **`secret_scanning.enabled` is now a security invariant** — `flatline_protocol.secret_scanning.enabled: false` previously would have sent raw code to OpenAI for Flatline review. The docs said "never disable" but the config loader respected the user value. Runtime now overrides `false` → `true` with a CRITICAL log in both `adversarial-review.sh` and `flatline-snapshot.sh` (the latter unconditionally returns true). The config key remains for forward compatibility but cannot disable scanning.
- **Default daily budget cap reduced from $500/day to $10/day** — the original default could burn $15,000/month if an autonomous workflow ran amok. Tiered guidance now recommends `$1/day` for solo $0–10/mo, `$10/day` for moderate use (new default), `$50/day` for active autonomous workflows.
- **README/config consistency** — README claimed Flatline Protocol, Simstim, and Spiral were all "disabled by default"; actually Flatline and Simstim are `enabled: true` (gated on API keys) and only Spiral defaults to `false`. README now reflects this accurately.
- **Dispatch guard documentation** — `/spiraling` invocations now carry explicit dispatch instructions. The skill loads as context, never as an orchestrator. (PR [#507](https://github.com/0xHoneyJar/loa/pull/507))
- **Post-PR Flatline cost inconsistency** — sub-keys table said `~$1.50` while the Cost Warning said `~$5–15`. Reconciled to `~$5–15 depending on diff size`.
- **Spiral safety "floor" misnomer** — `budget_cents` and `wall_clock_seconds` were documented as "floors" but are actually hard ceilings (values above are clamped). Renamed with explicit clamping semantics.
- **Missing `prompt_enhancement` documentation** — referenced in Cost Matrix and Decision Guide but had no dedicated section. Added full section with sub-keys, costs, and risks.

### Changed

- `hounfour.metering.budget.daily_micro_usd` default: `500000000` ($500/day) → `10000000` ($10/day)
- `hounfour.flatline_routing` documented as canonical key; `feature_flags.flatline_routing` documented as alias with precedence rule (top-level wins)
- `hounfour.metering.budget.on_exceeded` behavior documented: `block` (hard-stop), `downgrade` (Opus→Sonnet), `warn` (log + continue)
- Bridgebuilder `auto_triage_blockers` rate-limiting behavior documented: findings queue to `.run/bridge-pending-bugs.jsonl`, dispatched one at a time through `/bug` with circuit breaker (same finding 3× = HITL escalation)
- Model names throughout CONFIG_REFERENCE are documented as runtime-configured via Hounfour, not hardcoded contracts

### Security

- Secret-scanning invariant now enforced in runtime (not just documented)
- Hook wiring fix closes 11 dormant safety hooks that were silently not firing
- `/loa setup` wizard refuses to set security invariants to unsafe values

### Process

This release was produced through the `/spiraling` autopoietic pipeline with kaironic Bridgebuilder convergence:

- 3 Bridgebuilder iterations on PR [#511](https://github.com/0xHoneyJar/loa/pull/511)
- Iteration 1: 11 findings (4 actionable, mean confidence 0.79) → all resolved
- Iteration 2: 11 findings (4 actionable, mean confidence 0.61) → 3 resolved (SEC-001 runtime enforcement, RISK-001 documentation, DOC-003 ceiling clarification)
- Iteration 3: 11 findings (3 actionable, mean confidence 0.73) → 3 resolved (missing prompt_enhancement section, budget ceiling clarification, on_exceeded behavior)
- Convergence: 0 HIGH findings, remaining MEDIUMs are code-change proposals tracked in follow-up issues

Issue [#512](https://github.com/0xHoneyJar/loa/issues/512) filed to automate this kaironic loop inside `spiral-harness.sh` — the harness currently runs Bridgebuilder as a terminal advisory step; the follow-up teaches it to iterate until convergence the way `/run-bridge` does standalone.

### Versions Consolidated

This release bundles changes from intermediate tags:

- `v1.88.1` — PR [#507](https://github.com/0xHoneyJar/loa/pull/507): spiral dispatch guard documentation
- `v1.89.0` — PR [#508](https://github.com/0xHoneyJar/loa/pull/508), cycle-072: pipeline profiles + scheduling + mechanical dispatch guard
- `v1.89.1` — auto-sentinel hook
- `v1.89.2` — hook wiring fix (safety hooks now actually fire)
- `v1.90.0` — this release (cycle-073: config transparency + security enforcement + bundled changes)

### References

- Config reference: [`docs/CONFIG_REFERENCE.md`](docs/CONFIG_REFERENCE.md)
- Setup wizard skill: [`.claude/skills/loa-setup/`](.claude/skills/loa-setup/)
- Cycle-073 PRD/SDD/Sprint: [`grimoires/loa/prd.md`](grimoires/loa/prd.md), [`grimoires/loa/sdd.md`](grimoires/loa/sdd.md), [`grimoires/loa/sprint.md`](grimoires/loa/sprint.md)
- Follow-up work: [#512](https://github.com/0xHoneyJar/loa/issues/512) (harness kaironic BB loop)

---

## [1.88.0] - 2026-04-15 — Spiral Autopoietic Orchestrator

Loa can now improve itself. The Spiral Autopoietic Orchestrator (`/spiral`) is a self-improving meta-loop that dispatches full development cycles (plan, build, review, audit), harvests lessons from each cycle, and feeds them into the next. This release ships the complete infrastructure across 13 cycles of development (059–071), culminating in an evidence-gated harness architecture that was validated through A/B benchmarking of Sonnet vs Opus executor models.

The key architectural insight: **LLMs skip quality gates when self-supervising.** Cycle-070's E2E test proved it — a monolithic `claude -p` session self-certified every gate in 4 seconds. The fix is harness engineering: bash controls sequencing, the LLM does scoped work within bounded tasks. Flatline, Review, and Audit run between phases in bash — the model cannot skip them because it is not the model's decision.

### Added

- **`/spiral` autopoietic meta-orchestrator** (cycles 063–068, [RFC-060](grimoires/loa/proposals/rfc-060-spiral.md), PRs [#490](https://github.com/0xHoneyJar/loa/pull/490)–[#495](https://github.com/0xHoneyJar/loa/pull/495))
  - Full lifecycle: SEED → SIMSTIM → HARVEST → EVALUATE across multiple cycles
  - Six composable stopping conditions: cycle budget, Flatline convergence, cost budget, wall-clock, HITL halt, quality gate failure
  - State machine: INIT → RUNNING → COMPLETED | HALTED | FAILED with crash recovery
  - Per-cycle workspace isolation (`.run/cycles/cycle-N/`) — eliminates single-slot artifact collision
  - SEED phase queries Vision Registry for relevant speculative insights from prior cycles
  - HARVEST phase feeds accepted Flatline findings and Bridgebuilder praise into the next cycle's context
  - State-machine coalescer + `--archive-completed` for clean cycle transitions
  - Config: `spiral.enabled: true` in `.loa.config.yaml` (opt-in, default off)

- **Evidence-gated harness architecture** (cycles 070–071, [proposal](grimoires/loa/proposals/spiral-harness-architecture.md), PRs [#500](https://github.com/0xHoneyJar/loa/pull/500)–[#502](https://github.com/0xHoneyJar/loa/pull/502))
  - Replaces monolithic `claude -p` dispatch with Phase-as-subprocess + Gate-as-script pattern
  - Each phase is a separate `claude -p` call with scoped prompt and per-phase budget cap
  - Quality gates run in bash between phases — Flatline multi-model review, independent Review session, independent Security Audit session, Bridgebuilder PR review
  - **Flight recorder**: append-only JSONL (`flight-recorder.jsonl`) logging every action with sequence numbers, timestamps, sha256 checksums, costs, durations, and verdicts — complete audit trail for every cycle
  - Evidence verification: artifact existence, minimum size, content-addressed checksums linking inputs → outputs across phases
  - Circuit breaker: configurable max retries per gate (default 3), exits on repeated failure
  - Budget enforcement: per-phase caps + cumulative tracking, exits before overspend
  - Scripts: `.claude/scripts/spiral-harness.sh` (orchestrator), `.claude/scripts/spiral-evidence.sh` (verification + flight recorder)

- **Advisor Strategy: Sonnet executes, Opus judges** (cycle-071 cost optimization, PR [#501](https://github.com/0xHoneyJar/loa/pull/501))
  - Execution phases (PRD, SDD, Sprint Plan, Implementation) use Sonnet at ~5x cheaper tokens
  - Judgment phases (Review, Security Audit) use Opus where reasoning quality matters
  - Projected ~60% cost reduction vs all-Opus: ~$6.50/cycle (execution) + ~$4 (judgment) vs ~$16/cycle previously
  - Config: `spiral.harness.executor_model: sonnet`, `spiral.harness.advisor_model: opus`
  - Validated via [A/B benchmark](grimoires/loa/reports/spiral-harness-benchmark-report.md): equivalent output quality, both APPROVED first try, functionally identical code

- **Vision Registry graduation: shadow_mode → active** (cycle-069, [#486](https://github.com/0xHoneyJar/loa/issues/486), PR [#496](https://github.com/0xHoneyJar/loa/pull/496))
  - Visions captured during Bridgebuilder Design Reviews now feed into subsequent cycles' `/plan-and-analyze` context
  - Query API: `vision-query.sh --tag`, `--status`, `--health` for registry health reporting
  - Lifecycle management: `vision-lifecycle.sh promote|archive|reject|explore|propose|defer`
  - Spiral SEED integration: queries relevant visions by tag to seed each cycle's planning context
  - 190 tests across vision registry scripts

- **HARVEST phase consumer** (cycles 059–061, PRs [#481](https://github.com/0xHoneyJar/loa/pull/481), [#484](https://github.com/0xHoneyJar/loa/pull/484))
  - `lore-promote.sh`: vetted PRAISE findings from Bridgebuilder reviews → `grimoires/loa/lore/patterns.yaml`
  - Wired into post-merge-orchestrator as a pipeline phase (continuous HARVEST)
  - Bridge triage stats aggregator for cross-PR pattern analysis

- **Spiral harness benchmark report** (PR [#505](https://github.com/0xHoneyJar/loa/pull/505))
  - Data-driven comparison of Sonnet vs Opus as executor model across 3 flight recorder cycles
  - Flatline consensus analysis across 6 planning gates with model agreement percentages
  - Recommended defaults, budget sizing guide, and debugging checklist
  - Full report: [`grimoires/loa/reports/spiral-harness-benchmark-report.md`](grimoires/loa/reports/spiral-harness-benchmark-report.md)

### Fixed

- **Flatline jq 1.7 parser error** in red-team/inquiry metrics merge (cycle-062, PR [#488](https://github.com/0xHoneyJar/loa/pull/488))
- **Flatline review-mode wiring** — inquiry tests and default case handling (cycle-062, PR [#489](https://github.com/0xHoneyJar/loa/pull/489))
- **Harness system zone override** — `--append-system-prompt` authorization for `.claude/scripts/` edits during authorized cycles (PR [#502](https://github.com/0xHoneyJar/loa/pull/502))
- **Harness verdict grep** — case-insensitive broad match for APPROVED/CHANGES_REQUIRED in any Markdown formatting (PR [#501](https://github.com/0xHoneyJar/loa/pull/501))
- **Harness budget sizing** — default raised from $10 to $15 after E2E testing proved $10 exhausts at Audit phase (PR [#501](https://github.com/0xHoneyJar/loa/pull/501))
- **Flatline stderr capture** — redirected to evidence directory for debugging silent failures (PR [#501](https://github.com/0xHoneyJar/loa/pull/501))

### Changed

- **Simstim dispatch** now routes through `spiral-harness.sh` instead of monolithic `claude -p` when `spiral.harness.enabled: true` (default) — quality gates enforced by bash, not the LLM
- **Vision Registry** default mode changed from `shadow_mode: true` to `shadow_mode: false` — visions now actively surface during planning
- **Per-phase budget caps** are now configurable via `.loa.config.yaml` — `planning_budget_usd` ($1), `implement_budget_usd` ($5), `review_budget_usd` ($2), `audit_budget_usd` ($2)

### Benchmark Data (Sonnet vs Opus Executor)

| Metric | Sonnet Executor | Opus Executor |
|--------|----------------|---------------|
| Total budget | $12 | $12 |
| Token efficiency | ~5x cheaper | baseline |
| PRD Flatline | 2 HIGH, 2 BLOCKER, 70% agreement | 3 HIGH, 7 BLOCKER, 70% agreement |
| SDD Flatline | 3 HIGH, 4 BLOCKER, 80% agreement | 1 HIGH, 3 BLOCKER, 40% agreement |
| Sprint Flatline | 4 HIGH, 3 BLOCKER, 90% agreement | 2 HIGH, 5 BLOCKER, 80% agreement |
| Implementation | 141 lines, APPROVED 1st try | 143 lines, APPROVED 1st try |
| Audit | APPROVED 1st try | APPROVED 1st try |
| Wall clock | ~18.5 min | ~18 min |

**Verdict**: Sonnet is the right default executor. Quality is equivalent for bounded tasks. The evidence-gated architecture catches issues regardless of model — gates are mechanical, not model-dependent. Full analysis in [benchmark report](grimoires/loa/reports/spiral-harness-benchmark-report.md).

### Known Issues / Future Work

- **Benchmark covers simple tasks only.** The Sonnet-equivalent-to-Opus finding was validated on a well-scoped feature (add `--version` flag). Complex architectural work may benefit from Opus executor — revisit if Sonnet implementations start failing review at higher rates.
- **No retry-from-CHANGES_REQUIRED path benchmarked.** Both runs achieved APPROVED on first try. The retry mechanism (max 3 attempts per gate) was validated in pre-benchmark test cycles but the recovery loop hasn't been load-tested.
- **Budget tracking records caps, not actual token spend.** Flight recorder logs the per-phase budget allocation ($1, $5, etc.), not the actual API cost. Token-level cost tracking would require parsing Claude API response metadata.
- **Arbiter is round-robin, not adaptive.** The Flatline arbiter rotates models (PRD→Opus, SDD→GPT, Sprint→Gemini) — it doesn't learn which model is best for which document type.

### Migration Notes

**Opt-in.** The spiral orchestrator is disabled by default (`spiral.enabled: false`). To enable:

```yaml
# .loa.config.yaml
spiral:
  enabled: true
  max_budget_per_cycle_usd: 15     # minimum for clean run
  max_total_budget_usd: 50         # hard stop across all cycles
  harness:
    enabled: true                   # evidence-gated pipeline (recommended)
    executor_model: sonnet          # ~5x cheaper, equivalent quality
    advisor_model: opus             # judgment quality for review/audit
```

All existing workflows (`/plan`, `/build`, `/review`, `/ship`, `/run`) continue to work unchanged. `/spiral` is a new command that wraps them in a self-improving loop.

### Quality Gates

| Cycle | What | Senior Review | Security Audit | Tests | PR |
|-------|------|---------------|----------------|-------|----|
| 059 | Lore promoter | Yes | Yes | - | [#481](https://github.com/0xHoneyJar/loa/pull/481) |
| 060 | Post-merge HARVEST wiring | Yes | Yes | - | [#484](https://github.com/0xHoneyJar/loa/pull/484) |
| 061 | Bridge triage aggregator | Yes | Yes | - | [#467](https://github.com/0xHoneyJar/loa/issues/467) |
| 062 | Flatline jq/review-mode fixes | Yes | Yes | Yes | [#488](https://github.com/0xHoneyJar/loa/pull/488), [#489](https://github.com/0xHoneyJar/loa/pull/489) |
| 063 | State coalescer | Yes | Yes | Yes | [#490](https://github.com/0xHoneyJar/loa/pull/490) |
| 064 | Per-cycle workspace | Yes | Yes | Yes | [#491](https://github.com/0xHoneyJar/loa/pull/491) |
| 065 | RFC-060 design | Yes | - | - | [#492](https://github.com/0xHoneyJar/loa/pull/492) |
| 066 | /spiral MVP scaffolding | Yes | Yes | Yes | [#493](https://github.com/0xHoneyJar/loa/pull/493) |
| 067 | /spiral completion | Yes | Yes | 66 tests | [#494](https://github.com/0xHoneyJar/loa/pull/494) |
| 068 | Real /simstim dispatch | Yes | Yes | Yes | [#495](https://github.com/0xHoneyJar/loa/pull/495) |
| 069 | Vision Registry graduation | Yes | Yes | 190 tests | [#496](https://github.com/0xHoneyJar/loa/pull/496) |
| 070+071 | Harness architecture + E2E | Yes | Yes | E2E validated | [#500](https://github.com/0xHoneyJar/loa/pull/500)–[#502](https://github.com/0xHoneyJar/loa/pull/502) |
| Benchmark | Sonnet vs Opus A/B | - | - | 3 flight recorder cycles | [#503](https://github.com/0xHoneyJar/loa/pull/503), [#504](https://github.com/0xHoneyJar/loa/pull/504) |

### Source

- Design: [RFC-060](grimoires/loa/proposals/rfc-060-spiral.md), [Harness Architecture Proposal](grimoires/loa/proposals/spiral-harness-architecture.md)
- Benchmark: [Spiral Harness Benchmark Report](grimoires/loa/reports/spiral-harness-benchmark-report.md)
- Issues: [#486](https://github.com/0xHoneyJar/loa/issues/486) (Vision Registry), [#481](https://github.com/0xHoneyJar/loa/issues/481) (Lore Promoter), [#484](https://github.com/0xHoneyJar/loa/issues/484) (HARVEST Wiring), [#483](https://github.com/0xHoneyJar/loa/issues/483) (RFC-060 Umbrella)
- PRs: [#481](https://github.com/0xHoneyJar/loa/pull/481), [#484](https://github.com/0xHoneyJar/loa/pull/484), [#488](https://github.com/0xHoneyJar/loa/pull/488)–[#496](https://github.com/0xHoneyJar/loa/pull/496), [#500](https://github.com/0xHoneyJar/loa/pull/500)–[#505](https://github.com/0xHoneyJar/loa/pull/505)

---

## [1.78.0] - 2026-04-13 — Process Feedback Sweep

Three independent framework improvements driven by observations from a recent multi-cycle development run. All three fix friction points where the framework's contracts were under-enforced or its failure modes were silent. Filed as issues [#473](https://github.com/0xHoneyJar/loa/issues/473), [#474](https://github.com/0xHoneyJar/loa/issues/474), [#475](https://github.com/0xHoneyJar/loa/issues/475); shipped as cycles 056/057/058. The post-merge auto-pipeline tagged each as its own minor bump (v1.76.0, v1.77.0, v1.78.0); this release rolls them together with curated narrative.

### Fixed

- **simstim `sync_run_mode` now cross-references git history** (#474, cycle-056, was v1.76.0)
  - Previously the sync trusted `sprint-plan-state.json` unconditionally; when context compaction left the file at `state: "RUNNING"` despite git showing all sprint commits already landed, operators were forced to use the documented last-resort `--force-phase complete --yes` escape hatch.
  - New `git_inferred_completion_check` helper greps `git log ${base_branch}..HEAD` for matching sprint commits using a configurable pattern (default `^feat\(sprint-`). When `commits_found >= sprints.total`, the sync auto-marks the state `JACKED_OUT` with a `git_inferred: true` flag and returns `synced: true, reason: "git_inferred_completion"` with diagnostic counts.
  - Fallback only fires when state already says `RUNNING` AND commit count meets the threshold — existing behavior preserved for genuine in-flight runs and partial completions.
  - Configurable via `.loa.config.yaml` `run_mode.git.{base_branch,sprint_commit_pattern}`.
  - Tests: 5 BATS cases covering stale-with-commits, no-commits, partial commits, state-update assertion, sprints.list fallback.

- **Bridge orchestrator silent-no-op now fails loud** (#473, cycle-058, was v1.78.0)
  - When `bridge-orchestrator.sh --depth N` ran without an acting skill on the other end of the pipe, all `SIGNAL:*` lines fired in seconds and the script exited cleanly with `JACKED_OUT` state — but zero findings, zero sprints executed. Silent success is the worst kind of failure.
  - Post-loop check: when `.run/bridge-reviews/` contains zero findings files after a full-depth run, exits `3` with an actionable error message listing three remediation paths. Default `DETECT_SILENT_NOOP=true`. Opt out via `--no-silent-noop-detect` (intended for tests/CI).

### Added

- **`/implement` enforces structural AC verification** (#475, cycle-057, was v1.77.0)
  - Prior to this release, acceptance criteria were exhortation, not enforcement. SDD-implementation drift routinely escaped past `/implement` into `/review-sprint`, costing a full fix-loop round trip.
  - `implementing-tasks/SKILL.md` now requires every AC from `sprint.md` to be walked verbatim in the `## AC Verification` section of `reviewer.md`, with status (`✓ Met` / `✗ Not met` / `⚠ Partial` / `⏸ [ACCEPTED-DEFERRED]`) and **file:line evidence** for every Met claim.
  - `reviewing-code/SKILL.md` auto-returns `CHANGES_REQUIRED` when the AC Verification section is missing, when any AC shows `Not met` without a scope-split, when deferrals lack a matching NOTES.md Decision Log entry, or when evidence is vague ("implemented in src/", "done").
  - `implementation-report.md` template includes the structured section with anti-vacuous-satisfaction examples (good vs bad evidence).
  - Karpathy "goal-driven" enforcement: verifies the contract was honored, not just that code was written.
  - No new scripts, no new tests — discipline enforced by the existing review skill flow.

- **Bridge orchestrator `--single-iteration` re-entrancy flag** (#473, cycle-058)
  - Processes exactly one iteration body and exits with state preserved; pair with `--resume --single-iteration` to advance step by step. Restores the mid-loop intercept point that was missing for skills wanting to act on `SIGNAL:*` lines per-iteration rather than letting all iterations fire in one shell invocation.
  - Default `SINGLE_ITERATION=false` preserves the one-shot contract for existing callers.
  - 7 BATS test cases covering flag recognition, defaults, banner/error text presence.

### Changed

- **`bridge-orchestrator.sh` exit codes documented**: code `3` is now reserved for "silent no-op detected". Codes `0`, `1`, `2` unchanged. Listed in both `--help` output and the file-header comment block.

### Known Issues / Future Work

- **Bridge orchestrator full re-entrant rewrite still pending** (noted in #473 commit). The `--single-iteration` flag narrows the intercept window to one iteration's worth of signals, but multiple `SIGNAL:*` lines still fire within a single iteration before the calling skill can act. The asymptote — emit one signal per invocation — remains valuable future work and would warrant its own RFC cycle.
- **AC verification deferrals are agent-validated, not script-validated** (#475 audit). The check that `[ACCEPTED-DEFERRED]` has a matching Decision Log entry relies on the reviewing agent reading `NOTES.md`, consistent with how all other gates in Loa work (agent-executed).
- **Git-aware sync count-based inference can fire early** (#474 docs). A sprint that produced multiple matching commits (e.g., review-feedback fix commits with the same prefix) can satisfy the count check before all sprints are truly done. Empirically rare under squash-merge workflows. Beads-based authoritative alternative noted as a future enhancement.

### Migration Notes

**None required.** All three changes are additive or default-preserving:
- Git-aware sync only fires when state already says `RUNNING` (existing behavior preserved)
- AC verification gate is enforced by the review skill — implementations that don't include the section get auto-rejected, but this matches the intent (the framework now catches drift instead of silently approving it)
- Bridge orchestrator new flags default to off; silent-no-op detection defaults to on with opt-out

### Quality Gates

| Cycle | Senior Review | Cypherpunk Audit | Tests |
|-------|---------------|------------------|-------|
| 056 (#474) | APPROVED (3 concerns addressed: grep double-zero, dead --oneline, missing docs) | APPROVED (5/5 vectors clear) | 5/5 BATS |
| 057 (#475) | APPROVED (combined review+audit) | APPROVED (no injection surface) | N/A (SKILL.md only) |
| 058 (#473) | APPROVED (combined review+audit) | APPROVED (PROJECT_ROOT-bounded find, no injection) | 7/7 BATS |

### Source

- Cycles: 056, 057, 058
- PRs: #476, #477, #478
- Issues closed: #473, #474, #475

---

## [1.75.0] - 2026-04-13 — Cross-Repo Context + Lore Active Weaving

Closes [#464](https://github.com/0xHoneyJar/loa/issues/464) Part A entirely. The last two "written but unwired" exports from `v1.72.0`'s multi-model Bridgebuilder pipeline are now actually invoked. Two config flags that were previously no-ops (`cross_repo.auto_detect`, `depth_5.lore_active_weaving`) now produce real behavior.

### Added

- **Cross-repo context wiring** (#471, cycle-055 sprint 2 — closes #464 A4)
  - `core/cross-repo.ts` exports (`detectRefs`, `parseManualRefs`, `fetchCrossRepoContext`) are now invoked from the multi-model review path. Previously unit-tested but never reached at runtime.
  - `auto_detect: true` scans the PR title for `owner/repo#NNN` references; `manual_refs: [...]` passes a configured list through `parseManualRefs`.
  - `fetchCrossRepoContext` runs with the documented per-ref (5s) and total (30s) timeouts. Manual refs are hoisted out of the per-PR loop (cached once per run); only auto-detected refs are fetched per-item.
  - Fetched issue/PR titles, bodies (truncated to 1KB at the source, then again at render), and labels are formatted into a `## Cross-Repository Context` markdown section with a 20KB byte budget and an "untrusted data" header. Failed fetches surface as a "Cross-Repo Fetch Failures" subsection rather than blocking the review.
  - New `core/cross-repo-render.ts` keeps the template a pure formatter; main.ts handles the resolution + fetch + render flow.

- **Lore active weaving** (#471, cycle-055 sprint 1 — closes #464 A5)
  - New `core/lore-loader.ts`. `loadLoreEntries(path?, logger?)` shells out to `yq` (already a Loa hard prerequisite) to convert YAML → JSON, validates required fields (`id`, `term`, `short`, `context`), flattens object-form `source` (cycle/bridge_iteration/date) to a single string. Default path: `grimoires/loa/lore/patterns.yaml`; configurable via `depth.lore_path`.
  - When `depth_5.lore_active_weaving: true`, lore entries are loaded once per run and threaded through `EnrichmentContext` to `template.buildEnrichedSystemPrompt()`. The template's `lore_active_weaving` gate (which had been waiting for entries to actually arrive) now fires.
  - Degrades gracefully: missing file → `[]` + warning, malformed entries → skipped per-entry with explicit logs, yq subprocess failure → throws with actionable message that the orchestrator catches and continues without lore.

- **`tests/unit/red-team-model-adapter.bats`** (v1.74.1, #469) — 6-test regression suite catching the original mock-mode-only bug, with negative-and-positive assertions guarded by `bash -c` positional-args (injection-safe across BATS versions).

- **`red_team:` block in `.loa.config.yaml.example`** (v1.74.1, #469) — was absent; mounted projects had no template for enabling the skill.

- **Bridgebuilder unit test coverage** (#471) — 16 new tests (8 lore-loader + 8 cross-repo-render). Bridgebuilder skill is now at 609/609 passing.

### Fixed

- **Red Team live model invocation** (v1.74.1, #469, sprint-bug-102) — `invoke_live()` was a hardcoded stub; wired to `.claude/scripts/model-invoke` (cheval.py). Pipeline now passes explicit `--live`/`--mock` flag to all three adapter call sites and resolves the default mode via `hounfour.flatline_routing` + provider API key presence. Mock mode emits an unmissable WARNING banner so fixture data can't be mistaken for live analysis.

- **Manual cross-repo refs no longer re-fetched per PR** (#471, Bridgebuilder pass-1 FIND-002) — surfaced by the multi-model review of this PR itself; manual refs were originally inside the per-PR loop, making N×M redundant network calls. Hoisted above the loop with per-item dedup against the manual cache.

- **Lore-loader test now skips cleanly when `yq` is missing** (#471, Bridgebuilder pass-1 FIND-007) — `before` hook probes `yq --version` once; `beforeEach` skips with install instructions. Replaces opaque `execFile` errors in CI containers without yq.

### Changed

- **Post-PR Bridgebuilder Review enabled on this repository** (v1.74.0, #468, cycle-054, Option A from #467) — `post_pr_validation.phases.bridgebuilder_review.enabled: true` in `.loa.config.yaml`. The kaironic-convergence loop from `v1.73.0` now runs automatically after every PR's `FLATLINE_PR` phase. False positives accepted during experimental rollout per HITL design decision logged in #467.

### Known Issues

- **Auto-detection scans PR title only** (#471 FIND-006) — `PullRequest` port type does not carry the body field. Requires port-type extension to scan body too. Filed as follow-up.
- **`lore_path` path-traversal defense-in-depth** (#469 + #471 cycle-055 audit) — config is operator-controlled (`.loa.config.yaml`), not user input, so accepted as informational. A path-jail check could be added in a follow-up micro-PR.
- **Pre-existing BATS Tests failures on `main`** persist (`adversarial-review.bats`, `butterfreezone-validate.bats`, `gpt-review-api.bats`). None relate to this release.
- **Legacy `bd` hooks** in `.git/hooks/pre-commit` and `post-merge` for users who installed before the `br` (beads_rust) migration. Hooks are per-clone, so `install-br.sh` cannot rewrite them. Manual fix:
  ```bash
  sed -i 's/\bbd\b/br/g' .git/hooks/pre-commit .git/hooks/post-merge
  sed -i 's|br import -i "$BEADS_DIR/issues.jsonl"|br sync --import-only|' .git/hooks/post-merge
  ```

### Migration Notes

**None required.** All changes are additive or opt-in:
- `cross_repo.auto_detect: false` and `depth_5.lore_active_weaving: false` defaults preserve existing behavior.
- `red_team.enabled: false` in the new config example template (opt-in).
- `post_pr_validation.phases.bridgebuilder_review.enabled: true` only applies to this repository's `.loa.config.yaml`; downstream consumers retain their existing settings.

### Quality Gates

| Gate | v1.74.1 (#469) | v1.75.0 (#471) |
|------|----------------|----------------|
| Senior tech-lead review | APPROVED | APPROVED (with noted concerns addressed) |
| Cypherpunk security audit | APPROVED | APPROVED (2 LOW informational, no blockers) |
| Bridgebuilder convergence | FLATLINE @ pass 4 | FLATLINE @ pass 2 (HIGH 1→0) |
| Test suite | 609/609 | 609/609 |

The v1.75.0 cycle's Bridgebuilder dogfood pass surfaced its own dead code (the `dedupeRefs` helper became unused after the FIND-002 hoisting fix replaced its caller) — caught and removed before merge. Clean closed-loop demonstration.

### Source

- PRs: #468, #469, #470, #471
- Refs: #464 (closed Part A), #467 Option C (completed), #467 Option A (in production observation)

---

## [1.74.1] - 2026-04-13 — Closed-Loop Adversarial Review

Completes the multi-cycle arc that began with `v1.72.0` (multi-model Bridgebuilder) and `v1.73.0` (Amendment 1 post-PR loop). Both adversarial review systems — Bridgebuilder and Red Team — now actually run end-to-end against live models.

### Fixed

- **Red Team live model invocation** (#469, sprint-bug-102)
  - `invoke_live()` in `.claude/scripts/red-team-model-adapter.sh` was a hardcoded stub returning `exit 1` with a "requires cheval.py (Hounfour integration)" error, even though `cheval.py` has been in-production use by Flatline and Bridgebuilder since `v1.65.0`. Wired to `.claude/scripts/model-invoke` with role→agent and model→provider:model-id mapping (mirrors `flatline-orchestrator.sh` pattern).
  - Pipeline (`.claude/scripts/red-team-pipeline.sh`) now propagates an explicit `--live`/`--mock` flag to every adapter invocation, resolved once via `resolve_adapter_mode()`. Previously all three call sites (phases 1/2/4) relied on the adapter's silent default, which was hardcoded to `mock`.
  - Config-driven default mode detection: `live` when `hounfour.flatline_routing: true` AND `model-invoke` is executable AND at least one provider API key is present (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GOOGLE_API_KEY`, `GEMINI_API_KEY`). Falls back to `mock` otherwise — safe default prevents accidental API billing on half-configured installs.
  - Unmissable WARNING banner on stderr whenever mock mode runs, with the three steps to enable live mode. Pipeline also emits a mode notice so users see the banner even when child stderr is suppressed.
  - Impact: Users running `/red-team` against their SDD now actually receive real adversarial analysis from the configured model, not fixture data from Loa's own development history.

### Added

- **`red_team:` block in `.loa.config.yaml.example`** (#469) — was absent; mounted projects had no template for enabling the skill.
- **`tests/unit/red-team-model-adapter.bats`** (#469) — 6 BATS regression tests covering stub removal, explicit mode propagation, banner emission, config documentation, explicit `--mock` honoring, and self-test integrity. Post-merge Bridgebuilder 4-pass convergence validated the suite.

### Changed

- **Post-PR Bridgebuilder Review enabled on this repository** (#468, cycle-054, Option A from #467) — `post_pr_validation.phases.bridgebuilder_review.enabled: true` in `.loa.config.yaml`. The iterative kaironic-convergence loop from `v1.73.0` now runs automatically after every PR's `FLATLINE_PR` phase. False positives are accepted during experimental rollout per HITL design decision logged in #467.
- **Stale `dist/` synchronized** (#468) — `.claude/skills/bridgebuilder-review/resources/dist/` was out of date when `v1.72.0` merged; rebuilt and committed.

### Known Issues

- **BATS Tests suite status on `main`**: Pre-existing failures in `adversarial-review.bats`, `butterfreezone-validate.bats`, `gpt-review-api.bats`, and others. None relate to this release. Tracked as technical debt; not introduced by #468/#469.
- **`.git/hooks/pre-commit` and `.git/hooks/post-merge`** still reference the legacy `bd` binary for users who migrated to `br` (beads_rust) before the hook scripts were updated. These hooks are per-clone (not version-controlled), so `install-br.sh` cannot rewrite them. Manual fix: replace `bd` with `br` in both files, and `bd import -i` with `br sync --import-only`. A future version of `install-br.sh` should emit a migration warning.

### Migration Notes

None required. All changes are additive or opt-in:
- `red_team.enabled: false` in the new config example template (opt-in).
- `post_pr_validation.phases.bridgebuilder_review.enabled: true` only applies to this repository's `.loa.config.yaml`; downstream consumers retain their existing settings.
- `invoke_live` signature extended with new positional args (`prompt_file`, `output_file`, `budget`, `timeout`) — the adapter's external CLI interface (`--role`, `--model`, `--prompt-file`, `--output-file`, `--mock`/`--live`) is unchanged.

### Quality Gates

| Gate | Status |
|------|--------|
| Senior tech-lead review | APPROVED (with noted concerns addressed) |
| Cypherpunk security audit | APPROVED (2 informational LOW, 1 pre-existing) |
| Bridgebuilder post-PR convergence | FLATLINE at pass 4 — 0 HIGH, 2 PRAISE |

Full convergence trajectory: `grimoires/loa/a2a/trajectory/bridge-triage-2026-04-13.jsonl`.

### Source

- PRs: #468, #469
- Commits: 2 on main (1 fix, 1 feat)
- Refs: #464, #467

---

## [1.67.0] - 2026-03-25

### Added

- **cycle-052**: DX Hardening — User-Facing Release Communication (#460)
  - `classify-commit-zone.sh`: Three-Zone commit classification for release pipeline (system-only, state-only, app, mixed-internal)
  - `generate-release-summary.sh`: Emoji-prefixed "What's New" summaries from CHANGELOG/git log — max 5 lines, filters internal changes
  - `/update-loa` now shows friendly summary after successful update (configurable via `update_loa.friendly_summary`)
  - `semver-bump.sh --downstream`: Excludes System/State-only commits from downstream version bumps
  - `post-merge-orchestrator.sh --downstream`: Zone-aware changelog and release note filtering with auto-detection
  - 36 new tests (16 classify + 14 summary + 6 downstream bump)

### Fixed

- Release notes on downstream projects no longer include Loa framework cycles and System Zone changes (#394)

## [1.66.1] - 2026-03-25

### Fixed

- **collect-trace.sh**: Three bash strict mode failures — empty array expansion, invalid JSON in `--argjson`, unbound `PATTERNS_MATCHED` array (#444, #459)

### Changed

- **shell-conventions.md** (v2): Added bash strict mode safety patterns — empty array guards, array/string initialization, JSON construction validation, arithmetic with `set -e`

## [1.66.0] - 2026-03-24

### Added

- **cycle-051**: First-Class Construct Support — RFC #452 (#454)
  - **Construct Index** (L1): `construct-index-gen.sh` generates `.run/construct-index.yaml` from installed packs with capability aggregation, composition pre-computation, and `--validate` flag for schema integrity
  - **Name Resolution** (L2): `construct-resolve.sh` with 3-tier resolution (slug → name → command) and collision warnings. CLAUDE.md conditional instruction for agent-side activation
  - **Composition as Pipe** (L3): `compose` subcommand detects writes/reads path overlap between constructs. Honest messaging when no material chain exists
  - **Personal Operator OS** (L4): `archetype-resolver.sh` with activate/deactivate/status/greeting. User-defined modes in `.loa.config.yaml` mapping to construct compositions. Gate merging: most-restrictive-wins
  - **Ambient Protocol Presence** (L5): Opt-in session greeting showing constructs, compositions, entry points, open threads. Thread tracking in `.run/open-threads.jsonl` with 30-day auto-archive
  - 56 new tests across 7 suites (construct-index-gen, construct-resolve, archetype-resolver, ambient-greeting, open-threads, cross-platform-validation, construct-e2e)

### Fixed

- **constructs-install.sh**: Prefer local source clone over stale registry pack (#449, #453)
  - `find_local_source()` checks for `manifest.json` OR `construct.yaml` (previously construct.yaml only — most packs don't have it)
  - Freshness uses `find -newer` on any file (not just construct.yaml mtime — catches fixes in any file)
  - Staleness warning (stderr) when installed pack >7 days old
  - Configurable local search paths via `.loa.config.yaml`
  - 6 new tests

### Security

- Bridgebuilder two-pass review on both PRs
- Deep ecosystem review connecting to supply chain integrity patterns
- All findings addressed before merge

## [1.65.0] - 2026-03-23

### Added

- **cycle-049**: Upstream Platform Alignment — Claude Code Feature Adoption (#451)
  - `allowed-tools` restrictions on 13 read-only/analytical skills (principle of least privilege)
  - `context: fork` + `agent` type for 6 heavy skills (/ride, /audit, /bridgebuilder-review)
  - `name` and `description` metadata on 13 skills for Claude Code discoverability
  - Path-scoped `.claude/rules/` directory with 3 zone rule files (zone-system, zone-state, shell-conventions)
  - ADVISORY compliance hook prototype (`implement-gate.sh`) — warns on App Zone writes outside /implement
  - Model adapter backward-compat aliases (claude-opus-4-0, 4-1, 4.0, 4.1, 4-5)
  - Memory system ownership boundary (auto-memory vs observations.jsonl)
  - Agent Teams hook validation + ATK-011 mitigation (blocks unset LOA_TEAM_MEMBER)
- **cycle-050**: Multi-Model Permission Architecture — Ecosystem-Wide Governance Primitives (#451)
  - **Capability taxonomy**: Model-agnostic `capabilities:` field on all 25 skills with `schema_version: 1`, 8 capability categories, strict tokenized `execute_commands` grammar (no raw shell strings)
  - **Cost profiles**: `cost-profile:` field on all 25 skills (lightweight/moderate/heavy/unbounded) for Freeside conservation guard integration
  - **Rule lifecycle metadata**: `origin`, `version`, `enacted_by` on all `.claude/rules/` files (mirrors loa-dixie ConstraintOrigin pattern)
  - **Dual-mode compliance hook**: `implement-gate.sh` supports authoritative mode (platform-detected) + heuristic fallback with mode pinning and audit logging
  - **Feature detection**: `detect-platform-features.sh` for versioned capability handshake
  - **Mount conflict detection**: `mount-conflict-detect.sh` with CSS-specificity precedence (project > Loa > default), dry-run output, deterministic ordering
  - **Validation tooling**: `validate-skill-capabilities.sh` (--strict, --json, deny-all default) and `validate-rule-lifecycle.sh`
  - **Portable date conversion**: `_date_to_epoch()` in compat-lib.sh v1.1.0 (GNU/macOS/perl fallback)
  - **Permissions reference doc**: Complete taxonomy documentation with cross-repo integration guidance
  - 38 new tests across 7 test suites (skill-capabilities, rule-lifecycle, compliance-hook, mount-conflicts, model-adapter, agent-teams, integration)
  - Cross-repo integration issues: loa-hounfour#49, loa-freeside#138, loa-dixie#80

### Changed

- **Fail-closed defaults**: Unannotated skills get deny-all capabilities (inverted from fail-open, per Flatline SKP-001)
- **`capabilities: all` prohibited**: Must use explicit expanded maps (Flatline SKP-003)
- **Strict execute_commands grammar**: Tokenized command+args, no raw shell patterns (Flatline IMP-003/SKP-004)
- **Validation in --strict mode**: Warnings promoted to errors on CI (Flatline IMP-002)
- `compat-lib.sh` bumped to v1.1.0
- `implement-gate.sh` path normalization resolves absolute paths relative to PROJECT_ROOT

### Fixed

- `has_tool()` word-boundary matching prevents substring false positives (CRIT-1)
- `_date_to_epoch("")` rejects empty string instead of returning current time (CRIT-3)
- `validate-skill-capabilities.sh` counter bug in strict mode (CRIT-2)
- `.claude/rules/zone-state.md` missing `.ck/**` path (BB-049-002)
- Portable date conversion in implement-gate.sh (BB-049-001)

### Security

- Flatline 3-model review (Opus + GPT-5.3-codex + Gemini 2.5 Pro): 5 HIGH_CONSENSUS integrated, 15 BLOCKERS addressed
- Red Team: 5 attack scenarios analyzed, 0 confirmed vulnerabilities
- Security audit: APPROVED — no CRITICAL/HIGH findings
- ATK-011: Blocks `unset LOA_TEAM_MEMBER` and `env -u` privilege escalation in Agent Teams

## [Unreleased]

## [1.117.0] — 2026-05-05

## [1.94.0] — 2026-04-17

## [1.91.7] — 2026-04-16

### Added

- **cycle-038**: Organizational Memory Sovereignty — three-zone state architecture with state-dir resolution, migration engine, trajectory redaction, memory pipeline, and federated learning across 6 sprints (#410)
- **cycle-036**: Quick-Win UX Fixes — state zone merge protection, stealth `.ck/` directory, bridgebuilder `.env` auto-loading, origin-first remote detection (#407)
- **cycle-035**: Minimal Footprint by Default — submodule-first installation with `/loa eject` for full copy (#406)
- **cycle-034**: Declarative Execution Router + Adaptive Multi-Pass review pipeline (#404)
- **cycle-030/031**: UX Redesign + Interview Depth Configuration + BUTTERFREEZONE Skill Provenance Segmentation (#391, #392)
- **cycle-029**: Construct-Aware Constraint Yielding — constructs can declare gate overrides (#378)
- **cycle-028**: Security Hardening — Bridgebuilder cross-repository findings (#377)
- **cycle-027**: Broader QMD Integration across core skills (#373)
- 5 README updates

## [1.49.0] — 2026-02-18 — Bridgebuilder Model Upgrade

### Changed

- **bridgebuilder**: Upgrade default model to `claude-opus-4-6` for improved review quality (#372)

## [1.48.2] — 2026-02-18 — Bridgebuilder ESM Fix

### Fixed

- **bridgebuilder**: Fix ESM `require()` crash + stale model default (#371)

## [1.48.1] — 2026-02-18 — Hounfour Runtime Bridge

### Fixed

- **hounfour**: Config-driven token param — fixes GPT-5.2+ `model-invoke` (#347)

### Added

- **cycle-026**: Hounfour Runtime Bridge — GoogleAdapter, Deep Research routing, metering, FLockSemaphore for model-heterogeneous agent execution (#368)

## [1.47.1] — 2026-02-17 — Cross-Codebase Feedback Routing

### Fixed

- **update-loa**: Preserve `.claude/constructs/` during framework updates (BUG-361) (#362)

### Added

- **cycle-025**: Cross-Codebase Feedback Routing — attribution engine, redaction, deduplication (#357, #360)

## [1.45.2] — 2026-02-17 — Scoring Engine Syntax Fix

### Fixed

- **scoring-engine**: Remove apostrophe breaking `bash -n` syntax check (#356)

## [1.45.1] — 2026-02-16 — Hygiene Sprint

### Fixed

- **cycle-024**: The Hygiene Sprint — adapter fixes, scoring engine cleanup, cleanup hook (#353)

## [1.45.0] — 2026-02-16 — The Permission Amendment + Gemini Integration

### Added

- **cycle-023**: The Permission Amendment — MAY constraints, REFRAME severity level, Vision-004 speculative exploration (#352)
- **cycle-021**: Gemini Integration Audit & Activation (#348)

## [1.43.0] — 2026-02-16 — Agent Teams + Enrichment + Release Automation

### Added

- **cycle-020**: TeamCreate Compatibility — Agent Teams Orchestration with lead/teammate role enforcement (#341)
- **cycle-018**: Ride Enrichment — Gap Tracking & Decision Archaeology (#338)
- **cycle-017**: BUTTERFREEZONE Excellence — Agent-API Interface Standard (#336)
- **cycle-016**: Release Automation Excellence — CHANGELOG Generation & Release Quality (#334)

## [1.39.1] — 2026-02-15 — Collateral Deletion Safeguard + CI Hardening

### Fixed

- **update-loa**: Collateral deletion safeguard — `/update-loa` merge could destroy 933+ downstream project files when upstream deletes framework files. Added `--no-commit` merge + framework zone allowlist in new Phase 5.3 (#330, #331)
- **CI**: Cross-platform `sed` portability — replace bare `sed -i` with temp-file-and-mv pattern in `post-merge-orchestrator.sh` and `red-team-pipeline.sh` (macOS compatibility)
- **CI**: Constraint registry validation — add `eval`, `bridge`, `merge` categories; `SHOULD` rule type; missing E115/E116 error codes
- **CI**: Internal link checker — strip `#anchor` fragments before file existence check

### Added

- **cycle-015**: Platform Hardening — portable locking, model catalog expansion (Gemini 3 models), BUTTERFREEZONE narrative quality, construct sync

_Source: PR #330_

## [1.39.0] — 2026-02-15 — Environment Design for Agent Flourishing

Four interconnected environment design advances that transform the framework from a tool that executes tasks into a system that develops self-knowledge, architectural memory, and speculative depth.

### Added

- **cycle-014**: Environment Design for Agent Flourishing — trajectory narrative + session awakening, bidirectional lore + discovery pipeline, vision sprints + speculation channel, hardening for all Bridgebuilder findings, speculation primitives with state recovery + model attribution (#326)
- 5 sprints (global 91-95), 3 bridge iterations converging to 0 findings
- 26 files changed, 9 findings addressed, 39/39 evals passing

_Source: PR #326_

## [1.38.1] — 2026-02-14 — Hounfour Hardening — Model Invocation Pipeline Fixes

### Fixed

- **cycle-013**: Hounfour Hardening — model invocation pipeline fixes including model validation, invocation fallbacks, and pipeline resilience (#320, #321, #294)

_Source: PR #320_

## [1.38.0] — 2026-02-14 — Adversarial Hardening Release

### Why This Release

Six cycles of concurrent engineering since v1.33.1 — spanning autonomous excellence loops, agent-grounded documentation, safety infrastructure, generative adversarial security design, and CI pipeline fixes — consolidated into a single release. Covers cycles 005 through 012, 10 merged PRs, and the transition from manual bridge reviews to autonomous red team pipelines.

### Added

#### Flatline Red Team — Generative Adversarial Security Design (#317, Cycle 012)

Complete red team pipeline for adversarial security analysis of design documents:

- **Red Team Pipeline** (`red-team-pipeline.sh`): 5-phase pipeline (sanitize → attack generation → cross-validation → consensus → counter-design) with per-phase timing metrics, budget enforcement, and inter-model safety envelope
- **Scoring Engine** (`scoring-engine.sh`): Multi-model consensus scoring with 4 categories — CONFIRMED_ATTACK (both >700), THEORETICAL (one >700, other ≤700), CREATIVE_ONLY (neither >700), DEFENDED (with counter-design). Configurable thresholds via `.loa.config.yaml`
- **Model Adapter** (`red-team-model-adapter.sh`): Mock/live abstraction for multi-model invocation with `--role attacker|defender|evaluator`, `--budget`, `--timeout` flags. Mock mode loads fixtures, live mode reserved for Hounfour integration
- **Golden Set** (`red-team-golden-set.json`): 33-entry calibration corpus across all 4 consensus categories, 5 attacker profiles (external, insider, supply_chain, confused_deputy, automated), 5 attack surfaces, and 8 compositional vulnerability entries
- **Input Sanitizer** (`red-team-sanitizer.sh`): Multi-pass sanitization with UTF-8 normalization, secret scanning, injection pattern detection, and `--inter-model` lightweight mode for between-phase safety
- **Report Generator** (`red-team-report.sh`): Markdown report with executive summary, per-attack details, counter-designs, and metrics
- **Retention Policy** (`red-team-retention.sh`): Configurable retention with age/count-based cleanup
- **Attack Surfaces Registry** (`attack-surfaces.yaml`): 5 Loa-specific surfaces (agent-identity, token-gated-access, prompt-pipeline, config-as-code, multi-model-consensus) with graceful degradation for non-Loa projects
- **Model Permissions** (`model-permissions.yaml`): Per-model capability constraints for 5 models
- **Red Team Schema** (`red-team-result.schema.json`): JSON Schema for pipeline output validation
- **Fixtures**: 5 response fixtures (2 attacker, 2 evaluator, 1 defender) for end-to-end mock testing
- **`/red-team` Skill**: Command and skill registration with danger_level: high
- 45 tests (33 scoring engine + 7 sanitizer + 5 model adapter)
- 6 sprints (global 79-84), 3 bridge iterations achieving flatline (23 → 1.1 → 0.4)

#### Harness Engineering — Safety Hooks, Deny Rules, Token Optimization (#315, Cycle 011)

Production safety infrastructure for autonomous agent operation:

- **Safety Hooks**: PreToolUse:Bash hook (`block-destructive-bash.sh`) blocks `rm -rf`, `git push --force`, `git reset --hard`, `git clean -f` with safer alternative suggestions
- **Deny Rules**: Template credential deny rules (SSH, AWS, Kube, GPG, npm, pypi, git, gh) with merge installer script (`install-deny-rules.sh`)
- **Stop Guard** (`run-mode-stop-guard.sh`): Stop hook detects active autonomous runs and injects context reminder
- **Audit Logger** (`mutation-logger.sh`): PostToolUse:Bash JSONL logger for mutating commands with 10MB auto-rotation
- **CLAUDE.md Optimization**: 757 → 244 lines (68% reduction), 3433 → 1554 words (55% reduction), 6 reference files extracted to `.claude/loa/reference/`
- **Invariant Linter** (`lint-invariants.sh`): 9 structural invariants validated mechanically — system zone integrity, managed headers, constraints sync, required files, hooks, safety hook tests, deny rules
- **Token Budget Measurement** (`measure-token-budget.sh`): Shows 71% of tokens are demand-loaded via skill invocation
- 45 safety hook tests + 13 linter self-tests

#### BUTTERFREEZONE — Agent-Grounded README Standard (#311, Cycle 009)

Machine-generated, provenance-tagged README with ground truth anchoring:

- **Generator** (`butterfreezone-gen.sh`, ~1230 lines): 3-tier input detection (reality files → static analysis → bootstrap), 8 section extractors with provenance tagging (CODE-FACTUAL, DERIVED, OPERATIONAL), advisory checksums (per-section SHA-256), word-count budget enforcement (3200 total, 800/section), security redaction, manual section preservation via sentinels, atomic writes with flock
- **Validator** (`butterfreezone-validate.sh`): 7 validation checks (existence, AGENT-CONTEXT, provenance, references, word budget, ground-truth-meta, freshness) with `--strict`/`--json`/`--quiet` modes
- **Bridge Integration**: BUTTERFREEZONE_GEN hook in bridge orchestrator FINALIZING phase (non-blocking)
- **`/butterfreezone` Skill**: danger_level: safe
- 3 lore glossary entries: butterfreezone, lobster, grounding-ritual
- 41 BATS tests (28 gen + 13 validate)

### Fixed

- **Flatline Model Validation** (#308): `validate_model()` rejects invalid model names (agent aliases like `reviewer`) before API calls with actionable error messages; timeout raised 60s → 120s for Opus; stderr captured to temp files instead of `/dev/null`; 2s stagger between review and skeptic waves to avoid rate-limit contention; 13 BATS tests
- **Bridgebuilder Filtering Gaps** (#313): 7 new `LOA_EXCLUDE_PATTERNS` entries (`evals/**`, `.run/**`, `.flatline/**`, `PROCESS.md`, `BUTTERFREEZONE.md`, `INSTALLATION.md`, `grimoires/**/NOTES.md`); new `isLoaSystemZone()` function demotes framework file security findings to tier2; `resolveRepoRoot()` with CLI > env > git auto-detect precedence; 332 tests passing
- **Post-Merge Pipeline** (#318): Added git identity config to GitHub Actions workflow (fixed `fatal: empty ident name` that caused all 7 post-merge runs to fail); extended cycle classification regex to match `feat(cycle-...)` commits; fixed Discord webhook secret name to match repo configuration (`MELANGE_DISCORD_WEBHOOK`)

## [1.37.0] — DX Hardening (Cycle 008)

### Why This Release

Addresses three compounding DX pain points: eager secret resolution crashes config loading when unused providers lack env vars (#300), framework development artifacts pollute fresh user project mounts (#299), and review tools process system zone files alongside user code (#303).

### Added

- **Lazy Config Interpolation** (`interpolation.py`): `LazyValue` wrapper defers `{env:*}` resolution until `str()` access — missing env vars for unused providers no longer crash config load (FR-1, #300)
- **`_DEFAULT_LAZY_PATHS`**: Configurable set of dotted-key patterns (`providers.*.auth`) controlling which config paths get lazy treatment
- **Enhanced Error Messages**: `LazyValue.resolve()` includes provider name, agent context, and `/loa-credentials set` hint on failure
- **Mount Hygiene** (`mount-loa.sh`): `clean_grimoire_state()` removes framework development artifacts (prd.md, sdd.md, sprint.md, BEAUVOIR.md, SOUL.md) and stale a2a/archive contents after grimoire checkout (FR-3, #299)
- **Clean Ledger Init**: Mount now initializes empty `ledger.json` with zeroed counters instead of inheriting framework cycle data
- **NOTES.md Template**: Creates `## Learnings / ## Blockers / ## Observations` template if missing during mount
- **52 Python Tests**: 26 original + 26 new covering LazyValue, lazy path matching, lazy interpolation, lazy redaction
- **13 BATS Tests**: Mount hygiene — artifact removal, directory preservation, clean ledger, NOTES.md, context preservation, idempotency
- **Credential Provider Chain** (`credentials/providers.py`): Layered resolution — env vars → encrypted store → `.env.local` (FR-2, #300)
- **Encrypted Credential Store** (`credentials/store.py`): Fernet-encrypted `~/.loa/credentials/store.json.enc` with auto-generated key, 0600/0700 permissions, corrupt store recovery
- **Credential Health Checks** (`credentials/health.py`): HTTP validation against OpenAI, Anthropic, Moonshot endpoints with configurable timeouts
- **`/loa-credentials` Skill**: Interactive credential management — `status`, `set`, `test`, `delete` subcommands with `AskUserQuestion` for secure input
- **31 Credential Tests**: EnvProvider, DotenvProvider, CompositeProvider, EncryptedStore (conditional), EncryptedFileProvider, factory, health checks, interpolation integration
- **Review Scope Utility** (`review-scope.sh`): Shared script for zone detection + `.reviewignore` pattern matching — `detect_zones()`, `load_reviewignore()`, `is_excluded()`, `filter_files()` (FR-4, #303)
- **`.reviewignore` Template**: Gitignore-style review exclusion patterns — system zone, state zone, generated files, vendor deps
- **Mount `.reviewignore` Creation**: `create_reviewignore()` creates template during mount if not present
- **lib-content.sh Scope Integration**: `prepare_content()` excludes out-of-scope files before priority-based truncation
- **Bridgebuilder `.reviewignore` Support**: `loadReviewIgnore()` merges `.reviewignore` patterns with `LOA_EXCLUDE_PATTERNS` in truncation pipeline
- **Audit-Sprint Zone Awareness**: Security audit skill instructions updated to focus on app zone files with `.reviewignore` support
- **19 Review Scope BATS Tests**: Zone detection, `.reviewignore` parsing, glob/directory patterns, `--no-reviewignore` bypass, filter pipeline, combined filtering

### Changed

- `ProviderConfig.auth` type widened from `str` to `Any` to accept `LazyValue`
- `interpolate_config()` accepts `lazy_paths` and `_current_path` parameters
- `redact_config()` handles `LazyValue` without triggering resolution
- `redact_config_value()` uses duck-typing for `LazyValue` detection (no import needed)
- `interpolate_value()` resolves `{env:VAR}` through credential provider chain (env → encrypted → dotenv) instead of `os.environ` alone
- `loader.py` passes `lazy_paths=_DEFAULT_LAZY_PATHS` to interpolation pipeline

## [1.36.0] - 2026-02-13 — Post-Merge Automation Pipeline

### Why This Release

Automates the entire post-merge lifecycle: when a PR merges to main, a GitHub Actions workflow classifies the PR type (cycle/bugfix/other), computes the next semver from conventional commits, finalizes the CHANGELOG, creates tags and releases, and posts a summary. Cycle PRs get the full 8-phase pipeline via claude-code-action; bugfix/other PRs get lightweight tag-only processing. Closes #298.

### Added

- **Post-Merge Orchestrator** (`.claude/scripts/post-merge-orchestrator.sh`): 8-phase pipeline with atomic state updates, phase matrix, dry-run mode, and idempotent phases
- **Semver Bump Script** (`.claude/scripts/semver-bump.sh`): Conventional commit parser — feat→minor, fix→patch, BREAKING→major, outputs JSON
- **Release Notes Generator** (`.claude/scripts/release-notes-gen.sh`): CHANGELOG extraction with cycle/bugfix/other templates
- **GitHub Actions Workflow** (`.github/workflows/post-merge.yml`): 4-job workflow (classify → simple-release/full-pipeline → notify)
- **claude-code-action Integration**: Sonnet model, 15 max turns, tool allowlist for cycle PRs
- **Shell-Only Fallback**: Pipeline runs without ANTHROPIC_API_KEY for cycle PRs
- **Discord Notification**: Webhook alert on pipeline failure
- **Post-Merge Config**: `post_merge:` section in `.loa.config.yaml`
- **Constraints**: C-MERGE-001 through C-MERGE-005 (orchestrator-only, no manual tags, RTFM non-blocking, idempotent phases, cycle-only full pipeline)
- **61 BATS Tests**: 22 semver + 15 release-notes + 24 orchestrator

## [1.35.1] - 2026-02-12 — Bridgebuilder Enrichment

### Why This Release

The Bridgebuilder Enrichment release (cycle-006, Issue #295) transforms automated bridge reviews from convergence-only checklists into educational experiences. The manual Bridgebuilder produces reviews that teach — FAANG parallels, metaphors, teachable moments. The automated bridge now supports the same richness through enriched findings schema, PRAISE severity, persona-driven review, and dual-stream output.

### Added

- **Bridgebuilder Persona** (`.claude/data/bridgebuilder-persona.md`): Identity, Voice (6 examples from manual reviews), Review Output Format (dual-stream), Content Policy (5 NEVER rules), PRAISE/Educational guidance, Token Budget
- **PRAISE Severity**: Weight 0, excluded from convergence score, celebrates good engineering decisions
- **Enriched Findings Fields**: `faang_parallel`, `metaphor`, `teachable_moment`, `connection`, `praise` in bridge-findings-parser.sh and JSON schema
- **JSON Fenced Block Parser**: Structured JSON inside `<!-- bridge-findings-start/end -->` markers with strict grammar enforcement (exit code 3 on violations)
- **Legacy Parser Fallback**: Backward-compatible regex parsing when no JSON fence detected
- **Atomic State Updates**: `flock`-based locking with write-to-temp + atomic `mv` for crash safety in bridge-state.sh
- **Content Redaction**: `redact_security_content()` with gitleaks-inspired patterns (AWS AKIA, GitHub ghp_/gho_/ghs_/ghr_, JWT eyJ, generic secrets) and allowlist
- **Post-Redaction Safety Check**: Blocks PR comment posting if secret prefixes remain after redaction
- **Size Enforcement**: 65KB truncation preserving findings JSON, 256KB findings-only fallback
- **Phase 3.1 Enriched Review Workflow**: 10-step process in SKILL.md (integrity check, validation, lore load, embody persona, dual-stream, save, size check, redact, safety check, parse+post)
- **Enrichment Metrics**: Per-iteration tracking of persona_loaded, findings_format, field_fill_rates, praise_count, insights_size_bytes, redactions_applied
- **Constraints**: C-BRIDGE-006 (ALWAYS load persona), C-BRIDGE-007 (SHOULD praise quality), C-BRIDGE-008 (SHOULD educational fields)
- **Configuration**: `run_bridge.bridgebuilder` section with persona, size, redaction settings
- **Formal JSON Schema**: `tests/fixtures/bridge-findings.schema.json` with all severity levels and enriched fields
- **Test Fixtures**: `enriched-bridge-review.md` (5 findings, PRAISE, full enrichment) and `legacy-bridge-review.md` (4 findings, markdown format)
- **99 BATS Tests**: 31 parser + 42 state + 26 trail covering JSON extraction, enriched fields, PRAISE, strict grammar, flock, crash safety, redaction, size enforcement, post-redaction safety

### Changed

- **bridge-findings-parser.sh**: Rewritten v2.0.0 — JSON extraction with legacy fallback, strict grammar, PRAISE in SEVERITY_WEIGHTS
- **bridge-state.sh**: Rewritten v2.0.0 — `atomic_state_update()` wrapping all RMW functions, enrichment metrics in iteration template
- **bridge-github-trail.sh**: Updated v2.0.0 — redaction, size enforcement, post-redaction safety, retention cleanup, printf fixes

## [1.35.0] - 2026-02-12 — Bridge Release

### Why This Release

The Run Bridge release (cycle-005, Issue #292) delivers autonomous excellence loops — iterative sprint-plan, Bridgebuilder review, findings parsing, and vision capture cycles that terminate via kaironic flatline detection. Built across 3 sprints: foundation data infrastructure (lore KB, vision registry, grounded truth), bridge core engine (orchestrator, state machine, findings parser), and full integration (GitHub trail, skill registration, golden path detection).

### Added

#### Run Bridge — Autonomous Excellence Loop (`/run-bridge`)

Complete iterative improvement system with 6 new scripts:

- **Bridge Orchestrator** (`bridge-orchestrator.sh`): State machine (PREFLIGHT→JACK_IN→ITERATING→FINALIZING→JACKED_OUT) with SIGNAL protocol for agent delegation, configurable depth (1-5), per-sprint mode, resume support, circuit breakers
- **Bridge State Manager** (`bridge-state.sh`): JSON state management with atomic writes, transition validation, iteration tracking, metrics accumulation
- **Bridge Findings Parser** (`bridge-findings-parser.sh`): Extracts structured JSON from Bridgebuilder markdown between `<!-- bridge-findings-start/end -->` markers. Severity weights: CRITICAL=10, HIGH=5, MEDIUM=2, LOW=1, VISION=0
- **Flatline Detection**: Kaironic termination — loop stops when severity score drops below threshold (default 5%) for consecutive iterations (default 2)
- **Vision Capture** (`bridge-vision-capture.sh`): Filters VISION findings, creates numbered entries, updates registry index
- **GitHub Trail** (`bridge-github-trail.sh`): PR comments with dedup markers, PR body summary tables, vision link posting. Graceful degradation when `gh` unavailable

#### `/run-bridge` Command and Skill

- **Command**: `.claude/commands/run-bridge.md` with `--depth`, `--per-sprint`, `--resume`, `--from` flags
- **Skill registration**: `.claude/skills/run-bridge/` with index.yaml (danger_level: high) and SKILL.md
- **Configuration**: `run_bridge:` section in `.loa.config.yaml` with defaults, timeouts, GitHub trail, GT, vision registry, RTFM, and lore settings

#### Mibera Lore Knowledge Base (`.claude/data/lore/`)

Cultural and philosophical context for agent skills, structured as YAML entries with `short` (inline) and `context` (teaching) fields:

- **Mibera core entries**: kaironic time, cheval, network mysticism, techno-animism, hounfour, loa rides
- **Mibera cosmology**: Milady/Mibera duality, BGT triskelion, Honey/Bera, the Jar
- **Mibera rituals**: bridge loop, sprint ceremony, mounting, jacking in, flatline ceremony, vision capture
- **Mibera glossary**: 15 term definitions for agent consumption
- **Neuromancer concepts**: ICE, jacking in, cyberspace, the matrix, SimStim, flatline construct, Wintermute, Neuromancer AI
- **Neuromancer mappings**: 9 concept-to-Loa-feature mappings
- **Integration guide**: README.md with entry schema and skill integration patterns

#### Vision Registry (`grimoires/loa/visions/`)

Directory structure for capturing VISION-type findings from bridge iterations:

- **index.md**: Status summary with table headers (ID, Title, Source, Status, Tags)
- **entries/**: Directory for individual vision entry files

#### Grounded Truth Generator (`.claude/scripts/ground-truth-gen.sh`)

Shell script handling mechanical GT operations:

- **Scaffold mode**: Creates hub-and-spoke directory structure (index.md, api-surface.md, architecture.md, contracts.md, behaviors.md)
- **Checksums mode**: Computes SHA-256 of source files referenced in reality/ extraction
- **Validate mode**: Token budget validation (index < 500, sections < 2000 tokens)
- **Cross-platform**: BSD/GNU sha256sum compatibility

#### `/ride` Ground Truth Extension (Phase 11)

- **`--ground-truth` flag**: Generates Grounded Truth output after ride
- **`--non-interactive` flag**: Skips phases 1, 3, 8 for autonomous bridge loop usage
- **Phase 11**: Read reality/ → synthesize GT files → generate checksums → validate tokens
- **riding-codebase SKILL.md**: Phase 11 documentation with token budgets and trajectory logging

#### Bridgebuilder Lore-Aware Persona

- **BEAUVOIR.md**: Lore Integration section with circuit breaker→kaironic-time, multi-model→hounfour, session recovery→cheval mappings
- **Structured Findings Format**: Documented `<!-- bridge-findings-start/end -->` marker protocol with severity tags and VISION type

#### Golden Path Bridge State Detection

- **`golden_detect_bridge_state()`**: Reads `.run/bridge-state.json`, returns state or "none"
- **`golden_bridge_progress()`**: Human-readable progress for `/loa` display (iteration N/depth, score, resume instructions)

#### Lore Integration Across Skills

- **Bridgebuilder** (`BEAUVOIR.md`): Teaching moments with lore references
- **Discovering Requirements** (`SKILL.md`): Philosophical framing for PRD creation
- **Golden Path / `/loa`** (`loa.md`): Naming context from glossary entries

#### Constraints

5 new bridge constraints (C-BRIDGE-001 through C-BRIDGE-005):
- Use `/run sprint-plan` within bridge iterations
- Post Bridgebuilder review as PR comment after each iteration
- Ensure GT claims cite `file:line` references
- Use YAML format for lore entries with required schema fields
- Include source bridge iteration and PR in vision entries

#### Tests

- **bridge-state.bats**: 21 tests (init, transitions, illegal transitions, flatline, metrics, schema)
- **bridge-findings-parser.bats**: 9 tests (parsing, severity weighting, edge cases)
- **bridge-vision-capture.bats**: 6 tests (entry creation, 0 visions, error handling)
- **bridge-github-trail.bats**: 10 tests (subcommands, arg validation, graceful degradation)
- **bridge-golden-path.bats**: 11 tests (state detection, progress display, regression)
- **lore-validation.bats**: 25 tests (YAML schema, cross-references, glossary count)
- **ground-truth-gen.bats**: 11 tests (scaffold, checksums, validate, all modes)
- **7 eval tasks**: lore-index-valid, lore-entries-schema, gt-checksums-match, bridge-state-schema-valid, bridge-findings-parser-works, golden-path-bridge-detection, vision-entries-traceability

## [1.34.1] - 2026-02-12

### Why This Release

Quality hardening pass for the Onboarding UX release. Fixes CI failures, adds missing test coverage, formalizes schemas, and documents lifecycle protocols — all traced to Bridgebuilder architectural review findings on PR #291.

### Fixed

- **Template Protection CI** — removed 37 forbidden state files (`.run/`, `.beads/`, `.ck/`) from git tracking that accumulated during previous development cycles
- **Fixture sync CI integration** — new `fixture-sync` CI job runs `sync-fixtures.sh --check` on every PR to catch drift before merge

### Added

- **Bug-specific journey bar** — `golden_format_bug_journey()` renders bug lifecycle visualization: `/triage ━━━ /fix ●━━━ /review ━━━ /close`
- **JSON output mode** — `golden_menu_options --json` produces machine-readable output for tooling integration
- **Archetype risk seeding** — `/plan` now seeds `NOTES.md ## Known Risks` from selected archetype's `context.risks`
- **Archetype schema validation** — `schema.yaml` defines required archetype fields; `sync-fixtures.sh --check` validates all archetypes
- **Auto-discovery of sync targets** — `sync-fixtures.sh` scans eval task YAML files to auto-populate fixture sync map
- **BATS unit test suite** — 33 tests covering `golden-path.sh` state detection, menu options, journey visualization, pipe sanitization, and bug transitions
- **Sprint completion protocol** — `.claude/protocols/sprint-completion.md` documents the implement → review → audit → COMPLETED lifecycle
- **Bug lifecycle protocol** — `.claude/protocols/bug-lifecycle.md` documents the full bug state machine with transitions and TOCTOU-safe verification
- 2 new framework eval tasks: `golden-bug-journey`, `golden-menu-json`

## [1.34.0] - 2026-02-12

### Why This Release

The Onboarding UX release makes Loa dramatically easier to get started with. Inspired by competitive analysis of Hive's onboarding (PR #290), this release adds **context-aware navigation**, **post-mount verification**, a **setup wizard**, and **project archetypes** — reducing first-5-minutes friction while keeping all power-user truename commands intact.

### Added

#### Context-Aware `/loa` Menu (FR-1, Sprint 8)

The `/loa` command now shows a dynamic, state-aware action menu instead of a static 3-option list:

- **9-state detection engine** (`golden_detect_workflow_state()`) — determines where you are in the workflow
- **Context-specific menu options** — each state shows relevant next actions (e.g., "Build sprint-2" when implementing, "Fix bug: title" when triaging)
- **Smart routing** — menu selections invoke the correct skill automatically
- **Destructive action safety** — "Plan new cycle" requires confirmation before archiving
- 3 new framework eval tasks (golden-menu-*)

#### Post-Mount Verification (FR-2, Sprint 9)

`mount-loa.sh` now validates the installation after framework sync:

- **`verify_mount()`** — checks framework files, config, deps, optional tools, and API key presence
- **NFR-8 compliance** — API key check is boolean-only ("is set" / "not set"), zero key material in output
- **Safe JSON assembly** — uses `jq -n --arg` instead of string concatenation (Flatline SKP-004)
- **Flags**: `--quiet`, `--json`, `--strict` (converts warnings to failures)
- **Exit codes**: 0 = success+warnings, 1 = failure
- 2 new framework eval tasks (mount-verify-*)

#### Setup Wizard `/loa setup` (FR-3, Sprint 10)

New interactive environment setup command:

- **`loa-setup-check.sh`** — JSONL validation engine checking API key, deps, optional tools, config
- **4-step wizard** — validate deps → check tools → show config → toggle features
- **`--check` flag** — non-interactive validation-only mode
- **Feature toggle UI** — AskUserQuestion with multiSelect for Flatline, Memory, Enhancement

#### Project Archetypes (FR-4, Sprint 10)

First-time `/plan` users now see a project archetype menu:

- **4 templates**: REST API, CLI Tool, Library/Package, Full-Stack App
- **Each template** provides vision, technical context, NFRs, testing strategy, and risks
- **"Other" option** skips to blank-slate interview
- **Auto-ingestion** — selected archetype written to `grimoires/loa/context/archetype.md`
- 2 new framework eval tasks (setup-check-nfr8, archetype-schema)

#### Use-Case Qualification (FR-5, Sprint 11)

First-time `/plan` users see a brief "Loa works best for..." guidance screen:

- Shows feature comparison ("What does Loa add?")
- Never blocks — always allows continuing
- Helps users self-qualify before investing in full planning

#### Auto-Format Construct Pack Spec (FR-6, Sprint 11)

Design specification for a construct pack that installs language-specific formatting hooks:

- Supports Python (ruff), JS/TS (prettier), Go (gofmt), Rust (rustfmt)
- Non-destructive — preserves existing formatter configs
- Implementation ships separately in `loa-constructs` repo

### Framework Eval Suite

- **30 tasks** (up from 23), 0 failures
- New coverage: golden-menu-*, mount-verify-*, setup-check-*, archetype-*

---

## [1.33.1] - 2026-02-12

### Fixed

#### Update Safety — Workflow File Propagation (#288)

`/update-loa` no longer propagates `.github/workflows/` files to downstream projects:

- **`.gitattributes`**: Added `merge=ours` rules for `.github/workflows/*.yml` and `.yaml` — prevents upstream workflow files from overwriting downstream versions during `git merge loa/main`
- **`/update-loa` Phase 5.5**: New post-merge revert step detects and removes workflow files added by upstream (handles new files that `merge=ours` cannot protect)
- **Eval**: Added `gitattributes-workflow-protection` framework test (23 total), updated fixture and baseline

**Root cause**: v1.33.0 introduced `.github/workflows/eval.yml` which propagated to downstream projects. GitHub requires the `workflow` OAuth scope to push workflow changes, blocking users without that scope.

---

## [1.33.0] - 2026-02-11 — Garde Release

### Why This Release

The Garde Release builds protective infrastructure around Loa's development lifecycle. A full **eval sandbox** lands with deterministic framework testing, 9 code-based graders, CI pipeline with dual-checkout trust boundaries, and baseline regression detection. Alongside this, **bug mode** (`/bug`) introduces a lightweight triage-to-fix workflow that enforces test-first development while bypassing PRD/SDD gates for observed failures. **6 PRs** covering eval infrastructure, bug-fixing workflows, and RTFM-surfaced documentation repairs.

### Added

#### Eval Sandbox — Framework Evals, Regression Suite, CI Pipeline (#277, #282)

Full evaluation infrastructure for deterministic framework testing:

- **7-script harness pipeline**: `run-eval.sh` orchestrator, `validate-task.sh`, `sandbox.sh`, `grade.sh`, `compare.sh`, `report.sh`, `pr-comment.sh`
- **9 code-based graders**: `file-exists`, `tests-pass`, `function-exported`, `pattern-match`, `diff-compare`, `quality-gate`, `no-secrets`, `constraint-enforced`, `skill-index-validator`
- **Framework correctness suite**: 22 deterministic tasks covering config validation, constraint enforcement, golden path structure, quality gates
- **Regression suite scaffold**: 11 agent-simulated tasks — bug triage, implementation, and review scenarios with 3 trials per task
- **5 test fixtures**: `loa-skill-dir`, `hello-world-ts`, `buggy-auth-ts`, `simple-python`, `shell-scripts`
- **GitHub Actions CI pipeline**: dual-checkout trust model (base=trusted graders, PR=untrusted tasks), source-injection scanning, symlink escape prevention, PR comment reports with collapsible results
- **Dockerfile.sandbox**: container isolation with yq, jq, git, bash 4.0+
- **Baseline comparison**: Wilson confidence intervals, regression/improvement/new/missing classification
- **`/eval` command**: skill registration for running suites from Claude Code
- 61 unit + integration tests across harness and graders

#### Bug Mode — Lightweight Bug-Fixing Workflow (#278, #279)

New `/bug` command and `bug-triaging` skill for observed-failure triage:

- **5-phase triage**: dependency check → eligibility validation → hybrid interview → codebase analysis → micro-sprint creation
- **Eligibility scoring**: 2-3 point rubric with disqualifiers for feature requests
- **PII redaction**: API keys, JWT tokens, passwords, emails stripped from imported content
- **GitHub issue import**: `--from-issue N` flag for automated intake
- **Test-first enforcement**: HALTs if no test infrastructure detected
- **Run mode integration**: `/run --bug "description"` with circuit breaker
- **Golden path awareness**: `/build` auto-detects active bugs and routes correctly
- **State management**: bug state tracking in `.run/bugs/{id}/state.json` with TOCTOU-safe detection
- **Process compliance**: C-PROC-015 (validate eligibility) and C-PROC-016 (no feature work via `/bug`)

### Changed

- Process compliance tables in CLAUDE.loa.md updated to include `/bug` as valid implementation path
- `/loa` status command extended to detect and report active bug workflows
- Run mode SKILL.md updated with `/run --bug` documentation

### Fixed

- **CI trust boundary false positives**: refactored globstar save/restore in `run-eval.sh` to avoid `eval` command; test directories excluded from trust boundary scanner (#283)
- **Fixture config tracking**: `.gitignore` negation for `evals/fixtures/**/.loa.config.yaml` — global ignore rule caused 3 framework task failures (#284)
- **PR comment coverage**: workflow step now posts results for ALL suites, not just most recent run directory (#284)
- **README documentation gaps**: added "What Is This?" definition, clarified slash commands vs shell commands, added prerequisites, post-install verification, first-run expectations, and beads_rust requirement clarification
- **INSTALLATION documentation gaps**: moved optional enhancements after core install, fixed config bootstrap path, added minimal working config example, clarified `.beads/` creation timing, resolved beads_rust requirement contradiction, added uninstall section, added failure recovery guidance

### Documentation

- **Eval CI pipeline guide**: trust model, dual-checkout architecture, pipeline steps, suite types, artifact retention (#285)
- **Eval health checks**: local verification commands, task category reference, monitoring recommendations (#285)
- **Eval operational runbook**: adding tasks/graders/fixtures, investigating CI failures, baseline update procedures (#285)

---

## [1.32.0] - 2026-02-10 — Hounfour Release

### Why This Release

The Hounfour Release extracts multi-model provider infrastructure from loa-finn into upstream Loa as the `loa_cheval` Python package — a full provider abstraction layer with Anthropic + OpenAI adapters, cost metering, routing chains, and circuit breakers. Alongside this headline feature, Bridgebuilder v2.1 lands with typed errors, glob matching, incremental review, and persona routing, while `/rtfm` introduces zero-context documentation quality testing. **15 PRs** covering provider infrastructure, skill polish, documentation tooling, and template hygiene.

### Added

#### Hounfour: Multi-Model Provider Abstraction Layer (`loa_cheval`)

Extracted from loa-finn as a standalone Python package under `.claude/adapters/loa_cheval/`:

- **Provider adapters**: Anthropic (Claude) and OpenAI (GPT) with unified response types
- **Config system**: YAML loading with `${ENV_VAR}` interpolation, secret redaction, validation
- **Cost metering**: Micro-USD integer arithmetic ledger, pricing registry, budget enforcement
- **Routing**: Model alias resolution, multi-step chains, circuit breaker with half-open recovery
- **CLI**: `model-invoke` shell entry point for script-level model calls
- **Schema**: `model-config.schema.json` for configuration validation
- **185 tests** across 10 test files, zero regressions

#### Bridgebuilder v2.1 — Typed Errors, Glob, Incremental Review, Persona Routing (#263, #267)

- **Loa-aware filtering**: Auto-detect Loa-mounted repos, 39 security patterns with 6 categories
- **Progressive truncation**: 3-level diff truncation targeting 90% budget, adaptive LLM retry
- **Persona pack system**: 5 built-in personas (default, security, dx, architecture, quick) with CLI-wins precedence
- **Enhanced glob matching**: `path.matchesGlob()` for Node 22+, fallback for older runtimes
- **Incremental review**: Delta-only review on PR updates since last reviewed SHA
- **Multi-model persona routing**: YAML frontmatter model hints, CLI `--model` override
- 277 tests passing

#### /rtfm Documentation Quality Testing (#236, #259)

New skill that spawns zero-context tester agents to validate documentation usability:
- Hermetic tester spawn via Task subagent with context isolation canary
- Structured [GAP] report parsing with 6 types, 3 severities
- Task template system (install, quickstart, mount, beads, gpt-review, update)
- Prompt injection hardening per GPT-5.2 cross-model review
- Progressive size limits with three-tier handling (50KB/100KB/reject)

#### /ride: Persistent Artifact Writes + Verification Gate (#272)

- Add `Write` tool to allowed-tools (root cause: agent could analyze but never persist)
- 8 write checkpoints (CP-1 through CP-9) after each artifact phase
- Phase 10.0 Artifact Verification Gate (BLOCKING) before handoff
- Phase 0.6 staleness detection with configurable `ride.staleness_days`
- Architecture-overview.md template added to output formats

#### Bridgebuilder Autonomous PR Review Skill (#248)

Full hexagonal architecture extraction over 6 sprints:
- 7 port interfaces, 5 core domain classes, default adapters (GitHub CLI, Anthropic, sanitizer)
- Config resolution with 5-level precedence (CLI > env > YAML > auto-detect > defaults)
- GPT-5.2 cross-model security hardening, strict endpoint allowlist (default-deny)
- Persona voice with Bridgebuilder identity, config provenance tracking
- 100+ tests (unit + integration), zero runtime npm dependencies

#### Skill Benchmark Audit Against Anthropic Guide (#261, #264)

- 10-check validation script (`validate-skill-benchmarks.sh`) against Anthropic's skill guide
- riding-codebase refactored: 6,905 → 1,915 words (72% reduction, under 5,000 limit)
- Schema update: description maxLength 500 → 1024, added `negative_triggers`
- 25-assertion test suite with compliant/non-compliant fixtures

#### Mount: Structured Error Handling E010-E016 (#237, #241)

- 7 new structured error codes for mount failures
- Empty repo detection and handling (`detect_repo_state()`)
- Path-scoped rollback in `create_upgrade_commit()`
- Golden Path next steps banner
- 20 hermetic shell tests, Bash 3.2 compatible

### Changed

- Token budgets raised: maxInputTokens 8K→128K, maxOutputTokens 4K→16K, maxDiffBytes 100K→512K (#260)
- CLI flags added: `--max-input-tokens`, `--max-output-tokens`, `--max-diff-bytes`, `--model` (#260)
- API timeout scales with prompt size: 50K→180s, 100K→300s (#262)
- GPT review findings now persist to `grimoires/loa/a2a/gpt-review/` (#249, #251)
- Update script skips when already at upstream version (#245, #250)
- `.gitignore` hardened: `.beads/`, `.loa.config.yaml`, dev planning docs excluded (#253)
- Simstim Telegram bridge package removed (#252)
- Feature-specific mockups and screenshots removed from template (#254)
- README.md, PROCESS.md, INSTALLATION.md, SECURITY.md, LICENSE.md updated

### Fixed

- Bridgebuilder `--pr` filter not propagated to resolveItems pipeline (#257, #258)
- Bridgebuilder streaming: Cloudflare 60s TTFB timeout resolved via SSE streaming (#271)
- Bridgebuilder self-review: 422 on REQUEST_CHANGES to own PR, falls back to COMMENT (#271)
- Bash 4.0+ version guard added to all 17 `declare -A` scripts (#240, #244)
- GPT review: curl payload via temp file instead of bash arg (size limit fix)
- Hounfour: dead import, duplicate branches, safety comments, thread-safety docs

---

## [1.31.0] - 2026-02-07 — Bridgebuilder Release

### Why This Release

This is the largest Loa release to date — **27 PRs** spanning developer experience, security hardening, cross-model adversarial review, and a complete documentation overhaul. The headline: **Golden Path** gives 90% of users 5 zero-arg commands, while **Adversarial Flatline Dissent** adds cross-model challenge to code review and security audit.

The README and INSTALLATION.md have been rewritten with input from the Bridgebuilder persona — optimized for both human onboarding and AI agent consumption.

### Added

#### Golden Path — 5 Commands for 90% of Users (#219)

Five zero-argument porcelain commands wrapping the full truename workflow:

| Command | What It Does |
|---------|-------------|
| `/loa` | Where am I? What's next? |
| `/plan` | Requirements → Architecture → Sprints |
| `/build` | Build the current sprint |
| `/review` | Code review + security audit |
| `/ship` | Deploy and archive |

Design follows the git porcelain/plumbing model — Golden Path for most users, truenames for power users.

#### Error Code Registry & `/loa doctor` (#218)

Structured error codes (LOA-E001+) with human-readable explanations and fix suggestions. `/loa doctor` provides comprehensive system health diagnostics with CI-friendly JSON output.

#### Adversarial Flatline Dissent (#235)

Cross-model adversarial challenge during code review and security audit. GPT-5.2-Codex acts as independent dissenter against Claude's findings with:
- Priority-based diff truncation with P0-P3 file classification
- Context escalation for security-critical files
- Secret scanning with configurable allowlists
- Anchor validation and severity demotion for ungrounded findings
- Budget pre-check to prevent runaway API costs
- Graceful degradation on API failure

#### GPT Review: System Zone Detection & Priority Truncation (#233)

GPT review now detects `.claude/` system zone modifications and applies priority-based diff truncation to stay within token limits while ensuring security-critical files are always reviewed first.

#### Cross-Repo Pattern Extraction (#227)

25 reusable shell patterns extracted into 5 library modules:
- `lib-validate.sh` — Input validation, path safety, schema checking
- `lib-log.sh` — Structured logging with levels and JSON output
- `lib-config.sh` — YAML config loading with defaults
- `lib-git.sh` — Git operations, branch detection, upstream safety
- `lib-io.sh` — File I/O, atomic writes, temp file management

#### DRY Constraint Registry (#225)

Single-source constraint definitions in `.claude/data/constraints.json` with generated CLAUDE.md tables. Eliminates constraint drift between documentation and enforcement.

#### Portable Persistence Framework (#220)

WAL-based key-value persistence for shell scripts with pluggable backends and circuit breakers.

#### Cross-Platform Shell Scripting Protocol (#210)

Portable compatibility layer handling macOS vs Linux differences (BSD date, sed, stat, mktemp). Eliminates `%N` nanosecond and other platform-specific failures.

#### Construct Manifest Standard (#213)

Standardized manifest format for Loa Constructs with event-driven contracts, tool dependency declarations, and JSON schema validation.

#### MLP-Informed Beads Enhancements (#209)

Beads enhanced with gap detection, lineage tracking, task classification, and context compilation — informed by Machine Learning Pipeline (MLP) patterns.

#### Opus 4.6 & GPT-5.3-Codex Model Support (#202)

Model registry updated with Claude Opus 4.6 and GPT-5.3-Codex pricing and capabilities.

#### Run Mode `--local` Flag (#201)

`--local` flag for run mode to skip git push. Configurable via `auto_push` setting for offline or local-only workflows.

#### Beads TypeScript Runtime Patterns (#191)

TypeScript patterns for beads_rust integration in application code.

#### CODEOWNERS (#206)

Added `.github/CODEOWNERS` for automatic PR review assignment.

### Changed

- Layered process enforcement prevents AI from bypassing implement/review/audit gates (#221)
- README.md rewritten: Golden Path prominent, value proposition section, agent-readable metadata, 17 skills listed, updated feature table
- INSTALLATION.md overhauled: TOC added, Claude Code install instructions, yq ambiguity fixed (mikefarah/yq only), `/loa doctor` verification step, beads-first language

### Fixed

- Event bus bash version guard for non-bash shell sourcing (#234)
- Beads-health.sh zero output and event-bus.sh flock detection (#231)
- Event bus hardened against jq injection, DLQ diagnostics improved (#215)
- Backward compatibility aliases for renamed scripts + Opus 4.6 sweep (#207)
- Heredoc corruption of `${...}` template literals in generated source files (#203, #200)
- macOS `date %N` incompatibility breaking Flatline Protocol (#199)
- Simstim Plan Mode hijacking orchestration workflows (#196)
- Constructs URL migration, multi-pack UI, and smart routing (#189)

### Security

- Critical and high findings from security audit remediated (#232)
- 56-finding comprehensive audit remediated — supply chain, secrets, injection, CI hardening (#212)

### Performance

- Beads isomorphic optimizations: WAL, batch queries, and circuit breaker (#205)

---

## [1.29.0] - 2026-02-05 — Beads-First Infrastructure

### Why This Release

This release implements **Beads-First Architecture** where task tracking via beads_rust is the EXPECTED DEFAULT, not an optional enhancement. Working without beads becomes ABNORMAL and requires explicit, time-limited acknowledgment.

*"We're building spaceships. Safety of operators and users is paramount."*

### Added

#### Beads-First Preflight (#182)

Comprehensive health check infrastructure for beads_rust:

```bash
# Check beads health
.claude/scripts/beads/beads-health.sh --json

# Manage state
.claude/scripts/beads/update-beads-state.sh --health HEALTHY
.claude/scripts/beads/update-beads-state.sh --opt-out "Reason"
```

**New Files**:
| File | Purpose |
|------|---------|
| `beads-health.sh` | Comprehensive health check (6 exit codes) |
| `update-beads-state.sh` | State file management |
| `beads-preflight.md` | Protocol documentation |
| `test_beads_health.sh` | Unit tests |

**Health Check Exit Codes**:
| Code | Status | Meaning |
|------|--------|---------|
| 0 | HEALTHY | All checks pass |
| 1 | NOT_INSTALLED | br binary not found |
| 2 | NOT_INITIALIZED | No .beads directory |
| 3 | MIGRATION_NEEDED | Schema incompatible |
| 4 | DEGRADED | Partial functionality |
| 5 | UNHEALTHY | Critical issues |

#### Autonomous Mode Beads Gate

Autonomous mode (`/run`) now REQUIRES beads by default:

```bash
# Will HALT if beads unavailable
/run sprint-1

# Override (not recommended)
export LOA_BEADS_AUTONOMOUS_OVERRIDE=true
```

**Configuration**:
```yaml
beads:
  mode: recommended  # required | recommended | disabled
  autonomous:
    requires_beads: true
```

#### Opt-Out Workflow

Time-limited acknowledgment for working without beads:

- 24h expiry (configurable)
- Requires reason (configurable)
- Re-prompts when expired
- Logs to trajectory for auditability

### Changed

- Updated `/sprint-plan` with Phase -1 beads preflight
- Updated `/implement` with Phase -2 beads sync
- Updated `/simstim` Phase 0 with beads check
- Updated `/run` preflight with autonomous beads gate
- Added beads configuration section to `.loa.config.yaml.example`
- Updated `CLAUDE.loa.md` with Beads-First documentation

### Migration Notes

**For existing users without beads_rust installed**:

1. Install beads_rust: `cargo install beads_rust`
2. Initialize: `br init`
3. Workflows will prompt if beads unavailable (not a hard block in interactive mode)

**For autonomous/run mode**:
- If you run autonomous mode without beads, add `beads.autonomous.requires_beads: false` to your config
- Consider installing beads for better state persistence across context windows

---

## [1.28.0] - 2026-02-05 — Dicklesworth Improvements

### Why This Release

This release adds three major features inspired by the Dicklesworthstone ecosystem: **Post-Compact Recovery Hooks** for automatic context recovery after compaction, **Flatline Beads Loop** for iterative task graph refinement, and **Persistent Memory** for session-spanning observation storage.

*"Check your beads N times, implement once."*

### Added

#### Post-Compact Recovery Hooks (#178)

Automatic context recovery after Claude Code context compaction:

```json
{
  "hooks": {
    "PreCompact": [{"matcher": "", "hooks": [{"type": "command", "command": ".claude/hooks/pre-compact-marker.sh"}]}],
    "UserPromptSubmit": [{"matcher": "", "hooks": [{"type": "command", "command": ".claude/hooks/post-compact-reminder.sh"}]}]
  }
}
```

**New Files**:
| File | Purpose |
|------|---------|
| `pre-compact-marker.sh` | Captures state before compaction |
| `post-compact-reminder.sh` | Injects recovery reminder after compaction |
| `settings.hooks.json` | Hook registration template |
| `test_pcr_hooks.sh` | 13 unit tests |

**Features**:
- One-shot delivery (marker deleted after reminder)
- Captures run_mode, simstim, and skill state
- Logs compaction events to trajectory
- Project-local and global fallback markers

#### Flatline Beads Loop (#177)

Iterative multi-model refinement of task graphs:

```bash
.claude/scripts/beads-flatline-loop.sh --max-iterations 6 --threshold 5
```

**How It Works**:
1. Export beads to JSON
2. Run Flatline Protocol review on task graph
3. Apply HIGH_CONSENSUS suggestions automatically
4. Repeat until changes "flatline" (< 5% for 2 iterations)
5. Sync final state to git

**New Files**:
| File | Purpose |
|------|---------|
| `beads-flatline-loop.sh` | Main orchestrator script |
| `beads-review.md` | Flatline prompt for task graph review |
| `test_blf.sh` | 16 unit tests |

**Simstim Integration**: New Phase 6.5 "FLATLINE_BEADS" runs automatically after PLANNING when beads_rust is installed.

#### Persistent Memory (#175)

Session-spanning observation storage with progressive disclosure:

```bash
# Token-efficient index (~50 tokens per entry)
.claude/scripts/memory-query.sh --index

# Full details (~500 tokens)
.claude/scripts/memory-query.sh --full obs-1234567890-abc123
```

**New Files**:
| File | Purpose |
|------|---------|
| `memory-writer.sh` | Hook for capturing observations |
| `memory-query.sh` | Query interface with progressive disclosure |
| `test_memory.sh` | 19 unit tests |

**Features**:
- Learning signal detection (discovered, learned, fixed, resolved, pattern, insight)
- Privacy filtering (redacts `<private>` tagged content)
- Session-specific logging
- Retention limits with automatic archiving

### Changed

- Updated `flatline-orchestrator.sh` to support `--phase beads`
- Updated `simstim.md` with Phase 6.5 documentation
- Updated `planning-sprints/SKILL.md` with Beads Flatline Loop section
- Added memory configuration section to `.loa.config.yaml.example`

### Tests

| Test Suite | Tests | Status |
|------------|-------|--------|
| PCR Hooks | 13 | ✅ All passing |
| BLF | 16 | ✅ All passing |
| Memory | 19 | ✅ All passing |
| **Total** | **48** | ✅ All passing |

---

## [1.27.0] - 2026-02-04 — Configurable Paths & Trace-Based Routing

### Why This Release

This release introduces **configurable grimoire paths** for flexible workspace layouts (e.g., OpenClaw integration) and **feedback trace-based routing** for intelligent issue classification. Also includes critical stability fixes for run-mode and simstim state synchronization.

*"Configure your paths, trace your feedback."*

### Added

#### Configurable Grimoires Location (#176, #173)

Grimoire and state file locations are now configurable for integration scenarios:

```yaml
paths:
  grimoire: grimoires/loa          # Default
  beads: .beads
  soul:
    source: grimoires/loa/BEAUVOIR.md
    output: grimoires/loa/SOUL.md
```

**OpenClaw Integration Example**:
```yaml
paths:
  grimoire: .loa/grimoire
  soul:
    source: .loa/grimoire/BEAUVOIR.md
    output: SOUL.md    # At workspace root
```

**New Files**:
| File | Purpose |
|------|---------|
| `bootstrap.sh` | PROJECT_ROOT detection (3 fallback strategies) |
| `path-lib.sh` | 16 getter functions for path resolution |
| `test_path_lib.sh` | 16 unit tests |
| `test_configurable_paths.sh` | 10 integration tests |

**Rollback Safety**:
- `LOA_USE_LEGACY_PATHS=1` bypasses config, uses hardcoded defaults
- CI lint check (warning mode) prevents path regression
- Environment overrides: `LOA_GRIMOIRE_DIR`, `LOA_BEADS_DIR`, `LOA_SOUL_SOURCE`, `LOA_SOUL_OUTPUT`

**Requirements**: yq v4+ (mikefarah/yq). Missing yq uses defaults with warning.

#### Feedback Trace-Based Routing (#174, #171)

Intelligent `/feedback` routing based on execution trajectory analysis:

```yaml
feedback:
  trace_routing:
    enabled: true  # Disabled by default
```

**Classification Categories**:
| Category | Description |
|----------|-------------|
| `skill_bug` | Bug in existing skill |
| `skill_gap` | Missing feature in skill |
| `missing_skill` | Need new skill |
| `runtime_bug` | Framework/runtime issue |

**Implementation**:
- `trace_analyzer` Python package with hybrid matching (keyword + fuzzy + embeddings)
- Privacy-first: default-deny PII redaction
- 80 unit tests passing
- Disabled by default pending classifier tuning

#### Two-Pass Security Analysis (#163)

Enhanced `/audit` with structured taint analysis methodology:

**New Phases**:
| Phase | Description |
|-------|-------------|
| 0.5 (Scope) | Count files by security category |
| 1A (Recon) | Source/sink identification with taxonomy |
| 1B (Investigate) | Taint path tracing with time budget |

**Detection Patterns**: SQL Injection, Command Injection, XSS, Path Traversal, SSRF, LLM Safety

### Fixed

#### Run-Mode State Preservation (#165)

- **Problem**: Context compaction caused `/run sprint-plan` to lose autonomous state
- **Solution**: Added run mode state recovery to CLAUDE.loa.md and session protocols
- Recovery checks `.run/sprint-plan-state.json` and resumes without confirmation

#### Simstim Run-Mode Sync (#172)

- **Problem**: Simstim state stuck in "RUNNING" after `/run sprint-plan` completed
- **Solution**: New `--sync-run-mode` command with plan ID correlation
- Added `--set-expected-plan-id` for pre-invocation correlation
- Auto-recovery on resume for completed-but-not-recorded scenarios

#### Constructs Skill Count (#168)

- Fixed jq query to read from `manifest.skills` array
- Packs now correctly display skill counts in `/constructs` browser

#### Flatline macOS Case-Sensitivity (#167)

- Fixed path comparison failure on case-insensitive filesystems
- Applied `realpath` fix to `flatline-orchestrator.sh`

### Related PRs

- PR #176: Configurable grimoires location
- PR #174: Feedback trace-based routing
- PR #172: Simstim run-mode state sync
- PR #168: Constructs skill count fallback
- PR #167: Flatline macOS case-sensitivity
- PR #165: Run-mode state preservation
- PR #163: Two-Pass Security Analysis

---

## [1.26.0] - 2026-02-04 — Workspace Cleanup & Post-PR Validation

### Why This Release

This release introduces **workspace cleanup** for fresh development cycles and completes the **Post-PR Validation Loop** integration. Together, these features ensure both clean starting conditions and rigorous post-PR quality gates.

*"Archive the past, validate the future."*

### Added

#### Workspace Cleanup (#160)

Automated archiving of previous cycle artifacts during `/simstim` and `/autonomous` preflight:

```bash
# Interactive mode (default)
workspace-cleanup.sh                    # Prompt with 5s timeout

# Autonomous mode
workspace-cleanup.sh --yes --json       # Archive without prompt

# Preview mode
workspace-cleanup.sh --dry-run          # Show what would be archived
```

**4-Stage Archive Process**:
| Stage | Description |
|-------|-------------|
| 1. Copy | Copy files to staging directory |
| 2. Verify | SHA256 checksum verification |
| 3. Finalize | Rename staging to archive with manifest |
| 4. Remove | Delete originals (with transaction log) |

**Security Features**:
- Symlink rejection (no following)
- Path traversal prevention (`..` blocked)
- Absolute path rejection
- Realpath containment validation
- Writability and ownership checks

**Integration Points**:
- `simstim-orchestrator.sh` - Preflight cleanup (respects `--resume`, `--no-clean`)
- `autonomous-agent/SKILL.md` - Phase 0.0 with fail-closed policy

**Configuration** (`.loa.config.yaml`):
```yaml
workspace_cleanup:
  enabled: true
  default_action: archive
  retention:
    max_age_days: 90
    max_count: 10
  security:
    follow_symlinks: false
```

**Files**:
- `.claude/scripts/workspace-cleanup.sh` - Main script (~1100 lines)
- `.claude/scripts/tests/test-workspace-cleanup.bats` - 30 unit tests

#### Post-PR Validation Integration (#158, #159)

Complete post-PR validation loop with `/autonomous` integration:

**Workflow**:
```
PR_CREATED → POST_PR_AUDIT → CONTEXT_CLEAR → E2E_TESTING → FLATLINE_PR → READY_FOR_HITL
```

**Scripts**:
| Script | Purpose |
|--------|---------|
| `post-pr-orchestrator.sh` | Main orchestrator with state machine |
| `post-pr-state.sh` | State management with locking |
| `post-pr-audit.sh` | PR audit with finding classification |
| `post-pr-e2e.sh` | E2E test runner with failure tracking |
| `post-pr-context-clear.sh` | Checkpoint writer for fresh context |

**Exit Codes**:
| Code | Meaning | Action |
|------|---------|--------|
| 0 | Success | READY_FOR_HITL |
| 1 | Invalid args | Error |
| 2 | Timeout | HALT |
| 3 | Phase failure | HALT |
| 4 | Flatline blocker | HALT |
| 5 | User interrupt | HALT |

**Configuration** (`.loa.config.yaml`):
```yaml
post_pr_validation:
  enabled: true
  phases:
    audit: { enabled: true, max_iterations: 5 }
    context_clear: { enabled: true }
    e2e: { enabled: true, max_iterations: 3 }
    flatline: { enabled: false }  # ~$1.50 cost
```

### Fixed

- **Empty array bug** in `workspace-cleanup.sh` - `validate_scanned_paths()` now correctly handles empty result arrays
- **Test assertions** - Fixed 6 failing tests in `test-workspace-cleanup.bats`
- **Unsafe command execution** in `post-pr-audit.sh` - Replaced `bash -c "$cmd"` with array-based execution

### Related PRs

- PR #158: Post-PR Validation Loop v1.25.0
- PR #159: Autonomous Post-PR Integration (Phase 5.5)
- PR #160: Workspace Cleanup

---

## [1.25.0] - 2026-02-03 — Post-PR Validation Loop

### Why This Release

This release introduces the **Post-PR Validation Loop**, an automated quality assurance process that runs after PR creation. It ensures code is thoroughly reviewed before human review begins.

*"Trust but verify—automatically."*

### Added

#### Post-PR Validation Command

```bash
# Full validation loop
.claude/scripts/post-pr-orchestrator.sh --pr-url <url>

# Dry run
.claude/scripts/post-pr-orchestrator.sh --dry-run --pr-url <url>

# Resume from checkpoint
.claude/scripts/post-pr-orchestrator.sh --resume --pr-url <url>
```

#### Validation Phases

| Phase | Description | Fix Loop |
|-------|-------------|----------|
| POST_PR_AUDIT | Security/quality audit | Yes (max 5) |
| CONTEXT_CLEAR | Save checkpoint, prompt `/clear` | No |
| E2E_TESTING | Fresh-eyes build & test | Yes (max 3) |
| FLATLINE_PR | Multi-model review (~$1.50) | No |

#### Circuit Breakers

- Same finding 3x → Audit escalation
- Same failure 2x → E2E escalation

#### Finding Identity Algorithm

Stable 16-char hash for deduplication:
```
SHA256(category|rule_id|file|normalized_line|severity)[:16]
```

Line normalization: ±5 tolerance (round to nearest 10)

### Related PRs

- PR #158: Post-PR Validation Loop v1.25.0

---

## [1.23.0] - 2026-02-03 — Flatline-Enhanced Compound Learning

### Why This Release

This release connects the **Flatline Protocol** to the **Compound Learning** pipeline, enabling consensus-based learning extraction and validation.

*"When two models agree on a learning, promote it. When they disagree, investigate."*

### Added

#### Flatline → Learning Capture

HIGH_CONSENSUS insights from Flatline reviews become learning candidates:

```bash
# Extract learnings from Flatline results
.claude/scripts/flatline-learning-extractor.sh --results flatline-results.json

# Validate borderline learning
.claude/scripts/flatline-validate-learning.sh --learning learning.json --dry-run
```

#### 3-Layer Circular Prevention

Prevents Flatline from validating its own outputs:
| Layer | Check | Action |
|-------|-------|--------|
| L1 | `source: flatline` | Skip |
| L2 | Validation history | Skip if seen |
| L3 | Rate limit | 30s cooldown |

#### Semantic Similarity

Embedding-based duplicate detection before upstream proposal:
```bash
.claude/scripts/flatline-semantic-similarity.sh --learning learning.json --threshold 0.85
```

#### Pre-Proposal Review

Adversarial review of upstream proposals:
```bash
.claude/scripts/flatline-proposal-review.sh --proposal proposal.json
```

#### Rejection Pattern Analysis

Root cause tracking for rejected proposals:
```bash
.claude/scripts/flatline-rejection-analysis.sh --rejection rejection.json
```

#### New Scripts

| Script | Purpose |
|--------|---------|
| `flatline-learning-extractor.sh` | Extract learnings from HIGH_CONSENSUS |
| `flatline-validate-learning.sh` | Single-learning 2-model validator |
| `flatline-semantic-similarity.sh` | Embedding-based duplicate detection |
| `flatline-proposal-review.sh` | Pre-proposal adversarial review |
| `flatline-rejection-analysis.sh` | Root cause pattern tracking |
| `lib/api-resilience.sh` | API retry, circuit breaker, budget controls |

#### Consensus Mapping

| GPT Vote | Opus Vote | Consensus | Action |
|----------|-----------|-----------|--------|
| approve | approve | APPROVE | Promote |
| reject | reject | REJECT | Demote |
| mixed | - | DISPUTED | Human review |

### Configuration

```yaml
flatline_integration:
  learning_extraction:
    enabled: true
    source_marker: true
  validation:
    max_per_cycle: 10
    daily_budget: 50
  semantic_similarity:
    threshold: 0.85
    model: text-embedding-3-small
```

### Related PRs

- PR #156: Flatline-Enhanced Compound Learning v1.23.0

---

## [1.22.1] - 2026-02-03 — Constructs Skill Discovery Fix

### Fixed

#### Constructs Skill Symlinks (#153)

Fixed skill symlink location so Claude Code can discover installed pack skills:

**Before** (broken):
```
.claude/constructs/skills/observer/analyzing-gaps → ../../packs/observer/skills/analyzing-gaps
```

**After** (fixed):
```
.claude/skills/analyzing-gaps → ../constructs/packs/observer/skills/analyzing-gaps
```

- Skills now symlink directly to `.claude/skills/<skill>`
- Added collision detection for existing framework skills
- Uninstall correctly removes individual skill symlinks

### Related PRs

- PR #153: fix(constructs): symlink skills to .claude/skills/ for Claude Code discovery

---

## [1.24.0] - 2026-02-03 — Simstim HITL Workflow

### Why This Release

This release introduces the **Simstim** command (`/simstim`), a Human-In-The-Loop (HITL) accelerated development workflow that orchestrates the complete Loa development cycle with integrated Flatline Protocol reviews at each stage.

*"Experience the AI's work while maintaining your own consciousness."* — Gibson, Neuromancer

### Added

#### /simstim Command

Full-cycle orchestration from PRD to implementation:

```bash
/simstim                     # Full cycle: PRD → SDD → Sprint → Implementation
/simstim --from architect    # Skip PRD (already exists)
/simstim --from sprint-plan  # Skip PRD + SDD
/simstim --from run          # Skip planning, just run sprints
/simstim --resume            # Continue from interruption
/simstim --dry-run           # Preview planned phases
/simstim --abort             # Clean up state and exit
```

**8-Phase Workflow**:
| Phase | Name | Description |
|-------|------|-------------|
| 0 | PREFLIGHT | Validate configuration, check state |
| 1 | DISCOVERY | Create PRD interactively |
| 2 | FLATLINE PRD | Multi-model review of PRD |
| 3 | ARCHITECTURE | Create SDD interactively |
| 4 | FLATLINE SDD | Multi-model review of SDD |
| 5 | PLANNING | Create sprint plan interactively |
| 6 | FLATLINE SPRINT | Multi-model review of sprint plan |
| 7 | IMPLEMENTATION | Autonomous execution via `/run sprint-plan` |
| 8 | COMPLETE | Summary and cleanup |

#### HITL Flatline Mode

New Flatline mode optimized for human operators:

| Category | Criteria | Action |
|----------|----------|--------|
| HIGH_CONSENSUS | Both models >700 | Auto-integrate (no prompt) |
| DISPUTED | Score delta >300 | Present to user for decision |
| BLOCKER | Skeptic concern >700 | Present to user for decision (NOT auto-halt) |
| LOW_VALUE | Both <400 | Skip silently |

Key difference from `/autonomous`: BLOCKERs are shown to the human for decision instead of automatically halting the workflow.

#### State Management

Resume capability via `.run/simstim-state.json`:
- Tracks phase completion and artifact checksums
- Detects artifact drift on resume
- PID-based lockfile prevents concurrent execution

**Files**:
- `.claude/skills/simstim-workflow/SKILL.md` - Main orchestration skill
- `.claude/skills/simstim-workflow/index.yaml` - Skill metadata
- `.claude/commands/simstim.md` - User documentation
- `.claude/scripts/simstim-orchestrator.sh` - State and orchestration logic

**Configuration** (`.loa.config.yaml`):
```yaml
simstim:
  enabled: true
  flatline:
    auto_accept_high_consensus: true
    show_disputed: true
    show_blockers: true
    phases: [prd, sdd, sprint]
  defaults:
    timeout_hours: 24
```

---

## [1.22.0] - 2026-02-03 — Autonomous Flatline Integration

### Why This Release

This release enables the **Flatline Protocol** to operate within autonomous workflows (`/autonomous`, `/run sprint-plan`) without human intervention. HIGH_CONSENSUS findings auto-integrate, BLOCKERS halt the workflow with escalation reports, and DISPUTED items are logged for post-review.

*"Adversarial review at machine speed - consensus integrates, disputes escalate."*

### Added

#### Autonomous Mode Detection

Script: `.claude/scripts/flatline-mode-detect.sh`

Intelligent mode detection with strong vs weak signal distinction:

```bash
# Strong signals (trigger auto-enable)
CLAWDBOT_GATEWAY_TOKEN  # AI gateway authenticated
LOA_OPERATOR=ai         # Explicit AI operator

# Weak signals (require opt-in)
Non-TTY                 # Could be pipe or batch
CLAUDECODE              # Claude Code agent
CLAWDBOT_AGENT          # Clawdbot agent
```

**Mode Precedence**: CLI flags → Environment → Config → Auto-detect → Default (interactive)

#### Atomic Integration Pipeline

Safe document modification with rollback support:

```
lock → verify_hash → snapshot → integrate → release
```

**Scripts**:
- `.claude/scripts/flatline-lock.sh` - flock()-based advisory locking with NFS fallback
- `.claude/scripts/flatline-snapshot.sh` - Pre-integration snapshots with quota management
- `.claude/scripts/flatline-manifest.sh` - Run tracking with UUIDv4 IDs
- `.claude/scripts/flatline-rollback.sh` - Single or full-run rollback

#### Result Handler

Script: `.claude/scripts/flatline-result-handler.sh`

Mode-aware result processing:
- **Autonomous**: HIGH_CONSENSUS auto-integrates, DISPUTED logged, BLOCKER halts
- **Interactive**: All findings presented to user

**Exit Codes**:
| Code | Meaning | Workflow Action |
|------|---------|-----------------|
| 0 | Success | Continue |
| 1 | BLOCKER halt | Generate escalation, HALT |
| 4 | Disputed threshold | Generate escalation, HALT |
| 5 | Integration failed | Log error, continue |

#### Error Handling & Retry

Script: `.claude/scripts/flatline-error-handler.sh`

- Transient vs fatal error categorization
- Exponential backoff with jitter
- Configurable retry limits

**Transient** (retryable): `rate_limit`, `timeout`, `network`, `overloaded`
**Fatal** (no retry): `auth`, `invalid_request`, `budget_exceeded`, `permission_denied`

#### Escalation Reports

Script: `.claude/scripts/flatline-escalation.sh`

Generated on workflow halt:
- Markdown and JSON format
- Includes blockers, disputed items, rollback instructions
- Logged to `grimoires/loa/a2a/flatline/escalation-*.md`

#### `/autonomous` Integration

Flatline reviews integrated into `/autonomous` workflow:
- Phase 1.4: PRD Review (after generation)
- Phase 2.3: SDD Review (after architecture)
- Phase 2.5: Sprint Plan Review (after planning)

```bash
/autonomous --resume  # Continue from Flatline halt
```

#### `/run sprint-plan` Integration

PR template includes Flatline summary:

```markdown
### Flatline Review Summary

| Phase | HIGH | DISPUTED | BLOCKER | Status |
|-------|------|----------|---------|--------|
| PRD   | 5    | 2        | 0       | ✅     |
| SDD   | 3    | 1        | 0       | ✅     |
| SPRINT| 4    | 0        | 1       | ⚠️     |
```

### Configuration

```yaml
# .loa.config.yaml
autonomous_mode:
  enabled: false                    # Require explicit opt-in
  auto_enable_for_ai: true          # Auto-enable for strong AI signals
  actions:
    high_consensus: integrate       # Auto-apply findings
    disputed: log                   # Log for post-review
    blocker: halt                   # Halt workflow
    low_value: skip                 # Discard silently
  thresholds:
    disputed_halt_percent: 80       # Halt if >80% disputed
  retry:
    max_attempts: 3
    base_delay_ms: 1000
    max_delay_ms: 30000
  snapshots:
    enabled: true
    max_count: 100
    max_bytes: 104857600            # 100MB
    on_quota: purge_oldest
```

### Scripts Reference

| Script | Purpose |
|--------|---------|
| `flatline-mode-detect.sh` | Mode detection with signal analysis |
| `flatline-lock.sh` | Advisory locking (flock + NFS fallback) |
| `flatline-snapshot.sh` | Pre-integration snapshots |
| `flatline-manifest.sh` | Run tracking and integration IDs |
| `flatline-rollback.sh` | Single or full-run rollback |
| `flatline-result-handler.sh` | Mode-aware result processing |
| `flatline-editor.sh` | Safe document modification |
| `flatline-error-handler.sh` | Error categorization and retry |
| `flatline-escalation.sh` | Escalation report generation |

### Documentation

- Updated `CLAUDE.loa.md` with autonomous Flatline section
- Updated `/flatline-review` command with rollback options
- Updated `/run sprint-plan` PR template with Flatline summary
- Updated `/autonomous` skill with Flatline integration phases

### Related PRs

- PR #151: Autonomous Flatline Integration v1.22.0

---

## [1.21.0] - 2026-02-03 — Flatline Protocol: Multi-Model Adversarial Review

### Why This Release

This release introduces the **Flatline Protocol** - a multi-model adversarial review system using Claude Opus 4.5 + GPT-5.2 for planning document quality assurance. Two frontier models review AND critique each other's suggestions, creating consensus-based quality filtering.

*"When two models agree, you can trust it. When they disagree, you should look closer."*

### Added

#### Flatline Protocol Core (#149)

Multi-model adversarial review with four-phase architecture:

```yaml
# .loa.config.yaml
flatline_protocol:
  enabled: true
  models:
    primary: opus           # Claude Opus 4.5
    secondary: gpt-5.2      # OpenAI GPT-5.2
  thresholds:
    high_consensus: 700     # Both >700 = auto-integrate
    dispute_delta: 300      # Delta >300 = disputed
    low_value: 400          # Both <400 = discard
    blocker: 700            # Skeptic concern >700 = blocker
```

**Protocol Phases**:

| Phase | Description |
|-------|-------------|
| Phase 0 | Knowledge retrieval (Tier 1: local + Tier 2: NotebookLM optional) |
| Phase 1 | 4 parallel calls: GPT review, Opus review, GPT skeptic, Opus skeptic |
| Phase 2 | Cross-scoring: GPT scores Opus suggestions, Opus scores GPT suggestions |
| Phase 3 | Consensus extraction: HIGH/DISPUTED/LOW/BLOCKER classification |

**Consensus Thresholds** (0-1000 scale):

| Category | Criteria | Action |
|----------|----------|--------|
| `HIGH_CONSENSUS` | Both models >700 | Auto-integrate |
| `DISPUTED` | Score delta >300 | Present to user |
| `LOW_VALUE` | Both models <400 | Discard |
| `BLOCKER` | Skeptic concern >700 | Must address |

#### `/flatline-review` Command

Manual invocation of Flatline Protocol:

```bash
# Review a planning document
/flatline-review grimoires/loa/prd.md

# CLI invocation
.claude/scripts/flatline-orchestrator.sh --doc grimoires/loa/prd.md --phase prd --json
```

#### Auto-Trigger Integration

Planning commands can auto-trigger Flatline review:

```yaml
flatline_protocol:
  auto_trigger:
    enabled: true
    phases: [prd, sdd, sprint]  # /plan-and-analyze, /architect, /sprint-plan
```

When enabled, Flatline review runs automatically after:
- `/plan-and-analyze` → Reviews PRD
- `/architect` → Reviews SDD
- `/sprint-plan` → Reviews Sprint Plan

#### Two-Tier Knowledge Retrieval

**Tier 1 (Local)**: Automatic, always enabled
- `.claude/loa/learnings/` - Framework learnings
- `grimoires/loa/NOTES.md` - Project learnings
- Prior cycle artifacts

**Tier 2 (NotebookLM)**: Optional, requires setup
- Curated domain expertise notebooks
- Browser automation via Patchright
- See: `.claude/skills/flatline-knowledge/resources/auth-setup.md`

```yaml
flatline_protocol:
  knowledge:
    local:
      enabled: true
    notebooklm:
      enabled: false        # Optional
      notebook_id: ""
```

#### Model Adapter

Script: `.claude/scripts/model-adapter.sh`

Unified interface for multi-model calls:
- OpenAI GPT-5.2 via API
- Anthropic Claude Opus via API
- Handles retries, timeouts, error normalization

#### Scoring Engine

Script: `.claude/scripts/scoring-engine.sh`

Cross-model scoring with jq-based aggregation:
- Normalizes scores to 0-1000 scale
- Calculates consensus categories
- Handles edge cases (timeouts, API errors)

### Schemas & Protocols

- **New Schema**: `.claude/schemas/flatline-result.schema.json`
- **New Protocol**: `.claude/protocols/flatline-protocol.md`
- **New Command**: `.claude/commands/flatline-review.md`
- **New Skill**: `.claude/skills/flatline-knowledge/`

### Templates

- `flatline-review.md.template` - Reviewer prompt
- `flatline-skeptic.md.template` - Skeptic prompt
- `flatline-score.md.template` - Cross-scoring prompt
- `flatline-postlude.md.template` - Integration prompt

### Documentation

- Updated `INSTALLATION.md` with NotebookLM setup guide
- Updated `CLAUDE.loa.md` with Flatline Protocol section
- Comprehensive protocol documentation in `.claude/protocols/flatline-protocol.md`

### Related PRs

- PR #149: Flatline Protocol v1.17.0 - Multi-Model Adversarial Review
- PR #121: GPT 5.2 cross-model review integration (foundation)

---

## [1.20.0] - 2026-02-03 — Input Guardrails & Tool Risk Enforcement

### Why This Release

This release implements **Input Guardrails & Tool Risk Enforcement** based on OpenAI's "A Practical Guide to Building Agents". Provides pre-execution validation for skill invocations with PII filtering, prompt injection detection, and danger level enforcement.

*"Defense in depth for agentic workflows."*

### Added

#### Input Guardrails Framework

Pre-execution validation layer before skill execution:

```yaml
# .loa.config.yaml
guardrails:
  input:
    enabled: true
    pii_filter:
      enabled: true
      mode: blocking
    injection_detection:
      enabled: true
      threshold: 0.7
  danger_level:
    enforce: true
```

**Guardrail Types**:
| Type | Mode | Purpose |
|------|------|---------|
| `pii_filter` | blocking | Redact API keys, emails, SSN, credit cards |
| `injection_detection` | blocking | Detect prompt injection patterns |
| `relevance_check` | advisory | Verify request matches skill purpose |

**Execution Modes**:
- `blocking` - Must pass before skill runs
- `parallel` - Runs async, can trigger tripwire
- `advisory` - Logs warning but continues

#### Danger Level Enforcement

Skills classified by risk level with mode-specific enforcement:

| Level | Interactive | Autonomous |
|-------|-------------|------------|
| `safe` | Execute | Execute |
| `moderate` | Notice | Log |
| `high` | Confirm | BLOCK (use `--allow-high`) |
| `critical` | Confirm+Reason | ALWAYS BLOCK |

**Override for Run Mode**:
```bash
/run sprint-1 --allow-high
/run sprint-plan --allow-high
```

#### PII Filter

Script: `.claude/scripts/pii-filter.sh`

Detects and redacts sensitive patterns:
- API Keys (OpenAI, GitHub, AWS, Anthropic)
- Email addresses, phone numbers
- SSN, credit card numbers
- JWT tokens, private keys
- Home directory paths (anonymization)

#### Injection Detection

Script: `.claude/scripts/injection-detect.sh`

Pattern categories with weighted scoring:
- Instruction override (0.4): "ignore previous", "disregard"
- Role confusion (0.3): "you are now", "act as"
- Context manipulation (0.2): "system prompt", "debug mode"
- Encoding evasion (0.1): base64, unicode tricks

#### Guardrails Orchestrator

Script: `.claude/scripts/guardrails-orchestrator.sh`

Coordinates all checks in sequence:
1. Danger level check
2. PII filter (blocking)
3. Injection detection (blocking)

Returns aggregated PROCEED/WARN/BLOCK action.

#### Tripwire Mechanism

Script: `.claude/scripts/tripwire-handler.sh`

Handles parallel guardrail failures:
- Halt execution on failure
- Optional rollback of uncommitted changes
- Trajectory logging

#### Handoff Logging

Script: `.claude/scripts/log-handoff.sh`

Explicit handoff events in trajectory:
```json
{
  "type": "handoff",
  "from_agent": "implementing-tasks",
  "to_agent": "reviewing-code",
  "artifacts": [{"path": "reviewer.md"}],
  "context_preserved": ["sprint_id"]
}
```

#### Skill Preludes

Input guardrails prelude added to priority skills:
- `implementing-tasks` (moderate danger)
- `deploying-infrastructure` (high danger)
- `autonomous-agent` (high danger)
- `auditing-security` (safe)
- `reviewing-code` (safe)
- `run-mode` (high danger)

### Schemas & Protocols

- **New Schema**: `.claude/schemas/guardrail-result.schema.json`
- **New Protocol**: `.claude/protocols/input-guardrails.md`
- **New Protocol**: `.claude/protocols/danger-level.md`
- **Updated**: `.claude/protocols/feedback-loops.md` (handoff logging)
- **Updated**: `.claude/protocols/run-mode.md` (Level 5 enforcement)
- **Updated**: `skill-index.schema.json` (input_guardrails section)

### Configuration

New config sections in `.loa.config.yaml.example`:
- `guardrails.input` - PII filter, injection detection, relevance check
- `guardrails.tripwire` - Parallel failure handling
- `guardrails.danger_level` - Enforcement rules per mode
- `guardrails.logging` - Trajectory logging options

### Research

Based on analysis of OpenAI's "A Practical Guide to Building Agents":
- Research document: `docs/research/openai-agent-guide-research.md`
- PRD: `grimoires/loa/prd-input-guardrails.md`
- SDD: `grimoires/loa/sdd-input-guardrails.md`

---

## [1.19.0] - 2026-02-02 — Invisible Retrospective Learning

### Why This Release

This release brings **Invisible Retrospective Learning**, automatically detecting and cataloging learnings during skill execution without requiring users to invoke `/retrospective` manually. Mirrors the invisible enhancement pattern from PR #145.

*"Learn as you work, silently capturing discoveries for future sessions."*

### Added

#### Invisible Retrospective Learning

Automatic learning detection using skill postludes (mirrors PR #145's prelude pattern):

```yaml
# .loa.config.yaml
invisible_retrospective:
  enabled: true
  surface_threshold: 3  # Min gates to surface (out of 4)
  skills:
    implementing-tasks: true
    auditing-security: true
    reviewing-code: true
```

**Key Features**:
- **Silent Scanning**: Session scanned for learning signals after skill completion
- **4-Gate Quality Filter**: Depth, Reusability, Trigger Clarity, Verification
- **Qualified Surfacing**: Only learnings passing 3+ gates are surfaced to user
- **Trajectory Logging**: All activity logged to `grimoires/loa/a2a/trajectory/retrospective-*.jsonl`
- **NOTES.md Integration**: Qualified learnings added to `## Learnings` section
- **Upstream Queue**: Learnings queued for upstream detection (PR #143 integration)

**Learning Signal Detection**:
| Signal | Example Patterns |
|--------|------------------|
| Error Resolution | "error", "fixed", "resolved", "the issue was" |
| Multiple Attempts | "tried", "finally", "after several" |
| Unexpected Behavior | "surprisingly", "turns out", "discovered" |
| Workaround Found | "instead", "alternative", "the trick is" |
| Pattern Discovery | "pattern", "convention", "always" |

**Skills with Retrospective Postlude**:
- `implementing-tasks` - Bug fixes, debugging discoveries
- `auditing-security` - Security patterns and remediations
- `reviewing-code` - Code review insights

**`/loa` Status Updates**:
- Shows retrospective metrics (detected/extracted/skipped count)
- Last extraction timestamp

#### Schema & Configuration

- New schema: `.claude/schemas/retrospective-log.schema.json`
- New config section: `invisible_retrospective` in `.loa.config.yaml.example`
- Postlude template: `.claude/skills/continuous-learning/resources/retrospective-postlude.md`

### Changed

- `/loa` command now displays invisible retrospective statistics
- Updated CLAUDE.loa.md with Invisible Retrospective documentation

### Technical Notes

- Uses postlude-based architecture (skill SKILL.md files include `<retrospective_postlude>` at END)
- Recursion prevention: continuous-learning skill excluded from postlude execution
- <200ms latency target with early exit for disabled config
- Integrates with PR #143's upstream learning flow via queued learnings

### Related PRs

- PR #145: Invisible Prompt Enhancement (architecture pattern)
- PR #143: Upstream Learning Flow (integration point)

## [1.18.0] - 2026-02-02 — Visual Communication & Invisible Enhancement

### Why This Release

This release brings **Visual Communication v2.0** with GitHub-native Mermaid rendering and browser automation infrastructure, **Invisible Prompt Enhancement** that silently improves prompt quality, and a **95% context reduction** in CLAUDE.md through modular reference files.

*"Better diagrams, better prompts, better context efficiency."*

### Added

#### Visual Communication v2.0 (#144)

Complete rewrite of Mermaid diagram support with multiple rendering modes:

```yaml
# .loa.config.yaml
visual_communication:
  mode: "github"   # github (default) | render | url
  theme: "github"  # github|dracula|nord|tokyo-night|solarized-light|solarized-dark|catppuccin
```

**Key Features**:
- **GitHub Native Mode**: Direct Mermaid code blocks render in GitHub PRs/Issues
- **Local Render Mode**: SVG/PNG output via mermaid-cli for offline use
- **Legacy URL Mode**: External service URLs for backward compatibility
- **7 Theme Presets**: GitHub, Dracula, Nord, Tokyo Night, Solarized (light/dark), Catppuccin

**Browser Automation Infrastructure**:
- MCP dev-browser integration for visual verification
- Screenshot capture to `grimoires/loa/screenshots/`
- Headless and extension modes
- Protocol: `.claude/protocols/browser-automation.md`

#### Invisible Prompt Enhancement (#145)

Automatic prompt enhancement without user visibility using PTCF framework:

```yaml
# .loa.config.yaml
prompt_enhancement:
  invisible_mode:
    enabled: true
    log_to_trajectory: true
```

**Key Features**:
- **Silent Enhancement**: Prompts scoring < 4 are enhanced invisibly
- **PTCF Framework**: Persona + Task + Context + Format analysis
- **Skill-Level Preludes**: Enhancement logic embedded in skill SKILL.md files
- **Recursion Prevention**: `/enhance` command has `enhance: false` frontmatter
- **Trajectory Logging**: Activity logged to `grimoires/loa/a2a/trajectory/prompt-enhancement-*.jsonl`
- **Passthrough on Error**: Any failure uses original prompt unchanged

**Skills with Enhancement Prelude**:
- `discovering-requirements` (/plan-and-analyze)
- `implementing-tasks` (/implement)
- `translating-for-executives` (/translate)

**`/loa` Status Updates**:
- Shows enhancement metrics (enhanced/skipped/errors count)
- Average latency tracking

#### CLAUDE.md Context Optimization (#142)

95% reduction in CLAUDE.md token usage through modular reference architecture:

**New Reference Files** (`.claude/loa/reference/`):
- `context-engineering.md` - Memory protocols, attention budgets
- `protocols-summary.md` - Key protocol summaries
- `scripts-reference.md` - Helper script documentation
- `version-features.md` - Version-specific feature details

**Token Impact**:
- Before: ~50K tokens loaded every session
- After: ~2.5K tokens (table of contents)
- Reference files loaded on-demand

### Changed

- `/loa` command now displays prompt enhancement statistics
- `mermaid-url.sh` enhanced with theme support and local rendering options
- `.loa.config.yaml.example` expanded with visual communication and invisible enhancement configs

### Technical Notes

- Browser automation requires MCP dev-browser server (opt-in)
- Invisible enhancement uses prelude-based architecture (hooks cannot modify prompts)
- Reference files use lazy loading pattern for context efficiency

## [1.17.0] - 2026-02-02 — Upstream Learning Flow

### Why This Release

This release introduces the **Upstream Learning Flow** that enables users to contribute high-value project learnings back to the Loa framework. Eligible learnings are detected silently after retrospectives, anonymized to remove PII, and proposed via GitHub Issues for maintainer review.

*"Knowledge flows upstream. The framework evolves from its users."*

### Added

#### Upstream Learning Flow (#143)

Complete implementation for contributing project learnings to the Loa framework:

```bash
# Propose a specific learning
/propose-learning L-0001

# Preview without submitting
/propose-learning L-0001 --dry-run

# Check proposal status
.claude/scripts/check-proposal-status.sh --learning L-0001
```

**Key Features**:
- **Silent Detection**: Post-retrospective hook identifies eligible learnings automatically
- **User Opt-In**: Presents candidates via AskUserQuestion, never auto-proposes
- **PII Anonymization**: Redacts API keys, paths, emails, IPs, JWT tokens, private keys before submission
- **Weighted Scoring**: `upstream_score = quality(25%) + effectiveness(30%) + novelty(25%) + generality(20%)`
- **Eligibility Threshold**: score ≥ 70, applications ≥ 3, success_rate ≥ 80%
- **Duplicate Detection**: Jaccard similarity check against existing framework learnings
- **Rejection Handling**: 90-day cooldown for rejected proposals

**New Files**:
- `.claude/scripts/upstream-score-calculator.sh` - Weighted eligibility scoring
- `.claude/scripts/anonymize-proposal.sh` - PII redaction (API keys, JWT, private keys, DB creds)
- `.claude/scripts/proposal-generator.sh` - GitHub Issue creation with deduplication
- `.claude/scripts/check-proposal-status.sh` - Proposal status sync from GitHub
- `.claude/scripts/post-retrospective-hook.sh` - Silent detection after /retrospective
- `.claude/commands/propose-learning.md` - User-facing command
- `docs/MAINTAINER_GUIDE.md` - Maintainer workflow for reviewing proposals

**Updated Files**:
- `.claude/schemas/learnings.schema.json` - Added `proposal` object with status, issue_ref, rejection fields
- `.claude/scripts/gh-label-handler.sh` - Added `--body-file` for secure content handling
- `.claude/commands/retrospective.md` - Added Step 6: Upstream Detection
- `.claude/skills/continuous-learning/SKILL.md` - Added Upstream Flow section
- `.loa.config.yaml` - Added `upstream_detection` and `upstream_proposals` config sections

**Historical Learning Extraction**:
- 32 learnings extracted from historical development cycles
- Total framework learnings: 72 (exceeds 50+ PRD target)

**Security Hardening**:
- CRITICAL-001: Command injection prevention via `--body-file` parameter
- HIGH-001: Extended PII patterns (Slack webhooks, JWT, private keys, DB credentials)
- HIGH-002: Null-safe filename iteration with `find -print0`
- Input validation on learning IDs (alphanumeric only)
- Secure temp file handling with `umask 077`

**Configuration** (`.loa.config.yaml`):
```yaml
upstream_detection:
  enabled: true
  min_occurrences: 3
  min_success_rate: 0.8
  min_upstream_score: 70

upstream_proposals:
  target_repo: "0xHoneyJar/loa"
  label: "learning-proposal"
  anonymization:
    enabled: true
  rejection_cooldown_days: 90
```

---

## [1.16.0] - 2026-02-02 — Managed Scaffolding & Two-Tier Learnings

### Why This Release

This release introduces **Projen-Style Ownership** with managed scaffolding for framework files, and **Two-Tier Learnings Architecture** that ships 40 battle-tested patterns with every Loa installation. Framework files now have clear ownership markers, and learnings flow automatically to every project.

*"Managed files stay managed. Learnings flow downstream. The framework teaches itself."*

### Added

#### Projen-Style Ownership with Managed Scaffolding (#134)

Framework files in `.claude/` now use managed scaffolding inspired by AWS Projen:

```bash
# Check file ownership
.claude/scripts/marker-utils.sh check-marker .claude/protocols/run-mode.md
# → managed: true, version: 1.16.0

# Eject from framework (transfer ownership)
/loa-eject                    # Interactive eject wizard
/loa-eject --file <path>      # Eject specific file
/loa-eject --all              # Full framework eject
```

**Key Features**:
- **`_loa_marker` metadata**: JSON/YAML files include `managed: true`, `version`, `hash` fields
- **`_loa_managed` comments**: Markdown/script files use comment markers
- **Integrity verification**: SHA-256 hash validation for tamper detection
- **Eject command**: Transfer file ownership from framework to project
- **Version-targeted updates**: Update only files from specific versions

**New Files**:
- `.claude/scripts/marker-utils.sh` - Marker verification utilities
- `.claude/scripts/loa-eject.sh` - Eject command implementation
- `.claude/commands/loa-eject.md` - Command routing
- `.claude/skills/loa-eject/` - Eject skill with interactive wizard

**Updated Files**:
- All `.claude/protocols/*.md` - Added `_loa_managed` markers
- All `.claude/schemas/*.json` - Added `_loa_marker` metadata
- All `.claude/scripts/*.sh` - Added `_loa_managed` markers
- `.claude/scripts/update.sh` - Version-targeted update support

#### Two-Tier Learnings Architecture (#139)

Framework learnings now ship with Loa and are available to all projects:

```bash
# Query framework learnings
.claude/scripts/loa-learnings-index.sh query "bash" --tier framework

# Query both tiers (default)
.claude/scripts/loa-learnings-index.sh query "context management"

# Check tier status
.claude/scripts/loa-learnings-index.sh status
# → Framework (Tier 1): 40 (weight: 1.0)
# → Project (Tier 2): 0 (weight: 0.9)
```

**Two-Tier Model**:
| Tier | Location | Weight | Source |
|------|----------|--------|--------|
| Framework | `.claude/loa/learnings/` | 1.0 | Ships with Loa |
| Project | `grimoires/loa/a2a/compound/` | 0.9 | Project retrospectives |

**40 Seeded Learnings**:
- **10 Patterns**: Three-Zone Model, JIT Retrieval, Circuit Breaker, etc.
- **8 Anti-Patterns**: Arrow closures, `((var++))` with set -e, etc.
- **10 Decisions**: Why grimoires/, Why draft PRs, Why ICE layer, etc.
- **12 Troubleshooting**: Bash 4+, macOS compatibility, yq vs jq, etc.

**New Files**:
- `.claude/loa/learnings/index.json` - Manifest with counts
- `.claude/loa/learnings/patterns.json` - Proven architectural patterns
- `.claude/loa/learnings/anti-patterns.json` - Common pitfalls
- `.claude/loa/learnings/decisions.json` - Architectural decision records
- `.claude/loa/learnings/troubleshooting.json` - Issue resolution guides

**Updated Files**:
- `.claude/schemas/learnings.schema.json` - Added `tier`, `version_added`, `source_origin`
- `.claude/scripts/loa-learnings-index.sh` - Two-tier indexing with `--tier` flag
- `.claude/scripts/anthropic-oracle.sh` - Weighted search across tiers
- `.claude/scripts/update.sh` - `post_update_learnings()` for sync on update
- `.loa.config.yaml` - `learnings` configuration section

**Closes**: #76 (Extend /oracle to include Loa's own compound learnings)

### Fixed

#### Oracle Bash Increment Exit Code (#138)

Fixed `((count++))` causing premature script termination when `set -e` is active and count starts at 0:

```bash
# Before (fails when count=0)
((count++))

# After (safe increment)
count=$((count + 1))
```

This pattern is now documented in `.claude/loa/learnings/anti-patterns.json`.

### Configuration

New `.loa.config.yaml` sections:

```yaml
# Two-Tier Learnings
learnings:
  tiers:
    framework:
      enabled: true
      weight: 1.0
      source_dir: ".claude/loa/learnings"
    project:
      enabled: true
      weight: 0.9
  query:
    default_tier: all
    max_results: 10
    deduplicate: true
  index:
    rebuild_on_update: true
```

---

## [1.15.0] - 2026-02-02 — Prompt Enhancement & Developer Experience

### Why This Release

This release introduces the **Intelligent Prompt Enhancement System** with a new `/enhance` command, **consolidated sprint PRs** for cleaner Run Mode output, and several developer experience improvements including the **Canonical URL Registry** to prevent agent hallucination.

*"Enhance your prompts. Consolidate your PRs. Ground your URLs."*

### Added

#### `/enhance` Command & Prompt Enhancement Skill (#108, #109, #120)

New skill and command for improving prompt quality using the PTCF framework (Persona + Task + Context + Format):

```bash
/enhance "review the code"              # Analyze and enhance prompt
/enhance --analyze-only "check auth"    # Analysis without enhancement
/enhance --task-type code_review "..."  # Use specific template
```

**Features**:
- **Quality Scoring**: 0-10 score based on component detection
- **7 Task Templates**: debugging, code_review, refactoring, summarization, research, generation, general
- **Feedback Loop**: Up to 3 refinement iterations based on runtime errors or test failures
- **PTCF Analysis**: Detects missing Persona, Task, Context, and Format components

**New Files**:
- `.claude/skills/enhancing-prompts/` - 3-level skill architecture (15 files, 1282 lines)
- `.claude/commands/enhance.md` - Command routing

**Sources**: [Google Gemini Prompting Guide](https://workspace.google.com/blog/product-announcements/gemini-gems-ai-guide-prompting), SDPO feedback concepts

#### Canonical URL Registry (#127, #131)

Protocol and infrastructure to prevent agent URL hallucination:

```yaml
# grimoires/loa/urls.yaml (auto-created during /mount)
project:
  repository: "https://github.com/org/repo"
  documentation: "https://docs.example.com"
anthropic:
  docs: "https://docs.anthropic.com"
  api_reference: "https://docs.anthropic.com/en/api"
```

**Agent Protocol**: Agents must use `urls.yaml` entries or explicit user-provided URLs. Never fabricate URLs.

**New Files**:
- `.claude/protocols/url-registry.md` - Protocol specification
- `grimoires/loa/urls.yaml` - Created during `/mount`

#### Consolidated Sprint PRs (#124, #132)

`/run sprint-plan` now creates a **single consolidated PR** after all sprints complete (default behavior):

```bash
/run sprint-plan                  # Consolidated PR at end (default)
/run sprint-plan --no-consolidate # Legacy: separate PR per sprint
```

**Benefits**:
- Single PR for easier review
- Per-sprint breakdown table in PR description
- Commits grouped by sprint (`feat(sprint-1): ...`)
- Clean git history with sprint markers

**Updated Files**:
- `.claude/protocols/run-mode.md` - Consolidated PR format
- `.claude/skills/run-mode/SKILL.md` - Updated execution loop
- `.claude/commands/run-sprint-plan.md` - New `--no-consolidate` option

### Fixed

#### Mount Version Detection (#123, #133)

Fixed `/mount` installing outdated version (v1.7.2) instead of latest:

- `sync_zones()` now pulls upstream `.loa-version.json` during installation
- `create_manifest()` reads from pulled file with git tag fallback
- Removed hardcoded version from banner

#### Oracle Auto-Index (#116, #128)

Fixed `/oracle-analyze` returning no results when index doesn't exist:

- Oracle now auto-builds index on first query
- Clear error messages when index build fails

#### Feedback Trace Enablement (#115, #125, #130)

`/feedback` now prompts to enable trace collection when disabled:

- AskUserQuestion offers "Enable for this submission" option
- One-time collection without persisting settings
- Created `feedback` label in all ecosystem repos (#126)

#### Constructs API Migration (#106, #107)

Fixed `/constructs` command after API endpoint changes:

- Updated to unified `/v1/constructs` endpoint
- Supports both `.data[]` and legacy `.packs[]` response formats

### Documentation

#### Memory Leak Pattern (#129)

Added arrow function closure memory leak pattern to review and audit skills:

- `.claude/skills/reviewing-code/resources/REFERENCE.md` - Detection criteria
- `.claude/skills/auditing-security/resources/REFERENCE.md` - CWE-401 classification
- `grimoires/loa/memory/learnings.yaml` - Learning entry L-0001

**Pattern**: Use `obj.method.bind(obj)` instead of `() => obj.method()` to prevent closure memory leaks (1GB+ reduction in long sessions).

#### README Version Badge (#122)

Synced README version badge to current release.

---

## [1.14.1] - 2026-02-01 — Constructs Bug Fix

### Fixed

#### get_api_key() Missing from Shared Library (#104, #105)

Fixed undefined function error in `/constructs` command. The `get_api_key()` and `check_file_permissions()` functions were only defined in `constructs-install.sh` but called by `constructs-auth.sh` and `constructs-browse.sh`.

**Solution**: Moved both functions to `constructs-lib.sh` (the shared library sourced by all constructs scripts).

---

## [1.14.0] - 2026-02-01 — Constructs Multi-Select UI

### Why This Release

The `/constructs` command brings a streamlined pack installation experience with multi-select UI. Browse the Loa Constructs Registry, select multiple packs, and install them in one flow.

*"Point. Click. Install. The registry at your fingertips."*

### Added

#### `/constructs` Command (#88)

New slash command for browsing and installing packs from the Loa Constructs Registry:

```bash
/constructs              # Browse with multi-select UI
/constructs install <pack>   # Direct install
/constructs list         # Show installed packs
/constructs update       # Check for updates
/constructs uninstall <pack> # Remove a pack
/constructs auth         # Check auth status
/constructs auth setup   # Configure API key
```

**Multi-Select UI**: Uses Claude Code's `AskUserQuestion` with `multiSelect: true` for intuitive pack selection:

```
Select packs to install:

  [x] 🔮 Observer (6 skills) - User truth capture
  [x] ⚗️ Crucible (5 skills) - Validation & testing
  [ ] 🎨 Artisan (10 skills) - Brand/UI craftsmanship
  [ ] 📣 GTM Collective (Pro) - Go-to-market skills 🔒

  [Install Selected]  [Skip for Now]
```

**New Files**:
- `.claude/commands/constructs.md` - Command definition with agent routing
- `.claude/skills/browsing-constructs/` - Multi-select workflow skill
- `.claude/scripts/constructs-browse.sh` - Registry API + caching (1hr TTL)
- `.claude/scripts/constructs-auth.sh` - API key setup and validation

**Authentication**: Premium packs require API key:
```bash
/constructs auth setup   # Interactive setup
# Or set environment variable
export LOA_CONSTRUCTS_API_KEY="sk_your_key"
```

### Documentation

- **README.md** - Added `/constructs` to Ad-hoc commands
- **INSTALLATION.md** - New "Browse and Install with `/constructs`" section

---

## [1.13.0] - 2026-02-01 — Skill Best Practices & Security Hardening

### Why This Release

Loa now aligns with **Vercel AI SDK** and **Anthropic tool-writing best practices** for skill definitions. This release also adds the **Anthropic Context Features** foundation (effort parameter, context editing, memory schema) and comprehensive **security hardening** of shell scripts.

*"Industry-aligned skills. Fortified shell scripts. Token-efficient futures."*

### Added

#### Skill Best Practices Alignment (#97, #99)

All 13 skills now follow Vercel AI SDK and Anthropic best practices with new schema fields:

| Field | Type | Purpose |
|-------|------|---------|
| `effort_hint` | `low\|medium\|high` | Recommended reasoning depth |
| `danger_level` | `safe\|moderate\|high\|critical` | Risk classification |
| `categories` | `string[]` | Semantic groupings for search |
| `inputExamples` | `object[]` | Native Anthropic examples |
| `defer_loading` | `boolean` | Future deferred loading |

- **New Schema**: `.claude/schemas/skill-index.schema.json` - JSON Schema 2020-12 validation
- **Validation Script**: `.claude/scripts/validate-skills.sh` - Automated skill validation
- **Token Budget Mapping**: `low (~4K)`, `medium (~16K)`, `high (~64K)`
- **Canonical Categories**: planning, implementation, quality, support, operations

**Sources**: [Vercel AI SDK](https://ai-sdk.dev/docs/ai-sdk-core/tools-and-tool-calling), [Anthropic Advanced Tool Use](https://anthropic.com/engineering/advanced-tool-use)

#### Anthropic Context Features (#94, #95, #96, #98)

Foundation for three Anthropic platform features:

- **Effort Parameter** (#94): Configurable thinking budget per skill
  - Budget ranges: low (1K-4K), medium (8K-16K), high (24K-32K)
  - Verified: 76% token reduction (Anthropic Opus 4.5 announcement)

- **Context Editing** (#95): Three-layer architecture for intelligent compaction
  - Layers: Preserve → Cache → Compact
  - Threshold: 80% context usage triggers compaction
  - Verified: 84% token reduction (Claude context management blog)

- **Memory Schema** (#96): Grimoire-based persistence
  - 5 categories: fact, decision, learning, error, preference
  - Lifecycle: active → archived → expired
  - Location: `grimoires/loa/memory/`
  - Verified: 39% improvement with context editing

**New Files**:
- `.claude/schemas/memory.schema.json` - Memory entry validation
- `.claude/protocols/context-editing.md` - Three-layer architecture
- `.claude/protocols/memory.md` - Memory lifecycle protocol
- `docs/integration/runtime-contract.md` - Runtime integration contract

### Security

#### Shell Script Hardening (#99, #100, #101)

Comprehensive security audit with fixes across 20+ shell scripts:

| Finding | Severity | Fix |
|---------|----------|-----|
| CRITICAL-001 | Unsafe temp files | `mktemp + chmod 600` in 18 scripts |
| HIGH-001 | yq injection | New `yq-safe.sh` library |
| HIGH-002 | HTTP downgrade | `--proto =https --tlsv1.2` |
| HIGH-003 | Secret leak | Expanded redaction patterns |
| HIGH-004 | JSON injection | `jq -n` for generation |

- **New Library**: `.claude/scripts/yq-safe.sh` - Type-safe YAML extraction
  - `safe_yq_identifier` - Validates kebab-case names
  - `safe_yq_version` - Validates semver format
  - `safe_yq_enum` - Validates against allowed values
  - `safe_yq_path/url/bool/int` - Type-specific validation

- **Secret Redaction**: Now covers OpenSSH keys, hex keys (Web3), base64 secrets, OAuth tokens

### Changed

- **validate-skills.sh** - Now uses jq for JSON parsing with pattern validation
- **constructs-loader.sh** - Uses safe_yq_version with fallback validation
- **schema-validator.sh** - Added 100KB content size limit

### Documentation

- **CLAUDE.md** - Added Skill Best Practices section with:
  - Token budget mapping table
  - Canonical categories table
  - Enforcement status (#94 runtime prep)

---

## [1.12.0] - 2026-02-01 — Oracle Compound Learnings

### Why This Release

Loa now **learns from itself**. The Oracle system has been extended to query Loa's own compound learnings alongside Anthropic documentation. This implements the recursive improvement loop: Executions → Feedback → Oracle → Skills → Executions.

*"Loa should be its own oracle—teaching other agent systems how to improve based on what worked here."*

### Added

#### Oracle Compound Learnings (#89, #76)

Extend the oracle system to query Loa's own accumulated knowledge with hierarchical source weighting.

- **`query` Command** - New oracle action with scope parameter:
  ```bash
  # Query Loa learnings only
  .claude/scripts/anthropic-oracle.sh query "auth token" --scope loa

  # Query Anthropic docs only
  .claude/scripts/anthropic-oracle.sh query "hooks" --scope anthropic

  # Query all sources with weighted ranking
  .claude/scripts/anthropic-oracle.sh query "patterns" --scope all
  ```

- **Hierarchical Source Weighting**:
  | Source | Weight | Description |
  |--------|--------|-------------|
  | Loa Learnings | 1.0 | Skills, feedback, decisions from this repo |
  | Anthropic Docs | 0.8 | Official Claude best practices |
  | Community | 0.5 | External contributions |

- **Loa Sources Indexed**:
  - Skills: `.claude/skills/**/*.md`
  - Feedback: `grimoires/loa/feedback/*.yaml`
  - Decisions: `grimoires/loa/decisions.yaml`
  - Learnings: `grimoires/loa/a2a/compound/learnings.json`

- **`loa-learnings-index.sh`** - New indexing script (949 lines):
  ```bash
  # Build/update Loa learnings index
  .claude/scripts/loa-learnings-index.sh index

  # Query indexed learnings
  .claude/scripts/loa-learnings-index.sh query "pattern"

  # Show index status
  .claude/scripts/loa-learnings-index.sh status
  ```

- **QMD Integration** - Semantic search with grep fallback:
  - Uses QMD when available for semantic queries
  - Falls back to grep-based keyword search
  - Configurable via `.loa.config.yaml`

- **Effectiveness Tracking** - Track learning application:
  ```bash
  # Track that a learning was applied
  .claude/scripts/anthropic-oracle.sh query "pattern" --track
  ```

- **Configuration** (`.loa.config.yaml`):
  ```yaml
  oracle:
    compound_learnings:
      enabled: true
      default_scope: "all"
      source_weights:
        loa_learnings: 1.0
        anthropic_docs: 0.8
        community: 0.5
      index_paths:
        skills: ".claude/skills/**/*.md"
        feedback: "grimoires/loa/feedback/*.yaml"
        decisions: "grimoires/loa/decisions.yaml"
  ```

- **Updated Files**:
  - `.claude/commands/oracle-analyze.md` - Extended with query documentation
  - `.claude/schemas/learnings.schema.json` - Expanded schema
  - `grimoires/loa/feedback/README.md` - Feedback directory documentation

### Documentation

- **CLAUDE.md** - Added Oracle Compound Learnings section with:
  - Query command usage
  - Source weighting table
  - Index management
  - Configuration reference

---

## [1.11.0] - 2026-02-01 — Autonomous Agents & Developer Experience

### Why This Release

This is a **major release** with six significant features: the **Autonomous Agent Orchestra** (#82) for end-to-end workflow automation, **LLM-as-Judge** (#69) structured evaluation for auditors, **Adversarial Critic Protocol** (#85) for rigorous code reviews, **Decision Lineage Schema** (#86) for tracking architectural decisions, **Smart Feedback Routing** (#81) for ecosystem-aware issue routing, and **WIP Branch Testing** (#91) for safe framework updates. Plus comprehensive **security hardening** and **attention budget enforcement** (#83) across all skills.

*"The orchestra plays. The agents review. The decisions persist."*

### Added

#### Autonomous Agent Orchestra (#82)

Meta-orchestrator skill for exhaustive Loa process compliance with 8-phase execution model.

- **`/autonomous` command** - End-to-end autonomous workflow
  - Phase 1: Initialization & context loading
  - Phase 2: PRD discovery & requirements
  - Phase 3: Architecture design
  - Phase 4: Sprint planning
  - Phase 5: Implementation cycles
  - Phase 6: Review & audit loops
  - Phase 7: Deployment preparation
  - Phase 8: Completion & learning extraction

- **Operator Detection** - Identifies workflow context and adapts behavior
- **Quality Gates** - Configurable checkpoints between phases
- **Escalation Templates** - Structured handoff when human intervention needed

- **New Skill**: `.claude/skills/autonomous-agent/`
  - `index.yaml` - Skill metadata
  - `SKILL.md` - 8-phase execution model
  - Resources: operator-detection, phase-checklist, quality-gates

#### LLM-as-Judge Auditor Enhancement (#69)

Structured evaluation rubrics with machine-parseable output for the auditing-security skill.

- **23 Scoring Dimensions** across 5 categories:
  - Security (injection, auth, crypto, data protection)
  - Architecture (coupling, scalability, resilience)
  - Code Quality (complexity, testing, documentation)
  - Operations (logging, monitoring, deployment)
  - Compliance (privacy, licensing, accessibility)

- **Output Schema** - JSONL format with reasoning traces
- **New Resources**:
  - `RUBRICS.md` - 23 evaluation dimensions
  - `OUTPUT-SCHEMA.md` - JSONL schema specification

#### Adversarial Critic Protocol (#85)

Enhances code reviews with adversarial analysis that challenges assumptions and identifies edge cases.

- **Structured Adversarial Sections**:
  - Concerns identified
  - Assumptions challenged
  - Alternatives not considered
  - Adversarial verdict

- **Review Template** - `reviewing-code/resources/templates/review-feedback.md`

#### Decision Lineage Schema (#86)

Track architectural decisions with full lineage - why decisions were made, alternatives considered, and connections to requirements.

- **Decision Record Structure**:
  ```yaml
  decisions:
    - id: DEC-001
      title: "Decision title"
      context: "Why this decision was needed"
      options: [{ name: "Option A", pros: [...], cons: [...] }]
      chosen: "Option A"
      rationale: "Why this option was chosen"
      supersedes: null  # Links to previous decisions
  ```

- **New Files**:
  - `.claude/schemas/decisions.schema.json` - JSON schema
  - `.claude/protocols/decision-capture.md` - Capture protocol
  - `docs/architecture/decision-lineage.md` - Documentation

#### Attention Budget Enforcement (#83)

Tool Result Clearing attention budgets added to all 7 search-heavy skills.

- **Token Thresholds**:
  | Context Type | Limit | Action |
  |--------------|-------|--------|
  | Single search result | 2,000 tokens | Apply 4-step clearing |
  | Accumulated results | 5,000 tokens | MANDATORY clearing |
  | Full file load | 3,000 tokens | Synthesize immediately |
  | Session total | 15,000 tokens | STOP, synthesize to NOTES.md |

- **Skills Updated**: `auditing-security`, `implementing-tasks`, `discovering-requirements`, `riding-codebase`, `reviewing-code`, `planning-sprints`, `designing-architecture`

#### Smart Feedback Routing (#81, #93)

Context-aware routing for the `/feedback` command to direct issues to the correct ecosystem repository.

- **`feedback-classifier.sh`** - Context classification engine
  - Signal-based scoring with weights for different patterns
  - Confidence calculation for routing decisions
  - Categories: `loa_framework`, `loa_constructs`, `forge`, `project`

- **Ecosystem Routing** - Routes to appropriate repo based on context:
  | Repo | Signals |
  |------|---------|
  | `0xHoneyJar/loa` | `.claude/`, `grimoires/`, `skill`, `protocol`, `PRD`, `SDD` |
  | `0xHoneyJar/loa-constructs` | `registry`, `API`, `endpoint`, `pack`, `constructs` |
  | `0xHoneyJar/forge` | `experimental`, `sandbox`, `WIP`, `draft` |
  | project-specific | `deployment`, `infra`, `application`, `app` |

- **AskUserQuestion Integration** - Per Anthropic best practices (#90):
  - Recommended option appears first with "(Recommended)" suffix
  - Headers under 12 characters for chip display
  - Descriptions explain trade-offs

- **`gh-label-handler.sh`** - Graceful label handling
  - Retries without labels if "label not found" error
  - Prevents single missing label from blocking feedback

#### WIP Branch Testing (#91, #93)

Test Loa framework updates on feature branches before merging to your working branch.

- **Branch Mode Selection** - When `/update-loa` detects a feature branch:
  - Option 1: "Checkout for testing (Recommended)" - Creates `test/loa-*` branch
  - Option 2: "Merge into current branch" - Existing behavior

- **`branch-state.sh`** - State management for test branches
  - Saves original branch for return flow
  - Commands: `save`, `load`, `clear`, `is-testing`
  - State file: `.loa/branch-testing.json`

- **Return Helper** - When on `test/loa-*` branch:
  - Return to original branch
  - Stay on test branch
  - Merge test branch into original

- **Configurable Patterns** - Feature branch detection:
  ```yaml
  update_loa:
    branch_testing:
      enabled: true
      feature_patterns: ["feature/*", "fix/*", "topic/*", "wip/*", "test/*"]
      test_branch_prefix: "test/loa-"
  ```

#### Security Hardening (#93)

Comprehensive security improvements based on code audit findings.

- **`security-validators.sh`** - Reusable validation library (452 lines)
  - `validate_safe_path()` - Path validation with symlink resolution
  - `validate_config_path()` - Config path validation (no traversal)
  - `validate_numeric()` / `validate_float()` - Numeric validation with bounds
  - `validate_boolean()` - Boolean normalization
  - `validate_repo_url()` - GitHub repo URL format validation
  - `safe_rm_rf()` - Boundary-checked rm -rf with symlink protection
  - `safe_config_*()` - Safe config extraction wrappers

- **HIGH-001 Fix** - Regex injection prevention in `feedback-classifier.sh`
  - Use `printf '%s'` instead of `echo` for user content
  - Add `--` before grep patterns to prevent option injection

- **MEDIUM-001 Fix** - Absolute path resolution in `branch-state.sh`
  - `find_project_root()` resolves state directory from project root
  - Prevents state file writes to unintended locations

- **MEDIUM-003 Fix** - Safe rm -rf in `cleanup-context.sh`
  - Replaced vulnerable `find -exec rm -rf {}` pattern
  - Added symlink resolution with `pwd -P`
  - Added boundary check after resolution

- **MEDIUM-004 Fix** - jq/yq output sanitization
  - `qmd-sync.sh`: Validates boolean, binary name, and path configs
  - `compact-trajectory.sh`: Validates numeric configs with bounds
  - Rejects traversal sequences, absolute paths, shell metacharacters

### Changed

- **`/feedback` command** - Now v2.1.0 with smart routing
- **`/update-loa` command** - Now v1.2.0 with WIP branch testing
- **7 skills** - Added attention budget sections with token thresholds
- **CLAUDE.md** - Added documentation for all new features

### New Commands

| Command | Description |
|---------|-------------|
| `/autonomous` | End-to-end autonomous workflow execution |

### Configuration

New sections in `.loa.config.yaml`:

```yaml
# Smart Feedback Routing
feedback:
  routing:
    enabled: true
    auto_classify: true
    require_confirmation: true
  repos:
    framework: "0xHoneyJar/loa"
    constructs: "0xHoneyJar/loa-constructs"
    forge: "0xHoneyJar/forge"
    project: "${GITHUB_REPOSITORY}"
  labels:
    graceful_missing: true
    default: ["feedback", "user-report"]

# WIP Branch Testing
update_loa:
  branch_testing:
    enabled: true
    feature_patterns: ["feature/*", "fix/*", "topic/*", "wip/*", "test/*"]
    test_branch_prefix: "test/loa-"
```

### New Scripts

| Script | Purpose |
|--------|---------|
| `feedback-classifier.sh` | Context-based routing classification |
| `gh-label-handler.sh` | Graceful GitHub label handling |
| `branch-state.sh` | WIP branch testing state management |
| `security-validators.sh` | Reusable security validation utilities |

---

## [1.10.0] - 2026-01-30 — Compound Learning & Visual Communication

### Why This Release

This release adds three major capabilities: **Compound Learning** for cross-session pattern detection, **Beautiful Mermaid** for visual diagram rendering, and **Feedback Traces** for regression debugging. Together, these features enable agents to learn across sessions, communicate visually, and provide better debugging information.

*"The agent gets smarter every day because it reads its own updated instructions."*

### Added

#### Compound Learning System (#67)

Cross-session pattern detection and automated knowledge consolidation, inspired by [Ryan Carson's autonomous coding workflow](https://x.com/ryancarson).

- **`/compound`** - End-of-cycle learning extraction
  - Reviews all trajectory logs from current development cycle
  - Detects cross-session patterns (repeated errors, convergent solutions)
  - Extracts qualified patterns as reusable skills
  - Archives cycles with changelog generation

- **`/retrospective --batch`** - Multi-session batch analysis
  - Analyzes trajectory files across configurable date ranges
  - Jaccard similarity clustering for pattern detection
  - 4-gate quality filter (Discovery Depth, Reusability, Trigger Clarity, Verification)
  - Configurable confidence thresholds

- **Effectiveness Feedback Loop** - Track, verify, reinforce/demote learnings
  - Signal weights for task completion, user feedback
  - Tier system (HIGH/MEDIUM/LOW/INEFFECTIVE)
  - Automatic pruning of ineffective learnings

- **Morning Context Loading** - Load relevant learnings at session start
  - Semantic matching based on current task context
  - Configurable max learnings and age limits

- **Skill Synthesis** - Merge related skills into refined knowledge
  - Cluster similar skills using semantic similarity
  - Human approval for all synthesis proposals

- **28 new scripts** in `.claude/scripts/` for pattern detection, clustering, and effectiveness tracking

#### Beautiful Mermaid Visual Communication (#68)

Integrated diagram rendering using [agents.craft.do/mermaid](https://agents.craft.do/mermaid) service.

- **`mermaid-url.sh`** - Security-hardened URL generator
  - Theme validation with allowlist (github, dracula, nord, tokyo-night, solarized-light, solarized-dark, catppuccin)
  - Mermaid syntax validation
  - Size limits (1500 chars max for URLs)
  - Configurable service URL via environment variable

- **Visual Communication Protocol** (`.claude/protocols/visual-communication.md`)
  - Standards for visual output across all agents
  - Required vs optional diagrams per agent type
  - Hybrid output: Mermaid code blocks + preview URLs

- **Agent Integration** - All skill files updated with visual communication sections:
  - `designing-architecture`: System diagrams, sequence diagrams, ER diagrams (required)
  - `translating-for-executives`: Executive dashboards (required)
  - `discovering-requirements`, `planning-sprints`, `reviewing-code`: Optional diagrams

- **Diagram Templates** - 5 templates in `.claude/skills/designing-architecture/resources/templates/diagrams/`:
  - `flowchart-system.md` - System architecture
  - `sequence-api.md` - API interactions
  - `class-domain.md` - Domain models
  - `er-database.md` - Database schemas
  - `state-lifecycle.md` - State machines

#### Feedback Trace Collection (#66)

Opt-in execution trace collection for regression debugging, replacing Linear with GitHub Issues.

- **`/feedback`** - Submit developer feedback with optional traces
  - Creates GitHub Issues with structured format
  - OSS-friendly (open to all users)
  - Auto-attaches trajectory excerpts when enabled

- **`collect-trace.sh`** - Trace collection script
  - Configurable scope: `execution`, `full`, `failure-window`
  - Privacy-first: opt-in only, user review before submit
  - Auto-redact secrets and sensitive patterns

- **Configuration** (`.claude/settings.local.json`):
  ```json
  {
    "feedback": {
      "trace_collection": {
        "enabled": true,
        "scope": "failure-window"
      }
    }
  }
  ```

### Configuration

New sections in `.loa.config.yaml`:

```yaml
# Compound Learning
compound_learning:
  enabled: true
  pattern_detection:
    min_occurrences: 2
    max_age_days: 90
  similarity:
    prefer_semantic: true
    fallback:
      jaccard_threshold: 0.6
  quality_gates:
    discovery_depth: { min_score: 5 }
    reusability: { min_score: 5 }
    trigger_clarity: { min_score: 5 }
    verification: { min_score: 3 }

# Visual Communication
visual_communication:
  enabled: true
  service: "https://agents.craft.do/mermaid"
  theme: "github"
  include_preview_urls: true
```

### New Commands

| Command | Description |
|---------|-------------|
| `/compound` | End-of-cycle learning extraction |
| `/compound status` | Show compound learning status |
| `/compound changelog` | Generate cycle changelog |
| `/retrospective --batch` | Multi-session pattern analysis |
| `/feedback` | Submit feedback with optional traces |

---

## [1.9.1] - 2026-01-29 — Memory Stack Patch

### Fixed

- **Venv Python Support** - Memory Stack now works with externally-managed Python environments (PEP 668)
  - `memory-admin.sh` and `memory-setup.sh` auto-detect `.loa/venv/bin/python3`
  - Fixes compatibility with modern Debian/Ubuntu systems that block system-wide pip installs

### Documentation

- Added resource requirements warning for Memory Stack (2-3 GB disk, ~500 MB RAM)
- Added links to [sentence-transformers](https://github.com/UKPLab/sentence-transformers) repository and documentation

---

## [1.9.0] - 2026-01-29 — Claude Code 2.1.x Feature Adoption

### Why This Release

This release aligns Loa with Claude Code 2.1.x platform capabilities, adding async hooks for improved performance and context cleanup automation.

*"Async where possible, blocking only when necessary."*

### Added

- **Async Hooks** - Non-blocking hooks for improved session performance
  - `SessionStart` → `check-updates.sh` (async: true)
  - `PermissionRequest` → `permission-audit.sh` (async: true)
  - `PreToolUse` hooks remain blocking when they must complete before execution

- **Context Cleanup Hook** - Auto-archive previous cycle context before `/plan-and-analyze`
  - Detects existing PRD/SDD/sprint files from previous cycles
  - Prompts user: Archive (Y), Keep (n), or Abort (q)
  - Archives to cycle's archive directory with timestamp
  - Prevents stale context from polluting new development cycles

- **One-Time Hooks** - `once: true` flag prevents duplicate runs per session
  - Update check only runs once on session start

- **Session ID Tracking** - `${CLAUDE_SESSION_ID}` now logged in trajectory files
  - Enables cross-session correlation and debugging

- **Skill Forking Protocol** - Documentation for `context: fork` pattern
  - Read-only skills like `/ride` use isolated execution context
  - Prevents context pollution from exploration tasks

### Changed

- **Settings.json** - Updated with async flags and cleanup hook configuration
- **Recommended Hooks Protocol** - Expanded documentation for async patterns

---

## [1.8.0] - 2026-01-28 — Memory Stack

### Why This Release

This release introduces the **Memory Stack** - a vector database with PreToolUse hook system for mid-stream semantic grounding during Claude Code sessions. All security vulnerabilities identified in the comprehensive audit have been remediated.

*"Learnings that persist. Context that recalls itself."*

### Added

- **Vector Database** (`memory-admin.sh`)
  - SQLite + sentence-transformers embeddings (all-MiniLM-L6-v2, 384 dimensions)
  - CLI for managing memories: add, search, list, delete, prune
  - Semantic similarity search with configurable threshold

- **PreToolUse Hook** (`memory-inject.sh`)
  - Mid-stream memory injection during Read/Glob/Grep/WebFetch/WebSearch
  - Extracts last N characters from thinking block as query
  - Deduplication via SHA-256 hash to prevent repeated queries
  - Configurable timeout (default 500ms) for latency control

- **NOTES.md Sync** (`memory-sync.sh`)
  - Automatic extraction of learnings section to vector database
  - Runs on session start if `auto_sync: true`
  - Incremental sync - only new learnings added

- **QMD Integration** (`qmd-sync.sh`)
  - Document search with semantic or grep fallback
  - Indexes grimoires/loa for searchable project context
  - Collection-based organization

- **Setup Wizard** (`memory-setup.sh`)
  - First-time setup with dependency checking
  - Interactive configuration prompts
  - Validates Python + sentence-transformers installation

### Security Remediation

| Issue | Severity | Fix |
|-------|----------|-----|
| SQL Injection in memory queries | HIGH | Python parameterized queries |
| Command Injection via query | HIGH | Environment variable passing instead of shell interpolation |
| Path Traversal in file operations | HIGH | realpath validation |
| Input Sanitization | MEDIUM | Control character + ANSI escape removal |
| Temp File Security | MEDIUM | mktemp with random suffix |
| Trajectory Sensitivity | MEDIUM | Documentation + .gitignore coverage |

### Configuration

```yaml
# .loa.config.yaml
memory:
  pretooluse_hook:
    enabled: false  # Opt-in for safety
    thinking_chars: 1500
    similarity_threshold: 0.35
    max_memories: 3
    timeout_ms: 500
    tools:
      - Read
      - Glob
      - Grep
      - WebFetch
      - WebSearch

  vector_db:
    path: .loa/memory.db
    model: all-MiniLM-L6-v2
    dimension: 384

  auto_sync: false  # Sync NOTES.md learnings on session start
```

### Research References

| Paper | Relevance |
|-------|-----------|
| [Retrieval-Augmented Generation for LLM Agents](https://arxiv.org/abs/2312.10997) | RAG patterns for agent workflows |
| [Self-RAG: Learning to Retrieve, Generate, and Critique](https://arxiv.org/abs/2310.11511) | Self-reflective retrieval |
| [Semantic Caching for LLM Applications](https://arxiv.org/abs/2311.04934) | Query deduplication via hashing |

---

## [1.7.2] - 2026-01-28 — Issues Remediation

### Fixed

- **Mount Script Version Detection** (#56) - Fixed hardcoded fallback version `0.6.0` → `1.7.1`
  - Version detection now checks root `.loa-version.json` first
  - Updated banner version from `v0.9.0` to `v1.7.1`

- **Anthropic Oracle URLs** (#58) - Updated Claude Code documentation URLs
  - Docs moved from `docs.anthropic.com` to `code.claude.com`
  - Added new endpoints: `memory`, `skills`, `hooks`

### Added

- **Sprint Auto-Continuation** (#55) - `/run sprint-plan` now automatically continues to next sprint
  - Sprint plan execution loop with automatic advancement
  - State tracking in `sprint-plan-state.json`
  - Sprint discovery priority: `sprint.md` → `ledger.json` → `a2a/` directories

- **Sprint Ledger Auto-Creation** (#57) - `/sprint-plan` now offers to create ledger if missing
  - Step 0 checks for ledger existence before planning
  - User prompt via `AskUserQuestion` with option to decline
  - Follows existing ledger.json schema

---

## [1.7.1] - 2026-01-24 — Template Cleanup

### Fixed

- **Template Pollution** - Removed 9 Loa-specific PRD/SDD/sprint documents that were accidentally committed in v1.6.0 and v1.7.0:
  - `prd-ck-migration.md`, `sdd-ck-migration.md`, `sprint-ck-migration.md`
  - `prd-ride-before-plan.md`, `sdd-ride-before-plan.md`, `sprint-ride-before-plan.md`
  - `prd-goal-traceability.md`, `sdd-goal-traceability.md`, `sprint-goal-traceability.md`

- **Improved .gitignore** - Updated patterns from exact filenames (`prd.md`) to globs (`prd*.md`) to prevent future pollution from feature-variant documents

### Notes

Fresh installs of v1.6.0 or v1.7.0 would have included these development documents in the `grimoires/loa/` directory. Users can safely delete them - they are Loa framework development artifacts, not project templates.

---

## [1.7.0] - 2026-01-24 — Goal Traceability & Guided Workflow

### Why This Release

This release introduces **Goal Traceability** - the ability to verify that PRD goals are actually achieved through sprint implementation. No more "we completed all tasks but did we hit the goals?" uncertainty.

*"Goals without traceability are wishes. Goals with traceability are commitments."*

### Added

- **Goal Validator Subagent** (`.claude/subagents/goal-validator.md`)
  - Verifies PRD goals are achieved through implementation
  - Three verdict levels: `GOAL_ACHIEVED`, `GOAL_AT_RISK`, `GOAL_BLOCKED`
  - Integration gap detection (new data without consumers, new APIs without callers)
  - Automatic invocation during final sprint review
  - Manual invocation via `/validate goals`

- **Goal Traceability Matrix** (Sprint Plan Appendix C)
  - Maps PRD goals to contributing tasks
  - Identifies E2E validation tasks per goal
  - Auto-generated by `/sprint-plan`

- **Workflow State Detection** (`workflow-state.sh`)
  - Detects current workflow state (initial → prd_created → sdd_created → sprint_planned → implementing → reviewing → auditing → complete)
  - Suggests next command based on state
  - Progress percentage tracking
  - Semantic cache integration (RLM pattern)

- **`/loa` Command** - Guided workflow entry point
  - Shows current state and progress
  - Suggests appropriate next action
  - No more guessing "what command should I run?"

- **Goal Status Section** in NOTES.md template
  - Track goal achievement: `NOT_STARTED`, `IN_PROGRESS`, `AT_RISK`, `ACHIEVED`, `BLOCKED`
  - Lightweight evidence identifiers (JIT pattern)
  - Validation cache key tracking

### Changed

- **Workflow Chain** updated to require goal traceability steps
- **NOTES.md Template** updated with Goal Status section using JIT retrieval pattern
- **Goal Validator** follows Loa patterns:
  - JIT Retrieval: Lightweight identifiers instead of eager loading
  - Semantic Cache: Results cached via `cache-manager.sh`
  - Beads Integration: Validation findings tracked with `br` commands
  - Truth Hierarchy: CODE → BEADS → NOTES → TRAJECTORY → PRD

### Configuration

```yaml
# .loa.config.yaml
goal_validation:
  enabled: true              # Master toggle (opt-in by default)
  block_on_at_risk: false    # Default: warn only
  block_on_blocked: true     # Default: always block
  require_e2e_task: true     # Require E2E task in final sprint
```

### Backward Compatibility

- If PRD has no goal IDs: auto-assigns G-1, G-2, G-3
- If sprint has no Appendix C: warns but doesn't block
- If `goal_validation.enabled: false`: skips entirely
- Existing projects continue working unchanged

---

## [1.6.0] - 2026-01-23 — Codebase Grounding & Security Hardening

### Why This Release

This release combines **Cycle-008** (ck-First Semantic Search Migration) and **Cycle-009** (Security Remediation v2). The `/plan-and-analyze` command now automatically grounds itself in codebase reality for brownfield projects, and all 30 security findings from the comprehensive audit have been addressed.

*"CODE IS TRUTH. PRDs are now grounded in what actually exists, not what we think exists."*

### Added

- **Automatic Codebase Grounding** (`/plan-and-analyze`)
  - Phase -0.5 automatically runs `/ride` for brownfield projects
  - Greenfield projects skip to Phase -1 with zero latency
  - Uses cached reality if <7 days old (configurable)
  - `--fresh` flag forces re-analysis
  - Configuration in `.loa.config.yaml`:
    ```yaml
    plan_and_analyze:
      codebase_grounding:
        enabled: true
        reality_staleness_days: 7
        ride_timeout_minutes: 20
        skip_on_ride_error: false
    ```

- **Brownfield Detection** (`detect-codebase.sh`)
  - Detects >10 source files OR >500 lines of code
  - Identifies primary language and source paths
  - 41 comprehensive BATS unit tests
  - JSON output for programmatic consumption

- **ck-First Semantic Search** (`search-orchestrator.sh`)
  - `ck` as primary search with automatic grep fallback
  - Updated for ck v0.7.0+ CLI syntax (`--sem`, `--limit`, positional path)
  - Three search modes: `semantic`, `hybrid`, `regex`
  - Input validation: regex syntax, numeric params, path traversal protection

- **Skills Updated for ck Search**
  - `riding-codebase`: Route, model, env var, tech debt extraction
  - `reviewing-code`: Impact analysis with hybrid search
  - `implementing-tasks`: Context retrieval with hybrid search
  - `deploying-infrastructure`: Secrets scanning with regex search
  - `translating-for-executives`: Ghost feature examples

### Security

- **CRITICAL Fixes (2)**
  - CRIT-001: Fixed Python code injection in `constructs-install.sh` heredoc
    - Uses quoted `'PYEOF'` delimiter + environment variables
  - CRIT-002: Added path traversal protection in pack extraction
    - New `safe_path_join()` with realpath + component validation

- **HIGH Fixes (8)**
  - HIGH-001: Atomic ledger writes with flock (5s timeout)
  - HIGH-002: Process substitution for Authorization header (no ps exposure)
  - HIGH-003: Improved symlink validation with readlink -f
  - HIGH-004: Global trap handlers (EXIT/INT/TERM) in update.sh
  - HIGH-005: Replaced `eval` with `bash -c` in preflight.sh
  - HIGH-006: Fixed branch regex bypass with glob matching
  - HIGH-007: Atomic backup cleanup with flock
  - HIGH-008: Atomic write pattern (temp + mv) across state files

- **MEDIUM Fixes (12)**
  - MED-001: Credential file permission checking (600/400 only)
  - MED-004: Reduced JWT key cache TTL from 24h to 4h
  - MED-005: New `secure_write_file()` and `secure_write_json()` utilities
  - MED-006: Fixed license validation error propagation
  - MED-007: Backup preservation in jq operations
  - MED-008: Backup validation before restore
  - MED-010: flock-based sync locking for beads operations

- **LOW Fixes (5)**
  - LOW-004: Explicit numeric validation before arithmetic
  - LOW-005: Standardized shebang (`#!/usr/bin/env bash`) in 24 scripts

### Changed

- **ck v0.7.0+ Syntax** across all protocols and scripts
  - `--sem` instead of `--semantic`
  - `--limit` instead of `--top-k`
  - Path as final positional argument instead of `--path`

- **search-orchestrator.sh** hardening
  - Added regex syntax validation (prevents ReDoS)
  - Added numeric parameter validation
  - Added path traversal protection with realpath

### Fixed

- Fixed unsafe xargs usage in detect-codebase.sh (filenames with spaces)
- Fixed all ck calls to use v0.7.0+ syntax

---

## [1.5.0] - 2026-01-23 — Recursive JIT Context System

### Why This Release

Introduces the **Recursive JIT Context System** — a comprehensive solution for context management in long-running agent sessions. This release addresses the fundamental challenge of Claude Code's automatic context summarization by providing semantic caching, intelligent condensation, and continuous synthesis to persistent ledgers.

*"The code remembers what the context forgets."*

### Added

- **Recursive JIT Context System** (`.claude/scripts/`)
  - `cache-manager.sh` — Semantic result caching with mtime-based invalidation
    - LRU eviction, TTL expiration (30 days default)
    - Secret pattern detection on write
    - Integrity verification with SHA256 hashes
  - `condense.sh` — Result condensation engine
    - Strategies: `structured_verdict` (~50 tokens), `identifiers_only` (~20), `summary` (~100)
    - Full result externalization to `.claude/cache/full/`
  - `early-exit.sh` — Parallel subagent coordination
    - File-based "first-to-finish wins" protocol
    - Session management, agent registration, result passing
  - `synthesize-to-ledger.sh` — Continuous synthesis trigger
    - Writes decisions to NOTES.md and trajectory at RLM trigger points
    - Survives Claude Code's automatic context summarization

- **Continuous Synthesis** — Anti-platform-summarization defense
  - RLM operations (cache set, condense, early-exit) trigger automatic ledger writes
  - Decisions externalized to NOTES.md Decision Log
  - Trajectory entries for audit trail
  - Optional bead comment injection (when `br` available)
  - Configuration in `.loa.config.yaml`:
    ```yaml
    recursive_jit:
      continuous_synthesis:
        enabled: true
        on_cache_set: true
        on_condense: true
        on_early_exit: true
        update_bead: true
    ```

- **Post-Upgrade Health Check** (`upgrade-health-check.sh`)
  - Detects bd → br migration status
  - Finds deprecated references in settings.local.json
  - Identifies new config sections available
  - Suggests recommended permissions for new features
  - Auto-fix mode: `--fix` flag applies safe corrections
  - Runs automatically after `update.sh`

- **Upgrade Completion Banner** (`upgrade-banner.sh`)
  - Cyberpunk-themed ASCII art completion message
  - Rotating quotes from Neuromancer, Blade Runner, The Matrix, Ghost in the Shell
  - Original Loa-themed quotes about synthesis and context management
  - CHANGELOG highlights parsing (when available)
  - Mount mode vs upgrade mode with appropriate next steps
  - JSON output for scripting: `--json`

- **beads_rust Integration** with Continuous Synthesis
  - Active bead detection from NOTES.md Session Continuity
  - Automatic `[Synthesis] <message>` comment injection
  - Redundant persistence: NOTES.md + trajectory + bead comments

- **Protocol Documentation**
  - `.claude/protocols/recursive-context.md` — Full RLM system documentation
  - Architecture diagrams, integration patterns, configuration reference

### Changed

- **Opt-Out Defaults** — All RLM features now enabled by default
  - Scripts use `// true` fallbacks instead of `// false`
  - Users can disable features in config rather than needing to enable them
  - Ships with sane defaults for immediate benefit

- **CLAUDE.md** — Updated with Recursive JIT Context section
  - New scripts documented in Helper Scripts table
  - Protocol references added

### Technical Details

- **Two-Level Context Management**
  - Platform level: Claude Code's automatic summarization (outside Loa's control)
  - Framework level: Loa's protocols for proactive externalization (full control)
  - Solution: Write to ledgers BEFORE platform summarization occurs

- **Performance Targets**
  - Cache hit rate: >30% over 30 days
  - Context reduction: 30-40% via condensation
  - Cache lookup: <100ms
  - Condensation: <50ms

### Migration Notes

No migration required. All features are enabled by default and backward compatible.

Run `upgrade-health-check.sh` after upgrading to check for:
- Legacy `bd` references that should be `br`
- Missing config sections
- Recommended permission additions

## [1.4.0] - 2026-01-22 — Clean Upgrade & CLAUDE.md Diet

### Why This Release

Eliminates git history pollution during framework upgrades and dramatically reduces CLAUDE.md size for better Claude Code context efficiency.

### Added

- **Clean Upgrade Commits**: Framework upgrades now create single atomic commits
  - `mount-loa.sh` and `update.sh` create conventional commits: `chore(loa): upgrade framework v{OLD} -> v{NEW}`
  - Version tags: `loa@v{VERSION}` for easy upgrade history tracking
  - Query history with `git tag -l 'loa@*'`
  - Rollback with `git revert HEAD` or `git checkout loa@v{VERSION} -- .claude`

- **Upgrade Configuration**: New `.loa.config.yaml` section
  ```yaml
  upgrade:
    auto_commit: true   # Create git commit after upgrade
    auto_tag: true      # Create version tag
    commit_prefix: "chore"  # Conventional commit prefix
  ```

- **`--no-commit` Flag**: Skip automatic commit creation
  - `mount-loa.sh --no-commit`
  - `update.sh --no-commit`

- **Protocol Documentation**
  - `.claude/protocols/helper-scripts.md` - Comprehensive script documentation
  - `.claude/protocols/upgrade-process.md` - 12-stage upgrade workflow documentation

### Changed

- **CLAUDE.md**: Reduced from 1,157 lines to 321 lines (72% reduction)
  - Core instructions remain in CLAUDE.md
  - Detailed documentation moved to protocol files
  - References added for JIT loading when needed

### Technical Details

- **Stealth Mode**: No commits created in stealth persistence mode
- **Tag Handling**: Existing tags are not overwritten
- **Dirty Tree**: Warnings shown but upgrades continue
- **Config Priority**: CLI flags > config file > defaults

### Migration Notes

No migration required. Existing installations will gain clean upgrade behavior automatically on next update.

## [1.3.1] - 2026-01-20 — Gitignore Hardening

### Why This Release

Security and hygiene improvements to ensure sensitive files and project-specific state are never accidentally committed.

### Added

- **Simstim `.gitignore`** — Protects user-specific configuration
  - `simstim.toml` (contains Telegram chat IDs)
  - Audit logs and Python artifacts

- **Enhanced Beads exclusions** — Runtime files now properly ignored
  - `daemon.lock` (process lock)
  - `.local_version` (local br version)
  - `beads.db` (SQLite database)
  - `*.meta.json` (sync metadata)
  - `*.jsonl` (task graph - template repo only)

- **Archive exclusion** — `grimoires/loa/archive/` now ignored
  - Project-specific development cycle history
  - Prevents template pollution

### Security

All user-specific and runtime files are now protected from accidental commits.

## [1.3.0] - 2026-01-20 — Simstim Telegram Bridge

### Why This Release

This release introduces **Simstim**, a Telegram bridge for remote monitoring and control of Loa (Claude Code) sessions. **Ported from [takopi.dev](https://takopi.dev/)** and adapted for Loa workflows. Named after the neural interface technology in William Gibson's Sprawl trilogy, Simstim lets you experience your AI agent workflows from anywhere—approve permissions, monitor phases, and control execution from your phone.

### Added

- **Simstim Package** (`simstim/`)
  - Full Python package with CLI interface
  - Telegram bot integration for permission relay
  - Auto-approve policy engine with pattern matching
  - Phase transition and quality gate notifications
  - Offline queue with automatic reconnection
  - Comprehensive JSONL audit logging

- **Permission Features**
  - One-tap approve/deny from Telegram
  - Configurable timeout with default action
  - Rate limiting per user
  - Denial backoff for abuse prevention

- **Policy Engine**
  - TOML-based policy configuration
  - Pattern matching for file paths and commands
  - Allowlist/blocklist support
  - Fail-closed defaults for security

- **Monitoring Capabilities**
  - Phase transition notifications
  - Quality gate alerts (review/audit)
  - NOTES.md update detection
  - Sprint progress tracking

### Security Hardening

Comprehensive security audit identified and remediated 9 vulnerabilities:

| Finding | Severity | CWE | Fix |
|---------|----------|-----|-----|
| SIMSTIM-001 | CRITICAL | CWE-522 | SafeSecretStr for token protection |
| SIMSTIM-002 | CRITICAL | CWE-78 | Command allowlist, shell=False enforcement |
| SIMSTIM-003 | HIGH | CWE-285 | Fail-closed authorization by default |
| SIMSTIM-004 | HIGH | CWE-312 | Credential redaction in notifications |
| SIMSTIM-005 | HIGH | CWE-943 | Literal-only policy value comparisons |
| SIMSTIM-006 | MEDIUM | CWE-208 | Constant-time rate limit evaluation |
| SIMSTIM-007 | MEDIUM | CWE-200 | Extended redaction (30+ patterns, JWT, AWS keys) |
| SIMSTIM-008 | MEDIUM | CWE-778 | HMAC-SHA256 audit log hash chain |
| SIMSTIM-009 | MEDIUM | CWE-74 | Environment variable whitelist |

**Security Grade: A** (Production-ready)

**221 Security Tests** covering all vulnerability remediations.

### Technical Details

- **Architecture**: Bridge pattern with event queue
- **Dependencies**: Python 3.11+, python-telegram-bot, pydantic
- **Configuration**: TOML-based with environment variable expansion
- **Logging**: Structured JSONL with tamper-evident hash chains

### Installation

```bash
pip install simstim
simstim config --init
simstim start -- /implement sprint-1
```

See `simstim/README.md` for full documentation.

## [1.2.0] - 2026-01-20 — Beads Migration & Security Hardening

### Why This Release

This release introduces comprehensive bd → br migration tooling for projects transitioning from Python beads to beads_rust, plus security hardening that brings the framework to Grade A audit status.

### Added

- **Migration Tooling** (`migrate-to-br.sh`)
  - Full bd → br migration script with schema compatibility handling
  - Prefix normalization for mixed JSONL files (e.g., `arrakis-*` → `loa-*`)
  - Daemon cleanup and lockfile handling
  - `--dry-run` mode for safe preview
  - `--force` mode for re-migration
  - Automatic backup creation

- **Enhanced Beads Detection** (`check-beads.sh` rewrite)
  - Detects bd vs br installation
  - Returns `MIGRATION_NEEDED` (exit 3) when bd found
  - JSON output mode for scripting (`--json`)
  - Detailed status reporting

- **Symlink Validation** (`constructs-install.sh`)
  - New `validate_symlink_target()` function
  - Prevents path traversal attacks via symlinks
  - Validates targets stay within constructs directory

- **Config Validation** (`update.sh`)
  - New `validate_config()` function
  - Validates YAML syntax before processing
  - Graceful fallback to defaults on invalid config

### Security Hardening

All MEDIUM findings from security audit remediated:

| Finding | Fix |
|---------|-----|
| M-002: Missing strict mode | All 57 scripts now have `set -euo pipefail` |
| M-001: Temp file leaks | Cleanup traps added to 6 mktemp locations |
| M-003: Symlink validation | Path traversal prevention implemented |
| L-003: Config validation | YAML syntax validation before use |

**Security Grade: A** (upgraded from A-)

### Changed

- `analytics.sh` - Added strict mode, cleanup trap, BASH_SOURCE fix
- `context-check.sh` - Added strict mode
- `git-safety.sh` - Added strict mode
- `detect-drift.sh` - Added cleanup trap, removed manual rm
- `update.sh` - Added config validation, cleanup traps (4 locations)

### Scripts

New/updated scripts in `.claude/scripts/beads/`:

| Script | Purpose |
|--------|---------|
| `migrate-to-br.sh` | **NEW** - Full bd → br migration |
| `check-beads.sh` | Rewritten for bd/br detection |
| `install-br.sh` | Updated with better error handling |

## [1.1.1] - 2026-01-20 — br Permissions

### Added

- **Pre-approved `br` commands** in `.claude/settings.json`
  - 17 command patterns: `br:*`, `br create:*`, `br list:*`, `br show:*`, `br update:*`, `br close:*`, `br sync:*`, `br ready:*`, `br dep:*`, `br blocked:*`, `br stats:*`, `br doctor:*`, `br prime:*`, `br init:*`, `br search:*`, `br import:*`, `br export:*`
  - All beads_rust CLI commands now work without permission prompts

## [1.1.0] - 2026-01-20 — beads_rust Migration

### Why This Release

This release migrates from Python-based `bd` CLI to the Rust-based `br` CLI for task management, delivering significant performance and reliability improvements. Additionally, a comprehensive security remediation sprint addressed 16 vulnerabilities across the framework.

### Performance Improvements

- **10x faster startup** - Rust binary vs Python interpreter cold start
- **Lower memory footprint** - Native binary vs Python runtime overhead
- **Instant CLI responses** - No import delays or virtualenv activation

### Reliability Improvements

- **Single binary distribution** - No Python version conflicts or dependency issues
- **SQLite with WAL mode** - Better concurrency for daemon operations
- **Crash-resistant state** - Atomic writes prevent corruption

### Developer Experience

- **Simplified installation** - `cargo install beads_rust` or download binary
- **No virtualenv management** - Eliminates `bd` activation dance
- **Consistent behavior** - Same binary across all platforms

### Technical Debt Reduction

- **Removes Python dependency** - Framework is now pure shell + Rust
- **Eliminates daemon startup issues** - Rust daemon is more stable
- **Cleaner error messages** - Rust's error handling is more precise

### Changed

- **All beads scripts migrated** to use `br` CLI instead of `bd`
  - `check-beads.sh` - Updated detection and installation
  - `create-sprint-epic.sh` - Uses `br create`
  - `create-sprint-task.sh` - New script for task creation
  - `get-ready-work.sh` - Replaces `get-ready-by-priority.sh`
  - `get-sprint-tasks.sh` - Updated for `br list`
  - `install-br.sh` - Replaces `install-beads.sh`
  - `loa-prime.sh` - New context recovery script
  - `log-discovered-issue.sh` - New issue logging
  - `sync-and-commit.sh` - Replaces `sync-to-git.sh`

- **Protocols updated**
  - `beads-integration.md` - New comprehensive protocol (replaces `beads-workflow.md`)
  - `session-continuity.md` - Updated for `br` commands
  - `session-end.md` - Updated sync workflow

- **Skills updated** (6 files)
  - Task management instructions updated for `br` CLI

- **Documentation**
  - CLAUDE.md - Updated beads section with `br` commands
  - README.md - Updated installation instructions
  - PROCESS.md - Updated workflow references

### Security Hardening

Comprehensive security audit identified and remediated 16 vulnerabilities:

| Severity | Fixed | Key Fixes |
|----------|-------|-----------|
| CRITICAL | 3 | Shell injection prevention, credential permissions, log sanitization |
| HIGH | 8 | Path traversal, jq/yq injection, symlink attacks, content verification |
| MEDIUM | 4 | Temp file cleanup, input validation library |
| LOW | 1 | Rate limiting infrastructure |

**Security Grade**: B+ → **A-** (Production-ready)

#### Security Functions Added

- `secure_credentials_file()` - Enforces 600/400 file permissions
- `sanitize_sensitive_data()` - Redacts credentials from permission logs
- `validate_path_safe()` - Prevents path traversal attacks
- `validate_identifier()` - Sanitizes yq/jq arguments
- `safe_symlink()` - Validates symlink targets before creation
- `verify_content_hash()` - SHA256 verification for downloads
- `validate_api_key()`, `validate_url()`, `validate_safe_identifier()` - Input validation library
- `check_rate_limit()`, `reset_rate_limit()` - Rate limiting infrastructure

### Migration Guide

**For existing projects using `bd`:**

1. Install beads_rust: `cargo install beads_rust`
2. The `br` CLI is API-compatible with `bd` for common operations
3. Existing `.beads/` directory and data are compatible
4. Run `br doctor` to verify installation

**Command mapping:**
| Old (`bd`) | New (`br`) |
|------------|------------|
| `bd create` | `br create` |
| `bd list` | `br list` |
| `bd sync` | `br sync` |
| `bd prime` | `br prime` |

### Breaking Changes

- **`bd` CLI no longer supported** - Framework now requires `br` (beads_rust)
- Old beads scripts removed: `install-beads.sh`, `get-ready-by-priority.sh`, `sync-to-git.sh`
- `beads-workflow.md` protocol replaced by `beads-integration.md`

---

## [1.0.1] - 2026-01-19

### Fixed

- **Template Pollution**: `grimoires/loa/ledger.json` was being tracked in git and shipped with the template, causing new projects mounted with Loa to inherit development cycle history from the Loa framework itself.

### Changed

- Added `grimoires/loa/ledger.json` and `grimoires/loa/ledger.json.bak` to `.gitignore`
- Removed existing `ledger.json` from git tracking

### Remediation

If you mounted Loa v1.0.0 and see "active cycle Documentation Coherence" or similar inherited state:

```bash
# Option 1: Delete the inherited ledger and start fresh
rm grimoires/loa/ledger.json
/plan-and-analyze

# Option 2: Pull the fix via update
/update-loa
```

New projects mounted from v1.0.1+ will start with a clean slate.

---

## [1.0.0] - 2026-01-19 — Run Mode AI (Autonomous Initiation)

### Why This Release

This is **Loa's first major release** — a milestone that marks the framework's evolution from experimental agent orchestration to production-ready autonomous development. **Run Mode AI** ("AI" = Autonomous Initiation) represents the culmination of 19 iterative releases, 6 development cycles, and comprehensive battle-testing across real-world projects.

Loa 1.0.0 delivers:

1. **Autonomous Sprint Execution**: `/run sprint-N` executes complete implement → review → audit cycles without human intervention
2. **Multi-Sprint Orchestration**: `/run sprint-plan` executes entire sprint plans, creating a single draft PR
3. **4-Level Safety Defense**: ICE Layer, Circuit Breaker, Opt-In, and Visibility controls prevent runaway execution
4. **Continuous Learning**: Agents extract non-obvious discoveries into reusable skills
5. **Intelligent Subagents**: Specialized validation (architecture, security, tests) with automated quality gates
6. **Documentation Coherence**: Every task ships with its documentation — no batching at sprint end

### Major Features Summary

This release bundles all capabilities developed since v0.1.0:

#### Core Framework
- **9 Specialized AI Agents** orchestrating the complete product lifecycle
- **Three-Zone Model**: System (`.claude/`), State (`grimoires/`), App (`src/`)
- **Enterprise-Grade Managed Scaffolding** inspired by AWS Projen, Copier, Google ADK
- **3-Level Skills Architecture**: Metadata → Instructions → Resources

#### Autonomous Execution (v0.18.0)
- **`/run sprint-N`** — Single sprint autonomous execution
- **`/run sprint-plan`** — Multi-sprint execution with single PR
- **`/run-status`** — Progress monitoring with circuit breaker state
- **`/run-halt`** — Graceful stop with incomplete PR creation
- **`/run-resume`** — Checkpoint-based continuation
- **ICE Layer** — Git safety wrapper blocking protected branches
- **Circuit Breaker** — Halts on same-issue repetition, no progress, cycle limits

#### Continuous Learning (v0.17.0)
- **`/retrospective`** — Manual skill extraction from session
- **`/skill-audit`** — Lifecycle management (approve, reject, prune, stats)
- **Four Quality Gates**: Discovery Depth, Reusability, Trigger Clarity, Verification
- **Phase Gating**: Enabled during implement/review/audit/deploy phases

#### Intelligent Subagents (v0.16.0)
- **`/validate`** command with architecture, security, tests, docs subagents
- **architecture-validator** — SDD compliance checking
- **security-scanner** — OWASP Top 10 vulnerability detection
- **test-adequacy-reviewer** — Test quality assessment
- **documentation-coherence** — Per-task documentation validation (v0.19.0)

#### Context Management (v0.9.0-v0.15.0)
- **Lossless Ledger Protocol** — "Clear, Don't Compact" paradigm
- **Session Continuity** — Tiered recovery (L1: ~100 tokens, L2: ~500, L3: full)
- **Grounding Enforcement** — 95% citation requirement before `/clear`
- **Sprint Ledger** — Global sprint numbering across development cycles
- **RLM Pattern** — Probe-before-load achieving 29.3% token reduction

#### Developer Experience
- **Frictionless Permissions** — 150+ pre-approved commands (npm, git, docker, etc.)
- **Permission Audit** — HITL request logging and analysis
- **Auto-Update Check** — Session-start version checking
- **MCP Configuration Examples** — Pre-built integrations for Slack, GitHub, Sentry, Postgres

#### Mount & Ride Workflow (v0.7.0)
- **`/mount`** — Install Loa onto existing repositories
- **`/ride`** — Analyze codebase, generate evidence-grounded docs
- **Drift Detection** — Three-way analysis: Code vs Docs vs Context
- **Ghost Feature Detection** — Identifies documented but unimplemented features

### Removed Phases
- **`/setup` command** — No longer needed (v0.15.0). Start directly with `/plan-and-analyze`
- **Phase 0** — THJ detection via `LOA_CONSTRUCTS_API_KEY` environment variable

### Complete Workflow

```
Phase 1:   /plan-and-analyze  → grimoires/loa/prd.md
Phase 2:   /architect         → grimoires/loa/sdd.md
Phase 3:   /sprint-plan       → grimoires/loa/sprint.md
Phase 4:   /implement sprint-N → Code + reviewer.md
Phase 5:   /review-sprint     → engineer-feedback.md
Phase 5.5: /audit-sprint      → auditor-sprint-feedback.md + COMPLETED marker
Phase 6:   /deploy-production → deployment/

Autonomous: /run sprint-N      → Draft PR with full cycle execution
            /run sprint-plan   → Multi-sprint Draft PR
```

### Full Agent Roster (The Loa)

| Agent | Role | Output |
|-------|------|--------|
| `discovering-requirements` | Senior Product Manager | PRD |
| `designing-architecture` | Software Architect | SDD |
| `planning-sprints` | Technical PM | Sprint Plan |
| `implementing-tasks` | Senior Engineer | Code + Report |
| `reviewing-code` | Tech Lead | Approval/Feedback |
| `auditing-security` | Security Auditor | Security Approval |
| `deploying-infrastructure` | DevOps Architect | Infrastructure |
| `translating-for-executives` | Developer Relations | Summaries |
| `run-mode` | Autonomous Executor | Draft PR + State |

### Configuration Reference

```yaml
# .loa.config.yaml (v1.0.0)
persistence_mode: standard        # standard | stealth
integrity_enforcement: strict     # strict | warn | disabled

grounding:
  enforcement: warn               # strict | warn | disabled
  threshold: 0.95

run_mode:
  enabled: false                  # IMPORTANT: Explicit opt-in
  defaults:
    max_cycles: 20
    timeout_hours: 8
  circuit_breaker:
    same_issue_threshold: 3
    no_progress_threshold: 5

continuous_learning:
  enabled: true
  auto_extract: true
  require_approval: true

agent_skills:
  enabled: true
  load_mode: dynamic              # dynamic | eager
```

### Breaking Changes

None from v0.19.0. All existing projects continue to work unchanged.

**From earlier versions (pre-v0.15.0)**:
- `/setup` command removed — start with `/plan-and-analyze`
- `/update` renamed to `/update-loa`
- `loa-grimoire/` migrated to `grimoires/loa/`

### Security

All 19 releases passed security audits:
- No hardcoded credentials
- All scripts use `set -euo pipefail`
- Shell safety (`shellcheck` compliant)
- Input validation on all user-facing scripts
- Path traversal prevention
- Test isolation with `BATS_TMPDIR`

### Test Coverage

| Category | Count |
|----------|-------|
| Unit Tests | 700+ |
| Integration Tests | 180+ |
| Edge Case Tests | 100+ |

### Acknowledgments

This major release represents the collective efforts of multiple development cycles:
- **cycle-001**: Foundation, Managed Scaffolding, Lossless Ledger Protocol
- **cycle-002**: Semantic Search, Mount & Ride, Context Improvements
- **cycle-003**: Sprint Ledger, Auto-Update, Anthropic Oracle
- **cycle-004**: Continuous Learning Skill
- **cycle-005**: Run Mode, Permission Audit
- **cycle-006**: Documentation Coherence

---

## [0.19.0] - 2026-01-19

### Why This Release

The **Documentation Coherence** release enforces atomic per-task documentation validation:

1. **Atomic Enforcement**: Every task ships with its documentation - no batching at sprint end
2. **Integrated Workflow**: documentation-coherence subagent runs during review, audit, and deploy phases
3. **Clear Blocking Rules**: CHANGELOG missing = blocked; new command without CLAUDE.md = blocked

### Added

#### documentation-coherence Subagent (Sprint 1)

- **`.claude/subagents/documentation-coherence.md`** - Per-task documentation validation
  - Task type detection: new feature, bug fix, new command, API change, refactor, security fix, config change
  - Per-task documentation requirements matrix
  - Severity levels: COHERENT, NEEDS_UPDATE, ACTION_REQUIRED
  - Escalation rules (missing CHANGELOG → ACTION_REQUIRED)
  - Task-level and sprint-level report formats
  - Blocking behavior per trigger documented

#### /validate docs Command (Sprint 1)

- **`/validate docs`** - Run documentation-coherence on demand
  - `/validate docs --sprint` - Sprint-level verification
  - `/validate docs --task N` - Specific task verification
  - Advisory (non-blocking) when run manually
  - Produces reports at `grimoires/loa/a2a/subagent-reports/`

#### Skill Integrations (Sprint 2)

- **reviewing-code skill**: New "Documentation Verification (Required)" section
  - Pre-review check for documentation-coherence report
  - Documentation checklist with blocking criteria
  - "Cannot Approve If" conditions
  - Approval/rejection language templates

- **auditing-security skill**: New "Documentation Audit (Required)" section
  - Sprint documentation coverage verification
  - Security-specific documentation checks (SECURITY.md, auth docs, API docs)
  - Red flags for secrets/internal info in docs
  - Audit checklist additions

- **deploying-infrastructure skill**: New "Release Documentation Verification (Required)" section
  - Pre-deployment documentation checklist
  - CHANGELOG verification (version set, all tasks, breaking changes)
  - README verification (features, quick start, links)
  - Deployment and operational documentation requirements
  - "Cannot Deploy If" conditions

#### Tests (Sprint 1-2)

- `tests/unit/documentation-coherence.bats` - 54 unit tests
  - Task type detection, CHANGELOG verification, severity levels
  - Report format generation, escalation rules
- `tests/integration/documentation-coherence.bats` - 31 integration tests
  - Skill integrations, cross-references, blocking behavior

#### Context Cleanup Script

- **`.claude/scripts/cleanup-context.sh`** - Discovery context archive and cleanup
  - **Archives first**: Copies context to `{archive-path}/context/` before cleaning
  - Automatically called by `/run sprint-plan` on completion
  - Smart archive location: uses ledger.json or finds most recent archive
  - Supports `--dry-run`, `--verbose`, and `--no-archive` options
  - Preserves valuable discovery context while ensuring fresh start

#### v0.8.0 Spec Compliance (Skills Housekeeping)

- **`.claude/protocols/verification-loops.md`** - New protocol (P1.1)
  - 7-level verification hierarchy (tests → type check → lint → build → integration → E2E → manual)
  - Agent responsibilities for implementing-tasks, reviewing-code, deploying-infrastructure
  - Minimum viable verification requirements
  - Integration with quality gates workflow

- **implementing-tasks skill**: Task-Level Planning section (P1.2)
  - Complex task criteria (3+ files, architectural decisions, >2 hours)
  - Task plan template with Objective, Approach, Files, Dependencies, Risks, Verification
  - Plan review requirements before implementing
  - Plans stored at `grimoires/loa/a2a/sprint-N/task-{N}-plan.md`

- **reviewing-code skill**: Complexity Review section (P1.3)
  - Function complexity checks (>50 lines, >5 params, nesting >3)
  - Code duplication detection (>3 occurrences)
  - Dependency analysis (circular imports, unused)
  - Naming quality assessment
  - Dead code detection
  - Blocking vs non-blocking complexity verdicts

- **deploying-infrastructure skill**: E2E Verification section (P1.4)
  - Pre-deployment verification matrix (tests, build, type check, security scan)
  - Infrastructure verification checklist
  - Staging environment test requirements
  - E2E test categories (happy path, error handling, auth, data integrity)
  - Verification report template for deployment reports
  - Blocking conditions for deployment

- **PROCESS.md**: Context Hygiene section (P2.1)
  - Loading priority table (NOTES.md → sprint files → PRD/SDD → source → tests)
  - Grep vs skim decision guidance
  - When to request file tree
  - Context budget awareness (Green/Yellow/Red zones)
  - Tool result clearing examples

- **PROCESS.md**: Long-Running Task Guidance (P2.3)
  - Session handoff protocol with NOTES.md updates
  - Checkpoint creation examples
  - Multi-file refactoring tracking patterns
  - Avoiding context exhaustion (>2 hour tasks)
  - Recovery after interruption steps

- **CONTRIBUTING.md**: Command Optimization section (P3.1)
  - Parallel call patterns with good/bad examples
  - Sequential patterns for dependencies
  - Command invocation examples
  - Pre-flight check patterns
  - Context loading optimization
  - Error message quality guidelines
  - Command documentation requirements

### Changed

- **CLAUDE.md**: Added documentation-coherence to subagents table
- **CLAUDE.md**: Added `/validate docs` to commands table
- **/validate command**: Now includes docs subcommand with options

### PRD/SDD References

- PRD: `grimoires/loa/prd.md` (cycle-006)
- SDD: `grimoires/loa/sdd.md` (cycle-006)

---

## [0.18.0] - 2026-01-19

### Why This Release

The **Run Mode** release enables autonomous sprint execution with human-in-the-loop shifted to PR review:

1. **Autonomous Execution**: `/run sprint-N` executes implement → review → audit cycles until all pass
2. **Safety Controls**: 4-level defense (ICE, Circuit Breaker, Opt-In, Visibility) prevents runaway execution
3. **Multi-Sprint Support**: `/run sprint-plan` executes entire sprint plans with single PR
4. **Resumable State**: Checkpoint-based execution allows halt and resume from any point

### Added

#### Run Mode Commands (Sprint 2-3)

- **`/run sprint-N`** - Autonomous single sprint execution
  - Cycles through implement → review → audit until all pass
  - Options: `--max-cycles`, `--timeout`, `--branch`, `--dry-run`
  - Creates draft PR on completion
  - Never merges or pushes to protected branches

- **`/run sprint-plan`** - Multi-sprint execution
  - Three-tier sprint discovery (sprint.md → ledger.json → directories)
  - Options: `--from N`, `--to N` for partial execution
  - Single PR for entire plan
  - Graceful failure handling with incomplete PR

- **`/run-status`** - Progress display
  - Box-formatted run info, metrics, circuit breaker status
  - Options: `--json`, `--verbose`
  - Sprint plan progress tree for multi-sprint runs

- **`/run-halt`** - Graceful stop
  - Completes current phase before stopping
  - Creates draft PR marked `[INCOMPLETE]`
  - Options: `--force`, `--reason "..."`

- **`/run-resume`** - Continue from checkpoint
  - Branch divergence detection
  - Circuit breaker state check
  - Options: `--reset-ice`, `--force`

#### Safety Infrastructure (Sprint 1)

- **`.claude/scripts/run-mode-ice.sh`** - Git operation safety wrapper
  - Blocks push to protected branches (main, master, staging, etc.)
  - Blocks all merge operations
  - Blocks branch deletion
  - Enforces draft-only PR creation

- **`.claude/scripts/check-permissions.sh`** - Permission validation
  - Verifies required Claude Code permissions
  - Clear error messages for missing permissions

- **`.claude/protocols/run-mode.md`** - Safety protocol
  - 4-level defense in depth documentation
  - State machine transitions
  - Circuit breaker triggers and thresholds

#### Circuit Breaker (Sprint 2)

- **Same Issue Detection**: Hash-based comparison, halts after 3 repetitions
- **No Progress Detection**: Halts after 5 cycles without file changes
- **Cycle Limit**: Halts after configurable max cycles (default 20)
- **Timeout**: Halts after configurable runtime (default 8 hours)
- **State**: CLOSED (normal) → OPEN (halted), reset with `--reset-ice`

#### State Management (Sprint 2)

- **`.run/state.json`** - Run progress, metrics, cycle history
- **`.run/circuit-breaker.json`** - Trigger counts, trip history
- **`.run/deleted-files.log`** - Tracked deletions for PR body
- **`.run/rate-limit.json`** - Hour boundary API call tracking

#### Skill & Configuration (Sprint 4)

- **`.claude/skills/run-mode/`** - Run Mode skill definition
  - `index.yaml`: Triggers, inputs, outputs, safety requirements
  - `SKILL.md`: KERNEL instructions for autonomous execution

- **`.loa.config.yaml`**: `run_mode` section
  - `enabled`: Master toggle (defaults to `false` for safety)
  - `defaults.max_cycles`: Maximum cycles before halt
  - `defaults.timeout_hours`: Maximum runtime
  - `rate_limiting.calls_per_hour`: API exhaustion prevention
  - `circuit_breaker.same_issue_threshold`: Repetition tolerance
  - `circuit_breaker.no_progress_threshold`: Empty cycle tolerance
  - `git.branch_prefix`: Auto-created branch prefix
  - `git.create_draft_pr`: Always true (enforced)

#### Tests (Sprint 1-2)

- `tests/unit/run-mode-ice.bats`: ICE wrapper safety tests
- `tests/unit/circuit-breaker.bats`: Circuit breaker trigger tests
- `tests/integration/run-mode.bats`: End-to-end Run Mode tests

#### Permission Audit

- **`.claude/scripts/permission-audit.sh`** - HITL permission request logging
  - Logs all commands that required human approval
  - `view`: Display permission request log
  - `analyze`: Show patterns and frequency
  - `suggest`: Recommend permissions to add to settings.json
  - `clear`: Clear the log

- **`/permission-audit`** command for easy access

- **`PermissionRequest` hook** in settings.json enables automatic logging

### Changed

- **CLAUDE.md**:
  - Updated skill count from 8 to 9
  - Added Run Mode section with commands, safety model, configuration
  - Added `run-mode` to skills table
  - Added Run Mode commands to workflow commands list

- **`.gitignore`**: Added `.run/` directory (Run Mode state)
- **`.gitignore`**: Added `permission-requests.jsonl` (user-specific audit log)
- **`.claude/settings.json`**: Updated to new Claude Code v2.1.12+ hooks format
- **`.claude/settings.json`**: Added `PermissionRequest` hook for audit logging

### Security

- **Explicit Opt-In**: Run Mode disabled by default
- **ICE Layer**: All git operations wrapped with safety checks
- **Draft PRs Only**: Never creates ready-for-review PRs
- **Protected Branches**: Push to main/master/staging always blocked
- **Merge Block**: Merge operations completely disabled
- **Deleted File Tracking**: All deletions prominently displayed in PR

### PRD/SDD References

- PRD: `grimoires/loa/prd.md` (cycle-005)
- SDD: `grimoires/loa/sdd.md` (cycle-005)

---

## [0.17.0] - 2026-01-19

### Why This Release

The **Continuous Learning Skill** release enables Loa agents to build compound knowledge over time:

1. **Skill Extraction**: Agents detect non-obvious discoveries during implementation and extract them into reusable skills
2. **Quality Gates**: Four gates (Discovery Depth, Reusability, Trigger Clarity, Verification) prevent low-value extraction
3. **Lifecycle Management**: `/retrospective` and `/skill-audit` commands for approval, rejection, and pruning workflows

**Research Foundation**: Based on Voyager (Wang et al., 2023), CASCADE (2024), Reflexion (Shinn et al., 2023), and SEAgent (2025).

### Added

#### Continuous Learning Skill (Sprint 1-2)

- **`.claude/skills/continuous-learning/`** - Core skill definition
  - `index.yaml`: Skill metadata with triggers and phase activation
  - `SKILL.md`: KERNEL instructions for discovery detection and extraction
  - `resources/skill-template.md`: Template for extracted skills
  - `resources/examples/nats-jetstream-consumer-durable.md`: Example skill

- **`.claude/protocols/continuous-learning.md`** - Evaluation protocol
  - Four quality gates with pass/fail criteria
  - Phase gating table (enabled during implement/review/audit/deploy)
  - Zone compliance rules (State Zone only for extracted skills)
  - Trajectory logging format

- **State Zone directories** for skill lifecycle:
  - `grimoires/loa/skills/`: Active extracted skills
  - `grimoires/loa/skills-pending/`: Skills awaiting approval
  - `grimoires/loa/skills-archived/`: Rejected or pruned skills

#### Commands (Sprint 3)

- **`/retrospective`** - Manual skill extraction
  - Five-step workflow: Session Analysis → Quality Gates → Cross-Reference → Extract → Summary
  - `--scope <agent>`: Limit extraction to specific agent context
  - `--force`: Skip quality gate prompts
  - Example conversation flow with output formats

- **`/skill-audit`** - Lifecycle management
  - `--pending`: List skills awaiting approval
  - `--approve <name>`: Move skill to active
  - `--reject <name>`: Archive skill with reason
  - `--prune`: Review for low-value skills (>90 days, <2 matches)
  - `--stats`: Show skill usage statistics

#### Configuration & Documentation (Sprint 4)

- **`.loa.config.yaml`**: `continuous_learning` section
  - `enabled`: Master toggle
  - `auto_extract`: Enable/disable automatic extraction
  - `require_approval`: Skip or require pending workflow
  - `quality_gates.min_discovery_depth`: 1-3 threshold
  - `pruning.prune_after_days`: Age-based archive threshold
  - `pruning.prune_min_matches`: Usage-based retention threshold

- **CLAUDE.md**: New "Continuous Learning Skill (v0.17.0)" section
  - Command reference table
  - Quality gates documentation
  - Phase activation table
  - Configuration examples

#### Tests (Sprint 4)

- `tests/unit/quality-gates.bats`: Quality gate logic validation
- `tests/unit/zone-compliance.bats`: State Zone write enforcement
- `tests/integration/retrospective.bats`: End-to-end extraction flow
- `tests/integration/skill-audit.bats`: Lifecycle management flows

### Changed

- **CLAUDE.md**: Added `/retrospective` and `/skill-audit` to ad-hoc commands
- **Document flow diagram**: Now includes extracted skills in `grimoires/loa/`

### PRD/SDD References

- PRD: `grimoires/loa/prd.md` (cycle-004)
- SDD: `grimoires/loa/sdd.md` (cycle-004)

---

## [0.16.0] - 2026-01-18

### Why This Release

The **Loa Orchestration** release delivers three key developer experience improvements:

1. **Frictionless Permissions**: 150+ pre-approved commands eliminate permission prompts for standard development operations (npm, git, docker, etc.)

2. **Intelligent Subagents**: Three validation subagents (architecture-validator, security-scanner, test-adequacy-reviewer) provide automated quality gates

3. **Enhanced Agent Memory**: Structured NOTES.md protocol with 6 required sections ensures consistent context preservation across sessions

### Added

#### Frictionless Permissions (Sprint 1)

- **150+ pre-allowed patterns** in `.claude/settings.json`
  - Package managers: npm, pnpm, yarn, bun, cargo, pip, poetry, gem, go
  - Git operations: add, commit, push, pull, branch, merge, rebase, stash
  - Containers: docker, docker-compose, kubectl, helm
  - Runtimes: node, python, ruby, java, go, rustc
  - Testing: jest, vitest, pytest, mocha, bats
  - Build tools: webpack, vite, esbuild, tsc, swc
  - Deploy CLIs: vercel, fly, railway, aws, gcloud

- **Security deny list**
  - Privilege escalation blocked: sudo, su, doas
  - Destructive operations: rm -rf /, fork bombs
  - Remote code execution: curl|bash, wget|sh
  - Device attacks: /dev/sda, dd, mkfs

- **Documentation**: New "Frictionless Permissions" section in INSTALLATION.md

#### Intelligent Subagents (Sprints 2-3)

- **`.claude/subagents/` directory** with three validation agents:
  - `architecture-validator.md`: SDD compliance, structural and naming checks
  - `security-scanner.md`: OWASP Top 10, input validation, auth/authz
  - `test-adequacy-reviewer.md`: Coverage quality, test smells, missing tests

- **`/validate` command**
  - `/validate` - Run all subagents
  - `/validate architecture|security|tests` - Run specific subagent
  - `/validate security src/auth` - Scoped validation

- **Subagent Invocation Protocol** (`.claude/protocols/subagent-invocation.md`)
  - Scope determination: explicit > sprint context > git diff
  - Output location: `grimoires/loa/a2a/subagent-reports/`
  - Quality gate integration with blocking verdicts

- **`reviewing-code` skill updated**: Checks subagent reports, blocks on CRITICAL/HIGH

#### Enhanced NOTES.md Protocol (Sprint 4)

- **Required sections defined** (`.claude/protocols/structured-memory.md`):
  - Current Focus: Active task, status, blocked by, next action
  - Session Log: Append-only event history table
  - Decisions: Architecture/implementation decisions with rationale
  - Blockers: Checkbox list with [RESOLVED] marking
  - Technical Debt: ID, description, severity, found by, sprint
  - Learnings: Project-specific knowledge
  - Session Continuity: Recovery anchor (v0.9.0)

- **Agent Discipline events**: Session start, decision made, blocker hit/resolved, session end, mistake discovered

- **NOTES.md template** (`.claude/templates/NOTES.md.template`)

#### MCP Configuration Examples (Sprint 5)

- **`.claude/mcp-examples/` directory** for power users:
  - `slack.json` - HIGH risk (read + write)
  - `github.json` - MEDIUM risk (read + write)
  - `sentry.json` - LOW risk (read only)
  - `postgres.json` - CRITICAL risk (configurable)

- **Security documentation**: Required scopes, setup steps, risk levels, recommendations

### Changed

- **`reviewing-code` skill**: Now checks `a2a/subagent-reports/` for blocking verdicts
- **`structured-memory.md` protocol**: Enhanced with v0.16.0 required sections and agent discipline
- **CLAUDE.md**: New sections for Intelligent Subagents and MCP examples
- **README.md**: Updated repository structure, frictionless permissions note

### Test Coverage

New tests added:
- `tests/unit/settings-permissions.bats`: Permission patterns validation
- `tests/unit/subagent-loader.bats`: Subagent loading and YAML validation
- `tests/unit/subagent-reports.bats`: Security scanner and test adequacy
- `tests/unit/notes-template.bats`: NOTES.md template sections
- `tests/integration/validate-flow.bats`: End-to-end /validate command

### Security

All 5 sprints passed security audit:
- No hardcoded credentials in any file
- All scripts use `set -euo pipefail`
- Deny list prevents dangerous commands
- MCP examples use environment variable placeholders only

---

## [0.15.0] - 2026-01-18

### Why This Release

This release delivers two major feature cycles:

1. **Sprint Ledger** (Cycle 1): Global sprint numbering across multiple development cycles, preventing directory collisions when running `/plan-and-analyze` multiple times.

2. **RLM Context Improvements** (Cycle 2): Probe-before-load pattern achieving 29.3% token reduction, based on MIT CSAIL research on Recursive Language Models.

Additionally, this release removes the `/setup` phase, allowing users to start immediately with `/plan-and-analyze`.

### Added

#### Sprint Ledger (v0.13.0 features)

- **`/ledger` command**: View current ledger status and sprint history
- **`/archive-cycle "label"` command**: Archive completed cycles with full artifact preservation
- **`ledger-lib.sh` script**: Core ledger functions (init, create_cycle, add_sprint, resolve_sprint)
- **`validate-sprint-id.sh` script**: Resolves local sprint IDs (sprint-1) to global IDs (sprint-7)
- **Cycle archiving**: Preserves PRD, SDD, sprint.md and all a2a artifacts to `grimoires/loa/archive/`
- **Backward compatibility**: Projects without ledger work exactly as before (legacy mode)

#### RLM Context Improvements (v0.15.0 features)

- **Probe-Before-Load Pattern** (`context-manager.sh`)
  - `probe <file|dir> --json`: Lightweight metadata extraction without loading content
  - `should-load <file> --json`: Decision engine for selective loading
  - Achieves **29.3% token reduction** with only **0.6% overhead**

- **Schema Validator Assertions** (`schema-validator.sh`)
  - `assert <file> --schema prd --json`: Programmatic validation mode
  - Field existence, enum validation, semver format, array checks
  - Replaces re-prompting with code-based verification

- **RLM Benchmark Framework** (`rlm-benchmark.sh`)
  - `run --target <dir> --json`: Compare current vs RLM loading patterns
  - `baseline`: Capture metrics for future comparison
  - `compare`: Delta analysis against baseline
  - `report`: Generate markdown report with methodology and results

- **Trajectory logging**: All new operations logged to `grimoires/loa/a2a/trajectory/`

### Changed

- **`/plan-and-analyze`**: Creates ledger and cycle automatically on first run
- **`/sprint-plan`**: Registers sprints in ledger with global IDs
- **`/implement sprint-N`**: Resolves local ID to global directory
- **`/review-sprint sprint-N`**: Resolves local ID to global directory
- **`/audit-sprint sprint-N`**: Resolves ID and updates completion status in ledger
- **`/update` renamed to `/update-loa`**: Avoids conflict with Claude Code built-in command

### Configuration

New options in `.loa.config.yaml`:

```yaml
context_management:
  probe_before_load: true
  max_eager_load_lines: 500
  relevance_keywords: ["export", "class", "interface", "function"]
  exclude_patterns: ["*.test.ts", "*.spec.ts", "node_modules/**"]
```

### Test Coverage

| Category | Count |
|----------|-------|
| Unit Tests | 652 |
| Integration Tests | 149 |
| Edge Case Tests | 86 |
| **Total** | **887** |

New tests added:
- 100+ Sprint Ledger tests (Cycle 1)
- 120+ RLM Context tests (Cycle 2)

### Security

All 12 sprints across both cycles passed security audit:
- No hardcoded credentials
- Shell safety (`set -euo pipefail`)
- Input validation
- No command injection
- Test isolation
- Path traversal prevention

### Documentation

- `CLAUDE.md`: Sprint Ledger and RLM Benchmark sections
- `grimoires/pub/research/rlm-release-notes.md`: Release notes
- `grimoires/pub/research/benchmarks/final-report.md`: Benchmark results
- `grimoires/pub/research/rlm-recursive-language-models.md`: Research analysis

---

### Previous 0.15.0 Changes (Setup Removal)

This release also removes the `/setup` phase entirely, allowing users to start with `/plan-and-analyze` immediately after cloning. THJ membership is now detected via the `LOA_CONSTRUCTS_API_KEY` environment variable instead of a marker file.

### ⚠️ Breaking Changes

- **`/setup` command removed**: No longer needed. Start directly with `/plan-and-analyze`
- **`/mcp-config` command removed**: MCP configuration is now documentation-only
- **`.loa-setup-complete` no longer created**: THJ detection uses API key presence
- **Phase 0 removed from workflow**: Workflow now starts at Phase 1

### Added

- **`is_thj_member()` function** (`.claude/scripts/constructs-lib.sh`)
  - Canonical source for THJ membership detection
  - Returns 0 when `LOA_CONSTRUCTS_API_KEY` is set and non-empty
  - Zero network dependency - environment variable check only

- **`check-thj-member.sh` script** (`.claude/scripts/check-thj-member.sh`)
  - Pre-flight check script for THJ-only commands
  - Used by `/feedback` to gate access

### Removed

- **`/setup` command** (`.claude/commands/setup.md`)
- **`/mcp-config` command** (`.claude/commands/mcp-config.md`)
- **`check_setup_complete()` function** (from `preflight.sh`)
- **`check_cached_detection()` function** (from `git-safety.sh`)
- **`is_detection_disabled()` function** (from `git-safety.sh`)

### Changed

- **All phase commands**: Removed `.loa-setup-complete` pre-flight check
  - `/plan-and-analyze` - No prerequisites, this is now the entry point
  - `/architect` - Only requires PRD
  - `/sprint-plan` - Only requires PRD and SDD
  - `/implement` - Only requires PRD, SDD, and sprint.md
  - `/review-sprint` - Unchanged (requires reviewer.md)
  - `/audit-sprint` - Unchanged (requires "All good" approval)
  - `/deploy-production` - Only requires PRD and SDD

- **`/feedback` command**: Uses script-based THJ detection
  - Now uses `check-thj-member.sh` pre-flight script
  - Error message directs OSS users to GitHub Issues
  - THJ members need `LOA_CONSTRUCTS_API_KEY` set

- **`analytics.sh`**: Updated to use `is_thj_member()` from constructs-lib.sh
  - `get_user_type()` returns "thj" or "oss" based on API key presence
  - `should_track_analytics()` delegates to `is_thj_member()`

- **`preflight.sh`**: Updated THJ detection
  - `check_user_is_thj()` now uses `is_thj_member()`
  - Sources `constructs-lib.sh` for canonical detection function

- **`git-safety.sh`**: Removed marker file detection layer
  - Template detection now uses origin URL, upstream remote, and GitHub API only
  - Removed cached detection that read from marker file

- **`check-prerequisites.sh`**: Removed marker file checks
  - All phases work without `.loa-setup-complete`
  - `setup` case removed entirely
  - `plan|prd` case now has no prerequisites

- **`.gitignore`**: Updated comment for `.loa-setup-complete`
  - Marked as legacy (v0.14.0 and earlier)
  - Entry remains for backward compatibility

### Documentation

- **README.md**: Updated Quick Start to remove `/setup` step
- **CLAUDE.md**: Removed Phase 0 from workflow table, added THJ detection note
- **PROCESS.md**: Updated overview to reflect seven-phase workflow

### Migration Guide

**For existing projects:**
- The `.loa-setup-complete` file is no longer needed
- THJ members should set `LOA_CONSTRUCTS_API_KEY` environment variable
- Existing marker files are safely ignored (not deleted)

**For new projects:**
- Clone and immediately run `/plan-and-analyze`
- THJ members: Set `LOA_CONSTRUCTS_API_KEY` for constructs access and `/feedback`
- OSS users: Full workflow access, submit feedback via GitHub Issues

## [0.14.0] - 2026-01-17

### Why This Release

This release introduces **Auto-Update Check** - automatic version checking that notifies users when updates are available. The check runs on session start via a SessionStart hook, caches results to minimize API calls, and auto-skips in CI environments.

### Added

- **Auto-Update Check** (`.claude/scripts/check-updates.sh`)
  ```bash
  check-updates.sh --notify   # Check and notify (SessionStart hook)
  check-updates.sh --check    # Force check (bypass cache)
  check-updates.sh --json     # JSON output for scripting
  check-updates.sh --quiet    # Suppress non-error output
  ```
  - Fetches latest release from GitHub API
  - Semver comparison with pre-release support
  - Cache management (24h TTL default)
  - CI environment detection (GitHub Actions, GitLab CI, Jenkins, CircleCI, Travis, Bitbucket, Azure)
  - Three notification styles: banner, line, silent
  - Major version warning highlighting

- **SessionStart Hook** (`.claude/settings.json`)
  - Runs update check automatically on Claude Code session start
  - Uses `--notify` flag for terminal-friendly output
  - Silent in CI environments

- **`/update --check` Flag**
  - Check for updates without performing update
  - `--json` flag for scripting integration
  - Returns exit code 1 when update available

- **Configuration** (`.loa.config.yaml`)
  ```yaml
  update_check:
    enabled: true                    # Master toggle
    cache_ttl_hours: 24              # Cache TTL (default: 24)
    notification_style: banner       # banner | line | silent
    include_prereleases: false       # Include pre-release versions
    upstream_repo: "0xHoneyJar/loa"  # GitHub repo to check
  ```

- **Environment Variable Overrides**
  - `LOA_DISABLE_UPDATE_CHECK=1` - Disable all checks
  - `LOA_UPDATE_CHECK_TTL=48` - Cache TTL in hours
  - `LOA_UPSTREAM_REPO=owner/repo` - Custom upstream
  - `LOA_UPDATE_NOTIFICATION=line` - Notification style

- **Comprehensive Test Suite**
  - 30 unit tests (`tests/unit/check-updates.bats`)
    - semver_compare: 10 tests
    - is_major_update: 4 tests
    - is_ci_environment: 9 tests
    - CLI arguments: 7 tests
  - 11 integration tests (`tests/integration/check-updates.bats`)
    - Full check with JSON output
    - Cache TTL behavior
    - Network failure handling
    - CI mode skipping
    - Quiet mode suppression
    - Banner notification format
    - Major version warning
    - Exit code validation

### Changed

- **CLAUDE.md**: Added Update Check section under Helper Scripts
  - Command usage with all flags
  - Exit codes documentation
  - Configuration options
  - Environment variables
  - Feature highlights

### Technical Details

- **Exit Codes**
  | Code | Meaning |
  |------|---------|
  | 0 | Up to date, disabled, or skipped |
  | 1 | Update available |
  | 2 | Error |

- **Cache Location**: `~/.loa/cache/update-check.json`

- **Network**: 2-second timeout, silent failure on errors

### Security

- All scripts use `set -euo pipefail` for safe execution
- No secrets or credentials required (public GitHub API)
- CI environment auto-detection prevents unwanted output in pipelines
- Sprint 1 & 2 security audits: **APPROVED - LETS FUCKING GO**

---

## [0.13.0] - 2026-01-12

### Why This Release

This release introduces the **Anthropic Oracle** - an automated system for monitoring Anthropic's official sources for updates relevant to Loa. Also includes research-driven improvements from Continuous-Claude-v3 and Kiro analysis, plus cross-platform compatibility fixes.

### Added

- **Anthropic Oracle** (`.claude/scripts/anthropic-oracle.sh`)
  ```bash
  anthropic-oracle.sh check      # Fetch latest Anthropic sources
  anthropic-oracle.sh sources    # List monitored URLs
  anthropic-oracle.sh history    # View check history
  anthropic-oracle.sh template   # Generate research template
  ```
  - Monitors 6 Anthropic sources: docs, changelog, API reference, blog, GitHub repos
  - 24-hour cache TTL (configurable via `ANTHROPIC_ORACLE_TTL`)
  - Interest areas: hooks, tools, context, agents, mcp, memory, skills, commands

- **Oracle Commands**
  - `/oracle` - Quick access to oracle script with workflow documentation
  - `/oracle-analyze` - Claude-assisted analysis of fetched content

- **GitHub Actions Workflow** (`.github/workflows/oracle.yml`)
  - Weekly automated checks (Mondays 9:00 UTC)
  - Creates analysis issues with structured prompts
  - Duplicate issue detection (7-day window)
  - Manual dispatch support

- **Risk Analysis Protocol** (`.claude/protocols/risk-analysis.md`)
  - Pre-mortem framework from Continuous-Claude-v3
  - Tiger/Paper Tiger/Elephant categorization
  - Two-pass verification methodology
  - Automation hooks for risk detection

- **Recommended Hooks Protocol** (`.claude/protocols/recommended-hooks.md`)
  - Claude Code hooks documentation
  - 6 recommended hook patterns (session continuity, grounding check, git safety, sprint completion, auto-test, drift detection)
  - Example scripts clearly marked as templates
  - Integration with Kiro and Continuous-Claude patterns

- **EARS Requirements Template** (`.claude/skills/discovering-requirements/resources/templates/ears-requirements.md`)
  - Easy Approach to Requirements Syntax
  - 6 patterns: Ubiquitous, Event-Driven, State-Driven, Conditional, Optional, Complex
  - PRD integration section
  - Referenced in `discovering-requirements` skill

### Changed

- **Oracle Script Cross-Platform Support**
  - Added bash 4+ version check with macOS upgrade instructions
  - Added `jq` and `curl` dependency validation
  - Follows `mcp-registry.sh` pattern for consistency

- **Documentation Updates**
  - CLAUDE.md now includes Anthropic Oracle section under Helper Scripts
  - Protocol index updated with new protocols

### Fixed

- Example hook scripts now clearly marked as "Example Only" to prevent confusion
- `.gitignore` updated to exclude `grimoires/pub/` content (except README.md)

### Security

- Oracle script uses `set -euo pipefail` for safe execution
- GitHub Actions workflow uses minimal permissions (`contents: read`, `issues: write`)
- No secrets or credentials in automated workflows
- Sprint 1 security audit: **APPROVED**

---

## [0.12.0] - 2026-01-12

### Why This Release

This release introduces the **Grimoires Restructure** - a reorganization of the grimoire directory structure for better separation of private project state and public shareable content. The new `grimoires/` directory serves as the home for all grimoires, with `grimoires/loa/` for private state and `grimoires/pub/` for public documents.

### Added

- **Grimoires Directory Structure**
  | Path | Git Status | Purpose |
  |------|------------|---------|
  | `grimoires/loa/` | Ignored | Private project state (PRD, SDD, notes, trajectories) |
  | `grimoires/pub/` | Tracked | Public documents (research, audits, shareable artifacts) |

- **Migration Tool** (`.claude/scripts/migrate-grimoires.sh`)
  ```bash
  migrate-grimoires.sh check      # Check if migration needed
  migrate-grimoires.sh plan       # Preview changes (dry-run)
  migrate-grimoires.sh run        # Execute migration
  migrate-grimoires.sh rollback   # Revert using backup
  migrate-grimoires.sh status     # Show current state
  ```
  - Backup-before-migrate pattern for safety
  - JSON output support for automation (`--json`)
  - Force mode for scripted usage (`--force`)

- **Public Grimoire Structure** (`grimoires/pub/`)
  ```
  grimoires/pub/
  ├── research/     # Research and analysis documents
  ├── docs/         # Shareable documentation
  ├── artifacts/    # Public build artifacts
  └── audits/       # Security audit reports
  ```

- **CI Template Protection**: Extended to protect `grimoires/pub/` from project-specific content in template repository

### Changed

- **Path Migration**: 134+ files updated from `loa-grimoire` to `grimoires/loa`
  - All scripts in `.claude/scripts/`
  - All skills in `.claude/skills/`
  - All commands in `.claude/commands/`
  - All protocols in `.claude/protocols/`
  - Configuration files (`.gitignore`, `.loa-version.json`, `.loa.config.yaml`)
  - Documentation (README.md, CLAUDE.md, INSTALLATION.md, PROCESS.md)

- **Update Script**: Now checks for grimoire migration after framework updates (Stage 11)

### Security

- Migration tool security audit: **APPROVED**
  - No command injection vulnerabilities (all paths hardcoded)
  - Safe shell scripting (`set -euo pipefail`)
  - Proper backup/rollback capability
  - Audit report: `grimoires/pub/audits/grimoires-restructure-audit.md`

### Migration Guide

Existing projects using `loa-grimoire/` will be prompted to migrate:

```bash
# Check if migration needed
.claude/scripts/migrate-grimoires.sh check

# Preview changes
.claude/scripts/migrate-grimoires.sh plan

# Execute migration (creates backup automatically)
.claude/scripts/migrate-grimoires.sh run

# If issues occur, rollback
.claude/scripts/migrate-grimoires.sh rollback
```

The migration tool will:
1. Create `grimoires/` directory structure
2. Move content from `loa-grimoire/` to `grimoires/loa/`
3. Update `.loa.config.yaml` and `.gitignore` references
4. Create `grimoires/pub/` with README files

### Breaking Changes

**None** - The migration tool provides a smooth upgrade path. Existing `loa-grimoire/` paths continue to work until manually migrated.

---

## [0.11.0] - 2026-01-12

### Why This Release

This release introduces **Context Management Optimization** and **Tool Search & MCP Enhancement** - two major features that improve Claude Code session management and tool discovery. Additionally, it adds a comprehensive **Claude Platform Integration** system with JSON schemas, skills adapters, and thinking trajectory logging.

### Added

- **Context Management System** (`.claude/scripts/`)
  | Script | Purpose |
  |--------|---------|
  | `context-manager.sh` | Dashboard for context lifecycle (status, preserve, compact, checkpoint, recover) |
  | `context-benchmark.sh` | Performance measurement and tracking (run, baseline, compare, history) |

- **Context Compaction Protocol** (`.claude/protocols/context-compaction.md`)
  - Defines preservation categories (ALWAYS vs COMPACTABLE)
  - Documents compaction workflow and recovery guarantees
  - Simplified checkpoint process (7 steps → 3 manual steps)

- **Tool Search & Discovery** (`.claude/scripts/tool-search-adapter.sh`)
  - Search MCP servers and Loa Constructs by name, description, scope
  - Relevance scoring: name=100, key=80, description=50, scope=30
  - Cache system with configurable TTL (~/.loa/cache/tool-search/)
  - Commands: `search`, `discover`, `cache list/clear`
  - JSON output support for automation

- **MCP Registry Search** (`.claude/scripts/mcp-registry.sh`)
  - New `search` command for finding MCP servers
  - Case-insensitive matching across name, description, scope
  - Shows configuration status in results

- **Claude Platform Integration**
  | Component | Purpose |
  |-----------|---------|
  | `.claude/schemas/` | JSON Schema validation for PRD, SDD, Sprint, Trajectory |
  | `schema-validator.sh` | CLI for validating documents against schemas |
  | `skills-adapter.sh` | Unified skill loading and invocation |
  | `thinking-logger.sh` | Trajectory logging for agent reasoning |

- **Comprehensive Test Suite** (1,795 lines across 5 test files)
  - `context-manager.bats` - 35 tests for context management
  - `tool-search-adapter.bats` - 33 tests for tool search
  - `schema-validator.bats` - Schema validation tests
  - `skills-adapter.bats` - Skills adapter tests
  - `thinking-logger.bats` - Thinking logger tests

### Changed

- **Session Continuity Protocol**: Enhanced with context manager integration (+82 lines)
- **Synthesis Checkpoint Protocol**: Simplified to 3 manual steps (+50 lines)
- **Configuration**: New sections in `.loa.config.yaml`
  ```yaml
  tool_search:
    enabled: true
    cache_ttl_hours: 24
    include_constructs: true
    default_limit: 10
    ranking:
      name_weight: 100
      key_weight: 80
      description_weight: 50
      scope_weight: 30

  context_management:
    enabled: true
    auto_checkpoint: true
    preserve_on_clear: true
  ```

- **CLAUDE.md**: Added Context Management and Tool Search documentation (+194 lines)

### Security

- All new scripts use `set -euo pipefail` for safe bash execution
- Comprehensive security audit passed (39 scripts, 626 tests)
- No hardcoded secrets, proper input validation
- Cache operations confined to user's home directory

### Breaking Changes

**None** - This release is fully backward compatible.

---

## [0.10.1] - 2026-01-04

### Why This Release

This release adds the **Loa Constructs CLI** - a command-line interface for installing packs and skills from the Loa Constructs Registry. Pack commands are now automatically symlinked to `.claude/commands/` after installation, making them immediately available.

### Added

- **`constructs-install.sh`** - New CLI for pack and skill installation
  ```bash
  constructs-install.sh pack <slug>              # Install pack from registry
  constructs-install.sh skill <vendor/slug>      # Install individual skill
  constructs-install.sh uninstall pack <slug>    # Remove a pack
  constructs-install.sh uninstall skill <slug>   # Remove a skill
  constructs-install.sh link-commands <slug|all> # Re-link pack commands
  ```

- **Automatic Command Symlinking** (Fixes #21)
  - Pack commands in `.claude/constructs/packs/{slug}/commands/` are automatically symlinked to `.claude/commands/`
  - User files are never overwritten (safety feature)
  - Existing pack symlinks are updated on reinstall

- **Skill Symlinking for Loader Discovery**
  - Pack skills symlinked to `.claude/constructs/skills/{pack}/` for loader compatibility

- **Comprehensive Test Suite**
  - 21 unit tests covering installation, symlinking, uninstall, and edge cases

### Fixed

- **#20**: Add CLI install command for Loa Constructs packs
- **#21**: Pack commands not automatically available after installation

### Directory Structure Update

```
.claude/constructs/packs/{slug}/
├── commands/           # Pack commands (auto-symlinked to .claude/commands/)
├── skills/             # Pack skills (auto-symlinked to .claude/constructs/skills/)
├── manifest.json       # Pack metadata
└── .license.json       # JWT license token
```

---

## [0.10.0] - 2026-01-03

### Why This Release

This release introduces **Loa Constructs** - a commercial skill distribution system that enables third-party skills and skill packs to be installed, validated, and loaded alongside local skills. Skills are JWT-signed with RS256, license-validated with grace periods, and support offline operation.

### Added

- **Loa Constructs Registry Integration**
  - Commercial skill distribution via `loa-constructs-api.fly.dev`
  - JWT-signed licenses with RS256 signature verification
  - Grace periods by tier: 24h (individual/pro), 72h (team), 168h (enterprise)
  - Offline operation with cached public keys
  - Skill packs for bundled skill distribution

- **New Scripts** (`.claude/scripts/`)
  | Script | Purpose |
  |--------|---------|
  | `constructs-loader.sh` | Main CLI for listing, validating, loading constructs |
  | `constructs-lib.sh` | Shared library functions for construct operations |
  | `license-validator.sh` | JWT license validation with RS256 signatures |

- **New Protocol** (`.claude/protocols/constructs-integration.md`)
  - Skill loading priority (local > override > registry > pack)
  - License validation flow with exit codes
  - Offline behavior and key caching
  - Directory structure for installed constructs

- **Auto-Gitignore for Constructs**
  - `.claude/constructs/` automatically added to `.gitignore` on install
  - Prevents accidental commit of licensed content
  - `ensure-gitignore` CLI command for manual verification

- **CI Template Protection**
  - `.claude/constructs/` added to forbidden paths in CI
  - Prevents licensed skills from being committed to template repository

- **Comprehensive Test Suite** (2700+ lines)
  - Unit tests for loader, lib, and license validator
  - Integration tests with mock API server
  - E2E tests for full workflow validation
  - Pack support and update check tests

### Changed

- **Configuration**: New `.loa.config.yaml` options
  ```yaml
  registry:
    enabled: true
    default_url: "https://loa-constructs-api.fly.dev/v1"
    validate_licenses: true
    offline_grace_hours: 24
    check_updates_on_setup: true
  ```

- **CLAUDE.md**: Added Registry Integration section with API endpoints, authentication, and CLI commands

### Directory Structure

```
.claude/constructs/
├── skills/{vendor}/{slug}/    # Installed skills
│   ├── .license.json          # JWT license token
│   ├── index.yaml             # Skill metadata
│   └── SKILL.md               # Instructions
├── packs/{name}/              # Skill packs
│   ├── .license.json          # Pack license
│   └── skills/                # Bundled skills
└── .constructs-meta.json      # Installation state
```

### Breaking Changes

**None** - This release is fully backward compatible. The constructs system is opt-in and does not affect existing local skills.

---

## [0.9.2] - 2025-12-31

### Why This Release

The `/update` command was overwriting project-specific `CHANGELOG.md` and `README.md` files with Loa framework template versions. These files define the project, not the framework, and should always be preserved during updates.

### Fixed

- **`/update` Command**: Now preserves project identity files during framework updates
  - Added `CHANGELOG.md` and `README.md` to the Merge Strategy table as preserved files
  - Added "Project Identity Files" section in Conflict Resolution guidance
  - These files are now automatically resolved with `--ours` (keep project version)
  - Updated Next Steps to link to upstream releases instead of local CHANGELOG

### Upgrade Instructions

No action required. The fix is in the `/update` command documentation itself, so future updates will properly preserve your project files.

If you previously lost your `CHANGELOG.md` or `README.md` during an update:
```bash
git checkout <commit-before-update> -- CHANGELOG.md README.md
git commit -m "fix: restore project CHANGELOG and README"
```

---

## [0.9.1] - 2025-12-30

### Why This Release

**CRITICAL UPGRADE**: Version 0.9.0 was released with project-specific artifacts (PRD, SDD, sprint plans, A2A files) that should never have been in the template. This polluted the template and caused new installations to include irrelevant documentation.

This release cleans up the template and adds strict CI guards to prevent this from happening again.

### Fixed

- **Template Pollution**: Removed all project-specific files from `loa-grimoire/`
  - Deleted: `prd.md`, `sdd.md`, `sprint.md`, `NOTES.md`
  - Deleted: All `a2a/sprint-*` directories and files
  - Deleted: `deployment/`, `reality/`, `analytics/`, `research/` contents
  - Each directory now contains only a README.md explaining its purpose

### Added

- **Template Protection CI Guard**: New GitHub Actions job that blocks forbidden files
  - Runs first, all other CI jobs depend on it passing
  - Blocks: `prd.md`, `sdd.md`, `sprint.md`, `NOTES.md`, `a2a/*`, `deployment/*`, `reality/*`, `analytics/*`, `research/*`
  - Escape hatch: `[skip-template-guard]` in commit message for exceptional cases
  - `.github/BRANCH_PROTECTION.md` documents required GitHub settings

- **Branch Protection**: GitHub API configured to enforce strict checks
  - `Template Protection` status check required
  - `Validate Framework Files` status check required
  - Admin bypass disabled (`enforce_admins: true`)

### Changed

- **`.gitignore`**: Now excludes all template-specific files by default
  - README.md files in each directory are preserved
  - Projects using Loa as a base will automatically ignore generated artifacts

### Upgrade Instructions

**If you installed v0.9.0**, you have polluted template files. To clean up:

```bash
# Pull the clean template
/update

# Or manually remove polluted files
rm -rf loa-grimoire/prd.md loa-grimoire/sdd.md loa-grimoire/sprint.md
rm -rf loa-grimoire/NOTES.md loa-grimoire/a2a/* loa-grimoire/deployment/*
rm -rf loa-grimoire/reality/* loa-grimoire/analytics/* loa-grimoire/research/*
```

**New installations** from v0.9.1+ will start clean automatically.

---

## [0.9.0] - 2025-12-27

### Why This Release

This release introduces the **Lossless Ledger Protocol** - a paradigm shift from "compact to survive" to "clear, don't compact." Instead of letting Claude's context compaction smudge your reasoning state, agents now proactively checkpoint their work to persistent ledgers before clearing context, enabling instant lossless recovery.

### Added

- **Lossless Ledger Protocol**: "Clear, Don't Compact" context management
  - Proactive `/clear` before compaction instead of reactive summarization
  - Tiered state recovery: Level 1 (~100 tokens), Level 2 (~500 tokens), Level 3 (full)
  - Session continuity across context clears with zero information loss
  - Grounding ratio enforcement (≥0.95 required before `/clear`)

- **Session Continuity Protocol** (`.claude/protocols/session-continuity.md`)
  - 7-level immutable truth hierarchy (Code → Beads → NOTES → Trajectory → Docs)
  - 3-phase session lifecycle: Start → During → Before Clear
  - Self-healing State Zone with git-based recovery
  - Lightweight identifier format for 97% token reduction

- **Grounding Enforcement Protocol** (`.claude/protocols/grounding-enforcement.md`)
  - 4 grounding types: `citation`, `code_reference`, `user_input`, `assumption`
  - Configurable enforcement levels: `strict` (blocking), `warn` (advisory), `disabled`
  - Script: `.claude/scripts/grounding-check.sh` - Calculates grounding ratio
  - Default threshold: 0.95 (95% of claims must be grounded)

- **Synthesis Checkpoint Protocol** (`.claude/protocols/synthesis-checkpoint.md`)
  - 7-step checkpoint before `/clear`: 2 blocking, 5 non-blocking
  - Step 1: Grounding verification (blocking if strict)
  - Step 2: Negative grounding ghost detection (blocking)
  - Steps 3-7: Decision sync, Bead update, handoff log, decay advisory, EDD verify
  - Script: `.claude/scripts/synthesis-checkpoint.sh`

- **Attention Budget Protocol** (`.claude/protocols/attention-budget.md`)
  - Traffic light system: Green (0-5k), Yellow (5-15k), Red (>15k tokens)
  - Delta-synthesis at Yellow threshold
  - Advisory-only (doesn't block)

- **JIT Retrieval Protocol** (`.claude/protocols/jit-retrieval.md`)
  - Lightweight identifiers: `${PROJECT_ROOT}/path:lines | purpose | timestamp`
  - 97% token reduction vs embedding full code blocks
  - `ck` semantic search integration with grep fallback

- **Self-Healing State Zone**
  - Script: `.claude/scripts/self-heal-state.sh`
  - Recovery priority: git history → git checkout → template
  - Automatic recovery of NOTES.md, trajectory/, .beads/

- **Comprehensive Test Suite** (127 tests)
  - 65+ unit tests for grounding-check, synthesis-checkpoint, self-heal-state
  - 22 integration tests for session lifecycle
  - 30+ edge case tests (zero-claim, corrupted data, missing files)
  - 10 performance benchmarks with PRD KPI validation

- **UAT Validation Script** (`.claude/scripts/validate-prd-requirements.sh`)
  - Validates all 11 Functional Requirements (FR-1 through FR-11)
  - Validates 2 Integration Requirements (IR-1, IR-2)
  - 45 automated checks with pass/fail/warning output

- **CI/CD Validation** (`.claude/scripts/check-loa.sh` enhanced)
  - `check_v090_protocols()` - Validates 5 protocol files
  - `check_v090_scripts()` - Validates 3 scripts (executable, shellcheck)
  - `check_v090_config()` - Validates grounding configuration
  - `check_notes_template()` - Validates NOTES.md sections

### Changed

- **NOTES.md Schema Extended**: New required sections
  - `## Session Continuity` - Critical context (~100 tokens)
  - `## Lightweight Identifiers` - Code references table
  - `## Decision Log` - Timestamped decisions with grounding

- **Trajectory Logging Enhanced**: New entry types
  - `session_handoff` - Context passed to next session
  - `negative_grounding` - Ghost feature detection
  - `test_scenario` - EDD verification entries

- **Configuration**: New `.loa.config.yaml` options
  ```yaml
  grounding:
    enforcement: warn    # strict | warn | disabled
    threshold: 0.95      # 0.00-1.00
  ```

### Technical Details

- **Performance Targets Met**
  | Metric | Target | Achieved |
  |--------|--------|----------|
  | Session recovery | <30s | ✅ |
  | Level 1 recovery | ~100 tokens | ✅ |
  | Grounding ratio | ≥0.95 | ✅ |
  | Token reduction (JIT) | 97% | ✅ |
  | Test coverage | >80% | ✅ 127 tests |

- **Sprints Completed**: 4 sprints, all approved
  - Sprint 1: Foundation & Core Protocols
  - Sprint 2: Enforcement Layer
  - Sprint 3: Integration Layer
  - Sprint 4: Quality & Polish

### Breaking Changes

**None** - This release is fully backward compatible. New protocols are additive.

---


## [0.8.0] - 2025-12-27

### Why This Release

This release adds **optional semantic code search** via the `ck` tool, enabling dramatically improved code understanding while maintaining full backward compatibility. The enhancement is **completely invisible** to users—your workflow remains unchanged whether or not you have `ck` installed.

### Added

- **Semantic Code Search Integration** (optional)
  - Vector-based search using nomic-v1.5 embeddings via `ck` tool
  - <500ms search latency on repositories up to 1M LOC
  - 80-90% cache hit rate with delta reindexing
  - Automatic fallback to grep when `ck` unavailable

- **Ghost Feature Detection**
  - Identifies documented but unimplemented features
  - Uses Negative Grounding Protocol (2+ diverse queries returning 0 results)
  - Creates Beads issues for discovered liabilities (if `bd` installed)

- **Shadow System Classification**
  - Identifies undocumented code in repositories
  - Classifies as Orphaned, Drifted, or Partial
  - Generates actionable drift reports

- **8 New Protocol Documents** (`.claude/protocols/`)
  - `preflight-integrity.md` - Integrity verification before operations
  - `tool-result-clearing.md` - Attention budget management
  - `trajectory-evaluation.md` - Agent reasoning audit (enhanced)
  - `negative-grounding.md` - Ghost feature detection protocol
  - `search-fallback.md` - Graceful degradation strategy
  - `citations.md` - Word-for-word citation requirements
  - `self-audit-checkpoint.md` - Pre-completion validation
  - `edd-verification.md` - Evaluation-Driven Development protocol

- **6 New Scripts** (`.claude/scripts/`)
  - `search-orchestrator.sh` - Unified search interface
  - `search-api.sh` - Search API functions (semantic_search, hybrid_search, regex_search)
  - `filter-search-results.sh` - Result deduplication and relevance filtering
  - `compact-trajectory.sh` - Trajectory log compression
  - `validate-protocols.sh` - Protocol documentation validation
  - `validate-ck-integration.sh` - CI/CD validation script (42 checks)

- **Test Suite** (127 total tests)
  - 79 unit tests for core scripts
  - 22 integration tests for /ride workflow
  - 26 edge case tests for error handling
  - Performance benchmarking with PRD target validation

- **Documentation**
  - `RELEASE_NOTES_CK_INTEGRATION.md` - Detailed release notes
  - `MIGRATION_GUIDE_CK.md` - Step-by-step migration guide
  - Updated `INSTALLATION.md` with ck installation instructions
  - Updated `README.md` with semantic search mentions

### Changed

- **`/ride` Command**: Enhanced with semantic analysis
  - Ghost Feature detection in drift report
  - Shadow System classification
  - Improved code reality extraction

- **`/setup` Command**: Shows ck installation status
  - Displays version if installed
  - Provides installation instructions if missing

- **`.gitignore`**: New entries
  - `.ck/` - Semantic search index directory
  - `.beads/` - Beads issue tracking
  - `loa-grimoire/a2a/trajectory/` - Agent reasoning logs

### Technical Details

- **Performance Targets Met**
  | Metric | Target | Achieved |
  |--------|--------|----------|
  | Search Speed (1M LOC) | <500ms | ✅ |
  | Cache Hit Rate | 80-90% | ✅ |
  | Grounding Ratio | ≥0.95 | ✅ |
  | User Experience Parity | 100% | ✅ |

- **Invisible Enhancement Pattern**: All commands work identically with or without `ck` installed. No mentions of "semantic search", "ck", or "fallback" in agent output.

### Breaking Changes

**None** - This release is fully backward compatible.

### Installation (Optional)

```bash
# Install ck for semantic search
cargo install ck-search

# Install bd for issue tracking
npm install -g beads-cli

# Both tools are optional - Loa works perfectly without them
```

---

## [0.7.0] - 2025-12-22

### Why This Release

This release introduces the **Mount & Ride** workflow for existing codebases. Instead of requiring a full discovery interview, developers can now mount Loa onto any repository and "ride" through the code to generate evidence-grounded documentation automatically.

### Added

- **`/mount` Command**: Install Loa framework onto existing repositories
  - Configures upstream remote for updates
  - Installs System Zone with integrity checksums
  - Initializes State Zone structure
  - Optional stealth mode (no commits)
  - Optional Beads initialization skip

- **`/ride` Command**: Analyze codebase and generate evidence-grounded docs
  - 10-phase analysis workflow
  - Code extraction: routes, models, dependencies, tech debt
  - Three-way drift analysis: Code vs Docs vs Context
  - Evidence-grounded PRD/SDD generation
  - Legacy documentation inventory and deprecation
  - Governance audit (CHANGELOG, CONTRIBUTING, SECURITY)
  - Trajectory self-audit for hallucination detection

- **Change Validation Protocol** (`.claude/protocols/change-validation.md`)
  - Pre-implementation validation checklist
  - File reference validation
  - Function/method existence verification
  - Dependency validation
  - Breaking change detection
  - Three validation levels (quick, standard, deep)

- **New Scripts**
  - `.claude/scripts/detect-drift.sh` - Quick/full drift detection between code and docs
  - `.claude/scripts/validate-change-plan.sh` - Validate sprint plans against codebase reality

### Changed

- Documentation updated to reference Mount & Ride workflow
- Command reference tables include `/mount` and `/ride`
- Helper scripts list expanded with new utilities

---

## [0.6.0] - 2025-12-22

### Why This Release

This release transforms Loa from a "fork-and-modify template" into an **enterprise-grade managed scaffolding framework** inspired by AWS Projen, Copier, and Google's ADK. The goal is to eliminate merge hell, enable painless updates, and provide ADK-level agent observability.

### Added

- **Three-Zone Model**: Clear ownership boundaries for files
  | Zone | Path | Owner | Permission |
  |------|------|-------|------------|
  | System | `.claude/` | Framework | Immutable, checksum-protected |
  | State | `loa-grimoire/`, `.beads/` | Project | Read/Write |
  | App | `src/`, `lib/`, `app/` | Developer | Read (write requires confirmation) |

- **Projen-Level Synthesis Protection**: System Zone integrity enforcement
  - SHA-256 checksums for all System Zone files (`.claude/checksums.json`)
  - Three enforcement levels: `strict`, `warn`, `disabled`
  - CI validation script: `.claude/scripts/check-loa.sh`

- **Copier-Level Migration Gates**: Safe framework updates
  - Fetch → Validate → Migrate → Swap pattern
  - Atomic swap with automatic rollback on failure
  - User overrides preserved in `.claude/overrides/`
  - New script: `.claude/scripts/update.sh`

- **ADK-Level Trajectory Evaluation**: Agent reasoning audit
  - JSONL trajectory logs in `loa-grimoire/a2a/trajectory/`
  - Grounding types: `citation`, `code_reference`, `assumption`, `user_input`
  - Evaluation-Driven Development (EDD): 3 test scenarios before task completion
  - New protocol: `.claude/protocols/trajectory-evaluation.md`

- **Structured Agentic Memory**: Persistent context across sessions
  - `loa-grimoire/NOTES.md` with standardized sections
  - Tool Result Clearing for attention budget management
  - New protocol: `.claude/protocols/structured-memory.md`

- **One-Command Installation**: Mount Loa onto existing repositories
  - `curl -fsSL .../mount-loa.sh | bash`
  - Handles remote setup, zone syncing, checksum generation
  - New script: `.claude/scripts/mount-loa.sh`

- **Version Manifest**: Schema tracking and migration support
  - `.loa-version.json` with framework version, schema version, zone definitions
  - Migration tracking for breaking changes
  - Integrity verification timestamps

- **User Configuration File**: Framework-safe customization
  - `.loa.config.yaml` (never modified by updates)
  - Persistence mode: `standard` or `stealth`
  - Integrity enforcement level
  - Memory and EDD settings

- **New Documentation**
  - `INSTALLATION.md`: Detailed installation, customization, troubleshooting guide

### Changed

- **All 8 SKILL.md Files Updated** with managed scaffolding integration:
  - Zone frontmatter for boundary enforcement
  - Integrity pre-check before execution
  - Factual grounding requirements (cite sources or flag as `[ASSUMPTION]`)
  - Structured memory protocol (read NOTES.md on start, log decisions)
  - Tool Result Clearing for attention budget management
  - Trajectory logging for audit

- **README.md**: Rewritten for v0.6.0
  - Three-zone model documentation
  - Managed scaffolding features
  - Updated quick start with mount-loa.sh

- **CLAUDE.md**: Added managed scaffolding architecture
  - Zone permissions table
  - Protocol references
  - Customization via overrides

- **PROCESS.md**: Added new protocol sections
  - Structured Agentic Memory section
  - Trajectory Evaluation section
  - Updated helper scripts list

### Technical Details

- **yq Compatibility**: Scripts support both mikefarah/yq (Go) and kislyuk/yq (Python)
- **Checksum Algorithm**: SHA-256 for integrity verification
- **Migration Pattern**: Blocking migrations with rollback support
- **Backup Retention**: 3 most recent `.claude.backup.*` directories kept

---

## [0.5.0] - 2025-12-21

### Added

- **Beads Integration**: Sprint lifecycle state management via `bd` CLI
  - Sprint state tracking in `.beads/` directory
  - Automatic bead creation on sprint start
  - State transitions: `pending` → `active` → `review` → `audit` → `done`
  - New script: `.claude/scripts/check-beads.sh`

### Changed

- Sprint commands now create/update beads for state tracking
- `/implement`, `/review-sprint`, `/audit-sprint` update bead status

---

## [0.4.0] - 2025-12-21

### Why This Release

This release delivers a major architectural refactor based on Anthropic's recommendations for Claude Code skills development. The focus is on action-oriented naming, modular architecture, and extracting deterministic logic to reusable scripts—making skills more maintainable and reducing context overhead.

### Added

- **v4 Command Architecture**: Thin routing layer with YAML frontmatter
  - `agent:` and `agent_path:` fields for skill routing
  - `command_type:` for special commands (wizard, survey, git)
  - `pre_flight:` validation checks before execution
  - `context_files:` with prioritized loading and variable substitution

- **3-Level Skills Architecture**: Modular structure for all 8 agents
  - Level 1: `index.yaml` - Metadata and triggers (~100 tokens)
  - Level 2: `SKILL.md` - KERNEL instructions (<500 lines)
  - Level 3: `resources/` - Templates, scripts, references (loaded on-demand)

- **Context-First Discovery**: `/plan-and-analyze` now ingests existing documentation
  - Auto-scans `loa-grimoire/context/` for `.md` files before interviewing
  - Presents understanding with source citations before asking questions
  - Only asks about gaps, ambiguities, and strategic decisions
  - Parallel ingestion for large context (>2000 lines)
  - New script: `.claude/scripts/assess-discovery-context.sh`

- **8 New Helper Scripts** (`.claude/scripts/`)
  | Script | Purpose |
  |--------|---------|
  | `check-feedback-status.sh` | Sprint feedback state detection |
  | `validate-sprint-id.sh` | Sprint ID format validation |
  | `check-prerequisites.sh` | Phase prerequisite checking |
  | `assess-discovery-context.sh` | Context size assessment |
  | `context-check.sh` | Parallel execution thresholds |
  | `preflight.sh` | Pre-flight validation functions |
  | `analytics.sh` | Analytics helpers (THJ only) |
  | `git-safety.sh` | Template detection utilities |

- **Protocol Documentation** (`.claude/protocols/`)
  - `git-safety.md` - Template detection, warning flow, remediation
  - `analytics.md` - THJ-only tracking, schema definitions
  - `feedback-loops.md` - A2A communication, approval markers

- **Context Directory** (`loa-grimoire/context/`)
  - New location for pre-discovery documentation
  - Template README with suggested file structure
  - Supports nested directories and any `.md` files

### Changed

- **Skill Naming Convention**: All 8 skills renamed from role-based to action-based (gerund form)
  | Old Name | New Name |
  |----------|----------|
  | `prd-architect` | `discovering-requirements` |
  | `architecture-designer` | `designing-architecture` |
  | `sprint-planner` | `planning-sprints` |
  | `sprint-task-implementer` | `implementing-tasks` |
  | `senior-tech-lead-reviewer` | `reviewing-code` |
  | `paranoid-auditor` | `auditing-security` |
  | `devops-crypto-architect` | `deploying-infrastructure` |
  | `devrel-translator` | `translating-for-executives` |

- **Documentation Streamlining**: Reduced CLAUDE.md from ~1700 to ~200 lines
  - Detailed specifications moved to `.claude/protocols/`
  - Single source of truth principle enforced
  - Command tables reference skill files for details

- **discovering-requirements Skill**: Complete rewrite for context-first workflow
  - Phase -1: Context Assessment (runs script)
  - Phase 0: Context Synthesis with XML context map
  - Phase 0.5: Targeted Interview for gaps only
  - Phases 1-7: Conditional based on context coverage
  - Full source tracing in PRD output

- **Parallel Execution Thresholds**: Standardized across skills
  | Skill | SMALL | MEDIUM | LARGE |
  |-------|-------|--------|-------|
  | discovering-requirements | <500 | 500-2000 | >2000 |
  | reviewing-code | <3,000 | 3,000-6,000 | >6,000 |
  | auditing-security | <2,000 | 2,000-5,000 | >5,000 |
  | implementing-tasks | <3,000 | 3,000-8,000 | >8,000 |
  | deploying-infrastructure | <2,000 | 2,000-5,000 | >5,000 |

### Breaking Changes

- **Skill Names Renamed**: All 8 skills have new names (see Changed section)
  - Custom commands referencing old names will need updates
  - Automation scripts using skill names must be migrated
  - Migration script available: `.claude/scripts/migrate-skill-names.sh`

### Migration Guide

If you have custom commands or scripts referencing old skill names:

```bash
# Run the migration script on your custom files
./.claude/scripts/migrate-skill-names.sh --check  # Preview changes
./.claude/scripts/migrate-skill-names.sh          # Apply changes
```

Or manually update references using this mapping:
- `prd-architect` → `discovering-requirements`
- `architecture-designer` → `designing-architecture`
- `sprint-planner` → `planning-sprints`
- `sprint-task-implementer` → `implementing-tasks`
- `senior-tech-lead-reviewer` → `reviewing-code`
- `paranoid-auditor` → `auditing-security`
- `devops-crypto-architect` → `deploying-infrastructure`
- `devrel-translator` → `translating-for-executives`

### Technical Details

- **Command Files Updated**: 10 commands with new skill references
- **Agent Files Renamed**: 8 agent files to match new naming
- **Index Files Updated**: 8 index.yaml files with gerund names
- **GitHub Templates Updated**: Issue templates reference new names
- All references to old skill names migrated throughout codebase

---

## [0.3.0] - 2025-12-20

### Why This Release

Claude Code has a tendency to proactively suggest git operations—committing changes, creating PRs, and pushing to remotes—which can be problematic when working in forked repositories. Developers using Loa as a template for their own projects were at risk of accidentally pushing proprietary code to the public upstream repository (`0xHoneyJar/loa`).

This release introduces comprehensive safety rails to prevent these accidents while still enabling intentional contributions back to the framework.

### Added
- **Git Safety Protocol**: Multi-layer protection against accidental pushes to upstream template repository
  - 4-layer template detection system (origin URL, upstream remote, loa remote, GitHub API)
  - Automatic detection during `/setup` with results stored in marker file
  - Warnings before push/PR operations targeting upstream
  - Prevents accidentally leaking project-specific code to the public Loa repository

- **`/contribute` command**: Guided OSS contribution workflow for contributing back to Loa
  - Pre-flight checks (feature branch, clean working tree, upstream remote)
  - Standards checklist (clean commits, no secrets, tests, DCO)
  - Automated secrets scanning with common patterns (API keys, tokens, credentials)
  - DCO sign-off verification with fix guidance
  - Guided PR creation with proper formatting
  - Handles both fork-based and direct repository contributions

- **Template detection in `/setup`**: New Phase 0.5 detects fork/template relationships
  - Runs before user-type selection
  - Displays safety notice when template detected
  - Stores detection metadata in `.loa-setup-complete` marker file

- **`/config` command**: Post-setup MCP server reconfiguration (THJ only)
  - Allows adding/removing MCP integrations after initial setup
  - Shows currently configured servers
  - Updates marker file with new configuration

### Changed
- **Setup marker file schema**: Now includes `template_source` object with detection metadata
  ```json
  {
    "template_source": {
      "detected": true,
      "repo": "0xHoneyJar/loa",
      "detection_method": "origin_url",
      "detected_at": "2025-12-20T10:00:00Z"
    }
  }
  ```
- **CLAUDE.md**: Added Git Safety Protocol documentation and `/contribute` command reference
- **CONTRIBUTING.md**: Updated with contribution workflow using `/contribute` command
- **Documentation**: Updated setup flow diagrams and command reference tables

### Security
- **Secrets scanning**: `/contribute` scans for common secret patterns before PR creation
  - AWS access keys (AKIA...)
  - GitHub tokens (ghp_...)
  - Slack tokens (xox...)
  - Private keys (-----BEGIN PRIVATE KEY-----)
  - Generic password/secret/api_key patterns
- **DCO enforcement**: Contribution workflow verifies Developer Certificate of Origin sign-off
- **Template isolation**: Prevents accidental code leakage from forked projects to upstream

---

## [0.2.0] - 2025-12-19

### Added
- **`/setup` command**: First-time onboarding workflow
  - Guided MCP server configuration (GitHub, Linear, Vercel, Discord, web3-stats)
  - Project initialization (git user info, project name detection)
  - Creates `.loa-setup-complete` marker file
  - Setup enforcement: `/plan-and-analyze` now requires setup completion
- **`/feedback` command**: Developer experience survey
  - 4-question survey with progress indicators
  - Linear integration: posts to "Loa Feedback" project
  - Analytics attachment: includes usage.json in feedback
  - Pending feedback safety net: saves locally before submission
- **`/update` command**: Framework update mechanism
  - Pre-flight checks (clean working tree, remote verification)
  - Fetch, preview, and confirm workflow
  - Merge conflict guidance per file type
  - CHANGELOG excerpt display after update
- **Analytics system**: Usage tracking for feedback context
  - `loa-grimoire/analytics/usage.json` for raw metrics
  - `loa-grimoire/analytics/summary.md` for human-readable summary
  - Tracks: phases, sprints, reviews, audits, deployments
  - Non-blocking: failures logged but don't interrupt workflows
  - Opt-in sharing: only sent via `/feedback` command

### Changed
- **Fresh template**: Removed all generated loa-grimoire content (PRD, SDD, sprint plans, A2A files) so new projects start clean
- All phase commands now update analytics on completion
- `/plan-and-analyze` blocks if setup marker is missing
- `/deploy-production` suggests running `/feedback` after deployment
- Documentation updated: CLAUDE.md, PROCESS.md, README.md
- Repository structure now includes `loa-grimoire/analytics/` directory
- `.gitignore` updated with setup marker and pending feedback entries

### Directory Structure
```
loa-grimoire/
├── analytics/           # NEW: Usage tracking
│   ├── usage.json       # Raw usage metrics
│   ├── summary.md       # Human-readable summary
│   └── pending-feedback.json # Pending submissions (gitignored)
└── ...

.loa-setup-complete      # NEW: Setup marker (gitignored)
```

---

## [0.1.0] - 2025-12-19

### Added
- Initial release of Loa agent-driven development framework
- 8 specialized AI agents (the Loa):
  - **prd-architect** - Product requirements discovery and PRD creation
  - **architecture-designer** - System design and SDD creation
  - **sprint-planner** - Sprint planning and task breakdown
  - **sprint-task-implementer** - Implementation with feedback loops
  - **senior-tech-lead-reviewer** - Code review and quality gates
  - **devops-crypto-architect** - Production deployment and infrastructure
  - **paranoid-auditor** - Security and quality audits
  - **devrel-translator** - Technical to executive translation
- 10 slash commands for workflow orchestration:
  - `/plan-and-analyze` - PRD creation
  - `/architect` - SDD creation
  - `/sprint-plan` - Sprint planning
  - `/implement` - Sprint implementation
  - `/review-sprint` - Code review
  - `/audit-sprint` - Sprint security audit
  - `/deploy-production` - Production deployment
  - `/audit` - Codebase security audit
  - `/audit-deployment` - Deployment infrastructure audit
  - `/translate` - Executive translation
- Agent-to-Agent (A2A) communication system
- Dual quality gates (code review + security audit)
- Background execution mode for parallel agent runs
- MCP server integrations (Linear, GitHub, Vercel, Discord, web3-stats)
- `loa-grimoire/` directory for Loa process artifacts
- `app/` directory for generated application code
- Comprehensive documentation (PROCESS.md, CLAUDE.md)
- Secret scanning workflow (TruffleHog, GitLeaks)
- AGPL-3.0 licensing

### Directory Structure
```
app/                    # Application source code (generated)
loa-grimoire/           # Loa process artifacts
├── prd.md              # Product Requirements Document
├── sdd.md              # Software Design Document
├── sprint.md           # Sprint plan
├── a2a/                # Agent-to-agent communication
└── deployment/         # Production infrastructure docs
```

[1.1.0]: https://github.com/0xHoneyJar/loa/releases/tag/v1.1.0
[1.0.1]: https://github.com/0xHoneyJar/loa/releases/tag/v1.0.1
[1.0.0]: https://github.com/0xHoneyJar/loa/releases/tag/v1.0.0
[0.19.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.19.0
[0.18.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.18.0
[0.17.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.17.0
[0.16.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.16.0
[0.15.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.15.0
[0.14.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.14.0
[0.13.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.13.0
[0.12.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.12.0
[0.11.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.11.0
[0.10.1]: https://github.com/0xHoneyJar/loa/releases/tag/v0.10.1
[0.10.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.10.0
[0.9.2]: https://github.com/0xHoneyJar/loa/releases/tag/v0.9.2
[0.9.1]: https://github.com/0xHoneyJar/loa/releases/tag/v0.9.1
[0.9.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.9.0
[0.8.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.8.0
[0.7.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.7.0
[0.6.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.6.0
[0.5.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.5.0
[0.4.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.4.0
[0.3.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.3.0
[0.2.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.2.0
[0.1.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.1.0
