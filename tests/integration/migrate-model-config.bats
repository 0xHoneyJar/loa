#!/usr/bin/env bats
# =============================================================================
# tests/integration/migrate-model-config.bats
#
# cycle-099 Sprint 1E — T1.14 loa migrate-model-config CLI tests.
#
# Per SDD §3.1.1.1 the v1→v2 migration is a pure function inside
# .claude/scripts/lib/model-config-migrate.py; the operator-facing CLI at
# .claude/scripts/loa-migrate-model-config.py drives I/O + reporting.
#
# Acceptance per AC-S1.11: v1 input → valid v2 file (full v2 schema validation
# passes); idempotent on v2 input; exits 78 on validation failure; field-level
# CLI report per SDD §3.1.1.1 table.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    CLI="$PROJECT_ROOT/.claude/scripts/loa-migrate-model-config.py"
    LIB="$PROJECT_ROOT/.claude/scripts/lib/model-config-migrate.py"
    SCHEMA="$PROJECT_ROOT/.claude/data/schemas/model-config-v2.schema.json"
    FIXTURES="$PROJECT_ROOT/tests/fixtures/model-config-migrate"

    [[ -f "$CLI" ]] || skip "loa-migrate-model-config.py not present"
    [[ -f "$LIB" ]] || skip "model-config-migrate.py not present"
    [[ -f "$SCHEMA" ]] || skip "model-config-v2.schema.json not present"

    # Pinned interpreter — .venv has the ruamel.yaml + jsonschema deps.
    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="${PYTHON_BIN:-python3}"
    fi

    # Verify deps; otherwise skip with a clear marker.
    "$PYTHON_BIN" -c "import ruamel.yaml, jsonschema" 2>/dev/null \
        || skip "ruamel.yaml or jsonschema not available in $PYTHON_BIN"

    WORK_DIR="$(mktemp -d)"
    OUT="$WORK_DIR/out.yaml"
    REPORT="$WORK_DIR/report.json"
}

teardown() {
    if [[ -n "${WORK_DIR:-}" ]] && [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
    return 0
}

# Helper: run an inline Python script with paths exposed via os.environ
# rather than shell interpolation. Closes BB iter-1 F2 — a quoted-EOF heredoc
# eliminates the shell-injection-into-Python-source surface that unquoted
# heredocs leave open when paths contain quotes/$/\.
#
# Usage:
#     _python_assert <<'EOF'
#     import os
#     from ruamel.yaml import YAML
#     y = YAML(typ='safe')
#     with open(os.environ["OUT"]) as f:
#         data = y.load(f)
#     ...
#     EOF
_python_assert() {
    OUT="$OUT" \
    FIXTURES="$FIXTURES" \
    PROJECT_ROOT="$PROJECT_ROOT" \
    SCHEMA="$SCHEMA" \
    WORK_DIR="$WORK_DIR" \
    "$PYTHON_BIN" -
}

# ---------------------------------------------------------------------------
# M1 — v1 → v2 happy path (cycle-095-vintage)
# ---------------------------------------------------------------------------

@test "M1.1 happy path: cycle-095 v1 migrates to valid v2" {
    run "$PYTHON_BIN" "$CLI" "$FIXTURES/v1-happy-path.yaml" -o "$OUT"
    [[ "$status" -eq 0 ]]
    [[ -f "$OUT" ]]
    # schema_version: 2 must appear
    grep -q '^schema_version: 2$' "$OUT"
    # Original cycle-095 fields preserved verbatim
    grep -q 'gpt-5.5' "$OUT"
    grep -q 'claude-opus-4-7' "$OUT"
}

@test "M1.2 happy path: validates against v2 schema after migration" {
    "$PYTHON_BIN" "$CLI" "$FIXTURES/v1-happy-path.yaml" -o "$OUT"
    # Independent schema check (sanity)
    _python_assert <<'EOF'
import json, os
import jsonschema
from ruamel.yaml import YAML
y = YAML(typ='safe')
with open(os.environ["OUT"]) as f:
    data = y.load(f)
with open(os.environ["SCHEMA"]) as f:
    schema = json.load(f)
jsonschema.Draft202012Validator(schema).validate(data)
EOF
}

# ---------------------------------------------------------------------------
# M2 — schema_version detection
# ---------------------------------------------------------------------------

@test "M2.1 detection: v1 absent (cycle-095 vintage) treated as v1" {
    run "$PYTHON_BIN" "$CLI" "$FIXTURES/v1-happy-path.yaml" -o "$OUT"
    [[ "$status" -eq 0 ]]
    grep -q '^schema_version: 2$' "$OUT"
}

@test "M2.2 detection: v3+ input rejected with structured error" {
    run "$PYTHON_BIN" "$CLI" "$FIXTURES/v3-future.yaml" -o "$OUT"
    [[ "$status" -eq 78 ]]
    [[ "$output" == *"CONFIG-SCHEMA-VERSION-UNSUPPORTED"* ]]
}

# ---------------------------------------------------------------------------
# M3 — Field rename (endpoint_class → endpoint_family)
# ---------------------------------------------------------------------------

@test "M3.1 rename: endpoint_class becomes endpoint_family in v2" {
    run "$PYTHON_BIN" "$CLI" "$FIXTURES/v1-with-rename.yaml" -o "$OUT"
    [[ "$status" -eq 0 ]]
    # endpoint_class gone, endpoint_family present
    ! grep -q 'endpoint_class' "$OUT"
    grep -q 'endpoint_family: chat' "$OUT"
}

@test "M3.2 rename: report contains INFO for renamed field" {
    run "$PYTHON_BIN" "$CLI" "$FIXTURES/v1-with-rename.yaml" -o "$OUT" --report-format text
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"renamed"* ]]
    [[ "$output" == *"endpoint_class"* ]]
    [[ "$output" == *"endpoint_family"* ]]
}

