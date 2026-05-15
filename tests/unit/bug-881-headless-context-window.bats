#!/usr/bin/env bats
# =============================================================================
# tests/unit/bug-881-headless-context-window.bats
#
# Bug #881 — cheval headless adapters silently fell back to the 128000-
# token ModelConfig.context_window default because the three headless
# entries in model-config.yaml omitted the `context_window` field. BB
# review on cycle-shaped PRs (~120k token diffs) failed with
# `CONTEXT_TOO_LARGE` even though the underlying CLI tools natively
# support 200k+ tokens.
#
# Fix: declare per-entry context_window in YAML
#   - codex-headless:   200000 (gpt-5.5 capacity)
#   - claude-headless:  200000 (sonnet/opus capacity)
#   - gemini-headless: 1048576 (gemini-3.1-pro-preview capacity)
#
# These tests prove the YAML side (presence + canonical values) and the
# loader-side roundtrip (resolved ModelConfig carries the value).
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    YAML="$PROJECT_ROOT/.claude/defaults/model-config.yaml"
    export YAML
}

# =============================================================================
# YAML field presence + canonical values
# =============================================================================

@test "bug-881-1: codex-headless declares context_window=200000" {
    run python3 - <<'PY'
import yaml, sys, os
y = yaml.safe_load(open(os.environ['YAML']))
v = y['providers']['openai']['models']['codex-headless'].get('context_window')
print(v)
assert v == 200000, f"expected 200000 got {v}"
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"200000"* ]]
}

@test "bug-881-2: claude-headless declares context_window=200000" {
    run python3 - <<'PY'
import yaml, sys, os
y = yaml.safe_load(open(os.environ['YAML']))
v = y['providers']['anthropic']['models']['claude-headless'].get('context_window')
print(v)
assert v == 200000, f"expected 200000 got {v}"
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"200000"* ]]
}

@test "bug-881-3: gemini-headless declares context_window=1048576" {
    run python3 - <<'PY'
import yaml, sys, os
y = yaml.safe_load(open(os.environ['YAML']))
v = y['providers']['google']['models']['gemini-headless'].get('context_window')
print(v)
assert v == 1048576, f"expected 1048576 got {v}"
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"1048576"* ]]
}

# =============================================================================
# Loader roundtrip — proves the YAML edit reaches the runtime
# =============================================================================

@test "bug-881-4: load_config() resolves each headless entry to its canonical context_window" {
    cd "$PROJECT_ROOT"
    run python3 - <<'PY'
import sys
sys.path.insert(0, '.claude/adapters')
from loa_cheval.config.loader import load_config
cfg, _ = load_config()
providers = cfg['providers']

cases = [
    ('openai',    'codex-headless',   200000),
    ('anthropic', 'claude-headless',  200000),
    ('google',    'gemini-headless', 1048576),
]
for prov, model, expected in cases:
    cw = providers[prov]['models'][model].get('context_window')
    assert cw == expected, f"{prov}.{model}: got {cw} expected {expected}"
print("OK")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# =============================================================================
# Negative control — the 128000 default MUST NOT have leaked into a headless entry
# =============================================================================

@test "bug-881-5: no headless entry silently picks up the 128000 default" {
    cd "$PROJECT_ROOT"
    run python3 - <<'PY'
import sys
sys.path.insert(0, '.claude/adapters')
from loa_cheval.config.loader import load_config
cfg, _ = load_config()
providers = cfg['providers']
for prov, model in [('openai','codex-headless'),('anthropic','claude-headless'),('google','gemini-headless')]:
    cw = providers[prov]['models'][model].get('context_window')
    assert cw is not None, f"{prov}.{model} has no context_window — would fall back to 128000"
    assert cw != 128000, f"{prov}.{model} declares 128000 — too low for headless CLI dispatch"
print("OK")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# =============================================================================
# Checksum — drift gate must stay green
# =============================================================================

@test "bug-881-6: model-config.yaml.checksum matches the current YAML" {
    cd "$PROJECT_ROOT"
    expected=$(cat .claude/defaults/model-config.yaml.checksum)
    actual=$(sha256sum .claude/defaults/model-config.yaml | awk '{print $1}')
    [ "$expected" = "$actual" ]
}
