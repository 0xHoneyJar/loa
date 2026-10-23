# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Scope:** `pr/head.diff` — 45 files, sprint-251 operator decisions (FR-1 agy opt-in, FR-2 Opus 5.5 catalog effort default, FR-3 headless ceiling probe + fr23b I2 clamp, catalog 180,000 → 936,000)
**Methodology:** Systematic 5-category review (Security, Architecture, Code Quality, DevOps; Blockchain n/a) over the `pr/head/` tree, plus the two-voice security dissent on `pr/head.diff`

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The change narrows a real exposure: the `gemini-headless` hop dispatches `agy -p`, which carries the whole prompt on argv (CWE-214), and the PR makes that route opt-in, default off, with a fail-closed predicate (`agy_opt_in_enabled`, `head/.claude/adapters/loa_cheval/config/loader.py:113-127`) that accepts only a YAML boolean, has no environment override, and refuses before any binary discovery, workspace or spawn (`head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:124-125`, tested with discovery/spawn mocks asserted never called in `head/.claude/adapters/tests/test_agy_opt_in_gate.py:70-83`). The five planners (dissent companion chain, Flatline tertiary, Bridgebuilder, run preflight, `/loa`) all read the key with `yq` by tag (`tag == "!!bool" and . == true`), file passed as an argument, never interpolated. The probe tool sends its prompt on stdin, runs the CLI in an empty private cwd, caps captured output at 1 MB, verifies accepts with a random needle, and writes the catalog only on a `clean` outcome. The catalog checksum and the Bridgebuilder build-manifest hashes for the three touched TS sources match the head files (verified with `sha256sum`). No secrets, no injection paths, no new dependencies.

One finding blocks. The refusal is a `ConfigError`, and cheval's own chain walk treats any `ChevalError` as a hard abort (`head/.claude/adapters/cheval.py:2544-2552`, "surface immediately"). Under `hounfour.headless.mode: prefer-cli` the resolver orders CLI entries first, so with the new default off and `agy` installed every Google invoke exits `INVALID_CONFIG` at hop 1 and the HTTP Gemini hops behind it — credentialed and working — are never tried. The Bridgebuilder and Flatline gates treat only `cli-only` as agy-routed (the PR's own test pins `prefer-cli` as *not* agy-routed, `head/.claude/skills/bridgebuilder-review/resources/__tests__/multi-model-agy-opt-in.test.ts:61`), so they plan the voice, dispatch it, and record it as failed — the #1274 DEGRADED pattern the PR set out to remove, now reachable by default on a host that worked yesterday. That is an availability/resilience defect in the multi-model gate itself (SEC-AV, ARCH-RE) and it falsifies the migration doc's "not planned, never failed" claim for cheval's own routing.

The medium findings are: the opt-in is read from the tree under review (a PR branch can opt the reviewing host in), the dissent's primary chain is not filtered, MODELINV effort telemetry misreports CLI fallback hops, the 936,000 calibration is hand-authored from a partial probe whose record is not in the PR and the status surface and cheval disagree on whether observed verdicts may lower it, two tests became tautological and the only schema check of the written calibration now always skips, and a 218-line function. The lows are comment drift, stale docs, and small robustness gaps. The security dissent ran with two independent voices (`gpt-5.5-pro` primary, `claude-headless` companion), completed clean, rejected nothing; it is not degraded.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 6 |
| Low | 16 |

**Overall Risk Level:** MODERATE (rubric 3.5/5 — see Category Scores)

### Process notes

1. **Phase 0 prerequisite not met, proceeded on instruction.** `engineer-feedback.md` says CHANGES REQUIRED (trailer: 0 critical / 1 high / 6 medium / 13 low, `excluded: 0`), not "All good". The task directive for review-r15 orders the audit to run autonomously against the PR files, and `pr/AUDIT-INSTRUCTIONS.md` says to skip pre-flight steps the frozen PR cannot satisfy. Recorded here, not silently skipped.
2. **Tests were not executed.** The PR's base tree differs from this workspace (`cheval.py`, `flatline-orchestrator.sh`, the catalog; `tools/` is absent here) and `.claude/` is the System Zone, so no overlay build was attempted. Every test claim below is from reading the head files.
3. **Input guardrails:** `guardrails-orchestrator.sh` returned `PROCEED`. **Integrity pre-check:** `.loa.config.yaml` sets no `integrity_enforcement` (default; `integrity_check: true` at line 247); no drift check was run against the frozen PR.
4. **Scope analysis** (`security-audit-scope.sh --json` over `pr/head/`): 0 HTTP sources; 24 sinks (14 command-exec, 8 file-op, 2 query-shaped); 15 auth-flavoured and 15 LLM files. The command-exec sinks are the `yq` readers (argument-passed), `execFileSync("yq", …)` in TS, and the probe's `subprocess.run` of the CLI — all traced in §1A/1B below.
5. **Known-failures surface** `grimoires/loa/known-failures.md` is unreadable in this workspace (hook WARNING at session start); triaged without it.
6. **Documentation coherence reports:** none under `grimoires/loa/a2a/subagent-reports/` (directory absent). The migration doc and `.loa.config.yaml.example` do document the security-relevant change (the opt-in and its argv rationale); the breaking effect of the default flip on `prefer-cli`/`cli-only` hosts with `agy` is not named — recorded under LOW-004, not a blocker on its own.
7. **Retrospective postlude:** `invisible_retrospective.enabled` is true, but `.claude/skills/continuous-learning/resources/RETROSPECTIVE.md` does not exist in this tree; the scan was not run.

