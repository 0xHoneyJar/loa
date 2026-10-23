# Adjudication list — pr-14

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

13 item(s) disagree.

### H10: anchors, severity


Annotator A:

```json
{
  "anchor_lines": [
    53,
    55,
    56,
    57
  ],
  "category": "security",
  "description": "When jq is missing, the payload cannot be parsed, or the tool is NotebookEdit (notebook_path), file_path comes out empty and the gate allows the write instead of asking.",
  "file": ".claude/hooks/compliance/implement-gate.sh",
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
    52,
    53,
    55,
    56,
    57
  ],
  "category": "security",
  "description": "An unparsable payload or missing jq yields an empty file_path and the gate allows (fail-open), and NotebookEdit's notebook_path is never read so notebook writes are never gated.",
  "file": ".claude/hooks/compliance/implement-gate.sh",
  "group": "D2",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H11: anchors


Annotator A:

```json
{
  "anchor_lines": [
    73,
    76,
    77,
    78,
    81,
    89,
    90,
    97,
    99
  ],
  "category": "security",
  "description": "Path normalization is a textual prefix test, so /proc/self/cwd/src/x, //ROOT/src/x, ROOT/../name/src/x, a symlinked root or a case variant reaches an App-Zone file without an ask (and writes to the gate's own trust inputs are not checked).",
  "file": ".claude/hooks/compliance/implement-gate.sh",
  "group": "D3",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    73,
    76,
    77,
    78,
    81,
    89,
    97,
    99
  ],
  "category": "security",
  "description": "Path normalisation is a textual prefix test, so /proc/self/cwd/src/x, //ROOT/src/x, ROOT/../<name>/src/x, symlinked roots, case variants or relative paths reach App Zone files unseen and are allowed; trust-input state files are also writable without an ask.",
  "file": ".claude/hooks/compliance/implement-gate.sh",
  "group": "D3",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H15: category


Annotator A:

```json
{
  "anchor_lines": [
    200,
    202,
    203
  ],
  "category": "security",
  "description": "A simstim-state.json with phase implementation counts as active however old it is, so stale state permanently allows App-Zone writes.",
  "file": ".claude/hooks/compliance/implement-gate.sh",
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
    200,
    202,
    203
  ],
  "category": "logic",
  "description": "A simstim-state.json left in phase implementation allows App Zone writes forever, with no staleness check.",
  "file": ".claude/hooks/compliance/implement-gate.sh",
  "group": "D7",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H16: category


Annotator A:

```json
{
  "anchor_lines": [
    209,
    211,
    212
  ],
  "category": "security",
  "description": "A state.json with state RUNNING counts as active with no staleness check, so a leftover run state allows App-Zone writes indefinitely.",
  "file": ".claude/hooks/compliance/implement-gate.sh",
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
    209,
    211,
    212
  ],
  "category": "logic",
  "description": "A state.json left RUNNING allows App Zone writes forever, with no staleness check.",
  "file": ".claude/hooks/compliance/implement-gate.sh",
  "group": "D7",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H17: anchors


Annotator A:

```json
{
  "anchor_lines": [
    230,
    135
  ],
  "category": "contract",
  "description": "The ask is emitted as top-level {\"decision\":\"ask\"}, which the PreToolUse contract does not accept (only approve|block), so the advisory ask is not honoured as an ask.",
  "file": ".claude/hooks/compliance/implement-gate.sh",
  "group": "D6",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    230,
    135,
    228
  ],
  "category": "contract",
  "description": "The ask reply is printed as {\"decision\":\"ask\"}, which the Claude Code PreToolUse contract does not accept (top-level decision is approve|block), so the ask is not honoured; the raw file_path also reaches stderr.",
  "file": ".claude/hooks/compliance/implement-gate.sh",
  "group": "D6",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H26: anchors


Annotator A:

```json
{
  "anchor_lines": [
    62,
    66
  ],
  "category": "input-validation",
  "description": "The refresh carries any seen_at/source value forward from the file without checking its shape.",
  "file": ".claude/scripts/detect-platform-features.sh",
  "group": "D9",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    66
  ],
  "category": "input-validation",
  "description": "The refresh carries active_skill_seen_at and active_skill_source forward unvalidated, preserving arbitrary model-written values.",
  "file": ".claude/scripts/detect-platform-features.sh",
  "group": "D9",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H27: anchors, group, severity

