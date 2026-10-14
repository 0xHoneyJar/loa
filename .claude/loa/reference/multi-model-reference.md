# Multi-Model Activation Reference (cheval substrate)

Full migration state, rollback model, and verification history for the cheval Python substrate. Moved out of `CLAUDE.loa.md`; the per-turn rules live there in compressed form.

## Multi-Model Activation (cycle-109 sprint-3)

The cheval Python substrate is the **unconditional** dispatch path for all
multi-model consumers (BB, Flatline orchestrator, Red-team pipeline,
adversarial-review, bridgebuilder-review, flatline-readiness,
red-team-model-adapter, post-pr-triage). The pre-cycle-109
`hounfour.flatline_routing` runtime flag is being phased out across the
T3.6→T3.7→T3.8 sequence.

| Status (cycle-109 sprint-3 state) | BB | Flatline | Red-team |
|---|---|---:|---:|
| **Post-T3.6 (commit C — current)** | cheval (unchanged) | cheval (unconditional) | cheval (unconditional) |
| **Post-T3.7 (commit D — gated by C109.OP-S3)** | cheval | cheval | cheval (legacy file DELETED) |
| **Post-T3.8 (commit E)** | cheval | cheval | cheval (`hounfour.flatline_routing` flag REMOVED) |

BB has used `ChevalDelegateAdapter` unconditionally since cycle-103 PR #846.
Cycle-109 T3.6 (commit C, this sprint) removed the conditional branches at
the FL orchestrator + model-adapter main() entrypoints; cheval is now
operator-facing unconditional. Mock-mode delegation at model-adapter.sh:519-526
remains until T3.7 + T3.8 land mock-mode migration under operator approval.

All consumers benefit from:
- **Chain-walk**: cheval walks the within-company `fallback_chain` (e.g. gpt-5.5-pro → gpt-5.5 → gpt-5.3-codex → codex-headless) on retryable errors (EmptyContent, RateLimited, ProviderOutage, RetriesExhausted).
- **Voice-drop**: when a voice's chain exhausts, flatline-orchestrator DROPS that voice from consensus instead of substituting another company's model. Audit log: `consensus.voice_dropped`.
- **MODELINV v1.3 envelope**: per-invocation audit record at `.run/model-invoke.jsonl` with `final_model_id`, `transport`, `config_observed`, `models_failed[]`, `models_requested[]`, `capability_evaluation`, `verdict_quality`.
- **Verdict-quality envelope** (cycle-109 Sprint 2): every substrate output carries a `verdict_quality` envelope describing voices succeeded/dropped, chain health, blocker_risk, confidence floor, rationale. `status: clean | APPROVED` is definitionally impossible when verdict quality is degraded (NFR-Rel-1).

### Rollback (cycle-109 model)

**There is no runtime-flag rollback path post-cycle-109.** The
`hounfour.flatline_routing` flag is being removed in T3.8 because the
legacy adapter it gated is being deleted in T3.7 under explicit
operator-approval marker C109.OP-S3. Once Sprint 3 lands on main, the
canonical rollback path is:

  **`git revert` of the cycle-109 sprint-3 merge commits.**

A full rollback runbook lives at
`grimoires/loa/runbooks/cycle-109-rollback.md` — covers per-commit revert,
config restoration, baseline comparison against
`grimoires/loa/cycles/cycle-109-substrate-hardening/baselines/legacy-final-baseline.json`,
and CI re-validation. Operators do NOT need to flip a runtime flag; they
revert.

