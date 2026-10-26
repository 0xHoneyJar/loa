# Adjudication list — pr-73

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

2 item(s) disagree.

### H01: anchors


Annotator A:

```json
{
  "anchor_lines": [
    407,
    408,
    409
  ],
  "category": "error-handling",
  "description": "When build.chunkImportMap is enabled but getImportMap returns undefined (no import map asset in the bundle), the non-null assertion lets head dereference importMap.mapping and crash instead of skipping import-map handling.",
  "file": "packages/vite/src/node/plugins/importAnalysisBuild.ts",
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
    407,
    408
  ],
  "category": "error-handling",
  "description": "When build.chunkImportMap is enabled the head code non-null-asserts getImportMap's result, so a bundle with no import map asset gives undefined and the importMap.mapping access crashes instead of the block being skipped.",
  "file": "packages/vite/src/node/plugins/importAnalysisBuild.ts",
  "group": "D1",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### I02: anchors


Annotator A:

```json
{
  "anchor_lines": [
    405,
    406,
    407,
    408,
    409,
    410,
    411,
    412
  ],
  "description": "With chunk import maps, the preload dependencies a chunk resolves through the import map are not included in that chunk's hash, so preload changes can leave the hash unchanged and serve stale cached chunks; exact head lines are not shown, so the anchors point at the import-map handling region.",
  "file": "packages/vite/src/node/plugins/importAnalysisBuild.ts",
  "group": "D2",
  "severity": "medium",
  "verdict": "defect-at-head"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    407,
    408,
    409
  ],
  "description": "With chunk import maps, the head code leaves preload dependencies and import-map key selection out of chunk hashing, so a chunk's hash can stay the same while its preload keys change, which leaves stale cached chunks.",
  "file": "packages/vite/src/node/plugins/importAnalysisBuild.ts",
  "group": "D2",
  "severity": "medium",
  "verdict": "defect-at-head"
}
```