# ---------------------------------------------------------------------------
# M4 — Unknown field preservation
# ---------------------------------------------------------------------------

@test "M4.1 unknown: experimental_routing archived under _unknown_v1_fields" {
    run "$PYTHON_BIN" "$CLI" "$FIXTURES/v1-with-unknown.yaml" -o "$OUT"
    [[ "$status" -eq 0 ]]
    grep -q '^_unknown_v1_fields:' "$OUT"
    grep -q 'experimental_routing' "$OUT"
    # The original top-level key must NOT remain at the root
    ! grep -q '^experimental_routing:' "$OUT"
}

@test "M4.2 unknown: report contains WARN for preserved unknown field" {
    run "$PYTHON_BIN" "$CLI" "$FIXTURES/v1-with-unknown.yaml" -o "$OUT" --report-format text
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"experimental_routing"* ]]
}

# ---------------------------------------------------------------------------
# M5 — Invalid v2 rejection (context_window < 1024)
# ---------------------------------------------------------------------------

@test "M5.1 invalid: context_window=500 fails post-migration v2 schema" {
    run "$PYTHON_BIN" "$CLI" "$FIXTURES/v1-invalid-context-window.yaml" -o "$OUT"
    [[ "$status" -eq 78 ]]
    [[ "$output" == *"MIGRATION-PRODUCED-INVALID-V2"* ]]
    # Output should reference the offending field path
    [[ "$output" == *"context_window"* ]]
}

# ---------------------------------------------------------------------------
# M6 — Idempotency on v2 input
# ---------------------------------------------------------------------------

@test "M6.1 idempotency: v2 input emits MIGRATION-NOOP-V2-INPUT and exits 0" {
    run "$PYTHON_BIN" "$CLI" "$FIXTURES/v2-already.yaml" -o "$OUT"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"MIGRATION-NOOP-V2-INPUT"* ]]
}

