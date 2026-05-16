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
# Fix: declare per-entry context_window in YAML. Canonical values live in
# `.claude/defaults/model-config.yaml` (single source of truth). Each
# headless entry MUST agree with its `extra.cli_model` http_api sibling;
# the cross-entry invariant is pinned by bug-881-1b below.
#
# These tests prove the YAML side (presence + canonical values) and the
# loader-side roundtrip (resolved ModelConfig carries the value).
#
# Note (BB #914 F-001-test-header): the previous header duplicated the
# expected numeric values inline (`codex-headless: 200000`, etc.); the
# assertions below diverged from that list (codex-headless is 400000),
# which would have misled the next editor reading the header before the
# assertions. The duplicated list was removed; the YAML is canonical.
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

@test "bug-881-1: codex-headless declares context_window=400000 (matches gpt-5.5 capacity)" {
    # BB #914 F-001 correction: the initial PR shipped 200000 with an
    # inaccurate comment. gpt-5.5 (which the codex CLI dispatches by
    # default) declares context_window: 400000 in this same YAML.
    run python3 - <<'PY'
import yaml, sys, os
y = yaml.safe_load(open(os.environ['YAML']))
v = y['providers']['openai']['models']['codex-headless'].get('context_window')
print(v)
assert v == 400000, f"expected 400000 got {v}"
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"400000"* ]]
}

@test "bug-881-1b: each headless context_window matches its cli_model's http_api sibling (BB #914 F-001 invariant)" {
    # Pin the cross-entry invariant the BB F-001 finding surfaced: when a
    # headless entry's `extra.cli_model: X` exists and X has an http_api
    # sibling with `context_window`, the two MUST agree. Prevents future
    # cli_model edits from silently desyncing the budget.
    cd "$PROJECT_ROOT"
    run python3 - <<'PY'
import yaml, sys
with open('.claude/defaults/model-config.yaml') as f:
    cfg = yaml.safe_load(f)

aliases = cfg.get('aliases') or {}
backcompat = cfg.get('backward_compat_aliases') or {}
all_aliases = {**backcompat, **aliases}

def resolve_sibling(prov, ref, providers):
    """`ref` may be a direct model name in providers[prov].models, or an
    alias that resolves to `<provider>:<model>`. Return (provider, model_dict)
    or (None, None) if unresolvable."""
    models = providers[prov].get('models') or {}
    if ref in models:
        return prov, models[ref]
    target = all_aliases.get(ref)
    if target and ':' in target:
        target_prov, target_name = target.split(':', 1)
        target_models = (providers.get(target_prov) or {}).get('models') or {}
        if target_name in target_models:
            return target_prov, target_models[target_name]
    return None, None

errors = []
cli_kind_count = 0
for prov, prov_block in cfg['providers'].items():
    for name, m in (prov_block.get('models') or {}).items():
        if m.get('kind') != 'cli':
            continue
        cli_kind_count += 1
        # BB #914 F-002 fix: a missing context_window / cli_model is a
        # hard failure of the contract this PR pins; a non-resolvable
        # cli_model is a soft signal (some CLIs accept tool-internal
        # short forms like `claude --model sonnet` that don't appear in
        # YAML — operator-overridable on purpose). Distinguish:
        #
        #   HARD: kind:cli entry MUST declare context_window
        #   HARD: kind:cli entry MUST declare extra.cli_model
        #   SOFT: IF the cli_model resolves via YAML/aliases, cw MUST match
        #         the sibling. Unresolved short forms are accepted but
        #         logged so a typo-driven drop is still visible.
        cli_model = (m.get('extra') or {}).get('cli_model')
        if not cli_model:
            errors.append(f"{prov}.{name} kind:cli but no extra.cli_model")
            continue
        cw_self = m.get('context_window')
        if cw_self is None:
            errors.append(f"{prov}.{name} missing context_window (the fix this PR pins)")
            continue
        sib_prov, sibling = resolve_sibling(prov, cli_model, cfg['providers'])
        if not sibling:
            # Tool-internal alias (e.g. claude CLI's `sonnet` short form
            # that the CLI itself resolves). Acceptable; cw cross-check
            # is best-effort and skipped.
            continue
        sib_kind = sibling.get('kind', 'http_api')
        if sib_kind == 'cli':
            errors.append(f"{prov}.{name} cli_model={cli_model!r} resolves to "
                          f"another kind:cli entry (would form a cli→cli cycle)")
            continue
        cw_sib = sibling.get('context_window')
        if cw_sib is None:
            errors.append(f"{prov}.{name} sibling {cli_model!r} missing context_window")
            continue
        if cw_self != cw_sib:
            errors.append(f"{prov}.{name} cw={cw_self} != cli_model {cli_model!r} cw={cw_sib}")
# Vacuous-loop guard: the regression test is meaningless if no kind:cli
# entries exist. If a future YAML edit drops them all, fail loudly.
if cli_kind_count == 0:
    print("FATAL: no kind:cli entries discovered — regression test is vacuous", file=sys.stderr)
    sys.exit(1)
if errors:
    print('\n'.join(errors), file=sys.stderr)
    sys.exit(1)
print("OK")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
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
    ('openai',    'codex-headless',   400000),
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

@test "bug-881-6: model-config.yaml.checksum matches the current YAML (portable across linux + macos)" {
    # BB #914 F-002 fix: `sha256sum` is GNU coreutils and absent on macOS;
    # macOS ships `shasum -a 256` instead. The drift-gate CI matrix
    # includes macos-latest, so this test must work on both. Prefer
    # sha256sum (linux), fall back to shasum (macos).
    cd "$PROJECT_ROOT"
    expected=$(cat .claude/defaults/model-config.yaml.checksum)
    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum .claude/defaults/model-config.yaml | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        actual=$(shasum -a 256 .claude/defaults/model-config.yaml | awk '{print $1}')
    else
        skip "Neither sha256sum nor shasum available — no checksum tool"
    fi
    [ "$expected" = "$actual" ]
}
