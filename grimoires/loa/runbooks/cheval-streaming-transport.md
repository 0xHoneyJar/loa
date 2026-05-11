# Cheval Streaming Transport Runbook

Operator-visible documentation for the Sprint 4A streaming transport in
cheval (cycle-102, AC-4.5e closure for KF-002 layer 3 / Loa #774).

## What changed

cheval's three production provider adapters — Anthropic, OpenAI
(both `/chat/completions` and `/v1/responses`), and Google Gemini — now
**stream provider responses by default**. The legacy non-streaming
`http_post()` path is preserved behind an operator kill switch.

| Path | Mechanism |
|------|-----------|
| Streaming (default) | `http_post_stream()` in `base.py` + per-provider SSE parser; server emits the first token within seconds of accepting the request |
| Legacy non-streaming | `http_post()` blocks until the entire response body is buffered server-side, then returns it as one JSON document |

## Why this exists

The legacy non-streaming path was load-bearing in the
[KF-002 layer 3](../known-failures.md) failure mode: at >27K input
tokens (OpenAI) / >40K input tokens (Anthropic), the server took >60
seconds to produce the first byte of the response. Intermediaries
(Cloudflare edge, AWS ALBs) closed the idle TCP connection at the 60s
mark, surfacing as `httpx.RemoteProtocolError("Server disconnected
without sending a response")` and propagating to
`RetriesExhaustedError`.

Streaming **eliminates this failure class by construction**: the server
begins emitting bytes immediately, so the TCP connection is never idle
from the intermediary's point of view.

## How to verify your installation is on the streaming path

```bash
# Quick: any cheval call's audit envelope will carry `streaming: true`
# on the streaming default and `streaming: false` when the kill switch
# is set.
.claude/scripts/model-invoke \
  --agent flatline-reviewer \
  --model "claude-opus-4.7" \
  --input /tmp/some-prompt.txt \
  --max-tokens 4096 \
  --output-format json

# Check the most recent MODELINV envelope:
tail -1 .run/cheval-modelinv.jsonl | jq '.payload.streaming'
# → true   (Sprint 4A default)
```

## The kill switch

Setting `LOA_CHEVAL_DISABLE_STREAMING=1` reverts a single call (or an
entire process tree, depending on scope) back to the legacy
non-streaming path.

```bash
# One-shot operator backstop
LOA_CHEVAL_DISABLE_STREAMING=1 .claude/scripts/model-invoke \
  --agent flatline-reviewer \
  --model "claude-opus-4.7" \
  --input prompt.txt \
  --max-tokens 4096
```

**Truthy values that activate the kill switch**: `1`, `true`, `yes`
(case-insensitive). Anything else (including unset, empty, `0`,
`false`, `no`) leaves streaming active.

**Caveat**: when the kill switch is set, the per-model
`max_input_tokens` gate in `.claude/defaults/model-config.yaml` still
reflects the Sprint 4A raised defaults (200K for OpenAI, 180K for
Anthropic). These values are NOT safe on the legacy path, which still
hits the 24K / 27K / 40K walls. If you flip the kill switch, override
the gate in your own config:

```yaml
# .loa.config.yaml override (when streaming is disabled)
providers:
  openai:
    models:
      gpt-5.5-pro:
        max_input_tokens: 24000   # legacy-safe value
  anthropic:
    models:
      claude-opus-4-7:
        max_input_tokens: 36000   # legacy-safe value
```

## Operator overrides — full surface

| Control | Scope | Effect |
|---------|-------|--------|
| `LOA_CHEVAL_DISABLE_STREAMING=1` | Process | Routes ALL adapter calls through the legacy non-streaming path. The streaming code is never invoked. |
| `LOA_CHEVAL_DISABLE_INPUT_GATE=1` | Process | Disables the per-model `max_input_tokens` gate entirely (both streaming + legacy paths). |
| `--max-input-tokens 0` | Per-call | Disables the gate for that one invocation. |
| `--max-input-tokens N` | Per-call | Overrides the per-model gate value for that one invocation. |
| `LOA_CHEVAL_FORCE_HTTP2_UNAVAILABLE=1` | Test only | Forces HTTP/1.1 even when `h2` is installed. Gated behind `PYTEST_CURRENT_TEST` — production paths ignore. |

## Dependencies

Streaming HTTP/2 requires the `h2` Python package. The
`pyproject.toml` `full` extra now declares `httpx[http2]` which pulls in
`h2` + `hpack` automatically:

```bash
pip install '.claude/adapters[full]'
```

When `h2` is missing at runtime, streaming **still works** — it
transparently falls back to HTTP/1.1 with a stderr WARN. Both protocols
pass the regression pin tests. HTTP/2 is preferred for concurrency
robustness but not for correctness.

## Per-provider behavior detail

### Anthropic Messages API

- Streaming URL: `POST {endpoint}/messages` with `body["stream"] = true`
- Response: SSE events (7 types): `message_start`, `content_block_start`,
  `content_block_delta`, `content_block_stop`, `message_delta`,
  `message_stop`, `ping`
- 3 block types handled: `text`, `thinking` (extended-thinking
  blocks), `tool_use` (assembled from `input_json_delta` events)
- Parser: `loa_cheval/providers/anthropic_streaming.py`

### OpenAI `/v1/chat/completions`

- Streaming URL: `POST {endpoint}/chat/completions` with
  `body["stream"] = true` + `body["stream_options"] =
  {"include_usage": true}`
- Response: SSE chunks (one `data: {...}` line each) terminated by
  `data: [DONE]`
- Tool-call argument assembly: index-keyed accumulator for parallel
  tool calls
- Parser: `loa_cheval/providers/openai_streaming.py::parse_openai_chat_stream`

### OpenAI `/v1/responses`

- Streaming URL: `POST {endpoint}/responses` with `body["stream"] = true`
- Response: typed event stream (`response.created`,
  `response.output_item.added`, `response.output_text.delta`,
  `response.function_call_arguments.delta`,
  `response.reasoning_summary_text.delta`, `response.refusal.delta`,
  `response.completed`, `response.failed`, `response.incomplete`)
- Parser produces the same six-shape output as the non-streaming
  `_parse_responses_response` (PRD §3.1, SDD §5.4)
- Sprint 1F `text.format=text` request-body parameter preserved
  (orthogonal to streaming — still forces a visible text item even
  when reasoning exhausts max_output_tokens)
- Parser: `loa_cheval/providers/openai_streaming.py::parse_openai_responses_stream`

### Google Gemini

- Streaming URL: `POST {endpoint}/models/{model}:streamGenerateContent?alt=sse`
- Response: SSE events; each `data:` line is a partial
  `GenerateContentResponse` JSON fragment. The full response is the
  left-fold of all fragments.
- Parts with `thought: true` route to `CompletionResult.thinking`;
  others to `.content` (parity with non-streaming `_parse_response`).
- Safety / Recitation blocks raise `InvalidInputError` (translated
  from `ValueError` by the adapter).
- Parser: `loa_cheval/providers/google_streaming.py::parse_google_stream`

## Regression pins

Anti-regression test surface (Sprint 4A T4A.6):

| Test file | Coverage |
|-----------|----------|
| `tests/test_streaming_transport.py` | 12 cases — R1 transport pin (5-chunk mock), R2 60s-wall regression (non-streaming raises, streaming survives), R3 h2-missing fallback, exception-class parametrized matrix |
| `tests/test_anthropic_streaming.py` | 11 cases — all 6 SSE event types, UTF-8 multibyte chunking, tool-use reconstruction, error event |
| `tests/test_openai_streaming.py` | 11 cases — both endpoint families, parallel tool calls, refusal, truncation, response.failed |
| `tests/test_google_streaming.py` | 8 cases — multi-fragment text, thinking-part segregation, safety/recitation blocks, missing-usage fallback |
| `tests/test_modelinv_streaming_field.py` | 15 cases — env-derivation, schema constraint, explicit-override semantics |

Total: 57 new tests for the Sprint 4A surface. All 887 cheval pytest
cases pass after the sprint (0 net-new failures vs main).

## What happens if KF-002 layer 3 returns

The streaming path closes the failure class by construction. If the
operator observes a new `httpx.RemoteProtocolError` or
`ConnectionLostError` against a cheval-modeled provider:

1. **Don't** flip the kill switch as a first response — that would
   surface the failure mode the streaming fix was designed to prevent.
2. **Do** check whether `body["stream"] = true` is actually being
   sent — confirm via tcpdump or by inspecting the audit envelope's
   `streaming` field.
3. **Do** check whether `h2` is importable in the cheval Python
   environment — `LOA_CHEVAL_FORCE_HTTP2_UNAVAILABLE` aside, missing
   `h2` is the only path to HTTP/1.1 in production, and HTTP/1.1
   streaming has been observed to be slightly less robust under
   high-concurrency parallel-dispatch scenarios.
4. **Do** open a KF-002 Attempts row with the observed
   `transport_class` (from `ConnectionLostError.transport_class`),
   payload size, and whether `streaming: true` was set in the audit
   payload at failure time.
5. **Don't** lower the input-size gate as a first response — the gate's
   Sprint 4A values are validated against the streaming path. If you
   genuinely need a lower gate (e.g., to constrain cost), do it via
   `.loa.config.yaml` override, not by modifying the shipped defaults.

## Related files

- `.claude/adapters/loa_cheval/providers/base.py` —
  `http_post_stream()` + `StreamingResponse` + h2 detection
- `.claude/adapters/loa_cheval/providers/anthropic_streaming.py`
- `.claude/adapters/loa_cheval/providers/openai_streaming.py`
- `.claude/adapters/loa_cheval/providers/google_streaming.py`
- `.claude/adapters/loa_cheval/audit/modelinv.py` — `streaming` field
- `.claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json` v1.1
- `.claude/defaults/model-config.yaml` — raised `max_input_tokens`
- `grimoires/loa/known-failures.md` — KF-002 status, 2026-05-11
  Resolution note
- `grimoires/loa/diagnostics/cheval-http-repro/` — session 10
  empirical-reproduction harness

## Origin

- Diagnosis: session 10 (2026-05-11) — empirical non-reproduction of
  KF-002 layer 3 documented in known-failures.md
- Plan: cycle-102 sprint.md "Sprint 4A — Cheval Streaming Transport"
- Implementation: 7 commits on `feature/feat/cycle-102-sprint-4A`
