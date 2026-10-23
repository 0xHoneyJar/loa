# Adjudication list — pr-27

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

6 item(s) disagree.

### H07: anchors


Annotator A:

```json
{
  "anchor_lines": [
    329,
    330,
    331,
    332,
    333,
    337
  ],
  "category": "resource",
  "description": "scope_map has no bound on the number of headers, so a large file with many unterminated headers triggers a quadratic span scan (resource exhaustion on agent-influenced input).",
  "file": "evals/graders/recall-vs-defects.sh",
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
    329,
    331,
    333,
    337
  ],
  "category": "resource",
  "description": "scope_map scans headers quadratically with no bound, so a huge file with many unterminated headers can stall the grader.",
  "file": "evals/graders/recall-vs-defects.sh",
  "group": "D5",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H09: anchors


Annotator A:

```json
{
  "anchor_lines": [
    1629,
    1630,
    1631,
    1632,
    1633,
    1634,
    1635
  ],
  "category": "security",
  "description": "grade_recall drops EVAL_HEAD_DIR when no PR fixture head exists, letting recall-vs-defects.sh fall back to the sandbox's agent-writable pr/head copy.",
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
    1629,
    1630,
    1631,
    1632,
    1633
  ],
  "category": "security",
  "description": "When no PR fixture head exists, popping EVAL_HEAD_DIR lets recall-vs-defects.sh fall back to the copied sandbox pr/head in the grading dir, the agent-controlled copy.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D1",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H13: anchors


Annotator A:

```json
{
  "anchor_lines": [
    1993,
    1994,
    1995
  ],
  "category": "security",
  "description": "A bare repo-name token standing as a whole line becomes its own unit, which is a substring of every fixture token line, so it is always exempt even when used as a command argument.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D7",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    1986,
    1993,
    1994,
    1995
  ],
  "category": "security",
  "description": "A bare repo-name token forming a whole line (for-list word, continuation line) is a substring of any fixture token line and is wrongly exempted.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D7",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H17: group

- group members besides H17: A ['H24'], B -

Annotator A:

```json
{
  "anchor_lines": [
    2065
  ],
  "category": "logic",
  "description": "SILENT_SINK only recognises a counting/quiet grep flag as the first argument and misses egrep/fgrep/-L, so `diff … | grep -i -c x` is treated as printing diff content and falsely marks defects exposed.",
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
    2065
  ],
  "category": "logic",
  "description": "SILENT_SINK only recognises a counting/quiet grep flag as the first argument (and misses egrep/-L etc.), so `| grep -i -c` is read as printing diff content and falsely marks defects exposed.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D9",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H20: anchors


Annotator A:

```json
{
  "anchor_lines": [
    2243,
    2244,
    2245,
    2246,
    2247
  ],
  "category": "resource",
  "description": "segment_tokens runs PATHISH and expansion over arbitrarily large agent-authored segments and words without any size bound.",
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
    2241,
    2243,
    2244
  ],
  "category": "resource",
  "description": "segment_tokens runs the PATHISH regex and expansion over arbitrarily large agent-authored segments and words with no bound.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D12",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H24: anchors, group

- group members besides H24: A ['H17'], B -

Annotator A:

```json
{
  "anchor_lines": [
    2477,
    2481,
    2482,
    2483
  ],
  "category": "logic",
  "description": "The diff-form check misses silent sinks with flags after the first argument and treats stat-only `git diff --stat/--name-only` as printing content, producing false oracle exposures.",
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
    2477,
    2478,
    2482,
    2483
  ],
  "category": "logic",
  "description": "A stat-only git diff (--stat, --name-only, …) is treated as printing diff content and can mark defects exposed; the hunk also switches to the new silent_sink helper.",
  "file": "evals/harness/ablation-grade.sh",
  "group": "D11",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

## Description differences (informational; the merge takes A's text)

- H02

