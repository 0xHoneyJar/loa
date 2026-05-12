# Chain-walk debugging (operator runbook)

> **Audience:** Loa operators triaging why a cheval invocation walked to
> a different model than they expected, or why a voice was dropped from
> consensus. Companion to [headless-mode.md](headless-mode.md).
>
> **Cycle:** cycle-104 sprint-2 T2.12. Documents the verbose-mode stderr
> contract + MODELINV envelope read patterns.

---

## 1. The two evidence surfaces

A chain walk produces evidence in two places:

| Surface | Where | When to use |
|---------|-------|-------------|
| **Verbose stderr** (`LOA_HEADLESS_VERBOSE=1`) | Real-time, on the invoking shell | Live debug during a failing pass |
| **MODELINV envelope** | `grimoires/loa/a2a/trajectory/modelinv-<date>.jsonl` (cheval's append) | Post-hoc forensics; the canonical record |

Either alone tells the story, but together they correlate the operator's
direct observation with the durable audit. Always cite the envelope
entry — stderr is ephemeral.

---

## 2. Verbose mode (`LOA_HEADLESS_VERBOSE=1`)

Set the env var on the invoking shell. cheval emits a one-line stderr
record at every chain-walk decision point. Format:

| Event | Stderr line |
|-------|-------------|
| Capability skip | `[cheval] skip <provider:model> (capability_mismatch: missing=<list>)` |
| Input-too-large skip | `[cheval] skip <provider:model> (input_too_large: <est> > <threshold>)` |
| Walk on retryable error | `[cheval] fallback <provider:model> -> next (<reason>)` |

The `<reason>` token is one of:

- `empty_content` — KF-003 class; provider returned 200 with no content
- `context_too_large` — adapter-level CONTEXT_TOO_LARGE error
- `rate_limited` — provider 429 / quota
- `provider_unavailable` — provider 5xx
- `fallback_exhausted` — adapter ran out of internal retries
- `provider_disconnect` — KF-008 class; mid-stream TCP disconnect

Off by default to keep stderr quiet for happy-path callers. cycle-104
SDD §6.4 reserves the right to add reasons; new ones surface here without
schema bumps.

---

## 3. Reading the MODELINV v1.1 envelope

A representative chain-walk envelope (formatted for readability — the
actual JSONL is one object per line):

```jsonc
{
  "event": "modelinv.complete",
  "models_requested": [
    "openai:codex-headless",
    "openai:gpt-5.5-pro",
    "openai:gpt-5.3-codex"
  ],
  "models_failed": [
    {
      "model": "openai:codex-headless",
      "provider": "openai",
      "error_class": "CAPABILITY_MISS",
      "missing_capabilities": ["tools"]
    },
    {
      "model": "openai:gpt-5.5-pro",
      "provider": "openai",
      "error_class": "EMPTY_CONTENT",
      "message_redacted": "Provider returned 200 with empty content"
    }
  ],
  "final_model_id": "openai:gpt-5.3-codex",
  "transport": "http",
  "config_observed": {
    "headless_mode": "prefer-cli",
    "headless_mode_source": "env"
  }
}
```

### Diagnostic queries

| Question | jq query |
|----------|----------|
| Was this a chain walk? | `.final_model_id != .models_requested[0] and (.models_failed | length) > 0` |
| What killed each skipped entry? | `.models_failed[] | {model, error_class}` |
| Did the chain exhaust? | `.final_model_id == null and .transport == null` |
| What mode resolved this call? | `.config_observed.headless_mode, .config_observed.headless_mode_source` |
| Which transport ran the winner? | `.transport` (`"http"` / `"cli"` / `null`) |

```bash
# Pull every chain-walk over the last day (final ≠ first attempted)
jq -c 'select(.event=="modelinv.complete" and .final_model_id != .models_requested[0])' \
  grimoires/loa/a2a/trajectory/modelinv-$(date +%Y-%m-%d).jsonl
```

---

## 4. Voice-drop forensics

When a voice drops from flatline consensus (cheval exit 12 →
T2.8 voice-drop wiring), TWO log lines tell the story:

**Trajectory (machine-readable):**
`grimoires/loa/a2a/trajectory/flatline-<date>.jsonl`

```jsonc
{
  "type": "flatline_protocol",
  "event": "consensus.voice_dropped",
  "timestamp": "2026-05-12T13:24:00Z",
  "state": "PHASE1",
  "data": {
    "voice": "gpt-review",
    "phase": "prd",
    "reason": "chain_exhausted",
    "exit_code": 12
  }
}
```

**Orchestrator stderr (operator-facing):**

```
[flatline] Voice dropped from consensus (chain exhausted): gpt-review
[flatline] Voice-drop: 1 of 4 Phase 1 voices dropped from consensus (chain exhausted): gpt-review
```

To correlate the drop with its cheval-side cause: find the MODELINV
envelope for the same timestamp window and assert `final_model_id ==
null and (models_failed | length) >= 1`. The `models_failed[]` entries
explain WHY the chain ran out for that voice.

```bash
# All voice-drops in the last day, with their voice labels
jq -c 'select(.event=="consensus.voice_dropped") | .data.voice' \
  grimoires/loa/a2a/trajectory/flatline-$(date +%Y-%m-%d).jsonl
```

---

## 5. Common diagnostic patterns

### "The chain always walks past my first entry"

Likely cause: `LOA_HEADLESS_MODE` resolution.

1. Check `config_observed.headless_mode` + `config_observed.headless_mode_source`.
2. If `source: "env"`, you set the env to a non-default value somewhere
   (wrapper script, IDE settings, dotfile).
3. If `source: "default"`, neither env nor config was set; you may want
   to explicitly set `hounfour.headless.mode: prefer-api` in
   `.loa.config.yaml` to make the intent durable.

### "Voice dropped but I expected substitution"

This is cycle-104 design (T2.8): cross-company substitution was the
cycle-102 T1B.4 anti-pattern and is structurally retired. Voice-drop is
graceful — the orchestrator proceeds with the remaining voices and
emits `consensus.voice_dropped` to the trajectory log. If you NEED
cross-company semantics, you're routing through the wrong primitive.
See SDD §6.5 cycle-104.

### "Every voice in my consensus dropped"

Check `models_failed[]` across the 3 voices' MODELINV envelopes for the
same timestamp. If all 3 show the SAME `error_class`, the issue is
systemic (provider outage, capability-gate misconfig, input-size
ceiling). If they differ, you have 3 independent failures and a likely
network event.

### "I never see verbose lines even with `LOA_HEADLESS_VERBOSE=1`"

cheval reads the env at invocation start; if your wrapper script
sanitizes env vars before exec, the var won't propagate. Try
`env LOA_HEADLESS_VERBOSE=1 <wrapper>` to force-pass, or set it in the
wrapper's own startup section.

### "`transport: cli` shows up unexpectedly under `prefer-api`"

`prefer-api` does NOT mean "API only". It means "chain entries in
their declared order; HTTP first if that's how the YAML reads".
A `kind: cli` entry can still win if the HTTP entries upstream all
walked. To force HTTPS-only, set `LOA_HEADLESS_MODE=api-only` or
`hounfour.headless.mode: api-only`.

---

## 6. When chain-walk is NOT the story

These exit codes are NOT chain walks — they short-circuit the loop:

| Exit | Class | Meaning |
|------|-------|---------|
| 8 | INTERACTION_PENDING | Async-mode handle; only single-entry chains allowed |
| 11 | NO_ELIGIBLE_ADAPTER | Chain has 0 entries after mode/capability filter (operator config error) |
| 12 | CHAIN_EXHAUSTED | Multi-entry chain walked to end without success |

A single-entry chain that fails preserves cycle-103 exit codes
(`RETRIES_EXHAUSTED`, `RATE_LIMITED`, etc.) — external tooling that
already grepped those codes still works. The new codes (11, 12) only
appear when the operator declared a multi-entry chain.

---

## 7. Related runbooks

- [headless-mode.md](headless-mode.md) — operator-facing mode reference
- [headless-capability-matrix.md](headless-capability-matrix.md) — capability gate table
- [cheval-delegate-architecture.md](cheval-delegate-architecture.md) — the cheval substrate (cycle-103)
- `.claude/adapters/cheval.py` — chain walk implementation
- `tests/integration/flatline-orchestrator-voice-drop.bats` — voice-drop wiring contract
