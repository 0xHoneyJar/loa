# Task: settings do not survive a save and a load

`kvconf` (under `src/kvconf/`) reads and writes INI-style settings files. A `Config` holds ordered sections of ordered key/value pairs (all strings): `set(section, key, value)`, `add_section(name)`, `get(section, key, default=None)`, `sections()`, `keys(section)` and `items(section)` (pairs in order). Two configs are equal (`==`) when they have the same sections, keys and values in the same order, spelled the same way. `dumps(config)` returns the file text and `loads(text)` parses it; `save(config, path)` and `load(path)` do the same with a file; `merge(base, overlay)` returns a new `Config`. A malformed file raises `ParseError` (a `ConfigError`), whose message starts with `line <n>: `.

The file format: a `[name]` line opens a section; `key = value` lines follow; blank lines and lines starting with `#` or `;` are comments. A bare value runs to the end of the line or to the first whitespace followed by `#` or `;` (an inline comment), with surrounding whitespace removed. A quoted value is written in double quotes, with the escapes `\\`, `\"`, `\n`, `\t` and `\r`, and may be followed by whitespace and an inline comment.

**Bug (observed):**
- A value with a trailing space comes back without it, and a value such as `red # blue` comes back as `red`.
- The path `C:\new\temp` comes back with a newline and a tab in it. A quoted value with an escape that is not one of the five, such as `"a\q"`, loads as `a\q` instead of being refused.
- Key spelling is lost: `DisplayName = Al` loads back with the key `displayname`, and afterwards `set("user", "DisplayName", "Bo")` adds a second key instead of replacing the first.
- `merge` of a config with `[User]` / `Name = a` and one with `[user]` / `name = b` keeps both sections, and saving the result and loading it back fails with `ParseError`.

**Expected:**
- `loads(dumps(config)) == config` for every config, and `load` after `save` likewise, whatever its values contain (printable characters, spaces, tabs, newlines and carriage returns, quotes, backslashes, `#`, `;`, an empty value), and with the spelling of every section and key kept. A value that needs none of this is still written bare: `name = alice smith`.
- In a quoted value, a backslash followed by anything other than the five escape letters is a `ParseError` with the message `line <n>: bad escape: \<c>` (`<c>` the character after the backslash).
- Section and key names are compared case-insensitively everywhere (after stripping surrounding whitespace): by `get`, `set`, `add_section`, `keys`, `items`, `merge` and the duplicate checks of `loads`. `set` on an existing name replaces the value in place and keeps the existing spelling and position; a new key is appended to its section, and a new section is appended to the config.
- `merge(base, overlay)` leaves both inputs unchanged and returns every section and key of `base` in `base` order and spelling, with the value from `overlay` wherever `overlay` has the same name; the keys only `overlay` has follow in `overlay` order, in their section (sections only `overlay` has come last, in `overlay` order and spelling).
- The existing error messages are unchanged.

Fix the bug in place and add regression tests of your own. Run the suite with `python3 -m pytest -q tests`.
