#!/usr/bin/env python3
"""Offline model-invoke fixture; only local JSON inputs and sidecars."""
import json
import os
from pathlib import Path
import sys

args = dict(zip(sys.argv[1::2], sys.argv[2::2]))
scenario = os.environ["SCENARIO"]
agent = args["--agent"]
model = args.get("--model", "fixture:stage-scorer").split(":", 1)[-1]
status = "APPROVED"
if agent == "flatline-reviewer":
    content = {"improvements": [{
        "id": "IMP-001", "description": model + " distinct requirement", "priority": "HIGH",
    }]}
elif agent == "flatline-skeptic":
    content = {"concerns": []}
    if scenario.startswith("arbiter_") and model == "secondary":
        content["concerns"] = [{
            "id": "SKEP-1", "concern": "Required dependency is absent.",
            "severity": "HIGH", "severity_score": 900,
        }]
else:
    assert agent == "flatline-scorer", args
    items = json.loads(Path(args["--input"]).read_text())
    content = {"scores": [{"id": item["id"], "score": 900} for item in items["improvements"]]}
    if scenario == "degraded_score":
        status = "DEGRADED"
    if scenario == "same_actual_scorer":
        model = "same-resolved-scorer"
text = json.dumps(content)
if agent == "flatline-scorer" and scenario in ("contradictory", "contradictory_reversed"):
    zero = json.dumps({"scores": [{"id": row["id"], "score": 0} for row in content["scores"]]})
    text = text + "\n" + zero if scenario == "contradictory" else zero + "\n" + text
quality = {
    "status": status, "consensus_outcome": "consensus", "truncation_waiver_applied": False,
    "voices_planned": 1, "voices_succeeded": 1, "voices_succeeded_ids": [model],
    "voices_dropped": [], "chain_health": "degraded" if status == "DEGRADED" else "ok",
    "confidence_floor": "high", "rationale": "Offline fixture", "single_voice_call": True,
}
if agent == "flatline-scorer" and scenario == "invalid_quality":
    quality["voices_succeeded"] = 2
if agent != "flatline-scorer" or scenario != "missing_quality":
    Path(os.environ["LOA_VERDICT_QUALITY_SIDECAR"]).write_text(json.dumps(quality))
Path(os.environ["CASE_ROOT"], f"invoke-{os.getpid()}.json").write_text(json.dumps({
    "args": args, "model": model, "quality": quality,
}))
result = {"content": text, "usage": {"input_tokens": 1, "output_tokens": 1},
          "model": model, "provider": "fixture"}
if agent == "flatline-scorer" and scenario == "missing_identity":
    result.pop("model")
print(json.dumps(result))
if agent == "flatline-scorer" and scenario == "error_after_scores":
    sys.exit(12)
