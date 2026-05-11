# cheval-delegate architecture (operator runbook)

> **Audience:** Loa operators running BB / Flatline. Not a developer SDD —
> for the full design see
> `grimoires/loa/cycles/cycle-103-provider-unification/sdd.md`. This runbook
> covers operational concerns: how the unified path works, what env vars
> matter, how to diagnose common failures.
>
> **Cycle:** cycle-103 sprint-1 (commits `bed7db56`, `13a3bffa`, `1e1381dd`,
> `2f9887a5`, `92c0057e`, `b430e48e`, `14689c26`, `92b82ba2`, `5143bf5e`).

---

## 1. What changed in cycle-103

Before cycle-103, BB (TypeScript) and Flatline (bash) each spoke directly to
provider APIs over HTTP — BB via Node `fetch`, Flatline via `curl` (or
`call_api_with_retry`). Three observable consequences:

- A provider-side hiccup (KF-001, KF-008) affected BB only, not Flatline,
  or vice versa — because the failure modes were tied to the specific HTTP
  client.
- Fixes had to ship per-language. The KF-001 NODE_OPTIONS workaround in
  `entry.sh` lived in TS-land; the redaction layer lived in bash-land.
- Audit chains diverged: BB emitted its own MODELINV envelope; Flatline
  emitted a separate one through `model-invoke`.

After cycle-103 sprint-1, BB and Flatline both delegate to the cheval Python
substrate (`.claude/adapters/cheval.py`). One HTTP boundary. One audit chain.
Provider-side fixes ship once (in Python) and propagate to every TS / bash
consumer.

---

## 2. The flow at a glance

```
                  ┌─────────────────────────────────────────┐
   Operator       │  BB review pass        Flatline chat    │
   triggers ─────►│  (TypeScript)          (bash)           │
                  └─────────────┬────────────┬──────────────┘
                                │            │
                  ChevalDelegate│            │call_flatline_chat
                  Adapter       │            │(lib-curl-fallback.sh)
                                ▼            ▼
                            ┌───────────────────┐
                            │  python3          │
                            │  .claude/adapters │
                            │  /cheval.py       │
                            └────────┬──────────┘
                                     │ httpx (streaming)
                                     ▼
                           ┌──────────────────────┐
                           │  Provider API:       │
                           │   anthropic /        │
                           │   openai / google    │
                           └──────────────────────┘
                                     │
                          MODELINV   │
                          audit ◄────┘ (one envelope, one chain)
```

The TS delegate spawns a fresh `python3 cheval.py` process per call. The
bash helper does the same. Spawn-per-call latency was benchmarked at
worst-case p95=126ms (well under the 1000ms budget) — see
`grimoires/loa/cycles/cycle-103-provider-unification/handoffs/spawn-vs-daemon-benchmark.md`.
Daemon-mode was descoped for Sprint 1 by that benchmark outcome.

---

## 3. Env-var reference

### Credentials

These cross to the cheval subprocess via env inheritance ONLY — never argv,
never stdin (AC-1.8). Setting them in your shell is sufficient.

| Variable | Provider | Required for |
|----------|----------|--------------|
| `ANTHROPIC_API_KEY` | Anthropic | BB Claude reviews, Flatline Opus paths |
| `OPENAI_API_KEY` | OpenAI | BB GPT reviews, Flatline GPT paths |
| `GOOGLE_API_KEY` or `GEMINI_API_KEY` | Google | BB Gemini reviews |

### Flow-control flags

| Variable | Default | Behavior |
|----------|---------|----------|
| `LOA_BB_FORCE_LEGACY_FETCH` | unset | When `=1`, BB's `ChevalDelegateAdapter` constructor throws a guided-rollback `LLMProviderError(INVALID_REQUEST, ...)` pointing here. The path it would have restored doesn't exist anymore — see §6 below. |
| `LOA_BB_DISABLE_FAMILY_TIMEOUT_FIX` | unset | When `=1`, skips the (now vestigial — see T1.8 marker in `entry.sh`) NODE_OPTIONS Happy Eyeballs workaround. Slated for cycle-104 removal along with the export itself. |
| `LOA_CHEVAL_DISABLE_INPUT_GATE` | unset | When `=1`, disables the per-model max-input-tokens gate (KF-002 layer 3 backstop). Sets the floor for empirical replay tests. Don't use in production unless you've consciously characterized the failure threshold. |
| `LOA_CHEVAL_DISABLE_STREAMING` | unset | When `=1`, forces non-streaming transport. Operator safety valve introduced in cycle-102 Sprint 4A. |
| `HOUNFOUR_FLATLINE_ROUTING` | unset (defaults to config) | Forces `true`/`false`. Controls whether Flatline routes through `model-invoke` (cheval) or falls back to direct curl in `lib-curl-fallback.sh::call_api()`. After cycle-103, this should always evaluate to `true` for chat paths — `call_flatline_chat` calls `model-invoke` directly without checking. |

### Test / development overrides

These are gated to test fixtures only (see safety-mode pattern in
cycle-099 sprint-1E.c CRIT-1 closure) — production paths emit a stderr
warning and ignore them:

