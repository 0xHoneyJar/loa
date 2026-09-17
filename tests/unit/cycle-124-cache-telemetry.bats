#!/usr/bin/env bats
# =============================================================================
# tests/unit/cycle-124-cache-telemetry.bats
#
# cycle-124 Sprint 1 Task 1.6 (FR-4 / SDD §3.3): prompt-cache telemetry is
# visible end to end without a credential —
#   - a streaming SSE fixture whose message_start carries
#     cache_read_input_tokens / cache_creation_input_tokens lands on Usage;
#   - the non-streaming body does the same;
#   - the request body carries exactly one cache_control breakpoint (persona)
#     and the adaptive thinking block for a flagged model;
#   - LOA_CHEVAL_LEGACY_WIRE=1 restores the string system prompt and no thinking;
#   - the MODELINV payload schema accepts the emitted cache fields.
# The pytest twins (test_anthropic_cache_control.py, test_anthropic_thinking.py,
# test_cache_read_pricing.py) are the fine-grained coverage; this suite is the
# CI-visible bats surface the sprint plan names.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    ADAPTERS="$PROJECT_ROOT/.claude/adapters"
    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="$(command -v python3)"
    fi
    export LOA_MODELINV_LOG_PATH="$BATS_TEST_TMPDIR/model-invoke.jsonl"
    export LOA_COST_LEDGER_PATH="$BATS_TEST_TMPDIR/cost-ledger.jsonl"
    export LOA_CHEVAL_DISABLE_STREAMING LOA_CHEVAL_LEGACY_WIRE
    unset LOA_CHEVAL_DISABLE_STREAMING LOA_CHEVAL_LEGACY_WIRE
}

_py() {  # run a python snippet with the adapters package importable
    run "$PYTHON_BIN" -c "
import sys; sys.path.insert(0, '$ADAPTERS')
$1
"
}

@test "c124-1.6-1: streaming message_start cache counts land on Usage (thinking block first)" {
    _py '
import json
from contextlib import contextmanager
from unittest.mock import MagicMock, patch
from loa_cheval.providers.anthropic_adapter import AnthropicAdapter
from loa_cheval.types import CompletionRequest, ModelConfig, ProviderConfig
def ev(n, d): return f"event: {n}\ndata: {json.dumps(d)}\n\n".encode()
blob = (ev("message_start", {"type":"message_start","message":{"id":"m","model":"claude-opus-5","role":"assistant","content":[],"usage":{"input_tokens":50,"output_tokens":0,"cache_read_input_tokens":4321,"cache_creation_input_tokens":12}}})
      + ev("content_block_start", {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}})
      + ev("content_block_delta", {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"hmm"}})
      + ev("content_block_stop", {"type":"content_block_stop","index":0})
      + ev("content_block_start", {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}})
      + ev("content_block_delta", {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"answer"}})
      + ev("content_block_stop", {"type":"content_block_stop","index":1})
      + ev("message_delta", {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":7}})
      + ev("message_stop", {"type":"message_stop"}))
resp = MagicMock(); resp.status_code = 200; resp.http_version = "HTTP/2"; resp.iter_bytes = MagicMock(return_value=iter([blob]))
@contextmanager
def fake(*a, **k):
    yield resp
cfg = ProviderConfig(name="anthropic", type="anthropic", endpoint="https://api.anthropic.com/v1", auth="sk-ant-test",
                     models={"claude-opus-5": ModelConfig(capabilities=["chat"], context_window=1000000, params={"temperature_supported": False, "thinking_adaptive": True})})
with patch("loa_cheval.providers.anthropic_adapter.http_post_stream", fake):
    r = AnthropicAdapter(cfg).complete(CompletionRequest(messages=[{"role":"user","content":"x"}], model="claude-opus-5", max_tokens=64))
assert r.content == "answer", r.content
assert r.thinking == "hmm", r.thinking
assert r.usage.cache_read_input_tokens == 4321 and r.usage.cache_creation_input_tokens == 12, r.usage
print("OK")
'
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    [[ "$output" == *"OK"* ]]
}

@test "c124-1.6-2: non-streaming usage cache counts land on Usage" {
    LOA_CHEVAL_DISABLE_STREAMING=1 _py '
from unittest.mock import patch
from loa_cheval.providers.anthropic_adapter import AnthropicAdapter
from loa_cheval.types import CompletionRequest, ModelConfig, ProviderConfig
cfg = ProviderConfig(name="anthropic", type="anthropic", endpoint="https://api.anthropic.com/v1", auth="sk-ant-test",
                     models={"claude-opus-5": ModelConfig(capabilities=["chat"], context_window=1000000)})
body = {"id":"m","model":"claude-opus-5","role":"assistant","content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn",
        "usage":{"input_tokens":5,"output_tokens":2,"cache_read_input_tokens":999,"cache_creation_input_tokens":3}}
with patch("loa_cheval.providers.anthropic_adapter.http_post", return_value=(200, body)):
    r = AnthropicAdapter(cfg).complete(CompletionRequest(messages=[{"role":"user","content":"x"}], model="claude-opus-5", max_tokens=64))
assert (r.usage.cache_read_input_tokens, r.usage.cache_creation_input_tokens) == (999, 3), r.usage
print("OK")
'
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    [[ "$output" == *"OK"* ]]
}

