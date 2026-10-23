# Adjudication list — pr-22

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

44 item(s) disagree.

### H07: group

- group members besides H07: A -, B ['H18', 'H34', 'H35', 'H36', 'H37', 'H38', 'H39', 'H40', 'H41']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Help line range adjusted to the longer header.",
  "file": "evals/harness/ablation-row.sh",
  "group": null,
  "not_defect_class": "docs",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    83
  ],
  "category": null,
  "description": "The --help line range is widened to cover the longer header.",
  "file": "evals/harness/ablation-row.sh",
  "group": "D6",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H09: anchors


Annotator A:

```json
{
  "anchor_lines": [
    171,
    176,
    178,
    179,
    180
  ],
  "category": "resource",
  "description": "Grade, manifest, task and pipeline JSON are held in shell variables and later passed to jq as --argjson argv strings, which fails once an input exceeds MAX_ARG_STRLEN (128 KiB) on long runs.",
  "file": "evals/harness/ablation-row.sh",
  "group": "D4",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    168,
    171,
    173,
    176,
    178,
    179,
    180
  ],
  "category": "resource",
  "description": "Inputs that grow with the run (grade, manifest, task, pipeline.json) are held in shell strings and later passed to jq as --argjson argv, so a large run goes over MAX_ARG_STRLEN and the row cannot be built.",
  "file": "evals/harness/ablation-row.sh",
  "group": "D4",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H10: anchors, group, severity

- group members besides H10: A ['H42', 'H43', 'H44', 'H65'], B ['H42', 'H43', 'H44', 'H64', 'H65']

Annotator A:

```json
{
  "anchor_lines": [
    200,
    201,
    202,
    205,
    206
  ],
  "category": "security",
  "description": "envelope() prefers the agent-writable sandbox dissent envelope over the harness eval/ copy, so a later phase that rewrites the sandbox envelope changes the row's voices/degraded fields (hunk also moves MODELINV to a file and adds the arm-grammar check).",
  "file": "evals/harness/ablation-row.sh",
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
    200,
    201,
    202,
    203,
    205,
    206
  ],
  "category": "security",
  "description": "envelope() prefers the agent-writable sandbox copy of the dissent envelope over the harness eval/ copy, so a later phase can tamper with voices_run and degraded; the hunk also moves the MODELINV and manifest inputs to files and adds the arm grammar check.",
  "file": "evals/harness/ablation-row.sh",
  "group": "D3",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H12: anchors


Annotator A:

```json
{
  "anchor_lines": [
    225,
    226
  ],
  "category": "resource",
  "description": "The row program receives every run-scaled input via --argjson argv strings, which aborts on large MODELINV ledgers (hunk also hardens ms() and voices() against odd shapes and adds the Bash mount scan).",
  "file": "evals/harness/ablation-row.sh",
  "group": "D4",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    224,
    225,
    226
  ],
  "category": "resource",
  "description": "The row jq call passes every run-scaled input (MODELINV, pipeline.json, envelopes, writes) as --argjson argv strings, which fails on long runs past the per-argument limit; the hunk also hardens ms() and voices().",
  "file": "evals/harness/ablation-row.sh",
  "group": "D4",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H13: group, category

- group members besides H13: A ['H15', 'H16'], B ['H14', 'H15', 'H16', 'H17']

Annotator A:

```json
{
  "anchor_lines": [
    247
  ],
  "category": "input-validation",
  "description": "A non-object models_used (e.g. an array) makes keys[] misbehave, so the row build aborts or reports bogus model mismatches.",
  "file": "evals/harness/ablation-row.sh",
  "group": "D8",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    247
  ],
  "category": "error-handling",
  "description": "A models_used that is not an object (e.g. an array) makes keys[] abort the whole row program.",
  "file": "evals/harness/ablation-row.sh",
  "group": "D7",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H14: verdict


Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Binds the parsed start/finish timestamps used by the wall_clock_ms fix.",
  "file": "evals/harness/ablation-row.sh",
  "group": "D7",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    230,
    313
  ],
  "category": "error-handling",
  "description": "An empty or non-Z-offset started/finished timestamp makes ms()/fromdateiso8601 abort the row build; the hunk binds the guarded timestamps.",
  "file": "evals/harness/ablation-row.sh",
  "group": "D7",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H15: group, category

