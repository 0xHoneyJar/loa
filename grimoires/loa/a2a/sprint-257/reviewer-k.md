# Sprint 257 — security audit fix round a257-1 (implementer K)

**Implementer:** Claude Opus 5.5 subagent, model id `global.anthropic.claude-opus-5-5`
**Date:** 2026-10-14
**Worktree:** `/home/merlin/Documents/thj/code/loa-wt-s3e` (branch `wt/cycle-129-s3e` at `4184c052`, uncommitted, KF-014)
**Input:** `grimoires/loa/a2a/sprint-257/auditor-sprint-feedback.md` (main checkout), verdict CHANGES_REQUIRED (2 MEDIUM, 3 LOW)
**Patch:** `~/.cache/loa/cycle-129/patches/s3-k.patch`

## Executive Summary

All seven deliverables are done and verified. cheval, the process that sends the prompt, now applies the local-hop rule to
its own chain under `hounfour.locality: local_voices`: hosted hops are planned around by name, an all-hosted chain is
refused before any dispatch with a MODELINV `failure_class: locality_refused` row, and the loader refuses a local model
whose `fallback_chain` reaches a hosted hop. Bridgebuilder walks a local voice's `fallback_chain` through the trusted
aliases, and on a pull request refuses any head whose hounfour providers, aliases, locality or secret allowlist drift from
the trusted source (exit 5). `localhost` is resolved and checked at request time. The audit envelope carries
`metadata.locality.degraded_security_review`, and the budget estimate warns on a zero price that is not `open_weight`.
One rule implementation (`endpoint_policy.hop_is_local`) now serves cheval's planner, the loader check and MODELINV
`hop_locality`. DISS-001 is accepted by design: no change.

## Security Audit Feedback Addressed

### MEDIUM-A1 (a) — cheval plans around locality — FIXED
- `.claude/adapters/cheval.py:423` `_entry_is_local` (a `kind: cli` hop is hosted; otherwise `endpoint_policy.hop_is_local`).
- `.claude/adapters/cheval.py:432` `_plan_around_locality`: under `local_voices` each hop failing the rule is dropped with one
  stderr line `locality: local_voices refuses hosted hop <provider>:<model> (fallback of <alias>)` or `(primary)`, and
  recorded in MODELINV `models_not_planned` with `reason: locality_refused`; an empty plan raises `LocalityRefusedError`
  (`.claude/adapters/loa_cheval/types.py:543`, a `ConfigError`, `failure_class = "locality_refused"`, bare message on
  `.detail` starting `locality: local_voices refuses every hop of <alias>`); under `hosted`/unset the chain object is returned unchanged.
- `.claude/adapters/cheval.py:1855` applied right after `_plan_around_agy`; the refusal prints the JSON error envelope
  (`failure_class: locality_refused`), emits a MODELINV row (every hop in `models_failed` with `error_class: INVALID_CONFIG`,
  `failure_class: locality_refused`, plus `destination`/`locality_mode`/`hop_locality`) and exits `INVALID_CONFIG` (2).
- Schema: `model-invoke-complete.payload.schema.json` `failure_class` enum and `models_not_planned.reason` enum gain
  `locality_refused` (lines 66–67, 761, 782); the schema pin in `test_agy_chain_walk_opt_in.py:215` bumped deliberately.
- `.claude/adapters/loa_cheval/audit/modelinv.py:473` `hop_locality_of` now delegates to `hop_is_local`.
- Pinned by `.claude/adapters/tests/test_locality_fallback_plan.py` (13 cases, real loader, stub server on 127.0.0.1):
  `[local-a, hosted]` plans and dispatches only `local-a` and names the drop; a hosted primary in front of a local fallback
  is dropped as `(primary)` and the local hop answers; `[hosted]` alone refuses with exit 2, nothing sent, the MODELINV row
  validated against the payload schema; the typed error raised directly; `hosted` and unset leave the chain unchanged; a
  `kind: cli` hop is hosted whatever its label.

