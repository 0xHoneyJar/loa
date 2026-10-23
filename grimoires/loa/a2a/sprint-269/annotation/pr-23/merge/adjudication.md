# Adjudication list — pr-23

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

27 item(s) disagree.

### H12: group

- group members besides H12: A ['H21', 'H22', 'H25', 'H26'], B ['H20', 'H28']

Annotator A:

```json
{
  "anchor_lines": [
    167,
    169,
    172
  ],
  "category": null,
  "description": "Imports, version bump and constants (timeouts, caps, harness names) supporting the execution-hardening and related fixes.",
  "file": "evals/harness/ablation-grade.sh",
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
  "description": "Imports, version bump and constants (HARNESS_NAMES, caps, timeout knob) supporting the hardening fixes.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D4",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H13: anchors


Annotator A:

```json
{
  "anchor_lines": [
    238,
    239,
    240,
    241,
    242
  ],
  "category": "security",
  "description": "remove_path chmods every directory entry with os.chmod, which follows symlinks, so an agent-planted link to an outside directory gets that directory's mode changed to 0700.",
  "file": "evals/harness/ablation-grade.sh",
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
    239,
    240,
    242
  ],
  "category": "security",
  "description": "remove_path chmods every walked directory entry with os.chmod, which follows an agent-planted symlink and changes the mode of a directory outside the grading tree.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D2",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H15: anchors


Annotator A:

```json
{
  "anchor_lines": [
    271,
    272,
    273,
    282,
    283,
    293,
    294
  ],
  "category": "security",
  "description": "copy_tree recreates every symlink verbatim, so absolute or tree-escaping links from the agent's sandbox land in the grading tree and point the tests at host paths.",
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
    271,
    272,
    283,
    294
  ],
  "category": "security",
  "description": "copy_tree recreates every symlink from the agent's sandbox verbatim, including absolute or tree-escaping links that commands and later steps then follow outside the grading tree.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D1",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H18: group

- group members besides H18: A ['H19', 'H45', 'H46'], B ['H19', 'H45', 'H46', 'H48', 'H52']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Records the structural check's source path for the refactor hidden-test fix.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D6",
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
  "description": "Records the structural check's source path for the refactor grading fix.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H19: group

- group members besides H19: A ['H18', 'H45', 'H46'], B ['H18', 'H45', 'H46', 'H48', 'H52']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Counts structural cases for the refactor hidden-test fix.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D6",
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
  "description": "Counts the structural check's static cases for the refactor grading fix.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H20: group

- group members besides H20: A ['H28'], B ['H12', 'H28']

Annotator A:

```json
{
  "anchor_lines": [
    493
  ],
  "category": "security",
  "description": "The pytest command honours an agent-written ini file's addopts, so the agent can inject plugins or deselect hidden tests.",
  "file": "evals/harness/ablation-grade.sh",
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
    493
  ],
  "category": "security",
  "description": "The pytest invocation honours an agent-written ini file's addopts, letting the agent inject plugins or deselect hidden tests.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D4",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H21: anchors, group

- group members besides H21: A ['H12', 'H22', 'H25', 'H26'], B ['H22', 'H25', 'H26']

Annotator A:

```json
{
  "anchor_lines": [
    502,
    503,
    504,
    505,
    506,
    507,
    508
  ],
  "category": "resource",
  "description": "The grading container runs unnamed with no pid/memory/cpu limits, capabilities intact and a plain timeout without kill-after, so a hung or runaway container cannot be killed or cleaned up.",
  "file": "evals/harness/ablation-grade.sh",
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
    506,
    507,
    508
  ],
  "category": "resource",
  "description": "The grading container runs unnamed without pid/memory/cpu limits, capability drop, init or a kill-after deadline, so a hung or forking agent program cannot be reliably stopped or cleaned up.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D5",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H22: anchors, group

- group members besides H22: A ['H12', 'H21', 'H25', 'H26'], B ['H21', 'H25', 'H26']

Annotator A:

```json
{
  "anchor_lines": [
    514,
    516,
    517,
    518,
    519,
    520,
    521,
    524
  ],
  "category": "resource",
  "description": "subprocess.run buffers unbounded output and on client timeout leaves the docker container running (no kill/rm), and timed_out only recognises rc 124.",
  "file": "evals/harness/ablation-grade.sh",
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
    514,
    517,
    518,
    521,
    524
  ],
  "category": "resource",
  "description": "subprocess.run captures unbounded output and on client timeout leaves the container running (no kill/rm) and misses 137 kills as timeouts.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D5",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H23: anchors