- group members besides H15: A ['H13', 'H16'], B ['H13', 'H14', 'H16', 'H17']

Annotator A:

```json
{
  "anchor_lines": [
    285
  ],
  "category": "input-validation",
  "description": "Phase records missing name or model_requested, or with a non-object models_used, are copied through as null/odd types, producing rows that fail --validate.",
  "file": "evals/harness/ablation-row.sh",
  "group": "D8",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    285
  ],
  "category": "error-handling",
  "description": "A phase without name or model_requested, or with a non-object models_used, passes null or bad shapes into the row, which then fails validation.",
  "file": "evals/harness/ablation-row.sh",
  "group": "D7",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H16: group, category

- group members besides H16: A ['H13', 'H15'], B ['H13', 'H14', 'H15', 'H17']

Annotator A:

```json
{
  "anchor_lines": [
    303,
    304,
    305,
    306,
    307
  ],
  "category": "input-validation",
  "description": "Non-boolean verdict_accuracy values or a non-object verdict_accuracy_per_gate are passed through or crash indexing, yielding invalid rows or a jq abort.",
  "file": "evals/harness/ablation-row.sh",
  "group": "D8",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    303,
    304,
    305,
    306,
    307
  ],
  "category": "error-handling",
  "description": "A non-boolean verdict_accuracy or a non-object verdict_accuracy_per_gate either aborts the row program or produces a row with the wrong field types.",
  "file": "evals/harness/ablation-row.sh",
  "group": "D7",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H17: anchors, group

- group members besides H17: A ['H14'], B ['H13', 'H14', 'H15', 'H16']

Annotator A:

```json
{
  "anchor_lines": [
    230,
    313
  ],
  "category": "error-handling",
  "description": "wall_clock_ms calls ms() on any non-null started/finished, so an empty or offset timestamp makes fromdateiso8601 abort the whole row build.",
  "file": "evals/harness/ablation-row.sh",
  "group": "D7",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    313
  ],
  "category": "error-handling",
  "description": "wall_clock_ms calls ms() on a present but unparseable started/finished and aborts, instead of falling back to the phase sum.",
  "file": "evals/harness/ablation-row.sh",
  "group": "D7",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H18: group

- group members besides H18: A ['H35', 'H36', 'H37', 'H38', 'H39', 'H40', 'H41'], B ['H07', 'H34', 'H35', 'H36', 'H37', 'H38', 'H39', 'H40', 'H41']

Annotator A:

```json
{
  "anchor_lines": [
    326,
    327
  ],
  "category": "security",
  "description": "zone_violations only records Write/Edit tool inputs under .claude/, so Bash rewrites of the mount (CLAUDE.md, .loa.config.yaml) go unreported, and a jq abort exits without naming the run.",
  "file": "evals/harness/ablation-row.sh",
  "group": "D6",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    326,
    327
  ],
  "category": "security",
  "description": "zone_violations records only Write/Edit inputs under .claude/, so Bash rewrites of the mount and changed CLAUDE.md/.loa.config.yaml never show up; a failed row program also exits with a bare jq error.",
  "file": "evals/harness/ablation-row.sh",
  "group": "D6",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H20: group

- group members besides H20: A -, B ['H21', 'H22', 'H24', 'H25']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Help line range adjusted to the longer header.",
  "file": "evals/harness/execute-agent.sh",
  "group": null,
  "not_defect_class": "docs",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    115
  ],
  "category": null,
  "description": "The usage line range is widened to cover the longer header.",
  "file": "evals/harness/execute-agent.sh",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H21: group, severity, category

- group members besides H21: A ['H22', 'H24', 'H25'], B ['H20', 'H22', 'H24', 'H25']

Annotator A:

