# JIT Retrieval Protocol

> **Version**: 2.0 (v0.20.0 Recursive JIT Context System)
> **Paradigm**: Clear, Don't Compact

## Purpose

Replace eager loading of code blocks with lightweight identifiers, achieving 97% token reduction while maintaining full access to evidence on-demand.

## Recursive JIT Integration (v0.20.0)

The JIT Retrieval Protocol now integrates with the Recursive JIT Context System for enhanced caching and parallel subagent coordination. See `recursive-context.md` for full details.

### Cache Integration

Before performing expensive retrieval operations, check the semantic cache:

```bash
# Generate cache key from query parameters
cache_key=$(.claude/scripts/cache-manager.sh generate-key \
  --paths "$target_files" \
  --query "$query" \
  --operation "jit-retrieve")

# Check cache first
if cached=$(.claude/scripts/cache-manager.sh get --key "$cache_key"); then
  # Cache hit - use cached identifiers
  echo "$cached"
else
  # Cache miss - perform retrieval
  result=$(ck --hybrid "$query" "$path" --top-k 5 --jsonl)

  # Condense and cache for future use
  condensed=$(.claude/scripts/condense.sh condense \
    --strategy identifiers_only \
    --input <(echo "$result"))

  .claude/scripts/cache-manager.sh set \
    --key "$cache_key" \
    --condensed "$condensed" \
    --sources "$target_files"

  echo "$condensed"
fi
```

### Updated Decision Tree

```
RETRIEVAL DECISION (with Cache):
┌───────────────────────────────────────────────────────────────┐
│ Need code evidence?                                            │
│   │                                                            │
│   ├── YES: Check semantic cache first                         │
│   │   │                                                        │
│   │   ├── CACHE HIT: Use cached identifiers                   │
│   │   │                                                        │
│   │   └── CACHE MISS: Is ck available?                        │
│   │       ├── YES: ck --hybrid → cache result                 │
│   │       └── NO: grep fallback → cache result                │
│   │                                                            │
│   └── NO: Use identifier only (no retrieval needed)           │
└───────────────────────────────────────────────────────────────┘
```

### Semantic Recovery

When recovering context after `/clear`, use query-based semantic selection:

```bash
# Semantic recovery with query (new in v0.20.0)
.claude/scripts/context-manager.sh recover 2 --query "authentication"

# This selects NOTES.md sections most relevant to the query,
# rather than loading fixed sections positionally.
```

## The Problem

Eager loading consumes attention budget:

```
EAGER LOADING (Anti-Pattern):
┌─────────────────────────────────────────────────────────────────┐
│ User: "How does authentication work?"                            │
│                                                                  │
│ Agent loads:                                                     │
│   • auth/jwt.ts (full file - 200 lines)        → ~2000 tokens   │
│   • auth/refresh.ts (full file - 150 lines)    → ~1500 tokens   │
│   • middleware/auth.ts (full file - 100 lines) → ~1000 tokens   │
│                                                                  │
│ TOTAL CONTEXT CONSUMED: ~4500 tokens                             │
│ ATTENTION REMAINING: Severely degraded                           │
└─────────────────────────────────────────────────────────────────┘
```

## The Solution

JIT retrieval stores identifiers, loads content on-demand:

```
JIT RETRIEVAL (Correct):
┌─────────────────────────────────────────────────────────────────┐
│ User: "How does authentication work?"                            │
│                                                                  │
│ Agent stores identifiers:                                        │
│   • ${PROJECT_ROOT}/src/auth/jwt.ts:45-67      → ~15 tokens     │
│   • ${PROJECT_ROOT}/src/auth/refresh.ts:12-34  → ~15 tokens     │
│   • ${PROJECT_ROOT}/middleware/auth.ts:20-45   → ~15 tokens     │
│                                                                  │
│ TOTAL CONTEXT: ~45 tokens (97% reduction)                        │
│ ATTENTION: Full budget available for reasoning                   │
└─────────────────────────────────────────────────────────────────┘
```

## Token Comparison

| Approach | Tokens | Result |
|----------|--------|--------|
| Eager loading (50-line block) | ~500 | Context fills, attention degrades |
| JIT identifier (path + line) | ~15 | 97% reduction, retrieve on-demand |
| Full file load (200 lines) | ~2000 | Catastrophic attention loss |

**Math**: 15 tokens / 500 tokens = 3% → **97% reduction**

## Lightweight Identifier Format

### Standard Format

```markdown
| Identifier | Purpose | Last Verified |
|------------|---------|---------------|
| ${PROJECT_ROOT}/src/auth/jwt.ts:45-67 | Token validation logic | 14:25:00Z |
| ${PROJECT_ROOT}/src/auth/refresh.ts:12 | rotateRefreshToken function | 14:28:00Z |
```

### Format Requirements