@test "M6.2 idempotency: round-trip v2 → v2 produces structurally-equivalent output" {
    "$PYTHON_BIN" "$CLI" "$FIXTURES/v2-already.yaml" -o "$OUT"
    # Both inputs parse to the same dict structure (using safe yaml load)
    _python_assert <<'EOF'
import os
from ruamel.yaml import YAML
y = YAML(typ='safe')
with open(os.path.join(os.environ["FIXTURES"], "v2-already.yaml")) as f:
    a = y.load(f)
with open(os.environ["OUT"]) as f:
    b = y.load(f)
assert a == b, f"v2 round-trip not idempotent.\nin:  {a}\nout: {b}"
EOF
}

# ---------------------------------------------------------------------------
# M7 — agents.<skill>.model rename to default_tier (tier-tag values only)
# ---------------------------------------------------------------------------

@test "M7.1 agent rename: model: cheap becomes default_tier: cheap" {
    "$PYTHON_BIN" "$CLI" "$FIXTURES/v1-happy-path.yaml" -o "$OUT"
    # reviewer was 'model: cheap' in v1 → should be 'default_tier: cheap' in v2
    _python_assert <<'EOF'
import os
from ruamel.yaml import YAML
y = YAML(typ='safe')
with open(os.environ["OUT"]) as f:
    data = y.load(f)
reviewer = data["agents"]["reviewer"]
assert "default_tier" in reviewer, f"expected default_tier; got {reviewer}"
assert reviewer["default_tier"] == "cheap", f"expected cheap; got {reviewer.get('default_tier')}"
assert "model" not in reviewer, f"v1 model: key should be removed after rename; got {reviewer}"
EOF
}

@test "M7.2 agent rename: model: opus stays as model: (opus not a tier)" {
    "$PYTHON_BIN" "$CLI" "$FIXTURES/v1-happy-path.yaml" -o "$OUT"
    _python_assert <<'EOF'
import os
from ruamel.yaml import YAML
y = YAML(typ='safe')
with open(os.environ["OUT"]) as f:
    data = y.load(f)
arch = data["agents"]["designing-architecture"]
# 'opus' is a custom alias, not one of {max, cheap, mid, tiny}, so the
# migrator MUST keep model: rather than rename to default_tier:
assert arch.get("model") == "opus", f"expected model: opus; got {arch}"
assert "default_tier" not in arch, f"opus is not a tier; should NOT rename. got {arch}"
EOF
}

# ---------------------------------------------------------------------------
# M8 — tier_groups.mappings empty → populated per §3.1.2
# ---------------------------------------------------------------------------

@test "M8.1 tier_groups: empty mappings populated to §3.1.2 defaults" {
    "$PYTHON_BIN" "$CLI" "$FIXTURES/v1-happy-path.yaml" -o "$OUT"
    _python_assert <<'EOF'
import os
from ruamel.yaml import YAML
y = YAML(typ='safe')
with open(os.environ["OUT"]) as f:
    data = y.load(f)
mappings = data["tier_groups"]["mappings"]
# §3.1.2 specifies max/cheap/mid/tiny each with 3 providers
for tier in ("max", "cheap", "mid", "tiny"):
    assert tier in mappings, f"missing tier {tier} in {mappings}"
    for provider in ("anthropic", "openai", "google"):
        assert provider in mappings[tier], f"missing {tier}.{provider}"
EOF
}

# ---------------------------------------------------------------------------
# M9 — model-permissions merging (DD-1 Option B)
# ---------------------------------------------------------------------------

@test "M9.1 permissions: cycle-026 entries merged into providers.<p>.models.<id>.permissions" {
    run "$PYTHON_BIN" "$CLI" "$FIXTURES/v1-happy-path.yaml" \
        -o "$OUT" \
        --model-permissions "$FIXTURES/cycle026-permissions.yaml"
    [[ "$status" -eq 0 ]]
    _python_assert <<'EOF'
import os
from ruamel.yaml import YAML
y = YAML(typ='safe')
with open(os.environ["OUT"]) as f:
    data = y.load(f)
gpt = data["providers"]["openai"]["models"]["gpt-5.5"]
assert "permissions" in gpt, f"expected permissions block; got {gpt}"
ts = gpt["permissions"]["trust_scopes"]
assert ts["data_access"] == "medium"
assert ts["financial"] == "none"
EOF
}

