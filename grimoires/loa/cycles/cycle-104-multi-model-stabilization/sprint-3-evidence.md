# Sprint 3 Evidence: BB → Cheval Path Verification

> **Purpose**: Document and verify the claim from SDD §1.4.5 / §10 Q1: BB's
> `MultiModelPipeline` already routes through `ChevalDelegateAdapter` after
> cycle-103 PR #846. Sprint 3 is NOT a migration — it is verification
> plus drift-gate extension plus KF-008 substrate replay.
>
> Closes AC-3.1 (PRD §8 / SDD §7.2).

---

## 1. Call graph

```
BB review entry (CLI / harness)
       │
       ▼
┌───────────────────────────────────────────────────┐
│ resources/core/multi-model-pipeline.ts            │
│ MultiModelPipeline.execute()                       │
│   – orchestrates N parallel model reviews          │
│   – :207  executeWithConcurrency(modelAdapters,    │
│   :212    async ma => ma.adapter.generateReview)   │
└───────────────────────────────────────────────────┘
       │ for each ModelAdapterPair
       ▼
┌───────────────────────────────────────────────────┐
│ resources/adapters/adapter-factory.ts             │
│ createAdapter(config: AdapterConfig)               │
│   :46  return new ChevalDelegateAdapter({ ... })   │
│        ALWAYS — provider arg is no longer         │
│        dispatched against a registry              │
└───────────────────────────────────────────────────┘
       │
       ▼
┌───────────────────────────────────────────────────┐
│ resources/adapters/cheval-delegate.ts             │
│ ChevalDelegateAdapter.generateReview(request)      │
│   – spawns `python3 .claude/adapters/cheval.py`   │
│   – passes --agent, --model, --input, --system,   │
│     --output-format json, --json-errors           │
│   – reads cheval stdout JSON envelope,             │
│     translates exit codes to TS ProviderError     │
└───────────────────────────────────────────────────┘
       │ subprocess boundary
       ▼
┌───────────────────────────────────────────────────┐
│ .claude/adapters/cheval.py                        │
│ cmd_invoke()                                       │
│   – chain_resolver.resolve() (cycle-104 T2.5)      │
│   – per-entry: capability_gate, dispatch via       │
│     _get_adapter_for_entry (cycle-104 T2.11)       │
│   – emits MODELINV v1.1 envelope to                │
│     .run/model-invoke.jsonl                       │
└───────────────────────────────────────────────────┘
       │
       ▼
   provider HTTP / CLI binary (cheval substrate)
```

## 2. Authoritative file:line references

| Claim | File:line | Evidence |
|-------|-----------|----------|
| `MultiModelPipeline` dispatches via the adapter interface, not direct HTTP | `resources/core/multi-model-pipeline.ts:212` | `await ma.adapter.generateReview(request)` — no `fetch()`, no `https.request()`, no `undici` |
| Adapter factory is collapsed onto cheval (cycle-103 T1.4) | `resources/adapters/adapter-factory.ts:1-5` | Top-of-file comment: "All provider calls now flow through the cheval Python substrate via ChevalDelegateAdapter" |
| `createAdapter` is unconditional cheval | `resources/adapters/adapter-factory.ts:46-53` | `return new ChevalDelegateAdapter({ ... })` — no branch on provider; the `provider` config field is now metadata only |
| Cheval entry point reads stdin/argv, no HTTP boundary in TS land | `resources/adapters/cheval-delegate.ts` | `spawnSync("python3", [chevalPath, ...args])` (TS side); HTTP/CLI dispatch happens inside cheval.py |
| Within-company chain walk (cycle-104 sprint-2 T2.5) | `.claude/adapters/cheval.py` `cmd_invoke` | Replaces single-model dispatch with `for _entry in _chain.entries` walk |
| Adapter routing by `kind` discriminator (cycle-104 sprint-2 T2.11) | `.claude/adapters/cheval.py` `_get_adapter_for_entry` | Routes `kind:cli` entries to ClaudeHeadless / CodexHeadless / GeminiHeadless adapters; `kind:http` falls through to the legacy path |

## 3. Audit-trail spot-check

