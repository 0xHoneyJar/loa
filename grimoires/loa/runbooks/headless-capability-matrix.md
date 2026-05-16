# Headless adapter capability matrix

> **Audience:** Loa operators choosing between HTTP and CLI adapters for a
> specific call shape. Companion to
> [headless-mode.md](headless-mode.md).
>
> **Cycle:** cycle-104 sprint-2 T2.12 (FR-S2.2). Mirrors the capability
> declarations in `model-config.yaml`'s `capabilities:` block per
> adapter alias.

---

## 1. Feature × adapter table

The capability gate (`chain_resolver.py`'s capability filter) reads each
adapter's declared capabilities from `model-config.yaml` and skips entries
that lack a requested capability. A `✓` means the adapter advertises the
feature; `✗` means it does not; `~` means partial / version-gated.

| Capability | claude-headless | codex-headless | gemini-headless | claude (HTTP) | gpt-5.5 / 5.3 (HTTP) | gemini-3.1-pro (HTTP) |
|------------|:---------------:|:--------------:|:---------------:|:-------------:|:--------------------:|:--------------------:|
| **Text generation** | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| **System prompt (persona)** | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| **Streaming output** | ~ (line-buffered) | ~ | ~ | ✓ | ✓ | ✓ |
| **Tool use / function calling** | ✓ | ✗ | ~ (basic) | ✓ | ✓ | ✓ |
| **Structured JSON output** | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ |
| **Vision / image input** | ✓ | ✗ | ~ (CLI flag) | ✓ | ~ (per-model) | ✓ |
| **Long context (>128K)** | ✓ (1M on capable models) | ~ (model-dependent) | ✓ | ✓ | ~ | ✓ |
| **Citations / grounding** | ~ | ✗ | ✗ | ✓ | ✗ | ~ |
| **Cost metering by call** | ✗ (unmetered) | ✗ | ✗ | ✓ | ✓ | ✓ |

`~` semantics: read the adapter's actual `capabilities:` block in
`model-config.yaml` for the authoritative declaration. The table here is
a navigational hint, not a contract.

---

## 2. How the capability gate skips an entry

When a request asks for `tools`, the gate computes the request's required
capabilities and intersects with each chain entry's declared capabilities.
A missing capability triggers a skip BEFORE adapter dispatch:

```
[cheval] skip openai:codex-headless (capability_mismatch: missing=['tools'])
```

The MODELINV envelope records:

```json
{
  "models_failed": [
    {
      "model": "openai:codex-headless",
      "provider": "openai",
      "error_class": "CAPABILITY_MISS",
      "missing_capabilities": ["tools"],
      "message_redacted": "missing capabilities: ['tools']"
    }
  ]
}
```

The walk then proceeds to the next chain entry, which may be the HTTP
fallback for the same provider. The operator's `prefer-cli` intent is
respected up to the capability boundary.

---

## 3. When does this matter at orchestration time?

The capability gate runs **per adapter entry, per cheval invocation**.
Each voice (Phase 1 review or skeptic in flatline) is a separate
invocation. So:

- A 3-model flatline run with `LOA_HEADLESS_MODE=prefer-cli` and a
  tool-use request will see `codex-headless` skip on the OpenAI voice's
  chain, walk to `gpt-5.5-pro` HTTP, and dispatch there.
- The same run on a `cli-only` mode would chain-exhaust the OpenAI voice
  (codex-headless skipped, no HTTP fallback available), trip T2.8's
  voice-drop, and produce consensus with the remaining 2 voices.

The capability matrix is therefore the practical bound on how
`cli-only` mode performs for complex calls. Plain text generation
behaves identically; tool-augmented calls degrade gracefully via
voice-drop.

---

## 4. Adding / updating a capability

Capabilities live alongside the adapter alias in `model-config.yaml`:

```yaml
adapters:
  codex-headless:
    kind: cli
    binary: codex
    provider: openai
    model_id: gpt-5.5
    capabilities:
      - text
      - system_prompt
      - structured_output
      # no `tools` — codex CLI does not support function calling
```

The set is unenum'd intentionally; callers ask for whatever capability
string they need, and the gate compares against the declared set. The
canonical capability strings used by the codebase are documented in
`.claude/adapters/capability_gate.py:CapabilityRequest`.

---

## 5. Related

- [headless-mode.md](headless-mode.md) — operator-facing mode reference
- [chain-walk-debugging.md](chain-walk-debugging.md) — diagnosing skip events post-hoc
- `.claude/adapters/capability_gate.py` — gate implementation
- `.claude/adapters/tests/test_capability_gate.py` — pinned skip behavior
