# Adjudication list — pr-30

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

4 item(s) disagree.

### H01: group, category

- group members besides H01: A ['H02', 'H03', 'H04'], B -

Annotator A:

```json
{
  "anchor_lines": [
    149,
    150,
    151,
    152,
    153,
    154,
    155,
    156
  ],
  "category": "concurrency",
  "description": "close() does not clear the pending debounce timer, so a rerun can still fire after the optimizer is closed, and pending processing promises are only settled if such a run happens.",
  "file": "packages/vite/src/node/optimizer/optimizer.ts",
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
    149,
    150,
    151,
    152,
    153,
    154,
    155,
    156
  ],
  "category": "resource",
  "description": "close() does not clear the pending debounce timer, so a debounced rerun can still fire after the optimizer has been closed.",
  "file": "packages/vite/src/node/optimizer/optimizer.ts",
  "group": "D1",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H02: anchors, group

- group members besides H02: A ['H01', 'H03', 'H04'], B ['H03', 'H04']

Annotator A:

```json
{
  "anchor_lines": [
    149,
    155,
    156,
    340,
    341
  ],
  "category": "concurrency",
  "description": "close() never resolves depOptimizationProcessing or the enqueued processing promises; it relies on a later runOptimizer call seeing `closed`, so waiters can hang forever when no run follows the close.",
  "file": "packages/vite/src/node/optimizer/optimizer.ts",
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
    149,
    150,
    155,
    156,
    340,
    341
  ],
  "category": "concurrency",
  "description": "close() never resolves depOptimizationProcessing or the enqueued processing promises (only a later rerun does), so callers awaiting optimization can hang forever once the optimizer is closed and no rerun happens.",
  "file": "packages/vite/src/node/optimizer/optimizer.ts",
  "group": "D2",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H03: group

- group members besides H03: A ['H01', 'H02', 'H04'], B ['H02', 'H04']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Removes the promise resolution from the closed branch of runOptimizer because close() now does it.",
  "file": "packages/vite/src/node/optimizer/optimizer.ts",
  "group": "D1",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    340,
    341
  ],
  "category": null,
  "description": "Removes the promise resolution from rerun's closed branch now that close() resolves them.",
  "file": "packages/vite/src/node/optimizer/optimizer.ts",
  "group": "D2",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H04: group

- group members besides H04: A ['H01', 'H02', 'H03'], B ['H02', 'H03']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Removes the duplicate enqueued-promise resolution after a cancelled run because close() now does it.",
  "file": "packages/vite/src/node/optimizer/optimizer.ts",
  "group": "D1",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    363
  ],
  "category": null,
  "description": "Removes the redundant resolveEnqueuedProcessingPromises call in the post-run closed branch since close() now resolves them.",
  "file": "packages/vite/src/node/optimizer/optimizer.ts",
  "group": "D2",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```