1. **Absolute path**: Always use `${PROJECT_ROOT}` prefix
2. **Line reference**: Single line (`:45`) or range (`:45-67`)
3. **Purpose**: Brief description (~3-5 words)
4. **Verification timestamp**: ISO 8601 time (without date, assumes current day)

### Path Validation

```
VALID:
  ${PROJECT_ROOT}/src/auth/jwt.ts:45
  ${PROJECT_ROOT}/src/auth/jwt.ts:45-67
  ${PROJECT_ROOT}/lib/utils/hash.ts:100

INVALID:
  src/auth/jwt.ts:45           (relative path)
  ./src/auth/jwt.ts:45         (relative path)
  /home/user/project/src/...   (hardcoded absolute)
  auth/jwt.ts                   (no line reference)
```

## Retrieval Methods

### Method 1: ck Hybrid Search (Recommended)

When you need to find relevant code semantically:

```bash
# Semantic + keyword hybrid search
ck --hybrid "token validation" "${PROJECT_ROOT}/src/" --top-k 3 --jsonl

# Output format (JSONL):
{"path":"src/auth/jwt.ts","line":45,"score":0.92,"snippet":"export function validateToken..."}
```

**When to use**: Initial discovery, finding related code, answering "how does X work?"

### Method 2: ck Full Section (AST-Aware)

When you need a complete function/class:

```bash
# Get complete function with AST awareness
ck --full-section "validateToken" "${PROJECT_ROOT}/src/auth/jwt.ts"

# Returns the entire function, not just matched lines
```

**When to use**: Need complete context for a specific function, code review, modification planning

### Method 3: sed Line Extraction (Fallback)

When ck is unavailable:

```bash
# Extract specific line range
sed -n '45,67p' "${PROJECT_ROOT}/src/auth/jwt.ts"
```

**When to use**: ck not installed, simple line extraction, known exact location

### Method 4: grep Pattern Search (Fallback)

When ck is unavailable and you need to search:

```bash
# Search with context
grep -n "validateToken" "${PROJECT_ROOT}/src/" -r --include="*.ts"
```

**When to use**: ck not installed, pattern-based search, known function name

## Retrieval Decision Tree

```
RETRIEVAL DECISION:
┌───────────────────────────────────────────────────────────┐
│ Need code evidence?                                        │
│   │                                                        │
│   ├── YES: Is ck available?                               │
│   │   │                                                    │
│   │   ├── YES: Need semantic search?                      │
│   │   │   ├── YES → ck --hybrid "query" path              │
│   │   │   └── NO: Need full function?                     │
│   │   │       ├── YES → ck --full-section "name" file     │
│   │   │       └── NO → sed -n 'start,endp' file           │
│   │   │                                                    │
│   │   └── NO: Know exact location?                        │
│   │       ├── YES → sed -n 'start,endp' file              │
│   │       └── NO → grep -n "pattern" path                 │
│   │                                                        │
│   └── NO: Use identifier only (no retrieval needed)       │
└───────────────────────────────────────────────────────────┘
```

## Integration with Session Continuity

### Storing Identifiers

When you find relevant code, store the identifier (not the content):

```markdown
### Lightweight Identifiers
| Identifier | Purpose | Last Verified |
|------------|---------|---------------|
| ${PROJECT_ROOT}/src/auth/jwt.ts:45-67 | Token validation | 14:25:00Z |
```

### Decision Log Evidence

When logging decisions, use word-for-word quotes with identifiers:

```markdown
**Evidence**:
- `export function validateToken(token: string): boolean` [${PROJECT_ROOT}/src/auth/jwt.ts:45]
```

### Session Recovery

After `/clear`, identifiers are available but content is not loaded:

```
RECOVERY SEQUENCE:
1. Read NOTES.md Session Continuity section
2. Identifiers table shows what code was relevant
3. DO NOT load content yet
4. When reasoning requires code, JIT retrieve specific sections
```

## ck Availability Check

Before using ck commands, verify availability:

```bash
# Check if ck is available
.claude/scripts/check-ck.sh

# Returns:
#   CK_STATUS=available    # ck is installed and functional
#   CK_STATUS=unavailable  # ck not found, use fallbacks
```

### Integration with check-ck.sh

The `check-ck.sh` script provides a standardized way to detect ck availability:

```bash
# In your workflow script
source .claude/scripts/check-ck.sh 2>/dev/null || CK_STATUS="unavailable"

if [[ "$CK_STATUS" == "available" ]]; then
    # Use ck for semantic search
    ck --hybrid "$query" "$path" --top-k 5 --jsonl
else
    # Fallback to grep
    grep -rn "$pattern" "$path"
fi
```

### ck Command Reference

