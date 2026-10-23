# Adjudication list — pr-25

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

12 item(s) disagree.

### H04: anchors


Annotator A:

```json
{
  "anchor_lines": [
    1079,
    1080,
    1081,
    1086,
    1087,
    1093,
    1096,
    1098,
    1100
  ],
  "category": "logic",
  "description": "remove_colliding deletes any agent-added .py whose bare basename matches a hidden/fixture test-dir .py (including helpers and modules inside packages, e.g. src/pkg/helpers.py), so correct solutions lose files and fail, while it misses real pytest import-name collisions in packages, ignores files inside directory overlays and the task's python_files setting.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D1",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    1079,
    1080,
    1081,
    1086,
    1087,
    1093,
    1096
  ],
  "category": "logic",
  "description": "remove_colliding compares bare basenames of any .py: it deletes agent non-test modules (e.g. src/app/helpers.py) and modules inside packages that pytest would never clash on, so correct solutions fail. It also misses real import-name collisions of packaged test modules, ignores files inside directory overlays and the fixture's python_files, and does not handle helper shadowing.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D1",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H07: severity


Annotator A:

```json
{
  "anchor_lines": [
    633,
    634,
    635,
    636,
    637,
    640
  ],
  "category": "security",
  "description": "The auth.json copy placed in the agent-readable per-run HOME keeps a long-lived OPENAI_API_KEY verbatim, exposing the operator's API key to the agent under evaluation.",
  "file": "evals/harness/pipeline-run.sh",
  "group": "D2",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    633,
    634,
    635,
    636,
    637,
    640
  ],
  "category": "security",
  "description": "The auth.json copy into the agent-readable per-run HOME keeps any long-lived OPENAI_API_KEY verbatim, which exposes the operator's API key to the agent under evaluation.",
  "file": "evals/harness/pipeline-run.sh",
  "group": "D2",
  "not_defect_class": null,
  "severity": "critical",
  "verdict": "defect"
}
```

### H12: group

- group members besides H12: A ['H13', 'H14', 'H20', 'H21'], B ['H13', 'H14', 'H15', 'H16', 'H17', 'H18', 'H19', 'H20', 'H21']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Reads the new horizon override knob and initialises the pre-flight record variable used by the fixed pre-flight.",
  "file": "evals/harness/run-ablation.sh",
  "group": "D4",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Adds variables for the horizon override and the in-memory pre-flight record used by the horizon fix.",
  "file": "evals/harness/run-ablation.sh",
  "group": "D3",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H13: group

- group members besides H13: A ['H12', 'H14', 'H20', 'H21'], B ['H12', 'H14', 'H15', 'H16', 'H17', 'H18', 'H19', 'H20', 'H21']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Validates the new LOA_ABLATION_CODEX_HORIZON_S override.",
  "file": "evals/harness/run-ablation.sh",
  "group": "D4",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Validates the new horizon override knob.",
  "file": "evals/harness/run-ablation.sh",
  "group": "D3",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H14: verdict


Annotator A:

```json
{
  "anchor_lines": [
    786,
    788,
    806
  ],
  "category": "logic",
  "description": "On --resume the codex pre-flight counts every plan entry (including already-rowed trials) toward the token horizon, so a resume whose remaining trials fit the token's lifetime is wrongly refused.",
  "file": "evals/harness/run-ablation.sh",
  "group": "D4",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Passes the resume scope and the override into the pre-flight script so it can compute the corrected horizon.",
  "file": "evals/harness/run-ablation.sh",
  "group": "D3",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H15: group

- group members besides H15: A ['H16', 'H17'], B ['H12', 'H13', 'H14', 'H16', 'H17', 'H18', 'H19', 'H20', 'H21']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Adds auth_mode/trials_counted/horizon_source fields and a note slot to the pre-flight record for the fixed check.",
  "file": "evals/harness/run-ablation.sh",
  "group": "D3",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Adds auth_mode/trials_counted/horizon_source fields and a note slot to the pre-flight record.",
  "file": "evals/harness/run-ablation.sh",
  "group": "D3",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H16: group, severity

- group members besides H16: A ['H15', 'H17'], B ['H12', 'H13', 'H14', 'H15', 'H17', 'H18', 'H19', 'H20', 'H21']

Annotator A:

```json
{
  "anchor_lines": [
    806,
    814,
    815,
    816,
    817
  ],
  "category": "logic",
  "description": "The required horizon 2 x sum(watchdog)/concurrency can be shorter than a single trial's own watchdog, so a token that expires mid-trial passes the pre-flight (and an API-key-mode auth.json without tokens.access_token is wrongly refused).",
  "file": "evals/harness/run-ablation.sh",
  "group": "D3",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    806,
    814,
    815,
    816,
    817
  ],
  "category": "logic",
  "description": "The codex token horizon is computed wrongly: at concurrency >1 it can fall below one trial's own watchdog, so a token that expires mid-trial passes; on --resume it counts the whole plan, so valid resumes are refused. An API-key-mode auth.json, which has no access token, is also refused.",
  "file": "evals/harness/run-ablation.sh",
  "group": "D3",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H17: group

- group members besides H17: A ['H15', 'H16'], B ['H12', 'H13', 'H14', 'H15', 'H16', 'H18', 'H19', 'H20', 'H21']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Updates the refusal message for the new horizon formula, prints the API-key note and keeps the record in a variable instead of a scratch file.",
  "file": "evals/harness/run-ablation.sh",
  "group": "D3",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Updates the refusal message to the new horizon formula, keeps the pre-flight record in a variable instead of a $WORK file, and prints the API-key note.",
  "file": "evals/harness/run-ablation.sh",
  "group": "D3",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H18: group

- group members besides H18: A -, B ['H12', 'H13', 'H14', 'H15', 'H16', 'H17', 'H19', 'H20', 'H21']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Passes the pre-flight record to jq from a variable instead of a $WORK file.",
  "file": "evals/harness/run-ablation.sh",
  "group": null,
  "not_defect_class": "refactor",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "write_manifest reads the pre-flight record from the variable rather than the scratch file.",
  "file": "evals/harness/run-ablation.sh",
  "group": "D3",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H19: group

- group members besides H19: A -, B ['H12', 'H13', 'H14', 'H15', 'H16', 'H17', 'H18', 'H20', 'H21']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Reads the pre-flight record from the variable instead of the slurped file.",
  "file": "evals/harness/run-ablation.sh",
  "group": null,
  "not_defect_class": "refactor",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "MANIFEST uses $cpf from the variable.",
  "file": "evals/harness/run-ablation.sh",
  "group": "D3",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H20: group

- group members besides H20: A ['H12', 'H13', 'H14', 'H21'], B ['H12', 'H13', 'H14', 'H15', 'H16', 'H17', 'H18', 'H19', 'H21']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Passes the latest invocation's pre-flight record into STATUS.json so resume horizons are recorded.",
  "file": "evals/harness/run-ablation.sh",
  "group": "D4",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Passes the pre-flight record to write_status so STATUS.json can carry this invocation's record (trials counted on resume).",
  "file": "evals/harness/run-ablation.sh",
  "group": "D3",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H21: group

- group members besides H21: A ['H12', 'H13', 'H14', 'H20'], B ['H12', 'H13', 'H14', 'H15', 'H16', 'H17', 'H18', 'H19', 'H20']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Adds codex_preflight to STATUS.json.",
  "file": "evals/harness/run-ablation.sh",
  "group": "D4",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Adds codex_preflight to STATUS.json.",
  "file": "evals/harness/run-ablation.sh",
  "group": "D3",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```
