"""#1025: exercise the sixteen live consumers without any provider calls."""
import json
import os
from pathlib import Path
import subprocess

import pytest


REPO = Path(__file__).resolve().parents[2]
SCRIPTS = REPO / ".claude/scripts"
BAD_DOCUMENTS = ["", "{", "null", "{}", '{"tokens_used":0}\n{']


@pytest.fixture
def workspace(tmp_path):
    scripts = tmp_path / ".claude/scripts"
    scripts.mkdir(parents=True)
    # Real function bodies and dependencies; only unconditional CLI entrypoints
    # are removed from these disposable copies so phase functions can be called.
    for source in SCRIPTS.iterdir():
        target = scripts / source.name
        if source.name in {
            "scoring-engine.sh", "red-team-model-adapter.sh",
            "red-team-pipeline.sh", "flatline-orchestrator.sh",
        }:
            body = source.read_text()
            if body.endswith('\nmain "$@"\n'):
                body = body.removesuffix('\nmain "$@"\n') + "\n"
            target.write_text(body)
            target.chmod(0o755)
        elif source.name not in {"model-invoke", "model-adapter.sh", "flatline-mode-detect.sh"}:
            target.symlink_to(source, target_is_directory=source.is_dir())
    (tmp_path / ".claude/defaults").symlink_to(REPO / ".claude/defaults")
    (tmp_path / "doc.md").write_text("Local test document")
    (tmp_path / ".loa.config.yaml").write_text(
        "flatline_protocol:\n  enabled: true\n  autonomous_arbiter:\n"
        "    enabled: true\n    rotation: [opus, gpt, gemini]\n"
    )
    (tmp_path / "temp").mkdir()
    return tmp_path


def execute(workspace, script, body, **variables):
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1", PROJECT_ROOT=str(workspace),
               CASE_ROOT=str(workspace), REPO_ROOT=str(REPO))
    for key in list(env):
        if key.endswith("_API_KEY") or key.startswith("LOA_"):
            env.pop(key)
    env.update({key: str(value) for key, value in variables.items()})
    # A conditional caller disables implicit errexit in Bash functions.
    # Consumers must explicitly propagate parser failure in this context too.
    driver = f'''
source "$CASE_ROOT/.claude/scripts/{script}"
TEMP_DIR="$CASE_ROOT/temp"
{body}
'''
    return subprocess.run(["bash", "-c", driver], cwd=workspace, env=env,
                          capture_output=True, text=True, timeout=20)


def executable(path, body):
    path.write_text("#!/usr/bin/env bash\nset -eu\n" + body)
    path.chmod(0o755)


@pytest.mark.parametrize("attack", [False, True])
@pytest.mark.parametrize("voice", ["gpt", "opus"])
@pytest.mark.parametrize("bad", ["", "{", "null", "{}", '{"scores":{}}', '{"scores":[]}\n{'])
def test_scoring_rejects_unusable_document(workspace, attack, voice, bad):
    for name in ("gpt", "opus"):
        (workspace / f"{name}.json").write_text(
            bad if name == voice else json.dumps({"attacks" if attack else "scores": []})
        )
    result = execute(workspace, "scoring-engine.sh", '''
if main --gpt-scores "$CASE_ROOT/gpt.json" --opus-scores "$CASE_ROOT/opus.json" $ATTACK_FLAG;
then exit 0; else exit $?; fi
''', ATTACK_FLAG="--attack-mode" if attack else "")
    assert result.returncode == 2, (result.stdout, result.stderr)
    assert not result.stdout.strip()


@pytest.mark.parametrize("attack", [False, True])
def test_scoring_valid_empty_arrays_remain_explicitly_degraded(workspace, attack):
    (workspace / "scores.json").write_text(json.dumps({"attacks" if attack else "scores": []}))
    result = execute(workspace, "scoring-engine.sh", '''
main --gpt-scores "$CASE_ROOT/scores.json" --opus-scores "$CASE_ROOT/scores.json" $ATTACK_FLAG
''', ATTACK_FLAG="--attack-mode" if attack else "")
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)["degradation_reason"] == "no_items_to_score"