cycle-124 Sprint 2 (FR-7) — **structured outputs**: `cheval --json-schema FILE`
(object root, ≤ 64 KB) is enforced as Anthropic `output_config.format` on
catalog entries with the `structured_json` capability and forwarded as
`--json-schema` to `claude-headless` (`structured_output` is the answer); other
hops run unenforced. The MODELINV envelope records `schema_enforced` and
`output_schema_sha256` whenever a schema was requested; the dissent
(`adversarial-review.sh`, `dissent-<type>.wire.json`) and Flatline
(review/skeptic/scorer wire schemas) parse an enforced payload strictly and keep
the tolerant normalize path — with the KF-004 repair loop, now flag-less — only
for unenforced voices. Wire schemas live in `.claude/schemas/wire/`; the
provider-safe subset is pinned by `tests/unit/wire-schemas-api-safe.bats`. Ratio
one-liner over the log:
`jq -r 'select(.payload.schema_enforced != null) | [.payload.final_model_id, .payload.schema_enforced] | @tsv' .run/model-invoke.jsonl | sort | uniq -c`.

cycle-126 (FR-1) sizes every request from the catalog entry it resolves to.
The input bound is a **policy**, not a literal (`loa_cheval/routing/ceiling.py`):
I1 `estimate + max_tokens ≤ context_window` (the output budget shrinks to a
4,096 floor before anything is refused; the envelope records
`max_tokens_shrunk`), then I2 — the calibrated value when
`ceiling_calibration.calibrated_at` is set, else the `probed_ceiling`
(180,000) by default. `LOA_CHEVAL_UNCALIBRATED_CEILING=derived` opts into the
catalog-derived bound (`context_window − max_tokens`) for an uncalibrated
entry: above the probed bound the call proceeds with `preflight_decision:
warn` when the count endpoint confirmed the size or the estimate is
`low`-uncertainty, and preempts with the calibration command for a `high`
one (CJK/emoji-dense text, tool payloads). A provider's own size verdict (HTTP
400 prompt-too-long / 413) is **never walked** to the next voice: after one
output-budget shrink it exits `CONTEXT_TOO_LARGE`, records
`.run/ceiling-observed.json` (the bound for that entry until calibration; `/loa`
prints it) and names `tools/ceiling-probe-live.py --model <id> --write-catalog`,
which folds a measured ceiling, `calibrated_at` and `account_limits` into the
catalog. `LOA_CHEVAL_MAX_INPUT_TOKENS=N` lowers any bound;
`LOA_CHEVAL_LEGACY_CEILING=1` restores the pre-cycle literal + preempt (no I1,
no count). Output defaults: `min(cap, max_output_tokens)` for every provider
(64K/16K Anthropic streaming/legacy, 16K elsewhere; 4,096 only without a
declaration); `temperature` is absent from the wire unless set;
`params.beta_headers` (allowlisted dated flags) join into one `anthropic-beta`
header; the health probe asks `/v1/models` first. Envelope fields:
`capability_evaluation.{input_ceiling, estimator, max_tokens_shrunk,
ceiling_policy, ceiling_unverified, calibration_needed}`.

cycle-124 adds one **backstop** (not a rollback): `LOA_CHEVAL_LEGACY_WIRE=1`
makes the Anthropic adapter emit the pre-cycle-124 request body (no adaptive
`thinking`, no `cache_control` blocks, 4096 default `max_tokens`) so a wire
regression can be neutralised without a deploy while the credentialed
`live-floor-check.yml` is still unprobed. It removes what cycle-124 ADDED, no
more: temperature omission is catalog-driven and stays, and on Opus 5 /
Sonnet 5 / Fable the server runs thinking whether or not the block is sent, so
pass `--max-tokens` explicitly on those ids under the switch (the
`max_tokens` stop warning still fires). The code path stays; reverting is
still `git revert` of the cycle-124 unit commits (see the Sprint 1 rollback
proof). Env table: `grimoires/loa/runbooks/cheval-delegate-architecture.md`.