```json
{
  "A": "When EVAL_HEAD_DIR and the fixture head are absent, the grader silently falls back to <workspace>/pr/head, which is the graded agent's own writable tree, letting the graded agent influence same-function crediting.",
  "B": "The grader falls back by default to <workspace>/pr/head, the graded agent's own writable tree, so the agent can shape the head files used for same-function credit."
}
```

- H03

```json
{
  "A": "Markdown header detection treats `#` lines inside fenced code blocks as headings, splitting a section's scope at code comments.",
  "B": "Markdown header detection treats `#` lines inside fenced code blocks as headings, splitting a section's scope wrongly."
}
```

- H04

```json
{
  "A": "Bash closing-brace detection measures indentation without expanding tabs while headers() measures tab-expanded width, so tab-indented functions never match their closing brace and their scope runs too far.",
  "B": "Bash close-brace detection compares raw indentation against a tab-expanded header level, so tab-indented functions never close at their own brace and swallow later lines into scope."
}
```

- H05

```json
{
  "A": "Python end-of-definition detection starts right after the def line, so a multi-line signature's dedented closing `):` line ends the definition before its body.",
  "B": "Python end-of-definition detection ends a def with a multi-line signature at its first parameter line, dropping the body from the scope."
}
```

- H12

```json
{
  "A": "repo_name_exempt exempts a Bash command that actually reaches the upstream repository (curl/git/gh with 0xHoneyJar/loa) whenever the same line appears in the PR fixture, and ignores backslash-continued lines, hiding real contamination.",
  "B": "repo_name_exempt exempts an executed Bash command that fetches from the upstream repo (curl/git) whenever the same line appears in the PR fixture, hiding a real contamination probe."
}
```

- H14

```json
{
  "A": "corpus_sha256 validates the file with read_regular and then reopens it with plain open(), following symlinks and unbounded, so it can hash a different (swapped or oversized) file than the one checked.",
  "B": "corpus_sha256 checks the file with read_regular and then reopens it with a following open and unbounded read, a check-then-use race that can follow a swapped symlink or hash an oversized file."
}
```

- H18

```json
{
  "A": "The segment splitter treats `&` in redirections like 2>&1, >&2, &> and `|&` as a command separator, breaking the pipe association so `diff … 2>&1 | wc -l` is read as an unpiped content diff.",
  "B": "The segment splitter treats the `&` of redirections like 2>&1 or &>/dev/null (and `|&`) as a command separator, so the following pipe sink is not attached to the diff and silent diffs read as exposing."
}
```

- H19

```json
{
  "A": "expand() has no cap on the cartesian product of for-list variable substitutions, so agent-authored commands can blow up grading time/memory.",
  "B": "Variable expansion builds an unbounded for-list product from agent-authored input, allowing exponential blow-up in the grader."
}
```

- H21

```json
{
  "A": "The oracle scan runs difflib SequenceMatcher on arbitrarily long head and sandbox copies, an unbounded (quadratic) cost on agent-controlled file size.",
  "B": "difflib runs over arbitrarily long head and sandbox copies with no line cap, letting a huge sandbox file stall the grader."
}
```

- H22

```json
{
  "A": "Tool result text is processed with no bound on line count or line length.",
  "B": "Tool result text is processed unbounded in line count and line length."
}
```

- H23

```json
{
  "A": "for-list word lists are stored unbounded, feeding the expansion blow-up.",
  "B": "A for-list variable keeps every expanded word with no cap, feeding the unbounded expansion product."
}
```

- I02

```json
{
  "A": "The 1.3.0 oracle detector skips every tool_result flagged is_error, but a differing diff exits 1 and is error-marked, so real diff exposures can go undetected (fixed in grader 1.3.1).",
  "B": "The oracle detector skips every is_error tool result, but a differing diff exits 1 and is error-marked, so real head-vs-later diffs go undetected (fixed in grader 1.3.1)."
}
```
