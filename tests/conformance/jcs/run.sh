#!/usr/bin/env bash
# =============================================================================
# tests/conformance/jcs/run.sh — RFC 8785 JCS multi-language conformance gate.
#
# cycle-098 Sprint 1 (IMP-001 HIGH_CONSENSUS 736). Per SDD §6 Sprint 1 ACs:
#
#   - lib/jcs.sh (bash), .claude/adapters/loa_cheval/jcs.py (Python),
#     .claude/scripts/lib/jcs.mjs (Node) all produce byte-identical output for
#     the test vector corpus at tests/conformance/jcs/test-vectors.json.
#   - This script fails the PR on byte-divergence between any two adapters.
#
# Exit codes:
#   0 — all 3 adapters produce byte-identical output for every vector
#   1 — divergence detected (full diff printed)
#   2 — adapter unavailable (e.g., rfc8785 not installed)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

VECTORS="${SCRIPT_DIR}/test-vectors.json"
BASH_LIB="${REPO_ROOT}/lib/jcs.sh"
PY_ADAPTER="${REPO_ROOT}/.claude/adapters"
NODE_LIB="${REPO_ROOT}/.claude/scripts/lib/jcs.mjs"

# Sanity checks.
if [[ ! -f "$VECTORS" ]]; then
    echo "FATAL: test-vectors.json missing at $VECTORS" >&2
    exit 2
fi
if [[ ! -f "$BASH_LIB" ]]; then
    echo "FATAL: lib/jcs.sh missing at $BASH_LIB" >&2
    exit 2
fi
if [[ ! -f "$NODE_LIB" ]]; then
    echo "FATAL: jcs.mjs missing at $NODE_LIB" >&2
    exit 2
fi

# Verify all 3 adapters are available.
echo "==> Checking adapter availability..."

if ! bash "$BASH_LIB" --check >/dev/null 2>&1; then
    echo "FATAL: bash adapter unavailable. Run: bash $BASH_LIB --check" >&2
    exit 2
fi
echo "    bash       ok"

if ! python3 -c 'import sys; sys.path.insert(0, "'"$PY_ADAPTER"'"); from loa_cheval.jcs import available; sys.exit(0 if available() else 1)' >/dev/null 2>&1; then
    echo "FATAL: Python adapter unavailable. Install with: pip install rfc8785" >&2
    exit 2
fi
echo "    python     ok"

# Node — the canonicalize package must be installed in a discoverable location.
if ! ( cd "$SCRIPT_DIR" && node -e 'import("'"$NODE_LIB"'").then(async (m) => { const ok = await m.available(); process.exit(ok?0:1); });' ) >/dev/null 2>&1; then
    echo "FATAL: Node adapter unavailable. Run: cd $SCRIPT_DIR && npm install" >&2
    exit 2
fi
echo "    node       ok"

# Run the vectors through each adapter and compare bytes.
echo "==> Running test vector corpus..."

vector_count="$(python3 -c 'import json; print(len(json.load(open("'"$VECTORS"'"))["vectors"]))')"
echo "    $vector_count vectors loaded"

# Build a single Python driver that produces all 3 adapters' outputs for every
# vector and computes a diff. This is dramatically faster than shelling out
# per-vector and avoids subshell startup overhead.
fail=0
DRIVER_OUT="$(
    REPO_ROOT="$REPO_ROOT" \
    VECTORS="$VECTORS" \
    BASH_LIB="$BASH_LIB" \
    PY_ADAPTER="$PY_ADAPTER" \
    NODE_LIB="$NODE_LIB" \
    SCRIPT_DIR="$SCRIPT_DIR" \
    python3 - <<'PY'
import json, os, subprocess, sys

repo_root = os.environ["REPO_ROOT"]
vectors_path = os.environ["VECTORS"]
bash_lib = os.environ["BASH_LIB"]
py_adapter = os.environ["PY_ADAPTER"]
node_lib = os.environ["NODE_LIB"]
script_dir = os.environ["SCRIPT_DIR"]

sys.path.insert(0, py_adapter)
from loa_cheval.jcs import canonicalize as py_canonicalize

with open(vectors_path) as f:
    corpus = json.load(f)

failures = []
for v in corpus["vectors"]:
    vid = v["id"]
    inp = v["input"]
    expected = v["expected"]
    raw = json.dumps(inp)

    # Bash adapter (via stdin).
    bash_out = subprocess.run(
        ["bash", bash_lib],
        input=raw.encode("utf-8"),
        capture_output=True,
        check=False,
    )
    if bash_out.returncode != 0:
        failures.append(f"{vid}: bash adapter failed: {bash_out.stderr.decode('utf-8', 'replace')}")
        continue
    bash_bytes = bash_out.stdout

    # Python adapter (in-process).
    py_bytes = py_canonicalize(inp)

    # Node adapter (subprocess; CWD must be where node_modules lives).
    node_out = subprocess.run(
        ["node", node_lib],
        input=raw.encode("utf-8"),
        capture_output=True,
        cwd=script_dir,
        check=False,
    )
    if node_out.returncode != 0:
        failures.append(f"{vid}: node adapter failed: {node_out.stderr.decode('utf-8', 'replace')}")
        continue
    node_bytes = node_out.stdout

    expected_bytes = expected.encode("utf-8")
    if bash_bytes != expected_bytes:
        failures.append(
            f"{vid}: bash divergence — got {bash_bytes!r}, expected {expected_bytes!r}"
        )
    if py_bytes != expected_bytes:
        failures.append(
            f"{vid}: python divergence — got {py_bytes!r}, expected {expected_bytes!r}"
        )
    if node_bytes != expected_bytes:
        failures.append(
            f"{vid}: node divergence — got {node_bytes!r}, expected {expected_bytes!r}"
        )

if failures:
    for f in failures:
        print(f"FAIL  {f}")
    print(f"\n{len(failures)} divergences across {len(corpus['vectors'])} vectors")
    sys.exit(1)
print(f"PASS  all 3 adapters byte-identical on {len(corpus['vectors'])} vectors")
sys.exit(0)
PY
)" || fail=1

echo "$DRIVER_OUT"

if [[ "$fail" -ne 0 ]]; then
    echo "==> CONFORMANCE FAILED" >&2
    exit 1
fi

echo "==> CONFORMANCE PASSED"
exit 0