@test "c124-1.6-3: request body carries one cache_control breakpoint and the adaptive thinking block" {
    LOA_CHEVAL_DISABLE_STREAMING=1 _py '
import json
from loa_cheval.providers.anthropic_adapter import AnthropicAdapter
from loa_cheval.types import CompletionRequest, ModelConfig, ProviderConfig
cfg = ProviderConfig(name="anthropic", type="anthropic", endpoint="https://api.anthropic.com/v1", auth="sk-ant-test",
                     models={"claude-opus-5": ModelConfig(capabilities=["chat"], context_window=1000000, params={"temperature_supported": False, "thinking_adaptive": True})})
a = AnthropicAdapter(cfg); cap = {}
a._complete_nonstreaming = lambda url, headers, body: cap.setdefault("body", body)
a.complete(CompletionRequest(messages=[{"role":"system","content":"persona","cache_control":{"type":"ephemeral"}},{"role":"system","content":"---\n\ncontext"},{"role":"user","content":"x"}], model="claude-opus-5", max_tokens=64))
b = cap["body"]
assert b["thinking"] == {"type": "adaptive"}, b
assert isinstance(b["system"], list) and sum(1 for blk in b["system"] if "cache_control" in blk) == 1, b["system"]
assert "temperature" not in b and "budget_tokens" not in json.dumps(b)
print("OK")
'
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    [[ "$output" == *"OK"* ]]
}

@test "c124-1.6-4: LOA_CHEVAL_LEGACY_WIRE=1 ⇒ string system prompt, no thinking (pre-cycle body)" {
    LOA_CHEVAL_LEGACY_WIRE=1 LOA_CHEVAL_DISABLE_STREAMING=1 _py '
from loa_cheval.providers.anthropic_adapter import AnthropicAdapter
from loa_cheval.types import CompletionRequest, ModelConfig, ProviderConfig
cfg = ProviderConfig(name="anthropic", type="anthropic", endpoint="https://api.anthropic.com/v1", auth="sk-ant-test",
                     models={"claude-opus-5": ModelConfig(capabilities=["chat"], context_window=1000000, params={"temperature_supported": False, "thinking_adaptive": True})})
a = AnthropicAdapter(cfg); cap = {}
a._complete_nonstreaming = lambda url, headers, body: cap.setdefault("body", body)
a.complete(CompletionRequest(messages=[{"role":"system","content":"persona","cache_control":{"type":"ephemeral"}},{"role":"system","content":"---\n\ncontext"},{"role":"user","content":"x"}], model="claude-opus-5", max_tokens=64))
b = cap["body"]
assert b == {"model": "claude-opus-5", "messages": [{"role": "user", "content": "x"}], "max_tokens": 64, "system": "persona\n\n---\n\ncontext"}, b
print("OK")
'
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    [[ "$output" == *"OK"* ]]
}

@test "c124-1.6-5: emitted MODELINV payload with cache fields validates against the payload schema" {
    "$PYTHON_BIN" -c "import jsonschema" 2>/dev/null || skip "jsonschema not available"
    _py '
import json
from unittest.mock import patch
import jsonschema
from loa_cheval.audit import modelinv
cap = {}
with patch("loa_cheval.audit_envelope.audit_emit", lambda level, event, payload, *a, **k: cap.update(payload)), \
     patch("loa_cheval.audit.modelinv.redact_payload_strings", side_effect=lambda x: x), \
     patch("loa_cheval.audit.modelinv.assert_no_secret_shapes_remain"):
    modelinv.emit_model_invoke_complete(models_requested=["anthropic:claude-opus-5"], models_succeeded=["anthropic:claude-opus-5"],
        models_failed=[], operator_visible_warn=False, tokens_input=10, tokens_output=5,
        tokens_cache_read=1234, tokens_cache_creation=56, effort="xhigh",
        pricing_snapshot={"input_per_mtok": 5000000, "output_per_mtok": 25000000, "pricing_mode": "token", "cache_read_per_mtok": 500000, "cache_write_per_mtok": 6250000})
assert cap["tokens_cache_read"] == 1234 and cap["tokens_cache_creation"] == 56 and cap["effort"] == "xhigh", cap
schema = json.load(open("'"$PROJECT_ROOT"'/.claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json"))
from referencing import Registry, Resource
reg = Registry()
me = "'"$PROJECT_ROOT"'/.claude/data/trajectory-schemas/model-error.schema.json"
import os
if os.path.isfile(me):
    reg = reg.with_resource(uri="loa://schemas/model-error/v1.0.0", resource=Resource.from_contents(json.load(open(me))))
jsonschema.validators.validator_for(schema)(schema, registry=reg).validate(cap)
print("OK")
'
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    [[ "$output" == *"OK"* ]]
}