@pytest.mark.parametrize("bad", BAD_DOCUMENTS + [
    '{"tokens_used":-1}', '{"tokens_used":"0"}', '{"tokens_used":0.5}',
    '{"tokens_used":0}\n{"tokens_used":1}',
])
def test_mock_budget_does_not_accept_unknown_usage(workspace, bad):
    (workspace / "fixture.json").write_text(bad)
    result = execute(workspace, "red-team-model-adapter.sh", '''
load_fixture() { cat "$CASE_ROOT/fixture.json"; }
if invoke_mock attacker opus "$CASE_ROOT/doc.md" "$CASE_ROOT/out.json" 10;
then exit 0; else exit $?; fi
''')
    assert result.returncode != 0, (result.stdout, result.stderr)


@pytest.mark.parametrize("tokens,budget,status", [(0, 1, 0), (11, 10, 2), (11, 0, 0)])
def test_mock_budget_retains_zero_exceeded_and_unlimited(workspace, tokens, budget, status):
    (workspace / "fixture.json").write_text(json.dumps({"attacks": [], "tokens_used": tokens}))
    result = execute(workspace, "red-team-model-adapter.sh", '''
load_fixture() { cat "$CASE_ROOT/fixture.json"; }
if invoke_mock attacker opus "$CASE_ROOT/doc.md" "$CASE_ROOT/out.json" "$BUDGET";
then exit 0; else exit $?; fi
''', BUDGET=budget)
    assert result.returncode == status, result.stderr


@pytest.mark.parametrize("content", [
    "", "not JSON", "```json\n{\n```", "```json\n{}\n{", '{"attacks":[]}\n{',
    '{"attacks":null}', '{"attacks":"none"}',
])
def test_live_content_cannot_become_empty_findings(workspace, content):
    (workspace / "content").write_text(content)
    result = execute(workspace, "red-team-model-adapter.sh", '''
if wrap_live_response attacker opus "$(cat "$CASE_ROOT/content")" 1 2 "$CASE_ROOT/out.json";
then exit 0; else exit $?; fi
''')
    assert result.returncode != 0, result.stderr
    assert not (workspace / "out.json").exists()


@pytest.mark.parametrize("role,field", [
    ("attacker", "attacks"), ("evaluator", "attacks"), ("defender", "counter_designs"),
])
@pytest.mark.parametrize("fenced", [False, True])
def test_live_valid_content_retains_usage_and_verdict(workspace, role, field, fenced):
    content = json.dumps({field: [{"id": "kept"}]})
    if fenced:
        content = f"```json\n{content}\n```"
    (workspace / "content").write_text(content)
    result = execute(workspace, "red-team-model-adapter.sh", '''
wrap_live_response "$ROLE" opus "$(cat "$CASE_ROOT/content")" 2 3 "$CASE_ROOT/out.json" '{"status":"DEGRADED"}'
''', ROLE=role)
    assert result.returncode == 0, result.stderr
    out = json.loads((workspace / "out.json").read_text())
    assert out[field] == [{"id": "kept"}]
    assert out["tokens_used"] == 5
    assert out["verdict_quality"] == {"status": "DEGRADED"}


@pytest.mark.parametrize("role", ["attacker", "evaluator", "defender"])
@pytest.mark.parametrize("fenced", [False, True])
def test_partial_role_document_is_not_a_completed_evaluation(workspace, role, fenced):
    (workspace / "content").write_text("```json\n{}\n```" if fenced else "{}")
    result = execute(workspace, "red-team-model-adapter.sh", '''
if wrap_live_response "$ROLE" opus "$(cat "$CASE_ROOT/content")" 0 0 "$CASE_ROOT/out.json";
then exit 0; else exit $?; fi
''', ROLE=role)
    assert result.returncode == 5, result.stderr
    assert not (workspace / "out.json").exists()


@pytest.mark.parametrize("payload", BAD_DOCUMENTS + [
    '{"content":"{\\"attacks\\":[]}"}',
    '{"content":"{\\"attacks\\":[]}","usage":{"input_tokens":1}}',
    '{"content":"{\\"attacks\\":[]}","usage":{"input_tokens":"1","output_tokens":2}}',
    '{"content":"{\\"attacks\\":[]}","usage":{"input_tokens":1,"output_tokens":-2}}',
])
def test_live_envelope_requires_complete_honest_usage(workspace, payload):
    (workspace / "response").write_text(payload)
    executable(workspace / ".claude/scripts/model-invoke", 'cat "$CASE_ROOT/response"\n')
    result = execute(workspace, "red-team-model-adapter.sh", '''
has_any_api_key() { return 0; }
if invoke_live attacker opus "$CASE_ROOT/doc.md" "$CASE_ROOT/out.json" 10 1;
then exit 0; else exit $?; fi
''')
    assert result.returncode == 5, result.stderr
    assert not (workspace / "out.json").exists()


