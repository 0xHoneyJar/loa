"""bd-q0o: argv-prompt headless adapters must WALK (not crash) on un-execable argv.

Only gemini-headless + claude-headless pass the UNTRUSTED prompt on ARGV (`-p <prompt>`),
so only they are reachable by an embedded-NUL ValueError or an ARG_MAX OSError from a
crafted/oversized diff. (grok uses --prompt-file; codex + cursor use stdin via input= —
their prompt never touches argv. Verified: a NUL in stdin does NOT raise, a NUL in argv does.)

Found by the Gemini council voice (agy) reviewing the agy adapter on loa#1109 — a bug codex+
cursor missed. The agy adapter is fixed there; this covers the two vulnerable siblings.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.providers import get_adapter
from loa_cheval.types import (
    CompletionRequest,
    ModelConfig,
    ProviderConfig,
    ProviderUnavailableError,
)

# (module-seam, provider-type, model-id, extra) — ARGV-prompt adapters only.
_ARGV_ADAPTERS = [
    ("gemini_headless_adapter", "gemini-headless", "gemini-3-pro", {"cli_model": "gemini-3.1-pro-preview"}),
    ("claude_headless_adapter", "claude-headless", "sonnet", {"cli_model": "sonnet"}),
]


def _adapter(ptype, model_id, extra):
    cfg = ProviderConfig(
        name=ptype, type=ptype, endpoint="", auth=None,
        models={model_id: ModelConfig(context_window=200000, extra=extra)},
    )
    return get_adapter(cfg)


def _req(model_id):
    return CompletionRequest(messages=[{"role": "user", "content": "x"}], model=model_id, max_tokens=50)


@pytest.mark.parametrize("mod,ptype,model_id,extra", _ARGV_ADAPTERS)
def test_nul_byte_prompt_walks_not_crashes(mod, ptype, model_id, extra):
    # embedded NUL in an argv arg → subprocess raises ValueError (not OSError) → must WALK.
    with patch(f"loa_cheval.providers.{mod}.shutil.which", return_value="/usr/bin/x"), \
         patch(f"loa_cheval.providers.{mod}.run_subprocess_pgkill",
               side_effect=ValueError("embedded null byte")):
        with pytest.raises(ProviderUnavailableError):
            _adapter(ptype, model_id, extra).complete(_req(model_id))


@pytest.mark.parametrize("mod,ptype,model_id,extra", _ARGV_ADAPTERS)
def test_argmax_oserror_walks_not_crashes(mod, ptype, model_id, extra):
    # oversized prompt on argv → ARG_MAX/E2BIG OSError → must WALK, not crash the chain.
    with patch(f"loa_cheval.providers.{mod}.shutil.which", return_value="/usr/bin/x"), \
         patch(f"loa_cheval.providers.{mod}.run_subprocess_pgkill",
               side_effect=OSError(7, "Argument list too long")):
        with pytest.raises(ProviderUnavailableError):
            _adapter(ptype, model_id, extra).complete(_req(model_id))