---

## Category Scores (Rubric-Based Assessment)

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 3.8/5 | IV:4 AZ:3 CI:4 IN:5 AV:3 |
| Architecture | 3.2/5 | MO:4 SC:4 RE:2 CX:3 ST:3 |
| Code Quality | 3.2/5 | RD:3 TC:3 EH:3 TS:4 DC:3 |
| DevOps | 3.6/5 | AU:4 OB:3 RC:4 AC:4 DS:3 |
| Blockchain | n/a | — |
| **Overall** | **3.5/5** | Security weighted highest |

Justification: IN 5 — every `yq` call passes the file as an argument and a fixed expression; TS uses `execFileSync` (no shell); the probe sends the prompt on stdin. AZ 3 — the opt-in is read from the reviewed tree (MED-001). AV 3 / RE 2 — the hard-abort (HIGH-001). TC 3 — tautological floor tests and a permanent skip (MED-005). OB 3 — telemetry misreports (MED-003, MED-002). DC 3 — four stale comments/descriptions (LOW-001/002/003).

---

## Phase 1A/1B — Sources, Sinks and Traces

| # | Source → Sink | Trust | Status |
|---|---------------|-------|--------|
| 1 | `.loa.config.yaml` (cwd walk) → `agy_opt_in_enabled` → `complete()` spawn gate | operator-owned **but** cwd = reviewed tree in review flows | PARTIAL → MED-001 |
| 2 | `.loa.config.yaml` → `yq eval '<fixed expr>' "$CONFIG_FILE"` (4 shell planners) | operator-owned | SAFE (file as argv, fixed expression, fail-closed on error) |
| 3 | `repoRoot/.loa.config.yaml` → `execFileSync("yq", [...])` in `readAgyGate` | reviewed repo | SAFE mechanically (no shell); trust issue folded into MED-001 |
| 4 | `process.env.LOA_HEADLESS_MODE` → `readAgyGate.mode` → `isAgyRouted` → quorum arithmetic | ambient env | PARTIAL → LOW-015 |
| 5 | `--effort` (argparse choices) / catalog `params.default_effort` / `extra.effort` → `resolve_effort` → CLI argv `--effort` and HTTP `output_config.effort` | caller / catalog | SAFE (catalog and extra rungs validated; caller rung by argparse) → LOW-014 defensive |
| 6 | CLI stdout/stderr → `_classify` → record JSON | untrusted model output | SAFE (1 MB cap, `json.loads` guarded, diag truncated to 300) |
| 7 | probe record → `write_catalog_operator_set` → `_write_text_atomic(.claude/defaults/model-config.yaml)` | operator-run tool | SAFE (line-level edit inside the model block; `_write_text_atomic` pre-exists in base) |
| 8 | `AGY_HEADLESS_BIN` / `CLAUDE_HEADLESS_BIN` → binary that receives the prompt | ambient env | N/A — pre-existing, not changed by this PR (see Cross-Model DISS-C-003) |
| 9 | `BATS_VERSION`+`LOA_STATUS_CONFIG_FILE` → `_providers_config_file` | ambient env | PARTIAL (display only) → LOW-016 |

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] The opt-in refusal hard-aborts cheval's chain walk; `prefer-cli` hosts lose every Google voice

**Severity:** HIGH | **Confidence:** medium | **Criterion:** SEC-AV Availability/Resilience, ARCH-RE Resilience
**File:** `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:124-125`; `head/.claude/adapters/loa_cheval/types.py:503-518`; `head/.claude/adapters/cheval.py:2544-2552`; `head/.claude/skills/bridgebuilder-review/resources/config.ts:180-183`; `head/.claude/scripts/flatline-orchestrator.sh:529-536`

