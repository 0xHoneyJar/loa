# Adjudication list — pr-19

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

7 item(s) disagree.

### H02: anchors


Annotator A:

```json
{
  "anchor_lines": [
    329,
    330,
    331,
    332,
    333,
    334,
    335
  ],
  "category": "security",
  "description": "The check only verifies that a floor gate's script exists on disk, not that settings.json registers it, so an unregistered floor gate hook (never runs) leaves --check green.",
  "file": ".claude/scripts/guard-yield.sh",
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
    329,
    330,
    331,
    332,
    333,
    334
  ],
  "category": "security",
  "description": "The check only verifies that a floor gate script exists on disk, not that settings.json registers it, so an unregistered floor gate leaves --check green while the gate never runs.",
  "file": ".claude/scripts/guard-yield.sh",
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
    390,
    391,
    392,
    393,
    394,
    395,
    396,
    397,
    398
  ],
  "category": "logic",
  "description": "render_hooks_ref only counts the markers and does not check that the end marker follows the begin marker, so a misplaced end marker makes the awk pass drop all content after the begin marker from the hooks reference.",
  "file": ".claude/scripts/guard-yield.sh",
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
    390,
    391,
    392,
    393,
    394,
    395,
    396,
    397,
    398
  ],
  "category": "input-validation",
  "description": "render_hooks_ref checks marker counts but not their order, so an end marker placed before the begin marker makes the awk pass drop all content after the begin line from the hooks reference.",
  "file": ".claude/scripts/guard-yield.sh",
  "group": "D3",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H05: severity


Annotator A:

```json
{
  "anchor_lines": [
    163,
    164,
    165,
    166
  ],
  "category": "logic",
  "description": "resolve_toggles applies LOA_EVAL_ARM_TOGGLES even when not in arm mode and for the baseline arm, so a stale inherited variable silently alters a baseline or non-arm run.",
  "file": "evals/harness/execute-agent.sh",
  "group": "D5",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    163,
    164,
    165,
    166
  ],
  "category": "logic",
  "description": "resolve_toggles applies LOA_EVAL_ARM_TOGGLES even when not in arm mode and also for the baseline arm, so a stale environment variable silently changes what a non-arm or baseline run measures.",
  "file": "evals/harness/execute-agent.sh",
  "group": "D5",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H13: category


Annotator A:

```json
{
  "anchor_lines": [
    314,
    315
  ],
  "category": "security",
  "description": "Transport failures are detected by grepping the agent's own output with broad patterns ('network', any '5xx '), so the agent under test can trigger a retry just by mentioning such text.",
  "file": "evals/harness/run-arms.sh",
  "group": "D12",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    314,
    315
  ],
  "category": "logic",
  "description": "Transport-failure classification greps the agent's own output with loose patterns such as 'network', so the agent under test can trigger a retry just by mentioning such text.",
  "file": "evals/harness/run-arms.sh",
  "group": "D12",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H14: severity


Annotator A:

```json
{
  "anchor_lines": [
    336,
    337,
    338
  ],
  "category": "logic",
  "description": "The trial launch passes an inherited LOA_EVAL_ARM_TOGGLES from the parent environment to execute-agent.sh, overriding the suite-declared arm toggles.",
  "file": "evals/harness/run-arms.sh",
  "group": "D5",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    336,
    337,
    338
  ],
  "category": "logic",
  "description": "The trial launch passes an inherited LOA_EVAL_ARM_TOGGLES from the parent environment through to execute-agent.sh, overriding the suite-declared toggles of the arm.",
  "file": "evals/harness/run-arms.sh",
  "group": "D5",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H15: anchors, severity


Annotator A:

```json
{
  "anchor_lines": [
    111,
    112,
    113,
    114
  ],
  "category": "security",
  "description": "The secret redaction patterns miss common credential shapes (PEM private keys, JWTs, GitHub fine-grained/app tokens, Google/Stripe keys, generic api_key/token assignments), and \\s in the password/secret patterns can match across newlines, so secrets can be copied into the corpus unredacted.",
  "file": "evals/harness/seed-corpus-from-record.sh",
  "group": "D13",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    113,
    114,
    115,
    116
  ],
  "category": "security",
  "description": "The secret-redaction patterns miss common credential shapes (PEM keys, JWTs, fine-grained GitHub, Google and Stripe keys, generic tokens), and the \\s in the password/secret patterns can match across lines, so secrets get copied into fixtures unredacted.",
  "file": "evals/harness/seed-corpus-from-record.sh",
  "group": "D13",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H16: anchors, severity


Annotator A:

```json
{
  "anchor_lines": [
    307
  ],
  "category": "security",
  "description": "The scope exclusion does not exclude a root CLAUDE.md, so a fixture can carry an instruction file that Claude Code may load for the agent under test.",
  "file": "evals/harness/seed-corpus-from-record.sh",
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
    309
  ],
  "category": "security",
  "description": "The scope exclusion does not drop a root CLAUDE.md, so a fixture can carry an instruction file that Claude Code may load for the agent under test (the fix calls this defensive).",
  "file": "evals/harness/seed-corpus-from-record.sh",
  "group": "D14",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

## Description differences (informational; the merge takes A's text)

- H01

```json
{
  "A": "Containment of hook scripts is only checked when the leaf itself is a symlink, so a symlinked intermediate directory under .claude/ can point a registered hook at a file outside .claude/ without being refused.",
  "B": "Containment only resolves a symlinked leaf, so a hook path through an intermediate symlinked directory under .claude/ can register a script outside .claude/ without error."
}
```

- H04

```json
{
  "A": "The depth-1 checkout has no origin/main ref, so the floor-snapshot proof that compares against origin/main skips silently in CI.",
  "B": "The depth-1 checkout has no origin/main ref, so the floor-snapshot tests that compare against origin/main skip in CI and the floor proof never runs there."
}
```

- H06

```json
{
  "A": "A failed jq rewrite of constraints.json in the karpathy_block toggle is swallowed by the && chain and the toggle is reported as applied without verifying the Karpathy rows are gone.",
  "B": "When the constraints.json rewrite fails, the karpathy_block toggle passes silently and the result is never checked, so an arm can record the toggle as applied while the Karpathy rows remain."
}
```

- H07

```json
{
  "A": "LOA_EVAL_SOURCE_COMMIT is recorded without checking it is a hex id or matches the prompt tree's HEAD, so trials from different trees can claim the same source_commit and pass the skew check.",
  "B": "LOA_EVAL_SOURCE_COMMIT is recorded without checking that it is a hex id or that it matches the prompt tree's HEAD, so trials from different trees can claim the same source_commit and pass the skew check."
}
```

- H09

```json
{
  "A": "The default model claude-fable-5-1 had a trial refused by a safeguard, and the CLI then fell back to Opus partway through the session, so a default run was not homogeneous in executor model.",
  "B": "The default model claude-fable-5-1 gives non-homogeneous trials, because a safeguard refusal makes the CLI fall back to Opus mid-session, so the arm measurements mix models."
}
```

- H10

```json
{
  "A": "The --batch regex accepts '.' and '..', so the batch directory resolves to the suite directory or the results root instead of a child batch directory.",
  "B": "The --batch regex accepts '.' and '..', so BATCH_DIR resolves to the suite directory or its parent instead of a child batch directory."
}
```

- H11

```json
{
  "A": "verify_corpus only checks the files listed in SHA256SUMS, so a file added to the corpus without being listed reaches the sandbox under an unchanged corpus digest.",
  "B": "verify_corpus only checks files that are listed in SHA256SUMS, so an unlisted file added to the corpus reaches the sandbox under an unchanged corpus digest and is not reported as drift."
}
```

- H12

```json
{
  "A": "The pristine-worktree check ignores git-ignored files, so leftovers from an earlier run (.loa.config.yaml, .run/) get copied into every sandbox under one recorded commit.",
  "B": "The pristine-worktree check ignores git-ignored files, so leftover .loa.config.yaml or .run/ files from earlier runs get copied into every sandbox under one recorded commit."
}
```