- group members besides H27: A ['H28', 'H51', 'H95'], B ['H28']

Annotator A:

```json
{
  "anchor_lines": [
    582,
    583
  ],
  "category": "security",
  "description": "The inline python runs without -I, so a json.py/yaml.py in the cwd is imported and executed.",
  "file": ".claude/scripts/flatline-orchestrator.sh",
  "group": "D10",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    582
  ],
  "category": "security",
  "description": "The embedded python3 runs without -I, so a json.py/yaml.py in the cwd is imported and can forge the model validation.",
  "file": ".claude/scripts/flatline-orchestrator.sh",
  "group": "D10",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H28: group

- group members besides H28: A ['H27', 'H51', 'H95'], B ['H27']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "argv indices shifted for the new adapters-dir argument.",
  "file": ".claude/scripts/flatline-orchestrator.sh",
  "group": "D10",
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
  "description": "argv indices shifted for the new adapters-dir argument.",
  "file": ".claude/scripts/flatline-orchestrator.sh",
  "group": "D10",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H32: anchors, severity, category


Annotator A:

```json
{
  "anchor_lines": [
    655,
    656,
    657,
    659
  ],
  "category": "resource",
  "description": "A failing mktemp (unusable TMPDIR) breaks the call, and the stderr temp file is leaked when the caller is terminated, since no trap removes it.",
  "file": ".claude/scripts/model-adapter.sh",
  "group": "D12",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    656,
    657,
    659
  ],
  "category": "error-handling",
  "description": "An unusable TMPDIR makes mktemp fail so the call aborts or redirects to an empty path, and the stderr temp file is leaked when the caller is terminated mid-call.",
  "file": ".claude/scripts/model-adapter.sh",
  "group": "D12",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H44: anchors


Annotator A:

```json
{
  "anchor_lines": [
    19,
    52,
    53
  ],
  "category": "logic",
  "description": "Budgets are keyed by bare model id only and there is no alias map, so an alias such as the default `opus` misses its target's budget and gets the 100,000-token default.",
  "file": ".claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts",
  "group": "D14",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    19,
    53
  ],
  "category": "logic",
  "description": "The generated budgets are keyed by bare model id only with no alias map, so an alias such as the default `opus` misses its target's budget and falls to the default entry.",
  "file": ".claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts",
  "group": "D14",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H51: anchors, group, severity

- group members besides H51: A ['H27', 'H28', 'H95'], B -

Annotator A:

```json
{
  "anchor_lines": [
    61,
    62
  ],
  "category": "security",
  "description": "The grader's python runs without -I, so a json.py planted in the invoker's cwd is imported and can forge the grade.",
  "file": "evals/graders/recall-vs-defects.sh",
  "group": "D10",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    61
  ],
  "category": "security",
  "description": "The grader's python3 runs without -I, so a json.py planted in the invoker's cwd is imported and can forge the grade.",
  "file": "evals/graders/recall-vs-defects.sh",
  "group": "D16",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H53: verdict


Annotator A:

