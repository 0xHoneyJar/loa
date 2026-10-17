# Task: deny rules, wildcards, overrides and precedence for permit

`permit` (under `src/permit/`) decides whether a user may perform an action on a resource path. Users and their groups come from a users file (`permit.principals.parse_directory`). Rules come from a policy file (`permit.rules.parse_rules(text, source)`, one rule per line, blank lines and `#` comments skipped). `permit.engine.Evaluator(directory, policy).check(user, action, path)` answers `True` or `False`. Today a rule can only be `allow PRINCIPAL ACTION PATH`, matching that one exact path. Extend it as follows.

## Rules

A rule is four whitespace-separated fields: `EFFECT PRINCIPAL ACTION PATTERN`.

- `EFFECT` is `allow` or `deny`.
- `PRINCIPAL` is a user name, `@group` or `*` (anyone). A name is one or more of `A-Z a-z 0-9 _ . -`.
- `ACTION` is a name or `*` (any action).
- `PATTERN` is an absolute path pattern. Repeated and trailing slashes are dropped, exactly as for a request path. Each segment is a literal name, `*` (exactly one segment) or `**` (zero or more segments, allowed only as the last segment). So `/docs/**` matches `/docs` itself and everything below it, `/docs/*` matches `/docs/a` but neither `/docs` nor `/docs/a/b`, and `/**` matches every path.

A malformed rule raises `permit.errors.RuleError` with the message `<source>:<line>: <reason>`. The checks run in this order, and the first failure gives the reason:

1. `expected 4 fields, got <n>`
2. `unknown effect <repr>`
3. `bad principal <repr>` when the principal is none of a name, `@` followed by a name, or `*` (so `@`, `@*` and `a*` are bad)
4. `bad action <repr>` when the action is neither a name nor `*`
5. `pattern must start with /: <repr>`
6. `bad pattern: <repr>` when a segment is `.` or `..`
7. `wildcard must be a whole segment: <repr>` when a segment contains `*` but is neither `*` nor `**`
8. `'**' must be the last segment: <repr>`

Here `<repr>` is the `repr` of the field as written.

## Two sources

`Evaluator(directory, policy, overrides=())` takes the policy rules and, optionally, override rules. Override rules have the same syntax and are parsed with `parse_rules(text, "overrides")` (the policy uses `"policy"`).

## Deciding

For a request `(user, action, path)`, normalise the path first; a bad path still raises `PathError`. A rule matches when its principal matches (the user's own name, `@g` for one of the user's groups, or `*`), its action is the requested one or `*`, and its pattern matches the path. A user missing from the users file has no groups. Then:

1. If any override rule matches, only the matching override rules count. Otherwise the matching policy rules count. Overrides therefore beat the policy whatever their specificity.
2. Of those, only the rules with the most specific pattern count. Specificity compares three things in order. First, more literal segments is more specific. Next, a pattern without `**` beats one with it. Last, fewer `*` segments beats more (a `**` segment is not a `*` segment). Patterns equal on all three are equally specific. The principal and the action never affect specificity.
3. Of those, if any is a `deny` the answer is deny; otherwise it is allow. An explicit deny beats an allow of the same specificity.
4. When no rule matches at all, the answer is deny.

The deciding rule is the first rule, in file order, among the rules left after step 2 whose effect is the answer.

## Explain

`Evaluator.explain(user, action, path)` returns a decision with `allowed` (a bool) and `rule` (the deciding `Rule`, or `None` when nothing matched). Its `str()` is `<allow|deny> by <source>:<line>: <effect> <principal> <action> <pattern>`, with the four fields as written in the file, for example `deny by policy:4: deny @interns * /docs/**`. When nothing matched it is `deny by default`. `check` returns `explain(...).allowed`.

## Command line

`permit check --policy FILE --users FILE [--overrides FILE] [--explain] USER ACTION PATH`. `--overrides` adds override rules. With `--explain` the single output line is the explain text instead of `allow` / `deny`. Errors keep today's form: exit status 2 and `permit: <message>` on standard error.

The existing suite must stay green. Run it with `python3 -m pytest -q tests`, and add tests of your own for the new rules.