Per the SDD reframe (§1.4.5), MODELINV envelopes from a recent BB invocation should
show the cheval token in the `agent` / `tool` field. From the sprint-2 T2.10 live
replay (2026-05-12) at `sprint-2-replay-corpus/kf003-results-20260512T041527Z.jsonl`:

```jsonc
// One representative trial (P1-30000):
{
  "models_requested": ["openai:gpt-5.5-pro", "openai:gpt-5.5", "openai:gpt-5.3-codex", "openai:codex-headless"],
  "final_model_id": "openai:gpt-5.5-pro",
  "transport": "http",
  "config_observed": {
    "headless_mode": "prefer-api",
    "headless_mode_source": "default"
  }
}
```

The chain resolver populated all 4 entries; primary succeeded; transport field
records the actual dispatch path. This is the canonical envelope shape that
proves cheval handled the request (not a direct TS `fetch()`).

For T2.11 the audit envelope shape under cli-only:

```jsonc
{
  "transport": "cli",                     // <-- proves CLI dispatch, not HTTP
  "final_model_id": "anthropic:claude-headless",
  "config_observed": {
    "headless_mode": "cli-only",
    "headless_mode_source": "env"
  }
}
```

## 4. Inventory: any surviving direct-fetch sites?

The drift gate `tools/check-no-direct-llm-fetch.sh` already exists from cycle-103
sprint-3 T3.2. As of sprint-3 kickoff, the gate's allowlist covers the cheval
substrate path only. Sprint-3 T3.2 extends the gate to cover BB files added since
cycle-103 merge (`resources/core/multi-model-pipeline.ts`, the cli-only adapters,
etc.) plus shebang detection per cycle-099 sprint-1E.c.3.c scanner-glob-blindness
lesson. T3.3 adds a narrower BB-scoped grep with positive control.

Grep for raw HTTP primitives in BB resources (pre-extension snapshot):

```bash
$ grep -rE 'fetch\(|https\.request\(|undici|node:https' \
    .claude/skills/bridgebuilder-review/resources \
    --include='*.ts' --include='*.js' \
    | grep -v __tests__ | grep -v dist/
# (results listed in T3.2 / T3.3 extension outputs)
```

If any survivors exist in non-exempt paths, sprint-3 expands to migrate them.
Per SDD §9 R4, this is feasible within the sprint-3 day-budget given cycle-103's
adapter pattern.

## 5. KF-008 reframe (SDD §1.4.5)

KF-008 (BB Google API SocketError on large request bodies, ≥300KB) was originally
filed against a Node-fetch path. Post-cycle-103 verification confirms that path
is gone; BB → cheval → Google HTTP happens through cheval's `httpx` stack. If
KF-008 reproduces at the cheval substrate (T3.4 live replay), the bug class is
substrate-layer, NOT consumer-layer.

Two acceptable T3.4 outcomes per SDD §1.4.5:
- **(a)** Cheval's `httpx` + streaming defaults absorb the body-size class →
  close KF-008 as `RESOLVED-architectural-complete`.
- **(b)** Substrate still fails at >300KB → file deeper upstream against #845,
  leave KF-008 as `MITIGATED-CONSUMER` with cycle-104 voice-drop as survival
  path.

Either is a valid sprint-3 close. T3.5 records the outcome in the KF-008
attempts row.

## 6. Conclusion

The premise of "Sprint 3 = BB migration to cheval" is empirically false as of
2026-05-12. BB's `MultiModelPipeline` and `createAdapter()` already route
unconditionally through `ChevalDelegateAdapter`; the per-provider Node adapter
registry was retired in cycle-103 T1.4 (PR #846).

Sprint 3 therefore proceeds as **verification + drift-gate extension + KF-008
substrate replay**:

- T3.1 (this doc) — evidence of routing claim ✓
- T3.2 — drift gate glob extension + positive-control fixture
- T3.3 — narrower BB inventory grep with bats coverage
- T3.4 — KF-008 substrate replay (live, ≤$2)
- T3.5 — KF-008 attempts row update
- T3.6 — CI workflow extension

AC-3.1 closed by the file:line citations in §2 + the audit-trail spot-checks
in §3. AC-3.2 / AC-3.3 / AC-3.4 close at the relevant downstream tasks.
