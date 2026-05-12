#!/usr/bin/env bats
# =============================================================================
# kind-cli-cross-runtime.bats — T2.13 cross-runtime parity for kind: cli entries
# =============================================================================
# Cycle-104 sprint-2 T2.13 (SDD §7.1). Extends cycle-099 sprint-1E.c.1's
# cross-runtime corpus pattern: bash (yq+jq), Python (PyYAML), and TypeScript
# (npx tsx + yaml package) readers MUST produce byte-equal canonical JSON
# for every `kind: cli` adapter entry in `.claude/defaults/model-config.yaml`.
#
# Canonicalization: JCS-style compact JSON with deeply-sorted keys
# (sort_keys=true, no spaces). Each runtime emits the same shape and
# byte-equality is asserted at the file level.
#
# Why this matters: cycle-104 introduced the `kind: cli` discriminator
# on adapter entries. The Python `chain_resolver` is the canonical reader;
# the bash orchestrator and the TS BB cheval-delegate are downstream
# consumers. A YAML parser drift (e.g. a future runtime emitting `kind`
# as a number, dropping the field on unknown-key strict modes, or
# silently re-ordering list elements) would break the contract WITHOUT
# producing a Python-side failure. This test catches that class
# pre-emptively.
#
# Hermetic: no network. Requires `yq` (v4+), `python3`, and `npx tsx`
# which are CI-resident.

setup_file() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    export MODEL_CONFIG="$PROJECT_ROOT/.claude/defaults/model-config.yaml"
}

setup() {
    _tool_check() {
        local tool="$1"
        if ! command -v "$tool" >/dev/null 2>&1; then
            if [[ -n "${CI:-}" ]]; then
                printf '[kind-cli-cross-runtime] FATAL: %s not present in CI\n' "$tool" >&2
                return 1
            else
                skip "$tool not present"
            fi
        fi
    }
    _tool_check yq
    _tool_check jq
    _tool_check python3
    _tool_check npx

    WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/t213-XXXXXX")"
    chmod 700 "$WORK_DIR"
    [[ -f "$MODEL_CONFIG" ]] || skip "model-config.yaml not present at $MODEL_CONFIG"

    # Canonical JSON via jq's --sort-keys + --compact-output. Used by the
    # bash + python emitters. The TS emitter uses a hand-rolled deep-sort
    # to avoid pulling in another JCS dep.
    JCS_FILTER='--compact-output --sort-keys'
}