```json
{
  "anchor_lines": [
    113
  ],
  "category": "logic",
  "description": "The trailer regex needs exact single spaces and is greedy across comments, so a trailer with other whitespace is missed or the match over-reaches.",
  "file": "evals/graders/recall-vs-defects.sh",
  "group": "D15",
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
  "description": "Trailer read switched to the shared TRAILER pattern.",
  "file": "evals/graders/recall-vs-defects.sh",
  "group": "D15",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H95: anchors, group, severity

- group members besides H95: A ['H27', 'H28', 'H51'], B -

Annotator A:

```json
{
  "anchor_lines": [
    50,
    51
  ],
  "category": "security",
  "description": "The inline python runs without -I, so a module planted in the cwd is imported and can forge the budget check.",
  "file": "tools/check-prompt-budget.sh",
  "group": "D10",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    50
  ],
  "category": "security",
  "description": "The budget checker's python3 runs without -I, so a module planted in the cwd is imported and can forge the check.",
  "file": "tools/check-prompt-budget.sh",
  "group": "D17",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

## Description differences (informational; the merge takes A's text)

- H09

```json
{
  "A": "PROJECT_ROOT defaults to the process cwd, which follows Claude's `cd`, so App-Zone detection and the .run state the gate trusts can be shifted to another directory.",
  "B": "PROJECT_ROOT defaults to the process cwd, which follows Claude's cd, so the gate's zone test and state reads use the wrong root and App Zone writes can be classified outside the project."
}
```

- H12

```json
{
  "A": "The model-authored file_path is echoed raw to stderr, so control and bidi characters reach the operator's terminal.",
  "B": "The model-authored file_path (and active_skill) is echoed to stderr raw, so control and bidi characters reach the operator's terminal."
}
```

- H13

```json
{
  "A": "In authoritative mode a model-authored tool_input.active_skill naming an implementation skill allows the App-Zone write outright, so the model can grant itself permission.",
  "B": "In authoritative mode a model-authored tool_input.active_skill claiming an implementation skill grants an allow by itself, and the ask is emitted in a non-contract top-level decision field."
}
```

- H21

```json
{
  "A": "rule_key does not recognize universal rules (bare Bash, Bash(*), Bash(:*)), so a universal deny is ignored and a universal allow does not satisfy requirements.",
  "B": "rule_key rejects bare Bash and keys Bash(*) / Bash(:*) as an exact or empty-prefix rule, so universal allow or deny rules are not recognised and a universal deny passes the preflight."
}
```

- H22

```json
{
  "A": "The deny check never consults a universal deny, so a requirement denied by Bash(*) is reported effective.",
  "B": "The deny check never consults a universal deny, so every required permission is reported effective despite a Bash deny."
}
```

- H23

```json
{
  "A": "The allow check ignores a universal allow, so requirements covered by bare Bash are reported missing.",
  "B": "The allow check never consults a universal allow, so requirements covered by bare Bash are reported missing."
}
```

- H25

```json
{
  "A": "--line prints active_skill_seen_at and active_skill_source unvalidated, and tr [:cntrl:] leaves Unicode bidi/format characters, so forged evidence reaches /loa output.",
  "B": "The --line evidence prints any seen_at/source value from the file (only C0 stripped), so malformed or forged values and Unicode bidi/zero-width characters reach /loa output."
}
```

- H30

```json
{
  "A": "The stderr copy of a diff header path strips only C0/DEL, so UTF-8 C1 controls (CSI) and bidi code points from a crafted file name reach the terminal.",
  "B": "The stderr copy of a diff header path strips only C0/DEL, so UTF-8 C1 controls (e.g. CSI) and bidi/format code points from a PR file name reach the terminal."
}
```

- H35

```json
{
  "A": "The write-capable agent allowlist can be redirected by the ambient AGENT_TYPES_FILE environment variable, which weakens the invariant check.",
  "B": "The ambient AGENT_TYPES_FILE environment variable silently redirects the write-capable agent allowlist, letting the environment widen the invariant check."
}
```

- H52

```json
{
  "A": "The citation parser credits LOA-VERDICT trailer JSON numbers, URLs, spaced ranges and dates as path:line citations, which inflates recall.",
  "B": "The citation parser credits the LOA-VERDICT trailer and JSON numbers, dates and spaced ranges, URLs and comma continuations across lines as path:line citations, and misses backtick/bold-wrapped paths, so recall is miscounted."
}
```
