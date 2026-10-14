APPROVED - LET'S FUCKING GO

# Sprint 257 security audit — round 2 (cycle-129 Sprint 3) — APPROVED

**Auditor:** Paranoid Cypherpunk Auditor (Claude Fable 5.1, `global.anthropic.claude-fable-5-1`)
**Date:** 2026-10-14
**Implementation:** `07110d70` (audit fix round a257-1 by implementer K on `4184c052`; base `a7682ba4`); review APPROVED (`engineer-feedback.md`, round 2); round 1 audit kept as `auditor-sprint-feedback-r1.md`
**Dissent:** `adversarial-audit.json` (round 1, two voices, consensus, 0 rejected payloads) — the sprint's three dissent runs are spent (review r1, review r2, audit r1); this round is the auditor's direct verification of the fix range `4184c052..07110d70` against the tree and the suites (DEC-0343).

## Round 1 items, verified against the tree

- **MEDIUM-A1 closed.** One rule implementation, `endpoint_policy.hop_is_local` (model-entry or provider-block `dispatch_group: local`, not a CLI provider or `kind: cli` model, endpoint host passes `local_endpoint_host`), read in full. (a) `cheval.py` `_plan_around_locality` runs right after `_plan_around_agy`: under `local_voices` every non-local chain entry is dropped before the walk with one stderr line and a `models_not_planned` row (`reason: locality_refused`); an all-hosted chain raises `LocalityRefusedError` (`types.py`, a `ConfigError`, `failure_class: locality_refused`), prints the JSON error envelope, emits a MODELINV row with every hop in `models_failed` and the hop telemetry, and exits `INVALID_CONFIG` — the refusal happens before `_get_adapter_for_entry`, so nothing is sent; under `hosted` the chain object is returned unchanged. (b) `validate_local_fallbacks` runs from `loader.py` after `validate_providers`, only when the merged root `locality` is `local_voices`; `resolve_hop_spec` follows pins and aliases (depth 8, cycle-safe) and an unresolvable entry is refused as hosted. (c) Bridgebuilder `localVoiceDecisionAt` walks `modelFallbacks` through the trusted `aliases` (depth ≤ 8, a cycle back to a voice on the walk is not new) and names the hosted entry; `parseProviderDecls` carries `fallback_chain` as a list (a scalar is a one-entry chain, a non-string entry is unresolvable). The payload schema's two enums gain `locality_refused` and the pin test is bumped deliberately. Tests read: `test_locality_fallback_plan.py` (13; the stub server proves only `local-a` is dispatched and the all-hosted case sends nothing), LOC-10 (hosted loads all four, `local_voices` refuses `qwen-leaky` by name, loads without it), `trusted-config.test.ts` (4).
- **MEDIUM-A2 closed.** `computeHeadDrift` (pure, key-order-independent deep equality) compares `hounfour.providers.<name>`, `hounfour.aliases.<alias>`, `hounfour.locality` (absent = `hosted`), `hounfour.secret_env_allowlist` and a root `secret_env_allowlist` (absent = `[]`); an absent head reads as all defaults, an unparsable head is drift on `.loa.config.yaml` (fail closed); `headDriftRefusal` is applied in `main.ts` after `loadTrustedConfig` and before either path plans a voice; exit 5 is distinct from 0, 3 and 4 and `entry.sh` documents all four; the yq view reads `aliases` and both allowlists from both texts. Drift segments are bounded and JSON-quoted when not plain names, so head text cannot forge a refusal line. The example comment and the reference say why. Tests read: 9 drift cases incl. the two trusted sources and local mode never refusing. This branch's own config differs from `main` only in `guardrails`, so the cycle PR's Bridgebuilder pass is not refused.
- **LOW-A1 closed.** `_check_localhost_resolves_to_loopback`: `socket.getaddrinfo("localhost", None)` before the request; every address (zone suffix stripped, IPv4-mapped loopback accepted) must be loopback; an exception or an empty answer refuses; applies to every policy hop (a local label or an `allow_insecure_endpoint: localhost` opt-in) — tighter than asked, correct for plain http. IP literals never reach the resolver. 9 cases with a monkeypatched resolver.
- **LOW-A2 closed.** `metadata.locality.degraded_security_review` is `true` on an audit whose companion is not `independent_voice` (the sentence then in `note`), `false` otherwise; the auditing skill names the field (16,375 B); `verdict_quality`, `verdict-derive.sh` and the artefact gate untouched (floor). LOC-1/LOC-4.
- **LOW-A3 closed as a hardening.** The budget gate WARNs by name on a zero price not marked `open_weight` (BUD-3, BUD-7); metering unchanged; the metering-side guard is bead **bd-yzzb9** (carried as the one open LOW).
- **DISS-001 accepted by design** (DEC-0342).

## Suites on the integrated tree (`07110d70`)

cheval pytest 3277 passed / 6 skipped / 2 failed (the two `test_claude_headless_adapter.py` baseline failures, identical on `a7682ba4`); Sprint 3 bats plus the four probe suites 137/137; Bridgebuilder `npm test` 881/882 (`persona.test.ts`, KF-036) with `dist/` fresh; TypeScript port `--check` clean; fence corpus 99/99 · 184/184 · residual 0/5 · miss 0/0; guard register in sync (96 guards); prompt budget, knob readers, swallowed-jq, raw-sha256, shell-compat, skill-capabilities (37/37) green; `bash -n` on the two touched shell files.

## Rejected dissent payloads

None: 0 schema-rejected payloads in `adversarial-audit.json` (`rejected_count: 0`, no rejected sidecar); no fourth run.

## Security checklist

Secrets: none in the diff; the drift refusal line carries key names only, bounded and quoted. Transport: the local-hop rule now holds at load, at request time, in the planner, in cheval's chain plan and in Bridgebuilder, with `localhost` resolved; redirects refused, proxy ignored. Trusted configuration: ref names validated, the variable carries text, head-only and head-drift refused by name, fail closed on an unreadable head. Audit trail: MODELINV `locality_refused` rows, `models_not_planned` reasons, `degraded_security_review`. Floor untouched. Process: the fix round was authored in a linked worktree by an Opus 5.5 subagent and applied by the lead with `git apply --3way --index`; two spacing nits aside, the lead changed no code this sprint outside the three LOW hardenings of review round 2.

## Verdict

APPROVED - LET'S FUCKING GO. Sprint 257 is complete: AC-3.1 … AC-3.8 met (AC-3.6 by enforcement at every layer that sends a prompt), the floor byte-for-byte untouched, every finding of three two-voice dissent runs either fixed with a pinning test, refuted with evidence, or accepted by design with a recorded decision.

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":1},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-257","ts":"2026-10-14T10:32:02Z"} -->
