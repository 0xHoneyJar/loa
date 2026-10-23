# Adjudication list — pr-20

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

13 item(s) disagree.

### H02: anchors


Annotator A:

```json
{
  "anchor_lines": [
    190,
    191
  ],
  "category": "security",
  "description": "The executable-target regex omits workflow files, makefiles, justfiles, package manifests, Dockerfiles and CI/pre-commit configs, so a heredoc writing destructive content into them is classified non-executing and its body is not scanned.",
  "file": ".claude/hooks/safety/block-destructive-bash.sh",
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
    190
  ],
  "category": "security",
  "description": "The executable-target regex omits workflow files, makefiles, justfiles, package manifests, Dockerfiles and pre-commit/CI configs, so a heredoc writing destructive content into them is classified non-executing and its body is dropped from the scan.",
  "file": ".claude/hooks/safety/block-destructive-bash.sh",
  "group": "D2",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H05: anchors


Annotator A:

```json
{
  "anchor_lines": [
    1049,
    1054,
    1061,
    1067,
    1068
  ],
  "category": "security",
  "description": "Backtick command substitutions are never normalised, so no rule anchors on them and `echo \"see `git push --force origin main`\"` (or an unquoted heredoc body with backticks) passes the fence while its $( ) twin blocks.",
  "file": ".claude/hooks/safety/block-destructive-bash.sh",
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
    1049,
    1050,
    1051,
    1052,
    1053,
    1067,
    1068
  ],
  "category": "security",
  "description": "Backtick command substitutions (in double quotes, assignments, unquoted heredoc bodies) are never normalised, so no rule anchors on them and e.g. `echo \"see `git push --force origin main`\"` is allowed while its $( ) twin blocks.",
  "file": ".claude/hooks/safety/block-destructive-bash.sh",
  "group": "D4",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H14: anchors


Annotator A:

```json
{
  "anchor_lines": [
    6
  ],
  "category": "contract",
  "description": "allowed-tools lacks `Bash(.claude/scripts/lib/profile-lib.sh knob *)`, so the skill's postlude knob read (deny_raw_shell) is refused.",
  "file": ".claude/skills/auditing-security/SKILL.md",
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
    6,
    34,
    35
  ],
  "category": "contract",
  "description": "The skill's allowed-tools and command allowlist (deny_raw_shell) do not permit `.claude/scripts/lib/profile-lib.sh knob`, which its included retrospective postlude must run, so the postlude check cannot execute.",
  "file": ".claude/skills/auditing-security/SKILL.md",
  "group": "D7",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H16: verdict


Annotator A:

```json
{
  "anchor_lines": [
    6,
    297
  ],
  "category": "contract",
  "description": "allowed-tools lacks the profile-lib.sh knob grant that the retrospective postlude invokes, so that call is denied under deny_raw_shell.",
  "file": ".claude/skills/reviewing-code/SKILL.md",
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
    6,
    297
  ],
  "category": null,
  "description": "Same profile-lib.sh knob grant for the review-sprint skill, whose postlude (line 297) runs that command.",
  "file": ".claude/skills/reviewing-code/SKILL.md",
  "group": "D7",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H20: anchors


Annotator A:

```json
{
  "anchor_lines": [
    312
  ],
  "category": "logic",
  "description": "The example pins a profile-governed key explicitly, so a copied example overrides loa.profile and choosing lean/full has no effect on it.",
  "file": ".loa.config.yaml.example",
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
    312,
    325,
    1358,
    1404,
    1432,
    2932,
    2950,
    2962
  ],
  "category": "logic",
  "description": "The example config sets the profile-governed keys explicitly, so a copied example pins them as explicit overrides and loa.profile (lean/full) has no effect on them.",
  "file": ".loa.config.yaml.example",
  "group": "D8",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H21: verdict


Annotator A:

```json
{
  "anchor_lines": [
    325
  ],
  "category": "logic",
  "description": "decisions.surface_at_session_start is pinned in the example, overriding the profile in a copied config.",
  "file": ".loa.config.yaml.example",
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
    325
  ],
  "category": null,
  "description": "Same correction for decisions.surface_at_session_start.",
  "file": ".loa.config.yaml.example",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H22: verdict


Annotator A:

```json
{
  "anchor_lines": [
    1358
  ],
  "category": "logic",
  "description": "guardrails.input.enabled is pinned in the example, so the full profile cannot turn it on in a copied config.",
  "file": ".loa.config.yaml.example",
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
    1358
  ],
  "category": null,
  "description": "Same correction for guardrails.input.enabled.",
  "file": ".loa.config.yaml.example",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H23: verdict


Annotator A:

```json
{
  "anchor_lines": [
    1404
  ],
  "category": "logic",
  "description": "guardrails.danger_level.enforce is pinned in the example, overriding the profile.",
  "file": ".loa.config.yaml.example",
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
    1404
  ],
  "category": null,
  "description": "Same correction for guardrails.danger_level.enforce.",
  "file": ".loa.config.yaml.example",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H24: verdict


