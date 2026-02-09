# Deep Analysis Guide

> Extracted from `/home/merlin/Documents/thj/code/loa/.claude/skills/riding-codebase/SKILL.md`
> Covers Phase 2 (Code Reality Extraction) and Phase 2b (Code Hygiene Audit)

---

## Phase 2: Code Reality Extraction

### 2.1 Setup

```bash
mkdir -p grimoires/loa/reality
cd "$TARGET_REPO"
```

### 2.1.5 Apply Loading Strategy (from Phase 0.5)

The loading strategy from Phase 0.5 controls file processing:

```bash
# Track token savings for reporting
TOKENS_SAVED=0
FILES_SKIPPED=0
FILES_EXCERPTED=0
FILES_LOADED=0

# Helper function: Check if file should be fully loaded
should_load_file() {
  local file="$1"

  # Always load in "full" strategy (small codebase)
  if [[ "$LOADING_STRATEGY" == "full" || "$LOADING_STRATEGY" == "eager" ]]; then
    return 0
  fi

  # Check loading plan or run should-load
  local decision
  decision=$(.claude/scripts/context-manager.sh should-load "$file" --json 2>/dev/null | jq -r '.decision // "load"')

  case "$decision" in
    load) return 0 ;;
    excerpt)
      ((FILES_EXCERPTED++))
      return 1
      ;;
    skip)
      local tokens
      tokens=$(.claude/scripts/context-manager.sh probe "$file" --json 2>/dev/null | jq -r '.estimated_tokens // 0')
      ((TOKENS_SAVED += tokens))
      ((FILES_SKIPPED++))
      return 2
      ;;
  esac
}

# Helper function: Get excerpt of file (high-relevance sections only)
get_file_excerpt() {
  local file="$1"
  local keywords=("export" "class" "interface" "function" "async" "api" "route" "handler")

  echo "# Excerpt: $file"
  echo ""

  # Extract lines containing keywords with 2 lines context
  for kw in "${keywords[@]}"; do
    grep -n -B1 -A2 "$kw" "$file" 2>/dev/null | head -20
  done | sort -t: -k1 -n -u | head -50
}

echo "Loading strategy: $LOADING_STRATEGY"
```

---

### 2.2 Directory Structure Analysis

```bash
echo "## Directory Structure" > grimoires/loa/reality/structure.md
echo '```' >> grimoires/loa/reality/structure.md
find . -type d -maxdepth 4 \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -not -path "*/dist/*" \
  -not -path "*/build/*" \
  -not -path "*/__pycache__/*" \
  2>/dev/null >> grimoires/loa/reality/structure.md
echo '```' >> grimoires/loa/reality/structure.md
```

---

### 2.3 Entry Points & Routes

```bash
.claude/scripts/search-orchestrator.sh hybrid \
  "@Get @Post @Put @Delete @Patch router app.get app.post app.put app.delete app.patch @route @api route handler endpoint" \
  "${TARGET_REPO}/src" 50 0.4 \
  > grimoires/loa/reality/api-routes.txt 2>/dev/null || \
grep -rn "@Get\|@Post\|@Put\|@Delete\|@Patch\|router\.\|app\.\(get\|post\|put\|delete\|patch\)\|@route\|@api" \
  --include="*.ts" --include="*.js" --include="*.py" --include="*.go" "${TARGET_REPO}" 2>/dev/null \
  > grimoires/loa/reality/api-routes.txt

ROUTE_COUNT=$(wc -l < grimoires/loa/reality/api-routes.txt 2>/dev/null || echo 0)
echo "Found $ROUTE_COUNT route definitions"
```

Uses `search-orchestrator.sh hybrid` with fallback to raw `grep` if the orchestrator is unavailable.

---

### 2.4 Data Models & Entities

```bash
.claude/scripts/search-orchestrator.sh hybrid \
  "model @Entity class Entity CREATE TABLE type struct interface schema definition" \
  "${TARGET_REPO}/src" 50 0.4 \
  > grimoires/loa/reality/data-models.txt 2>/dev/null || \
grep -rn "model \|@Entity\|class.*Entity\|CREATE TABLE\|type.*struct\|interface.*{\|type.*=" \
  --include="*.prisma" --include="*.ts" --include="*.sql" --include="*.go" --include="*.graphql" "${TARGET_REPO}" 2>/dev/null \
  > grimoires/loa/reality/data-models.txt
