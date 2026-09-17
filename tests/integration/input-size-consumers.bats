#!/usr/bin/env bats
# =============================================================================
# tests/integration/input-size-consumers.bats
#
# cycle-124 Sprint 1 Task 1.4 — AC-3.5 input-size matrix across every consumer
# of the Anthropic input ceiling (SDD §3.2):
#   1. cheval pre-flight / legacy wall / context window — in-process matrix
#      (120K/160K/180K/200K/900K × gate on|off × streaming on|off), run via
#      pytest because `--dry-run` returns before the gate and
#      `--mock-fixture-dir` bypasses it (NOTES, 2026-09-17).
#   2. Bridgebuilder TOKEN_BUDGETS — the generated twin (dist/) carries
#      effective_input_ceiling − 20000 = 160000 for every Anthropic HTTP id,
#      getTokenBudget() serves it, and progressiveTruncate() on a 900K-token
#      fixture with an operator budget ABOVE the ceiling prepares ≤ 160K.
#   3. adversarial-review's Anthropic dissent budget is the same 160K figure.
# Nothing above the ceiling is ever dispatched by any consumer.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    BB_DIST="$PROJECT_ROOT/.claude/skills/bridgebuilder-review/dist"
    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="$(command -v python3)"
    fi
    export LOA_MODELINV_LOG_PATH="$BATS_TEST_TMPDIR/model-invoke.jsonl"
    export LOA_COST_LEDGER_PATH="$BATS_TEST_TMPDIR/cost-ledger.jsonl"
}

@test "AC-3.5/cheval: gate matrix — pre-flight owns >180K, 36K wall under the kill switch, nothing above the ceiling dispatched" {
    "$PYTHON_BIN" -c "import pytest" 2>/dev/null || skip "pytest not available"
    run "$PYTHON_BIN" -m pytest "$PROJECT_ROOT/.claude/adapters/tests/test_input_size_consumers.py" \
        -q -p no:cacheprovider
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    [[ "$output" == *"passed"* ]]
    [[ "$output" != *"failed"* ]]
}

@test "AC-3.5/BB: generated TOKEN_BUDGETS carry 160000 for every Anthropic HTTP id (dist twin)" {
    command -v node >/dev/null || skip "node not available"
    [ -f "$BB_DIST/core/truncation.generated.js" ] || skip "BB dist not built"
    run node --input-type=module -e "
import { GENERATED_TOKEN_BUDGETS } from '$BB_DIST/core/truncation.generated.js';
const ids = ['claude-fable-5-1','claude-fable-5','claude-opus-5','claude-opus-4-8','claude-opus-4-7','claude-opus-4-6','claude-sonnet-5','claude-sonnet-4-6','claude-sonnet-4-5-20250929','claude-haiku-4-5-20251001'];
for (const id of ids) {
  const b = GENERATED_TOKEN_BUDGETS[id];
  if (!b || b.maxInput !== 160000) { console.error('bad budget', id, JSON.stringify(b)); process.exit(1); }
}
if (GENERATED_TOKEN_BUDGETS['claude-headless'].maxInput !== 200000) process.exit(2);
console.log('OK');
"
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    [[ "$output" == *"OK"* ]]
}

@test "AC-3.5/BB: getTokenBudget serves the generated budget and progressiveTruncate caps a 900K fixture at ≤ 160K tokens" {
    command -v node >/dev/null || skip "node not available"
    [ -f "$BB_DIST/core/truncation.js" ] || skip "BB dist not built"
    run node --input-type=module -e "
import { getTokenBudget, progressiveTruncate, estimateTokens } from '$BB_DIST/core/truncation.js';
const model = 'claude-opus-5';
const budget = getTokenBudget(model);
if (budget.maxInput !== 160000) { console.error('getTokenBudget', JSON.stringify(budget)); process.exit(1); }
// 900K estimated tokens at coefficient 0.25 ⇒ 3.6M chars, spread over files so the
// progressive ladder has something to drop.
const files = [];
for (let i = 0; i < 9; i++) {
  files.push({ filename: 'src/big-' + i + '.ts', status: 'modified', additions: 1000, deletions: 0, patch: 'x'.repeat(400000) });
}
const before = files.reduce((n, f) => n + estimateTokens(f.patch, model), 0);
if (before < 900000) { console.error('fixture too small', before); process.exit(2); }
// Operator budget deliberately ABOVE cheval's ceiling — the clamp must win.
const result = progressiveTruncate(files, 300000, model, 0, 0);
const after = result.files.reduce((n, f) => n + estimateTokens(f.patch ?? '', model), 0);
if (after > 160000) { console.error('prepared', after, 'tokens > 160000 ceiling', JSON.stringify({level: result.level, files: result.files.length, totalBytes: result.totalBytes})); process.exit(3); }
console.log('OK before=' + before + ' after=' + after + ' level=' + result.level + ' kept=' + result.files.length);
"
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    [[ "$output" == *"OK before="* ]]
}

@test "AC-3.5/adversarial: Anthropic dissent input budget equals the BB figure (160000 = ceiling − 20K)" {
    run grep -E '^_ANTHROPIC_DISPATCH_INPUT_BUDGET=160000' "$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
    [ "$status" -eq 0 ]
    # and the catalog ceiling it derives from is 180000 on every Anthropic HTTP entry
    run "$PYTHON_BIN" -c "
import yaml
m = yaml.safe_load(open('$PROJECT_ROOT/.claude/defaults/model-config.yaml'))['providers']['anthropic']['models']
bad = [k for k, v in m.items() if v.get('auth_type') == 'http_api' and v.get('effective_input_ceiling') != 180000]
assert not bad, bad
print('OK')
"
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
}