### MEDIUM-A1 (b) — loader refuses a local model's hosted fallback under local_voices — FIXED
- `.claude/adapters/loa_cheval/config/endpoint_policy.py:200` `hop_is_local`, `:223` `resolve_hop_spec` (pin or alias via
  `hounfour.aliases`, depth 8, cycle-safe), `:245` `validate_local_fallbacks` (only when the merged `locality` is
  `local_voices`; message `[CONFIG-INVALID] providers.<p>.models.<m>: under hounfour.locality local_voices the
  fallback_chain reaches a hosted hop <entry>`; unresolvable is refused as hosted).
- Called from `.claude/adapters/loa_cheval/config/loader.py:707`, after `validate_providers`.
- Pinned by `test_locality_fallback_plan.py` (refused: pin, alias, unresolvable; admitted: local pin and local alias under
  `local_voices`, hosted fallback under `hosted`) and `tests/unit/adversarial-review-locality.bats` LOC-10, which now loads
  the fixture under `hosted` (all four models), asserts the named refusal of `qwen-leaky` under `local_voices`, then loads the
  fixture without `qwen-leaky` under `local_voices`. LOC-7/LOC-9 and FLL-1…9 unchanged and green.

### MEDIUM-A1 (c) — Bridgebuilder walks the fallback_chain — FIXED
- `.claude/skills/bridgebuilder-review/resources/core/types.ts`: `ProviderDecl.modelFallbacks`, `TrustedConfig.aliases`.
- `config.ts:500` `parseProviderDecls` carries per-model `fallback_chain`; `config.ts:938` `resolveFallbackSpec`;
  `config.ts:956` `localVoiceDecisionAt` (depth ≤ `LOCAL_FALLBACK_MAX_DEPTH` = 8, cycle-safe) reports
  `locality: local_voices refuses hosted hop <m> (<p>): dispatch_group local but its fallback_chain reaches hosted hop <entry>`.
- Pinned by `__tests__/trusted-config.test.ts` describe "a local voice's fallback_chain under local_voices" (4 cases: reader
  carries chain and aliases; local pin/alias/cycle stays local; hosted pin, hosted alias, alias cycle, deeper hosted hop each
  refused by name; depth limit). `dist/` rebuilt.

### MEDIUM-A2 — trusted config drift refused on a pull request — FIXED
- `config.ts:715` in pull-request mode `headDrift = computeHeadDrift(head, trusted)` (`config.ts:812`, pure): per-entry
  keys `hounfour.providers.<name>` (deep-equal, every field), `hounfour.aliases.<alias>`, `hounfour.locality` (absent =
  `hosted`), `hounfour.secret_env_allowlist` and a root `secret_env_allowlist` (absent = `[]`); an absent head reads as all
  defaults; an unparsable head is drift on `.loa.config.yaml` (fail closed). The yq view gained `aliases`, `allowlist`,
  `rootAllowlist`. Local mode: `headDrift: []`.
- `config.ts:839` `headDriftRefusal` (pure) and `EXIT_TRUSTED_CONFIG_DRIFT = 5` (`config.ts:833`); `main.ts:472` prints
  `[bridgebuilder] trusted config drift refused: <keys> differ between the PR head and <source>; merge the base branch into
  the head or set BRIDGEBUILDER_TRUSTED_CONFIG` and exits 5 before any voice is planned. `entry.sh:124` documents 0/3/4/5.
- Docs: `.loa.config.yaml.example` `bridgebuilder:` comment (line 2517) and `multi-model-reference.md` FR-7 paragraph state
  that cheval reads the checkout's configuration and that the drift refusal exists for that reason.
