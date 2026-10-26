# Adjudication list — pr-78

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

There are no disagreements: the merge needs an empty adjudication.json (`{}`).

## Description differences (informational; the merge takes A's text)

- H01

```json
{
  "A": "When set-cookie is first set with an array, head stores the caller's array by reference, so later set-cookie calls push into (mutate) the caller's array, making a shared/module-level array grow and leak cookies across requests.",
  "B": "reply.header('set-cookie', array) stores the caller's array by reference, so later set-cookie calls push into it and mutate the caller's (often module-level) array, making cookies accumulate and leak across requests."
}
```
