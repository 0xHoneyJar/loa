"""cycle-124 Sprint 1 Task 1.8 — live floor check scaffold (SDD §6 "Live scaffolds").

Gated: every test skips unless LOA_RUN_LIVE_TESTS=1 AND ANTHROPIC_API_KEY are
set. Wired into .github/workflows/live-floor-check.yml (HAS_KEY env gate,
retries ×2 per assertion, ≤ $5 per run via LOA_LIVE_BUDGET_USD, artifact
upload). The recorded pass is the cycle-124 draft PR's named merge
precondition; until then every catalog value stays `reference` in
grimoires/loa/reports/2026-09-17-cycle-124-catalog-evidence.md.

Operator command (from the repo root, ~$1–2 per run):

    LOA_RUN_LIVE_TESTS=1 ANTHROPIC_API_KEY=sk-ant-... \\
      python3 -m pytest tests/replay/test_cycle124_live_floor.py -rs -q

Red-result decision rule: a wire rejection (HTTP 400) on the thinking or
cache shape is a catalog/adapter defect — fix before merge; a missing model
id (404) on `claude-opus-5` / `claude-fable-5-1` means the account does not
serve the id yet — the chain-walk covers runtime, record `absent` in the
evidence file and keep the PR draft; `cache_read == 0` on the second call
with a ≥ 4096-token prefix is a defect; with a shorter prefix it is the
documented minimum-prefix rule, not a failure.

Assertions use stdlib urllib only (no SDK) so the scaffold runs on a bare
CI runner; each is retried twice on transport errors.
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / ".claude" / "adapters"))

API = "https://api.anthropic.com/v1"
LIVE = os.environ.get("LOA_RUN_LIVE_TESTS") == "1" and bool(os.environ.get("ANTHROPIC_API_KEY"))
SKIP_REASON = "live floor check: set LOA_RUN_LIVE_TESTS=1 and ANTHROPIC_API_KEY"
BUDGET_USD = float(os.environ.get("LOA_LIVE_BUDGET_USD", "5"))

# Reference pricing (micro-USD per MTok) used only for the in-run budget cap.
_PRICE = {
    "claude-opus-5": (5_000_000, 25_000_000),
    "claude-sonnet-5": (2_000_000, 10_000_000),
    "claude-fable-5-1": (10_000_000, 50_000_000),
    "claude-haiku-4-5-20251001": (1_000_000, 5_000_000),
    "claude-opus-4-8": (5_000_000, 25_000_000),
}
_spent_micro = 0

# thinking: explicit adaptive is required on 4.8 (off otherwise) and harmless
# default-on for Opus 5 / Sonnet 5; Fable accepts adaptive-or-omitted only.
THINKING_MODELS = ["claude-opus-5", "claude-sonnet-5", "claude-fable-5-1", "claude-haiku-4-5-20251001"]
EXPECT_THINKING_PARAM_ACCEPTED = {"claude-opus-5", "claude-sonnet-5", "claude-fable-5-1"}

pytestmark = pytest.mark.skipif(not LIVE, reason=SKIP_REASON)


def _charge(model: str, usage: dict) -> None:
    global _spent_micro
    inp, out = _PRICE.get(model, (10_000_000, 50_000_000))
    _spent_micro += usage.get("input_tokens", 0) * inp // 1_000_000
    _spent_micro += usage.get("output_tokens", 0) * out // 1_000_000
    _spent_micro += usage.get("cache_creation_input_tokens", 0) * inp * 5 // 4 // 1_000_000
    _spent_micro += usage.get("cache_read_input_tokens", 0) * inp // 10 // 1_000_000
    if _spent_micro > BUDGET_USD * 1_000_000:
        pytest.fail(f"live budget exceeded: {_spent_micro / 1e6:.2f} USD > {BUDGET_USD} USD")


def _request(method: str, path: str, body: dict | None = None, retries: int = 2) -> tuple[int, dict]:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        f"{API}{path}", data=data, method=method,
        headers={"x-api-key": os.environ["ANTHROPIC_API_KEY"], "anthropic-version": "2023-06-01",
                 "content-type": "application/json"},
    )
    last: Exception | None = None
    for attempt in range(retries + 1):
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                return resp.status, json.loads(resp.read().decode())
        except urllib.error.HTTPError as e:
            payload = e.read().decode(errors="replace")
            try:
                return e.code, json.loads(payload)
            except json.JSONDecodeError:
                return e.code, {"error": {"message": payload[:500]}}
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:  # transport — retry
            last = e
            time.sleep(2 * (attempt + 1))
    raise AssertionError(f"transport failed after {retries + 1} attempts: {last}")


def _messages_body(model: str, system=None, thinking: bool = True, max_tokens: int = 256) -> dict:
    body = {"model": model, "max_tokens": max_tokens,
            "messages": [{"role": "user", "content": "Reply with the single word: ready."}]}
    if system is not None:
        body["system"] = system
    if thinking:
        body["thinking"] = {"type": "adaptive"}
    return body


@pytest.fixture(scope="module")
def served_models() -> set:
    status, payload = _request("GET", "/models?limit=200")
    assert status == 200, payload
    return {m["id"] for m in payload.get("data", [])}


def test_catalog_ids_are_served(served_models):
    """GET /v1/models lists every Anthropic HTTP id the catalog names (AC-3.x)."""
    import yaml
    catalog = yaml.safe_load((REPO_ROOT / ".claude" / "defaults" / "model-config.yaml").read_text())
    wanted = [k for k, v in catalog["providers"]["anthropic"]["models"].items() if v.get("auth_type") == "http_api"]
    missing = sorted(m for m in wanted if m not in served_models)
    # A newly named id the account does not serve yet is chain-walkable at
    # runtime (HTTP 404 ⇒ ProviderUnavailableError); record it, do not hide it.
    assert not missing, f"catalog ids not served by this account: {missing}"


@pytest.mark.parametrize("model", THINKING_MODELS)
def test_thinking_shape_accepted(model, served_models):
    """AC-1.3: the adapter's thinking shape is accepted on the wire (no 400)."""
    if model not in served_models:
        pytest.skip(f"{model} not served by this account")
    status, payload = _request("POST", "/messages", _messages_body(model, thinking=True))
    if model in EXPECT_THINKING_PARAM_ACCEPTED:
        assert status == 200, payload
    else:
        # Haiku 4.5 predates adaptive thinking: a 400 here is the documented
        # reason the catalog does not flag it; 200 is also fine.
        assert status in (200, 400), payload
    if status == 200:
        _charge(model, payload.get("usage", {}))
        blocks = payload.get("content", [])
        kinds = [b.get("type") for b in blocks]
        assert "text" in kinds, kinds
        if "thinking" in kinds:
            assert kinds.index("thinking") < kinds.index("text"), "thinking block must precede text"


