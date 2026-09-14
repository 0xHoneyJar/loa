"""ADP-003/004/005: real Flatline main, wrapper, qualification and artifacts.

External model executables and config selections are local fixtures. No provider,
authentication, credential, network or GitHub activity is exercised.
"""
import json
import os
from pathlib import Path
import subprocess

import pytest


REPO = Path(__file__).resolve().parents[2]


@pytest.fixture
def workspace(tmp_path):
    scripts = tmp_path / ".claude/scripts"
    scripts.mkdir(parents=True)
    for source in (REPO / ".claude/scripts").iterdir():
        if source.name not in {"model-adapter.sh", "model-invoke"}:
            (scripts / source.name).symlink_to(source, target_is_directory=source.is_dir())
    (tmp_path / ".claude/adapters").symlink_to(REPO / ".claude/adapters")
    (tmp_path / "doc.md").write_text("Review the local dependency fixture.")
    (tmp_path / ".loa.config.yaml").write_text(
        "flatline_protocol:\n  autonomous_arbiter:\n    enabled: true\n"
        "    rotation: [primary, secondary, tertiary]\n"
    )
    arbiter = scripts / "model-adapter.sh"
    arbiter.write_text("""#!/usr/bin/env bash
printf 'call\\n' >> "$CASE_ROOT/arbiter-calls"
if [[ "$SCENARIO" == arbiter_exhausted ]]; then exit 12; fi
if [[ "$SCENARIO" == arbiter_complete ]]; then
    printf '%s\\n' '{"content":"[{\\"finding_id\\":\\"SKEP-1\\",\\"decision\\":\\"reject\\"}]"}'
else
    printf '%s\\n' '{"content":"[]"}'
fi
""")
    arbiter.chmod(0o755)
    invoke = scripts / "model-invoke"
    invoke.write_bytes((REPO / "tests/fixtures/flatline-evidence/model-invoke.py").read_bytes())
    invoke.chmod(0o755)
    return tmp_path


def run_flatline(workspace, scenario):
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(("LOA_", "SIMSTIM_", "FLATLINE_")) and
           not any(word in key for word in ("API_KEY", "TOKEN", "SECRET", "CREDENTIAL"))}
    env.update(REPO=str(REPO), CASE_ROOT=str(workspace), SCENARIO=scenario,
               PYTHONDONTWRITEBYTECODE="1", TMPDIR=str(workspace))
    return subprocess.run(["bash", "-c", r'''
source "$REPO/.claude/scripts/flatline-orchestrator.sh"
PROJECT_ROOT="$CASE_ROOT"
SCRIPT_DIR="$CASE_ROOT/.claude/scripts"
MODEL_INVOKE="$SCRIPT_DIR/model-invoke"
LOA_FLATLINE_OUTPUT_DIR_OVERRIDE="$CASE_ROOT/output"
is_flatline_enabled() { return 0; }
get_model_primary() { echo primary; }
get_model_secondary() { echo secondary; }
get_model_tertiary() { echo tertiary; }
configured_flatline_model() { printf 'fixture:%s\n' "$1"; }
validate_model() { return 0; }
check_budget() { return 0; }
is_arbiter_enabled() { return 1; }
is_stage_routing_scorer_enabled() { [[ "$SCENARIO" == stage_routing ]]; }
log_trajectory() { :; }
degraded_verdict_maybe_emit() { :; }
mktemp() {
    if [[ "$SCENARIO" == arbiter_no_temp && $# -eq 0 ]]; then return 1; fi
    command mktemp "$@"
}
[[ "$SCENARIO" != arbiter_* ]] || export SIMSTIM_AUTONOMOUS=1
main --doc "$CASE_ROOT/doc.md" --phase beads --domain fixture --run-id "$SCENARIO" \
    --skip-knowledge --no-silent-noop-detect --keep-temp --json
'''], cwd=workspace, env=env, capture_output=True, text=True, timeout=60)


def output_and_artifact(workspace, scenario, result):
    assert result.stdout.strip(), result.stderr
    output = json.loads(result.stdout)
    artifact = json.loads((workspace / f"output/beads-{scenario}-final_consensus.json").read_text())
    latest = json.loads((workspace / "output/beads-final_consensus.json").read_text())
    assert output["verdict_quality"] == artifact == latest
    assert artifact["voices_planned"] == artifact["voices_succeeded"] == 3
    return output, artifact