- Pinned by `trusted-config.test.ts` describe "trusted config drift on a pull request" (9 cases: identical head; endpoint
  re-point; auth template re-bind; alias re-point; allowlist widening, hounfour and root; locality change, explicit `hosted`
  equals absent; head-only provider, removed provider, absent head, unparsable head; the exact refusal text for base-ref and
  repository-settings sources and exit 5 ∉ {0,3,4}; local mode never refuses; `computeHeadDrift` purity).

### LOW-A1 — localhost resolved at request time — FIXED
- `.claude/adapters/loa_cheval/providers/base.py:153` / `:163` `_check_localhost_resolves_to_loopback`: `socket.getaddrinfo`
  ("localhost"); any non-loopback address (IPv4-mapped loopback accepted) refuses with `request host localhost for provider
  '<p>' resolves to <addr>, not a loopback address (dispatch_group local, D-7.2)`; a resolver exception or empty answer
  refuses with `… could not be resolved`. IP literals never reach the resolver.
- Example 4's threat-model comment (`.loa.config.yaml.example:1227-1232`) now says IP literals are never resolved and
  `localhost` is resolved and checked at request time.
- Pinned by `test_local_dispatch_group_rule.py` (9 new cases: loopback-only accepted ×2; a public address among the results
  refused by name ×2; RFC1918 answer refused; raising and empty resolver refused; an IP literal never resolved).

### LOW-A2 — degraded_security_review machine-readable — FIXED
- `.claude/scripts/adversarial-review.sh:4854-4863`: `metadata.locality.degraded_security_review` is `true` on an audit whose
  companion is not `independent_voice`, with the sentence in `note`; `false` otherwise (a review, or an audit with an
  independent companion), and then no `note`. `verdict_quality`, `verdict-derive.sh` and the artefact gate are untouched.
- `.claude/skills/auditing-security/SKILL.md:184` names the field; budget kept (16,375 ≤ 16,384 B) by dropping
  " in `.loa.config.yaml`" from line 181.
- Pinned by `adversarial-review-locality.bats` LOC-4 (`true`) and LOC-1 (`false`, no `note`).

### LOW-A3 — zero price not marked open_weight warns — FIXED
- `.claude/scripts/adversarial-review.sh:3890-3897`: on the zero-priced branch the pricing CLI's `--json` row is read for
  `open_weight`; anything other than `true` logs `budget: zero price on <alias> (<role>), not marked open_weight — check the
  pricing overlay`. The estimate and metering are unchanged.
- Pinned by `adversarial-review-budget.bats` BUD-3 (non-open-weight zero → warning line) and BUD-7 (new; `open_weight: true`
  zero → no warning).

### CHANGELOG
- `## [Unreleased]` `### Fixed`: one "Security audit round a257-1" entry naming the five items.
- `### Migration (cycle-129)`: a row for `local_voices` operators whose local model falls back to a hosted one, and a row for
  pull requests whose head changes the hounfour block (drift refusal, exit 5, how to clear it).

## Testing Summary

| Command | Result |
|---------|--------|
| `cd .claude/adapters && python3 -m pytest -q` | 3277 passed, 2 failed (baseline `test_claude_headless_adapter.py` ×2), 6 skipped |
| `bash -c 'LOA_HARNESS_CHECK=0 LOA_AUDIT_REPLAY=1 bats tests/unit/adversarial-review-locality.bats tests/unit/flatline-locality.bats tests/unit/adversarial-review-advisory.bats tests/unit/adversarial-review-budget.bats tests/unit/bb-exit-degraded-callers.bats tests/unit/model-health-probe*.bats'` | 137/137 |
| `cd .claude/skills/bridgebuilder-review && npm run build && npm test` | build ok; 882 tests, 881 pass, 1 fail (baseline `persona.test.ts`, KF-036); `trusted-config.test.ts` 35/35 |
| `tools/check-bb-dist-fresh.sh` | OK (fresh) |
| `python3 -m loa_cheval.codegen.emit_endpoint_validator_ts --check` | rc 0 |
| `tools/check-prompt-budget.sh` | rc 0 (auditing-security 16,375 B) |
| `bash tools/check-no-raw-sha256sum.sh`, `bash tools/check-no-swallowed-jq.sh` | rc 0, rc 0 |
| fence corpus: `bats tests/unit/block-destructive-bash.bats tests/unit/floor-snapshot.bats` | 297/297 |
| `python3 -m py_compile` on the 9 touched .py; `bash -n` on `adversarial-review.sh`, `entry.sh` | ok |

