"""Test cheval.py exception scoping — sub-issue 1 (issue #675).

Reproduces the UnboundLocalError shadow that masked RetriesExhaustedError
when Anthropic disconnected at 60s for max_tokens > 4096 on large prompts.

Root cause: cheval.py line 389 had a function-local
`from loa_cheval.types import BudgetExceededError` inside the
`except ImportError:` branch (`status == "BLOCK"` path). Python scoping rule:
any local `from X import Y` inside a function makes `Y` a local name throughout
the function. When the inner `except ImportError` path is not taken (the normal
case — retry module IS available), the local `BudgetExceededError` name is never
bound. The outer `except BudgetExceededError as e:` on line 424 then references
the unbound local → UnboundLocalError, masking the real RetriesExhaustedError.

Test must FAIL pre-fix (UnboundLocalError shadows real exception) and PASS
post-fix (line 389 local import removed, module-scope import on line 27 used).
"""

from __future__ import annotations

import io
import json
import sys
import types
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.types import RetriesExhaustedError

# Import cheval AFTER path setup
import cheval  # type: ignore[import-not-found]


def _make_args(tmp_path) -> object:
    """Construct a minimal valid argparse.Namespace for cmd_invoke()."""
    args = types.SimpleNamespace()
    args.agent = "flatline-reviewer"
    args.input = None
    args.prompt = "test prompt"
    args.system = None
    args.model = None
    args.max_tokens = 4096
    args.output_format = "text"
    args.json_errors = True
    args.timeout = 30
    args.include_thinking = False
    args.async_mode = False
    args.poll_id = None
    args.cancel_id = None
    args.dry_run = False
    args.print_config = False
    args.validate_bindings = False
    return args


def test_retries_exhausted_no_unbound_local(tmp_path, capsys, monkeypatch):
    """When invoke_with_retry raises RetriesExhaustedError, the outer except
    must catch it cleanly and emit RETRIES_EXHAUSTED — NOT UnboundLocalError
    on the local BudgetExceededError binding.

    Pre-fix: UnboundLocalError leaks because cheval.py line 389's local import
    creates a function-local binding that's referenced by line 424's outer
    except. PASS post-fix: line 389 removed, module-scope import wins.
    """
    # Mock provider/config resolution to bypass real config loading
    fake_resolved = MagicMock(provider="anthropic", model_id="claude-opus-4-7")
    fake_binding = MagicMock(temperature=0.7)
    fake_provider_cfg = MagicMock()
    fake_adapter = MagicMock()

    fake_config = {
        "providers": {
            "anthropic": {
                "type": "anthropic",
                "endpoint": "https://api.anthropic.com/v1/messages",
                "auth": "dummy",
                "models": {
                    "claude-opus-4-7": {
                        "capabilities": ["chat"],
                        "context_window": 200000,
                    },
                },
            },
        },
        "feature_flags": {"metering": False},  # disable budget enforcer to isolate scope bug
    }

    with patch.object(cheval, "load_config", return_value=(fake_config, {})), \
         patch.object(cheval, "resolve_execution", return_value=(fake_binding, fake_resolved)), \
         patch.object(cheval, "_build_provider_config", return_value=fake_provider_cfg), \
         patch.object(cheval, "get_adapter", return_value=fake_adapter), \
         patch("loa_cheval.providers.retry.invoke_with_retry") as mock_retry:

        # Simulate the exact failure mode from issue #675:
        # Anthropic disconnects at 60s, all 4 retries exhausted.
        mock_retry.side_effect = RetriesExhaustedError(
            total_attempts=4,
            last_error="Server disconnected without sending a response",
        )

        args = _make_args(tmp_path)
        exit_code = cheval.cmd_invoke(args)

    captured = capsys.readouterr()

    # Must surface the real exception, not the shadowed one.
    assert exit_code == cheval.EXIT_CODES["RETRIES_EXHAUSTED"], (
        f"Expected exit {cheval.EXIT_CODES['RETRIES_EXHAUSTED']} (RETRIES_EXHAUSTED), "
        f"got {exit_code}. stderr was:\n{captured.err}"
    )

    # Stderr must NOT contain the shadowing UnboundLocalError signature
    assert "UnboundLocalError" not in captured.err, (
        f"UnboundLocalError leaked to stderr — line 389 local import is shadowing "
        f"the outer except. stderr:\n{captured.err}"
    )
    assert "BudgetExceededError" not in captured.err or \
           "referenced before assignment" not in captured.err, (
        f"UnboundLocalError on BudgetExceededError leaked to stderr — function-local "
        f"import at cheval.py:389 must be removed. stderr:\n{captured.err}"
    )

    # Stderr must contain the structured RETRIES_EXHAUSTED error JSON
    # Find the JSON line in stderr
    json_line = None
    for line in captured.err.splitlines():
        line = line.strip()
        if line.startswith("{") and "RETRIES_EXHAUSTED" in line:
            json_line = line
            break

    assert json_line is not None, (
        f"Expected RETRIES_EXHAUSTED structured error JSON on stderr, none found. "
        f"stderr:\n{captured.err}"
    )

    payload = json.loads(json_line)
    assert payload.get("code") == "RETRIES_EXHAUSTED", payload
    assert payload.get("error") is True, payload
