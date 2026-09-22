# Cross-Platform Shell Scripting Protocol

**Version**: 1.0.0

## Overview

Loa scripts must work identically on Linux (GNU), macOS (BSD), and Windows WSL. Platform-specific commands cause silent failures that are notoriously difficult to debug — macOS `date +%N` outputs literal "N" instead of failing, `sed -i` creates garbage backup files, and `readlink -f` simply doesn't exist.

This protocol defines required patterns for cross-platform compatibility.

## Decision: Library-First, Not Inline

**Use `compat-lib.sh` functions instead of inline platform checks.** Fix detection once in a library, test once, benefit everywhere — inline platform checks are error-prone because each developer re-implements the detection logic slightly differently.

```bash
source "${SCRIPT_DIR}/compat-lib.sh"  # or via bootstrap chain
```

## Required Patterns

### Bash 4.0+ Version Guard

**Library**: `bash-version-guard.sh`

```bash
# WRONG — crashes with cryptic "unbound variable" on macOS bash 3.2
declare -A MY_MAP=( ["key"]="value" )

# RIGHT — source the guard before any declare -A
source "$SCRIPT_DIR/bash-version-guard.sh"
declare -A MY_MAP=( ["key"]="value" )
```

**Why it's subtle**: macOS ships with bash 3.2. `declare -A` (associative arrays) requires bash 4.0+. On bash 3.2, the script crashes with `unbound variable` instead of a clear version error. The guard detects this at source time and prints upgrade instructions.

### Timestamps

**Library**: `time-lib.sh`

```bash
# WRONG — macOS outputs literal "N", doesn't error
start_time=$(date +%s%3N)

# RIGHT — use time-lib.sh
source "${SCRIPT_DIR}/time-lib.sh"
start_time=$(get_timestamp_ms)
```

**Why it's subtle**: macOS `date +%s%3N` outputs `1738742714N` (with a literal N character). The command succeeds (exit 0), so fallback patterns like `$(date +%s%3N 2>/dev/null || date +%s)000` silently produce garbage. The fix tests whether the output is all-numeric, not whether the command succeeded.

### In-place sed

**Library**: `compat-lib.sh` → `sed_inplace()`

```bash
# WRONG — GNU only (creates empty-extension backup on macOS)
sed -i 's/old/new/' file.txt

# WRONG — macOS only (fails on Linux)
sed -i '' 's/old/new/' file.txt

# RIGHT — use compat-lib
source "${SCRIPT_DIR}/compat-lib.sh"
sed_inplace 's/old/new/' file.txt
```

**For atomic writes** (when partial writes would corrupt state, e.g. `ledger.json`), use temp file + mv instead of `sed_inplace()`:

```bash
sed 's/old/new/' file.txt > file.txt.tmp && mv file.txt.tmp file.txt
```

### Timeout Execution

**Library**: `compat-lib.sh` → `run_with_timeout()`

```bash
# WRONG — macOS doesn't ship GNU timeout
timeout 30 grep -rn "pattern" ./src

# RIGHT — 4-tier fallback: timeout → gtimeout → perl → warn
source "${SCRIPT_DIR}/compat-lib.sh"
run_with_timeout 30 grep -rn "pattern" ./src
```

**Why it's subtle**: macOS doesn't include GNU coreutils `timeout` (Homebrew provides `gtimeout`, but not every environment has Homebrew). `run_with_timeout()` falls back through GNU `timeout` → `gtimeout` → perl's `alarm()` → warn and run without timeout, detected at call time. Exit code 124 indicates a timeout, matching the GNU convention; the perl fallback uses fork+waitpid rather than bare exec to preserve the `$SIG{ALRM}` handler, since bare exec would produce exit 137 (SIGKILL) instead of 124.

### Curl Auth Config Files (SHELL-002)

**Library**: `lib-security.sh` → `write_curl_auth_config()`