cycle-129 (FR-8) — **local posture**: under `hounfour.locality: local_voices` the dissent, Flatline, Bridgebuilder and health-probe hops are planned only on providers whose model entry says `dispatch_group: local`, each hosted hop refused by name at plan time; the Claude Code session model is exempt and remains the platform, so a local posture keeps model calls local but the session itself still runs against Anthropic. Fewer voices means a DEGRADED verdict quality where the planned voice count is not met — the posture says so in the config comment and in the run output rather than inventing a voice. One fail-closed classifier (`.claude/scripts/lib/hop-locality.py`) serves the shell scripts: an unresolved hop, an unreadable config or a local entry whose fallback chain reaches a hosted entry counts as hosted; an invalid value refuses the run. A declared locality is enforced, not trusted: a hop is local only when its provider is an HTTP provider (not a CLI provider) whose endpoint host is an IP literal in a loopback (`127.0.0.0/8`, `::1`) or RFC1918 (`10/8`, `172.16/12`, `192.168/16`) range, or the literal `localhost` — the host rule of `allow_insecure_endpoint` (an `https` endpoint on such a host needs no opt-in; an `http` one does). The rule is applied at config load (the cheval loader refuses any other `dispatch_group: local` by name), at request time (the local hop's transport policy refuses a request host that fails it), in the planner (`hop-locality.py`: `endpoint_not_local:<host>`) and in Bridgebuilder's locality filter.

cycle-129 (FR-7) — **open-weight and local voices**: a local OpenAI-compatible server is declared as a provider (`type: openai_compat`, `keyless: true`, `allow_insecure_endpoint: "<host>"` where the host is a loopback or RFC1918 IP literal or `localhost`; Example 4 in `.loa.config.yaml.example`). The endpoint rule lives once in `.claude/scripts/lib/endpoint-validator.py` and is used by the cheval loader (`loa_cheval/config/endpoint_policy.py`), the bash wrapper and `model-health-probe.sh --provider <name>`, which probes a configured provider's `/models` with no credential when keyless; at request time a local hop runs with no proxy, no redirects and the declared path prefix. cheval refuses an `http`, loopback or private endpoint without the opt-in at load, for every provider. On the chat-completions path a `structured_json` entry sends `response_format` json_schema and `schema_enforced` is derived from the body sent (one retry without the schema on a server 400 that names it); `reasoning_content`, `reasoning` deltas and a leading `<think>` block go to `thinking` (`thinking_stripped`); an over-window prompt is refused by name. **Advisory voices**: `flatline_protocol.code_review.advisory_voices` and `security_audit.advisory_voices` run beside the counted voices under `advisory_timeout_seconds`; their findings appear only under `advisory_voices[].findings` with `duplicate_of` links and never touch the verdict, the counts or the cost totals — promotion to a counted role needs `hounfour.advisory_promotion`. The budget gate prices each planned voice from the catalog (`loa_cheval.metering.pricing --alias … --json`), whose entries now carry `open_weight`, `price_source` and `price_date`. **Bridgebuilder** reads `hounfour.providers`, `hounfour.locality` and `bridgebuilder.exit_on_degraded` from trusted configuration only (locally the working tree; on a pull request the `BRIDGEBUILDER_TRUSTED_CONFIG` repository variable, else the base branch's config, never the head), prints `completed/planned` voices and exits 3 on a DEGRADED consensus (`0` restores the old exit; `entry.sh`'s dependency preflight exits 4).

### Verification (cycle-107 sprint-1 + cycle-109 sprint-2/3 cumulative)

- FL 3-model run: 549s, 3 voices' MODELINV envelopes recorded, chains populated, all primaries succeeded
- RT review: 1 MODELINV envelope, cheval audit signature confirmed
- BB: verified via cycle-104 sprint-3 T3.4 (4/4 trials at 297-539KB clean)
- **cycle-109 Sprint 2**: 234 new tests; verdict-quality envelope wired through 7/7 IMP-004 consumers; 5 canonical regression fixtures (#807/#809/#823/#868/KF-002 PRD-review) locked in conformance matrix.
- **cycle-109 Sprint 3 progress**: T3.1 matrix scaffold + T3.2-T3.5 Cluster B fixes (#864/#863/#793/#820) + T3.6 feature-flag removal + T3.10 activation regression CI workflow. 810-cell matrix wired into `.github/workflows/activation-regression.yml`.