```

---

### 2.5 Environment Dependencies

```bash
.claude/scripts/search-orchestrator.sh regex \
  "process\\.env\\.[A-Z_]+|os\\.environ\\[|os\\.Getenv\\(|env\\.[A-Z_]+|import\\.meta\\.env\\." \
  "${TARGET_REPO}/src" 100 0.0 2>/dev/null | sort -u > grimoires/loa/reality/env-vars.txt || \
grep -roh 'process\.env\.\w\+\|os\.environ\[.\+\]\|os\.Getenv\(.\+\)\|env\.\w\+\|import\.meta\.env\.\w\+' \
  --include="*.ts" --include="*.js" --include="*.py" --include="*.go" "${TARGET_REPO}" 2>/dev/null \
  | sort -u > grimoires/loa/reality/env-vars.txt
```

---

### 2.6 Tech Debt Markers

```bash
.claude/scripts/search-orchestrator.sh regex \
  "TODO|FIXME|HACK|XXX|BUG|@deprecated|eslint-disable|@ts-ignore|type:\\s*any" \
  "${TARGET_REPO}/src" 100 0.0 \
  > grimoires/loa/reality/tech-debt.txt 2>/dev/null || \
grep -rn "TODO\|FIXME\|HACK\|XXX\|BUG\|@deprecated\|eslint-disable\|@ts-ignore\|type: any" \
  --include="*.ts" --include="*.js" --include="*.py" --include="*.go" "${TARGET_REPO}" 2>/dev/null \
  > grimoires/loa/reality/tech-debt.txt
```

---

### 2.7 Test Coverage Detection

```bash
find . -type f \( -name "*.test.ts" -o -name "*.spec.ts" -o -name "*_test.go" -o -name "test_*.py" \) \
  -not -path "*/node_modules/*" 2>/dev/null > grimoires/loa/reality/test-files.txt

TEST_COUNT=$(wc -l < grimoires/loa/reality/test-files.txt 2>/dev/null || echo 0)

if [[ "$TEST_COUNT" -eq 0 ]]; then
  echo "WARNING: NO TESTS FOUND - This is a significant gap"
fi
```

---

### 2.8 Tool Result Clearing Checkpoint (MANDATORY)

After all extractions complete, clear raw tool outputs from active context and replace with this summary template:

```markdown
## Phase 2 Extraction Summary (for active context)

Reality extraction complete. Results synthesized to grimoires/loa/reality/:
- Routes: [N] definitions -> reality/api-routes.txt
- Entities: [N] models -> reality/data-models.txt
- Env vars: [N] dependencies -> reality/env-vars.txt
- Tech debt: [N] markers -> reality/tech-debt.txt
- Tests: [N] files -> reality/test-files.txt

### Loading Strategy Results (RLM Pattern)

| Metric | Value |
|--------|-------|
| Strategy | $LOADING_STRATEGY |
| Files loaded | $FILES_LOADED |
| Files excerpted | $FILES_EXCERPTED |
| Files skipped | $FILES_SKIPPED |
| Tokens saved | ~$TOKENS_SAVED |

RAW TOOL OUTPUTS CLEARED FROM CONTEXT
Refer to reality/ files for specific file:line details.
```

---

## Phase 2b: Code Hygiene Audit

### Purpose

Flag potential issues for HUMAN DECISION - do not assume intent or prescribe fixes.

### 2b.1 Files Outside Standard Directories

Generate `grimoires/loa/reality/hygiene-report.md` using this template:

```markdown
# Code Hygiene Audit

## Files Outside Standard Directories
| Location | Type | Question for Human |
|----------|------|-------------------|
| `script.js` (root) | Script | Move to `scripts/` or intentional? |

## Potential Temporary/WIP Folders
| Folder | Files | Question |
|--------|-------|----------|
| `.temp_wip/` | 15 files | WIP for future, or abandoned? |

## Commented-Out Import/Code Blocks
| Location | Question |
|----------|----------|
| src/handlers/badge.ts:45 | Remove or waiting on fix? |

## Potential Dependency Conflicts
(e.g., Both `ethers` and `viem` present - potential conflict or migration in progress?)
```

---

### 2b.2 Dead Code Philosophy

Include this guidance in the hygiene report:

```markdown
## Important: Dead Code Philosophy

Items flagged above are for **HUMAN DECISION**, not automatic fixing.

When you see potential dead code:
- Ask: "What's the status of this?"
- Don't assume: "This needs to be fixed and integrated"

Possible dispositions:
- **Keep (WIP)**: Intentionally incomplete, will be finished
- **Keep (Reference)**: Useful for copy-paste or learning
- **Archive**: Move to `_archive/` folder
- **Delete**: Confirmed abandoned

Add disposition decisions to `grimoires/loa/NOTES.md` Decision Log.
```