```json
{
  "anchor_lines": [
    212,
    213,
    214,
    215
  ],
  "category": "logic",
  "description": "An inherited LOA_ADVERSARIAL_REVIEW_ENFORCE is only unset in arm mode, so an operator override leaks into baseline (non-arm) executor runs.",
  "file": "evals/harness/execute-agent.sh",
  "group": "D10",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    212,
    213,
    214,
    215
  ],
  "category": "security",
  "description": "An inherited LOA_ADVERSARIAL_REVIEW_ENFORCE is unset only in arm mode, so the operator's gate override still reaches the baseline (non-arm) executor.",
  "file": "evals/harness/execute-agent.sh",
  "group": "D8",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H22: group

- group members besides H22: A ['H21', 'H24', 'H25'], B ['H20', 'H21', 'H24', 'H25']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Captures the enforce value for recording in executor.json.",
  "file": "evals/harness/execute-agent.sh",
  "group": "D10",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    223
  ],
  "category": null,
  "description": "Captures the enforce value at launch so executor.json can record it.",
  "file": "evals/harness/execute-agent.sh",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H24: group

- group members besides H24: A ['H21', 'H22', 'H25'], B ['H20', 'H21', 'H22', 'H25']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Passes the recorded enforce value to the executor.json writer.",
  "file": "evals/harness/execute-agent.sh",
  "group": "D10",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    362
  ],
  "category": null,
  "description": "Passes the recorded enforce value to the executor.json jq call.",
  "file": "evals/harness/execute-agent.sh",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H25: group

- group members besides H25: A ['H21', 'H22', 'H24'], B ['H20', 'H21', 'H22', 'H24']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Adds adversarial_review_enforce to executor.json.",
  "file": "evals/harness/execute-agent.sh",
  "group": "D10",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    401
  ],
  "category": null,
  "description": "Adds adversarial_review_enforce to executor.json.",
  "file": "evals/harness/execute-agent.sh",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H29: group

- group members besides H29: A -, B ['H30']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Usage line range adjusted to the longer header.",
  "file": "evals/harness/freeze.sh",
  "group": null,
  "not_defect_class": "docs",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    38
  ],
  "category": null,
  "description": "The usage line range is widened to cover the longer header.",
  "file": "evals/harness/freeze.sh",
  "group": "D11",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H30: group

- group members besides H30: A -, B ['H29']

Annotator A:

```json
{
  "anchor_lines": [
    66,
    67,
    68,
    69,
    70
  ],
  "category": "security",
  "description": "The manifest listing ignores symlinks (find -type f) and splits newline-bearing paths, so a symlink whose target changes or a newline path escapes or corrupts the frozen suite manifest.",
  "file": "evals/harness/freeze.sh",
  "group": "D13",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    66,
    67,
    68,
    69,
    70
  ],
  "category": "security",
  "description": "The manifest listing uses find -type f, so symlinks are silently left out (their targets can change the suite while the manifest stays the same), and a path holding a newline splits into two bogus listing entries.",
  "file": "evals/harness/freeze.sh",
  "group": "D11",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H34: group

- group members besides H34: A -, B ['H07', 'H18', 'H35', 'H36', 'H37', 'H38', 'H39', 'H40', 'H41']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Help line range adjusted to the longer header.",
  "file": "evals/harness/pipeline-run.sh",
  "group": null,
  "not_defect_class": "docs",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    153
  ],
  "category": null,
  "description": "The --help line range is widened to cover the longer header.",
  "file": "evals/harness/pipeline-run.sh",
  "group": "D6",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H35: group

- group members besides H35: A ['H18', 'H36', 'H37', 'H38', 'H39', 'H40', 'H41'], B ['H07', 'H18', 'H34', 'H36', 'H37', 'H38', 'H39', 'H40', 'H41']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Initialises mount-integrity state variables.",
  "file": "evals/harness/pipeline-run.sh",
  "group": "D6",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    298
  ],
  "category": null,
  "description": "Initialises the mount-integrity state variables.",
  "file": "evals/harness/pipeline-run.sh",
  "group": "D6",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H36: group

