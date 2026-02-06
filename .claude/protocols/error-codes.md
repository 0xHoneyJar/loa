# Error Codes Protocol

**Version**: 1.0.0
**Status**: Active
**Data File**: `.claude/data/error-codes.json`
**Library**: `.claude/scripts/lib/dx-utils.sh`

---

## Overview

Loa uses a structured error code system inspired by [Rust RFC 1644](https://rust-lang.github.io/rfcs/1644-default-and-expanded-rustc-errors.html) — errors should teach, not punish. Every error code tells the user **what** went wrong and **how** to fix it.

```
LOA-E301: event_bus_unavailable

  The event bus store directory does not exist or is not writable.
  ─→ /home/user/project/.events/

  Fix: Check that the event store directory exists and is writable. Run /loa doctor for details.
```

Design principles from the [CLI Guidelines](https://clig.dev/):
- **Pattern 4**: Errors That Teach — every error includes a fix suggestion
- **Pattern 5**: Suggest the Next Command — guide users forward
- **Pattern 10**: Sweat Every Word — concise, scannable output

---

## Convention: LOA-EXXX

Error codes follow the format `LOA-EXXX` where `XXX` is a three-digit code grouped by category:

| Range | Category | Scope |
|-------|----------|-------|
| `E0xx` | Framework & Environment | Missing deps, config errors, path resolution |
| `E1xx` | Workflow & Lifecycle | Phase skipping, session timeouts, run mode |
| `E2xx` | Beads & Task Tracking | Installation, initialization, schema, sync |
| `E3xx` | Events & Bus | Delivery failures, validation, lock contention |
| `E4xx` | Security & Guardrails | Danger levels, PII detection, injection, integrity |
| `E5xx` | Constructs & Packs | Manifest validation, dependencies, topology |

### Why Numbered Codes?

1. **Searchable**: `LOA-E301` finds exactly one result in docs/code
2. **Parseable**: CI can match `LOA-E\d{3}` in output for automated triage
3. **Stable**: Code numbers never change; names can be refined
4. **Educational**: `dx_explain E301` shows expanded documentation

---

## Error Display Format

Every error rendered by `dx_error()` follows a four-part structure:

```
LOA-{CODE}: {name}

  {what}
  ─→ {context}           ← optional, caller-provided

  Fix: {fix}
```

| Field | Source | Example |
|-------|--------|---------|
| `code` | error-codes.json `.code` | `E301` |
| `name` | error-codes.json `.name` | `event_bus_unavailable` |
| `what` | error-codes.json `.what` | "The event bus store directory does not exist..." |
| `context` | Caller passes as `$2+` to `dx_error()` | Path, filename, or runtime detail |
| `fix` | error-codes.json `.fix` | "Check that the event store directory exists..." |

### Expanded View

`dx_explain E301` shows additional context:

```
LOA-E301: event_bus_unavailable
Category: Events & Bus

  What: The event bus store directory does not exist or is not writable.
  Fix:  Check that the event store directory exists and is writable.

  Related:
    LOA-E302  event_validation_failed
    LOA-E303  event_delivery_failed
    LOA-E304  event_payload_oversized
    LOA-E305  flock_timeout
```

---

## Data File Schema

Error codes live in `.claude/data/error-codes.json` — a JSON array where each entry has:

```json
{
  "code": "E301",
  "name": "event_bus_unavailable",
  "category": "events",
  "what": "The event bus store directory does not exist or is not writable.",
  "fix": "Check that the event store directory exists and is writable. Run /loa doctor for details."
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `code` | string | yes | `E` + 3 digits, unique across registry |
| `name` | string | yes | snake_case identifier |
| `category` | string | yes | One of: `framework`, `workflow`, `beads`, `events`, `security`, `constructs` |
| `what` | string | yes | User-facing description of the problem |
| `fix` | string | yes | Actionable remediation steps |

### Validation

The registry is validated structurally at test time:

```bash
# All codes unique
jq '[.[].code] | length == (. | unique | length)' error-codes.json

# All required fields present
jq 'all(.[]; .code and .name and .category and .what and .fix)' error-codes.json

# Valid categories
jq '[.[].category] | unique | . - ["framework","workflow","beads","events","security","constructs"] | length == 0' error-codes.json
```

---

## Using Error Codes in Scripts

### Basic Usage

```bash
source "${SCRIPT_DIR}/lib/dx-utils.sh"

# Emit a known error (returns 0)
dx_error "E301" "/path/to/event-store"

# Emit with no context (returns 0)
dx_error "E006"

# Unknown code (returns 1, prints generic message)
dx_error "E999"
```

### Important Contract

`dx_error()` **NEVER** calls `exit`. The caller decides what to do:

```bash
# Pattern: error + bail
dx_error "E006"
return 1

# Pattern: error + degrade gracefully
dx_error "E008" "flock not found"
echo "Falling back to non-atomic writes"

# Pattern: error + suggest next command
dx_error "E101"
dx_next_steps "Run /plan-and-analyze|Create a PRD first"
```

### Graceful Fallback

If `jq` is unavailable or `error-codes.json` is missing, `dx_error()` still works — it prints the raw code with a generic "run /loa doctor" suggestion. The library never crashes; it degrades.

---

## Adding a New Error Code

### Step 1: Choose a Code

Pick the next available number in the appropriate category:

```bash
# See what's taken
jq '.[].code' .claude/data/error-codes.json | sort
```

### Step 2: Add the Entry

Add to `.claude/data/error-codes.json`:

```json
{
  "code": "E010",
  "name": "your_error_name",
  "category": "framework",
  "what": "Clear description of what went wrong.",
  "fix": "Actionable steps to resolve. Include commands where possible."
}
```

### Step 3: Write Quality Checks

Before submitting:

- [ ] `what` answers "What happened?" in one sentence
- [ ] `fix` answers "How do I fix it?" with a concrete action
- [ ] `fix` includes a command if one exists (e.g., "Run /loa doctor")
- [ ] `category` matches the code range (E0xx→framework, etc.)
- [ ] Code is unique (run validation above)
- [ ] Entry passes `jq . < error-codes.json`

### Step 4: Use It

```bash
dx_error "E010" "optional runtime context"
```

No code changes needed in `dx-utils.sh` — the registry is loaded dynamically.

---

## References

- [Rust RFC 1644: Default and Expanded Errors](https://rust-lang.github.io/rfcs/1644-default-and-expanded-rustc-errors.html) — the gold standard for structured error output
- [CLI Guidelines (clig.dev)](https://clig.dev/) — community-driven CLI UX patterns
- [Issue #211](https://github.com/0xHoneyJar/loa/issues/211) — DX comparison audit that inspired this system
- [NO_COLOR](https://no-color.org/) — color output convention respected by dx-utils.sh
