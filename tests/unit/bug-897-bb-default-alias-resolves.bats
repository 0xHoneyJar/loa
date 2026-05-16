#!/usr/bin/env bats
# =============================================================================
# tests/unit/bug-897-bb-default-alias-resolves.bats
#
# Bug #897 — anti-regression: bridgebuilder-review's default model alias
# (whatever DEFAULTS.model in config.ts declares, currently `claude-opus-4-7`)
# must resolve cleanly via cheval's `load_config()` path. The original
# report claimed the alias was rejected with `INVALID_CONFIG: Unknown
# alias`, but the bug was already closed on main via the
# `_fold_backward_compat_aliases` fold at
# `.claude/adapters/loa_cheval/config/loader.py:573-606` (cycle-095
# Sprint 2). This test pins that contract so a future YAML edit can't
# silently drop the alias the BB tool actually uses by default.
#
# Note: the bats file reads the alias name from `config.ts` rather than
# hardcoding it, so a future BB default-model change (e.g., bumping to
# opus 4.8 or sonnet 5) will automatically pin the new alias instead of
# leaving a stale check passing against an obsolete model name.
#
# Closes #897 (verification + anti-regression).
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    # Extract the BB default model from config.ts.
    # BB #913 v5 (F-001 MEDIUM — unanchored grep / test oracle correlation):
    # the v3/v4 form `grep -oE 'model:\s*"..."' | head -1` matched the
    # FIRST `model:` line in config.ts. Today line 165 happens to be in
    # the DEFAULTS block, but a future edit that inserts a `model: "..."`
    # earlier (a comment, another struct, a Zod schema default) would
    # silently pin the wrong alias — making the anti-regression check
    # correlated with the regression it's meant to detect.
    # Fix: anchor on the `const DEFAULTS:` block with awk, then capture
    # the first `model:` line WITHIN that block. `exit` stops at
    # DEFAULTS.model and never sees later `model:` references.
    BB_DEFAULT_MODEL="$(awk '
        /^const DEFAULTS:[[:space:]]*BridgebuilderConfig[[:space:]]*=/{flag=1; next}
        flag && /^\}/{flag=0; exit}
        flag && /^[[:space:]]*model:[[:space:]]*"/{
            match($0, /"[^"]+"/)
            print substr($0, RSTART+1, RLENGTH-2)
            exit
        }
    ' "$PROJECT_ROOT/.claude/skills/bridgebuilder-review/resources/config.ts")"
    [ -n "$BB_DEFAULT_MODEL" ] || {
        echo "FATAL: could not extract DEFAULTS.model from config.ts (anchored awk found no match in the DEFAULTS block)" >&2
        return 1
    }
    export BB_DEFAULT_MODEL
}