**Reasoning Trace:**
> `complete()` raises `AgyOptInRequiredError()` (`agy_headless_adapter.py:124-125`); the class is `class AgyOptInRequiredError(ConfigError)` (`types.py:503`), and `ConfigError` is a `ChevalError`. The walker's error arms are, in order, a walkable `AuthRevokedError` (`continue`), then `except ChevalError as _e: # Non-retryable typed cheval error — surface immediately … return EXIT_CODES.get(_e.code, 1)` (`cheval.py:2544-2552`). There is no `health_check()` pre-dispatch step in the walk (`grep health_check cheval.py` → only the breaker CLI). `chain_resolver._apply_mode_transform` (workspace copy, untouched by the PR) returns `cli + http` for `prefer-cli`, so `gemini-headless` is hop 1 of every Google chain in that mode (the stock chains all end in `google:gemini-headless`, `head/.claude/defaults/model-config.yaml:216,228,248,262,289,309`). The TS gate `isAgyRouted` returns true only for `modelId === "gemini-headless" || mode === "cli-only"` (`config.ts:180-183`) and the new test pins `isAgyRouted("google","gemini-3.1-pro-preview","prefer-cli") === false` (`multi-model-agy-opt-in.test.ts:61`); `_tertiary_routes_to_agy` likewise returns 1 unless `cli-only` (`flatline-orchestrator.sh:533-534`).