## Known Limitations

- The drift refusal compares only `.loa.config.yaml`. A pull request that edits the System Zone catalog
  (`.claude/defaults/model-config.yaml`) or relies on `LOA_*` environment overrides also changes what cheval reads; those
  are outside this fix (the System Zone is review-guarded). Other hounfour keys (`headless`, Bedrock posture) are not compared.
- A pull request that changes the hounfour block on purpose is refused until the operator sets
  `BRIDGEBUILDER_TRUSTED_CONFIG`; merging the base branch does not help in that case (stated in the Migration row).
- The `localhost` check resolves before the request and urllib resolves again when it connects; a resolver answer that
  changes between the two calls is not covered.
- Cross-provider fallbacks were already refused by the chain resolver's within-company invariant, so the in-call leak (a)
  closes is the same-provider unlabelled or `kind: cli` hop; the planner applies to any chain it is handed regardless.
- `.claude/checksums.json` and `grimoires/loa/REPO-MAP.md` were not regenerated (forbidden to this round); the lead
  regenerates them with the System Zone edits (`cheval.py`, `endpoint_policy.py`, `loader.py`, `modelinv.py`, `types.py`,
  `base.py`, the payload schema, `adversarial-review.sh`, the BB sources and `dist/`, `auditing-security/SKILL.md`,
  `multi-model-reference.md`).
- The metering-side guard for LOW-A3 (a zero price on a non-open-weight hosted entry counted as unpriced) is the lead's
  follow-up bead; nothing in metering changed.

## Assumptions

- [ASSUMPTION fact] cheval's effective secret allowlist is `hounfour.secret_env_allowlist` (`load_project_config` returns only the `hounfour:` section); the brief said "root key", so both `hounfour.secret_env_allowlist` and a root `secret_env_allowlist` are compared.
- [ASSUMPTION decision] The drift refusal also applies on the single-model path: it runs right after the trusted config is loaded, before either path plans a voice, because the single-model voice also dispatches through cheval from the checkout.
- [ASSUMPTION decision] The `localhost` resolution check applies to every `TransportPolicy` hop (local label or an `allow_insecure_endpoint: localhost` opt-in), not only `local=True`: plain http to localhost must stay on this machine either way.
- [ASSUMPTION decision] `degraded_security_review` is `true` exactly when the audit's companion is not `independent_voice`, and the `note` sentence is attached only then; previously the sentence was attached to every `local_voices` audit.
- [ASSUMPTION decision] Planned-around hosted hops are recorded in MODELINV `models_not_planned` with a new reason `locality_refused` (schema enum extended, pin test bumped), mirroring the agy precedent; the all-hosted refusal records every hop in `models_failed`.
- [ASSUMPTION decision] `hop_is_local` honours a provider-block `dispatch_group: local` when the model entry is silent (the `hop-locality.py` rule); MODELINV `hop_locality` now uses it too, so it can say `local` where it said `hosted` for a block-labelled model.
- [ASSUMPTION decision] An unparsable PR-head config is drift (`.loa.config.yaml (unreadable in the PR head)`), and an absent one reads as all defaults: fail closed, since cheval's YAML reader may accept what yq refused.
- [ASSUMPTION decision] `LocalityRefusedError.detail` carries the bare message, because `ChevalError.__str__` prefixes `[cheval] INVALID_CONFIG:`; the JSON envelope and MODELINV message start with `locality: local_voices refuses every hop of <alias>`.
