"""#1032: generated routing and Python pricing share model-config.yaml."""

import subprocess
import sys
from pathlib import Path

import pytest
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from loa_cheval.metering.pricing import calculate_total_cost, find_pricing
from loa_cheval.routing.resolver import resolve_alias

ROOT = Path(__file__).resolve().parents[3]


def test_generated_aliases_match_python_resolution():
    config = yaml.safe_load((ROOT / ".claude/defaults/model-config.yaml").read_text())
    aliases = {**config.get("backward_compat_aliases", {}), **config["aliases"]}
    output = subprocess.check_output(
        ["bash", "-c",
         'source "$1"; for alias in "${!MODEL_IDS[@]}"; do '
         'printf "%s\\t%s:%s\\n" "$alias" "${MODEL_PROVIDERS[$alias]}" "${MODEL_IDS[$alias]}"; done',
         "registry-parity", str(ROOT / ".claude/scripts/generated-model-maps.sh")],
        text=True,
    )
    generated = dict(line.split("\t", 1) for line in output.splitlines())
    for alias in aliases:
        resolved = resolve_alias(alias, aliases)
        if resolved.provider != "claude-code":
            assert generated[alias] == f"{resolved.provider}:{resolved.model_id}", alias


@pytest.mark.parametrize("alias,input_cost,output_cost", [
    ("opus", 5000, 25000), ("claude-opus-4-6", 5000, 25000),
    ("gpt-5.3-codex", 1750, 14000), ("gemini-2.5-pro", 1250, 10000),
])
def test_retired_bash_pricing_contract_lives_in_python(alias, input_cost, output_cost):
    config = yaml.safe_load((ROOT / ".claude/defaults/model-config.yaml").read_text())
    aliases = {**config.get("backward_compat_aliases", {}), **config["aliases"]}
    resolved = resolve_alias(alias, aliases)
    pricing = find_pricing(resolved.provider, resolved.model_id, config)
    assert pricing is not None
    cost = calculate_total_cost(1000, 1000, 0, pricing)
    assert cost.input_cost_micro == input_cost
    assert cost.output_cost_micro == output_cost
