"""#1166: transport JSON is not a native structured-output guarantee."""

import json
import subprocess
import sys
from pathlib import Path
from unittest.mock import patch

import pytest
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from loa_cheval.providers.cursor_headless_adapter import CursorHeadlessAdapter
from loa_cheval.routing.capability_gate import check
from loa_cheval.routing.types import ResolvedEntry
from loa_cheval.types import CompletionRequest, ModelConfig, ProviderConfig


@pytest.mark.parametrize("model", ["composer-2.5", "composer-2.5-fast"])
def test_cursor_declarations_reject_native_structured_json_requirement(model):
    config = Path(__file__).resolve().parents[2] / "defaults/model-config.yaml"
    declaration = yaml.safe_load(config.read_text())["providers"]["cursor"]["models"][model]
    entry = ResolvedEntry(
        provider="cursor", model_id=model, adapter_kind="cli",
        capabilities=frozenset(declaration["capabilities"]), auth_type="headless",
    )
    request = CompletionRequest(
        model=model, messages=[{"role": "user", "content": "Return a JSON review."}],
        metadata={"requires_capabilities": ["chat", "structured_json"]},
    )
    assert check(request, entry).missing == ("structured_json",)
    request.metadata = {}
    assert check(request, entry).ok


def test_cursor_json_transport_accepts_unstructured_model_text(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
    adapter = CursorHeadlessAdapter(ProviderConfig(
        name="cursor", type="cursor-headless", endpoint="", auth=None,
        models={"composer-2.5": ModelConfig(context_window=200000)},
    ))
    request = CompletionRequest(
        model="composer-2.5",
        messages=[{"role": "user", "content": 'Return JSON matching {"verdict":"APPROVED"}.'}],
    )
    process = subprocess.CompletedProcess(
        ["cursor-agent"], 0,
        stdout=json.dumps({"type": "result", "is_error": False, "result": "Plain prose; no JSON."}),
        stderr="",
    )
    with patch(
        "loa_cheval.providers.cursor_headless_adapter.run_subprocess_pgkill",
        return_value=process,
    ) as runner:
        result = adapter.complete(request)
    command = runner.call_args.args[0]
    assert command[command.index("--output-format") + 1] == "json"
    assert "--json-schema" not in command and "--output-schema" not in command
    assert result.content == "Plain prose; no JSON."
