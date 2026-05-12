# Headless mode (operator runbook)

> **Audience:** Loa operators routing model traffic through CLI binaries
> (Claude Code / Codex / Gemini CLI) instead of HTTP API endpoints, or
> mixing the two via the within-company fallback chain.
>
> **Cycle:** cycle-104 sprint-2 (T2.4 + T2.7 wired the routing, T2.8
> repurposed the cross-company fallback as a voice-drop trigger, T2.12
> ships this runbook).

---

## 1. What headless mode does

Headless mode lets operators steer cheval's within-company fallback chain
toward CLI adapters (`kind: cli`) vs HTTP adapters (`kind: http`) without
editing `model-config.yaml`. It is a routing knob, not a feature flag —
the chain entries are already declared per provider; the mode reorders
or filters them at resolve-time.

Two surfaces produce the same routing decision:

| Surface | Where it lives | Precedence |
|---------|----------------|------------|
| `LOA_HEADLESS_MODE` env var | shell / wrapper script | **wins** |
| `hounfour.headless.mode` config key | `.loa.config.yaml` | fallback |
| (neither set) | hard-coded default `prefer-api` | last resort |

Resolution happens once at cheval invocation in `resolve_headless_mode()`
and is frozen onto the chain via `chain_resolver.resolve(mode=...)`. The
resolved mode is recorded in the MODELINV envelope under
`config_observed.headless_mode` + `config_observed.headless_mode_source`.

---

## 2. The four modes

| Mode | Effect on chain | When to use |
|------|-----------------|-------------|
| `prefer-api` (default) | Chain entries unchanged from `model-config.yaml`. HTTP first if that's how the chain is declared, CLI after. | Production with API keys present; preserves cycle-103 behavior. |
| `prefer-cli` | CLI entries (`kind: cli`) lifted to the front of the chain; HTTP entries kept after as fallback. | Operators with both CLI binaries AND API keys who want CLI's longer context / unmetered semantics when available, but with a working HTTPS fall-back. |
| `api-only` | All `kind: cli` entries filtered out. Pure HTTP chain. | Sandbox / CI without CLI binaries; explicit HTTPS-only audit lane. |
| `cli-only` | All `kind: http` entries filtered out. Pure CLI chain. | Zero-API-key environments (e.g. fresh laptop, secure airgap). cheval refuses to issue HTTPS — verifiable via `strace -f -e trace=connect`. |

Empty chain after filter (e.g. `prefer-cli` with no CLI binaries installed)
surfaces `NoEligibleAdapterError` → cheval exit 11 with install guidance.

---

## 3. Setting the mode

### Per-invocation override (most precise)

```bash
LOA_HEADLESS_MODE=cli-only python3 .claude/adapters/cheval.py invoke \
    --agent flatline-reviewer \
    --model claude-headless \
    --prompt "..."
```

### Project-wide default

```yaml
# .loa.config.yaml
hounfour:
  headless:
    mode: prefer-cli
    cli_paths:
      claude: /opt/claude/bin/claude    # optional override
      codex: /opt/openai/bin/codex
      gemini: /opt/google/bin/gemini
```

`cli_paths` is a discovery hint; cheval still falls back to `$PATH` if
the configured binary is missing. The adapter's `kind: cli` entry in
`model-config.yaml` declares which binary it needs.

### Unset → safe default

When neither env nor config is set, cheval logs
`config_observed.headless_mode_source: "default"` and resolves to
`prefer-api`. No surprises in upgrades that don't touch headless config.

---

## 4. CLI binary pre-requisites

| Adapter alias | Binary | Install (Ubuntu) | Auth |
|---------------|--------|------------------|------|
| `claude-headless` | `claude` (Claude Code CLI) | `npm i -g @anthropic-ai/claude-code` | OAuth via `claude` once |
| `codex-headless` | `codex` (OpenAI Codex CLI) | `npm i -g @openai/codex-cli` | OAuth via `codex` once |
| `gemini-headless` | `gemini` (Google Gemini CLI) | `npm i -g @google/gemini-cli` | OAuth via `gemini` once |

Each CLI maintains its own credential store in the user's home directory.
cheval does not pass API keys to CLIs; it `spawn`s the binary and reads
its stdout. CLI auth is the operator's responsibility, separate from
HTTP API keys.