Annotator A:

```json
{
  "anchor_lines": [
    1432
  ],
  "category": "logic",
  "description": "invisible_retrospective.enabled is pinned in the example, overriding the profile.",
  "file": ".loa.config.yaml.example",
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
    1432
  ],
  "category": null,
  "description": "Same correction for invisible_retrospective.enabled.",
  "file": ".loa.config.yaml.example",
  "group": "D8",
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
    2932
  ],
  "category": "logic",
  "description": "karpathy_principles.surgical_diff_warning is pinned in the example, overriding the profile.",
  "file": ".loa.config.yaml.example",
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
    2932
  ],
  "category": null,
  "description": "Same correction for karpathy_principles.surgical_diff_warning.",
  "file": ".loa.config.yaml.example",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H26: verdict


Annotator A:

```json
{
  "anchor_lines": [
    2950
  ],
  "category": "logic",
  "description": "karpathy_principles.require_success_criteria is pinned in the example, overriding the profile.",
  "file": ".loa.config.yaml.example",
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
    2950
  ],
  "category": null,
  "description": "Same correction for karpathy_principles.require_success_criteria.",
  "file": ".loa.config.yaml.example",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H27: verdict


Annotator A:

```json
{
  "anchor_lines": [
    2962
  ],
  "category": "logic",
  "description": "structured_handoff.enabled is pinned in the example, overriding the profile.",
  "file": ".loa.config.yaml.example",
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
    2962
  ],
  "category": null,
  "description": "Same correction for structured_handoff.enabled.",
  "file": ".loa.config.yaml.example",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H56: anchors


Annotator A:

```json
{
  "anchor_lines": [
    40,
    41,
    43,
    45
  ],
  "category": "error-handling",
  "description": "The knob-reader lint escapes only dots, misses reads split across a yq pipe or bracket form, and swallows grep errors (2>/dev/null, || true) so a bad pattern or missing tools/ dir reads as a clean pass.",
  "file": "tools/check-knob-readers.sh",
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
    40,
    41,
    43,
    44,
    45
  ],
  "category": "error-handling",
  "description": "The lint swallows grep errors (`2>/dev/null` and `|| true`) so a grep failure reads as a clean pass, escapes only dots in keys, and misses reads split across a pipe or a bracket form of the key.",
  "file": "tools/check-knob-readers.sh",
  "group": "D9",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

## Description differences (informational; the merge takes A's text)

- H03

```json
{
  "A": "The segment command-word extractor does not skip shell reserved words (if/then/do/while...), so a body line like `if :; then rm -rf src; fi` yields `then` as the command word and the rm segment is dropped.",
  "B": "The per-segment command-word extraction does not skip shell reserved words (if, then, do, while, ...), so a body line like `if :; then rm -rf src; fi` loses its rm segment and is allowed."
}
```

- H06

```json
{
  "A": "The scrub pipeline has no backtick-normalisation step before the rules run, letting backtick substitutions bypass every pattern.",
  "B": "The scrub chain applies no backtick-to-$( ) normalisation before the rules run, leaving backtick substitutions unmatched."
}
```

- H07

```json
{
  "A": "No rule refuses `gh api` with DELETE/PUT/PATCH (or GraphQL mutations) against refs, branch protection, tags, releases or the repository, so the REST escape hatch bypasses the force-push, branch-delete and spike fences.",
  "B": "No rule refuses `gh api` with DELETE/PUT/PATCH (or GraphQL delete/update mutations) on refs, branch protection, tags, releases or the repository, so the REST escape hatch bypasses the P2/P5/SP-1 porcelain fences."
}
```

- H12

```json
{
  "A": "LOA_PROFILE_CONFIG_FILE silently redirects knob reads outside bats with no visible warning, so a stray environment variable changes guard configuration unnoticed.",
  "B": "LOA_PROFILE_CONFIG_FILE is honoured outside bats with no notice, so knob reads can be silently redirected to another config file in live use."
}
```

- H13

```json
{
  "A": "The /loa Profile line does not report when input guardrails or danger-level enforcement resolve to off, hiding the now-default-off guardrail state from the operator.",
  "B": "The /loa Profile line does not report when input guardrails or danger-level enforcement resolve to off, hiding the default-off guardrail state the DEC-0161 change introduced (intent read from the audit comment; borderline feature)."
}
```