def pipeline(workspace, phase, payload, multi=False, adapter_exit=0):
    (workspace / "response").write_text(payload)
    (workspace / "input.json").write_text(json.dumps({
        "attacks": {"confirmed": [{"id": "A"}]}, "tokens_used": 12,
    }))
    # Replace the subprocess boundary, retaining actual pipeline phase bodies.
    executable(workspace / ".claude/scripts/red-team-model-adapter.sh", '''
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --output-file ]]; then out="$2"; shift; fi
  shift
done
cat "$CASE_ROOT/response" > "$out"
exit "$ADAPTER_EXIT"
''')
    return execute(workspace, "red-team-pipeline.sh", '''
BUDGET_LIMIT=100
ADAPTER_MODE_FLAG=--mock
check_budget() { return 0; }
record_tokens() { printf '%s %s\\n' "$1" "$2" >> "$CASE_ROOT/recorded"; }
sanitize_inter_model() { cp "$1" "$2"; }
render_counter_template() { cp "$CASE_ROOT/doc.md" "$3"; }
get_evaluator_multi_model_enabled() { [[ "$MULTI" == true ]]; }
get_evaluator_models() { printf 'one\\ntwo\\n'; }
if [[ "$PHASE" == 1 ]]; then
  if run_phase1_attacks "$CASE_ROOT/doc.md" standard 1; then exit 0; else exit $?; fi
elif [[ "$PHASE" == 2 ]]; then
  if run_phase2_validation "$CASE_ROOT/input.json" standard 1; then exit 0; else exit $?; fi
else
  if run_phase4_counter_design "$CASE_ROOT/input.json" prd standard; then exit 0; else exit $?; fi
fi
''', PHASE=phase, MULTI=str(multi).lower(), ADAPTER_EXIT=adapter_exit)


@pytest.mark.parametrize("phase,multi", [(1, False), (2, False), (2, True), (4, False)])
@pytest.mark.parametrize("payload", BAD_DOCUMENTS + ['{"tokens_used":"bad"}'])
def test_pipeline_propagates_missing_or_invalid_usage(workspace, phase, multi, payload):
    result = pipeline(workspace, phase, payload, multi)
    assert result.returncode != 0, (result.stdout, result.stderr)
    assert not result.stdout.strip(), "No downstream result path may escape"
    assert not (workspace / "recorded").exists()


@pytest.mark.parametrize("counter_designs", [None, {}, "none"])
def test_pipeline_rejects_wrong_counter_design_type(workspace, counter_designs):
    result = pipeline(workspace, 4, json.dumps({"tokens_used": 2, "counter_designs": counter_designs}))
    assert result.returncode != 0, (result.stdout, result.stderr)
    assert not result.stdout.strip()


@pytest.mark.parametrize("phase,multi,total", [(1, False, 7), (2, False, 7), (2, True, 14), (4, False, 7)])
def test_pipeline_keeps_real_token_sum_and_findings(workspace, phase, multi, total):
    result = pipeline(workspace, phase, '{"tokens_used":7,"attacks":[{"id":"A"}],"counter_designs":[{"id":"D"}]}', multi)
    assert result.returncode == 0, result.stderr
    out = json.loads(Path(result.stdout.strip()).read_text())
    assert (workspace / "recorded").read_text() == f"phase{phase} {total}\n"
    if phase == 4:
        assert out["counter_designs"] == [{"id": "D"}]
        assert out["attacks"]["confirmed"] == [{"id": "A"}]
    else:
        assert out["attacks"] == [{"id": "A"}]


@pytest.mark.parametrize("phase,multi", [(1, False), (2, False), (2, True), (4, False)])
def test_pipeline_does_not_swallow_adapter_parse_rejection(workspace, phase, multi):
    # Even valid-looking partial output is unusable when its producer rejected
    # the response. In particular the live adapter's new exit 5 must survive.
    result = pipeline(workspace, phase, '{"tokens_used":0,"attacks":[]}', multi, adapter_exit=5)
    assert result.returncode == 5, (result.stdout, result.stderr)
    assert not result.stdout.strip()
    assert not (workspace / "recorded").exists()


