# Adjudication list — pr-84

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

There are no disagreements: the merge needs an empty adjudication.json (`{}`).

## Description differences (informational; the merge takes A's text)

- H01

```json
{
  "A": "member_chain_callee_needs_parens only treats JsCallExpression as a call in the object chain, so a member chain rooted at a dynamic import() call (JsImportCallExpression) used as a callee (e.g. `new (import('x').y)()`) is judged not to need parens, and the printed output changes meaning.",
  "B": "member_chain_callee_needs_parens ignores import() call expressions in the object chain, so a `new` callee like `new (import('x').Foo)()` loses required parentheses and changes semantics."
}
```