- `LOA_FORCE_LEGACY_ALIASES` (cycle-099 model registry)
- `LOA_AUDIT_KEY_PASSWORD` (cycle-098 L1 — deprecated; use `--password-fd`)

---

## 4. Operator one-liners

### Verify the cheval substrate is reachable

```bash
mkdir -p /tmp/cheval-smoke && cat > /tmp/cheval-smoke/response.json <<'EOF'
{"content": "smoke", "usage": {"input_tokens": 1, "output_tokens": 1}}
EOF
python3 .claude/adapters/cheval.py \
  --agent flatline-reviewer \
  --model claude-opus-4.7 \
  --prompt "smoke" \
  --mock-fixture-dir /tmp/cheval-smoke \
  --output-format json \
  --json-errors
```

Expected: exit 0, stdout = JSON with `content: "smoke"`. No network needed
(fixture-mode).

### Verify a BB invocation routes through the delegate (no real API call)

```bash
cd .claude/skills/bridgebuilder-review && \
  npx tsx --test resources/__tests__/cheval-delegate-e2e.test.ts
```

Expected: 2 tests pass. The e2e test spawns real `python3 cheval.py
--mock-fixture-dir`.

### Confirm the CI drift gate is green on your branch

```bash
./tools/check-no-direct-llm-fetch.sh
```

Expected: `OK — no direct provider-API URLs outside the cheval substrate`.
A violation means someone added a provider URL outside the documented
exempt set in `tools/check-no-direct-llm-fetch.allowlist`.

### Pin a specific Claude model for BB

Edit `.loa.config.yaml::bridgebuilder.model`. The model alias passes through
to cheval as a `--model` override. Cheval's resolver
(`loa_cheval/routing/resolver.py`) maps the alias via
`.claude/defaults/model-config.yaml`.

**Known wart:** `claude-opus-4-7` (hyphen) is NOT a registered alias for the
newest Opus — only `claude-opus-4.7` (dot). Older 4-X models have both
forms. If you see `INVALID_CONFIG: Unknown alias: 'claude-opus-4-7'`, switch
to `claude-opus-4.7`. Discovered during T1.6 testing; flagged for the cycle
review backlog.

---

## 5. Troubleshooting matrix

Each row maps a symptom → most likely cause → first-pass fix. The "first
fix" is what to try before deep-diving into logs.

| Symptom | Likely cause | First fix |
|---------|--------------|-----------|
| `LLMProviderError(AUTH_ERROR): cheval-delegate: MISSING_API_KEY...` | API key env var unset, OR not exported to subshell | `echo $ANTHROPIC_API_KEY` etc. in the same shell; `export` it. |
| `LLMProviderError(RATE_LIMITED): cheval-delegate: RATE_LIMITED...` | Provider returned HTTP 429 | Wait + retry. Cheval's retry policy (`loa_cheval/providers/retry.py`) handled the immediate retries; persistent 429 needs operator backoff. |
| `LLMProviderError(TIMEOUT): cheval-delegate: process exceeded timeout=120000ms...` | Provider stream hung past the delegate's wall clock | Increase the delegate's `timeoutMs` constructor option (default 120s). Reasoning-class models (`gpt-5.5-pro`) already have 30min via `deriveTimeoutMs`. |
| `LLMProviderError(TOKEN_LIMIT): cheval-delegate: CONTEXT_TOO_LARGE...` | Input exceeded `max_input_tokens` gate for the model | (a) shrink prompt, OR (b) raise the gate in `.claude/data/model-config.yaml::models.<model>.max_input_tokens`, OR (c) `LOA_CHEVAL_DISABLE_INPUT_GATE=1` (last resort). |
| `LLMProviderError(PROVIDER_ERROR): cheval-delegate: MalformedDelegateError — stdout was not parseable JSON` | Cheval process died mid-output or wrote partial JSON | Look at stderr from the cheval invocation. Common cause: Python exception before MODELINV emit. Run the same command with `--json-errors` and inspect stderr's last line. |
| `LLMProviderError(INVALID_REQUEST): LOA_BB_FORCE_LEGACY_FETCH=1 set but legacy fetch path was removed in cycle-103.` | Someone (or some script) set the env var | Unset it. The legacy path is gone — see §6. |
| Drift gate fails CI on a PR with no provider URL changes | A `.bash` / `.legacy` / `.ts` file was renamed/moved and now matches the scan scope | Either remove the URL, or add the file to `tools/check-no-direct-llm-fetch.allowlist` with rationale. |
| `bridgebuilder-review` test passes locally but fails in CI | Pre-existing `persona.test.ts` makes live `api.anthropic.com` fetch calls | Not a cycle-103 regression — the failure was already there pre-T1.2 (verified on stashed tree). Skip or stub the test if it blocks. |
| Cheval Python pytest fails on `test_validate_bindings_includes_new_agents` | `model-invoke --validate-bindings` needs `--merged-config` arg | Pre-existing test bug; unrelated to cycle-103. |

---

## 6. The `LOA_BB_FORCE_LEGACY_FETCH=1` decision tree