**Issue:** Failure scenario — a host with `agy` installed and OAuth-authed (yesterday's working shape), `hounfour.headless.mode: prefer-cli`, a valid `GOOGLE_API_KEY`, and `agy_opt_in` absent (the new default): `cheval --model gemini-3.1-pro-preview` aborts at hop 1 with `INVALID_CONFIG` and never reaches `gemini-3.1-pro-preview` / `gemini-2.5-pro` over HTTP. Bridgebuilder plans the Google voice (not agy-routed under `prefer-cli`), the adapter returns an error, and `modelResults.some((result) => result.error …)` sets `mergeBlocked = true` (`head/.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts:422-426`). Flatline validates and dispatches the tertiary and records a dropped voice. The migration note "the dissent, Flatline's tertiary, Bridgebuilder, run-preflight.sh and /loa record the hop as not planned … rather than failed" (`head/docs/migration/v2.0-model-generation-floor.md:283-287`) is false for cheval's own routing. The PR's `.loa.config.yaml.example` text says "cheval refuses an agy dispatch before any spawn" — true — but a refusal that aborts the walk is a failed voice, not a not-planned one. (Under `prefer-api`, `gemini-headless` is the chain terminal, so the abort only changes the exit text of an already-exhausted chain; under `cli-only` the planners gate correctly. The regression is `prefer-cli`, a documented mode, and this repo's own config is CLI-routed — `.loa.config.yaml:114` here reads `cli-only`.)

**Impact:** Every multi-model verdict on such a host degrades by default after upgrade, with a working HTTP fallback silently removed; an operator reads `INVALID_CONFIG` for a chain whose HTTP hops are fully configured. The defence the PR adds (fail closed) is right; the failure *mode* defeats FR-1's own goal.

**Fix:**
1. Make the refusal a walk-skip: in the walker, before dispatching a `gemini-headless` entry, test `agy_opt_in_enabled()` (or the adapter's `health_check()`) and `continue` with a `models_failed` row `error_class: NOT_PLANNED`, `failure_class: opt_in_required`; or raise a walkable subclass of `ProviderUnavailableError` carrying `failure_class = "opt_in_required"` so the chain falls through to its HTTP siblings and the breaker is not tripped.
2. Treat `prefer-cli` as agy-routed for Google voices in `isAgyRouted` and `_tertiary_routes_to_agy` (the CLI hop runs first there), and flip the pinned assertion at `multi-model-agy-opt-in.test.ts:61`.
3. Add a `prefer-cli` case to `test_agy_opt_in_gate.py` and `tests/unit/flatline-tertiary-agy-opt-in.bats`; name the default flip for `prefer-cli`/`cli-only` hosts with `agy` as a behaviour change in the migration doc.

**Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html ; the walker's own skip-and-walk contract (cycle-104 §1.4.2, comment at `head/.claude/adapters/cheval.py:2174`). Confirmed by the review (Changes Required §1) and by the review-gate dissent DISS-C-003.

---

## Medium Priority Issues (Address Before Re-Audit Where Cheap)

### [MED-001] The opt-in is read from the tree under review (Confirmed by cross-model review — audit DISS-C-001)

**Severity:** MEDIUM | **Confidence:** medium | **Criterion:** SEC-AZ Authorization
**File:** `head/.claude/adapters/loa_cheval/config/loader.py:121-127`; `head/.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts:172`; `head/.claude/skills/bridgebuilder-review/resources/config.ts:190`
**Issue:** `root = project_root or _find_project_root()` walks up from `Path.cwd()` (`loader.py:97-103,121`). The agy adapter's own comment states "the caller's cwd is the reviewed tree" (`agy_headless_adapter.py:147`), and the Bridgebuilder pipeline reads the gate from `config.repoRoot` — the repository being reviewed (`multi-model-pipeline.ts:172`). A PR branch that adds `hounfour.headless.agy_opt_in: true` opts the reviewing host into the argv-exposed route (and the `agy --dangerously-skip-permissions --sandbox` spawn in the private workspace) without operator action. This is inside the existing trust model for `.loa.config.yaml` — a branch can also edit `.claude/` — and the PR is strictly safer than base (where the route needed no opt-in at all), so it is not high; but the docstring's "a planner is never talked into the agy voice by ambient env" and the example-config's "only ever exposed by an operator's deliberate choice" claim more than the design provides.
**Impact:** Prompt (the redacted diff plus the review template) visible to local accounts of the reviewing host via `/proc/<pid>/cmdline` for the life of the hop, on hosts whose operator believed the route off.
**Fix:** Read the key from an operator-owned layer (the framework root that owns `.claude/adapters`, or a non-tree file), or require it in both places; at minimum log the path the decision was read from and state the boundary in the docstring and `.loa.config.yaml.example`.
**Reference:** CWE-15 External Control of System or Configuration Setting — https://cwe.mitre.org/data/definitions/15.html ; CWE-214 Invocation of Process Using Visible Sensitive Information — https://cwe.mitre.org/data/definitions/214.html

### [MED-002] The dissent's primary chain is not filtered; a gated hop surfaces as `model_unavailable`

**Severity:** MEDIUM | **Confidence:** high | **Criterion:** DEV-OB Observability
**File:** `head/.claude/scripts/adversarial-review.sh:4080-4087`; `head/.claude/scripts/adversarial-review.sh:2979-2993`
**Issue:** `_adv_agy_filter_chain` is applied to `companion_chain_str` only. The primary chain (this run's was `gpt-5.5-pro gpt-5.5 gemini-3.1-pro claude-headless`) still carries a Google alias whose catalog chain terminates in `gemini-headless`; when cheval reaches it with the opt-in off it exits 2, and `_companion_failure_class` maps exit 2 to `model_unavailable` — a dropped voice — not `opt_in_required`. The migration doc's "verdict quality counts planned voices only" does not hold for the primary.
**Fix:** Filter the primary chain the same way, or classify an exit 2 whose diagnostic carries the opt-in marker as not planned; have the terminal refusal say that the HTTP hops were tried first.
**Reference:** CWE-778 Insufficient Logging — https://cwe.mitre.org/data/definitions/778.html

### [MED-003] MODELINV effort telemetry misreports CLI fallback hops; the primary's default overrides a hop's own `extra.effort` (Confirmed by cross-model review — review DISS-C-002)

**Severity:** MEDIUM | **Confidence:** high | **Criterion:** DEV-OB Observability
**File:** `head/.claude/adapters/cheval.py:1519-1523`, `:1829`, `:2838-2843`
**Issue:** Effort is resolved once against the primary entry and `effort=_effort` rides every hop's `CompletionRequest` (`:1829`), so a CLI fallback hop's own `extra.effort` is overridden, contradicting the docstring's "the headless adapter's own rung" (`:896-897`). `effort_effective` is then computed from the primary's `_effort`; `_effort_on_wire` returns `None` when `_effort is None` (`:934-935`) even though the answering CLI hop resolved and sent its own `--effort` (the PR's test pins the CLI behaviour at `head/.claude/adapters/tests/test_effort_catalog_default.py:384-386`). The MODELINV ledger — the audit chain — then records no effort for a call that put one on the wire.
**Fix:** Resolve effort per answering hop for the telemetry row (call `resolve_effort` against the final hop's raw entry); document or implement per-hop precedence for `effort=` on fallback requests.
**Reference:** CWE-778 — https://cwe.mitre.org/data/definitions/778.html

### [MED-004] The 936,000 calibration is hand-authored from a partial probe; its record is not in the PR; status and cheval disagree on how it may be lowered

**Severity:** MEDIUM | **Confidence:** medium | **Criterion:** DEV-RC Release Config, SEC-AV
**File:** `head/.claude/defaults/model-config.yaml:494-513`; `head/tests/unit/loa-status-providers.bats:66-69`; `head/tools/ceiling-probe-live.py:1017-1019`
**Issue:** The entry is written `source: operator_set`, `method: probed_headless`, `calibrated_at: "2026-10-07T09:29:07Z"`, yet the comment at line 496 says "the tool's own outcome was `partial`", and `_main_cli` writes the catalog only when `outcome == "clean"` (`ceiling-probe-live.py:1017-1019`), so this calibration was composed by hand from `grimoires/loa/reports/2026-10-07-opus-5-5-ceiling-probe-cli.json`, which is not in the PR and cannot be checked. The bound was measured through the Bedrock CLI (`cli_model: global.anthropic.claude-opus-5-5`) and now governs the `anthropic` HTTP entry — a transport whose limit for this model was not measured (the entry's `beta_headers: []`). The PR's status test pins "calibrated: the measured bound, observations never lower it" (`loa-status-providers.bats:69`), while this workspace's `routing/ceiling.py` lets a verified observed limit tighten a *foreign-transport* calibration (`is_foreign_transport_calibration`, "r251-1") — whichever of the two the PR's base carries, the status surface and the router disagree about the contract for exactly this entry. Bridgebuilder's budget follows to 916,000 (`head/.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts:34`).
**Impact:** If the direct API accepts less than 936,000 for this account, every oversize `opus` call fails with a provider context verdict until an operator re-probes, and `/loa` tells the operator the bound is calibrated and final.
**Fix:** Commit the probe record beside the catalog or under `grimoires/loa/reports/`; record the method as what it was (a partial headless probe, operator-accepted) or add an `operator_note`; align `_anthropic_ceiling_json` and its test with `ceiling.py`'s foreign-transport rule; add "any direct-API `PROVIDER_CONTEXT_LIMIT` for this model" to `reprobe_trigger`.
**Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

### [MED-005] Two calibrated-entry tests no longer test; the written calibration's schema check always skips (Confirmed by cross-model review — review DISS-C-006)

**Severity:** MEDIUM | **Confidence:** high | **Criterion:** CQ-TC Test Coverage
**File:** `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:146-148`, `:168-169`; `head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py:457-460`, `:499-501`
**Issue:** For a measured entry `cap = entry["effective_input_ceiling"]` and `expected = min(cap, cw − dmt)`, which any I2-respecting value satisfies; nothing asserts `effective_input_ceiling == min(measured_input_tokens, context_window − default_max_tokens)`. `test_write_operator_set_changes_only_the_entry_and_replaces_the_shortcut` now `pytest.skip`s whenever the shortcut comment is gone — i.e. permanently on this tree — and it was the only test validating the written `ceiling_calibration` against `$defs.ceilingCalibration` with `jsonschema`.
**Fix:** Assert against provenance for measured entries; move the schema assertion into the SYNTH-based tests.

### [MED-006] `_main_cli` is 218 lines with six nested closures

**Severity:** MEDIUM | **Confidence:** high | **Criterion:** ARCH-CX Complexity
**File:** `head/tools/ceiling-probe-live.py:632-849`; `:402-480`
**Issue:** The bisection (`step`, ~55 lines; `next_target` with the re-anchor rule), the record dict and the catalog write are inlined; `write_catalog_operator_set` is 79 lines. The rules the probe enforces (needle verification, tokenizer re-anchoring, budget accounting) cannot be unit-tested without a fake CLI.
**Fix:** Split into bisection / record / write.

---

## Low Priority Issues (Technical Debt)

### [LOW-001] Stale `caller | catalog | none` contract comments
- **File:** `head/.claude/adapters/loa_cheval/audit/modelinv.py:498`; `head/.claude/adapters/cheval.py:2834`
- **Issue:** `resolve_effort` returns a fourth value `extra` (`cheval.py:923-925`) and the payload schema enumerates it (`head/.claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json:755-762`). Comment drift only (review-gate DISS-C-001 claimed a schema failure; the schema in this diff accepts `extra`).
- **Fix:** Update both comments.

### [LOW-002] Probe docstring and schema description still describe the raw write
- **File:** `head/tools/ceiling-probe-live.py:45-46`; `head/.claude/data/schemas/model-config-v3.schema.json:306`
- **Issue:** "written raw — the api transport applies no safety margin either" and "the value written to probed_ceiling / effective_input_ceiling" predate the fr23b clamp (`ceiling-probe-live.py:377-399`); the live entry has 972,887 measured vs 936,000 written.
- **Fix:** Update both texts.

### [LOW-003] A re-probe leaves the hand-written six-line comment stale
- **File:** `head/.claude/defaults/model-config.yaml:495-501`
- **Issue:** `write_catalog_operator_set` replaces only the single `# cycle-127 FR-3: bound measured` line (`head/tools/ceiling-probe-live.py:469-479`).
- **Fix:** Fold the note into the provenance line or teach the writer to replace the block.

### [LOW-004] Migration history rewritten in place; breaking effect not named
- **File:** `head/docs/migration/v2.0-model-generation-floor.md:265-274`, `:290-291`
- **Issue:** The cycle-126 bullet now describes cycle-127 behaviour and the cycle-127 section refers back to it; the default flip's effect on `prefer-cli`/`cli-only` hosts with `agy` installed is not called out as a behaviour change.
- **Fix:** Restore the cycle-126 text, append under cycle-127, name the change.

### [LOW-005] Unbound private-method call with a `SimpleNamespace` stand-in
- **File:** `head/tools/ceiling-probe-live.py:261`, `:273`
- **Issue:** `ClaudeHeadlessAdapter._raise_for_error(SimpleNamespace(provider=…), …)` works because the method reads only `self.provider`; any future `self.` use raises `AttributeError`, swallowed by `except Exception` as `other`.
- **Fix:** Share a module-level classifier between adapter and probe.

### [LOW-006] Inline `__import__`
- **File:** `head/tools/ceiling-probe-live.py:135`, `:144`, `:147`, `:261`
- **Fix:** `import time`, `import re`, `import types`.

### [LOW-007] `--allow-partial` accepted but ignored on the CLI transport
- **File:** `head/tools/ceiling-probe-live.py:503`, `:580-581`
- **Issue:** `_main_cli` never reads `args.allow_partial`; the api path's message tells operators to pass it.
- **Fix:** Reject it for `--transport claude-headless` or honour it.

### [LOW-008] "Both rungs" WARN fires for HTTP entries
- **File:** `head/.claude/adapters/cheval.py:908-911`
- **Issue:** The `extra` rung applies only to CLI entries (`:915`); the WARN is noise elsewhere.
- **Fix:** Gate the WARN on `_is_cli_entry(entry)`.

### [LOW-009] Preflight FAIL detail misattributes the cause
- **File:** `head/.claude/scripts/run-preflight.sh:204`, `:207`
- **Issue:** When a stage's only voice was gated by the opt-in with `agy` on PATH, the message still says "no credential present and no CLI hop on PATH"; the truth is only in the `; not planned:` suffix.
- **Fix:** Name the opt-in in the primary message.

### [LOW-010] `/loa` hop column loses binary presence and overruns
- **File:** `head/.claude/scripts/loa-status.sh:805-806`, `:865`
- **Issue:** `_provider_hop` returns `""` for `agy` whenever the opt-in is off, and the 46-character `cli_hop_note` replaces the hop in a `%-7s` column.
- **Fix:** Show presence and the gate as separate fields.

### [LOW-011] `validateApiKeys` default gate is cwd-dependent
- **File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:190`
- **Issue:** `gate: AgyGate = readAgyGate()` reads `.loa.config.yaml` relative to the process cwd; the pipeline passes `repoRoot`; any other caller gets a different answer.
- **Fix:** Make `gate` required.

### [LOW-012] Flatline gate matches by name only
- **File:** `head/.claude/scripts/flatline-orchestrator.sh:529-536`
- **Issue:** An operator alias resolving to `google:gemini-headless` through the catalog bypasses `_tertiary_routes_to_agy` and surfaces as `INVALID_CONFIG`, a failed voice; `adversarial-review.sh` resolves aliases via `_adv_hop_canon` (`:2823`).
- **Fix:** Resolve through the catalog alias table.

### [LOW-013] `_effort_on_wire` evaluated inside the emit call after a paid call
- **File:** `head/.claude/adapters/cheval.py:2838-2843`
- **Issue:** The lazy import of the private `_effort_for_model` and the `final_model_id` split run inside the `_emit_modelinv(...)` argument list, inside the emit's fail-soft `except Exception` (`:2873-2879`, `[AUDIT-EMIT-FAILED]`); an exception there loses the MODELINV row for a call that cost money (review-gate DISS-C-005).
- **Fix:** Compute it beforehand under its own guard.
- **Reference:** CWE-778 — https://cwe.mitre.org/data/definitions/778.html

### [LOW-014] The caller rung bypasses `_valid_effort` (Confirmed by cross-model review — audit DISS-C-004)
- **File:** `head/.claude/adapters/cheval.py:912-914`
- **Issue:** `explicit = getattr(args, "effort", None)` is returned unchecked; only argparse `choices` (`cheval.py:3046`) constrain it. The chokepoint's contract ("one chokepoint, four rungs") depends on the argparse definition staying in sync; a programmatic `Namespace` lands any string on `--effort` and in MODELINV. Defensive; argparse does validate today.
- **Fix:** Run `explicit` through `_valid_effort` and refuse with `INVALID_CONFIG` on mismatch.
- **Reference:** CWE-20 — https://cwe.mitre.org/data/definitions/20.html

### [LOW-015] Ambient `LOA_HEADLESS_MODE=cli-only` un-plans every Google voice and shrinks the merge quorum
- **File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:176`, `:180-183`; `head/.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts:422`; `head/.claude/scripts/flatline-orchestrator.sh:533`
- **Issue:** `readAgyGate` returns `mode: process.env.LOA_HEADLESS_MODE || mode`, `isAgyRouted` treats `cli-only` as agy-routed, and the merge gate now expects `models.length - notPlanned.length` results. With the opt-in off, an inherited env var silently removes the Google voice from the quorum (and Flatline's tertiary) without any config change. "No environment override" holds for opting *in* only; env can still opt a voice *out*. Consistent with cheval's own precedence, so low.
- **Fix:** Say so in the docs, or ignore env for the planning decision and log the un-planned voice at WARN.
- **Reference:** CWE-15 — https://cwe.mitre.org/data/definitions/15.html

### [LOW-016] Status config seam gated by a bats marker only
- **File:** `head/.claude/scripts/loa-status.sh:792`
- **Issue:** `_providers_config_file` honours `LOA_STATUS_CONFIG_FILE` when `BATS_TEST_FILENAME` or `BATS_VERSION` is non-empty — a marker anyone can export — rather than a `*_TEST_MODE=1` flag plus the marker. It follows the file's two older seams (`:732`, `:782`) and affects display only. Confidence low.
- **Fix:** Gate on a test-mode flag as well, per the agent-network convention.

---

## Observations (not tallied)

- **Pre-existing, not introduced — `AGY_HEADLESS_BIN` / `CLAUDE_HEADLESS_BIN` choose the binary that receives the prompt** (`head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:300-302`, unchanged by the diff; audit DISS-C-003). The PR's "no env override" wording refers to the opt-in; once opted in, ambient env still redirects dispatch. Recommend saying so beside the opt-in note. No CWE tallied against this PR.
- **Pre-existing, not introduced — `build_headless_argv`'s `prompt` parameter places text on argv after `-p` without `--`** (`head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:127-161`; audit DISS-C-002). The base `_build_command` had the same branch; the adapter passes `None` (`:280`) and the probe passes none, so the prompt travels on stdin everywhere today. The PR widens the surface by making it a module-level function; drop the parameter or insert `--`.
- **The dissent's primary voice (`gpt-5.5-pro`) returned zero findings**; all four findings came from the companion. Both voices completed; not a degradation.

---

## Cross-Model Security Observations

Envelope: `grimoires/loa/a2a/sprint-1/adversarial-audit.json` — `type: audit`, `status: clean`, primary `gpt-5.5-pro` (answered), companion `claude-headless` `succeeded`, `counted_as: independent_voice`, `rejected_count: 0`, `degraded: false`, `locality: null`. Not DEGRADED_SECURITY_REVIEW. Advisory voices: none.

| Dissent | Severity | Claim | Triage |
|---------|----------|-------|--------|
| DISS-C-001 | MEDIUM | Opt-in read from the reviewed tree's config | **Confirmed** → MED-001 (Confirmed by cross-model review) |
| DISS-C-002 | LOW | `build_headless_argv` `prompt` param re-opens argv exposure | Pre-existing branch moved; adapter and probe pass `None` → Observations, not tallied |
| DISS-C-003 | LOW | `AGY_HEADLESS_BIN` env redirects the opted-in dispatch | Pre-existing, `_cli_bin` unchanged → Observations, not tallied |
| DISS-C-004 | LOW | Caller rung of `resolve_effort` not validated | **Confirmed** (defensive; argparse validates today) → LOW-014 |

Review-gate dissent (`adversarial-review.json`, triaged by the review) cross-checked: DISS-C-003 (hard abort) → HIGH-001; DISS-C-002 → MED-003; DISS-C-006 → MED-005; DISS-C-004 → MED-001; DISS-C-005 → LOW-013; DISS-C-001 (schema) → not a defect, LOW-001 comment drift only.

## Rejected dissent payloads

- none — the envelope's `metadata.rejected_summary` is `[]`, `metadata.rejected_sidecars` is `[]`, and no `adversarial-rejected-audit*.jsonl` sidecar exists beside it.

### Review demotions

The review trailer counts `excluded: 0`; there are no demoted highs to confirm. `excluded_confirmed: 0`.

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added — the TS test's `fixture-not-a-key`, the probe's random needle and the fake CLI are fixtures; `_cli_version` truncates to 120 chars; the probe record carries `cli_bin` and `AWS_REGION` only
- [x] Input validation at trust boundaries — opt-in accepts only a YAML boolean (Python `is True`, `yq` `tag == "!!bool"`, TS `=== true`); `default_effort` enum-validated in schema and `_valid_effort`; CLI output capped at 1 MB; diagnostics truncated
- [~] Authorization — the opt-in defaults off and fails closed; the layer it is read from is the reviewed tree (MED-001)
- [x] No injection — `yq` expressions fixed, file passed as an argument; `execFileSync` (no shell) in TS; `subprocess.run(cmd_list, input=…)` in the probe; prompts on stdin
- [x] Error handling does not leak info — the refusal names the key, not a value; `_run_capped` discards the workspace
- [~] Tests cover security paths — the gate is tested at the config layer and the adapter (`test_agy_opt_in_gate.py`); the `prefer-cli` walk path is untested (HIGH-001) and two floor tests are tautological (MED-005)
- [x] Audit-chain writes go through `emit_model_invoke_complete`; no raw appends added
- [x] Generated artefacts consistent — `sha256sum` of `head/.claude/defaults/model-config.yaml` = `17f75f07…1b08` (matches `.checksum`); `.build-manifest.json` hashes for `config.ts`, `core/multi-model-pipeline.ts`, `core/truncation.generated.ts` match the head sources

---

## Threat Model Summary

**Trust boundaries:** operator config (`.loa.config.yaml`) vs the tree under review (same file in review flows — MED-001); ambient environment vs config (opt-in: env cannot opt in; env can change `mode` — LOW-015; env chooses the CLI binary — pre-existing); CLI stdout/stderr (untrusted model output) → probe record.
**Attack vectors:** PR branch flips the opt-in → prompt on argv on the reviewing host (MEDIUM); default flip + `prefer-cli` → loss of the Google voice and degraded verdicts (HIGH, availability); inherited `LOA_HEADLESS_MODE` → quorum shrink (LOW).
**Mitigations present:** fail-closed predicate; refusal before discovery/spawn; `yq` by tag; stdin prompt transport in the claude route and the probe; private empty cwd; output caps; clean-only catalog write with I2 clamp.
**Residual risks:** the walk-abort regression until fixed; the unverifiable calibration provenance; the HTTP transport's unmeasured limit for Opus 5.5.

---

## Positive Findings

- One predicate for the opt-in, fail-closed, no env override, tested through the real config layer with discovery/spawn mocks asserted never called.
- `resolve_effort` is a single chokepoint with a clear rung order and warn-once behaviour; the payload schema was extended in the same change as the writer.
- The probe verifies every accept with a random needle, measures from provider usage, re-anchors after a tokenizer overshoot, caps output, runs in a private cwd, and never writes a partial result; the fr23b clamp pins cheval's I2 invariant.
- Checksum, build manifest and dist mirrors are consistent with their sources.

---

## Next Steps

**CHANGES_REQUIRED:**
1. Fix HIGH-001 (walk-skip or walkable refusal; `prefer-cli` treated as agy-routed in both planner gates; tests; migration note).
2. Fold MED-001 (trust-boundary wording or operator-owned layer), MED-002 and MED-003 into the same round — they are small.
3. Commit the probe record and reconcile the calibrated-bound contract between `/loa` and `ceiling.py` (MED-004); repair the two tautological tests and the permanent skip (MED-005).
4. Run the Python, bats and node suites on the PR's base tree and record the results in `reviewer.md`; then `/review-sprint sprint-1` and `/audit-sprint sprint-1` again.

Machine-parseable findings: `grimoires/loa/a2a/audits/2026-10-21/findings.jsonl`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":6,"low":16},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T18:12:00Z"} -->
