#!/usr/bin/env bats
# =============================================================================
# tests/unit/bug-897-bb-default-alias-resolves.bats
#
# Bug #897 — anti-regression: bridgebuilder-review's default model alias
# `claude-opus-4-7` (dash form) must resolve cleanly via cheval's
# `load_config()` path. The original report claimed the alias was
# rejected with `INVALID_CONFIG: Unknown alias`, but the bug was
# already closed on main via the `_fold_backward_compat_aliases` fold
# at `.claude/adapters/loa_cheval/config/loader.py:573-606` (cycle-095
# Sprint 2). This test pins that contract so a future YAML edit can't
# silently drop the dash-form alias and re-break BB Pass 1.
#
# Closes #897 (verification + anti-regression).
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
}

@test "bug-897-1: claude-opus-4-7 (dash form) resolves via load_config()" {
    cd "$PROJECT_ROOT"
    run python3 - <<'PY'
import sys
sys.path.insert(0, '.claude/adapters')
from loa_cheval.config.loader import load_config
cfg, _ = load_config()
aliases = cfg.get('aliases', {})
assert 'claude-opus-4-7' in aliases, \
    f"claude-opus-4-7 missing from aliases — found: {sorted(aliases)[:20]}"
assert aliases['claude-opus-4-7'] == 'anthropic:claude-opus-4-7', \
    f"claude-opus-4-7 resolves to '{aliases['claude-opus-4-7']}', expected 'anthropic:claude-opus-4-7'"
print("OK")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "bug-897-2: claude-opus-4.7 (dot form) resolves to the same target as the dash form" {
    cd "$PROJECT_ROOT"
    run python3 - <<'PY'
import sys
sys.path.insert(0, '.claude/adapters')
from loa_cheval.config.loader import load_config
cfg, _ = load_config()
aliases = cfg.get('aliases', {})
assert 'claude-opus-4.7' in aliases, \
    f"claude-opus-4.7 missing from aliases — found: {sorted(aliases)[:20]}"
dash = aliases.get('claude-opus-4-7')
dot  = aliases.get('claude-opus-4.7')
assert dash == dot, f"alias divergence: dash→{dash!r} dot→{dot!r}"
print("OK")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "bug-897-3: bridgebuilder default model entry matches the resolved alias" {
    # BB's generated config sets `claude-opus-4-7` as the default model.
    # Pin that the YAML still declares it in either the live aliases
    # map OR backward_compat_aliases.
    run grep -E '^\s*claude-opus-4-7\s*:' "$PROJECT_ROOT/.claude/defaults/model-config.yaml"
    [ "$status" -eq 0 ]
}
