"""cycle-129 FR-7 (SDD D-7.1, D-7.2; sprint-257 Task 3.1, AC-3.1).

Every example block in `.loa.config.yaml.example` marked `# @example-begin <name>` …
`# @example-end` is uncommented, merged over the System defaults with the real cheval
loader, and must load. The insecure-endpoint refusals (a public http host, a boolean
opt-in, an opt-in naming a public host, a DNS name, a link-local or metadata address,
a unique-local IPv6 address, a mismatched host) each fail at load with a named reason;
`::1`, `[::1]` and RFC1918 opt-ins are accepted when they match; one provider's opt-in
leaves another provider's refusals intact.
"""

from __future__ import annotations

import copy
import re
import shutil
import sys
from pathlib import Path
from typing import Any, Dict, List, Tuple

import pytest
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from loa_cheval.config.endpoint_policy import EndpointPolicyError  # noqa: E402
from loa_cheval.config.loader import clear_config_cache, load_config  # noqa: E402
from loa_cheval.types import ConfigError  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[3]
EXAMPLE = REPO_ROOT / ".loa.config.yaml.example"
DEFAULTS = REPO_ROOT / ".claude" / "defaults" / "model-config.yaml"

_BEGIN = re.compile(r"^#\s*@example-begin\s+([A-Za-z0-9_-]+)\s*$")
_END = re.compile(r"^#\s*@example-end\s*$")


def extract_examples(text: str) -> List[Tuple[str, str]]:
    """(name, uncommented YAML) for every marked block. One leading `#` and one
    following space are removed per line; a nested or unterminated block fails."""
    blocks: List[Tuple[str, str]] = []
    name = None
    lines: List[str] = []
    for raw in text.splitlines():
        if name is None:
            m = _BEGIN.match(raw)
            if m:
                name, lines = m.group(1), []
            elif _END.match(raw):
                raise AssertionError("@example-end without @example-begin")
            continue
        if _BEGIN.match(raw):
            raise AssertionError(f"nested @example-begin inside {name}")
        if _END.match(raw):
            blocks.append((name, "\n".join(lines) + "\n"))
            name = None
            continue
        assert raw.startswith("#"), f"example {name}: every line must be commented: {raw!r}"
        body = raw[1:]
        lines.append(body[1:] if body.startswith(" ") else body)
    assert name is None, f"unterminated example block {name}"
    return blocks


def _project(tmp_path: Path, hounfour: Dict[str, Any]) -> str:
    root = tmp_path / "proj"
    (root / ".claude" / "defaults").mkdir(parents=True, exist_ok=True)
    shutil.copy(DEFAULTS, root / ".claude" / "defaults" / "model-config.yaml")
    (root / ".loa.config.yaml").write_text(yaml.safe_dump({"hounfour": hounfour}, sort_keys=False))
    return str(root)


def _load(tmp_path: Path, hounfour: Dict[str, Any]) -> Dict[str, Any]:
    clear_config_cache()
    merged, _ = load_config(project_root=_project(tmp_path, hounfour))
    return merged


EXAMPLES = extract_examples(EXAMPLE.read_text())
_BY_NAME = {n: yaml.safe_load(y)["hounfour"] for n, y in EXAMPLES}


def test_marked_examples_are_present():
    names = [n for n, _ in EXAMPLES]
    assert len(names) == len(set(names)), names
    for required in ("conservative", "budget-conscious", "azure-openai", "local-openai-compatible"):
        assert required in names, f"example {required} is not marked in {EXAMPLE.name}"


@pytest.mark.parametrize("name, body", EXAMPLES, ids=[n for n, _ in EXAMPLES])
def test_every_marked_example_loads(tmp_path, name, body):
    doc = yaml.safe_load(body)
    assert isinstance(doc, dict) and "hounfour" in doc, f"example {name} must be a `hounfour:` block"
    merged = _load(tmp_path, doc["hounfour"])
    for prov in (doc["hounfour"].get("providers") or {}):
        assert prov in merged["providers"]


def test_azure_example_carries_the_required_model_fields(tmp_path):
    merged = _load(tmp_path, _BY_NAME["azure-openai"])
    model = merged["providers"]["azure-openai"]["models"]["gpt-5-azure"]
    for key in ("endpoint_family", "auth_type", "dispatch_group", "context_window", "max_output_tokens"):
        assert model.get(key), key
    assert "^AZURE_OPENAI_KEY$" in merged["secret_env_allowlist"]


def test_local_example_is_keyless_local_and_opted_in(tmp_path):
    merged = _load(tmp_path, _BY_NAME["local-openai-compatible"])
    prov = merged["providers"]["local"]
    assert prov["keyless"] is True
    assert prov["allow_insecure_endpoint"] == "127.0.0.1"
    model = prov["models"]["qwen3-coder-30b"]
    assert model["dispatch_group"] == "local"
    assert model["streaming_recovery"] == {"first_token_deadline_s": 120}
    assert model["pricing"] == {"input_per_mtok": 0, "output_per_mtok": 0}
    assert merged["aliases"]["local-reviewer"] == "local:qwen3-coder-30b"


def test_literal_auth_local_is_normalised_to_keyless(tmp_path):
    cfg = copy.deepcopy(_BY_NAME["local-openai-compatible"])
    del cfg["providers"]["local"]["keyless"]
    cfg["providers"]["local"]["auth"] = "local"
    merged = _load(tmp_path, cfg)
    assert merged["providers"]["local"]["keyless"] is True


# --- refusals at load ------------------------------------------------------------------------------------


