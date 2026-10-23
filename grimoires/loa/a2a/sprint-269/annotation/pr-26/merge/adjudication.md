# Adjudication list — pr-26

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

23 item(s) disagree.

### H08: verdict


Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Adds arm/task grammar constants used by the grader-tally path fix.",
  "file": "evals/harness/ablation-report.py",
  "group": "D1",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    1054,
    1057,
    1070,
    1072
  ],
  "category": "security",
  "description": "Row arm and task_id values are joined into filesystem paths without any grammar check, so an arm like '../..' makes the batch record read grade.json files outside the batch directory.",
  "file": "evals/harness/ablation-report.py",
  "group": "D6",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H12: group

- group members besides H12: A -, B ['H19', 'H28']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Extracts the provenance check and listing reasons into helpers with the same order and behaviour.",
  "file": "evals/harness/ablation-report.py",
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
  "description": "Extracts provenance_check and list_reason so partition can reuse the listing logic; same order of checks in _classify.",
  "file": "evals/harness/ablation-report.py",
  "group": "D1",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H15: verdict


Annotator A:

```json
{
  "anchor_lines": [
    757,
    758
  ],
  "category": "input-validation",
  "description": "nums() accepts NaN/infinite floats, so per-run means become NaN.",
  "file": "evals/harness/ablation-report.py",
  "group": "D3",
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
  "description": "nums() also skips non-finite values via is_num.",
  "file": "evals/harness/ablation-report.py",
  "group": "D10",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H16: verdict


Annotator A:

```json
{
  "anchor_lines": [
    773,
    776,
    778
  ],
  "category": "input-validation",
  "description": "Precision sums accept non-finite numbers and the cost read crashes on a non-numeric cost_usd.",
  "file": "evals/harness/ablation-report.py",
  "group": "D3",
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
  "description": "Same numeric-guard correction applied to the precision computation's cost read.",
  "file": "evals/harness/ablation-report.py",
  "group": "D10",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H17: verdict


Annotator A:

```json
{
  "anchor_lines": [
    797,
    798
  ],
  "category": "input-validation",
  "description": "cost_per_task crashes on a non-numeric cost_usd and cost_per_run ignores bad values inconsistently/propagates NaN.",
  "file": "evals/harness/ablation-report.py",
  "group": "D3",
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
  "description": "Same numeric-guard correction for cost_per_task and cost_per_run.",
  "file": "evals/harness/ablation-report.py",
  "group": "D10",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H18: anchors


Annotator A:

```json
{
  "anchor_lines": [
    825,
    827,
    831,
    832,
    833,
    835,
    839,
    840
  ],
  "category": "logic",
  "description": "version_key treats a non-integer float suite_version (2.1) as absent and keeps \"2.0\" distinct from 2, and version_order only handles digit keys, so versions are mis-partitioned or mis-sorted.",
  "file": "evals/harness/ablation-report.py",
  "group": "D4",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    827,
    831,
    832,
    833,
    835,
    836,
    840
  ],
  "category": "logic",
  "description": "version_key returns None for a non-integer float suite_version (e.g. 2.1), treating it as absent, and version_order only treats pure-digit keys as numeric, so non-integer versions are mispartitioned and missorted.",
  "file": "evals/harness/ablation-report.py",
  "group": "D2",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H19: group

- group members besides H19: A ['H28'], B ['H12', 'H28']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Returns the new unversioned list from partition.",
  "file": "evals/harness/ablation-report.py",
  "group": "D5",
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
  "description": "partition returns the listed version-less rows as a third value.",
  "file": "evals/harness/ablation-report.py",
  "group": "D1",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H20: verdict


Annotator A:

```json
{
  "anchor_lines": [
    965,
    968
  ],
  "category": "input-validation",
  "description": "Budget-matched cost sums crash on a non-numeric cost_usd and propagate NaN.",
  "file": "evals/harness/ablation-report.py",
  "group": "D3",
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
  "description": "Same numeric-guard correction for budget-matched cost reads.",
  "file": "evals/harness/ablation-report.py",
  "group": "D10",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H22: anchors, group, severity

- group members besides H22: A ['H08'], B -

Annotator A:

```json
{
  "anchor_lines": [
    1054,
    1062,
    1063,
    1064,
    1065,
    1066,
    1069,
    1070,
    1080,
    1081,
    1082
  ],
  "category": "logic",
  "description": "The grader tally counts every matching run directory of a row (reruns counted several times), its sort key mixes int and str segments (TypeError on e.g. 1.2.0 vs 1.2.0-rc1, aborting the report), and it builds paths from unvalidated row arm/task_id that can escape the batch directory.",
  "file": "evals/harness/ablation-report.py",
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
    1062,
    1063,
    1064,
    1065,
    1066,
    1067,
    1068,
    1069,
    1080,
    1081,
    1082
  ],
  "category": "logic",
  "description": "The grader tally counts every run directory matching a row's task and trial (base plus all reruns) instead of the row's own one, does not count directory-less rows as n/a, and sorts with a key mixing int and str segments that raises TypeError (e.g. 1.2.0 vs 1.2.0-rc1).",
  "file": "evals/harness/ablation-report.py",
  "group": "D4",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H23: verdict


Annotator A:

```json
{
  "anchor_lines": [
    1117
  ],
  "category": "contract",
  "description": "budget_json emits suite_version as a string key rather than a typed JSON value, inconsistent with primary_suite_version.",
  "file": "evals/harness/ablation-report.py",
  "group": "D7",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Budget JSON suite_version typed via version_value.",
  "file": "evals/harness/ablation-report.py",
  "group": "D3",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H25: verdict


Annotator A:

```json
{
  "anchor_lines": [
    1321
  ],
  "category": "input-validation",
  "description": "Cap-failure rendering crashes on a non-numeric cost_usd.",
  "file": "evals/harness/ablation-report.py",
  "group": "D3",
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
  "description": "Same numeric-guard correction in the cap-failure listing.",
  "file": "evals/harness/ablation-report.py",
  "group": "D10",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H26: anchors


Annotator A:

```json
{
  "anchor_lines": [
    1339
  ],
  "category": "contract",
  "description": "h1_json emits suite_version as a string key, not a typed value.",
  "file": "evals/harness/ablation-report.py",
  "group": "D7",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    1339,
    1351,
    1592,
    1611,
    1117
  ],
  "category": "contract",
  "description": "JSON version values are emitted with inconsistent types (string keys in h1/a4/by_suite_version, int only for digit-only primary, string for a numeric '2.1'), violating the documented typed contract.",
  "file": "evals/harness/ablation-report.py",
  "group": "D3",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H27: verdict


Annotator A:

```json
{
  "anchor_lines": [
    1351
  ],
  "category": "contract",
  "description": "a4_json emits suite_version as a string key, not a typed value.",
  "file": "evals/harness/ablation-report.py",
  "group": "D7",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Same typing correction for a4_json.",
  "file": "evals/harness/ablation-report.py",
  "group": "D3",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H28: group

- group members besides H28: A ['H19'], B ['H12', 'H19']

Annotator A:

```json
{
  "anchor_lines": [
    847,
    848,
    849,
    850,
    851,
    1403
  ],
  "category": "logic",
  "description": "Among two or more suite versions any version-less row aborts the report with exit 2, even one (smoke batch, no manifest, arm not run) that would only be listed and never decided.",
  "file": "evals/harness/ablation-report.py",
  "group": "D5",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    1403,
    847,
    848,
    849,
    850,
    851
  ],
  "category": "logic",
  "description": "Among two or more suite versions, any row without suite_version aborts the report with exit 2 even when it would only be listed (smoke batch, no manifest, arm not run), instead of listing it.",
  "file": "evals/harness/ablation-report.py",
  "group": "D1",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H30: verdict


Annotator A:

```json
{
  "anchor_lines": [
    1592
  ],
  "category": "contract",
  "description": "by_suite_version[N].suite_version is emitted as a string, not a typed value.",
  "file": "evals/harness/ablation-report.py",
  "group": "D7",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Same typing correction for version_json.",
  "file": "evals/harness/ablation-report.py",
  "group": "D3",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H31: verdict


Annotator A:

```json
{
  "anchor_lines": [
    1611
  ],
  "category": "contract",
  "description": "primary_suite_version is a string for a non-integer numeric key such as 2.1.",
  "file": "evals/harness/ablation-report.py",
  "group": "D7",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Same typing correction for primary_suite_version.",
  "file": "evals/harness/ablation-report.py",
  "group": "D3",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H34: anchors


Annotator A:

```json
{
  "anchor_lines": [
    1675,
    1677
  ],
  "category": "contract",
  "description": "json.dumps without allow_nan=False writes non-standard NaN/Infinity tokens into report.json, and the markdown is written before the JSON is serialised.",
  "file": "evals/harness/ablation-report.py",
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
    1675,
    1676,
    1677
  ],
  "category": "contract",
  "description": "The JSON twin is serialised with the default allow_nan, writing non-standard NaN/Infinity tokens (invalid JSON), and only after report.md is already written.",
  "file": "evals/harness/ablation-report.py",
  "group": "D11",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H37: group

- group members besides H37: A -, B ['H38', 'H39', 'H40', 'H41', 'H42']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Help sed range adjusted for the longer header.",
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
  "anchor_lines": [],
  "category": null,
  "description": "Help range extended for the longer header.",
  "file": "evals/harness/ablation-row.sh",
  "group": "D9",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H38: group

- group members besides H38: A ['H39', 'H40', 'H41', 'H42'], B ['H37', 'H39', 'H40', 'H41', 'H42']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Defines the shared jq missed_rule used by validate and the row program.",
  "file": "evals/harness/ablation-row.sh",
  "group": "D9",
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
  "description": "Defines the shared jq missed_rule definition.",
  "file": "evals/harness/ablation-row.sh",
  "group": "D9",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H39: group

- group members besides H39: A ['H38', 'H40', 'H41', 'H42'], B ['H37', 'H38', 'H40', 'H41', 'H42']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Prepends the rules definition to the validate jq program.",
  "file": "evals/harness/ablation-row.sh",
  "group": "D9",
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
  "description": "Prepends the rule definition to the validate program.",
  "file": "evals/harness/ablation-row.sh",
  "group": "D9",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H40: group

- group members besides H40: A ['H38', 'H39', 'H41', 'H42'], B ['H37', 'H38', 'H39', 'H41', 'H42']

Annotator A:

```json
{
  "anchor_lines": [
    165,
    166,
    167,
    168
  ],
  "category": "input-validation",
  "description": "--validate accepts a defects_missed list with malformed, duplicate or out-of-range ids or one contradicting defects_seeded/defects_caught.",
  "file": "evals/harness/ablation-row.sh",
  "group": "D9",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    165,
    166,
    167,
    168
  ],
  "category": "input-validation",
  "description": "--validate accepts any list of non-empty strings as defects_missed, including malformed, duplicate, out-of-range or count-inconsistent ids.",
  "file": "evals/harness/ablation-row.sh",
  "group": "D9",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H41: group

- group members besides H41: A ['H38', 'H39', 'H40', 'H42'], B ['H37', 'H38', 'H39', 'H40', 'H42']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Prepends the rules definition to the row program.",
  "file": "evals/harness/ablation-row.sh",
  "group": "D9",
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
  "description": "Prepends the rule definition to the row program.",
  "file": "evals/harness/ablation-row.sh",
  "group": "D9",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H42: group

- group members besides H42: A ['H38', 'H39', 'H40', 'H41'], B ['H37', 'H38', 'H39', 'H40', 'H41']

Annotator A:

```json
{
  "anchor_lines": [
    412,
    413
  ],
  "category": "input-validation",
  "description": "The row writer copies any list of non-empty strings into defects_missed, even one inconsistent with the seeded/caught counts.",
  "file": "evals/harness/ablation-row.sh",
  "group": "D9",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    412,
    413
  ],
  "category": "input-validation",
  "description": "The row writer copies recall.missed verbatim whenever it is a list of non-empty strings, emitting inconsistent id lists instead of null.",
  "file": "evals/harness/ablation-row.sh",
  "group": "D9",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

## Description differences (informational; the merge takes A's text)

- H13

```json
{
  "A": "defect_vector trusts any list of strings in defects_missed as per-defect ids, even ids outside d1..dN, duplicates, or lists contradicting defects_caught, producing wrong per-defect catch values.",
  "B": "defect_vector trusts any list of strings in defects_missed as per-defect ids, even ids outside d1..dN, duplicates, or lists contradicting defects_caught, producing wrong per-defect catch figures."
}
```

- H14

```json
{
  "A": "float(r.get('cost_usd') or 0) crashes on a non-numeric string cost and propagates NaN/inf into cost means.",
  "B": "Cost and wall-clock reads use float(r.get(...) or 0), which crashes on a non-numeric string and propagates NaN/infinity into the means."
}
```

- H29

```json
{
  "A": "An exception while computing or rendering the presentation-only batch record aborts the whole report instead of degrading.",
  "B": "The presentation-only batch record is computed and rendered without any guard, so any exception in it (e.g. the grader sort TypeError or an int() refusal) aborts the whole report."
}
```