@test "bug-897-1: BB default model alias resolves via load_config()" {
    cd "$PROJECT_ROOT"
    run env BB_DEFAULT_MODEL="$BB_DEFAULT_MODEL" python3 - <<'PY'
import os, sys
sys.path.insert(0, '.claude/adapters')
from loa_cheval.config.loader import load_config
cfg, _ = load_config()
aliases = cfg.get('aliases', {}) or {}
backcompat = cfg.get('backward_compat_aliases', {}) or {}
default = os.environ['BB_DEFAULT_MODEL']
merged = {**backcompat, **aliases}
assert default in merged, (
    f"BB default '{default}' missing from aliases/backward_compat_aliases — "
    f"sample aliases: {sorted(aliases)[:10]}, "
    f"sample backcompat: {sorted(backcompat)[:10]}"
)
target = merged[default]
assert target.startswith(('anthropic:', 'openai:', 'google:', 'bedrock:')), \
    f"BB default '{default}' resolves to '{target}' — expected provider:model form"
print("OK")
PY
    # OK-glob is intentional positive-control canary against accidental status=0 returns
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "bug-897-2: dot-form of the BB default resolves to the same target as the dash form" {
    cd "$PROJECT_ROOT"
    run env BB_DEFAULT_MODEL="$BB_DEFAULT_MODEL" python3 - <<'PY'
import os, re, sys
sys.path.insert(0, '.claude/adapters')
from loa_cheval.config.loader import load_config
cfg, _ = load_config()
aliases = cfg.get('aliases', {}) or {}
backcompat = cfg.get('backward_compat_aliases', {}) or {}
dash = os.environ['BB_DEFAULT_MODEL']
# BB #913 v4 fix (claude F-001 HIGH 0.97 — vacuous test): the v3 form
# used `dash.replace('-', '.', 1)` which replaces the FIRST dash, so
# 'claude-opus-4-7' became 'claude.opus-4-7' (wrong) instead of the
# intended 'claude-opus-4.7'. The conditional `if dot in merged` then
# silently skipped the assertion. Corrected substitution: target only
# the trailing version-separator dash. Examples:
#   claude-opus-4-7   → claude-opus-4.7
#   claude-sonnet-4-6 → claude-sonnet-4.6
#   gpt-5.5-pro       → unchanged (no trailing -\d+)
dot = re.sub(r'-(\d+)$', r'.\1', dash)
merged = {**backcompat, **aliases}
# BB #913 v4 fix (gpt F-002 MEDIUM 0.90 — conditional assertion): the
# previous `if dot in merged: assert X` form silently passed when the
# registry dropped the dot-form alias — the exact regression bug-897
# was opened to close. When the dash/dot forms genuinely differ, the
# dot form MUST be present AND resolve to the same target.
if dot != dash:
    assert dot in merged, (
        f"BB default dot-form {dot!r} (derived from {dash!r}) missing from "
        f"aliases / backward_compat_aliases — sample aliases: "
        f"{sorted(aliases)[:10]}"
    )
    assert merged[dash] == merged[dot], (
        f"alias divergence: dash form '{dash}'→{merged[dash]!r}  "
        f"dot form '{dot}'→{merged[dot]!r}"
    )
print("OK")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "bug-897-3: BB default model lives in a loader-readable section of model-config.yaml" {
    # BB #913 review (F-001 DISPUTED, 0.88 conf — drop-or-replace): the
    # previous version grepped `^\s*claude-opus-4-7\s*:` against the raw
    # YAML, which matches the key anywhere in the document tree (including
    # a hypothetical `deprecations:` section the fold helper never reads).
    # Replaced with a structural assertion that the alias lives in one of
    # the two sections `_fold_backward_compat_aliases` actually consults:
    # `aliases:` or `backward_compat_aliases:`. Anchors the path, not just
    # the key.
    cd "$PROJECT_ROOT"
    run env BB_DEFAULT_MODEL="$BB_DEFAULT_MODEL" python3 - <<'PY'
import os, sys
# BB #913 v4 (gpt F-001 MEDIUM 0.98 — sys.path ordering): sys.path
# must be configured BEFORE `import yaml` for a vendored copy under
# .claude/adapters to take effect. Otherwise the system pyyaml wins
# and tests 1+2 (which do this in the right order via the imports
# preceding the load_config call) end up using a different yaml lib
# than test 3.
sys.path.insert(0, '.claude/adapters')
import yaml
default = os.environ['BB_DEFAULT_MODEL']
with open('.claude/defaults/model-config.yaml') as f:
    cfg = yaml.safe_load(f)
aliases_section = cfg.get('aliases') or {}
backcompat_section = cfg.get('backward_compat_aliases') or {}
in_aliases  = default in aliases_section
in_backcompat = default in backcompat_section
# BB #913 review F-001 fix (format-string mismatch): three positional {}
# placeholders, three explicit .format() args. Without this the test's
# own failure path raised IndexError instead of emitting the diagnostic.
other_sections = [k for k, v in cfg.items()
                  if isinstance(v, dict) and default in v
                  and k not in ('aliases', 'backward_compat_aliases')]
assert in_aliases or in_backcompat, (
    "{default!r} not in aliases ({a_sample}) or backward_compat_aliases "
    "({b_sample}) — the fold helper at loader.py:573-606 won't see it. "
    "Found {default!r} present only in: {other}"
).format(
    default=default,
    a_sample=sorted(aliases_section)[:8],
    b_sample=sorted(backcompat_section)[:8],
    other=other_sections,
)
print("OK")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}
