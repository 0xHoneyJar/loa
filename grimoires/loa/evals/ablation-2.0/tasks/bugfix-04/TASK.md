# Task: false and zero settings are ignored

`runopts` (under `src/runopts/`) resolves a tool's options from the command line, the environment (`RUNTOOL_*` variables) and a parsed config file. The module docstring of `runopts.resolve` states the precedence rule.

**Bug (observed):**
- `resolve(["--no-color"], {"RUNTOOL_COLOR": "1"}, {})` gives `color: True`.
- A config file with `color: false` still gives `color: True`, and so does `RUNTOOL_COLOR=off`.
- `--retries 0` with `retries: 5` in the config gives `retries: 5`.
- `--timeout 0` is silently replaced by the default instead of being rejected.

Options set to a non-empty, non-zero, true value already resolve correctly.

**Expected:** for every option, the first layer that gives it a value wins: command line, then environment, then config file, then the built-in default. False, zero and the empty string are values. Only an option a layer does not mention falls through. The existing checks (a negative `retries`, a non-positive `timeout`, unknown config keys, bad environment booleans raise `OptionError`) apply to the value that wins.

Fix the bug in place and add regression tests of your own. Run the suite with `python3 -m pytest -q tests`.