@test "M9.2 permissions: missing permissions arg leaves models without permissions block" {
    "$PYTHON_BIN" "$CLI" "$FIXTURES/v1-happy-path.yaml" -o "$OUT"
    _python_assert <<'EOF'
import os
from ruamel.yaml import YAML
y = YAML(typ='safe')
with open(os.environ["OUT"]) as f:
    data = y.load(f)
gpt = data["providers"]["openai"]["models"]["gpt-5.5"]
# permissions block is optional in cycle-099 v2; absent without --model-permissions
assert "permissions" not in gpt, f"unexpected permissions block; got {gpt}"
EOF
}

# ---------------------------------------------------------------------------
# M10 — CLI exit codes + report
# ---------------------------------------------------------------------------

@test "M10.1 exit: 0 on successful migration" {
    run "$PYTHON_BIN" "$CLI" "$FIXTURES/v1-happy-path.yaml" -o "$OUT"
    [[ "$status" -eq 0 ]]
}

@test "M10.2 exit: 78 on post-migration validation failure" {
    run "$PYTHON_BIN" "$CLI" "$FIXTURES/v1-invalid-context-window.yaml" -o "$OUT"
    [[ "$status" -eq 78 ]]
}

@test "M10.3 exit: 78 on unsupported schema_version" {
    run "$PYTHON_BIN" "$CLI" "$FIXTURES/v3-future.yaml" -o "$OUT"
    [[ "$status" -eq 78 ]]
}

@test "M10.4 report: --report-format json produces valid JSON" {
    # Stream stdout into a file so apostrophes / quotes in the JSON cannot
    # break the python -c string interpolation (review remediation G-M1).
    # BB iter-2 F2 follow-up: even the file path is passed via env var so a
    # mktemp-d output containing shell metachars cannot inject into Python.
    run "$PYTHON_BIN" "$CLI" "$FIXTURES/v1-with-rename.yaml" -o "$OUT" --report-format json
    [[ "$status" -eq 0 ]]
    local payload="$WORK_DIR/report.json"
    printf '%s' "$output" > "$payload"
    PAYLOAD="$payload" "$PYTHON_BIN" -c '
import json, os
with open(os.environ["PAYLOAD"]) as f:
    data = json.load(f)
assert "changes" in data, f"expected changes field; got {data}"
assert any(c["kind"] == "rename" for c in data["changes"]), f"expected at least one rename; got {data}"
'
}

@test "M10.5 report: dry-run mode does not write output file" {
    rm -f "$OUT"
    run "$PYTHON_BIN" "$CLI" "$FIXTURES/v1-happy-path.yaml" -o "$OUT" --dry-run
    [[ "$status" -eq 0 ]]
    [[ ! -f "$OUT" ]]
}

# ---------------------------------------------------------------------------
# M11 — YAML structure preservation (ruamel round-trip)
# ---------------------------------------------------------------------------

@test "M11.1 structure: ruamel round-trip preserves key ordering" {
    "$PYTHON_BIN" "$CLI" "$FIXTURES/v1-happy-path.yaml" -o "$OUT"
    # The first non-comment, non-empty line must be schema_version: 2 (we
    # prepend it). Subsequent top-level keys appear in v1 order: providers,
    # aliases, ..., defaults.
    local first_key
    first_key="$(grep -E '^[a-z_]+:' "$OUT" | head -1 | cut -d: -f1)"
    [[ "$first_key" = "schema_version" ]]
}

@test "M11.2 structure: pure function migrate_v1_to_v2 is library-callable" {
    # The lib filename has dashes (cycle-099 file-naming convention) so we
    # load it via importlib.util.spec_from_file_location, mirroring the CLI.
    _python_assert <<'EOF'
import importlib.util, os
lib = os.path.join(
    os.environ["PROJECT_ROOT"],
    ".claude/scripts/lib/model-config-migrate.py",
)
spec = importlib.util.spec_from_file_location("mcm", lib)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
assert callable(m.migrate_v1_to_v2)
assert callable(m.detect_schema_version)
assert hasattr(m, "TIER_TAGS")
assert hasattr(m, "TIER_GROUPS_DEFAULTS")
EOF
}

