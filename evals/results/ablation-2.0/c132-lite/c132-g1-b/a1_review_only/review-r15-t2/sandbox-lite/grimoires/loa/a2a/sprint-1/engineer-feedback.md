# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (carries pr/PR.md)

---

## Overall Assessment

The change under review is `pr/head.diff` (45 files): the agy opt-in gate (FR-1), the Opus 5.5 catalog effort default resolved once at the cheval chokepoint (FR-2), the headless-CLI transport for `tools/ceiling-probe-live.py` with the I2 clamp (FR-3), the calibrated `claude-opus-5-5` ceiling (180,000 → 936,000) and the Bridgebuilder/dist regeneration. Every modified file and every new test file was read; symbols the new code imports from untouched modules (`_raw_model_entry`, `_effort_for_model`, `HeadlessCLIAdapter.health_check`, `routing.ceiling.is_context_limit_message` / `parse_context_limit` / `input_bound`, `providers.base.default_max_tokens`) were confirmed to exist. The catalog checksum matches the head catalog, and the dist bundles carry the new TS symbols.

The FR-2 chokepoint, the probe's measured-token bisection, the needle verification and the operator_set writer are well built and well tested. The FR-1 gate is correct everywhere a *planner* runs, but it is not honoured by cheval's own chain walk: `AgyOptInRequiredError` is a `ConfigError`, and cheval hard-aborts the whole fallback chain on `ConfigError`. Under `hounfour.headless.mode: prefer-cli` the agy hop comes first, so with the new default (opt-in absent) every Google model aborts with INVALID_CONFIG before its HTTP rung is tried, while every planner in this PR treats only `cli-only` as agy-routed and therefore plans the voice. That is the DEGRADED-voice outcome FR-1 exists to prevent. Both dissent voices reached the same conclusion independently (DISS-001, DISS-C-001).

Tests were not executed: the PR snapshot (`pr/head/`) holds only the touched files, so the Python/bats/TS suites cannot import their untouched dependencies from it; the workspace framework copy is a later revision than head and was used only to confirm untouched symbols exist. The verdict below rests on code reading.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Functionality — the opt-in refusal aborts cheval's chain walk instead of skipping the hop