Annotator A:

```json
{
  "anchor_lines": [
    533,
    534,
    535,
    536,
    537,
    538
  ],
  "category": "security",
  "description": "def_line opens whatever path the test output names (absolute, above the tree, a FIFO or device) with no bounds, so agent-printed node ids can hang or exhaust the grader.",
  "file": "evals/harness/ablation-grade.sh",
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
    536
  ],
  "category": "security",
  "description": "def_line opens any node path printed by code under test (absolute, outside the tree, a FIFO or device) and reads it whole, allowing hangs or reads outside the tree.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D6",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H24: anchors


Annotator A:

```json
{
  "anchor_lines": [
    575,
    576,
    577
  ],
  "category": "security",
  "description": "Collection-error expansion opens the agent-printed path unbounded, so /dev/zero or a FIFO blocks or exhausts the grader.",
  "file": "evals/harness/ablation-grade.sh",
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
    576
  ],
  "category": "security",
  "description": "Collection-error expansion opens an agent-printed path unbounded and unchecked (FIFO, /dev/zero, path above the tree).",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D6",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H25: group

- group members besides H25: A ['H12', 'H21', 'H22', 'H26'], B ['H21', 'H22', 'H26']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Caller updated for exec_in_tree's new return tuple.",
  "file": "evals/harness/ablation-grade.sh",
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
  "description": "Caller updated for exec_in_tree's new return tuple.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D5",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H26: group

- group members besides H26: A ['H12', 'H21', 'H22', 'H25'], B ['H21', 'H22', 'H25']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Propagates output_truncated into results.",
  "file": "evals/harness/ablation-grade.sh",
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
  "description": "Propagates output_truncated into results.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D5",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H27: anchors, group, severity

- group members besides H27: A ['H48'], B -

Annotator A:

```json
{
  "anchor_lines": [
    652,
    653,
    1091,
    1092,
    1093,
    1095
  ],
  "category": "logic",
  "description": "all_pass ignores the exit status and timeout (a passing TAP block followed by exit 1 is green), and regressions ignore exit statuses when either side is unparseable.",
  "file": "evals/harness/ablation-grade.sh",
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
    652,
    653
  ],
  "category": "logic",
  "description": "all_pass treats a run as green ignoring the exit status and timeout, so a passing TAP block followed by exit 1 or a timed-out run counts as green.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D9",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H28: group

- group members besides H28: A ['H20'], B ['H12', 'H20']

Annotator A:

```json
{
  "anchor_lines": [
    673,
    674
  ],
  "category": "security",
  "description": "prepare never removes agent-written conftest.py, ini files or bats helpers, so an agent hookwrapper can flip failures to passes before the hidden tests run.",
  "file": "evals/harness/ablation-grade.sh",
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
    673,
    674
  ],
  "category": "security",
  "description": "prepare leaves agent-written conftest.py, ini files and bats helpers/setup_suite in the grading tree, so the agent can make failing hidden tests pass.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D4",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H30: anchors


Annotator A:

