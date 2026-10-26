# Adjudication list — pr-75

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

1 item(s) disagree.

### H02: anchors


Annotator A:

```json
{
  "anchor_lines": [
    571,
    572,
    573,
    574
  ],
  "category": "logic",
  "description": "The fallback HTML page has no <meta charset> declaration, so browsers may decode the inlined non-ASCII HMR runtime with a legacy encoding and corrupt the inline module script.",
  "file": "packages/vite/src/node/server/middlewares/indexHtml.ts",
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
    571,
    573,
    574
  ],
  "category": "logic",
  "description": "The generated fallback HTML has no <meta charset>, so browsers may decode it with a legacy encoding and corrupt the inlined non-ASCII HMR runtime script.",
  "file": "packages/vite/src/node/server/middlewares/indexHtml.ts",
  "group": "D1",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```
