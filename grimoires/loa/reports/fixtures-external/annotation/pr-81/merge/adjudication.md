# Adjudication list — pr-81

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

There are no disagreements: the merge needs an empty adjudication.json (`{}`).

## Description differences (informational; the merge takes A's text)

- H02

```json
{
  "A": "The negation applies only to `type -p`, so the condition needs parallel to be both missing and runnable and is never true; --jobs without GNU parallel never aborts here and fails later instead.",
  "B": "Because `!` negates only the `type -p` check, the abort runs only when parallel is missing and `parallel --version` also succeeds, which can never both happen, so --jobs without GNU parallel never aborts here and fails later instead."
}
```