```json
{
  "anchor_lines": [
    705,
    706,
    707,
    708
  ],
  "category": "resource",
  "description": "Snapshot extraction writes tar members of any size, so a huge or sparse file becomes a dense write on the grader.",
  "file": "evals/harness/ablation-grade.sh",
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
    705,
    706,
    707,
    710
  ],
  "category": "resource",
  "description": "Snapshot extraction writes tar members of any size, so a huge file in a snapshot is materialised in full.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D3",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H34: verdict


Annotator A:

```json
{
  "anchor_lines": [
    743,
    744,
    745
  ],
  "category": "resource",
  "description": "churn diffs oversized files instead of counting them as changed unread.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D9",
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
  "description": "Counts oversized files as changed in churn.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D3",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H35: anchors


Annotator A:

```json
{
  "anchor_lines": [
    766,
    767,
    769
  ],
  "category": "security",
  "description": "gate_verdict follows a symlinked feedback file (reading outside the sandbox) and reads it unbounded, possibly blocking on a FIFO.",
  "file": "evals/harness/ablation-grade.sh",
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
    766,
    769
  ],
  "category": "security",
  "description": "gate_verdict follows a symlinked feedback file (os.path.isfile + open) and reads it unbounded, so an agent can point the verdict at an outside file or a FIFO.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D7",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H37: severity


Annotator A:

```json
{
  "anchor_lines": [
    855
  ],
  "category": "resource",
  "description": "envelope_texts reads the envelope JSON without a size bound or non-regular-file refusal.",
  "file": "evals/harness/ablation-grade.sh",
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
    855
  ],
  "category": "resource",
  "description": "Envelope JSON is read without size bound or non-blocking regular-file check.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D7",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H38: anchors


Annotator A:

```json
{
  "anchor_lines": [
    877,
    878,
    881
  ],
  "category": "security",
  "description": "combined_findings reads sandbox files unbounded and does not refuse a path through a symlinked parent directory outside the sandbox.",
  "file": "evals/harness/ablation-grade.sh",
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
    877,
    878
  ],
  "category": "security",
  "description": "Citation sources are read whole without a size cap or a check that the path resolves inside the sandbox (a symlinked parent is followed).",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D7",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H39: verdict


Annotator A:

```json
{
  "anchor_lines": [
    940
  ],
  "category": "security",
  "description": "The contamination scan has no pattern for ~/, $HOME/ or /proc/*/environ and /var/run, so home-relative and secret-bearing reads are not flagged.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D12",
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
  "description": "Adds HOME_WORD and SENSITIVE patterns for the contamination fix.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D11",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H45: anchors, group

- group members besides H45: A ['H18', 'H19', 'H46'], B ['H18', 'H19', 'H46', 'H48', 'H52']

Annotator A:

```json
{
  "anchor_lines": [
    1080,
    1083,
    1099,
    1100,
    1101,
    1102,
    1105
  ],
  "category": "logic",
  "description": "For refactor tasks hidden_tests is the fixture suite (test_command) instead of the structural check, so the pass rate and accuracy measure the wrong assertion.",
  "file": "evals/harness/ablation-grade.sh",
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
    1080,
    1083,
    1089,
    1090,
    1091,
    1092,
    1093,
    1099,
    1100,
    1101,
    1102,
    1105
  ],
  "category": "logic",
  "description": "For refactor tasks hidden_tests is the fixture suite rather than the structural check (an untouched tree scores 1.0), and the regression logic mis-handles an unparseable base or final run.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D8",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H46: group

- group members besides H46: A ['H18', 'H19', 'H45'], B ['H18', 'H19', 'H45', 'H48', 'H52']

Annotator A:

```json
{
  "anchor_lines": [
    1121,
    1122,
    1129
  ],
  "category": "logic",
  "description": "Snapshot trees of refactor tasks are graded with test_command rather than the structural check plus suite, so per-gate verdict accuracy is wrong.",
  "file": "evals/harness/ablation-grade.sh",
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
    1121,
    1122,
    1129
  ],
  "category": "logic",
  "description": "Snapshot trees for refactor gates are judged by test_command alone instead of the structural check plus suite, so per-gate verdict accuracy is wrong.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D8",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H48: anchors, group

- group members besides H48: A ['H27'], B ['H18', 'H19', 'H45', 'H46', 'H52']

Annotator A:

```json
{
  "anchor_lines": [
    1219,
    1222,
    1224
  ],
  "category": "logic",
  "description": "Self-check treats the suite and hidden tests as green from counts alone, ignoring exit status, timeout and parse errors.",
  "file": "evals/harness/ablation-grade.sh",
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
    1209,
    1211,
    1214,
    1216,
    1219,
    1224
  ],
  "category": "logic",
  "description": "Self-check judges green by pass counts only (ignoring exit status, timeout and parse errors) and uses the old refactor structural split.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D8",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H49: anchors


Annotator A:

```json
{
  "anchor_lines": [
    1240,
    1241
  ],
  "category": "security",
  "description": "--executor host runs agent code unisolated on the host with no opt-in or warning.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D11",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    1240
  ],
  "category": "security",
  "description": "--executor host runs agent code on the host as the calling user without isolation and without any opt-in or warning.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D12",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H52: group

- group members besides H52: A -, B ['H18', 'H19', 'H45', 'H46', 'H48']

Annotator A:

```json
{
  "anchor_lines": [
    261,
    262
  ],
  "category": "input-validation",
  "description": "A refactor task with a non-null regression_command is accepted although the grader uses test_command as its regression check.",
  "file": "evals/harness/validate-suite.sh",
  "group": "D14",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    261,
    262
  ],
  "category": "input-validation",
  "description": "validate-suite accepts a refactor task with a regression_command, which conflicts with test_command being the refactor regression check.",
  "file": "evals/harness/validate-suite.sh",
  "group": "D8",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H53: anchors


Annotator A:

```json
{
  "anchor_lines": [
    279,
    280
  ],
  "category": "input-validation",
  "description": "Validation does not require grader_protected to list every fixture/tests/ file, so agent-edited fixture tests can survive grading.",
  "file": "evals/harness/validate-suite.sh",
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
    276,
    279,
    280
  ],
  "category": "input-validation",
  "description": "validate-suite does not require grader_protected to list every fixture/tests file, so agent-edited fixture tests are not restored before grading.",
  "file": "evals/harness/validate-suite.sh",
  "group": "D13",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### I01: anchors


Annotator A:

```json
{
  "anchor_lines": [
    939,
    940,
    976,
    977,
    978,
    979,
    980
  ],
  "description": "The contamination scan's ABS_WORD/GIT_HIST heuristics flag ordinary agent text (slash commands like /review-sprint, heredoc prose, sed ranges) as outside_path or git_history, marking clean runs contaminated.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D15",
  "severity": "medium",
  "verdict": "defect-at-head"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    940,
    976,
    977,
    978,
    980,
    982
  ],
  "description": "The contamination scan's ABS_WORD path heuristic flags ordinary agent text (slash commands like /review-sprint, sed ranges, heredoc prose) as outside_path, marking clean runs contaminated.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D14",
  "severity": "medium",
  "verdict": "defect-at-head"
}
```

## Description differences (informational; the merge takes A's text)

- H16

```json
{
  "A": "A directory symlink is copied without checking that its target stays inside the tree.",
  "B": "A directory symlink is recreated in the grading tree regardless of whether its target escapes the tree."
}
```

- H17

```json
{
  "A": "A file symlink is copied without checking for an escaping target (and regular files of any size are copied densely).",
  "B": "A file symlink is recreated regardless of an escaping target (and regular files of any size are copied densely, e.g. a sparse 1 TB file)."
}
```

- H31

```json
{
  "A": "Snapshot extraction relies on data_filter alone, which misses a link that escapes only through another link in the tree.",
  "B": "data_filter judges members in archive order, so a snapshot symlink escaping via a later link survives extraction."
}
```

- H33

```json
{
  "A": "churn reads whole files of any size (and opens non-regular files such as FIFOs), so a huge file or FIFO exhausts or blocks the grader.",
  "B": "churn reads every file whole into memory with no size bound or file-type check."
}
```

- H40

```json
{
  "A": "Host-mode allowed roots exempt the caller's ~/.claude, ~/.claude.json, ~/.codex and ~/.aws credential stores from the outside_path check.",
  "B": "Host-mode contamination scan exempts the caller's credential stores (~/.claude, ~/.codex, ~/.aws), so reading them is never flagged."
}
```

- H41

```json
{
  "A": "outside() treats /proc/<pid>/environ etc. and /var/run as allowed and never flags home-relative paths.",
  "B": "outside() treats ~/ and $HOME/ paths and /proc/<pid>/environ or /var/run as allowed, missing credential reaches."
}
```

- H42

```json
{
  "A": "Bash scanning skips every one-component /x/ word as a regex (so `cd /root/` is never flagged) and ignores ~/ and $HOME/ words.",
  "B": "Bash scanning ignores home-relative words and skips every one-component /x/ word as a regex, so `cd /root/` or `cat ~/.aws/credentials` is never flagged."
}
```
