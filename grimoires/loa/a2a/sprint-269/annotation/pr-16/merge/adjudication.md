# Adjudication list — pr-16

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

11 item(s) disagree.

### H01: anchors


Annotator A:

```json
{
  "anchor_lines": [
    188,
    189,
    190,
    191,
    192
  ],
  "category": "security",
  "description": "Untrusted decision-row text is emitted into the TSV/JSON/INDEX.md index with < and > (e.g. <script>) and C1 controls not reliably neutralised, letting agent-authored markup reach the rendered index.",
  "file": ".claude/scripts/grimoire-index.sh",
  "group": "D1",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    186,
    187,
    189,
    190,
    191,
    192
  ],
  "category": "security",
  "description": "Untrusted agent-authored decision rows are only partly sanitised: C1 controls are not reliably flattened and < and > pass through, so markup such as <script> reaches the TSV, JSON and INDEX.md output.",
  "file": ".claude/scripts/grimoire-index.sh",
  "group": "D1",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H02: anchors


Annotator A:

```json
{
  "anchor_lines": [
    250,
    251,
    252,
    253
  ],
  "category": "security",
  "description": "Any --file target is classed as a fixture, so naming the live ledger or a pending file by path bypasses the CI/hook write refusal and the linked-worktree rule.",
  "file": ".claude/scripts/lib/dec-write-lib.sh",
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
    250,
    251,
    252,
    253,
    261
  ],
  "category": "security",
  "description": "Any --file target is treated as a fixture and returns before the CI/hook check, so naming the live ledger or a pending file by path writes it from CI, a hook or a linked worktree.",
  "file": ".claude/scripts/lib/dec-write-lib.sh",
  "group": "D2",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H03: category


Annotator A:

```json
{
  "anchor_lines": [
    626,
    627
  ],
  "category": "input-validation",
  "description": "import accepts --rewrite targets without checking them, so files outside the project, paths with '..', symlinks or missing files are rewritten (or fail mid-import after the ledger is changed).",
  "file": ".claude/scripts/lib/dec-write-lib.sh",
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
    626,
    627
  ],
  "category": "security",
  "description": "import never checks --rewrite targets, so it rewrites files outside the project, through '..' paths or symlinks, and fails on missing files only after the ledger has been written.",
  "file": ".claude/scripts/lib/dec-write-lib.sh",
  "group": "D3",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H04: group

- group members besides H04: A ['H05', 'H06', 'H07'], B -

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Documentation updated to say interview.pacing is unset by default, following the config example fix.",
  "file": ".claude/skills/discovering-requirements/resources/REFERENCE.md",
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
  "description": "Doc sentence updated to say pacing is unset by default, to match the config example fix.",
  "file": ".claude/skills/discovering-requirements/resources/REFERENCE.md",
  "group": null,
  "not_defect_class": "docs",
  "severity": null,
  "verdict": "not-defect"
}
```

### H05: group

- group members besides H05: A ['H04', 'H06', 'H07'], B -

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Comment updated to state pacing is unset by default.",
  "file": ".loa.config.yaml.example",
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
  "description": "Comment reworded to say pacing is unset by default.",
  "file": ".loa.config.yaml.example",
  "group": null,
  "not_defect_class": "docs",
  "severity": null,
  "verdict": "not-defect"
}
```

### H06: group

- group members besides H06: A ['H04', 'H05', 'H07'], B -

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Comment updated to describe the unset pacing default.",
  "file": ".loa.config.yaml.example",
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
  "description": "Comment reworded to describe the unset default.",
  "file": ".loa.config.yaml.example",
  "group": null,
  "not_defect_class": "docs",
  "severity": null,
  "verdict": "not-defect"
}
```

### H07: anchors, group, category

- group members besides H07: A ['H04', 'H05', 'H06'], B -

Annotator A:

```json
{
  "anchor_lines": [
    140,
    127
  ],
  "category": "logic",
  "description": "The shipped example sets pacing: rounds explicitly, which overrides the mode default so minimal mode gets rounds instead of its documented batch pacing.",
  "file": ".loa.config.yaml.example",
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
    140
  ],
  "category": "contract",
  "description": "The example sets pacing: rounds explicitly, and an explicit value wins, so a copied config makes minimal mode use rounds instead of its documented batch default.",
  "file": ".loa.config.yaml.example",
  "group": "D4",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H12: group

- group members besides H12: A -, B ['H13']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Test-helper change: comments and locals of check_operative reworked for the new exemption logic (the helper exempted a whole line if an exempt word appeared anywhere).",
  "file": "tests/unit/user-invoked-commands.bats",
  "group": null,
  "not_defect_class": "test",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Removes the regex/exempt variables and rewrites the header comment for the awk-based check in H13.",
  "file": "tests/unit/user-invoked-commands.bats",
  "group": "D5",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H13: verdict


Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Test-helper change: check_operative now judges only the clause before the verb match instead of exempting any line containing an exempt word.",
  "file": "tests/unit/user-invoked-commands.bats",
  "group": null,
  "not_defect_class": "test",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    65,
    69,
    74,
    75
  ],
  "category": "logic",
  "description": "The operative-reference check drops any line containing an exempt word anywhere (e.g. 'Run /alpha on the operator's behalf'), so operative invocations go unreported; this is an invariant-check helper in a test file, so the defect is in the guard rather than shipped code.",
  "file": "tests/unit/user-invoked-commands.bats",
  "group": "D5",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H16: anchors, category


Annotator A:

```json
{
  "anchor_lines": [
    71,
    72,
    73,
    74,
    75,
    77,
    79,
    82
  ],
  "category": "error-handling",
  "description": "Block contents and accumulated rounds are passed to jq as argv strings, so large transcripts or blocks crash on the per-argument size limit; the validation also accepts two JSON values in one block and unvalidated ids.",
  "file": "tools/check-round-independence.sh",
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
    65,
    71,
    72,
    73,
    74,
    75,
    77,
    79,
    82
  ],
  "category": "input-validation",
  "description": "Block contents and the accumulated rounds go to jq as argv strings, so transcripts over the 128 KiB argument limit crash; jq -e also accepts a block holding two JSON values and does not validate id characters.",
  "file": "tools/check-round-independence.sh",
  "group": "D6",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H18: anchors


Annotator A:

```json
{
  "anchor_lines": [
    139,
    140,
    142,
    73
  ],
  "category": "security",
  "description": "Untrusted question ids are printed raw to the terminal, so ESC/control characters in a transcript reach the output.",
  "file": "tools/check-round-independence.sh",
  "group": "D6",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    139,
    140,
    142,
    143
  ],
  "category": "security",
  "description": "The human-readable report prints ids and violation text unescaped, so control characters such as ESC from untrusted transcript ids reach the terminal.",
  "file": "tools/check-round-independence.sh",
  "group": "D7",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```
