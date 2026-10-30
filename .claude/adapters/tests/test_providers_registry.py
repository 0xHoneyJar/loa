"""Providers registry contract (cycle-138 FR-15, bd-0h7kq; SDD 1.5 § 5.9).

- ``cli_adapter_types()`` is derived from the static ``_AUTH_KIND`` table, so it
  imports no adapter module (before FR-15 it built the full registry and imported
  nine adapter modules to read each class's ``auth_type``).
- ``_AUTH_KIND`` agrees with every registered adapter class's declared ``auth_type``
  (``headless`` <=> ``cli``): the attribute stays the semantic (BB #966 round 2), so
  a renamed or new adapter cannot silently diverge from the table.
- Parity pins: the registry's contents and key order, and the exact CLI type set.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

_ADAPTERS_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_ADAPTERS_DIR))

from loa_cheval import providers  # noqa: E402

_EXPECTED_TYPES = [
    "openai", "anthropic", "openai_compat", "google", "bedrock",
    "codex-headless", "gemini-headless", "claude-headless", "cursor-headless", "grok-headless",
]
_EXPECTED_CLI = frozenset({
    "codex-headless", "gemini-headless", "claude-headless", "cursor-headless", "grok-headless",
})

# Runs in a fresh interpreter so no earlier test's cached registry or class can mask
# an import: every loa_cheval.providers.*_adapter module is evicted, then the set of
# adapter modules in sys.modules must be the same after cli_adapter_types() as before.
_PROBE = r"""
import sys
from loa_cheval.providers import cli_adapter_types
def adapters():
    return sorted(k for k in sys.modules
                  if k.startswith("loa_cheval.providers.") and k.endswith("_adapter"))
for k in adapters():
    del sys.modules[k]
before = adapters()
types = cli_adapter_types()
after = adapters()
assert after == before, "cli_adapter_types() imported adapter modules: %r" % (after,)
print(sorted(types))
"""


def test_cli_adapter_types_imports_no_adapter_module():
    proc = subprocess.run(
        [sys.executable, "-c", _PROBE], cwd=str(_ADAPTERS_DIR),
        capture_output=True, text=True, timeout=60,
    )
    assert proc.returncode == 0, proc.stderr
    assert proc.stdout == repr(sorted(_EXPECTED_CLI)) + "\n"


def test_auth_kind_agrees_with_each_adapter_auth_type():
    auth_kind = providers._AUTH_KIND
    assert list(auth_kind) == list(providers._ADAPTER_TYPES)
    for adapter_type, kind in auth_kind.items():
        assert kind in ("api", "cli"), (adapter_type, kind)
        cls = providers.adapter_class_for_type(adapter_type)
        assert (cls.auth_type == "headless") == (kind == "cli"), (
            f"_AUTH_KIND[{adapter_type!r}] = {kind!r} but "
            f"{cls.__name__}.auth_type = {cls.auth_type!r}"
        )


def test_registry_contents_and_order_match_adapter_types():
    registry = providers._ADAPTER_REGISTRY
    assert type(registry) is dict
    assert list(registry) == _EXPECTED_TYPES == list(providers._ADAPTER_TYPES)
    for adapter_type, cls in registry.items():
        assert cls.__name__ == providers._ADAPTER_TYPES[adapter_type]
        assert cls is providers.adapter_class_for_type(adapter_type)
        assert cls is getattr(providers, cls.__name__)
    assert providers.adapter_class_for_type("no-such-type") is None


def test_cli_adapter_types_exact_set():
    types = providers.cli_adapter_types()
    assert type(types) is frozenset
    assert types == _EXPECTED_CLI