@pytest.mark.parametrize("payload", ["", "{}", '{"status":null}', '{"status":"unexpected"}', '{"status":"APPROVED"}\n{'])
def test_consensus_status_must_be_valid_before_publication(workspace, payload):
    (workspace / "aggregate").write_text(payload)
    (workspace / "voice.json").write_text('{"verdict_quality":{"status":"APPROVED"}}')
    result = execute(workspace, "flatline-orchestrator.sh", '''
LOA_FLATLINE_OUTPUT_DIR_OVERRIDE="$CASE_ROOT/output"
FLATLINE_RUN_ID=gate-test
python3() { cat "$CASE_ROOT/aggregate"; }
degraded_verdict_maybe_emit() { echo CALLED >> "$CASE_ROOT/notified"; }
if aggregate_and_write_final_consensus prd 1 "$CASE_ROOT/voice.json";
then rc=0; else rc=$?; fi
[[ ! -f "$(final_consensus_path prd)" ]] || echo PUBLISHED
exit "$rc"
''')
    assert result.returncode != 0, (result.stdout, result.stderr)
    assert "PUBLISHED" not in result.stdout
    assert not (workspace / "notified").exists()


def arbiter(workspace, payload):
    (workspace / "arbiter-response").write_text(payload)
    executable(workspace / ".claude/scripts/model-adapter.sh", '''
echo call >> "$CASE_ROOT/provider-boundary-calls"
cat "$CASE_ROOT/arbiter-response"
''')
    (workspace / "consensus.json").write_text(json.dumps({
        "high_consensus": [], "disputed": [], "blockers": [{"id": "B1"}, {"id": "B2"}],
        "consensus_summary": {"high_consensus_count": 0, "disputed_count": 0,
                              "low_value_count": 0, "blocker_count": 2, "model_agreement_percent": 100},
    }))
    return execute(workspace, "flatline-orchestrator.sh", '''
SIMSTIM_AUTONOMOUS=1
is_flatline_enabled() { return 0; }
get_model_tertiary() { :; }
check_budget() { return 0; }
set_state() { :; }
log_trajectory() { :; }
invalidate_final_consensus() { :; }
run_phase1() { printf 'a\\nb\\nc\\nd\\n'; }
qualify_and_aggregate_reviews() { FLATLINE_VERDICT_QUALITY='{"status":"APPROVED"}'; return 0; }
run_phase2() { printf 'a\\nb\\n'; }
run_consensus() { cat "$CASE_ROOT/consensus.json"; }
main --doc "$CASE_ROOT/doc.md" --phase prd --domain local --skip-knowledge --no-silent-noop-detect
''')


@pytest.mark.parametrize("payload", [
    "", "{", '{"content":"not JSON"}', '{"content":"[]"}',
    '{"content":"[{\\"finding_id\\":\\"B1\\",\\"decision\\":\\"reject\\"}]"}',
    '{"content":"[{\\"finding_id\\":\\"B1\\",\\"decision\\":\\"invalid\\"}]"}',
    '{"content":"[{\\"finding_id\\":\\"B1\\",\\"decision\\":\\"reject\\"}"}',
])
def test_arbiter_parse_failure_never_clears_blockers_or_retries(workspace, payload):
    result = arbiter(workspace, payload)
    assert result.returncode != 0, (result.stdout, result.stderr)
    assert not result.stdout.strip()
    assert (workspace / "provider-boundary-calls").read_text() == "call\n"
    assert not (workspace / "grimoires/loa/a2a/flatline/prd-review.json").exists()


@pytest.mark.parametrize("framing", ["raw", "fenced", "prose"])
def test_arbiter_applies_complete_decisions_from_actual_main(workspace, framing):
    decisions = [{"finding_id": "B1", "decision": "accept"}, {"finding_id": "B2", "decision": "reject"}]
    content = json.dumps(decisions, indent=2)
    if framing == "fenced":
        content = f"```json\n{content}\n```"
    elif framing == "prose":
        content = f"Decisions:\n{content}\nComplete."
    result = arbiter(workspace, json.dumps({"content": content}))
    assert result.returncode == 0, result.stderr
    out = json.loads(result.stdout)
    assert [item["id"] for item in out["high_consensus"]] == ["B1"]
    assert [item["id"] for item in out["arbiter_rejected"]] == ["B2"]
    assert out["blockers"] == []
    assert (workspace / "provider-boundary-calls").read_text() == "call\n"