- group members besides H36: A ['H18', 'H35', 'H37', 'H38', 'H39', 'H40', 'H41'], B ['H07', 'H18', 'H34', 'H35', 'H37', 'H38', 'H39', 'H40', 'H41']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Adds sha/mount-state helpers for mount integrity.",
  "file": "evals/harness/pipeline-run.sh",
  "group": "D6",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    312
  ],
  "category": null,
  "description": "Adds the hashing and mount-integrity helper functions.",
  "file": "evals/harness/pipeline-run.sh",
  "group": "D6",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H37: group

- group members besides H37: A ['H18', 'H35', 'H36', 'H38', 'H39', 'H40', 'H41'], B ['H07', 'H18', 'H34', 'H35', 'H36', 'H38', 'H39', 'H40', 'H41']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Passes mount_integrity to the pipeline.json writer.",
  "file": "evals/harness/pipeline-run.sh",
  "group": "D6",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    331
  ],
  "category": null,
  "description": "Passes mount_integrity to the pipeline.json jq call.",
  "file": "evals/harness/pipeline-run.sh",
  "group": "D6",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H38: group

- group members besides H38: A ['H18', 'H35', 'H36', 'H37', 'H39', 'H40', 'H41'], B ['H07', 'H18', 'H34', 'H35', 'H36', 'H37', 'H39', 'H40', 'H41']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Writes mount_integrity into pipeline.json.",
  "file": "evals/harness/pipeline-run.sh",
  "group": "D6",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    340
  ],
  "category": null,
  "description": "Adds mount_integrity to pipeline.json.",
  "file": "evals/harness/pipeline-run.sh",
  "group": "D6",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H39: group

- group members besides H39: A ['H18', 'H35', 'H36', 'H37', 'H38', 'H40', 'H41'], B ['H07', 'H18', 'H34', 'H35', 'H36', 'H37', 'H38', 'H40', 'H41']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Computes mount integrity at finish.",
  "file": "evals/harness/pipeline-run.sh",
  "group": "D6",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    345
  ],
  "category": null,
  "description": "Computes mount integrity in finish().",
  "file": "evals/harness/pipeline-run.sh",
  "group": "D6",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H40: group

- group members besides H40: A ['H18', 'H35', 'H36', 'H37', 'H38', 'H39', 'H41'], B ['H07', 'H18', 'H34', 'H35', 'H36', 'H37', 'H38', 'H39', 'H41']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Computes mount integrity on an aborted exit.",
  "file": "evals/harness/pipeline-run.sh",
  "group": "D6",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    358
  ],
  "category": null,
  "description": "Computes mount integrity on an abnormal exit.",
  "file": "evals/harness/pipeline-run.sh",
  "group": "D6",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H41: group

- group members besides H41: A ['H18', 'H35', 'H36', 'H37', 'H38', 'H39', 'H40'], B ['H07', 'H18', 'H34', 'H35', 'H36', 'H37', 'H38', 'H39', 'H40']

Annotator A:

```json
{
  "anchor_lines": [
    487,
    492,
    497
  ],
  "category": "security",
  "description": "No baseline of CLAUDE.md/.loa.config.yaml is taken after materialisation, so an agent's Bash rewrite of the mount is never detected.",
  "file": "evals/harness/pipeline-run.sh",
  "group": "D6",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    487,
    492,
    497
  ],
  "category": "security",
  "description": "No baseline hash of sandbox CLAUDE.md/.loa.config.yaml is taken after materialisation, so an agent that rewrites the mount through Bash leaves no record.",
  "file": "evals/harness/pipeline-run.sh",
  "group": "D6",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H42: group, severity

- group members besides H42: A ['H10', 'H43', 'H44', 'H65'], B ['H10', 'H43', 'H44', 'H64', 'H65']

Annotator A:

```json
{
  "anchor_lines": [
    775,
    776,
    777,
    778
  ],
  "category": "security",
  "description": "After every phase all sandbox adversarial-*.json envelopes are re-copied over eval/, so a later FIX/AUDIT phase that edits a gate envelope (or symlinks it) overwrites the harness evidence.",
  "file": "evals/harness/pipeline-run.sh",
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
    775,
    776,
    777,
    778
  ],
  "category": "security",
  "description": "Every phase copies every sandbox adversarial-*.json to eval/ and overwrites the earlier copy, so a later FIX/AUDIT phase that edits a gate's envelope replaces the harness evidence (symlinks are followed too).",
  "file": "evals/harness/pipeline-run.sh",
  "group": "D3",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H43: group