When a chain entry's CLI binary is missing, cheval skips the entry with
`error_class: ROUTING_MISS` and continues walking the chain. The
operator sees the skip in the MODELINV envelope (`models_failed[]`).

---

## 5. Capability tradeoffs

Not every CLI has feature parity with its HTTP sibling. See
[headless-capability-matrix.md](headless-capability-matrix.md) for the
adapter-by-feature breakdown. The short version:

- `claude-headless` ≈ full parity with Anthropic HTTP API (same models,
  same context window, structured output via JSON mode).
- `codex-headless` does **not** support tool use; if your call needs
  tools, cheval's capability gate skips the entry with
  `error_class: CAPABILITY_MISS`.
- `gemini-headless` does **not** support structured-output JSON mode;
  same capability-gate skip path.

The capability gate runs BEFORE adapter dispatch, so a misrouted entry
walks the chain without spending a provider call.

---

## 6. Audit envelope evidence (MODELINV v1.1)

Every cheval invocation emits a MODELINV envelope. After T2.6 the
envelope includes:

| Field | What it tells you |
|-------|-------------------|
| `models_requested[]` | Every chain entry, in resolve order |
| `models_failed[]` | Per-entry skip / fail reason + `error_class` |
| `final_model_id` | provider:model_id that produced the result (null if chain exhausted) |
| `transport` | `"http"` or `"cli"` of the successful entry (null if exhausted) |
| `config_observed.headless_mode` | Resolved mode (one of 4 above) |
| `config_observed.headless_mode_source` | `"env"`, `"config"`, or `"default"` |

The combination of `final_model_id != models_requested[0]` AND non-empty
`models_failed[]` proves a chain walk happened. The `transport` field
lets the operator confirm CLI dispatch on a `cli-only` run without
needing strace.

See [chain-walk-debugging.md](chain-walk-debugging.md) for diagnostic
patterns against this envelope.

---

## 7. When the orchestrator drops a voice

cycle-104 T2.8 repurposes the cross-company
`flatline_protocol.models.{secondary, tertiary}` defaults: when a voice's
within-company chain exhausts (cheval exit 12 = `CHAIN_EXHAUSTED`), the
flatline orchestrator DROPS that voice from consensus aggregation rather
than substituting another company's model into the same slot. The drop
is surfaced via:

- `[flatline] Voice dropped from consensus (chain exhausted): <label>`
  on stderr
- A `consensus.voice_dropped` event in
  `grimoires/loa/a2a/trajectory/flatline-<date>.jsonl`

Voice-drop is graceful — consensus proceeds with the remaining voices.
All voices dropping (or a mix of drops + hard failures totaling the call
count) is the only condition that produces exit 3 "All Phase 1 model
voices unavailable" with the drop/fail breakdown in the diagnostic.

`NO_ELIGIBLE_ADAPTER` (cheval exit 11) is a config error — it is NOT a
voice-drop and surfaces as a hard failure so the operator sees the
underlying misconfig. The voice-drop classifier is pinned to this
distinction in `tests/unit/voice-drop-classifier.bats` (VDC-T3).

---

## 8. Common operator failures

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `NoEligibleAdapterError` + `cli-only` mode | No CLI binaries on `$PATH` | Install `claude` / `codex` / `gemini` per §4; or fall back to `api-only` |
| All voices chain-exhausted (exit 3) | Network outage affecting all providers | Wait + retry; do NOT manually set `flatline_protocol.code_review.model` (gated on KF-003 replay, T2.10) |
| `CAPABILITY_MISS` on `codex-headless` | Tool use requested, codex doesn't support | Use `prefer-api` for that voice OR remove tools from the call |
| `transport: http` when expecting `cli` | `LOA_HEADLESS_MODE` not set or unset in the wrapper | Check `config_observed.headless_mode_source` — `"default"` means neither env nor config was set |

---

## 9. Related runbooks

- [cheval-delegate-architecture.md](cheval-delegate-architecture.md) — the substrate cheval runs on (cycle-103)
- [headless-capability-matrix.md](headless-capability-matrix.md) — feature-by-adapter table (T2.12 companion)
- [chain-walk-debugging.md](chain-walk-debugging.md) — diagnosing chain-walk evidence in audit envelopes (T2.12 companion)