@pytest.mark.parametrize("scenario", [
    "contradictory", "contradictory_reversed", "degraded_score", "missing_quality",
    "invalid_quality", "missing_identity", "same_actual_scorer", "stage_routing",
    "error_after_scores",
])
def test_unqualified_scoring_retains_findings_without_approval(workspace, scenario):
    result = run_flatline(workspace, scenario)
    assert result.returncode == 6, (result.stdout, result.stderr)
    output, artifact = output_and_artifact(workspace, scenario, result)
    assert artifact["status"] == "DEGRADED"
    assert output["degraded"] is True
    assert output["high_consensus"] == []
    reviews = [json.loads(review["content"]) for review in output["raw_reviews"].values()]
    assert len([item for review in reviews for item in review["improvements"]]) == 3
    if scenario in {"stage_routing", "same_actual_scorer"}:
        assert output["consensus_summary"]["models_available"] == 1
        assert all(item["scorers_available"] == 1 for item in output["medium_value"])
    if scenario == "stage_routing":
        scores = [json.loads(p.read_text()) for p in workspace.glob("invoke-*.json")
                  if json.loads(p.read_text())["args"]["--agent"] == "flatline-scorer"]
        assert len(scores) == 6
        assert all("--model" not in row["args"] for row in scores)


def test_complete_independent_scorers_preserve_resolved_identity(workspace):
    result = run_flatline(workspace, "complete")
    assert result.returncode == 0, (result.stdout, result.stderr)
    output, artifact = output_and_artifact(workspace, "complete", result)
    assert artifact["status"] == "APPROVED"
    assert len(output["high_consensus"]) == 3
    assert output["consensus_summary"]["models_available"] == 3
    assert all(item["scorers_available"] == 2 for item in output["high_consensus"])
    prepared = list(workspace.glob("**/gpt-scores-prepared.json"))
    assert len(prepared) == 1
    score = json.loads(prepared[0].read_text())
    assert score["model"] == "secondary"
    assert score["provider"] == "fixture"
    assert score["requested_model"] == "secondary"
    assert score["verdict_quality"]["status"] == "APPROVED"


@pytest.mark.parametrize("scenario,calls", [
    ("arbiter_incomplete", 1), ("arbiter_exhausted", 3), ("arbiter_no_temp", 0),
])
def test_failed_arbitration_retains_unresolved_findings_and_failed_artifact(workspace, scenario, calls):
    result = run_flatline(workspace, scenario)
    assert result.returncode == 3, (result.stdout, result.stderr)
    output, artifact = output_and_artifact(workspace, scenario, result)
    assert artifact["status"] == "FAILED"
    assert [item["id"] for item in output["blockers"]] == ["SKEP-1"]
    assert len(output["high_consensus"]) == 3
    assert output["arbitration"]["status"] == "FAILED"
    assert output["execution"]["status"] == "FAILED"
    if calls:
        assert (workspace / "arbiter-calls").read_text() == "call\n" * calls
    else:
        assert not (workspace / "arbiter-calls").exists()


def test_complete_arbitration_control(workspace):
    result = run_flatline(workspace, "arbiter_complete")
    assert result.returncode == 0, (result.stdout, result.stderr)
    output, artifact = output_and_artifact(workspace, "arbiter_complete", result)
    assert artifact["status"] == "APPROVED"
    assert output["blockers"] == []
    assert [item["id"] for item in output["arbiter_rejected"]] == ["SKEP-1"]


@pytest.mark.parametrize("text", [
    '{"scores":[{"id":"I","score":900}]}\n{"scores":[{"id":"I","score":0}]}',
    '{"scores":[{"id":"I","score":0}]}\n{"scores":[{"id":"I","score":900}]}',
    '{"scores":[]}\n{"scores":[]}',
    '{"scores":[{"id":"I","score":900}],"scores":[{"id":"I","score":0}]}',
])
def test_score_normalization_rejects_ambiguous_payload(text):
    result = subprocess.run(["bash", "-c",
                             'source "$1"; normalize_score_response "$2"', "test",
                             str(REPO / ".claude/scripts/lib/normalize-json.sh"), text],
                            capture_output=True, text=True)
    assert result.returncode != 0
    assert not result.stdout.strip()