- group members besides H43: A ['H10', 'H42', 'H44', 'H65'], B ['H10', 'H42', 'H44', 'H64', 'H65']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Passes envelope copy evidence to the phase record writer.",
  "file": "evals/harness/pipeline-run.sh",
  "group": "D3",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    824
  ],
  "category": null,
  "description": "Passes the envelope copy fields to the phase-record jq call.",
  "file": "evals/harness/pipeline-run.sh",
  "group": "D3",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H44: group

- group members besides H44: A ['H10', 'H42', 'H43', 'H65'], B ['H10', 'H42', 'H43', 'H64', 'H65']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Adds envelope_copied/envelope_sha256 to gate phase records.",
  "file": "evals/harness/pipeline-run.sh",
  "group": "D3",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    849
  ],
  "category": null,
  "description": "Records envelope_copied and envelope_sha256 on gate phase records.",
  "file": "evals/harness/pipeline-run.sh",
  "group": "D3",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H47: group

- group members besides H47: A -, B ['H49', 'H50', 'H54', 'H55']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Usage line range adjusted to the longer header.",
  "file": "evals/harness/run-arms.sh",
  "group": null,
  "not_defect_class": "docs",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    89
  ],
  "category": null,
  "description": "The usage line range is widened to cover the longer header.",
  "file": "evals/harness/run-arms.sh",
  "group": "D13",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H48: verdict


Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Refuses a non-screen --batch named screen-*, part of the screen-exclusion fix.",
  "file": "evals/harness/run-arms.sh",
  "group": "D14",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    165,
    167
  ],
  "category": "logic",
  "description": "A regular --batch whose name starts with screen- is accepted, and then the suite aggregate silently drops it because it excludes batches by directory name.",
  "file": "evals/harness/run-arms.sh",
  "group": "D12",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H49: group

- group members besides H49: A ['H50', 'H54', 'H55'], B ['H47', 'H50', 'H54', 'H55']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Initialises the assumed-cap counter.",
  "file": "evals/harness/run-arms.sh",
  "group": "D15",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    346
  ],
  "category": null,
  "description": "Initialises the assumed-cap counter.",
  "file": "evals/harness/run-arms.sh",
  "group": "D13",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H50: group

- group members besides H50: A ['H49', 'H54', 'H55'], B ['H47', 'H49', 'H54', 'H55']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Reports assumed_cap_trials in STATUS.json.",
  "file": "evals/harness/run-arms.sh",
  "group": "D15",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    362,
    363,
    364
  ],
  "category": null,
  "description": "Reports assumed_cap_trials in STATUS.json.",
  "file": "evals/harness/run-arms.sh",
  "group": "D13",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H53: verdict


Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Removes the directory-name filter now replaced by the marker filter.",
  "file": "evals/harness/run-arms.sh",
  "group": "D14",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    391
  ],
  "category": "logic",
  "description": "Screen batches are excluded by the screen-* directory path rather than by the marker, which drops regular batches with that prefix and keeps unmarked-name screen batches.",
  "file": "evals/harness/run-arms.sh",
  "group": "D12",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H54: group

- group members besides H54: A ['H49', 'H50', 'H55'], B ['H47', 'H49', 'H50', 'H55']

Annotator A:

```json
{
  "anchor_lines": [
    505,
    506,
    507,
    508
  ],
  "category": "logic",
  "description": "A failed trial that reports no cost (timeout, transport loss) is charged USD 0 to spent, so the --max-usd cap under-counts and launches too many trials.",
  "file": "evals/harness/run-arms.sh",
  "group": "D15",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    505,
    506,
    507,
    508
  ],
  "category": "logic",
  "description": "A failed trial that reports no cost (killed, transport loss) adds 0 to spent, so the --max-usd cap underestimates real spend and launches too many trials.",
  "file": "evals/harness/run-arms.sh",
  "group": "D13",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H55: group

- group members besides H55: A ['H49', 'H50', 'H54'], B ['H47', 'H49', 'H50', 'H54']

Annotator A:

```json
{
  "anchor_lines": [
    522,
    523
  ],
  "category": "logic",
  "description": "A trial that writes no row adds nothing to spent, under-counting spend against --max-usd.",
  "file": "evals/harness/run-arms.sh",
  "group": "D15",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    522,
    523
  ],
  "category": "logic",
  "description": "A trial that writes no row at all is charged nothing to spent, which also undercounts spend against the cap.",
  "file": "evals/harness/run-arms.sh",
  "group": "D13",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H58: group

