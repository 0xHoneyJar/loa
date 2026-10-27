# Adjudication list — pr-82

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

1 item(s) disagree.

### H04: anchors


Annotator A:

```json
{
  "anchor_lines": [
    15,
    22,
    23,
    24,
    25,
    26
  ],
  "category": "logic",
  "description": "disablepictureinpicture and disableremoteplayback are missing from the boolean attribute lists, so setting them to false renders/keeps the attribute (e.g. disablepictureinpicture=\"false\") instead of removing it on client and SSR.",
  "file": "packages/shared/src/domAttrConfig.ts",
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
    15,
    22,
    23
  ],
  "category": "logic",
  "description": "specialBooleanAttrs omits disablepictureinpicture and disableremoteplayback, so setting them to false still renders the attribute (client patch and SSR) instead of removing/omitting it.",
  "file": "packages/shared/src/domAttrConfig.ts",
  "group": "D1",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```
