# cycle-099-model-registry — Session Resumption Brief

**Last updated**: 2026-05-07 (**Sprint 2E SHIPPED at #750 (v1.132.0)** + **PR #751 BB OpenAI endpoint_family routing fix** + **PR #752 gpt-5.5 temperature_supported + flatline SSOT migration (closes #753)** + **PR #754 gen-adapter-maps.sh `LC_ALL=C` locale-pin (closes Brief I Option D)** + **BB E2E TRIPLE-PROVIDER VERIFIED on PR #754 (closes Brief I Option A — anthropic 13s + openai gpt-5.5-pro 153s + google 7s, all returned cleanly, 0 BLOCKER, 0 HIGH_CONSENSUS, 1 DISPUTED, 4 LOW_VALUE/PRAISE)**. All three multi-model subsystems — Bridgebuilder + Red Team + Flatline — now invoke top-tier models successfully END-TO-END on real PRs. Cycle-099 Sprint 2 main thread closed. **Next: cycle-098 Sprint 4 (L4 graduated-trust, parked) OR cycle-099 T2.9-T2.16 operator-tooling (T2.12+T2.13 highest UX value)**)
**Author**: deep-name + Claude Opus 4.7 1M
**Purpose**: Crash-recovery + cross-session continuity. Read first when resuming cycle-099 work.

## 🎯 v1.130.0 milestone (2026-05-06)

**Cycle-099 is officially packaged.** Named milestone release published at https://github.com/0xHoneyJar/loa/releases/tag/v1.130.0 with FAANG-OSS standard release engineering:

- **CHANGELOG.md** — structured `[1.130.0]` rollup covering cycle-098 + cycle-099 + cheval headless adapters; per-tag inventory v1.110.0 → v1.129.1 stub-pointed
- **README** — "What's new in v1.130.0" highlights section linking to migration + ADR
- **`docs/migration/v1.130-cycle-099-model-registry.md`** (NEW) — operator migration guide with 4 worked recipes
- **`docs/architecture/ADR-001-cycle-099-model-registry.md`** (NEW) — architecture decision record covering 5 alternatives considered, 1 chosen-with-augmentation
- **`.loa-version.json`** — `framework_version: 1.130.0`
- **GitHub Release** — narrative-style rich notes (~2700 chars)

**Semver**: 1.130.0 = MINOR (additive only). Backward-compat: legacy `aliases:` block resolves via FR-3.9 stage 4 with deprecation warning; `gpt-5.3-codex` immutable self-map preserved; `LOA_FORCE_LEGACY_ALIASES=1` kill-switch active.

## 🚨 TL;DR — Sprint 1 + 2A + 2B + 2C + 2D.a+b + 2D.c + 2D.d + **2E** all SHIPPED; **20 cycle-099 PRs** + cheval headless adapters + v1.130.0 named release on main; 3-way cross-runtime parity gate + property suite + tier_groups defaults + prefer_pro wiring all ACTIVE; **T2.6 + T2.7 + T2.8 fully closed**; **BB + Red Team + Flatline all routing top-tier models post PR #751 + #752**

**On main (11 PRs):**
- chore #721 (`9ef33055`) — cycle-099 ledger activation + planning artifacts (mirrors cycle-098 #679 pattern)
- Sprint-1A #722 (`78c59568`) — bridgebuilder codegen foundation (T1.1 + T1.2)
- Sprint-1B #723 (`7140ff1c`) — adapter migrations + drift gate + lockfile (T1.3 + T1.4 + T1.5 + T1.6 + T1.8 + T1.10 partial)
- Sprint-1C #724 (`8b008b9b`) — codegen reproducibility matrix CI + toolchain runbook (T1.7 + T1.9) + latent-drift fix
- Sprint-1E.a #728 (`cd1c2438`) — log-redactor (T1.13) + migrate-model-config CLI (T1.14)
- Sprint-1E.b #729 (`fbd7c048`) — centralized endpoint validator T1.15 partial (Python canonical + bash wrapper + 8-step canonicalization + STRICT urllib.parse import-guard)
- Sprint-1E.c.1 #730 (`43a60225`) — TS port via Python+Jinja2 codegen (T1.15 cont.) — 37 cross-runtime parity tests + drift gate with hash cross-check; closes 2 CRITICAL allowlist bypasses caught by dual-review pre-merge
- Sprint-1E.c.2 #731 (`ada3584a`) — DNS rebinding + HTTP redirect enforcement (T1.15 cont.) — `LockedIP` + `lock_resolved_ip` / `verify_locked_ip` / `validate_redirect` / `validate_redirect_chain` + cdn_cidr_exemptions per SDD §1.9 + load-time CIDR-permissive WARN. 27 new tests with mocked DNS
- Sprint-1E.c.3.a #732 (`848d9fac`) — bash caller migration to `endpoint_validator__guarded_curl` (T1.15 cont.) — first production wiring of the validator; 3 callers migrated; 54 new tests covering smuggling defenses + --config-auth content gate + allowlist tree-restriction + positional-URL strict-reject. Cypherpunk dual-review caught CRITICAL --config URL smuggling + HIGH allowlist tree gap pre-merge.
- Sprint-1E.c.3.b #733 (`7815d56a`) — bash caller migration batch (T1.15 cont.) — 11 more callers + `mount-loa.sh` exempt with hardened dot-dot defense. 31 new bats. Subagent caught MEDIUM dot-dot bypass; BB iter-2 caught HIGH/MEDIUM test-logic + bash-c shell-injection pattern.
- **Sprint-2A #737 (`ace5a206`)** — JSON Schema for `model_aliases_extra` + standalone validator helper (T2.1). 4 deliverables: `.claude/data/trajectory-schemas/model-aliases-extra.schema.json` (DD-5 path-locked, Draft 2020-12, verbatim from SDD §3.2 + dual-review hardening), `.claude/scripts/lib/validate-model-aliases-extra.{py,sh}` (Python canonical + bash twin mirroring cycle-099 endpoint-validator pattern), `tests/unit/model-aliases-extra-schema.bats` (57 contract pins). Sprint scope reduced from "T2.1 + T2.2" to T2.1 only — cycle-095's strict-mode loader for `.loa.config.yaml` top-level fields doesn't actually exist; building one for 30+ existing top-level fields is its own sprint. Subagent dual-review caught **HIGH `permissions: {}` empty-object bypass** of FR-1.4 (fix: `minProperties: 1` + allOf strengthening), **HIGH framework-default collision check missing** per IMP-004 (fix: Python-side `_check_collisions()` against `.claude/defaults/model-config.yaml`), **MEDIUM dot-dot bypass in id pattern** (fix: `not.anyOf` rejecting `\.\.` + leading/trailing meta), **MEDIUM endpoint URI advisory** (fix: `pattern: ^https://` enforced at schema layer), all pre-merge. BB iter-1 caught hardcoded `/tmp/loa-pwned` flake risk + dead helpers. BB iter-2 caught duplicate-id silent-shadow + skip-on-missing-shipped-files masking + exit-code-pin slop. Plateau at iter-2.
- **Sprint-1D #735 (`cdedd3dd`)** — cross-runtime golden test corpus (T1.11 + T1.12) — 12 fixture YAMLs at `tests/fixtures/model-resolution/` covering each SDD §7.6.3 scenario + 3 byte-equal runtime runners (bash + python + TypeScript) parsing the same `generated-model-maps.sh` source-of-truth + 4 CI workflows including the `cross-runtime-diff.yml` byte-equality gate. Scope: Sprint 1D ships infrastructure only — runners consume `sprint_1d_query.alias` (alias-lookup subset). Full SDD §7.6.1 `input` + `expected` blocks preserved per-fixture for Sprint 2 T2.6 to extend. Each fixture's deferred markers ensure cross-runtime parity holds today. Subagent dual-review caught **CRIT-1 TS prototype walk** (`"toString" in modelIds` returned true; fixed via `Object.create(null)` + `hasOwn`), **CRITICAL-1 TS nested-object sort** (manual top-key sort doesn't recurse; fixed via `canonicalizeRecursive`), **CRITICAL-2 Python ensure_ascii=False** (Unicode escape divergence), **CRIT-3 env-override gate parity** (LOA_GOLDEN_* now mirror cycle-099 LOA_MODEL_RESOLVER_TEST_MODE pattern), **HIGH-3 pre-source sanitizer** (sources generated-model-maps.sh which would execute `$(...)`; strict-shape regex + outside-array hardening), **CRIT-2 bash YAML type discrimination** (yq `tag` check; uniform error markers across runtimes), **HIGH-1 npm ci --ignore-scripts** (preinstall RCE defense), **HIGH-2/MEDIUM-1 dead workflow_run trigger + paths filter additions**, **HIGH-4 dead explicit-pin code path** (fixture 02 now uses `anthropic:claude-opus-4-7` form). BB iter-2 plateau (one persistent false-alarm at 0.95 confidence — `local_yq` variable name mis-read as `local` keyword). 21 bats contract pins; ~448+21 cycle-099 cumulative bats. All 3 runtimes byte-equal locally + via CI cross-runtime-diff gate.
- **Sprint-2C #739 (`e06fd8d1`)** — model-adapter.sh overlay integration (T2.5). New `.claude/scripts/lib/overlay-source-helper.sh` (~330 LOC) exposes 5 public functions (`loa_overlay_init`, `loa_overlay_resolve_provider_id`, `loa_overlay_resolve_alias`, `loa_overlay_resolve_endpoint_family`, `loa_overlay_refresh_if_stale`). Adapter sources the helper at module load (function defs only — no I/O); `loa_overlay_init` runs INSIDE the `HOUNFOUR_FLATLINE_ROUTING=true` branch of `main()` so the legacy default path stays bit-identical to pre-cycle-099. Resolution chain reordered: overlay → resolve_provider_id → MODEL_TO_ALIAS → pass-through. **Sprint 2 runtime overlay end-to-end COMPLETE**: operators can now add `model_aliases_extra` entries to `.loa.config.yaml` and have them flow through to bash adapter calls. 49 new bats cases (37 unit + 7 integration + 5 version-mismatch). Subagent dual-review caught 18 findings: **2 CRITICAL** (CYP-F1 LOA_OVERLAY_MERGED unconditional override → 3-leg gate added; CYP-F2 bash -n misleading docstring → content-shape gate added rejecting `$(...)`+backticks+semicolons+pipes+non-allowlist chars) + **6 HIGH** (CYP-F3 python3 from $PATH → absolute-path resolution; CYP-F4 TOCTOU symlink → realpath+symlink-refuse; CYP-F5 lockfile O_NOFOLLOW → symlink check; CYP-F6 pre-poisoned arrays → unset before source; CYP-F7 mutable helper paths → readonly; GP-F1+CYP-F11 helper init in legacy path → moved to v2 branch + hook arg passthrough) + **4 MEDIUM** (GP-F3 diagnostics env var; GP-F4 H1 test rename; CYP-F8/GP-F9 awk header parser; CYP-F9 fingerprint validation; CYP-F10 alias charset + dot-dot) — all addressed pre-merge with regression-pin tests. **Bridgebuilder kaironic**: 3 iters; iter-2 (4 findings, 2 PRAISE+1 MED+1 LOW) addressed in `097a175b`; iter-3 (8 findings, 0 consensus, 3 disputed) addressed in `bbec0aed` — finding-rotation pattern + Anthropic-only API → plateau called per cycle-099 precedent. Admin-squashed.

- **Sprint-2B #738 (`83107f4f`)** — model-overlay-hook + writer + 4 AC tests (T2.3 + T2.4). Python startup hook at `.claude/scripts/lib/model-overlay-hook.py` (~1500 LOC) reads SoT + operator `model_aliases_extra`, validates via Sprint 2A's validator, atomically emits `.run/merged-model-aliases.sh`. Implements: shared-then-exclusive `flock` (5s/30s timeouts, env-overridable); SHA256 cache invalidation under shared lock; monotonic version header; `shlex.quote()` shell-escape per SDD §3.5 (6 rules) + belt-and-suspenders `..` rejection per `feedback_charclass_dotdot_bypass.md`; `chmod 0600` BEFORE rename; tempfile in same dir (NOT `$TMPDIR`); NFS detection blocklist with `LOA_ALLOW_NETWORK_FS_FOR_MERGED_ALIASES` opt-in; degraded read-only fallback (NFR-Op-6) with `LOA_OVERLAY_STRICT=1` opt-in; stale-lock recovery via retry-without-unlink + `kill -0`; `.run/overlay-state.json` corruption + future-version + auto-migration handlers per SDD §6.3.3. AC-S2.7 (26 bats) + AC-S2.8 (14 bats) + AC-S2.9 (106 pytest) + AC-S2.12 (3 latency bats; warm p95 ~19ms / cold p95 ~52ms in-process). 174 tests, 0 regressions on cycle-099 sentinel. Subagent dual-review caught 18 findings: **2 CRITICAL** (CYP-F1 lockfile O_NOFOLLOW + CYP-F2 stale-lock TOCTOU via os.unlink-and-reopen) + **5 HIGH** (GP-F1 future-version state-file routing + GP-F2 corruption-rebuild ts collision + CYP-F3 test-mode third-leg gate + CYP-F4 target_dir symlink redirect + CYP-F5 future-version downgrade) + **4 MEDIUM** (lock-timeout marker on success-path + dead `write_log` + unused imports + dead post-quote assertion + CYP-F6 lockfile-holder via held fd + CYP-F8 sticky `sys.path.insert` + CYP-F10 df/mount safe PATH + CYP-F11 degraded write OSError logged) — all addressed pre-merge. **Bridgebuilder kaironic plateau by API-unavailability**: 3 BB iters, all 3 providers (Anthropic 400 / OpenAI 404 / Google network) errored synchronously every iter; cycle-099 precedent (sprint-1A pattern) accepts API-unavailability as plateau condition. Pre-BB subagent dual-review provided substantive review surface; admin-squash documented in PR comment.

- **Sprint-1E.c.3.c #734 (`b8dea0f5`)** — final SSRF closure (T1.15 cont.) — strict CI flip + load_allowlist host validation + opt-in webhook allowlist. Three deliverables: (1) `tools/check-no-raw-curl.sh` strict scanner with heredoc-state tracking + word-boundary regex + suppression marker; CI guard flipped from `::warning::` to `::error::` + `exit 1`. (2) `_validate_allowlist_entries` rejects sentinel hosts (`*`, `?`, FULLWIDTH ASTERISK U+FF0A, ASTERISK OPERATOR U+2217, NUL/CR/LF/TAB control bytes) at LOAD time, fail-closed with provider+index in error. (3) `_webhook_send` / `_webhook_dispatch` refactor with opt-in toggle `model_health_probe.alert_webhook_endpoint_validator_enabled` (literal-lowercase-`true` only) + `webhook-hosts.json` empty-default allowlist. **Subagent dual-review caught CRITICAL `model-adapter.sh.legacy` exempt-blindness** (3 live raw-curl invocations invisible to `*.sh`-only glob) + **HIGH FULLWIDTH-ASTERISK U+FF0A bypass** of `_validate_allowlist_entries` — both fixed pre-merge with bats coverage. **gp HIGH heredoc-string-mention + same-line-opener bypasses** also caught and fixed. BB kaironic 2-iter plateau (iter-1 caught F2/F3/F4 marker-scope + suffix-class + echo-cmdsub bypasses; iter-2 caught F13 push.paths gap). 4 exempt files now: `endpoint-validator.sh` (wrapper), `mount-loa.sh` (bootstrap), `model-health-probe.sh` (legacy webhook), `model-adapter.sh.legacy` (deferred Sprint 4 sunset).

- **Sprint-2D.a+b #740 (`fc27b7cf`)** — FR-3.9 6-stage canonical resolver + bash twin (T2.6 partial). New `.claude/scripts/lib/model-resolver.py` (~750 LOC) — pure-function `resolve(merged_config, skill, role) -> dict` implementing all 6 stages (S1 explicit pin → S6 prefer_pro overlay) per SDD §1.5. Supports both dict-form and string-form alias entries (cycle-099 + cycle-095 back-compat via `_normalize_alias_entry`). `_has_ctrl_byte` rejects C0 control bytes at entry. `_canonicalize_dict_keys` stringifies non-string YAML keys (matches yq's silent stringification). New `model-resolver-output.schema.json` (Draft 2020-12, discriminated `oneOf` for resolution-level vs fixture-level errors, strict `additionalProperties:false` on `details`). Bash twin at `tests/bash/golden_resolution.sh` (~810 LOC) re-implements all 6 stages independently for cross-runtime parity verification. 41 new bats: 16 G + 23 P + 2 L. Cross-runtime-diff CI gate flipped to Python+bash byte-equality + JSON Schema validation (TS deferred to 2D.c). Production-yaml smoke resolves 21/21 framework agents via canonical resolver. Subagent dual-review caught **6 HIGH** all addressed pre-merge. **Bridgebuilder kaironic 2-iter plateau** by API-unavailability (Anthropic-only). Admin-squashed.

- **Sprint-2D.d #748 (T2.6 final closure)** — SC-14 property suite. New `tests/property/lib/property-gen.bash` (~580 LOC) — bash property generator with SHA-256-of-(seed,tag) deterministic random. 7 invariant generators with multi-flavour internal dispatch (INV3 has 8 flavours covering all S6 emission paths; INV2/4/5 have 2-3 flavours; INV6 covers fail-closed; INV7 is positive S5 control). New `tests/property/model-resolution-properties.bats` — 7 bats tests, one per FR-3.9 invariant. New per-PR + nightly workflows. Subagent dual-review caught **2 CRIT** (CYP I3 vacuous green, CYP I4 biconditional vacuous) + **10 HIGH** (CYP I1 model_id collision, GP I3 only S2 path, GP I4 dead biconditional, CYP I6 negative-only / no positive S5 control, GP I5 no S5 absence pin, CYP eval-on-positional, CYP paths trigger forward-compat hole, CYP iter=1 bypass attack, CYP TTY-injection on dump leak) + 6 selected MEDs all addressed pre-merge. **Bridgebuilder kaironic plateau by API-unavailability** (Anthropic-only signal; OpenAI 404 + Google network across iters) per cycle-099 precedent — F14 nightly cap reduction (100K→10K) addressed inline; other 11 findings split 5 PRAISE / 2 false-alarm MED / 4 cosmetic LOW. Local smoke: 100 iter × 7 invariants → 7/7 ok in ~3:30; CI smoke: 4m1s on ubuntu-latest. Coverage: 99-100 distinct configs/invariant in 100 seeds (was 82 for inv3 pre-fix). 0 sentinel regressions on adjacent sprint-2D parity bats (27 P + 16 G). Admin-squashed.

- **Sprint-2D.c #741 (`29c7a8a8`, v1.128.0)** — TS port via Python+Jinja2 codegen (T2.6 cont.). Mirrors sprint-1E.c.1 verbatim. Restores 3-way Python ↔ bash ↔ TS byte-equality gate. 4 new files: `.claude/adapters/loa_cheval/codegen/emit_model_resolver_ts.py` (Python emit module with realpath + symlink-refusal codegen-symlink-defense per cypherpunk MED-1 + ctrl_byte_pattern `/`-guard per gp MED-1 + source-hash cross-check), `.claude/scripts/lib/codegen/model-resolver.ts.j2` (~720 LOC Jinja2 template with `codepointCompare` for Python-parity sort + canonicalizeRecursive at resolve() entry per gp CRIT-1 + empty-dict tier_mapping fall-through per gp CRIT-2), `.claude/skills/bridgebuilder-review/resources/lib/model-resolver.generated.ts` (825 LOC committed output with SHA-256 of canonical Python source in DO-NOT-EDIT header), `.github/workflows/cycle099-sprint-2d-c-ts-tests.yml` (drift gate + parity tests). Updated: `tests/typescript/golden_resolution.ts` (consumes generated module + Sprint 2D shape), `.github/workflows/cross-runtime-diff.yml` (TS leg restored, 3-way byte-equality + JSON Schema validation extended to all 3 runners, repo-root absolute-path tsx invocation per BB iter-2 F2), `tests/integration/sprint-2D-resolver-parity.bats` (extended to 27 P-tests including new P16c TS direct ctrl-byte defense + P23 codegen drift gate + P24 hash cross-check via portable awk + P25 widened to skill/role/alias/tier-key positions). Subagent dual-review caught **2 CRIT + 3 HIGH + 8 MED + 10 LOW + 11 PRAISE** — all CRIT/HIGH and selected MED addressed pre-merge. **Bridgebuilder kaironic 2-iter plateau** by API-unavailability (Anthropic-only; finding-rotation + 3 PRAISE in BOTH iters = convergence). 45 Sprint 2D bats green; 0 cycle-099 sentinel regressions. Admin-squashed.

- **Sprint-2C #739 (`e06fd8d1`)** — model-adapter.sh overlay integration (T2.5). New `.claude/scripts/lib/overlay-source-helper.sh` (~330 LOC) exposes 5 public functions (`loa_overlay_init`, `loa_overlay_resolve_provider_id`, `loa_overlay_resolve_alias`, `loa_overlay_resolve_endpoint_family`, `loa_overlay_refresh_if_stale`). Adapter sources the helper at module load (function defs only — no I/O); `loa_overlay_init` runs INSIDE the `HOUNFOUR_FLATLINE_ROUTING=true` branch of `main()` so the legacy default path stays bit-identical to pre-cycle-099. Resolution chain reordered: overlay → resolve_provider_id → MODEL_TO_ALIAS → pass-through. **Sprint 2 runtime overlay end-to-end COMPLETE**: operators can now add `model_aliases_extra` entries to `.loa.config.yaml` and have them flow through to bash adapter calls. 49 new bats cases (37 unit + 7 integration + 5 version-mismatch). Subagent dual-review caught 18 findings: **2 CRITICAL** (CYP-F1 LOA_OVERLAY_MERGED unconditional override → 3-leg gate added; CYP-F2 bash -n misleading docstring → content-shape gate added rejecting `$(...)`+backticks+semicolons+pipes+non-allowlist chars) + **6 HIGH** (CYP-F3 python3 from $PATH → absolute-path resolution; CYP-F4 TOCTOU symlink → realpath+symlink-refuse; CYP-F5 lockfile O_NOFOLLOW → symlink check; CYP-F6 pre-poisoned arrays → unset before source; CYP-F7 mutable helper paths → readonly; GP-F1+CYP-F11 helper init in legacy path → moved to v2 branch + hook arg passthrough) + **4 MEDIUM** (GP-F3 diagnostics env var; GP-F4 H1 test rename; CYP-F8/GP-F9 awk header parser; CYP-F9 fingerprint validation; CYP-F10 alias charset + dot-dot) — all addressed pre-merge with regression-pin tests. **Bridgebuilder kaironic**: 3 iters; iter-2 (4 findings, 2 PRAISE+1 MED+1 LOW) addressed in `097a175b`; iter-3 (8 findings, 0 consensus, 3 disputed) addressed in `bbec0aed` — finding-rotation pattern + Anthropic-only API → plateau called per cycle-099 precedent. Admin-squashed.

**Cumulative**: ~778 cycle-099 bats tests on main (~733 prior + 45 from Sprint 2D after 2D.c regen: 16 G + 27 P + 2 L). 0 regressions. Drift-gate CI active across endpoint-validator + model-resolver. Strict v2 schema. **FR-3.9 canonical 6-stage resolver SHIPPED across all 3 runtimes** (Python canonical; bash twin for test parity; TS port via Python+Jinja2 codegen). **3-way cross-runtime-diff gate ACTIVE** — Python ↔ bash ↔ TS byte-equality + JSON Schema validation enforced on every PR. Production-yaml smoke verifies 21/21 framework agents resolve cleanly.

### Operator decision needed at session start

> **Sprint 2D.d is SHIPPED.** SC-14 property suite landed at #748 (v1.131.0 will auto-tag). **T2.6 is now fully closed.** 7 FR-3.9 invariants verified at 100 random configs/PR + 1000-iter nightly stress. Cumulative ~785 cycle-099 tests; 0 regressions. **Three-layer defense ACTIVE**: cross-runtime byte-equality (Python ↔ bash ↔ TS) + JSON Schema validation + property invariants — all enforced on every PR touching the resolver. Production-yaml smoke verifies 21/21 framework agents resolve cleanly. **Next: cycle-098 Sprint 4 (L4 graduated-trust, parked during cycle-099 urgency, now unblocked) OR Sprint 2E (T2.7+T2.8 tier_groups defaults + prefer_pro overlay operator-config wiring, ~5-7h)**.

**Sprint 2 scope** (per cycle-099 sprint plan; Sprint 2A + 2B + 2C + 2D.a+b + 2D.c SHIPPED, 10 tasks remain):
- ✅ T2.1 — JSON Schema (Sprint 2A #737)
- ⏳ T2.2 — Strict-mode loader (deferred; partially served by Sprint 2D's canonical Python loader)
- ✅ T2.3 — Python startup hook (Sprint 2B #738)
- ✅ T2.4 — `.run/merged-model-aliases.sh` writer (Sprint 2B #738)
- ✅ T2.5 — `model-adapter.sh` overlay integration (Sprint 2C #739)
- ✅ **T2.6 (Python canonical + bash twin)** — Sprint 2D #740
- ✅ **T2.6 (TS port via Python+Jinja2 codegen)** — Sprint 2D.c #741
- ✅ **T2.6 (SC-14 property suite)** — Sprint 2D.d #748 (T2.6 fully closed)
- ⏳ T2.7 — `tier_groups.mappings` probe-confirmed defaults
- ⏳ T2.8 — `prefer_pro_models` overlay with FR-3.4 legacy gate (semantics shipped in Sprint 2D resolver; T2.8 covers operator-config wiring)
- ⏳ T2.9 — Legacy-shape backward compat (semantics shipped in Sprint 2D S4; T2.9 covers FR-3.7 deprecation warnings)
- ⏳ T2.10 — Permissions baseline + acknowledge flag (FR-1.4)
- ⏳ T2.11 — Endpoint allowlist integration (T1.15 wrapping)
- ⏳ T2.12 — `model-invoke --validate-bindings` CLI
- ⏳ T2.13 — `LOA_DEBUG_MODEL_RESOLUTION=1` tracing
- ⏳ T2.14 — `.loa.config.yaml.example` worked examples
- ⏳ T2.16 — `network-fs-merged-aliases.md` runbook

**Sprint-2B candidate**: T2.3 + T2.4 (Python overlay hook + merged-aliases.sh writer). T2.2's "strict-mode loader" is structurally an existing-loader EXTENSION — but no such loader exists; deferred until T2.6 brings the canonical Python loader. Sprint-2B's natural slice is the runtime-overlay infrastructure that T2.6 will plug into.

**Sprint 2A → Sprint 2B integration handoff**: validator at `.claude/scripts/lib/validate-model-aliases-extra.{py,sh}` is invokable today. `validate(config, schema, block_path, framework_ids)` returns `(is_valid, errors, block_present)`. Sprint 2B's loader will call this at the right moment in the agent-startup sequence + plumb the validator into a CI gate.

Dependency chain: Sprint 2's T2.6 (full FR-3.9 resolver) extends Sprint 1D's runners — replacing the `deferred_to: "sprint-2-T2.6"` markers with real `resolution_path` arrays. The cross-runtime-diff gate from 1D becomes the parity guarantee for the full resolver. Sprint 2A's schema becomes the input-validation layer for the resolver.

**Followup-issues filed at merge** (BB iter-1 deferred LOWs to track in cycle-100 hardening sprint or Sprint 4 sunset):
- `model-adapter.sh.legacy` SSRF migration (BB iter-2 F5) — defer to Sprint 4 legacy sunset
- Scanner CRLF/BOM shebang detection (BB iter-2 F1) — cycle-100 hardening
- ANSI-C $'...' string heredoc-state tracking (BB iter-2 F2) — cycle-100 hardening
- `command -v` / `which` bypass via aliasing (cypherpunk LOW) — cycle-100 hardening
- ports-field load-time validation (BB iter-2 F12 PRAISE-suggestion) — cycle-100 if needed

---

## What's on main (cycle-099 inventory)

### Sprint-1A — codegen foundation (`78c59568`)

| Artifact | Path | Notes |
|---|---|---|
| Bun-compatible codegen | `.claude/skills/bridgebuilder-review/scripts/gen-bb-registry.ts` | 549 LOC; reads model-config.yaml via yq subprocess; emits TS |
| Generated truncation | `.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts` | TOKEN_BUDGETS map |
| Generated config registry | `.claude/skills/bridgebuilder-review/resources/config.generated.ts` | MODEL_REGISTRY map |
| Build pipeline | `.claude/skills/bridgebuilder-review/package.json::scripts.build` | `npm run build` invokes codegen before tsc |
| Drift-check entrypoint | `npm run gen-bb-registry:check` (exits 3 on stale) | Consumed by sprint-1B drift-gate |
| 33 bats tests | `tests/unit/gen-bb-registry-codegen.bats` | T1-T12 categories incl. prototype-pollution guard |
| tsx pinned | BB skill `package.json` devDeps | Closes supply-chain via `node_modules/.bin/tsx` |

### Sprint-1B — adapter migrations + drift gate (`7140ff1c`)

| Artifact | Path | Notes |
|---|---|---|
| Resolver lib | `.claude/scripts/lib/model-resolver.sh` | `resolve_alias` / `resolve_provider_id`; override gated behind `LOA_MODEL_RESOLVER_TEST_MODE=1` |
| RT model-adapter migration | `.claude/scripts/red-team-model-adapter.sh` | Sources resolver; prefer-resolver-fallback-to-local |
| RT cvds migration | `.claude/scripts/red-team-code-vs-design.sh` | `--model "$_opus_model_id"` (resolved via resolve_alias) |
| Default adapter migration | `.claude/scripts/model-adapter.sh` | Same pattern; cycle-082 keys preserved |
| Lockfile | `.claude/defaults/model-config.yaml.checksum` | SHA256 hex; verified by drift-gate |
| Drift-gate workflow | `.github/workflows/model-registry-drift.yml` | 3 jobs: lockfile-checksum, bash-codegen-check, ts-codegen-check |
| 6 lockfile tests | `tests/integration/lockfile-checksum.bats` | L1-L5 |
| 25 sentinel tests | `tests/integration/legacy-adapter-still-works.bats` | S1-S6 covering all migrations |

### Sprint-1E.c.3.a — bash caller migration (`848d9fac`)

| Artifact | Path | Notes |
|---|---|---|
| `endpoint_validator__guarded_curl` helper | `.claude/scripts/lib/endpoint-validator.sh` | New ~250 LOC. argv: `--allowlist <PATH>` (tree-restricted) + `--config-auth <FILE>` (content-gated) + `--url <URL>` + caller curl args. Hardened defaults: `--proto =https / --proto-redir =https / --max-redirs 10` |
| Per-caller allowlists | `.claude/scripts/lib/allowlists/{loa-providers,loa-anthropic-docs,openai}.json` | Narrow allowlists per caller domain (model APIs / oracle docs / openai-only) |
| `model-health-probe.sh` migration | `.claude/scripts/model-health-probe.sh` | 2 of 3 curl sites migrated (provider POST/GET); webhook (3rd) keeps raw curl with `[ENDPOINT-VALIDATOR-EXEMPT]` rationale + `--proto =https / --max-redirs 10` hardening; SSRF-rejection stderr captured to tempfile + `log_warn` audit emit |
| `anthropic-oracle.sh` migration | `.claude/scripts/anthropic-oracle.sh` | `fetch_source` migrated; `--tlsv1.2 --fail-with-body` preserved |
| `lib-curl-fallback.sh` migration | `.claude/scripts/lib-curl-fallback.sh` | `call_api` migrated (transitively closes `gpt-review-api.sh`); auth tempfile via `--config-auth`; exit 78 + 64 = NO retry |
| Smuggling defenses | `.claude/scripts/lib/endpoint-validator.sh` | `--config` / `-K` / `-K?*` / `--next` / `-:` REJECTED in caller args (cypherpunk CRITICAL); `--config-auth` file content-gated to `header = "..."` lines only (rejects `url=` / `next=` / `output=` / CR-byte / backslash-injection); positional URL strict-reject (any `^https?://` arg) |
| Allowlist tree-restriction | same | `realpath -e` resolves allowlist; rejects out-of-tree (cypherpunk HIGH); `LOA_ENDPOINT_VALIDATOR_TEST_MODE=1 + LOA_ENDPOINT_VALIDATOR_TEST_ALLOWLIST_DIR` test-only escape (cycle-098 L3 pattern) |
| 54 wrapper tests | `tests/integration/endpoint-validator-guarded-curl.bats` | G1-G8 (24): wrapper invariants + acceptance/rejection + argv parsing + exit-code propagation + ordering pin + sourcing API stability. S1 (4): smuggling-flag rejection. S2 (10): --config-auth content gate. T1 (4): allowlist tree-restriction. S3 (3): glued-form smuggling (--config=PATH, -KPATH, -K=PATH). S4 (4): positional URL rejection + false-positive guard. S5 (2): --config-auth argv position pin. S6 (3): strict-reject design boundary (--referer/--proxy/-e https://x rejected) |

### Sprint-1E.c.2 — DNS rebinding + redirect enforcement (`ada3584a`)

| Artifact | Path | Notes |
|---|---|---|
| `LockedIP` dataclass | `.claude/scripts/lib/endpoint-validator.py` | Frozen; `__post_init__` normalizes host (lowercase + trailing-dot strip) + ipaddress-validates ip + initial_ips. Forge defense at construction. |
| Error hierarchy | same | `EndpointDnsError` base; `DnsResolutionError` (getaddrinfo failure) + `DnsRebindingError` (rebinding / blocked-range / port-pivot) subclasses |
| `lock_resolved_ip()` | same | Resolve once, check ALL records (Happy Eyeballs defense), apply `cdn_cidr_exemptions` per SDD §1.9 (relaxing semantics — IPs in CIDR skip blocked-range check) |
| `verify_locked_ip()` | same | Re-resolve; accept if any locked initial_ip in fresh records (CDN round-robin tolerance); else raise DnsRebindingError |
| `validate_redirect()` | same | Same-host + **same-port** + same-IP enforcement; rejects port-pivot via redirect even when alt-port allowlisted |
| `validate_redirect_chain()` | same | Per-hop validation against locked endpoint; bounded by `max_hops` (default 10 per RFC 7231 §6.4) — prevents unbounded redirect-chain DoS |
| Load-time CIDR-permissive WARN | `_warn_overly_permissive_cidr` | Emits `[ALLOWLIST-OVERLY-PERMISSIVE]` on stderr for `cdn_cidr_exemptions` entries with prefix /0../4 (catches `0.0.0.0/0` copy-paste defeat) |
| 27 DNS-rebinding tests | `tests/integration/endpoint-validator-dns-rebinding.bats` | L (lock × 3) + V (verify × 3) + R (redirect × 4) + C (cdn_exemption × 4) + H (Happy Eyeballs × 1) + N (normalize/forge × 2) + P (port-pivot × 1) + X (chain × 3) + B (errors/warn × 2) + I (IPv6 × 4) |
| Dedicated CI | `.github/workflows/cycle099-sprint-1e-c2-dns-tests.yml` | timeout-minutes: 5; mocked DNS (offline) |

### Sprint-1E.c.1 — TS port via Python+Jinja2 codegen (`43a60225`)

| Artifact | Path | Notes |
|---|---|---|
| Jinja2 template | `.claude/scripts/lib/codegen/endpoint-validator.ts.j2` | ~430 LOC TS validator with `{{ }}` substitutions for canonical-Python constants |
| Python emit module | `.claude/adapters/loa_cheval/codegen/emit_endpoint_validator_ts.py` | spec_loader → constant extraction → render → `--check` mode does byte-diff + canonical-source-hash cross-check (catches tampered-canonical scenario) |
| Generated TS | `.claude/skills/bridgebuilder-review/resources/lib/endpoint-validator.generated.ts` | 489 LOC; DO NOT EDIT — header carries SHA-256 of canonical Python source |
| 37 parity tests | `tests/integration/endpoint-validator-ts-parity.bats` | 8 acceptance + 28 rejection (E1-E20 + E21-E28 review-remediation: percent-encoded dots, Unicode dots, soft-hyphen, backslash, IPv4-octal, IPv6 zone-id, IPv4-compat IPv6) + 1 drift gate |
| Dedicated CI | `.github/workflows/cycle099-sprint-1e-c-ts-tests.yml` | Two jobs: drift gate (--check) + parity tests (bats + tsx via BB skill node_modules) |
| Surrogate-aware filter | `_ts_escape_cp` in emit module | non-BMP codepoints use `\u{XXXXX}` brace form (cypherpunk MEDIUM remediation) |
| Authority pre-parse gate | `_validate_authority` in canonical Python | unified gate rejects `%`/`\\`/Unicode dot equivalents/soft-hyphen/zero-width controls/obfuscated IPv4 octets BEFORE either parser normalizes — closes 2 CRITICAL allowlist bypasses |

### Sprint-1E.b — centralized endpoint validator (`fbd7c048`)

| Artifact | Path | Notes |
|---|---|---|
| Validator (Python canonical) | `.claude/scripts/lib/endpoint-validator.py` | ~370 LOC; 8-step pipeline + IPv4 literal block (incl. AWS IMDS + RFC 1918 + decimal/hex/octal obfuscation) + userinfo reject + raw-control-byte gate (CR/LF/TAB/NUL pre-urlsplit); stdlib + idna 3.13 |
| Validator (bash wrapper) | `.claude/scripts/lib/endpoint-validator.sh` | Subprocess delegate hardened against argv smuggling (`--` separator + python -I) and BASH_SOURCE symlink swap (realpath -e + tree-confinement) |
| Test allowlist fixture | `tests/fixtures/endpoint-validator/allowlist.json` | Mirror of cycle-099 production providers (openai/anthropic/google/bedrock × 3 regions) |
| 72 cross-runtime tests | `tests/integration/endpoint-validator-cross-runtime.bats` | E0 userinfo, E1-E8 step rejection, A1-A9 acceptance, B1-B2 wrapper hardening, C1-C8 stream contract, P1-P2 parity |
| Dedicated CI | `.github/workflows/cycle099-sprint-1e-b-tests.yml` | Two jobs: parity tests + STRICT Python urllib.parse import-guard (5 import patterns; scope: .claude/{adapters,scripts,skills,commands,hooks}/ + tests/ + scripts/ if exists) |
| Pre-existing baseline | `.github/workflows/lint-pre-existing-urllib.txt` | 3 entries: bedrock_adapter.py, test_bedrock_redaction_adversarial.py, mock_server.py. Cycle-100 expiry target |

### Sprint-1E.a — hardening primitives (`cd1c2438`)

| Artifact | Path | Notes |
|---|---|---|
| Log-redactor (Python canonical) | `.claude/scripts/lib/log-redactor.py` | Stdlib-only; URL userinfo + 6 query-param secret patterns; case-insensitive name match with case preservation |
| Log-redactor (bash twin) | `.claude/scripts/lib/log-redactor.sh` | POSIX BRE; explicit `[Aa]`-style case classes; sed line-by-line; cross-runtime byte-identical |
| Migrate CLI driver | `.claude/scripts/loa-migrate-model-config.py` | argparse + ruamel.yaml + jsonschema; O_NOFOLLOW + 0o600 output; distinct error codes (MIGRATION-PRODUCED vs CONFIG-V2-INVALID) |
| Migrate lib (pure) | `.claude/scripts/lib/model-config-migrate.py` | `migrate_v1_to_v2()` + `detect_schema_version()`; deepcopy-safe; field-level report list |
| v2 JSON Schema | `.claude/data/schemas/model-config-v2.schema.json` | Strict `additionalProperties:false` at root + providers + modelEntry + agentBinding + permissionsBlock; agentBinding forbids tier-tag in `model:` field |
| 37 log-redactor tests | `tests/integration/log-redactor-cross-runtime.bats` | T1-T12 SDD §5.6.4 corpus + T8.4 caller-contract pin |
| 37 migrate tests | `tests/integration/migrate-model-config.bats` | M1-M18 incl. M13 security (symlink, mode, !!python/object), M14 tier_groups edges, M15 pure-function, M16 distinct error codes, M18 strict-mode |
| Dedicated CI | `.github/workflows/cycle099-sprint-1e-tests.yml` | ruamel.yaml + jsonschema pinned; runs both bats + production smoke against `.claude/defaults/model-config.yaml` + cycle-026 perms |

### Sprint-1C — matrix CI + runbook (`8b008b9b`)

| Artifact | Path | Notes |
|---|---|---|
| Matrix CI | `.github/workflows/model-registry-drift.yml::ts-codegen-check` | `[ubuntu-latest, macos-latest]` with platform-aware SHA256-pinned yq |
| Toolchain runbook | `grimoires/loa/runbooks/codegen-toolchain.md` | 168 lines; per-platform install steps; pinned versions |
| Verification script | `tools/check-codegen-toolchain.sh` | `_version_ge` via `sort -V`; CI invokes it on matrix runners |
| Bash codegen drift fix | `.claude/scripts/generated-model-maps.sh` | +5 lines for `claude-sonnet-4-5-20250929` (sprint-1A latent regression) |

---

## Brief A — Sprint 1D (cross-runtime golden corpus, T1.11 + T1.12)

Paste into a fresh Claude Code session:

```
Read grimoires/loa/cycles/cycle-099-model-registry/RESUMPTION.md FIRST and the section "Brief A". Then ship Sprint 1D.

Sprint-1D scope (T1.11 + T1.12 per cycle-099 sprint.md §1):
  - 12 golden fixture files at tests/fixtures/model-resolution/ covering
    SDD §7.6.3 scenarios: happy-path tier-tag, explicit-pin, missing-tier-
    fail-closed, legacy-shape-deprecation, override-conflict, extra-only-
    model, empty-config, unicode-operator-id, prefer-pro-overlay, extra-vs-
    override-collision, tiny-tier-anthropic, degraded-mode-readonly
  - 3 cross-runtime runners that consume the fixture corpus identically:
      tests/python/golden_resolution.py
      tests/bash/golden_resolution.bats
      tests/typescript/golden_resolution.test.ts
  - 4 CI workflows:
      .github/workflows/python-runner.yml
      .github/workflows/bash-runner.yml
      .github/workflows/bun-runner.yml
      .github/workflows/cross-runtime-diff.yml
    The cross-runtime-diff job downloads all three runners' artifacts and
    asserts byte-equality. Mismatch fails the build (SDD §7.6.2).

Caveat — the FR-3.9 6-stage resolver is sprint-2 scope. The 1D runners
should test what CURRENTLY exists (the codegen-derived MODEL_PROVIDERS /
MODEL_IDS lookup and the new generated-model-maps.sh / config.generated.ts
output) — i.e., the SUBSET of FR-3.9 behavior that's already implemented.
Sprint 2 will extend the corpus + runners as the full resolver lands.

Continue Path: cut feat/cycle-099-sprint-1d from main (8b008b9b+).

Tooling already in place from sprint-1C:
  - bats v1.10+ (existing repo dependency)
  - Python 3.13 (cheval venv per .claude/scripts/lib/cheval-venv/)
  - tsx via BB skill node_modules (npx --no-install tsx works after npm ci)
  - pyyaml (cheval requirement) — for the python runner
  - yq pinned v4.52.4 with darwin-arm64 SHA256

Quality-gate chain (sprint-1A/1B/1C precedent):
  1. Implement test-first: write golden_resolution.bats first as the canonical
     reference, then port to python and TS verifying byte-equal output
  2. Subagent review (general-purpose) + audit (paranoid cypherpunk) in parallel
  3. Bridgebuilder kaironic INLINE via .claude/skills/bridgebuilder-review/resources/entry.sh --pr <N>
  4. Admin-squash after kaironic plateau (typical: 2 iterations for code PRs)

Slice if needed:
  - 1D.a: 12 fixtures + bats runner + bash-runner.yml (smallest, fastest gate)
  - 1D.b: python runner + python-runner.yml
  - 1D.c: TS runner + bun-runner.yml + cross-runtime-diff.yml

Refs: SDD §7.6.3 (fixture corpus); Flatline SDD pass #1 SKP-002 CRITICAL 890
(this is the resolution).
```

---

## Brief B — Sprint 1E.c.2 (DNS rebinding + redirect enforcement) — SHIPPED at #731 ada3584a

Sprint-1E.a (T1.13 + T1.14) SHIPPED at #728 cd1c2438. Sprint-1E.b (T1.15 partial — Python canonical + bash wrapper + 8-step pipeline) SHIPPED at #729 fbd7c048. Sprint-1E.c.1 (T1.15 cont. — TS port via Jinja2 codegen) SHIPPED at #730 43a60225. **Sprint-1E.c.2 (T1.15 cont. — DNS rebinding + redirect enforcement) SHIPPED at #731 ada3584a.** **Sprint-1E.c.3.a (T1.15 cont. — first 3 bash callers + smuggling defenses) SHIPPED at #732 848d9fac.** Remaining T1.15 follow-ons: 1E.c.3.b remaining ~11 callers + 1E.c.3.c CI guard flip (Brief C below).

## Brief C — Sprint 1E.c.3.b (remaining bash callers) + 1E.c.3.c (CI guard flip)

Sprint-1E.c.3.a SHIPPED at #732 848d9fac with the wrapper + 3 callers (model-health-probe, anthropic-oracle, lib-curl-fallback). Remaining:
- 1E.c.3.b: ~11 scripts (`flatline-{semantic-similarity,learning-extractor,proposal-review,validate-learning,error-handler}.sh`, `constructs-*.sh`, `check-updates.sh`, `license-validator.sh`, `mount-loa.sh` (special-case bootstrap), `lib-curl-fallback`-style helpers)
- 1E.c.3.c: flip CI guard `.github/workflows/cycle099-sprint-1e-b-tests.yml` from informational warning to STRICT failure (curl/wget outside endpoint-validator.sh fails build); remove pre-existing-curl baseline if no entries left

Plus deferred from 1E.c.3.a:
- HIGH-2: reject `host: "*"` / `host: ""` at load time in `load_allowlist` (Python canonical) — defense-in-depth even though tree-restriction now closes the realistic substitution vector
- MEDIUM (webhook): opt-in webhook-host allowlist (`.claude/scripts/lib/allowlists/webhook-hosts.json`, empty by default; opt-in via `.loa.config.yaml`)
- LOW (subprocess DoS): batch-validate or document a probe-interval floor for hot-loop callers

The wrapper + smuggling defenses are stable; this sprint is straightforward "apply the same pattern to N more files".

Paste into a fresh Claude Code session:

```
Read grimoires/loa/cycles/cycle-099-model-registry/RESUMPTION.md FIRST and the section "Brief C". Then ship Sprint 1E.c.3.b.

Sprint-1E.c.3.b scope — Bash caller migration, remaining ~11 scripts:
  1E.c.3.a SHIPPED at #732 848d9fac. Wrapper + smuggling defenses + 3
  callers landed. Apply the same pattern (source endpoint-validator.sh +
  swap raw `curl` to `endpoint_validator__guarded_curl --allowlist X
  --config-auth Y --url Z [args]`) to:
    .claude/scripts/flatline-semantic-similarity.sh   (OpenAI embedding API)
    .claude/scripts/flatline-learning-extractor.sh    (multi-model)
    .claude/scripts/flatline-proposal-review.sh       (multi-model)
    .claude/scripts/flatline-validate-learning.sh     (multi-model)
    .claude/scripts/flatline-error-handler.sh         (retry helper — verify it actually shells out)
    .claude/scripts/check-updates.sh                  (github.com framework version check)
    .claude/scripts/constructs-*.sh                   (construct registry fetches)
    .claude/scripts/license-validator.sh
    .claude/scripts/mount-loa.sh                      (special case — see below)
    .claude/scripts/lib-content.sh                    (if it shells out)
  mount-loa.sh special case: bootstrap script CAN'T depend on .venv being
  present. Either (a) carve out with [ENDPOINT-VALIDATOR-EXEMPT] rationale +
  raw curl with --proto =https + github.com explicit URL match, OR (b) defer
  it as the LAST migration after the validator's Python dep ships separately.

Sprint-1E.c.3.c scope — flip CI guard:
  Edit .github/workflows/cycle099-sprint-1e-b-tests.yml: change the
  `endpoint-validator-import-guard::Bash — informational scan for curl/wget`
  step from `::warning::` (advisory) to `::error::` + `exit 1` (blocking).
  Should remain only ONE allowlist exception: `.claude/scripts/lib/
  endpoint-validator.sh` (the wrapper itself). Remove the
  lint-pre-existing-curl baseline file if no entries remain.
  (~30 min if 1E.c.3.b is clean.)

Continue Path: cut feat/cycle-099-sprint-1E.c.3.b from main (848d9fac+).

Reference: 1E.c.3.a's endpoint-validator-guarded-curl.bats (54 tests) is
the template for caller-migration smoke tests. The wrapper API is stable;
new callers need only:
  - source .claude/scripts/lib/endpoint-validator.sh (after lib-security.sh)
  - declare a CALLER_ALLOWLIST="${LOA_OVERRIDE:-$SCRIPT_DIR/lib/allowlists/<name>.json}"
  - swap `curl args URL` → `endpoint_validator__guarded_curl --allowlist X --url URL args`
  - if caller uses --config (auth tempfile), swap to --config-auth
  - if caller uses --next or -:, refactor (forbidden)
  - smoke-test the caller still works

Quality-gate chain (same as 1A/1B/1C/1E.a/1E.b/1E.c.1/1E.c.2/1E.c.3.a):
  1. Implement test-first (smoke tests for each migrated caller)
  2. Subagent dual-review (general-purpose + paranoid cypherpunk) in parallel
  3. Bridgebuilder kaironic INLINE via .claude/skills/bridgebuilder-review/resources/entry.sh --pr <N>
     (typical 2-iter convergence; iter-1 catches real defects, iter-2 cosmetic)
  4. Admin-squash after plateau (--admin --squash --delete-branch)
  5. RESUMPTION.md + memory update

Reference patterns from Sprint-1E.b (#729):
  - .claude/scripts/lib/endpoint-validator.py canonical pipeline (8 steps
    + IPv4 obfuscation + userinfo reject + control-byte gate)
  - .claude/scripts/lib/endpoint-validator.sh wrapper hardening pattern
    (`--` separator, realpath -e tree-confinement, python -I isolated)
  - tests/integration/endpoint-validator-cross-runtime.bats — 72 tests:
    E1-E8 step rejection codes, B1-B2 wrapper hardening, C6-C8 stream
    contract, P1-P2 byte-equal parity helpers
  - .github/workflows/cycle099-sprint-1e-b-tests.yml — STRICT urllib.parse
    import-guard with scope pre-filter (existing dirs only — closes the
    `set -e` × `grep -2-on-missing-dir` race that bit me locally)
  - .github/workflows/lint-pre-existing-urllib.txt — baseline-with-comments
    pattern for migration debt tracking

Tooling already in place:
  - .venv has idna 3.13 + ruamel.yaml + jsonschema pinned
  - For 1E.c.1 jinja2: pip install jinja2>=3.1 in .venv on first sub-PR
  - For 1E.c.2 socket.getaddrinfo + httpx: stdlib only; no new deps
  - bats v1.10+, jq, yq pinned (cycle-099 sprint-1C runbook)

Quality-gate chain (same as 1A/1B/1C/1E.a/1E.b):
  1. Implement test-first (bats parity test + golden corpus before code)
  2. Subagent dual-review (general-purpose + paranoid cypherpunk) in parallel
  3. Bridgebuilder kaironic INLINE via .claude/skills/bridgebuilder-review/resources/entry.sh
     (typical 2-iter convergence for code PRs)
  4. Admin-squash after plateau
  5. RESUMPTION.md update + memory write

Sprint-1E.b remediation lessons worth carrying forward:
  - `set -e` + `grep -rEln` against a missing dir → exit 2 fatal under bash -e
    Pre-filter scope arrays via `for d in ...; do [[ -d $d ]] && scope+=$d; done`
    BEFORE expanding into argv. Local interactive-shell smoke MISSES this; the
    workflow's default `bash -e` shell is the canonical CI test environment.
  - Stream-contract: rejection JSON to STDERR (per SDD §6.2), acceptance JSON
    to STDOUT. Bats `_validate_both` that does `2>&1` merge HIDES regressions.
    Add explicit C6/C7/C8 tests that capture only one stream at a time.
  - `python -I` (isolated mode) on subprocess invocations: ignores PYTHONPATH
    + user-site to defend against env-var-injected interpreter modules.
  - `realpath -e` + tree-confinement check before sourcing/exec'ing sibling
    scripts: prevents BASH_SOURCE symlink-swap attacks.
  - argv smuggling defense: bash wrappers MUST insert `--` before user-
    supplied URL/path values so argparse can't reinterpret them as flags.
    Pattern: `flags=("${@:1:$last_idx}"); url="${!#}"; "$py" "$tool" "${flags[@]}" -- "$url"`
  - Subagent verdict-counting at iter-2: persistent false-alarm = plateau
    signal. Sprint-1E.b iter-1+iter-2 BB both flagged the same imaginary
    "import urllib.parse" regex miss (verified by manual grep). Document
    the false alarm in commit and admin-squash.
  - Production-yaml smoke gate caught schema-vs-reality drift in 1E.a;
    matches the same pattern in 1E.b (real provider URLs in fixture).

Refs: SDD §1.9.1 (endpoint validator) + §6.5 (8-step canonicalization);
Flatline SDD pass #2 SKP-006 CRITICAL 870 + pass #3 IMP-002 HIGH_CONSENSUS 880.
```

---

## Brief I — next session candidates (post Sprint 2E + #751 + #752 + #754 + BB E2E verified)

**Status as of 2026-05-07**: cycle-099 Sprint 1 + 2A + 2B + 2C + 2D.a+b + 2D.c + 2D.d + **2E** all SHIPPED (21 PRs on main, v1.132.0). All three multi-model subsystems route top-tier models cleanly post the PR #751 + #752 wave AND verified end-to-end via PR #754. Issue #753 closed. Main HEAD `a212f18b`.

### Option A — BB end-to-end verification — ✅ SHIPPED at PR #754 (2026-05-07)

Triple-provider success on PR #754 (`fix(cycle-099): pin LC_ALL=C in gen-adapter-maps.sh for locale-immune codegen`):
- `anthropic/claude-opus-4-7` complete in 13.0s (872 in / 768 out)
- `openai/gpt-5.5-pro` complete in 152.9s (522 in / 4544 out)
- `google/gemini-3.1-pro-preview` complete in 7.0s (555 in / 227 out)

Consensus: 0 HIGH_CONSENSUS, 1 DISPUTED, 0 BLOCKER, 4 LOW_VALUE/PRAISE, 5 unique. Verdict: COMMENT. All 4 review artifacts posted (3 per-model + 1 enriched consensus). No Anthropic-only signal. The routing chain that PR #751 + #752 fixed is now verified end-to-end against a real PR via the path actual BB users hit. Memory: `project_cycle099_bb_e2e_verified.md`.

### Option B — cycle-099 T2.9-T2.16 operator-tooling

Cycle-099 Sprint 2 has 7 operator-tooling tasks remaining:
- T2.9 — Legacy-shape backward compat (FR-3.7 deprecation warnings)
- T2.10 — Permissions baseline + acknowledge flag (FR-1.4)
- T2.11 — Endpoint allowlist integration (T1.15 wrapping)
- T2.12 — `model-invoke --validate-bindings` CLI
- T2.13 — `LOA_DEBUG_MODEL_RESOLUTION=1` tracing
- T2.14 — `.loa.config.yaml.example` worked examples
- T2.16 — `network-fs-merged-aliases.md` runbook

These are small-to-medium tasks. T2.12 + T2.13 (validate-bindings + tracing) are the highest-value operator UX surfaces; T2.14 + T2.16 are docs. Could batch ~2-3 per sub-sprint.

### Option C — Cycle-098 Sprint 4 (L4 graduated-trust)

Read `grimoires/loa/cycles/cycle-098-agent-network/RESUMPTION.md` for the full Brief D handoff. Larger scope; possibly MAJOR if it introduces breaking changes to the L1-L7 envelope. Parked since 2026-05-04.

### Option D — Latent locale-fix — ✅ SHIPPED at PR #754 (2026-05-07)

`gen-adapter-maps.sh` now has `export LC_ALL=C` near the top (after `set -euo pipefail`), with explanatory comment block citing the PR #750 origin. Verified locale-immune across `en_AU.UTF-8 / C.UTF-8 / de_DE.UTF-8 / LANG-only` invocations — all four produce byte-identical output matching committed `generated-model-maps.sh`. Choice of `C` over `C.UTF-8`: universally available + matches established repo convention (4 prior generators use `export LC_ALL=C`). Memory: `feedback_locale_pin_in_codegen.md`.

### Recommendation (post A + D shipped)

**B next** (operator-tooling). Cycle-099 Sprint 2 has 7 remaining tasks; T2.12 (`model-invoke --validate-bindings`) and T2.13 (`LOA_DEBUG_MODEL_RESOLUTION=1` tracing) deliver the highest operator-UX value. Both build on the FR-3.9 6-stage resolver SHIPPED at Sprint 2D — they expose its decision-path to operators for both batch validation and runtime debugging. Could batch as one sub-sprint. **C deserves its own fresh context** (Sprint 4 is potentially MAJOR — read cycle-098 RESUMPTION first).

### Quick handover to next session

* Main HEAD: `a212f18b` (PR #754 merge — locale-pin + BB E2E verified)
* Latest releases: v1.130.0 (named milestone) → v1.131.0 (Sprint 2D.d) → v1.132.0 (Sprint 2E)
* Today's PRs: #748 (2D.d) → #750 (2E) → #751 (BB OpenAI routing) → #752 (gpt-5.5 temp + flatline SSOT) → #754 (locale-pin + BB E2E verification)
* Closed issues: #753 (cheval temperature on gpt-5.5)
* Pre-existing CI flakes (admin-merged through): macOS bash 3.2 (TS codegen), beads BHM tests (Shell Tests — `BHM-T1` + `BHM-T5` per #661)
* ~~Latent: `gen-adapter-maps.sh` locale-dependence~~ — RESOLVED at PR #754
* Memory entries written today: `project_top_models_routing_fixes.md`, `project_cycle099_sprint2e_shipped.md`, `feedback_bb_openai_endpoint_family_routing.md`, `project_cycle099_sprint2dd_shipped.md`, `project_v1130_named_release.md`, `feedback_named_release_pattern.md`, `project_cycle099_bb_e2e_verified.md`, `feedback_locale_pin_in_codegen.md`

---

## Brief H — Cycle-098 Sprint 4 (L4 graduated-trust) OR Sprint 2E (T2.7 + T2.8)  [HISTORIC — Sprint 2E SHIPPED at #750]

**Status as of 2026-05-06**: cycle-099 Sprint 1 + 2A + 2B + 2C + 2D.a+b + 2D.c + **2D.d SHIPPED** (18 PRs on main + #748 sprint-2D.d). **T2.6 fully closed.** Sprint 2D.d activates SC-14 property suite: 7 invariants × 100 random configs/PR + 1000-iter nightly stress. **FR-3.9 canonical resolver SHIPPED across all 3 runtimes** (Python canonical + bash twin + TS codegen). 3-way cross-runtime byte-equality + JSON Schema validation + property invariants all enforced on every PR. Production-yaml smoke resolves 21/21 framework agents.

### Option A — Cycle-098 Sprint 4: L4 graduated-trust audit-network feature

The work parked during cycle-099 urgency, now unblocked. Read `grimoires/loa/cycles/cycle-098-agent-network/RESUMPTION.md` for the full Brief D handoff. Ships as v1.131.0 (or v2.0.0 if it introduces breaking changes — audit before deciding).

### Option B — Sprint-2E: T2.7 + T2.8 (~5-7h)

- **T2.7** — `tier_groups.mappings` probe-confirmed defaults: framework `tier_groups.mappings` is currently sparse (per fixture corpus). Sprint 2E populates the full default map for each (tier × provider) cell, validated via probe (a quick health-check call to each provider's allowlisted endpoint). Failures emit warnings but don't block.
- **T2.8** — `prefer_pro_models` overlay operator-config wiring: Sprint 2D ships the resolver-side semantics (S6 stage). Sprint 2E plumbs the operator-config knob through the runtime overlay so operators can toggle it via `.loa.config.yaml::prefer_pro_models: true` and have it propagate to all skill resolutions (with FR-3.4 per-skill `respect_prefer_pro` gate for legacy shapes).

### Recommendation

**Option A (Cycle-098 Sprint 4)** unblocks weeks-old parked work. Cycle-099 main-thread is now closed (T2.6 fully shipped); resuming cycle-098 honors the original sprint sequencing. Read `grimoires/loa/cycles/cycle-098-agent-network/RESUMPTION.md` first — Sprint 4 may be MAJOR if it introduces breaking changes to the L1-L7 envelope.

If operator wants to keep cycle-099 momentum, Option B (Sprint 2E) is the natural successor — operator-visible config knobs land sooner, building on the resolver invariants now hard-pinned by Sprint 2D.d.

### Sprint 2D.d handoff (in place at HEAD post-merge)

- `tests/property/lib/property-gen.bash` — bash property generator (~580 LOC); SHA-256-of-(seed,tag) deterministic random across hosts. 7 invariant generators with multi-flavour internal dispatch (INV3 has 8 flavours; INV2/4/5 have 2-3; INV1/6/7 have 1-2).
- `tests/property/model-resolution-properties.bats` — 7 bats tests (I1-I7), 1 per FR-3.9 invariant + I7 positive S5 control. On-failure dump strips control bytes for safe CI logs.
- `.github/workflows/cycle099-sprint-2d-d-property.yml` — per-PR check at 100 iter × 7 invariants. Seed_base = `sha256(github.sha + github.run_id)[:8]` (cypherpunk MED-3 mitigation).
- `.github/workflows/cycle099-sprint-2d-d-property-nightly.yml` — cron `0 6 * * *` + workflow_dispatch with iter floor=100, cap=10000.

### Followup-issues filed at Sprint 2D.d merge (deferred non-blocking findings)

- **gp MED-3** (state-space coverage analysis) — covered in test header; cycle-100 if more analysis needed
- **gp MED-4** (IMP-007 collision not exercised in property suite) — fixture corpus already covers; cycle-100 hardening if duplication wanted in property layer
- **cypherpunk MED-2** (cancel-in-progress force-push masking) — branch-protection scope, not file-level
- **BB iter-1 LOW F1** (nightly seed_base in $GITHUB_STEP_SUMMARY) — UX nice-to-have, cycle-100
- **BB iter-1 LOW F5** (per-pick python3 subprocess perf) — 100-iter at 3:30 fits PR budget; cycle-100 if scaling becomes blocker
- **BB iter-1 false-alarms F3/F4/F6/F7/F8/F15** — verified non-issues, documented in commit
- All cosmetic LOWs from gp + cypherpunk reviews

---

## Brief G — Sprint 2D.d (SC-14 property suite) [HISTORIC — SHIPPED at #748]

**Status as of 2026-05-06**: cycle-099 Sprint 1 + 2A + 2B + 2C + 2D.a+b + 2D.c all SHIPPED (17 PRs on main, v1.128.0). HEAD at `29c7a8a8`. **FR-3.9 canonical resolver SHIPPED across all 3 runtimes** (Python canonical + bash twin + TS codegen). 3-way cross-runtime byte-equality + JSON Schema validation enforced on every PR. Production-yaml smoke resolves 21/21 framework agents.

### Option A — Sprint-2D.d: SC-14 property suite (~3-5h, closes T2.6)

Property-based testing per cycle-099 SC-14 + DD-6:
- Bash property generator at `tests/property/lib/property-gen.bash` (~150 lines per SDD §5 — emits N random valid configs).
- Property test runner at `tests/property/model-resolution-properties.bats` exercising 6 invariants per FR-3.9:
  1. (1) and (4) both present → (1) wins
  2. Two same-priority mechanisms always produce error
  3. prefer_pro overlay always applied last (step 6)
  4. Deprecation warning emitted ⟺ stage (4) was the resolution path
  5. Operator-extra-tier resolves before framework-default-tier when both define same provider mapping
  6. Unmapped tier produces FR-3.8 fail-closed error, never silent fallback to (5)
- ~100 random scenarios per CI run; 1000-iter stress nightly via `cron: '0 6 * * *'`.

Acceptance criteria:
- AC-S2.d.1: All 6 invariants pass on ~100 random configs per PR check.
- AC-S2.d.2: 1000-iter nightly stress passes with 0 invariant violations.
- AC-S2.d.3: Property runner shells out to canonical Python resolver via `python3 -m model_resolver resolve`.

### Option B — Sprint-2E: T2.7 + T2.8 (~5-7h)

- **T2.7** — `tier_groups.mappings` probe-confirmed defaults: framework `tier_groups.mappings` is currently sparse (per fixture corpus). Sprint 2E populates the full default map for each (tier × provider) cell, validated via probe (a quick health-check call to each provider's allowlisted endpoint). Failures emit warnings but don't block.
- **T2.8** — `prefer_pro_models` overlay operator-config wiring: Sprint 2D ships the resolver-side semantics (S6 stage). Sprint 2E plumbs the operator-config knob through the runtime overlay so operators can toggle it via `.loa.config.yaml::prefer_pro_models: true` and have it propagate to all skill resolutions (with FR-3.4 per-skill `respect_prefer_pro` gate for legacy shapes).

### Recommendation

**Option A (2D.d) first** — closes T2.6 entirely. Property testing is the canonical "fortify-resolver" follow-up; running 100-1000 random configs against the canonical Python resolver finds invariant violations that fixture-corpus testing can't surface. Smaller scope (~3-5h) and orthogonal to operator-config plumbing work.

If operator wants to start exposing the resolver to operators (T2.7 + T2.8), Option B is correct — but the full T2.6 closure (2D.d) provides hard guarantees that operator-config plumbing then can rely on.

### Sprint 2D.c handoff (in place at HEAD `29c7a8a8`)

- `.claude/scripts/lib/codegen/model-resolver.ts.j2` — Jinja2 template (~720 LOC TS resolver)
- `.claude/adapters/loa_cheval/codegen/emit_model_resolver_ts.py` — Python emit module + drift gate
- `.claude/skills/bridgebuilder-review/resources/lib/model-resolver.generated.ts` — committed generated output (regen via `python3 -m loa_cheval.codegen.emit_model_resolver_ts > <path>`)
- `tests/typescript/golden_resolution.ts` — Sprint 2D shape, imports generated module
- `.github/workflows/cross-runtime-diff.yml` — 3-way byte-equality gate (Python ↔ bash ↔ TS)
- `.github/workflows/cycle099-sprint-2d-c-ts-tests.yml` — drift gate + parity tests
- `tests/integration/sprint-2D-resolver-parity.bats` — 27 P-tests (3-way + new P16c, P23, P24, P25)

Cut: `feat/cycle-099-sprint-2D.d` (or `2E`) from main (`29c7a8a8`+).

Quality-gate chain (cycle-099 standard, established across 17 PRs):
1. Test-first
2. Subagent dual-review (gp + paranoid cypherpunk) IN PARALLEL via background agents
3. Bridgebuilder kaironic INLINE — **NOTE**: BB API outage (Anthropic-only signal across iters) observed on Sprint 2B + 2C + 2D.a+b + 2D.c. Cycle-099 precedent accepts API-unavailability as plateau; pre-BB subagent review provides substantive surface.
4. Admin-squash after plateau
5. Update RESUMPTION.md + memory

Beads still UNHEALTHY/MIGRATION_NEEDED ([#661](https://github.com/0xHoneyJar/loa/issues/661)). `--no-verify` policy active.

### Followup-issues filed at Sprint 2D.c merge (deferred non-blocking findings)

- **gp MED-3** (sprint-2D.c): `_load_canonical()` called twice in --check mode — minor perf. Cycle-100 hardening.
- **gp MED-4** (sprint-2D.c): Stage 3 detail strings differ on edge cases not in fixture corpus. Latent.
- **gp LOW-2/3/4** (sprint-2D.c): cosmetic / sprint-1E.c.1 inheritance.
- **cypherpunk LOW-3/4/5/6** (sprint-2D.c): npx tsx (already fixed but pattern note), ESM/CJS __dirname (no root package.json today), P16 alternation (intentional), P16c/P25 heredoc (paths bounded).
- **BB iter-1 F1/F2/F6** + **iter-2 F3/F5/F6/F7/F8** (sprint-2D.c): aesthetic / nice-to-have. Cycle-100 hardening sprint.

---

## Brief F — Sprint 2D.c (TS port via Python+Jinja2 codegen) [HISTORIC — SHIPPED at #741 29c7a8a8]

**Status as of 2026-05-06**: cycle-099 Sprint 1 + 2A + 2B + 2C + 2D.a+b all SHIPPED (16 PRs on main). HEAD at `fc27b7cf` (Sprint 2D.a+b merge). FR-3.9 canonical resolver shipped Python-canonical + bash twin; 41 new bats; cross-runtime byte-equality enforced for Python+bash. TS leg of cross-runtime-diff gate is **temporarily deferred** — TODO marker in `.github/workflows/cross-runtime-diff.yml` references Sprint 2D.c.

### Option A — Sprint-2D.c: TS port via Python+Jinja2 codegen (~4-6h, recommended next)

Mirrors sprint-1E.c.1's pattern verbatim. Same shape:

- Jinja2 template at `.claude/scripts/lib/codegen/model-resolver.ts.j2` (~600 LOC TS resolver) with `{{ }}` substitutions for canonical Python constants (stage labels, error codes, tier names).
- Python emit module at `.claude/adapters/loa_cheval/codegen/emit_model_resolver_ts.py` — spec_loader → constant extraction → render → `--check` mode does byte-diff + canonical-source-hash cross-check (catches tampered-canonical scenario).
- Generated TS at `.claude/skills/bridgebuilder-review/resources/lib/model-resolver.generated.ts` (DO-NOT-EDIT header carries SHA-256 of canonical Python source).
- Update `tests/typescript/golden_resolution.ts` to consume the generated TS resolver and emit Sprint 2D shape.
- Reactivate the TS leg of `.github/workflows/cross-runtime-diff.yml` — 3-way byte-equality gate (Python ↔ bash ↔ TS).
- New CI workflow `cycle099-sprint-2d-c-ts-tests.yml` mirroring `cycle099-sprint-1e-c-ts-tests.yml` (drift gate `--check` mode + parity tests).

Acceptance criteria:
- AC-S2.c.1: TS runner emits canonical-JSON byte-identical to Python+bash for all 12 fixtures + all 9 P-series synthesized cases.
- AC-S2.c.2: cross-runtime-diff CI gate fails when TS diverges.
- AC-S2.c.3: drift gate fails when canonical Python source changes without regenerating the TS module (hash cross-check).

Critical risk: **TS-vs-Python parser-confusion** is the central risk class (sprint-1E.c.1 pattern caught 2 CRITICAL allowlist bypasses pre-merge). Apply unified pre-parse gate in BOTH runtimes for any string-form alias parsing. Use `\u{XXXXX}` brace form for non-BMP codepoints (sprint-1E.c.1 cypherpunk MEDIUM lesson).

References:
- `feedback_cross_runtime_parity_traps.md` (THE central reference — 6 known classes)
- `project_cycle099_sprint1ec1_shipped.md` — sprint-1E.c.1 pattern this mirrors
- `feedback_bb_api_unavailability_plateau.md` (BB plateau pattern — same outage observed across Sprint 2B + 2C + 2D)

### Option B — Sprint-2D.d: SC-14 property suite (~3-5h)

Property-based testing per cycle-099 SC-14 + DD-6:
- Bash property generator at `tests/property/lib/property-gen.bash` (~150 lines per SDD §5 — emits N random valid configs).
- Property test runner at `tests/property/model-resolution-properties.bats` exercising 6 invariants per FR-3.9:
  1. (1) and (4) both present → (1) wins
  2. Two same-priority mechanisms always produce error
  3. prefer_pro overlay always applied last (step 6)
  4. Deprecation warning emitted ⟺ stage (4) was the resolution path
  5. Operator-extra-tier resolves before framework-default-tier when both define same provider mapping
  6. Unmapped tier produces FR-3.8 fail-closed error, never silent fallback to (5)
- ~100 random scenarios per CI run; 1000-iter stress nightly via `cron: '0 6 * * *'`.

Acceptance criteria:
- AC-S2.d.1: All 6 invariants pass on ~100 random configs per PR check.
- AC-S2.d.2: 1000-iter nightly stress passes with 0 invariant violations.
- AC-S2.d.3: Property test runner shells out to canonical Python resolver (no separate TS path; 2D.c provides 3-way for fixture corpus, 2D.d provides invariant coverage for the property space).

### Recommendation

**Option A first (2D.c)** — completes the TS arm of cross-runtime parity that the existing cross-runtime-diff gate is designed for. Without 2D.c, the TS production runtime (Bridgebuilder dist) lacks invariant verification on the new 6-stage shape until 2D.c lands. 2D.d adds orthogonal coverage but doesn't close the TS gap.

If operator wants property-suite coverage in one PR, Option B (2D.d) is correct — but expect that 2D.c becomes the highest-priority follow-up regardless.

### Sprint 2D.a+b handoff (in place at HEAD `fc27b7cf`)

- `.claude/scripts/lib/model-resolver.py` — canonical pure-function `resolve(merged_config, skill, role) -> dict`
- `.claude/data/trajectory-schemas/model-resolver-output.schema.json` — Draft 2020-12 with discriminated `oneOf` (resolution-level vs fixture-level errors)
- `tests/bash/golden_resolution.sh` — bash twin for parity verification (test code only; production bash sources `merged-aliases.sh` per Sprint 2C)
- `tests/python/golden_resolution.py` — Python golden runner consuming `expected.resolutions[]`
- `tests/integration/sprint-2D-resolver-parity.bats` — 23 P-series tests exercising stages + IMP-007 + FR-3.4 + ctrl-byte rejection + string-form alias parity + mixed-key stringification
- `tests/perf/model-resolver-latency.bats` — warm hot-path p95 + determinism micro-bench
- `.github/workflows/cross-runtime-diff.yml` — TODO(cycle-099-sprint-2D.c) marker for TS gate restoration
- `.github/workflows/cycle099-sprint-2d-tests.yml` — production-yaml smoke (≥100% framework agents must resolve)

Cut: `feat/cycle-099-sprint-2D.c` (or `.d`) from main (`fc27b7cf`+).

Quality-gate chain (cycle-099 standard, established across 16 PRs):
1. Test-first
2. Subagent dual-review (gp + paranoid cypherpunk) IN PARALLEL via background agents
3. Bridgebuilder kaironic INLINE — **NOTE**: BB API failures observed on Sprint 2B + 2C + 2D (Anthropic-only signal across all 3 sub-sprints). Cycle-099 precedent accepts API-unavailability as plateau; pre-BB subagent review provides substantive surface.
4. Admin-squash after plateau
5. Update RESUMPTION.md + memory

Beads still UNHEALTHY/MIGRATION_NEEDED ([#661](https://github.com/0xHoneyJar/loa/issues/661)). `--no-verify` policy active per cycle-099 sprint plan §`--no-verify` Safety Policy.

### Followup-issues filed at Sprint 2D merge (deferred non-blocking findings)

- BB iter-2 F001 HIGH (TS gate dropped without explicit issue link) — addressed by Sprint 2D.c
- cypherpunk MED-5 (reserved-key skill name collision) — defense-in-depth; cycle-100 hardening
- cypherpunk MED-6 (`_golden.bash.jsonl` co-located with `*.yaml`) — cosmetic
- gp LOW-2 (multi-resolution sort order coverage) — partially addressed by fixture 06 multi-resolution; full coverage in 2D.d
- gp LOW-4 (cross-runtime-diff.yml triggers list `model-resolver.sh` which doesn't exist) — cycle-100 cleanup
- All other LOWs from BB iter-1 + iter-2 — cycle-100 hardening sprint

---

## Brief E — Sprint 2C (T2.5 model-adapter integration OR T2.6 6-stage resolver) [HISTORIC]

**Status as of 2026-05-06**: cycle-099 Sprint 1 + 2A + 2B all SHIPPED (14 PRs on main). HEAD at `83107f4f` (Sprint 2B merge). The runtime-overlay infrastructure is now in place: `model-overlay-hook.py` writes `.run/merged-model-aliases.sh` atomically; bash consumers can `source` it. T2.5 is the consumer-side integration; T2.6 is the canonical resolver.

**Sprint-2C candidates** (operator's choice — smaller-scope OR larger-scope):

### Option A — Sprint-2C.A: T2.5 only (model-adapter.sh integration) — ~2-3h

Smallest viable next step. Wires `model-adapter.sh` to source `.run/merged-model-aliases.sh` with version-mismatch detection (re-read after exclusive-lock acquisition on mismatch). Uses Sprint 2B's monotonic version header to detect cross-process state drift.

Test surface (1-2 bats files):
- `tests/integration/model-adapter-overlay-source.bats` — source merged file, query alias, verify provider+api_id+endpoint_family+pricing match
- `tests/integration/model-adapter-version-mismatch.bats` — race two adapter invocations across a regen; verify late-reader sees consistent state

Sprint 2A's validator is invokable; Sprint 2B's hook produces the merged file. The integration is the LAST layer of the Sprint 2 runtime overlay. After T2.5 ships, operators can add `model_aliases_extra` entries to `.loa.config.yaml` and have them flow through to bash adapter calls without code changes.

Risk profile: low. No new flock semantics; no atomic-write surface. Just bash sourcing + version-string parse.

### Option B — Sprint-2C.B: T2.6 (FR-3.9 6-stage resolver) — ~6-8h

Larger-scope. Implements the full 6-stage resolution pipeline per SDD §1.5 + FR-3.9: explicit pin → operator tier_groups → framework tier_groups → legacy shape → framework default → prefer_pro_models overlay. Python canonical + bash twin matching cycle-099's other multi-runtime patterns.

Extends Sprint 1D's golden corpus runners — replacing the `deferred_to: "sprint-2-T2.6"` markers with real `resolution_path` arrays. The cross-runtime-diff CI gate then guarantees parity.

Test surface (substantial):
- `tests/integration/model-resolution-golden.bats` — 12 fixtures × 4 skills = ~48 cases
- Property suite: `tests/property/model-resolution-properties.bats` (SC-14, 6 invariants × ~100 random configs)
- Updates to all 3 runtime runners (bash/python/TS) in `tests/python/golden_resolution.py`, `tests/bash/golden_resolution.bats`, `tests/typescript/golden_resolution.test.ts`

Risk profile: medium-high. Cross-runtime parity is the central concern (per `feedback_cross_runtime_parity_traps.md` — 6 classes of silent bash/python/TS divergence). Sprint 1D infrastructure makes this tractable but each runner needs careful mirror.

### Recommendation

**Option A first (T2.5)** — small, low-risk, completes the Sprint 2 runtime overlay end-to-end. T2.6 makes more sense as Sprint-2D after T2.5 proves the consumer integration. This matches the cycle-099 sub-sprint pattern (1A → 1B → 1C → 1E.a → 1E.b → 1E.c.{1,2,3.a,3.b,3.c} → 1D — small slices, each independently shippable).

If operator wants the bigger lift in one shot, Option B (T2.6) is correct — but expect 3+ BB iters and more subagent-review surface for the cross-runtime parity assertions.

### Sprint 2B handoff (in place at HEAD `83107f4f`)

- `.claude/scripts/lib/model-overlay-hook.py` — full hook; CLI `--probe-shell-safety` for AC-S2.7 corpus testing
- `.run/merged-model-aliases.sh` — populated on first hook invocation with `# version=N` + `# source-sha256=<hash>` header
- `.run/overlay-state.json` — degraded-mode tracking; future-version + auto-migration handlers
- `.claude/data/trajectory-schemas/overlay-state.schema.json` — schema_version 1
- Test-mode override: `LOA_OVERLAY_TEST_MODE=1 + LOA_OVERLAY_PROC_MOUNTS_PATH_FOR_TEST + (BATS_VERSION OR PYTEST_CURRENT_TEST)` (three-leg gate)
- Strict mode opt-in: `LOA_OVERLAY_STRICT=1` (default is degraded-fallback per NFR-Op-6)
- Network-fs opt-in: `LOA_ALLOW_NETWORK_FS_FOR_MERGED_ALIASES=1` per SDD §6.6
- Lock-timeout overrides: `LOA_OVERLAY_LOCK_TIMEOUT_{SHARED,EXCLUSIVE}_MS`

Cut: `feat/cycle-099-sprint-2C` from main (`83107f4f`+).

Quality-gate chain (cycle-099 standard, established across 14 PRs):
1. Test-first
2. Subagent dual-review (gp + paranoid cypherpunk) IN PARALLEL
3. Bridgebuilder kaironic INLINE — **NOTE**: BB API failures observed on Sprint 2B (3 iters, all 3 providers errored synchronously). Cycle-099 precedent (sprint-1A) accepts API-unavailability as plateau condition; pre-BB subagent review provides substantive review surface. If BB fails on 2C, document and proceed.
4. Admin-squash after plateau
5. Update RESUMPTION.md + memory

Beads still UNHEALTHY/MIGRATION_NEEDED (#661). `--no-verify` policy active per cycle-099 sprint plan.

---

## Brief D — Sprint 2B (T2.3 + T2.4 — Python overlay hook + merged-aliases.sh writer) [SHIPPED]

**Status as of 2026-05-06**: cycle-099 Sprint 1 COMPLETE (12 PRs). Sprint 2A SHIPPED (#737 `ace5a206`). 13 cycle-099 PRs total on main; HEAD at `75321b90` (RESUMPTION.md update post Sprint 2A merge).

Sprint-2B scope (T2.3 + T2.4 per cycle-099 sprint.md §Sprint 2):

- **T2.3** — Python startup hook `.claude/scripts/lib/model-overlay-hook.py` per SDD §1.4.4 + DD-4. Reads merged config (SoT ∪ operator extras), validates `model_aliases_extra` via Sprint 2A's `validate-model-aliases-extra.py`, writes `.run/merged-model-aliases.sh` for bash consumers. Uses cheval venv per §10.1.4.
- **T2.4** — `.run/merged-model-aliases.sh` writer with:
  - Atomic-write via tempfile in same directory + `os.rename(2)` (cross-filesystem `rename` is non-atomic; SDD §1.4.4 explicitly forbids `${TMPDIR:-/tmp}`)
  - flock exclusive/shared semantics on `.run/merged-model-aliases.sh.lock` per FR-1.9
  - SHA256 invalidation under shared lock; skip regen if input hash matches header
  - Monotonic version header (incrementing on each successful write)
  - `shlex.quote()` shell-escape for operator-controlled values per SDD §3.5
  - `chmod 0600` on the temp file BEFORE `rename()` (avoid brief world-readable window)

Acceptance criteria (cycle-099 sprint.md AC-S2.7 + AC-S2.8 + AC-S2.9 + AC-S2.12):

- AC-S2.7 — `tests/integration/merged-aliases-shell-escape.bats` passes — operator-controlled values escaped via `shlex.quote()` survive bash sourcing without injection
- AC-S2.8 — `tests/integration/flock-network-fs-detection.bats` passes — NFS/SMB detection blocklist refuses without `LOA_ALLOW_NETWORK_FS_FOR_MERGED_ALIASES=1`
- AC-S2.9 — `tests/unit/model-overlay-hook.py.test` passes (pytest unit tests)
- AC-S2.12 — `tests/integration/overlay-resolution-latency.bats` p95 ≤50ms warm cache, p95 ≤500ms cold (NFR-Perf-1; SDD §7.5.1)

**T2.5 follow-on**: `model-adapter.sh` updated to source `.run/merged-model-aliases.sh` with version-mismatch detection (re-read after exclusive-lock acquisition on mismatch). May ride alongside 2B or split out.

**Sprint 2A handoff (already in place):**

- Schema: `.claude/data/trajectory-schemas/model-aliases-extra.schema.json`
- Validator API: `validate(config, schema, block_path, framework_ids) -> (is_valid, errors, block_present)`
  - `block_present` distinguishes "operator hasn't opted in" (vacuous success) from "operator opted in and config valid"
  - Sprint 2B's hook calls this BEFORE constructing the merged-aliases output
- Validator CLI: `--config / --block / --schema / --framework-defaults / --no-collision-check / --json / --quiet`
- Exit codes: 0 valid · 78 invalid · 64 usage error
- Bash twin: `.claude/scripts/lib/validate-model-aliases-extra.sh` (mirrors endpoint-validator pattern)

Cut: `feat/cycle-099-sprint-2B` from main (`75321b90`+).

Quality-gate chain (cycle-099 standard, established across 13 PRs):

1. **Implement test-first**: AC-S2.7 / AC-S2.8 / AC-S2.9 / AC-S2.12 bats files first. Each test should have positive control + named regression IDs (cycle-099 traceability convention).
2. **Subagent dual-review** (general-purpose + paranoid cypherpunk) IN PARALLEL via `Agent({subagent_type: "general-purpose", run_in_background: true})`. Paranoid cypherpunk catches CRITICAL/HIGH security bypasses pre-merge across cycle-099 (e.g., `permissions:{}` FR-1.4 bypass on Sprint 2A, `*.sh`-only-glob CRITICAL on Sprint 1D).
3. **Bridgebuilder kaironic INLINE**: `.claude/skills/bridgebuilder-review/resources/entry.sh --pr <N>`. Typical 2-iter plateau for code PRs; iter-1 catches real defects, iter-2 catches polish + plateau-signal false alarms (persistent low-confidence findings = plateau).
4. **Admin-squash** after plateau: `gh pr merge <N> --admin --squash --delete-branch`.
5. **Update RESUMPTION.md + memory** entries.

Specific SDD references for T2.3/T2.4:

- SDD §1.4.4 — `model-overlay-hook.py` purpose + concurrency + atomic-write + 0600 permission
- SDD §3.5 — `merged-aliases.sh` shape spec (shell-escape rules, version header)
- SDD §6.3 — flock acquisition order (shared first; upgrade to exclusive if write needed); 5s shared / 30s exclusive timeouts; env-var configurable via `LOA_OVERLAY_LOCK_TIMEOUT_*_MS`
- SDD §6.6 — NFS/SMB advisory-flock hazard; `LOA_ALLOW_NETWORK_FS_FOR_MERGED_ALIASES=1` opt-in
- SDD §6.3.2 — degraded read-only fallback default; `LOA_OVERLAY_STRICT=1` opt-in for fail-closed; stale-lock recovery via `kill -0` PID check; NFR-Op-6 contract
- SDD §7.5.1 — latency measurement methodology

Known cycle-099 gotchas to pre-empt (memory entries available):

- **Cross-runtime parity traps** (`feedback_cross_runtime_parity_traps.md`) — JSON Unicode (`ensure_ascii=False`), nested-key-sort recursion, JS `in`-walks-prototype, YAML scalar type semantics, bash sourcing executes shell metas. Even though Sprint 2B is Python+bash (no TS yet), the patterns apply.
- **Charclass dot-dot bypass** (`feedback_charclass_dotdot_bypass.md`) — pair `[a-zA-Z0-9._-]+` regex with `[[ "$input" != *..* ]]` companion check; Sprint 2A's schema added `not.anyOf` rejection. Apply same pattern in T2.4's id usage.
- **Allowlist tree-restriction** (`feedback_allowlist_tree_restriction.md`) — env-var overrides MUST require explicit TEST_MODE gate (mirroring `LOA_MODEL_RESOLVER_TEST_MODE` + `BATS_TEST_DIRNAME`).
- **Curl --config smuggling** (`feedback_curl_config_smuggling.md`) — N/A for 2B (no HTTP); reference for any wrapper-pattern reuse.
- **Subshell export gotcha** (`feedback_subshell_export_gotcha.md`) — bash `export` inside `$(...)` doesn't propagate; T2.4's atomic-write logic should call helpers BEFORE entering subshells.
- **Stash safety** (`.claude/rules/stash-safety.md`) — never pipe `git stash` output through `tail`; never append `|| true`. Use `stash_with_guard` helper. T2.4's tests around lock-recovery must respect this if they shell out to git.

Backwards-compat invariants (cycle-099 G-2):

- **Cycle-098 vintage `.loa.config.yaml`** (without any of the new top-level fields) MUST resolve identically before/after Sprint 2B (AC-S2.3 in cycle-099 sprint.md). T2.3's hook MUST short-circuit gracefully when no `model_aliases_extra` block exists (vacuous success — Sprint 2A's validator already returns `(True, [], False)` for this case).
- **Production `.claude/defaults/model-config.yaml`** loads through the hook without errors. Add a smoke test step against the real production yaml in the dedicated CI workflow (cycle-099 §`Production-yaml smoke-test` lesson from sprint-1E.a).

Beads still UNHEALTHY/MIGRATION_NEEDED ([#661](https://github.com/0xHoneyJar/loa/issues/661)). `--no-verify` policy active. Each commit MUST carry `[NO-VERIFY-RATIONALE: ...]` tag.

Slice if context-tight:
  - 2B.a: T2.3 only (Python hook, no writer side effects yet — validate-and-print mode)
  - 2B.b: T2.4 writer (atomic + flock + SHA256 + shlex.quote)
  - 2B.c: T2.5 model-adapter.sh sourcing integration

Conversation-budget discipline (cycle-099 lesson): T2.4's atomic-write + flock + shell-escape surface is the trickiest in Sprint 2; if subagent dual-review catches a CRITICAL flock or atomic-rename bug pre-merge, allocate buffer for 3-iter BB convergence. If iter-1 plateau-signals (anthropic-only because OpenAI/Google APIs intermittently 404/error, but iter-2 confirms), call plateau early.

After Sprint-2B ships:
  - Sprint-2C candidate: T2.6 (FR-3.9 6-stage resolver, Python canonical + bash twin) — extends Sprint 1D's golden corpus runners with full `resolution_path` arrays
  - Sprint-2D: T2.7 (tier_groups defaults) + T2.8 (prefer_pro_models overlay)
  - Sprint-2E: T2.9 (legacy compat) + T2.10 (permissions baseline)
  - Sprint-2F: T2.11 (endpoint allowlist integration with cycle-099 sprint-1E validator)
  - Sprint-2G: T2.12 (model-invoke --validate-bindings) + T2.13 (LOA_DEBUG_MODEL_RESOLUTION)
  - Sprint-2H: T2.14 (operator example block) + T2.16 (network-fs runbook)

---

## Open backlog at session-end (2026-05-06)

### Sprint 1 remaining

- **T1.10 unfinished bats**: bridgebuilder-dist-drift.bats + perf-bench.bats. Sprint-1A landed gen-bb-registry-codegen.bats; sprint-1B landed legacy-adapter-still-works.bats. Two more deliverables per SDD §7.2 still owed. **Defer to sprint-1D OR sprint-1E.c bundle** (small, can ride alongside).

### Sprint 1 deferred to follow-ups

- **macos arm64 hardcoding** (BB iter-1 F3 + iter-2 F5 from sprint-1C): pin to `macos-14` instead of `macos-latest` for deterministic arch.
- **yq upstream checksums URL** (BB iter-2 F2 from sprint-1C): cross-reference https://github.com/mikefarah/yq/releases/download/v4.52.4/checksums in the workflow comment for audit ergonomics.
- **Composite action for yq install** (BB iter-2 F8 from sprint-1C): three workflows currently duplicate the install step. Repository-local action could DRY this up.
- **`local alias=` shadows builtin** (sprint-1B review H1): cosmetic; rename to `_alias`.
- **Workflow_dispatch trigger for drift gate** (sprint-1C review process): catches "drift introduced before the gate landed" race.
- **Sprint-1E.a leftovers** (BB iter-2, all LOW or recycled, deferred):
  - F4: T8.2/T8.3 caller-contract docs discoverability — log-redactor module docstring already documents the URL-only scope; consider README/operator-doc snippet
  - F5: M13.3 umask defense-in-depth — Python `os.O_CREAT, mode=0o600` ALREADY enforces; the test pins it via the bash-side `stat`. Could add a parallel test that explicitly inspects Python's `os.stat()` result.
  - F6: pip-install-without-hashes — matches existing repo convention (jcs-conformance.yml, bedrock-contract-smoke.yml); deferred as repo-wide hardening cycle
  - F7: T1.2 mixed `_redact_both` + `_assert_parity` — uniformly migrate remaining sites to `_assert_redacts_to`
  - F8: smoke-test partial-write defense — add a `[ -s /tmp/migrated.yaml ]` size check after the migrate call
  - F12: M11.1 brittleness — replace `grep -E '^[a-z_]+:'` with a parser-based first-key check via ruamel.yaml

### Sprint 2+ scope (downstream of Sprint 1 completion)

- Sprint 2 — Config extension (`model_aliases_extra`) + per-skill granularity (`skill_models`) + runtime overlay (`.run/merged-model-aliases.sh`)
- Sprint 3 — Personas + docs migration + DD-1 Option B model-permissions codegen + bridgebuilder dist regen
- Sprint 4 (gated at T4.4) — Legacy adapter sunset

### Beads

UNHEALTHY/MIGRATION_NEEDED ([#661](https://github.com/0xHoneyJar/loa/issues/661)) unchanged across all 10 PRs (#721/#722/#723/#724/#728/#729/#730/#731/#732/#733). `--no-verify` policy active per cycle-099 sprint plan §`--no-verify` Safety Policy. Each PR commit message carries the `[NO-VERIFY-RATIONALE: ...]` audit-trail tag.

---

## Patterns established this session (worth remembering)

1. **Subagent dual-review (general-purpose + paranoid cypherpunk) in parallel** caught real bugs across all four sub-sprints. Paranoid cypherpunk specifically caught: `__proto__` prototype-shadowing (1A), `LOA_MODEL_RESOLVER_GENERATED_MAPS_OVERRIDE` ungated arbitrary-bash-source (1B), unverified macOS yq SHA256 (1C), `additionalProperties` schema gap + symlink-clobber on output write (1E.a). General-purpose specifically caught: silent regression of `claude-sonnet-4-5-20250929` (1A), brittle source-line regex pin (1B), advisory-only version-comparison-script (1C), input-dict mutation in "pure" function + tier_groups absent/partial-fill gaps + tautological assertion (1E.a).

2. **Bridgebuilder kaironic 2-iter convergence** held empirically. Each PR plateaued in 2 iterations including 1E.a.

3. **The vacuous-green-via-fixture-syntax-error pattern** (BB iter-1 F1 on PR #723): a security-test fixture with a bash syntax error means the negative assertion passes for the wrong reason (file fails to parse before the attack code runs). **Fix template**: add a positive-control sentinel that proves the payload WOULD fire if the gate were absent.

4. **The drift-gate-cannot-catch-its-own-introducing-PR race** (sprint-1A → 1B → 1C surfacing): SDD R-5 in the wild. Sprint-1C remediated retroactively via gen-adapter-maps regen. Sprint-1D follow-up should add `workflow_dispatch` post-merge gate.

5. **Inline implementation pattern with subagent quality gates** continues to outperform `/run` autopilot for sliced sub-sprints. Sprint 1A/1B/1C/1E.a all used the inline-then-subagent-review-then-BB-kaironic-then-admin-squash flow.

6. **Conversation-budget discipline**: future sessions should slice sprints further before starting. 1E.a was sliced cleanly from 1E.b at session start, so the remaining endpoint validator can ship as a small follow-up rather than getting bundled in mid-session.

7. **Production-yaml smoke-test in CI catches schema-vs-reality drift** (sprint-1E.a): the strict v2 schema initially rejected legitimate cycle-095 production fields (compliance_profile null, api_format dict for Bedrock per-capability mapping). Without the dedicated CI step that runs the migrator against `.claude/defaults/model-config.yaml`, this would have surfaced only when an operator hit it in the field. **Fix template**: every schema-tightening PR must include a smoke-test step that runs against the most-permissive real-world fixture available.

8. **Heredoc shell-injection-into-Python-source surface** (sprint-1E.a BB iter-1 F2): bats tests using `"$PYTHON" - <<EOF` (unquoted) interpolate every `$VAR` into the embedded Python source. If any path contains a quote, `$`, or `\`, the embedded code can break or be injected. **Fix template**: helper function `_python_assert` that exports paths via env vars + uses quoted heredoc `<<'EOF'`, with the embedded Python reading via `os.environ["PATH_VAR"]`. See `tests/integration/migrate-model-config.bats` for the canonical pattern.

9. **`set -e` × `grep -2-on-missing-dir` interaction** (sprint-1E.b CI fix): GitHub Actions default shell is `bash -e {0}`; `grep -rEln '...' missing-dir/` exits 2 (path-not-found), and `set -e` aborts the workflow step. Local interactive shells without `set -e` swallow the same condition, so the bug surfaces only in CI. **Fix template**: pre-filter scope arrays via `for d in ...; do [[ -d "$d" ]] && scope+=("$d"); done` before expanding into `grep` argv. Robust to repo-level path changes; future scope additions don't require workflow edits to remove non-existent paths.

10. **Stream-contract testing at the CLI surface** (sprint-1E.b gp M1 + cypherpunk LOW 3): bats helpers that capture `2>&1` (merged stdout + stderr) cannot detect regressions in stream-placement contracts. Per SDD §6.2 errors emit on stderr; my JSON-mode rejection-tests would have passed even if the validator emitted JSON-rejection on stdout. **Fix template**: separate test cases that capture only one stream at a time and assert the OTHER is empty: `out=$(... 2>"$WORK_DIR/err"); err=$(cat "$WORK_DIR/err")`. Add C6/C7/C8-style tests at every CLI's stream boundary.

11. **Persistent false-alarm = kaironic plateau** (sprint-1E.b BB iter-1+iter-2 F1): the same finding flagged by BB across two iterations, manually verified to be incorrect, is a strong plateau signal. Don't burn a third iteration trying to "fix" something the regex already handles. Document the false alarm in the commit message + admin-squash.

12. **TS-vs-Python parser-confusion is the central risk of multi-runtime validators** (sprint-1E.c.1 cypherpunk CRITICAL × 2): the URL constructor in JS silently percent-decodes `%2E` to `.`, normalizes Unicode dot equivalents (U+FF0E, U+3002, U+FF61), and folds backslashes — all behaviors that diverge from Python's `urlsplit`. **Fix template**: a unified pre-parse gate (`_validate_authority`) that rejects parser-confusion vectors in BOTH runtimes, applied to the RAW URL string before either parser sees it. Sprint-1E.c.1 ships `_AUTHORITY_FORBIDDEN_CHARS` containing `%`, `\`, three Unicode dots, soft-hyphen, and zero-width / bidi controls. Plus `_has_obfuscated_ipv4_octet` for leading-zero / 0x-prefix octets. Both reviewers (cypherpunk CRITICAL × 2 + general-purpose HIGH × 4) caught this pre-merge — without dual-review, sprint-1E.c.1 would have shipped a working SSRF allowlist bypass.

13. **Codegen surrogate trap for non-BMP codepoints** (sprint-1E.c.1 cypherpunk MEDIUM): naive Jinja2 emission `\u{{ '%04x' | format(cp) }}` works for BMP (≤ U+FFFF) but silently corrupts for non-BMP (e.g., U+E0001 → emits `11`, which JS parses as U+E000 followed by literal "11"). **Fix template**: a `_ts_escape_cp` filter that uses `\u{XXXXX}` brace form for codepoints > 0xFFFF. Latent bug today (Python's `_PATH_CONTROL_CHARS` are all in BMP), but a future addition would silently break the TS port without the filter.

14. **Drift-gate hash cross-check beats text-diff alone** (sprint-1E.c.1 gp MEDIUM): a codegen `--check` mode that only does `fresh_text != committed_text` byte-diff catches the common "forgot to regenerate" case but misses a tampered-canonical-with-matching-regen scenario. **Fix template**: extract the embedded `Source content hash:` header from the committed file and compare against a fresh hash of the canonical Python source — fail with `[BB-CODEGEN-HASH-DRIFT]` if they don't match. Forces operator review of any canonical edit.

15. **Spec-vs-impl semantic inversion is a HIGH-severity bug class** (sprint-1E.c.2 gp+cypherpunk HIGH 1): the SDD specified `cdn_cidr_exemptions` with RELAXING semantics (resolved IP in CIDR → SKIP blocked-range check, for CDN-via-Cloudflare reconciliation); my initial implementation introduced `cidr_ranges` with INVERTED REQUIRE-MATCH semantics. Operators reading the SDD would configure the spec'd field name; my code silently ignored it. **Fix template**: when adding security-related allowlist/blocklist fields, ALWAYS verify the field name AND the predicate (relaxing-vs-tightening) match the SDD verbatim. Adding undocumented schema extensions is a documentation-vs-code drift surface that operator misconfig will exercise.

16. **Happy Eyeballs records[0] gambit on dual-stack hosts** (sprint-1E.c.2 cypherpunk MEDIUM): `getaddrinfo` returns mixed AF_INET/AF_INET6 records in resolver-determined order. Naive `records[0]` extraction picks the first; OS-level connect (RFC 8305 Happy Eyeballs) prefers IPv6 when available. An attacker DNS that returns [public_v4, blocked_v6] could lock the public IPv4 (passes blocked-range check) while the actual TCP connect lands on the blocked v6. **Fix template**: validate ALL records in the set against blocked-range, not just records[0]. The CDN-CIDR exemption applies per-record. `lock_resolved_ip` iterates the full record list before returning.

17. **Forge-defense at dataclass `__post_init__`** (sprint-1E.c.2 cypherpunk LOW): `frozen=True` prevents MUTATION but not CONSTRUCTION. A future caller deserializing a `LockedIP` from a JSON state file (or any other persistence path) can construct one with garbage IP fields, bypassing the `lock_resolved_ip` blocked-range check entirely. **Fix template**: validate fields in `__post_init__` (e.g., `ipaddress.ip_address(self.ip)` parses cleanly) so deserialization paths fail-fast at construction. The dataclass becomes a true validated invariant carrier instead of a passive struct.

18. **`curl --config` URL smuggling vector** (sprint-1E.c.3.a cypherpunk CRITICAL): a curl wrapper that validates URL but lets caller pass `--config` is broken — curl config files honor `url = "..."` and `next` directives, allowing a tampered tempfile to smuggle additional URLs past the allowlist. `lib-security.sh::write_curl_auth_config` blocks the most obvious vector (newline injection in API key) at write time, but defense-in-depth says the WRAPPER must also: (a) reject caller-passed `--config` / `-K` / `--next` / `-:` outright, (b) require auth files via a NEW `--config-auth` flag that pre-parses the file and rejects anything other than `header = "..."` lines + comments + blanks. **Fix template**: a wrapper-flag-pair that separates "validated input file" from "raw curl args" so curl never sees the bag-of-flags shape that allows config-file smuggling. Also reject CR (0x0D) bytes — line-based grep would otherwise miss CR-only line endings that hide smuggled directives.

19. **Positional URL strict-reject as design boundary** (sprint-1E.c.3.a BB iter-1 MEDIUM, accepted at iter-2 F8 SPECULATION): a wrapper that takes `--url <URL>` + `[curl_args...]` MUST also reject naked `https?://` strings in caller args. curl treats positional args as additional URLs to fetch alongside `--url`'s target — `endpoint_validator__guarded_curl --url valid https://evil` would fetch BOTH. The trade-off: strict-reject catches naked positionals but ALSO rejects legitimate flag-VALUES like `--referer https://x` and `--proxy https://x`. For Loa's caller set this is correct (none use those flags); document the bound as failing tests rather than a comment so future callers see the design constraint explicitly.

20. **Allowlist tree-restriction matters even with caller-controlled defaults** (sprint-1E.c.3.a cypherpunk HIGH): caller scripts default the allowlist path via `${LOA_CALLER_ALLOWLIST:-$lib_dir/allowlists/foo.json}` — but env var override means an attacker who controls env can substitute. The realistic threat is operator-self-pwning, but defense-in-depth via `realpath -e` resolution + tree-restriction (path MUST be under `.claude/scripts/lib/allowlists/`) closes the substitution surface entirely. Test-mode escape via `LOA_ENDPOINT_VALIDATOR_TEST_MODE=1` + `LOA_ENDPOINT_VALIDATOR_TEST_ALLOWLIST_DIR` (gated AND requires both — partial test mode does NOT trigger escape, mirroring cycle-098 L3 pattern).

21. **Captured stderr for SSRF audit visibility** (sprint-1E.c.3.a gp LOW): a curl-wrapping script that does `2>/dev/null` on the wrapper call swallows the validator's structured rejection JSON. Operators tampering with provider URL would see only "transient HTTP_STATUS=0" with no SSRF breadcrumb. **Fix template**: capture wrapper stderr to a tempfile, and on `curl_rc==78` emit ONE structured `log_warn` line (`[ENDPOINT-VALIDATOR-REJECT]` + url + provider + first 400 bytes of validator stderr). Same surface as the existing audit-log pattern in `model-health-probe.sh`.
