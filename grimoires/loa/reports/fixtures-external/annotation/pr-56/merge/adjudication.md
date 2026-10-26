# Adjudication list — pr-56

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

1 item(s) disagree.

### I01: anchors, category

- invalid: an incident-only defect without a category

Annotator A:

```json
{
  "anchor_lines": [
    1299
  ],
  "description": "The yarn.lock fallback lockfile entry checks '.yarn/patches' even though patches are recorded in the lockfile, causing unnecessary patches-dir dependence in the optimizer hash; the head line number is inferred from the fix commit's offset.",
  "file": "packages/vite/src/node/optimizer/index.ts",
  "group": "D2",
  "severity": "low",
  "verdict": "defect-at-head"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    1297
  ],
  "description": "The yarn.lock fallback lockfile entry checks '.yarn/patches' even though patches are already recorded in the lockfile, which can invalidate the cache when nothing changed.",
  "file": "packages/vite/src/node/optimizer/index.ts",
  "group": "D2",
  "severity": "low",
  "verdict": "defect-at-head"
}
```

## Description differences (informational; the merge takes A's text)

- H01

```json
{
  "A": "The nub.lock entry checks the 'patches' directory even though patch hashes are already in the lockfile, so the optimizer hash depends on the patches dir state needlessly and can trigger spurious re-optimization.",
  "B": "The nub.lock entry checks a 'patches' directory even though patch hashes are already in the lockfile, which makes the optimizer cache hash depend on an unrelated directory and can invalidate the cache when nothing changed."
}
```
