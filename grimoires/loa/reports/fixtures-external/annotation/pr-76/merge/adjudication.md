# Adjudication list — pr-76

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

1 item(s) disagree.

### H01: category


Annotator A:

```json
{
  "anchor_lines": [
    3976,
    3988
  ],
  "category": "security",
  "description": "byte_length + byte_offset can overflow usize (panic in debug, wraparound in release), bypassing the bounds check so an out-of-range DataView is created over the ArrayBuffer.",
  "file": "ext/napi/js_native_api.rs",
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
    3976,
    3988
  ],
  "category": "input-validation",
  "description": "The bounds check `byte_length + byte_offset > buffer.byte_length()` can overflow usize (wrapping in release builds), so a huge byte_length/byte_offset passes the check and an out-of-bounds DataView is created (or a panic in debug builds).",
  "file": "ext/napi/js_native_api.rs",
  "group": "D1",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```
