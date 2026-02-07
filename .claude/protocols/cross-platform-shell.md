# Cross-Platform Shell Scripting Protocol

**Version**: 1.0.0
**Issue**: https://github.com/0xHoneyJar/loa/issues/195
**Origin**: Discovered during Flatline Protocol execution on macOS (#194)

## Overview

Loa scripts must work identically on Linux (GNU), macOS (BSD), and Windows WSL. Platform-specific commands cause silent failures that are notoriously difficult to debug — macOS `date +%N` outputs literal "N" instead of failing, `sed -i` creates garbage backup files, and `readlink -f` simply doesn't exist.

This protocol defines required patterns for cross-platform compatibility.

## Decision: Library-First, Not Inline

**Use `compat-lib.sh` functions instead of inline platform checks.**

This is the same principle Kubernetes applies in `hack/lib/util.sh` and Google's Bazel applies in its shell utility layer: fix once in a library, test once, benefit everywhere. Inline platform checks are error-prone because each developer re-implements the detection logic slightly differently.

```bash
# Source the library (usually via bootstrap.sh)
source "${SCRIPT_DIR}/compat-lib.sh"  # or source via bootstrap chain

# Then use portable functions throughout your script
```

## Required Patterns

### Bash 4.0+ Version Guard

**Library**: `bash-version-guard.sh` (since Issue #240)

```bash
# WRONG — crashes with cryptic "unbound variable" on macOS bash 3.2
declare -A MY_MAP=( ["key"]="value" )

# RIGHT — source the guard before any declare -A
source "$SCRIPT_DIR/bash-version-guard.sh"
declare -A MY_MAP=( ["key"]="value" )
```

**Why it's subtle**: macOS ships with bash 3.2. `declare -A` (associative arrays) requires bash 4.0+. On bash 3.2, the script crashes with `unbound variable` instead of a clear version error. The guard detects this and prints upgrade instructions.

The guard uses source-time detection (no function call needed) and has a double-source guard. This is the same fail-fast pattern used by `compat-lib.sh`.

### Timestamps

**Library**: `time-lib.sh` (since PR #199)

```bash
# WRONG — macOS outputs literal "N", doesn't error
start_time=$(date +%s%3N)

# RIGHT — use time-lib.sh
source "${SCRIPT_DIR}/time-lib.sh"
start_time=$(get_timestamp_ms)
```

**Why it's subtle**: macOS `date +%s%3N` outputs `1738742714N` (with a literal N character). The command succeeds (exit 0), so fallback patterns like `$(date +%s%3N 2>/dev/null || date +%s)000` silently produce garbage. The fix tests whether the output is all-numeric, not whether the command succeeded. This is the same class of bug that caused CloudFlare's 2017 leap-second outage — trusting exit codes instead of validating output.

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

**For atomic writes** (when partial writes would corrupt state):
```bash
# RIGHT — temp file + mv (atomic on POSIX filesystems)
sed 's/old/new/' file.txt > file.txt.tmp && mv file.txt.tmp file.txt
```

Google's Shell Style Guide recommends the temp-file-and-mv pattern for production scripts. We provide `sed_inplace()` as a convenience for the common case, but critical state files (like ledger.json) should use the atomic pattern.

### Canonical Paths

**Library**: `compat-lib.sh` → `get_canonical_path()`

```bash
# WRONG — not available on macOS
path=$(readlink -f "$file")

# WRONG — realpath may not exist either
path=$(realpath "$file")

# RIGHT — use compat-lib (3-tier fallback: readlink → realpath → pure bash)
source "${SCRIPT_DIR}/compat-lib.sh"
path=$(get_canonical_path "$file")
```

The pure bash fallback uses the `cd + pwd -P` pattern, which is the same approach Node.js uses in its configure script for portability.

### File Modification Time

**Library**: `compat-lib.sh` → `get_file_mtime()`

```bash
# WRONG — inconsistent inline fallbacks scattered everywhere
mtime=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null)

# RIGHT — cached detection, single branch per call
source "${SCRIPT_DIR}/compat-lib.sh"
mtime=$(get_file_mtime "$file")
```

### Version Sorting

**Library**: `compat-lib.sh` → `version_sort`

```bash
# WRONG — not available on macOS <10.15
echo "$versions" | sort -V

# RIGHT — fallback to numeric component sort
source "${SCRIPT_DIR}/compat-lib.sh"
echo "$versions" | version_sort
```

### Temp Files with Suffix

**Library**: `compat-lib.sh` → `make_temp()`

```bash
# WRONG — GNU-only flag
tmpfile=$(mktemp --suffix=.mmd)

# RIGHT — portable with auto-fallback
source "${SCRIPT_DIR}/compat-lib.sh"
tmpfile=$(make_temp ".mmd")
```

### Find + Sort by Time

**Library**: `compat-lib.sh` → `find_sorted_by_time()`

```bash
# WRONG — -printf not available on macOS
find "$dir" -name "*.log" -type f -printf '%T+ %p\n' | sort

# RIGHT — portable with stat fallback
source "${SCRIPT_DIR}/compat-lib.sh"
find_sorted_by_time "$dir" "*.log"
```

### Regex in grep

```bash
# WRONG — -P (PCRE) not available on macOS
grep -P '\d+' file

# RIGHT — use extended regex (available everywhere)
grep -E '[0-9]+' file
```

No library wrapper needed — just use `-E` instead of `-P`.

## Patterns That Are Already Portable

These are safe to use without library wrappers:

| Command | Notes |
|---------|-------|
| `mktemp -d` | Works on all platforms (without `--suffix`) |
| `grep -E` | Extended regex, universally supported |
| `date +%s` | Epoch seconds, universally supported |
| `basename`, `dirname` | POSIX, universally supported |
| `uname -s` | Universally supported for platform detection |
| `command -v` | POSIX, preferred over `which` |

## Library Architecture

```
.claude/scripts/
├── time-lib.sh        # Timestamps (PR #199)
├── path-lib.sh        # Grimoire path resolution
├── compat-lib.sh      # Cross-platform utilities (this PR)
└── lib/
    ├── api-resilience.sh     # API retry/circuit breaker
    ├── schema-validator.sh   # JSON schema validation
    └── validation-history.sh # Circular prevention
```

Each library:
- **Detects once** at source time (cached in `_COMPAT_*` variables)
- **Dispatches per-call** via cached flags (no fork per call)
- **Guards against double-sourcing** with `_*_LOADED` flags
- **Provides debug output** via `LOA_*_DEBUG=1` environment variables

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

## Adding a New Portable Function

When you encounter a new cross-platform incompatibility:

1. Add the function to `compat-lib.sh` with feature detection
2. Add the pattern to the CI lint script
3. Document it in this protocol
4. Update existing scripts to use the new function

## Testing

Portable functions should be verified on the CI matrix:

```yaml
strategy:
  matrix:
    os: [ubuntu-latest, macos-latest]
```

For local testing, use `LOA_COMPAT_DEBUG=1` to verify detection:

```bash
LOA_COMPAT_DEBUG=1 source .claude/scripts/compat-lib.sh
# [compat-lib] OS: darwin
# [compat-lib] sed: bsd
# [compat-lib] sort -V: true
# [compat-lib] readlink -f: false
# [compat-lib] find -printf: false
# [compat-lib] stat: bsd
```

## Related

- `time-lib.sh` — Cross-platform timestamps (PR #199)
- `path-lib.sh` — Configurable grimoire path resolution
- Issue #194 — Original macOS `date +%N` bug report
- Issue #195 — This protocol proposal
- Google Shell Style Guide — <https://google.github.io/styleguide/shellguide.html>
- Kubernetes hack/lib — <https://github.com/kubernetes/kubernetes/tree/master/hack/lib>
