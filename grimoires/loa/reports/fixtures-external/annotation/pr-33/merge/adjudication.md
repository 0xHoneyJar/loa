# Adjudication list — pr-33

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

1 item(s) disagree.

### H01: anchors


Annotator A:

```json
{
  "anchor_lines": [
    148,
    296,
    304,
    305,
    306,
    307,
    308,
    309,
    310
  ],
  "category": "logic",
  "description": "Separator elision uses pattern_is_trailing_recursive, which is true for any suffix ending in `**`, so every `/` in multi-component patterns like `a/b/**` or absolute `{cwd}/**` (used by `ls **`) is dropped, producing wrong matches.",
  "file": "crates/nu-glob/src/dc_glob/compiler.rs",
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
    148,
    296,
    304,
    305
  ],
  "category": "logic",
  "description": "Separator elision uses pattern_is_trailing_recursive, which is true for any suffix ending in `**`, so every `/` in multi-component patterns like `a/b/**` or absolute `{cwd}/**` (used by `ls **`) is dropped, producing wrong matches.",
  "file": "crates/nu-glob/src/dc_glob/compiler.rs",
  "group": "D1",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```