def _local(**overrides: Any) -> Dict[str, Any]:
    cfg = copy.deepcopy(_BY_NAME["local-openai-compatible"])
    prov = cfg["providers"]["local"]
    for k, v in overrides.items():
        if v is None:
            prov.pop(k, None)
        else:
            prov[k] = v
    return cfg


REFUSALS = [
    ("public-http-host", dict(endpoint="http://8.8.8.8/v1", allow_insecure_endpoint=None), "ENDPOINT-INSECURE-SCHEME"),
    ("public-http-dns", dict(endpoint="http://api.example.com/v1", allow_insecure_endpoint=None),
     "ENDPOINT-INSECURE-SCHEME"),
    ("boolean-optin", dict(allow_insecure_endpoint=True), "ENDPOINT-OPTIN-BOOLEAN"),
    ("optin-public-host", dict(endpoint="http://8.8.8.8/v1", allow_insecure_endpoint="8.8.8.8"),
     "ENDPOINT-OPTIN-NOT-LOCAL"),
    ("optin-dns-name", dict(endpoint="http://llm.internal/v1", allow_insecure_endpoint="llm.internal"),
     "ENDPOINT-OPTIN-DNS-NAME"),
    ("optin-link-local", dict(endpoint="http://169.254.10.10/v1", allow_insecure_endpoint="169.254.10.10"),
     "ENDPOINT-OPTIN-LINK-LOCAL"),
    ("optin-metadata", dict(endpoint="http://169.254.169.254/v1", allow_insecure_endpoint="169.254.169.254"),
     "ENDPOINT-OPTIN-METADATA"),
    ("optin-ipv6-ula", dict(endpoint="http://[fd12::1]:8000/v1", allow_insecure_endpoint="fd12::1"),
     "ENDPOINT-OPTIN-NOT-LOCAL"),
    ("mismatched-host", dict(endpoint="http://localhost:8000/v1", allow_insecure_endpoint="127.0.0.1"),
     "ENDPOINT-INSECURE-HOST-MISMATCH"),
    ("https-loopback-without-optin", dict(endpoint="https://127.0.0.1:8000/v1", allow_insecure_endpoint=None),
     "ENDPOINT-IP-BLOCKED"),
    ("https-private-without-optin", dict(endpoint="https://10.0.0.5/v1", allow_insecure_endpoint=None),
     "ENDPOINT-IP-BLOCKED"),
    ("https-metadata-without-optin", dict(endpoint="https://169.254.169.254/v1", allow_insecure_endpoint=None),
     "ENDPOINT-IP-BLOCKED"),
    ("userinfo", dict(endpoint="http://u:p@127.0.0.1:8000/v1"), "ENDPOINT-USERINFO-PRESENT"),
]


@pytest.mark.parametrize("case, overrides, code", REFUSALS, ids=[c for c, _, _ in REFUSALS])
def test_refused_at_load_with_a_named_reason(tmp_path, case, overrides, code):
    with pytest.raises(EndpointPolicyError) as info:
        _load(tmp_path, _local(**overrides))
    assert info.value.policy_code == code, str(info.value)
    assert f"[{code}]" in str(info.value) and "providers.local" in str(info.value)


ACCEPTED = [
    ("ipv4-loopback", "http://127.0.0.1:8000/v1", "127.0.0.1"),
    ("ipv6-loopback-bare", "http://[::1]:8000/v1", "::1"),
    ("ipv6-loopback-bracketed", "http://[::1]:8000/v1", "[::1]"),
    ("localhost", "http://localhost:11434/v1", "localhost"),
    ("rfc1918-10", "http://10.1.2.3:8000/v1", "10.1.2.3"),
    ("rfc1918-172", "http://172.20.0.4:8000/v1", "172.20.0.4"),
    ("rfc1918-192", "http://192.168.1.50:8000/v1", "192.168.1.50"),
    ("https-to-optin-host", "https://192.168.1.50/v1", "192.168.1.50"),
]


@pytest.mark.parametrize("case, endpoint, optin", ACCEPTED, ids=[c for c, _, _ in ACCEPTED])
def test_matching_optin_is_accepted(tmp_path, case, endpoint, optin):
    merged = _load(tmp_path, _local(endpoint=endpoint, allow_insecure_endpoint=optin))
    assert merged["providers"]["local"]["endpoint"] == endpoint


def test_one_providers_optin_leaves_another_providers_refusals_intact(tmp_path):
    cfg = _local()
    other = copy.deepcopy(cfg["providers"]["local"])
    other.pop("allow_insecure_endpoint")
    other["endpoint"] = "http://127.0.0.1:9000/v1"   # same loopback host, no opt-in of its own
    cfg["providers"]["other"] = other
    with pytest.raises(EndpointPolicyError) as info:
        _load(tmp_path, cfg)
    assert info.value.policy_code == "ENDPOINT-INSECURE-SCHEME"
    assert "providers.other" in str(info.value)
    # and the opted-in provider alone still loads
    _load(tmp_path, _local())


def test_keyless_requires_declared_context_window(tmp_path):
    cfg = _local()
    del cfg["providers"]["local"]["models"]["qwen3-coder-30b"]["context_window"]
    with pytest.raises(ConfigError, match="keyless provider is admitted only with a declared context_window"):
        _load(tmp_path, cfg)


def test_keyless_must_be_boolean(tmp_path):
    with pytest.raises(ConfigError, match="keyless must be true or false"):
        _load(tmp_path, _local(keyless="yes"))


def test_hosted_defaults_still_load_unchanged(tmp_path):
    merged = _load(tmp_path, {})
    assert merged["providers"]["openai"]["endpoint"].startswith("https://")
    assert "keyless" not in merged["providers"]["openai"]