teardown() {
    if [[ -n "${WORK_DIR:-}" && -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
}

# Helper: emit canonical JSON of every kind:cli entry via bash (yq → jq)
_emit_bash() {
    # yq's -o=json + jq -cS gives us canonical JSON. The query picks every
    # adapter entry under .providers.*.models.* whose .kind == "cli" and
    # returns a list of [provider, alias, body] triples for stable ordering.
    yq -o=json '.providers' "$MODEL_CONFIG" \
        | jq -c '
            [
              to_entries[] as $p
              | $p.value.models // {}
              | to_entries[]
              | select(.value.kind == "cli")
              | {provider: $p.key, alias: .key, body: .value}
            ]
            | sort_by(.provider + ":" + .alias)
          ' \
        | jq --sort-keys --compact-output .
}

# Helper: emit canonical JSON via Python (PyYAML)
_emit_python() {
    python3 - "$MODEL_CONFIG" <<'PY'
import json, sys, yaml
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    cfg = yaml.safe_load(f)
out = []
providers = cfg.get('providers', {}) or {}
for pname, pdata in providers.items():
    models = (pdata or {}).get('models', {}) or {}
    for alias, body in models.items():
        if isinstance(body, dict) and body.get('kind') == 'cli':
            out.append({'provider': pname, 'alias': alias, 'body': body})
out.sort(key=lambda e: f"{e['provider']}:{e['alias']}")
print(json.dumps(out, sort_keys=True, separators=(',', ':')))
PY
}

# Helper: emit canonical JSON via TypeScript-ish runtime (CommonJS Node).
# We use require() rather than ESM import because NODE_PATH (which lets
# us find the system or vendored `yaml` package) is honored only by the
# CJS resolver. The shape of the reader is identical to what BB's
# adapter-factory.ts does at runtime — yaml.parse + walk + filter on
# kind:cli — so this is a representative cross-runtime fidelity check.
_emit_typescript() {
    local script="$WORK_DIR/emit-ts.cjs"
    cat > "$script" <<'TS'
const fs = require("fs");
const path = require("path");

// Resolve `yaml` from several known locations so the test runs whether
// or not the developer ran `npm install` in the BB skill yet. Order:
//   1. BB skill's node_modules (if vendored locally)
//   2. project-root node_modules
//   3. Node's standard resolver (NODE_PATH + system paths)
const candidates = [
    path.join(__dirname, "..", "..", ".claude", "skills", "bridgebuilder-review", "node_modules", "yaml"),
    path.join(process.cwd(), "node_modules", "yaml"),
];
let yamlPkg = null;
for (const c of candidates) {
    try {
        yamlPkg = require(c);
        break;
    } catch (_) {}
}
if (!yamlPkg) yamlPkg = require("yaml");

function canon(value) {
    if (Array.isArray(value)) return value.map(canon);
    if (value !== null && typeof value === "object") {
        const out = {};
        for (const k of Object.keys(value).sort()) out[k] = canon(value[k]);
        return out;
    }
    return value;
}

const cfg = yamlPkg.parse(fs.readFileSync(process.argv[2], "utf-8")) || {};
const providers = cfg.providers || {};
const out = [];
for (const [pname, pdata] of Object.entries(providers)) {
    const models = (pdata && pdata.models) || {};
    for (const [alias, body] of Object.entries(models)) {
        if (body && typeof body === "object" && body.kind === "cli") {
            out.push({ provider: pname, alias, body });
        }
    }
}
out.sort((a, b) => (`${a.provider}:${a.alias}`).localeCompare(`${b.provider}:${b.alias}`));
process.stdout.write(JSON.stringify(canon(out)));
TS
    NODE_PATH="${NODE_PATH:+$NODE_PATH:}/usr/share/nodejs:/usr/lib/node_modules" \
        node "$script" "$MODEL_CONFIG"
}

# ---- T2.13 invariants ------------------------------------------------------

@test "T2.13-1: bash emitter finds at least one kind:cli entry" {
    local out
    out=$(_emit_bash)
    [ -n "$out" ]
    # Must be a non-empty array
    run jq 'type == "array" and length >= 1' <<< "$out"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "T2.13-2: python emitter matches bash emitter byte-for-byte" {
    local bash_out python_out
    bash_out=$(_emit_bash)
    python_out=$(_emit_python)
    if [[ "$bash_out" != "$python_out" ]]; then
        echo "--- bash (len=${#bash_out}) ---" >&2
        echo "$bash_out" >&2
        echo "--- python (len=${#python_out}) ---" >&2
        echo "$python_out" >&2
        diff <(echo "$bash_out") <(echo "$python_out") >&2 || true
        false
    fi
}

@test "T2.13-3: typescript emitter matches python emitter byte-for-byte" {
    local python_out ts_out
    python_out=$(_emit_python)
    ts_out=$(_emit_typescript)
    if [[ "$python_out" != "$ts_out" ]]; then
        echo "--- python ---" >&2; echo "$python_out" >&2
        echo "--- typescript ---" >&2; echo "$ts_out" >&2
        diff <(echo "$python_out") <(echo "$ts_out") >&2 || true
        false
    fi
}

@test "T2.13-4: all three kind:cli aliases present (claude / codex / gemini)" {
    # Pins that the canonical chain terminals (T2.4) are all declared.
    # A future YAML edit that drops one would silently regress the
    # cli-only mode for that provider.
    local out
    out=$(_emit_python)
    run jq -r '[.[].alias] | sort | join(",")' <<< "$out"
    [ "$status" -eq 0 ]
    [ "$output" = "claude-headless,codex-headless,gemini-headless" ]
}

@test "T2.13-5: every kind:cli entry has a non-empty capabilities array" {
    # Capability gate depends on this — an empty capabilities list would
    # quietly skip the entry on every capability-bearing request.
    local out
    out=$(_emit_python)
    run jq -e '
        all(
            .body.capabilities != null
            and (.body.capabilities | type == "array")
            and (.body.capabilities | length >= 1)
        )
    ' <<< "$out"
    [ "$status" -eq 0 ]
}

@test "T2.13-6: kind:cli entries have NO pricing block (CLI uses operator subscription)" {
    # YAML schema invariant: pricing entries imply per-call HTTP metering;
    # CLI adapters bill against the operator's subscription and MUST NOT
    # carry pricing — otherwise the cost-tracker double-counts.
    local out
    out=$(_emit_python)
    run jq -e 'all((.body | has("pricing")) | not)' <<< "$out"
    [ "$status" -eq 0 ]
}
