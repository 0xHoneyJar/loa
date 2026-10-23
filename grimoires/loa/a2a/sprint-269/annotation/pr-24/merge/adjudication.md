# Adjudication list — pr-24

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

11 item(s) disagree.

### H05: severity, category


Annotator A:

```json
{
  "anchor_lines": [
    1329
  ],
  "category": "logic",
  "description": "HIDDEN_TOKEN only matches lowercase adjacency, so Bash probes like Hidden/x, hiddenTests/, HiddenTests/, '*hidden*' globs and `cd hidden` are not flagged as contamination.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D5",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    1329
  ],
  "category": "security",
  "description": "HIDDEN_TOKEN only matches lowercase adjacency and HIDDEN, so Bash probes like `ls Hidden/x`, `ls hiddenTests/`, `find . -iname '*hidden*'` or `cd hidden` are not flagged as contamination.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D2",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H06: anchors, group, category

- group members besides H06: A -, B ['H12']

Annotator A:

```json
{
  "anchor_lines": [
    1377,
    1369,
    1372,
    1373,
    1374
  ],
  "category": "logic",
  "description": "The HEREDOC regex with re.S and a lazy (?:.*?\\n)*? body backtracks catastrophically on a << that is not a heredoc ($((1<<n)), <<<) and drops the operator-line remainder. The same hunk also fixes the in_quotes parity count and the empty-quote glued-token case in after_closing_quote.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D2",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    1369,
    1372,
    1373,
    1374
  ],
  "category": "security",
  "description": "in_quotes uses a quote parity count, so a sensitive word that is the whole quoted argument (cd \"/root\", ls '/home') is skipped as pattern text and parity is thrown off by apostrophes; the same hunk also fixes after_closing_quote treating ''/root/x as a glued tail and the backtracking-prone heredoc regex.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D3",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H07: anchors


Annotator A:

```json
{
  "anchor_lines": [
    1383
  ],
  "category": "security",
  "description": "strip_heredocs replaces the whole operator line after <<WORD, so a redirect, pipe or argument such as `cat <<'EOF' > /root/x` is never path-scanned.",
  "file": "evals/harness/ablation-grade.sh",
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
    1377,
    1383
  ],
  "category": "security",
  "description": "strip_heredocs replaces the heredoc together with the rest of its operator line, so a redirect or argument after <<WORD (cat <<'EOF' > /root/x) is never path-scanned, and the re.S lazy regex can backtrack heavily on << that is not a heredoc.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D4",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H08: severity, category


Annotator A:

```json
{
  "anchor_lines": [
    1395
  ],
  "category": "logic",
  "description": "The Bash hidden check uses only HIDDEN_TOKEN, so glob and filesystem-probe shapes of hidden go undetected.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D5",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    1395
  ],
  "category": "security",
  "description": "The Bash hidden check only consults HIDDEN_TOKEN, missing glob and filesystem-probe shapes of hidden.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D2",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H10: severity


Annotator A:

```json
{
  "anchor_lines": [
    1422,
    1423
  ],
  "category": "security",
  "description": "A globbed one-component word (/roo*, /ro?t) is read as a slash-command token and skipped, so a glob that reaches /root evades the outside_path check.",
  "file": "evals/harness/ablation-grade.sh",
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
    1422,
    1423
  ],
  "category": "security",
  "description": "A globbed one-component word such as /roo* or /ro?t tokenises to a non-sensitive single component and is skipped, letting a glob reach /root unseen.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D5",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H12: verdict


Annotator A:

```json
{
  "anchor_lines": [
    1444,
    1372,
    1373,
    1374
  ],
  "category": "logic",
  "description": "in_quotes uses a quote parity count, so a sensitive word that is the whole quoted argument (cd \"/root\") is skipped, and an apostrophe elsewhere in the command flips the result.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D3",
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
  "description": "Caller updated for the new in_quotes signature.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D3",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H20: verdict


Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Adds the timeout configuration variables used by the deadline fix.",
  "file": "evals/harness/run-ablation.sh",
  "group": "D9",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    262
  ],
  "category": "resource",
  "description": "The runner has no deadline configuration for the post-run grade and took-effect steps, so a hung grader or took-effect blocks the trial and batch indefinitely.",
  "file": "evals/harness/run-ablation.sh",
  "group": "D7",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H21: verdict


Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Validates the timeout variables and builds the timeout wrappers for the deadline fix.",
  "file": "evals/harness/run-ablation.sh",
  "group": "D9",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    341
  ],
  "category": "resource",
  "description": "No timeout wrapper is set up for grade and took-effect, leaving post-run steps unbounded.",
  "file": "evals/harness/run-ablation.sh",
  "group": "D7",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H25: anchors


Annotator A:

```json
{
  "anchor_lines": [
    976,
    978,
    980
  ],
  "category": "resource",
  "description": "took-effect.sh runs with no deadline, so a hang stalls the batch indefinitely, and any non-zero exit pauses the arm.",
  "file": "evals/harness/run-ablation.sh",
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
    976,
    978
  ],
  "category": "resource",
  "description": "took-effect runs without a deadline, so a hang stalls the trial (and a failure would pause the arm though a hang is no evidence about it).",
  "file": "evals/harness/run-ablation.sh",
  "group": "D7",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H26: anchors


Annotator A:

```json
{
  "anchor_lines": [
    996
  ],
  "category": "resource",
  "description": "The grader runs with no post-run deadline, so a hung grade blocks the trial and the batch forever.",
  "file": "evals/harness/run-ablation.sh",
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
    996,
    997
  ],
  "category": "resource",
  "description": "The grader is invoked without a deadline, so a hung grade blocks the batch from finishing.",
  "file": "evals/harness/run-ablation.sh",
  "group": "D7",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### I01: category

- invalid: an incident-only defect without a category

Annotator A:

```json
{
  "anchor_lines": [
    1401,
    1402
  ],
  "description": "The repo_name scan checks the whole Bash value, heredoc bodies included, so a reviewer quoting the PR's own '0xHoneyJar/loa' text in a heredoc is marked contaminated (KF-046 class 7).",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D10",
  "severity": "medium",
  "verdict": "defect-at-head"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    1401,
    1402
  ],
  "description": "The repo_name check scans the whole Bash value including heredoc prose, so a reviewer quoting the PR's own '0xHoneyJar/loa' text is flagged contaminated (KF-046 class 7).",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D8",
  "severity": "medium",
  "verdict": "defect-at-head"
}
```

## Description differences (informational; the merge takes A's text)

- H04

```json
{
  "A": "With no SIGTERM handler, a grader killed by the runner's deadline skips the finally block, so the SCRATCH directory is left behind.",
  "B": "The grader installs no SIGTERM handler, so a terminated grade skips the finally block and leaves its SCRATCH directory behind (version bump rides along)."
}
```

- H11

```json
{
  "A": "Every word starting with /. is skipped as a dot-directory, so /./root/x and /../root/x evade the outside_path check.",
  "B": "Any word starting with /. is skipped as a repo-relative dot-dir, so /./root/.ssh/id_rsa or /../root/x evades the outside_path check."
}
```
