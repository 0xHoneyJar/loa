# Adjudication list — pr-79

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

1 item(s) disagree.

### I02: verdict


Annotator A:

```json
{
  "anchor_lines": [],
  "description": "logSerializers is missing from RouteShorthandOptions. This is a separate, pre-existing type gap that the change under review did not touch.",
  "file": "types/route.d.ts",
  "group": null,
  "severity": null,
  "verdict": "not-at-head"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    51,
    60
  ],
  "description": "RouteShorthandOptions at head has no logSerializers per-route option, even though the runtime accepts and documents it.",
  "file": "types/route.d.ts",
  "group": "D2",
  "severity": "low",
  "verdict": "defect-at-head"
}
```

## Description differences (informational; the merge takes A's text)

- H01

```json
{
  "A": "RouteShorthandHook rebuilds the hook signature from Parameters<T> only, dropping the hook's `this` type, so shorthand route hooks lose their typed `this` (e.g. FastifyInstance) context.",
  "B": "RouteShorthandHook rebuilds the hook signature from Parameters<T> only, dropping the hook's `this` type, so shorthand route hooks lose their `this` (FastifyInstance) typing."
}
```