def test_second_identical_call_reads_the_cache(served_models, tmp_path, monkeypatch):
    """AC-4.3: cache_read_input_tokens > 0 on the second identical BB-voice call.

    The body is built by the PRODUCTION path, not by hand: Bridgebuilder
    dispatches `--agent reviewing-code` (no persona.md) with its stable prefix
    (INJECTION_HARDENING + .claude/data/bridgebuilder-persona.md) as the
    --system file, so `cheval._persona_messages` must mark that whole payload
    and `AnthropicAdapter._transform_messages` must emit exactly one breakpoint
    (review round-1 high #1 — the hand-built body could not observe the defect)."""
    import cheval
    from loa_cheval.providers.anthropic_adapter import _transform_messages

    model = "claude-opus-5" if "claude-opus-5" in served_models else "claude-opus-4-8"
    assert not (REPO_ROOT / ".claude" / "skills" / "reviewing-code" / "persona.md").exists()
    prefix = "SYSTEM SECURITY NOTICE\n\n" + (REPO_ROOT / ".claude" / "data" / "bridgebuilder-persona.md").read_text()
    # Pad to ≥ 4096 tokens so the minimum-prefix rule holds on every model.
    while len(prefix) < 4096 * 4:
        prefix += "\n\nContext padding paragraph for the live floor check. " * 8
    system_file = tmp_path / "bb-system.md"
    system_file.write_text(prefix)
    monkeypatch.chdir(REPO_ROOT)  # persona lookup is CWD-relative, as in production
    messages = cheval._persona_messages("reviewing-code", str(system_file))
    system, _ = _transform_messages(messages + [{"role": "user", "content": "Reply with the single word: ready."}])
    assert isinstance(system, list) and sum(1 for b in system if "cache_control" in b) == 1, system
    first_status, first = _request("POST", "/messages", _messages_body(model, system=system, max_tokens=64))
    assert first_status == 200, first
    _charge(model, first.get("usage", {}))
    second_status, second = _request("POST", "/messages", _messages_body(model, system=system, max_tokens=64))
    assert second_status == 200, second
    _charge(model, second.get("usage", {}))
    usage = second.get("usage", {})
    assert usage.get("cache_read_input_tokens", 0) > 0, usage


def test_schema_enforced_response_is_strict_json(served_models):
    """AC-7.x: one schema-enforced call returns strict JSON matching the schema
    (the same `output_config.format` shape the adapter emits on
    `structured_json` entries)."""
    model = "claude-opus-5" if "claude-opus-5" in served_models else "claude-opus-4-8"
    # The REAL artifact the dissent sends — nullable `anyOf` fields, enums,
    # closed objects — so a live pass proves the authored subset, not a toy.
    schema = json.loads((REPO_ROOT / ".claude" / "schemas" / "wire" / "dissent-review.wire.json").read_text())
    body = _messages_body(model, max_tokens=400)
    body["messages"] = [{"role": "user", "content": (
        "Review this diff and report exactly one ADVISORY finding in category other, anchored to x.sh:f, "
        "scope diff, with a one-sentence description and failure_mode:\n+ echo hi")}]
    body["output_config"] = {"format": {"type": "json_schema", "schema": schema}}
    status, payload = _request("POST", "/messages", body)
    assert status == 200, payload
    _charge(model, payload.get("usage", {}))
    text = "".join(b.get("text", "") for b in payload.get("content", []) if b.get("type") == "text")
    obj = json.loads(text)
    assert set(obj) == {"findings"} and isinstance(obj["findings"], list), obj
    for finding in obj["findings"]:
        assert set(finding) == set(schema["properties"]["findings"]["items"]["properties"]), finding
        assert finding["severity"] in ("BLOCKING", "ADVISORY")


def test_ceiling_probe_writes_evidence(tmp_path, served_models):
    """tools/ceiling-probe-live.py flips the evidence file's ceiling row from reference to probed."""
    import subprocess
    model = "claude-opus-5" if "claude-opus-5" in served_models else "claude-opus-4-8"
    out = tmp_path / "probe.json"
    proc = subprocess.run(
        [sys.executable, str(REPO_ROOT / "tools" / "ceiling-probe-live.py"), "--model", model,
         "--max-tokens-probe", "200000", "--output", str(out), "--budget-usd", "1.5"],
        capture_output=True, text=True, timeout=1200,
    )
    assert proc.returncode == 0, proc.stderr
    result = json.loads(out.read_text())
    assert result["model"] == model and result["source"] == "empirical_probe"
    assert result["partial"] is False, "budget cap stopped the bisection — raise --budget-usd; a partial record is not evidence"
    assert result["largest_ok_input_tokens"] >= 100_000, result