```
Operator sets LOA_BB_FORCE_LEGACY_FETCH=1 ──┐
                                            │
                                            ▼
                         ChevalDelegateAdapter constructor trips
                                            │
                                            ▼
                  throws LLMProviderError(INVALID_REQUEST, ...)
                  pointing here
                                            │
                                            ▼
                              Was that intentional?
                                    │
                  ┌─────────────────┴─────────────────┐
                  │                                   │
                Yes                                  No
                  │                                   │
                  ▼                                   ▼
   "I want the pre-cycle-103         "Some script / .env still has
    fetch path back"                  the var set from an old session"
                  │                                   │
                  ▼                                   ▼
   That path does NOT exist.         `unset LOA_BB_FORCE_LEGACY_FETCH`
   `adapters/{anthropic,openai,      and re-run.
   google}.ts` were deleted by
   T1.4 (commit 92c0057e). Their
   git history is recoverable
   via `git show HEAD~N:<path>`
   but the package no longer
   exports them.
                  │
                  ▼
   To resurrect: file an issue
   on 0xHoneyJar/loa describing
   what failure mode the cheval
   path doesn't cover. The cycle-
   104 sunset window will decide
   whether to keep this trip or
   remove it entirely.
```

### Short answer

**On cycle-103: never flip this flag.** It's a guided-rollback surface, not
a working escape hatch. The legacy fetch path was removed; the flag exists
so an operator who *expects* the old path can find this runbook instead of
silently degrading.

---

## 7. Audit + observability

Every cheval invocation emits a single MODELINV envelope at completion. The
envelope's `models_succeeded` field carries `<provider>:<model_id>`. From
the cheval side, `cmd_invoke` (`.claude/adapters/cheval.py:280`) wraps the
adapter dispatch in a try/finally that emits MODELINV on every exit —
success or failure.

Operator commands to inspect the chain:

```bash
# Last 10 MODELINV events
tail -10 .run/audit.jsonl | jq 'select(.event == "MODELINV/model.invoke.complete")'

# Filter by provider
jq 'select(.payload.models_succeeded[0] // "" | startswith("anthropic:"))' \
    .run/audit.jsonl | tail -3

# Latency distribution for the last 50 calls
tail -100 .run/audit.jsonl | \
    jq -r 'select(.event=="MODELINV/model.invoke.complete") | .payload.invocation_latency_ms' | \
    sort -n | uniq -c
```

The fixture-mode response carries `metadata.mock_fixture: true` and
`metadata.fixture_path: <path>` so an audit-trail review can distinguish
real calls from test-replay calls (see T1.5 implementation report
"Known Limitations" §3 — the MODELINV emitter doesn't currently surface
`mock_fixture` in the envelope itself; an operator wanting to filter must
look at the cheval-side log).

---

## 8. What about embeddings?

`flatline-semantic-similarity.sh::get_embedding` is exempt from the drift
gate. Cheval's adapter base class has only `complete()` — no `embed()` —
so the embeddings call still uses direct curl to
`https://api.openai.com/v1/embeddings`. This is documented in
`tools/check-no-direct-llm-fetch.allowlist` and in the T1.6 audit doc.

Migration path: when cheval grows an `embed()` method (cycle-104+), remove
the entry from the allowlist; the drift gate then enforces migration.

---

## 9. Related runbooks + docs

| Path | What it covers |
|------|----------------|
| `grimoires/loa/cycles/cycle-103-provider-unification/sdd.md` | Developer-facing design — types, contracts, exit-code tables |
| `grimoires/loa/cycles/cycle-103-provider-unification/handoffs/T1.6-flatline-api-audit.md` | Enumerated audit of every direct-API call site, pre- and post-migration |
| `grimoires/loa/known-failures.md#kf-008` | Architectural closure record |
| `grimoires/loa/runbooks/cheval-streaming-transport.md` | Streaming-specific operator concerns |
| `grimoires/loa/runbooks/curl-mock-harness.md` | Fixture-mode for bash callers (sibling pattern to cheval `--mock-fixture-dir`) |
| `tools/check-no-direct-llm-fetch.sh` | CI drift gate (T1.7) |

---

## 10. Version + commit references

This runbook describes the architecture as it ships in **cycle-103
sprint-1** (this branch: `feature/feat/cycle-103-kickoff`). Key commits:

- `bed7db56` — T1.0 httpx large-body spike
- `13a3bffa` — T1.1 spawn-vs-daemon benchmark (decided spawn-mode)
- `1e1381dd` — T1.2 `ChevalDelegateAdapter`
- `2f9887a5` — T1.5 cheval `--mock-fixture-dir`
- `92c0057e` — T1.4 adapter-factory collapse (deleted `adapters/{anthropic,openai,google}.ts`)
- `b430e48e` — T1.6 Flatline → model-invoke
- `14689c26` — T1.7 CI drift gate
- `92b82ba2` — T1.8 entry.sh NODE_OPTIONS vestigial marker
- `5143bf5e` — T1.9 KF-008 closure

If you're reading this runbook on `main` after cycle-103 merged, the commit
IDs may have changed due to rebase; the SHA-as-substring `cycle-103
sprint-1` should match either way via `git log --grep=`.