- **HIGH** (confidence: high) `head/.claude/adapters/loa_cheval/types.py:503` — `AgyOptInRequiredError(ConfigError)` is raised from `AgyHeadlessAdapter.complete()` (`head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:125`) inside cheval's fallback-chain walk, whose `ConfigError` arm is the hard abort (`head/.claude/adapters/cheval.py:2544`-2552: "STATIC misconfig (ConfigError/INVALID_CONFIG) still falls through to the hard-abort arm" — `print(_error_json(_e.code…)); return EXIT_CODES.get(_e.code, 1)`). Failing input: `hounfour.headless.mode: prefer-cli`, `agy_opt_in` absent (the default), `GOOGLE_API_KEY` present, `cheval --model gemini-3.1-pro`. The resolver's prefer-cli transform orders CLI hops first (`chain_resolver._apply_mode_transform`, untouched), so the walk reaches `google:gemini-headless`, raises the opt-in error and exits INVALID_CONFIG; the HTTP rung is never tried. Every planner in this PR says prefer-cli is *not* agy-routed — `head/.claude/scripts/flatline-orchestrator.sh:534` (`[[ "$mode" == "cli-only" ]] || return 1`), `head/.claude/skills/bridgebuilder-review/resources/config.ts:182` (`modelId === "gemini-headless" || mode === "cli-only"`) — so Flatline and Bridgebuilder plan the Google voice and cheval refuses it: a failed hop / DEGRADED council, which the types.py docstring ("never as a failed voice") and PR.md both say cannot happen.
**File:** `head/.claude/adapters/loa_cheval/types.py:503`
**Issue:** The "not planned" seam exists only in the shell/TS planners; cheval itself treats the refusal as a static misconfiguration and kills the invocation, including hops that would have succeeded.
**Why This Matters:** FR-1's stated goal is that an opted-out agy route never degrades a verdict (PR.md cites Bridgebuilder #1274 running DEGRADED 2/3 for exactly this). On any prefer-cli host the PR reproduces that outcome by default, now for every Google model and even when a Google credential is present.
**Required Fix:** Either (a) make the walk skip an opted-out agy hop and continue — e.g. catch `AgyOptInRequiredError` before the `ConfigError`/`ChevalError` arms in the chain loop (next to the `AuthRevokedError` arm at `cheval.py:2522`), record it in `models_failed` with `error_class: "OPT_IN_REQUIRED"`, and only surface INVALID_CONFIG when it was the sole hop; or (b) make every planner treat prefer-cli as agy-routed too (`flatline-orchestrator.sh:534`, `config.ts:182`, and the dissent's chain filter), and document that prefer-cli Google voices need the opt-in. (a) matches the design intent; (b) is the smaller change. Add a test for the prefer-cli chain with the opt-in off in `test_agy_opt_in_gate.py` either way.
**Reference:** CWE-754 (improper check for unusual or exceptional conditions — a non-error state surfaced as a fatal error).

---

## Observations

Non-blocking; each carries a concrete failure scenario.

### Functionality / FR-1 coverage

- **MEDIUM** (confidence: high) `head/.claude/scripts/adversarial-review.sh:4083` — only the *companion* chain is passed through `_adv_agy_filter_chain`; the primary chain (`model` + `fallback_chain`, walked at `head/.claude/scripts/adversarial-review.sh:4134`) is not filtered. Failing input: this repository's own `.loa.config.yaml` (`hounfour.headless.mode: cli-only`, `code_review.fallback_chain: [gpt-5.5, gemini-3.1-pro, claude-headless]`): the `gemini-3.1-pro` hop is agy-routed under cli-only, cheval exits 2, and the envelope records a failed hop in `model_attempts`/`voices_dropped` instead of "not planned". Also `head/.claude/scripts/adversarial-review.sh:2360` matches only the canonical name `gemini-headless`, so a Google HTTP model under cli-only in an operator `companion_chain` is not filtered either, unlike `_tertiary_routes_to_agy` and `isAgyRouted`, which do handle cli-only. PR.md's "every planner … records the hop as not planned" is not met for the dissent.
- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:261`-262 — `validate_config()` reports an error on every default install (opt-in off is the default, `gemini-headless` is in the stock catalog). Nothing in the shipped tooling calls `validate_config()` today, so the impact is nil now; the day a whole-catalog validation path lands, a pristine install reads as misconfigured.
- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/config/loader.py:122`-124 — `agy_opt_in_enabled()` re-parses the full system catalog and the project config on every `complete()`, `health_check()` and `validate_config()` call, and the bare `except Exception: return False` swallows a malformed `.loa.config.yaml` silently, so an operator who opted in with a YAML typo gets the "set agy_opt_in: true" refusal with no hint. Root resolution is consistent with cheval's own `load_config` (both use the cwd walk), so the dissent's cwd-mismatch concern (DISS-C-004) does not apply. Cache per process and log the parse failure once.
- **LOW** (confidence: medium) `head/.claude/skills/bridgebuilder-review/resources/config.ts:190` — the default parameter `gate: AgyGate = readAgyGate()` reads `.loa.config.yaml` relative to the process cwd for any caller that passes no gate (the pipeline passes `repoRoot`-anchored path at `multi-model-pipeline.ts:172`; `main.ts` is untouched and still calls the one-argument form). A Bridgebuilder run from outside the repo root evaluates the gate against a different (absent) file.

### Evidence / tests (GOAL-DRIVEN)

- **MEDIUM** (confidence: high) `head/.claude/defaults/model-config.yaml:496`-501 — the `claude-opus-5-5` entry is written as `source: operator_set` / `probed_ceiling: 936000` from a probe whose own outcome was `partial` (the comment says so; the tool writes the catalog only on `clean`), with `sample_size: null` (`:506`). The same PR weakens the one test that checked the value: `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:146`-147 sets `cap = entry["effective_input_ceiling"]` for a calibrated entry, so `expected = min(effective_input_ceiling, cw − default_max_tokens)` and the equality assert is a tautology whenever the I2 bound (asserted independently on the next line) holds. No remaining check ties the calibrated value to `ceiling_calibration.measured_input_tokens` — a hand-edited ceiling above the measured accept would pass. Add `assert entry["effective_input_ceiling"] <= cal["measured_input_tokens"]` for measured entries. Also `head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py:459` makes the live-catalog writer test self-skip in the shipped tree (the catalog is now calibrated), so only the SYNTH-based writer tests run.
- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/audit/modelinv.py:498` and `head/.claude/adapters/cheval.py:2834` — comments state the `effort_source` domain as `caller | catalog | none`, but `resolve_effort` returns `"extra"` (`cheval.py:924`) and the payload schema enumerates it (`head/.claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json:760`). The schema was widened, so events validate; the two comments are stale (DISS-C-002 is therefore a documentation defect, not a schema failure).
- **LOW** (confidence: medium) `head/.claude/adapters/cheval.py:935`-936 — `_effort_on_wire` returns the requested effort for every entry `_is_cli_entry` matches, but only the claude-headless adapter forwards `CompletionRequest.effort` as `--effort`; codex reads `metadata["reasoning_effort"]`/`extra`, and the grok/gemini/agy/cursor CLIs build fixed argv. `effort_effective` therefore overstates what reached the wire on non-claude CLI hops.
- **LOW** (confidence: high) `head/.claude/adapters/cheval.py:908`-911 — the "sets both params.default_effort and extra.effort" WARN fires for HTTP entries, whose `extra.effort` the docstring says is never read, and also when an explicit `--effort` makes both rungs irrelevant. Gate it on `_is_cli_entry(entry) and not explicit`.

### Complexity / Simplicity

- **MEDIUM** (confidence: high) `head/tools/ceiling-probe-live.py:632`-848 — `_main_cli` is ~215 lines with four nested closures (`step` alone is ~55 lines, `:681`-735), and `write_catalog_operator_set` (`:402`-490) is ~90 lines. Both exceed the 50-line threshold without a justification comment. Extract the bisection loop (`step`/`next_target`) and the record assembly into module-level functions; the `_outcome_reasons` split already shows the pattern.
- `SIMPLICITY[shrink]`: the YAML-boolean opt-in predicate is implemented six times — `head/.claude/scripts/adversarial-review.sh:2350`, `head/.claude/scripts/flatline-orchestrator.sh:522`, `head/.claude/scripts/loa-status.sh:798`, `head/.claude/scripts/run-preflight.sh:154`, `config.ts:155` (`readAgyGate`) and `loader.py:113`. The four bash copies are byte-near-identical yq calls; one function in `.claude/scripts/lib/` sourced by all four removes three copies. net: -24 lines possible.

### Process

- **LOW** (confidence: high) `grimoires/loa/a2a/sprint-1/reviewer.md` carries PR.md only — no `## AC Verification` walkthrough. The eval brief names PR.md as the implementation report and this review proceeds on the code, but the sprint's success criterion ("report each defect … and give a merge verdict") is the only AC and is addressed by this file.
- `FAST-GATE:` not verifiable from the snapshot. The rebuilt `dist/` bundles and updated `.build-manifest.json` indicate `tsc` ran; no evidence of `prettier --check` / ruff / shellcheck is in the PR. Treat as unconfirmed, not failed.
- Documentation: `docs/migration/v2.0-model-generation-floor.md` gains a cycle-127 addendum, `.loa.config.yaml.example` documents `agy_opt_in`, and the security-relevant code (argv exposure, fail-closed gate) is commented. The repository has no CHANGELOG.md, so no entry is owed.

---

## Cross-Model Observations

Two voices (gpt-5.5-pro primary, claude-headless companion, `counted_as: independent_voice`, verdict quality APPROVED 2/2). Eight findings, none rejected.

- DISS-001 (BLOCKING, gpt-5.5-pro) and DISS-C-001 (BLOCKING, claude-headless) — the prefer-cli hard-abort; confirmed in code and folded into Changes Required §1.
- DISS-C-002 (BLOCKING) — `effort_source: "extra"` vs. the three-value comments; the schema does include `extra` (`:760`), so demoted to the LOW comment-drift observation above.
- DISS-C-003 (`validate_config` default-install error), DISS-C-004 (per-call re-parse / silent swallow; its cwd-mismatch sub-claim is refuted — cheval's `load_config` uses the same cwd walk), DISS-C-005 ("sets both" WARN noise), DISS-C-006 (`_effort_on_wire` overstatement), DISS-C-007 (floor-test tautology + operator_set from a partial probe) — each confirmed and recorded above at the severity shown.

## Rejected dissent payloads

None: `metadata.rejected_summary` is empty and the listed sidecar `adversarial-rejected-review.jsonl` has zero rows.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":3,"low":7},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T06:05:00Z"} -->
