# Task: environment-variable interpolation for confload

`confload` (the package under `src/confload/`) parses sectioned `key = value` configuration text into `{section: {key: value}}`; its format and its `ConfigError` (which carries the 1-based `line` and renders as `line N: <message>`) are documented in the module docstring. Add interpolation of environment variables into values.

## Interface

- `loads(text, env=None)` and `load(path, env=None)` gain an `env` argument: a mapping of variable names to string values. When `env` is `None`, the process environment (`os.environ`, read at call time) is used.
- A new exception class `InterpolationError`, a subclass of `ConfigError`, importable from `confload` and from the loader module. It carries the line number like any `ConfigError`.

## Rules

Interpolation applies to values only, after the surrounding whitespace is stripped; keys, section headers and comment lines are never interpolated. A value is scanned once from left to right:

- `$$` produces one literal `$`.
- `${NAME}` produces the value of `NAME` in `env`. A variable that is set to the empty string produces the empty string; a variable that is not set is an error.
- `${NAME:-default}` produces the value of `NAME` when it is set and non-empty, otherwise `default`. The default is everything after the first `:-` up to the closing brace, taken verbatim (it may be empty and may contain spaces, `:-`, `=` or `$`; it is not interpolated).
- The reference ends at the first `}` after `${`. `NAME` (the text before `:-`, or the whole text between the braces when there is no `:-`) must match `[A-Za-z_][A-Za-z0-9_]*`.
- A `$` followed by anything other than `$` or `{`, or at the end of the value, stays a literal `$` (`cost $5`, `$HOME`, `a$`).
- Substituted text is never scanned again: if `REF` is set to `${HOST}`, `${REF}` produces the text `${HOST}`. Whitespace inside a substituted value is kept.

## Errors

Each error raises `InterpolationError` for the line holding the value, with exactly this message after the `line N: ` prefix:

| Case | Message |
|------|---------|
| `${NAME}` where `NAME` is not set | `undefined variable: NAME` |
| `${` with no closing `}` in the value | `unterminated variable reference` |
| a name that does not match the pattern (including an empty one, as in `${}` or `${:-x}`) | `invalid variable name: <the name text as written>` |

For example `host = ${DB_HOST}` on line 3 with `DB_HOST` unset raises `InterpolationError` whose string is `line 3: undefined variable: DB_HOST`; `${A B}` gives `invalid variable name: A B`, and `${}` gives `line N: invalid variable name: ` (the colon and space, then nothing).

Update the module docstring. Run the suite with `python3 -m pytest -q tests`, and add tests of your own for the new behaviour.