# ---------------------------------------------------------------------------
# M12 — CLI safety: missing input, write-failure
# ---------------------------------------------------------------------------

@test "M12.1 safety: missing input file errors out" {
    run "$PYTHON_BIN" "$CLI" "$WORK_DIR/does-not-exist.yaml" -o "$OUT"
    [[ "$status" -ne 0 ]]
}

@test "M12.2 safety: input file is malformed YAML" {
    local bad="$WORK_DIR/bad.yaml"
    printf 'providers:\n  - this is\n    : malformed yaml: [\n' > "$bad"
    run "$PYTHON_BIN" "$CLI" "$bad" -o "$OUT"
    [[ "$status" -ne 0 ]]
}

# ---------------------------------------------------------------------------
# M13 — Security hardening (review remediation)
# ---------------------------------------------------------------------------

@test "M13.1 hardening: !!python/object tag does not execute (typ='rt' safe)" {
    # C-M2 + BB iter-2 F1: confirm ruamel's round-trip loader does not execute
    # python tags. Use a per-test sentinel under WORK_DIR (mktemp-d) so
    # parallel bats runs don't race on a shared /tmp path.
    local rce_sentinel="$WORK_DIR/rce-canary"
    local fixture="$WORK_DIR/malicious.yaml"
    sed "s|/tmp/loa-rce-test|$rce_sentinel|g" \
        "$FIXTURES/v1-malicious-python-tag.yaml" > "$fixture"
    run "$PYTHON_BIN" "$CLI" "$fixture" -o "$OUT"
    # We don't assert exit code (ruamel rt may either reject the tag or store
    # it as opaque); we DO assert the malicious side effect did not happen.
    [[ ! -f "$rce_sentinel" ]]
}

@test "M13.2 hardening: --output refuses to follow an existing symlink" {
    # C-H2: ensure the migrator rejects a symlink target rather than clobbering
    # the symlink's destination.
    local victim="$WORK_DIR/victim.yaml"
    local link="$WORK_DIR/link.yaml"
    printf 'sentinel: untouched\n' > "$victim"
    ln -s "$victim" "$link"
    run "$PYTHON_BIN" "$CLI" "$FIXTURES/v1-happy-path.yaml" -o "$link"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"OUTPUT-IS-SYMLINK"* ]]
    # Sentinel intact: the migrator did NOT write through the symlink.
    grep -q '^sentinel: untouched$' "$victim"
}

@test "M13.3 hardening: output file mode is 0600 (owner-only)" {
    # C-L1: even on a permissive umask, the output should be owner-only.
    # F5 review remediation: BSD stat returns full mode like '100600'; trim
    # to the trailing 3 octal digits so this test passes on macOS too.
    local prior_umask
    prior_umask="$(umask)"
    umask 0022
    run "$PYTHON_BIN" "$CLI" "$FIXTURES/v1-happy-path.yaml" -o "$OUT"
    umask "$prior_umask"
    [[ "$status" -eq 0 ]]
    local mode
    if mode="$(stat -c '%a' "$OUT" 2>/dev/null)"; then
        :  # Linux: %a returns octal mode without leading bits
    else
        mode="$(stat -f '%Lp' "$OUT")"  # BSD/macOS: %Lp returns lower 12 bits as octal
    fi
    [[ "$mode" = "600" ]]
}

# ---------------------------------------------------------------------------
# M14 — tier_groups population edge cases (review remediation G-H2 + G-H3)
# ---------------------------------------------------------------------------

