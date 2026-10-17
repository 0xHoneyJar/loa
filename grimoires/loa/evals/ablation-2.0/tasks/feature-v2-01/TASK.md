# Task: user-defined filters for textpipe

`textpipe` (the package under `src/textpipe/`) applies named line filters to text. Its entry point is `textpipe.cli.main(argv, stdin=None, stdout=None, stderr=None)`, which returns the exit status. Today the only filters are the five built-in ones (`lower`, `rev`, `squeeze`, `strip`, `upper`), the optional JSON config file (`--config PATH`) knows one key, `apply`, and `--list` prints the built-in filters. Add user-defined filters that come from the config file and from the command line, with removal, a stated precedence and an exact error contract.

## Definitions

A definition gives a name to a sequence of steps; applying it to a line applies the steps in order. Steps always name built-in filters: a definition cannot use another definition, and a step keeps meaning the built-in filter even when that name has been redefined or removed.

- Config file: a new key `filters`, a JSON object mapping each name to a non-empty list of step names, e.g. `{"filters": {"shout": ["strip", "upper"]}}`.
- Command line: `--define NAME=STEP[,STEP...]`, repeatable, e.g. `--define shout=strip,upper`. The value has exactly one `=`, a name before it and one or more non-empty comma-separated steps after it, with no spaces.

A name is 1–32 characters: a lowercase ASCII letter followed by lowercase ASCII letters, digits, `_` or `-`.

## Removal

- Config file: a new key `disable`, a list of names to remove.
- Command line: `--undefine NAME`, repeatable.

A removal deletes the name from the registry entirely; it does not bring back a lower-precedence filter of the same name.

## Precedence

The registry is built from three sources in this order: the built-in filters, then the config file, then the command line. Within the config file and within the command line, definitions are applied first and removals second. A definition of a name that an earlier source already provides replaces it (a config definition may replace a built-in filter, a command-line definition may replace either). A removal may name anything in the registry as it stands at that point, including a definition from the same source.

After the registry is complete, every name to apply is looked up in it: the names given to `--apply`, or, without `--apply`, the config file's `apply` list. The config file's `apply` list is checked against the complete registry even when `--apply` is given.

## Listing

`--list` prints one line per filter in the complete registry, sorted by name, and nothing else. Each line is the name left-justified in a column as wide as the longest listed name, two spaces, and a description. A built-in filter keeps its existing description. A user-defined filter's description is its steps joined by ` | ` followed by a space and its source in brackets, `[config]` or `[command line]`; for example `shout  strip | upper [config]` when `shout` is the longest name.

## Errors

Errors are usage errors, as today: exit status 2, nothing on standard output, and exactly one line on standard error, `textpipe: <message>`. Every error about a value written in the config file (its `filters`, `disable` or `apply`) has a message starting `config: `; errors about command-line values do not. With `<name>`, `<step>` and `<value>` as written:

| Problem | Message from the command line | Message from the config file |
|---|---|---|
| a name that is not valid | `invalid filter name: <name>` | `config: invalid filter name: <name>` |
| a `--define` value that does not have the shape above | `invalid --define value: <value>` | — |
| a config definition that is not a non-empty list of strings | — | `config: invalid definition of <name>: steps must be a non-empty list of names` |
| a step that is not a built-in filter | `unknown step <step> in <name>` | `config: unknown step <step> in <name>` |
| the same name defined twice in one source (twice in `--define`, or twice as a key of the config `filters` object) | `duplicate definition of <name> on the command line` | `config: duplicate definition of <name>` |
| a removed or applied name not in the registry | `unknown filter: <name>` | `config: unknown filter: <name>` |
| `disable` that is not a list of strings | — | `config: disable must be a list of filter names` |

Update the usage text in the module docstring of `textpipe.cli`. Run the suite with `python3 -m pytest -q tests`, and add tests of your own for the new behaviour.
