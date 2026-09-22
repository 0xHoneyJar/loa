#!/usr/bin/env bash
# =============================================================================
# tools/regen-model-artifacts.sh — regenerate every artifact derived from
# .claude/defaults/model-config.yaml in ONE deterministic sequence.
#
# cycle-124 FR-3 / SDD §2.1. Before this script, a catalog edit needed four
# separately remembered steps and CI caught the forgotten one a push later.
#
# Sequence (regen mode):
#   1. .claude/scripts/gen-adapter-maps.sh        → .claude/scripts/generated-model-maps.sh
#   2. npm run build (bridgebuilder-review)      → resources/config.generated.ts,
#                                                   resources/core/truncation.generated.ts,
#                                                   resources/lib/*.generated.ts,
#                                                   resources/dist/** + dist/.build-manifest.json
#      (`build` runs gen-bb-registry first, then tsc, then the dist manifest)
#   3. sha256 of the yaml                        → .claude/defaults/model-config.yaml.checksum
#   4. self --check                              (proves the tree is drift-free afterwards)
#
# --check runs the drift gates only, writing nothing:
#   gen-adapter-maps.sh --check · npm run gen-bb-registry:check ·
#   tools/check-bb-dist-fresh.sh --check · checksum == sha256(yaml)
#
# Exit codes: 0 in sync (or regenerated) · 1 drift / a step failed · 2 usage ·
#             3 toolchain missing (npm / node / bridgebuilder node_modules) — NOT a drift result
# Toolchain pins: grimoires/loa/runbooks/codegen-toolchain.md
# Idempotence is pinned by tests/unit/cycle-124-anthropic-catalog.bats.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
YAML="$ROOT/.claude/defaults/model-config.yaml"
CHECKSUM="$YAML.checksum"
BB_DIR="$ROOT/.claude/skills/bridgebuilder-review"

usage() {
    sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

mode=regen
if [ "$#" -gt 1 ]; then
    echo "[regen-model-artifacts] error: at most one argument" >&2
    exit 2
fi
case "${1:-}" in
    "") ;;
    --check) mode=check ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[regen-model-artifacts] error: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
esac

step() { printf '[regen-model-artifacts] %s\n' "$*" >&2; }

# A missing toolchain is reported as 3, never as drift (1): CI without `npm ci`
# and a fresh clone must not read as "the catalog drifted".
precheck_toolchain() {
    local missing=()
    command -v npm >/dev/null 2>&1 || missing+=("npm")
    command -v node >/dev/null 2>&1 || missing+=("node")
    [ -d "$BB_DIR/node_modules" ] || missing+=("$BB_DIR/node_modules (run: npm ci in that directory)")
    if [ "${#missing[@]}" -gt 0 ]; then
        step "TOOLCHAIN: missing ${missing[*]} — cannot run the drift gates (exit 3, not a drift result)"
        return 3
    fi
}

check_checksum() {
    local recorded actual
    recorded="$(tr -d '[:space:]' < "$CHECKSUM" 2>/dev/null || true)"
    actual="$(sha256sum "$YAML" | awk '{print $1}')"
    if [ "$recorded" != "$actual" ]; then
        step "DRIFT: model-config.yaml.checksum ($recorded) != sha256(yaml) ($actual)"
        return 1
    fi
}

run_checks() {
    local rc=0
    step "check 1/4 gen-adapter-maps --check"
    bash "$ROOT/.claude/scripts/gen-adapter-maps.sh" --check || rc=1
    step "check 2/4 gen-bb-registry --check"
    (cd "$BB_DIR" && npm run --silent gen-bb-registry:check) || rc=1
    step "check 3/4 check-bb-dist-fresh --check"
    bash "$ROOT/tools/check-bb-dist-fresh.sh" --check || rc=1
    step "check 4/4 checksum"
    check_checksum || rc=1
    return "$rc"
}

precheck_toolchain || exit 3

if [ "$mode" = check ]; then
    if run_checks; then
        step "OK: every generated artifact matches $YAML"
        exit 0
    fi
    step "regenerate with: bash tools/regen-model-artifacts.sh"
    exit 1
fi

step "regen 1/3 gen-adapter-maps"
bash "$ROOT/.claude/scripts/gen-adapter-maps.sh"
step "regen 2/3 npm run build (gen-bb-registry → tsc → dist manifest)"
(cd "$BB_DIR" && npm run --silent build)
step "regen 3/3 checksum"
sha256sum "$YAML" | awk '{print $1}' > "$CHECKSUM"
step "verifying"
if run_checks; then
    step "OK: regenerated and drift-free"
    exit 0
fi
step "FAILED: a drift gate is still red after regeneration (toolchain drift?)"
exit 1
