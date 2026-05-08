# OpenAI API response fixtures (sprint-bug-143)

Captured raw responses from real OpenAI API calls during cycle-100 sprint-bug-143
investigation of #787 + #789. Used by `tests/unit/model-adapter-responses-api-shapes.bats`
to pin the parsing-side behavior of `model-adapter.sh.legacy`.

| File | Endpoint | Model | Class | Captured |
|------|----------|-------|-------|----------|
| `reasoning.json` | `/v1/responses` | `gpt-5.5-pro` | reasoning + message | 2026-05-08 |
| `codex.json` | `/v1/responses` | `gpt-5.3-codex` | message-only | 2026-05-08 |
| `chat.json` | `/v1/chat/completions` | `gpt-5.5` | chat | 2026-05-08 |

All three were captured with the prompt `"Output exactly: ok"` and `max_output_tokens=50`.

## PII redaction

Captures were redacted via `/tmp/capture-openai-shapes.py`'s `redact()` helper:
- `Authorization`, `api[_-]?key`, `organization`, `x-request-id` keys → `"[REDACTED]"`
- `sk-*` API keys, `org-*` org IDs, `Bearer *` tokens in any string position → tagged replacement

The `id` and `created_at` fields are intentionally PRESERVED — they're opaque
identifiers without secret content and they're what the adapters pass through.

## Why these three shapes

The three correspond to the divergent paths a parsing chain must handle:

1. **`reasoning.json`** — reasoning-class returns TWO output items:
   - `output[0]`: `type: "reasoning"` with empty `summary: []`
   - `output[1]`: `type: "message"` with `content[].type: "output_text"`
   The legacy jq filter must skip the reasoning item and pull text from the
   message item. (Tested: it does. The `*787` root cause was on the *request*
   side — missing `max_output_tokens` starves the visible budget.)

2. **`codex.json`** — non-reasoning `/v1/responses` returns ONE output item of
   `type: "message"`. Same parser path as the second item in reasoning, but
   the codex shape is the canonical baseline.

3. **`chat.json`** — `/v1/chat/completions` returns `choices[0].message.content`
   as a top-level string. The `//` operator in the jq filter chain falls back
   to this when the `.output[]` selector returns nothing.

## Regenerating

```bash
OPENAI_API_KEY=... python3 /tmp/capture-openai-shapes.py
```

Capture script lives at the path above (intentionally not committed; it's a
one-shot capture tool, not a recurring asset).