- group members besides H58: A -, B ['H61', 'H62']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Usage line range adjusted to the longer header.",
  "file": "evals/harness/spend.sh",
  "group": null,
  "not_defect_class": "docs",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    43
  ],
  "category": null,
  "description": "The usage line range is widened to cover the longer header.",
  "file": "evals/harness/spend.sh",
  "group": "D15",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H59: verdict


Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Replaces the seen set with a max-cost map, part of the dedup fix.",
  "file": "evals/harness/spend.sh",
  "group": "D16",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    121,
    122
  ],
  "category": "logic",
  "description": "Dedup keeps the first-seen row of a run_id, so a run rowed twice (a smoke row, then the graded row) counts whichever cost came first rather than the larger one, which can undercount spend.",
  "file": "evals/harness/spend.sh",
  "group": "D14",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H60: anchors


Annotator A:

```json
{
  "anchor_lines": [
    134,
    135,
    136,
    137,
    138,
    139,
    140
  ],
  "category": "logic",
  "description": "Deduplication keeps the first row seen for a run_id, so a smoke row followed by the graded row under-counts the run's cost depending on file order.",
  "file": "evals/harness/spend.sh",
  "group": "D16",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    134,
    135,
    136,
    137,
    138,
    139,
    140,
    141
  ],
  "category": "logic",
  "description": "A duplicate run_id is skipped once seen, so the counted cost depends on file and row order instead of being the larger cost.",
  "file": "evals/harness/spend.sh",
  "group": "D14",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H61: anchors, group, severity

- group members besides H61: A ['H62'], B ['H58', 'H62']

Annotator A:

```json
{
  "anchor_lines": [
    159,
    160,
    169
  ],
  "category": "error-handling",
  "description": "Skipped malformed lines leave the total a silent lower bound: the JSON has no completeness flag.",
  "file": "evals/harness/spend.sh",
  "group": "D17",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    169
  ],
  "category": "error-handling",
  "description": "The JSON output does not mark a total that skipped malformed lines as incomplete (no complete flag).",
  "file": "evals/harness/spend.sh",
  "group": "D15",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H62: anchors, group, severity

- group members besides H62: A ['H61'], B ['H58', 'H61']

Annotator A:

```json
{
  "anchor_lines": [
    173,
    174
  ],
  "category": "error-handling",
  "description": "With skipped lines the text output does not mark the total incomplete and the script exits 0.",
  "file": "evals/harness/spend.sh",
  "group": "D17",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    159,
    160,
    174
  ],
  "category": "error-handling",
  "description": "When malformed lines are skipped, the total is only a lower bound, yet the script prints it without an INCOMPLETE mark and exits 0.",
  "file": "evals/harness/spend.sh",
  "group": "D15",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H64: group

- group members besides H64: A -, B ['H10', 'H42', 'H43', 'H44', 'H65']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Help line range adjusted to the longer header.",
  "file": "evals/harness/took-effect.sh",
  "group": null,
  "not_defect_class": "docs",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    74
  ],
  "category": null,
  "description": "The --help line range is widened to cover the longer header.",
  "file": "evals/harness/took-effect.sh",
  "group": "D3",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H65: group, severity

- group members besides H65: A ['H10', 'H42', 'H43', 'H44'], B ['H10', 'H42', 'H43', 'H44', 'H64']

Annotator A:

```json
{
  "anchor_lines": [
    86,
    87,
    88
  ],
  "category": "security",
  "description": "took-effect reads the agent-writable sandbox envelope before the harness eval/ copy, so a rewritten sandbox envelope can flip rules like one_voice_planned.",
  "file": "evals/harness/took-effect.sh",
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
    86,
    87,
    88
  ],
  "category": "security",
  "description": "took-effect's envelope() reads the agent-writable sandbox envelope before the harness eval/ copy, so a tampered sandbox envelope decides one_voice_planned.",
  "file": "evals/harness/took-effect.sh",
  "group": "D3",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### I01: category

