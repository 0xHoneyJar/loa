# Adjudication list — pr-32

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

There are no disagreements: the merge needs an empty adjudication.json (`{}`).

## Description differences (informational; the merge takes A's text)

- H01

```json
{
  "A": "The GC traverse implementation for GeneralFieldsSerializer omits extra_serializer, so Python objects held by the extra-fields serializer are not visited by the cycle collector, allowing uncollectable reference cycles (memory leak).",
  "B": "The GC traverse implementation for GeneralFieldsSerializer omits the extra_serializer field, so Python objects reachable through it are not visited by the cycle collector and reference cycles through it can leak."
}
```