@test "M14.1 tier_groups: absent v1 section produces fully-populated v2" {
    local minimal="$WORK_DIR/minimal-v1.yaml"
    cat > "$minimal" <<'EOF'
providers:
  openai:
    type: openai
    endpoint: "https://api.openai.com/v1"
    models:
      gpt-5.5:
        capabilities: [chat]
        context_window: 200000
        endpoint_family: chat
EOF
    run "$PYTHON_BIN" "$CLI" "$minimal" -o "$OUT"
    [[ "$status" -eq 0 ]]
    _python_assert <<'EOF'
import os
from ruamel.yaml import YAML
y = YAML(typ='safe')
with open(os.environ["OUT"]) as f:
    data = y.load(f)
mappings = data["tier_groups"]["mappings"]
for tier in ("max", "cheap", "mid", "tiny"):
    assert tier in mappings, f"missing tier {tier}; got {mappings}"
    for provider in ("anthropic", "openai", "google"):
        assert provider in mappings[tier], f"missing {tier}.{provider}; got {mappings}"
EOF
}

@test "M14.2 tier_groups: partial v1 mappings get filled (operator entries preserved)" {
    local partial="$WORK_DIR/partial-v1.yaml"
    cat > "$partial" <<'EOF'
providers:
  openai:
    type: openai
    endpoint: "https://api.openai.com/v1"
    models:
      gpt-5.5:
        capabilities: [chat]
        context_window: 200000
        endpoint_family: chat
tier_groups:
  mappings:
    max:
      anthropic: my-custom-opus
  denylist: [some-alias]
  max_cost_per_session_micro_usd: 1000000
EOF
    run "$PYTHON_BIN" "$CLI" "$partial" -o "$OUT"
    [[ "$status" -eq 0 ]]
    _python_assert <<'EOF'
import os
from ruamel.yaml import YAML
y = YAML(typ='safe')
with open(os.environ["OUT"]) as f:
    data = y.load(f)
m = data["tier_groups"]["mappings"]
# Operator-supplied entry preserved verbatim
assert m["max"]["anthropic"] == "my-custom-opus", f"operator entry overwritten; got {m}"
# Missing tiers filled
assert "openai" in m["max"], f"missing max.openai default; got {m}"
assert "cheap" in m, f"missing cheap tier; got {m}"
# Operator's other fields preserved
assert data["tier_groups"]["denylist"] == ["some-alias"]
assert data["tier_groups"]["max_cost_per_session_micro_usd"] == 1000000
EOF
}

# ---------------------------------------------------------------------------
# M15 — Pure-function semantics (review remediation G-H1)
# ---------------------------------------------------------------------------

@test "M15.1 lib: migrate_v1_to_v2 does not mutate caller's dict" {
    _python_assert <<'EOF'
import importlib.util, os
lib = os.path.join(
    os.environ["PROJECT_ROOT"],
    ".claude/scripts/lib/model-config-migrate.py",
)
spec = importlib.util.spec_from_file_location("mcm", lib)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

# A v1 dict with nested mutable children
v1 = {
    "providers": {
        "openai": {
            "type": "openai",
            "endpoint": "https://api.openai.com/v1",
            "models": {
                "gpt-5.5": {
                    "capabilities": ["chat"],
                    "context_window": 200000,
                    "endpoint_family": "chat",
                    "endpoint_class": "chat",  # legacy -- migrator should pop
                }
            },
        }
    },
    "agents": {
        "x": {"model": "cheap"}  # tier-tag -- migrator should rename to default_tier
    },
}
import copy
v1_before = copy.deepcopy(v1)
v2, _report = m.migrate_v1_to_v2(v1)

# Caller's dict survives untouched: endpoint_class still present, model: cheap still present
assert v1 == v1_before, f"input dict was mutated.\nbefore: {v1_before}\nafter:  {v1}"
# But the v2 output has the migrations applied
gpt = v2["providers"]["openai"]["models"]["gpt-5.5"]
assert "endpoint_class" not in gpt, f"v2 should have endpoint_class popped; got {gpt}"
agent = v2["agents"]["x"]
assert "default_tier" in agent and agent["default_tier"] == "cheap"
EOF
}

