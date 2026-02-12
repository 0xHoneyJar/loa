# Auto-Format Construct Pack Specification

**Status**: Spec (implementation ships in `loa-constructs` repo)
**Pack ID**: `auto-format`
**Version**: 1.0.0
**Sprint**: sprint-11 (cycle-004)

---

## Overview

A construct pack that installs language-specific auto-formatting hooks into a Loa-managed project. Detects the project's primary language(s) and installs the corresponding formatter configuration.

## Pack Manifest

```yaml
# .claude/constructs/auto-format/manifest.yaml
id: auto-format
name: "Auto-Format Hooks"
version: "1.0.0"
description: "Language-specific auto-formatting for consistent code style"
category: developer-tools
tags: ["formatting", "lint", "hooks"]
danger_level: safe
install_type: additive
files:
  - path: ".claude/hooks/pre-commit-format.sh"
    type: hook
  - path: ".claude/data/formatters.yaml"
    type: config
```

## Supported Languages

| Language | Formatter | Config File |
|----------|-----------|-------------|
| Python | ruff format | `ruff.toml` or `pyproject.toml` |
| JavaScript/TypeScript | prettier | `.prettierrc` |
| Go | gofmt | (built-in) |
| Rust | rustfmt | `rustfmt.toml` |

## Language Detection Strategy

Detect languages by file extension prevalence:

```bash
detect_languages() {
  local lang_counts=()

  # Count files by extension (excluding node_modules, .git, vendor)
  local py_count=$(find . -name "*.py" -not -path "*/node_modules/*" -not -path "*/.git/*" | wc -l)
  local js_count=$(find . \( -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" \) -not -path "*/node_modules/*" -not -path "*/.git/*" | wc -l)
  local go_count=$(find . -name "*.go" -not -path "*/vendor/*" -not -path "*/.git/*" | wc -l)
  local rs_count=$(find . -name "*.rs" -not -path "*/target/*" -not -path "*/.git/*" | wc -l)

  [[ "$py_count" -gt 0 ]] && echo "python"
  [[ "$js_count" -gt 0 ]] && echo "javascript"
  [[ "$go_count" -gt 0 ]] && echo "go"
  [[ "$rs_count" -gt 0 ]] && echo "rust"
}
```

## Installation via `/constructs`

```bash
/constructs install auto-format

# Output:
# Detecting languages...
#   ✓ Python (47 files) → ruff format
#   ✓ TypeScript (23 files) → prettier
#
# Installing formatters:
#   → .claude/hooks/pre-commit-format.sh (hook)
#   → .claude/data/formatters.yaml (config)
#
# ⚠ Non-destructive: existing formatter configs preserved.
#   Existing .prettierrc found — keeping yours.
#   No ruff.toml found — creating default.
```

## Non-Destructive Behavior

The pack MUST NOT overwrite existing formatter configurations:

1. Check if formatter config exists (e.g., `.prettierrc`, `ruff.toml`)
2. If exists: skip config creation, log "keeping existing config"
3. If not exists: create minimal default config
4. Hook script always checks for formatter binary before running

## Hook Script

```bash
#!/usr/bin/env bash
# pre-commit-format.sh — Auto-format staged files
set -euo pipefail

# Load formatter config
FORMATTERS_YAML=".claude/data/formatters.yaml"
if [[ ! -f "$FORMATTERS_YAML" ]]; then
  exit 0  # No config = no formatting
fi

# Format staged files by detected language
staged_files=$(git diff --cached --name-only --diff-filter=ACM)

for file in $staged_files; do
  case "$file" in
    *.py)
      command -v ruff >/dev/null 2>&1 && ruff format "$file" && git add "$file"
      ;;
    *.js|*.ts|*.jsx|*.tsx)
      command -v prettier >/dev/null 2>&1 && prettier --write "$file" && git add "$file"
      ;;
    *.go)
      command -v gofmt >/dev/null 2>&1 && gofmt -w "$file" && git add "$file"
      ;;
    *.rs)
      command -v rustfmt >/dev/null 2>&1 && rustfmt "$file" && git add "$file"
      ;;
  esac
done
```

## Formatters Config

```yaml
# .claude/data/formatters.yaml
formatters:
  python:
    command: "ruff format"
    extensions: [".py"]
    config: "ruff.toml"
  javascript:
    command: "prettier --write"
    extensions: [".js", ".ts", ".jsx", ".tsx"]
    config: ".prettierrc"
  go:
    command: "gofmt -w"
    extensions: [".go"]
    config: null
  rust:
    command: "rustfmt"
    extensions: [".rs"]
    config: "rustfmt.toml"
```

## Next Steps

This spec is the design document. Implementation will happen in the `loa-constructs` repository as a new construct pack. See: https://github.com/0xHoneyJar/loa-constructs