| Command | Purpose | Output |
|---------|---------|--------|
| `ck --hybrid "query" path` | Semantic + keyword search | Ranked results |
| `ck --hybrid "query" path --jsonl` | Machine-parseable output | JSONL format |
| `ck --full-section "name" file` | AST-aware function extraction | Complete function |
| `ck --threshold 0.4` | Set similarity threshold | Filter low-confidence |
| `ck --top-k N` | Limit results | Top N matches |

### Example: Semantic Search with Fallback

```bash
#!/usr/bin/env bash
# search-with-fallback.sh

query="$1"
path="${2:-.}"

# Check ck availability
if command -v ck &>/dev/null; then
    # Semantic search (preferred)
    ck --hybrid "$query" "$path" --top-k 5 --jsonl
else
    # Grep fallback (degraded but functional)
    echo "# Warning: Using grep fallback (no semantic search)"
    grep -rn "$query" "$path" --include="*.ts" --include="*.js" | head -10
fi
```

### Example: AST-Aware Section Extraction

```bash
# With ck (AST-aware, extracts complete function)
ck --full-section "validateToken" src/auth/jwt.ts
# Returns the entire function definition, properly bounded

# Without ck (line-based, may be incomplete)
grep -n "validateToken" src/auth/jwt.ts  # Find line number
sed -n '45,80p' src/auth/jwt.ts          # Extract range (manual boundary detection)
```

**Note**: The grep/sed fallback requires manual boundary detection and may include incomplete or excessive content.

## Fallback Behavior

When ck is unavailable, all features have fallbacks:

| Feature | ck Command | Fallback |
|---------|------------|----------|
| Semantic search | `ck --hybrid "query"` | `grep -rn "pattern"` |
| AST-aware section | `ck --full-section "name"` | `sed -n 'start,endp'` (line range) |
| Negative grounding | `ck --hybrid --threshold 0.4` | Manual verification required |

**Important**: Fallbacks are **degraded** but functional. Semantic search becomes keyword search. AST-aware becomes line-range.

## Token Budget Tracking

Track your retrieval impact:

```markdown
### Token Budget
| Operation | Tokens Used | Running Total |
|-----------|-------------|---------------|
| Level 1 recovery | 100 | 100 |
| JIT: jwt.ts:45-67 | 50 | 150 |
| JIT: refresh.ts:12-34 | 45 | 195 |
| Reasoning | 300 | 495 |
```

**Goal**: Stay under Yellow threshold (5,000 tokens) for as long as possible.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|--------------|------------------|
| Load full file "just in case" | Store identifier, JIT retrieve when needed |
| Copy-paste entire functions | Quote the specific line with path reference |
| Search results in context | Summarize results, store identifiers |
| Relative paths | Always `${PROJECT_ROOT}` prefix |
| Load without tracking | Track token usage in context |

## Examples

### Example 1: Initial Discovery

```
User: "How does token refresh work?"

WRONG:
  cat src/auth/refresh.ts  # 150 lines → 1500 tokens

CORRECT:
  ck --hybrid "token refresh" src/auth/ --top-k 3 --jsonl
  # Store identifiers from results:
  | ${PROJECT_ROOT}/src/auth/refresh.ts:12-45 | rotateRefreshToken | now |
  | ${PROJECT_ROOT}/src/auth/jwt.ts:80-95 | isTokenExpired | now |

  # Summarize: "Token refresh handled by rotateRefreshToken() which checks
  # expiry via isTokenExpired(). Identifiers stored for JIT retrieval."
```

### Example 2: Evidence for Decision

```
Decision: Use 15-minute grace period for token expiry

WRONG:
  "Based on the code I saw earlier..." (no evidence)

CORRECT:
  ck --full-section "isTokenExpired" src/auth/jwt.ts
  # Extract specific quote:
  **Evidence**:
  - `graceMs = 900000` [${PROJECT_ROOT}/src/auth/jwt.ts:52]
  # Don't keep full function in context
```

### Example 3: Session Recovery

```
After /clear:

1. Read NOTES.md Session Continuity
2. See identifiers table:
   | ${PROJECT_ROOT}/src/auth/jwt.ts:45-67 | Token validation | 14:25:00Z |

3. Resume reasoning about token validation
4. When need actual code:
   sed -n '45,67p' "${PROJECT_ROOT}/src/auth/jwt.ts"
5. Use code, then discard from active context
```

## Configuration

See `.loa.config.yaml`:

```yaml
jit_retrieval:
  prefer_ck: true          # Use ck when available
  fallback_enabled: true   # Allow grep/sed fallbacks
  max_line_range: 100      # Max lines to retrieve at once
```

## Related Documentation

- `recursive-context.md` - Full Recursive JIT Context Protocol
- `semantic-cache.md` - Semantic cache operations
- `session-continuity.md` - Session lifecycle
- `context-compaction.md` - Compaction rules

---

**Document Version**: 2.0
**Protocol Version**: v2.3 (Recursive JIT Integration)
**Paradigm**: Clear, Don't Compact