```bash
# WRONG — API key visible in process listings (ps aux)
curl -H "Authorization: Bearer ${API_KEY}" https://api.example.com

# WRONG — header value can contain injection characters
printf 'header = "Authorization: Bearer %s"\n' "$API_KEY" > /tmp/curl.cfg

# RIGHT — validated, 0600 permissions, injection-safe
source "${SCRIPT_DIR}/lib-security.sh"
cfg=$(write_curl_auth_config "Authorization" "Bearer ${API_KEY}")
curl --config "$cfg" https://api.example.com
rm -f "$cfg"
```

**Why it's subtle**: passing API keys via `-H` exposes them in process listings (`ps aux`). `write_curl_auth_config()` writes a `chmod 600` temp file and rejects header values containing CR, LF, null bytes, or backslashes (header-injection defense), escaping embedded double quotes automatically.

**Reference**: SHELL-002 security control; tests in `tests/unit/curl-config-guard.bats`.

### Other `compat-lib.sh` Wrappers

Source `compat-lib.sh`, then replace each non-portable command:

| Non-portable | Fix |
|---|---|
| `readlink -f` / `realpath` (absent on macOS) | `get_canonical_path "$file"` (3-tier: readlink → realpath → pure bash) |
| `stat -c %Y` / `stat -f %m` | `get_file_mtime "$file"` |
| `sort -V` (absent on macOS <10.15) | pipe through `version_sort` |
| `mktemp --suffix=X` (GNU-only) | `make_temp X` |
| `find ... -printf` (GNU-only) | `find_sorted_by_time "$dir" "$pattern"` |
| `grep -P` (absent on macOS) | no wrapper needed — use `grep -E` instead |

## Patterns That Are Already Portable

These are safe to use without library wrappers:

| Command | Notes |
|---------|-------|
| `mktemp -d` | Works on all platforms (without `--suffix`) |
| `date +%s` | Epoch seconds, universally supported |
| `basename`, `dirname` | POSIX, universally supported |
| `uname -s` | Universally supported for platform detection |
| `command -v` | POSIX, preferred over `which` |

## Library Architecture

```
.claude/scripts/
├── time-lib.sh        # Timestamps
├── path-lib.sh        # Grimoire path resolution
├── compat-lib.sh      # Cross-platform utilities
└── lib/
    ├── api-resilience.sh     # API retry/circuit breaker
    ├── schema-validator.sh   # JSON schema validation
    └── validation-history.sh # Circular prevention
```

## CI Enforcement

The `shell-compat-lint.yml` workflow catches platform-specific patterns at PR time:

| Pattern | Severity | Rationale |
|---------|----------|-----------|
| `declare -A` (without bash-version-guard) | error | Crashes macOS bash 3.2 |
| `sed -i ` (without compat-lib) | error | Breaks macOS |
| `readlink -f` (without compat-lib) | error | Breaks macOS |
| `grep -P` | error | Breaks macOS |
| `find .* -printf` | warning | Breaks macOS |
| `mktemp --suffix` | warning | Breaks macOS |
| `sort -V` (without compat-lib) | warning | Breaks older macOS |
| `date +%.*N` | warning | Handled by time-lib.sh |
| `timeout [0-9]` (bare) | error | Not available on macOS; use `run_with_timeout()` |
| `Authorization.*Bearer` (raw) | error | Exposes keys in process list; use `write_curl_auth_config()` |

## Adding a New Portable Function

New incompatibility: add the function to `compat-lib.sh` with feature detection, add the pattern to the CI lint script, document it here, and update existing scripts to use it.

## Testing

Portable functions are verified on CI's `ubuntu-latest` / `macos-latest` matrix. For local testing, use `LOA_COMPAT_DEBUG=1` to verify detection:

```bash
LOA_COMPAT_DEBUG=1 source .claude/scripts/compat-lib.sh
# [compat-lib] OS: darwin
# [compat-lib] sed: bsd
# [compat-lib] sort -V: true
# [compat-lib] readlink -f: false
# [compat-lib] find -printf: false
# [compat-lib] stat: bsd
```

## Provenance

Removed from rule text: origin issue #194 (macOS `date +%N`), tracking issue #195, `bash-version-guard.sh` from issue #240, `time-lib.sh` from PR #199.
