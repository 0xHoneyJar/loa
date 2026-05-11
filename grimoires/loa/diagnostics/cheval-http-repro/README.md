# cheval HTTP-Asymmetry Reproduction Harness

Standalone diagnostic for KF-002 layer 3 — the "RemoteProtocolError at 60s"
class observed 2026-05-09 through 2026-05-10 on Anthropic + OpenAI cheval
paths with 26K+ token inputs.

## What this harness does

`repro.py` tests four httpx transport variants against the real provider
endpoints, sending a configurable prompt size and reporting wall-clock time
+ failure class for each variant:

| Variant | Transport |
|---------|-----------|
| V0_h11_post | `httpx.post()` with HTTP/1.1 — matches cheval `base.py:http_post()` exactly |
| V1_h2_client | `httpx.Client(http2=True).post()` — HTTP/2 negotiated via ALPN |
| V2_stream_h11 | `httpx.stream("POST", ...)` with `stream: true` in body |
| V3_h11_keepalv | HTTP/1.1 with `SO_KEEPALIVE` + TCP keepalive probes every 20s |

V0 is the control. V1, V2, V3 are candidate fixes for the 60s wall.

## Why this exists in the repo

The original layer 3 bug was reported with a specific stack trace
(`httpx.RemoteProtocolError("Server disconnected without sending a
response")` at exactly 60s wall-clock) but did not reproduce in
2026-05-11 testing. The harness is preserved so future sessions can:

- Confirm whether the failure has returned
- Validate any client-side fix (streaming response, HTTP/2, etc.) against
  the actual failure mode rather than a guess
- Provide a deterministic regression-pin scaffold for the eventual
  structural fix's pytest

## Running

```bash
# Set up an isolated venv with httpx + h2 (HTTP/2 support)
python3 -m venv /tmp/cheval-repro-venv
/tmp/cheval-repro-venv/bin/pip install --quiet "httpx[http2]"

# Smallest possible smoke (anthropic, 100-char prompt, V0 only)
ANTHROPIC_API_KEY=... /tmp/cheval-repro-venv/bin/python repro.py anthropic 100 V0_h11_post

# Full matrix (30K-token payload, all 4 variants)
ANTHROPIC_API_KEY=... /tmp/cheval-repro-venv/bin/python repro.py anthropic 120000

# Reasoning-model path with extended thinking
ANTHROPIC_THINKING=1 ANTHROPIC_MAX_TOKENS=8000 \
  /tmp/cheval-repro-venv/bin/python repro.py anthropic 200000 V0_h11_post

# OpenAI path
OPENAI_API_KEY=... /tmp/cheval-repro-venv/bin/python repro.py openai 120000
```

## Env-var inputs

| Var | Purpose | Default |
|-----|---------|---------|
| `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` | Provider credentials | Required |
| `ANTHROPIC_MODEL` | Override anthropic model | `claude-opus-4-5` |
| `ANTHROPIC_MAX_TOKENS` | Override max_tokens | `256` |
| `ANTHROPIC_THINKING` | Enable extended thinking | unset |

## Argv

```
repro.py <provider> [<prompt_chars>] [<variant_csv>]
   provider: anthropic | openai
   prompt_chars: integer (default 120000 ≈ 30K tokens)
   variant_csv: comma-separated subset of V0_h11_post,V1_h2_client,V2_stream_h11,V3_h11_keepalv
```

## Sample prompts

- `sample-30k-prompt.txt` — 120KB deterministic lorem-padded prompt (≈ 30K tokens)
- `sample-50k-sdd-prompt.txt` — review prompt over the real cycle-098 SDD (≈ 50K tokens)

## 2026-05-11 baseline results

All four variants passed against Anthropic at both prompt sizes; the cheval
CLI returned proper structured content for a 50K-token SDD review payload
in 26 seconds. Layer 3 did not reproduce. See `grimoires/loa/known-failures.md`
KF-002 Attempts table.