- invalid: an incident-only defect without a category

Annotator A:

```json
{
  "anchor_lines": [
    79,
    80
  ],
  "description": "The per-run HOME receives a full copy of the host ~/.codex/auth.json including the refresh token, so containers consume the refresh token and kill the host credential and later containers' OpenAI voice.",
  "file": "evals/harness/pipeline-run.sh",
  "group": "D18",
  "severity": "high",
  "verdict": "defect-at-head"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    79,
    80
  ],
  "description": "The per-run container HOME gets a full copy of the host ~/.codex/auth.json, refresh token included, so containers consume the host refresh token and the host and later containers lose Codex auth.",
  "file": "evals/harness/pipeline-run.sh",
  "group": "D16",
  "severity": "high",
  "verdict": "defect-at-head"
}
```

### I03: verdict


Annotator A:

```json
{
  "anchor_lines": [
    486,
    487,
    488
  ],
  "description": "Review-catch sandboxes mount the pinned framework, a later version of the PR-touched files, so the reviewer can diff against the fixed code (answer-key oracle).",
  "file": "evals/harness/pipeline-run.sh",
  "group": "D19",
  "severity": "high",
  "verdict": "defect-at-head"
}
```

Annotator B:

```json
{
  "anchor_lines": [],
  "description": "A mount-design hazard for review-catch tasks (later framework copy exposed), found in a later analysis; nothing in the head text shown points to a specific defect.",
  "file": "evals/harness/pipeline-run.sh",
  "group": null,
  "severity": null,
  "verdict": "not-at-head"
}
```

## Description differences (informational; the merge takes A's text)

- H01

```json
{
  "A": "The image carries an unused rust build stage that cargo-installs beads_rust 0.2.6, a crate the file itself says is not on crates.io, so the build fails or depends on the builder (legacy builder builds every stage).",
  "B": "A dead build stage cargo-installs beads_rust 0.2.6, which the file itself says is not on crates.io, so a builder that builds every stage (the legacy builder) fails the image build."
}
```

- H02

```json
{
  "A": "pip dependencies use >= ranges and bats-core is cloned by a movable tag without a commit check, so a rebuild can silently resolve different code than the batch image.",
  "B": "The pip dependencies use >= ranges and the bats-core clone trusts a movable tag, so a rebuild can pull different, unverified code into the image that is supposed to be reproducible."
}
```

- H08

```json
{
  "A": "--validate never checks the arm against the arm grammar (and only checks one zone_violations array), so rows with malformed arms pass validation.",
  "B": "--validate never checks the arm against the arm grammar (and checks only one zone_violations array), so rows with a malformed arm pass validation."
}
```

- H23

```json
{
  "A": "The arm's effort toggle is put on argv without whitelisting it to low|medium|high|xhigh|max.",
  "B": "The arm's effort toggle reaches the CLI argv without a low|medium|high|xhigh|max whitelist check in this script."
}
```

- H27

```json
{
  "A": "Without bats on PATH the script falls back to executing a host-specific operator dotfiles path, making the fingerprint host-dependent and running an arbitrary binary.",
  "B": "When bats is not on PATH, the script falls back to a host-specific path under the operator's dotfiles and executes it, so the fingerprint depends on that one machine and runs an unexpected binary."
}
```

- H52

```json
{
  "A": "The suite aggregate excludes screen batches by directory name instead of their STATUS screen marker, so a regular batch named screen-* is dropped and a screen batch in another directory is counted.",
  "B": "The aggregate does not filter on the STATUS.json screen marker, so a screen batch in a directory not named screen-* is counted in the suite totals and cuts."
}
```