# ---------------------------------------------------------------------------
# M16 — Distinct error code for operator-supplied invalid v2 (G-M4)
# ---------------------------------------------------------------------------

@test "M16.1 errors: invalid-v2 input emits CONFIG-V2-INVALID, not MIGRATION-PRODUCED" {
    local bad_v2="$WORK_DIR/bad-v2.yaml"
    cat > "$bad_v2" <<'EOF'
schema_version: 2
providers:
  openai:
    type: openai
    endpoint: "https://api.openai.com/v1"
    models:
      tiny-toy:
        capabilities: [chat]
        context_window: 500
        endpoint_family: chat
EOF
    run "$PYTHON_BIN" "$CLI" "$bad_v2" -o "$OUT"
    [[ "$status" -eq 78 ]]
    [[ "$output" == *"CONFIG-V2-INVALID"* ]]
    [[ "$output" != *"MIGRATION-PRODUCED-INVALID-V2"* ]]
}

@test "M16.2 errors: invalid v1 → invalid v2 emits MIGRATION-PRODUCED-INVALID-V2" {
    # Re-affirm the original error code is unchanged when the migrator IS
    # responsible for producing the bad v2.
    run "$PYTHON_BIN" "$CLI" "$FIXTURES/v1-invalid-context-window.yaml" -o "$OUT"
    [[ "$status" -eq 78 ]]
    [[ "$output" == *"MIGRATION-PRODUCED-INVALID-V2"* ]]
    [[ "$output" != *"CONFIG-V2-INVALID"* ]]
}

# ---------------------------------------------------------------------------
# M17 — version_bump emitted on v1→v2 (review remediation G-M2)
# ---------------------------------------------------------------------------

@test "M17.1 report: v1→v2 always emits a version_bump entry" {
    # F6 review remediation: assert version_bump kind appears in the report,
    # not the more general 'schema_version: 2' string (which leaked from the
    # original tautological OR — passed for the wrong reason on any input).
    # BB iter-2 F2 follow-up: pass the payload path via env var to avoid
    # interpolating it into the python -c source string.
    run "$PYTHON_BIN" "$CLI" "$FIXTURES/v1-with-rename.yaml" -o "$OUT" --report-format json
    [[ "$status" -eq 0 ]]
    local payload="$WORK_DIR/v17-report.json"
    printf '%s' "$output" > "$payload"
    PAYLOAD="$payload" "$PYTHON_BIN" -c '
import json, os
with open(os.environ["PAYLOAD"]) as f:
    data = json.load(f)
assert any(c.get("kind") == "version_bump" for c in data.get("changes", [])), \
    f"expected at least one version_bump entry; got {data}"
'
}

# ---------------------------------------------------------------------------
# M18 — Strict additionalProperties (review remediation C-H1)
# ---------------------------------------------------------------------------

@test "M18.1 strict-mode: top-level operator-injected key triggers MIGRATION-PRODUCED-INVALID-V2" {
    # The migrator sweeps unknown top-level keys to _unknown_v1_fields, so a
    # v1 input with an unknown key migrates cleanly. To exercise the schema's
    # additionalProperties:false at root we hand it a v2 file with an
    # unknown top-level key.
    local bad_v2="$WORK_DIR/bad-extra-top.yaml"
    cat > "$bad_v2" <<'EOF'
schema_version: 2
operator_injected_top: PWNED
providers:
  openai:
    type: openai
    endpoint: "https://api.openai.com/v1"
    models:
      gpt-5.5:
        capabilities: [chat]
        context_window: 200000
        endpoint_family: chat
EOF
    run "$PYTHON_BIN" "$CLI" "$bad_v2" -o "$OUT"
    [[ "$status" -eq 78 ]]
    [[ "$output" == *"CONFIG-V2-INVALID"* ]]
    [[ "$output" == *"operator_injected_top"* ]]
}

@test "M18.2 strict-mode: model-level operator-injected key rejected" {
    local bad_v2="$WORK_DIR/bad-extra-model.yaml"
    cat > "$bad_v2" <<'EOF'
schema_version: 2
providers:
  openai:
    type: openai
    endpoint: "https://api.openai.com/v1"
    models:
      gpt-5.5:
        capabilities: [chat]
        context_window: 200000
        endpoint_family: chat
        injected_field: PWNED
EOF
    run "$PYTHON_BIN" "$CLI" "$bad_v2" -o "$OUT"
    [[ "$status" -eq 78 ]]
    [[ "$output" == *"injected_field"* ]]
}

@test "M18.3 strict-mode: agentBinding rejects tier-tag in model: field" {
    local bad_v2="$WORK_DIR/bad-tier-in-model.yaml"
    cat > "$bad_v2" <<'EOF'
schema_version: 2
providers:
  openai:
    type: openai
    endpoint: "https://api.openai.com/v1"
    models:
      gpt-5.5:
        capabilities: [chat]
        context_window: 200000
        endpoint_family: chat
agents:
  test_skill:
    model: tiny
EOF
    run "$PYTHON_BIN" "$CLI" "$bad_v2" -o "$OUT"
    [[ "$status" -eq 78 ]]
}

# ---------------------------------------------------------------------------
# M19 — KF-006 regression coverage: max_output_tokens + max_input_tokens are
#       valid v2 fields (cycle-102 Sprint 1F closure)
# ---------------------------------------------------------------------------

@test "M19.1 KF-006: max_output_tokens passes v2 validation on per-model entries" {
    local v1="$WORK_DIR/v1-with-max-output.yaml"
    cat > "$v1" <<'EOF'
providers:
  openai:
    type: openai
    endpoint: "https://api.openai.com/v1"
    models:
      gpt-5.5-pro:
        capabilities: [chat, tools, function_calling, code]
        context_window: 400000
        endpoint_family: responses
        max_output_tokens: 32000
        token_param: max_completion_tokens
EOF
    run "$PYTHON_BIN" "$CLI" "$v1" -o "$OUT"
    [[ "$status" -eq 0 ]]
    # Field MUST be carried through unchanged (not stripped or archived)
    _python_assert <<'EOF'
import os
from ruamel.yaml import YAML
y = YAML(typ='safe')
with open(os.environ["OUT"]) as f:
    data = y.load(f)
m = data["providers"]["openai"]["models"]["gpt-5.5-pro"]
assert m["max_output_tokens"] == 32000, m
# Must NOT be archived (the bug class would have routed the field there
# in some buggy migrator variants)
assert "max_output_tokens" not in (m.get("_archived_v1_fields") or {})
EOF
}

@test "M19.2 KF-006: max_input_tokens passes v2 validation (Sprint 1F new field)" {
    local v1="$WORK_DIR/v1-with-max-input.yaml"
    cat > "$v1" <<'EOF'
providers:
  openai:
    type: openai
    endpoint: "https://api.openai.com/v1"
    models:
      gpt-5.5-pro:
        capabilities: [chat]
        context_window: 400000
        endpoint_family: responses
        max_output_tokens: 32000
        max_input_tokens: 24000
EOF
    run "$PYTHON_BIN" "$CLI" "$v1" -o "$OUT"
    [[ "$status" -eq 0 ]]
    _python_assert <<'EOF'
import os
from ruamel.yaml import YAML
y = YAML(typ='safe')
with open(os.environ["OUT"]) as f:
    data = y.load(f)
m = data["providers"]["openai"]["models"]["gpt-5.5-pro"]
assert m["max_input_tokens"] == 24000
assert m["max_output_tokens"] == 32000
EOF
}

@test "M19.3 KF-006: production model-config.yaml smoke-migrates without 78" {
    # The exact failure class from KF-006: production yaml's
    # max_output_tokens fields were rejected post-migration. With the
    # schema bump, the production yaml should now smoke-migrate clean.
    run "$PYTHON_BIN" "$CLI" "$PROJECT_ROOT/.claude/defaults/model-config.yaml" -o "$OUT"
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"MIGRATION-PRODUCED-INVALID-V2"* ]]
}
