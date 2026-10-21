# Retrospective Postlude Template

**Version**: 1.0.0
**Purpose**: Embed at END of SKILL.md files for invisible learning extraction

---

## Usage

Copy the `<retrospective_postlude>` section below and paste it at the very END of any skill's SKILL.md file, after all main skill content.

---

## Template

```xml
<retrospective_postlude>
## Invisible Retrospective

After completing main skill logic, scan session for learning opportunities.

**CRITICAL**: This postlude executes SILENTLY. Only surface findings that pass quality gates.

### Step 1: Check Configuration

Read `.loa.config.yaml`:
```yaml
invisible_retrospective:
  enabled: true|false
  skills:
    {current-skill-name}: true|false
```

**Exit Conditions** (skip all processing if any are true):
- `invisible_retrospective.enabled: false` → Log action: DISABLED, exit
- `invisible_retrospective.skills.{this-skill}: false` → Log action: DISABLED, exit
- **RECURSION GUARD**: This skill is `continuous-learning` → Exit silently (prevent infinite recursion)
  - INVARIANT: The `continuous-learning` skill MUST NEVER have a retrospective postlude
  - The schema also excludes `continuous-learning` from valid skill values

### Step 2: Scan Session for Learning Signals

Search the current conversation for these patterns:

| Signal | Detection Patterns | Weight |
|--------|-------------------|--------|
| Error Resolution | "error", "failed", "fixed", "resolved", "worked", "the issue was" | 3 |
| Multiple Attempts | "tried", "attempted", "finally", "after several", "on the Nth try" | 3 |
| Unexpected Behavior | "surprisingly", "actually", "turns out", "discovered", "realized" | 2 |
| Workaround Found | "instead", "alternative", "workaround", "bypass", "the trick is" | 2 |
| Pattern Discovery | "pattern", "convention", "always", "never", "this codebase" | 1 |

**Scoring**: Sum weights for each candidate discovery.

**Output**: List of candidate discoveries (max 5 per skill invocation, from config `max_candidates`)

If no candidates found:
- Log action: SKIPPED, candidates_found: 0
- Exit silently

### Step 3: Apply Lightweight Quality Gates

For each candidate, evaluate these 4 gates:

| Gate | Question | PASS Condition |
|------|----------|----------------|
| **Depth** | Required multiple investigation steps? | Not just a lookup - involved debugging, tracing, experimentation |
| **Reusable** | Generalizable beyond this instance? | Applies to similar problems, not hyper-specific to this file |
| **Trigger** | Can describe when to apply? | Clear symptoms or conditions that indicate this learning is relevant |
| **Verified** | Solution confirmed working? | Tested or verified in this session, not theoretical |

**Scoring**: Each gate passed = 1 point. Max score = 4.

**Threshold**: From config `surface_threshold` (default: 3)

### Step 3.5: Sanitize Descriptions (REQUIRED)

**CRITICAL**: Before logging or surfacing ANY candidate, sanitize descriptions to prevent sensitive data leakage.

Apply these redaction patterns (from `.claude/scripts/anonymize-proposal.sh`):

| Pattern | Regex | Replacement |
|---------|-------|-------------|
| API Keys | `(sk-[a-zA-Z0-9]{20,})\|(ghp_[a-zA-Z0-9]{36})\|(AKIA[A-Z0-9]{16})` | `[REDACTED_API_KEY]` |
| Private Keys | `-----BEGIN [A-Z ]+ PRIVATE KEY-----` | `[REDACTED_PRIVATE_KEY]` |
| JWT Tokens | `eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}` | `[REDACTED_JWT]` |
| Webhook URLs | `https://hooks\.(slack\|discord)\.com/[^\s]+` | `[REDACTED_WEBHOOK]` |
| File Paths | `/home/[^/]+/\|/Users/[^/]+/` | `/home/[USER]/` or `/Users/[USER]/` |
| Email Addresses | `[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}` | `[REDACTED_EMAIL]` |
| IP Addresses | `\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b` | `[REDACTED_IP]` |
| Generic Secrets | `(password\|secret\|token\|key)\s*[:=]\s*['"][^'"]+['"]` | `$1=[REDACTED]` |

**Implementation**:
1. For each candidate's `description` field, apply all patterns
2. Log warning to trajectory if any redactions occurred (for audit trail)
3. Use sanitized descriptions in ALL downstream operations

**Configuration** (`.loa.config.yaml`):
```yaml
invisible_retrospective:
  sanitize_descriptions: true  # Default: true, NEVER disable in production
```

If `sanitize_descriptions: false` is set, log WARNING to trajectory but still apply sanitization (defense in depth).

### Step 4: Log to Trajectory (ALWAYS)

Write to `grimoires/loa/a2a/trajectory/retrospective-{YYYY-MM-DD}.jsonl`:

```json
{
  "type": "invisible_retrospective",
  "timestamp": "{ISO8601}",
  "skill": "{current-skill-name}",
  "action": "DETECTED|EXTRACTED|SKIPPED|DISABLED|ERROR",
  "candidates_found": N,
  "candidates_qualified": N,
  "candidates": [
    {
      "id": "learning-{timestamp}-{hash}",
      "signal": "error_resolution|multiple_attempts|unexpected_behavior|workaround|pattern_discovery",
      "description": "Brief description of the learning",
      "score": N,
      "gates_passed": ["depth", "reusable", "trigger", "verified"],
      "gates_failed": [],
      "qualified": true|false
    }
  ],
  "extracted": ["learning-id-001"],
  "latency_ms": N
}
```

**Date**: Use today's date in YYYY-MM-DD format.
**Action Values**:
- `DETECTED`: Candidates found, some qualified
- `EXTRACTED`: Qualified candidates extracted to NOTES.md
- `SKIPPED`: No candidates found OR none qualified
- `DISABLED`: Feature or skill disabled in config
- `ERROR`: Processing error (see error field)

### Step 5: Surface Qualified Findings

IF any candidates score >= `surface_threshold`:

1. **Add to NOTES.md `## Learnings` section**:

   **CRITICAL - Markdown Escape**: Before inserting description, escape these characters:
   - `#` → `\#` (prevents section injection)
   - `*` → `\*` (prevents bold/italic injection)
   - `[` → `\[` (prevents link injection)
   - `]` → `\]` (prevents link injection)
   - `\n` → ` ` (collapse newlines to spaces - prevents multi-line injection)

   ```markdown
   ## Learnings
   - [{timestamp}] [{skill}] {ESCAPED Brief description} → skills-pending/{id}
   ```

   If `## Learnings` section doesn't exist, create it after `## Session Log`.

2. **Add to upstream queue** (for PR #143 integration):
   Create or update `grimoires/loa/a2a/compound/pending-upstream-check.json`:
   ```json
   {
     "queued_learnings": [
       {
         "id": "learning-{timestamp}-{hash}",
         "source": "invisible_retrospective",
         "skill": "{current-skill-name}",
         "queued_at": "{ISO8601}"
       }
     ]
   }
   ```

3. **Show brief notification**:
   ```
   ────────────────────────────────────────────
   Learning Captured
   ────────────────────────────────────────────
   Pattern: {brief description}
   Score: {score}/4 gates passed

   Added to: grimoires/loa/NOTES.md
   ────────────────────────────────────────────
   ```

IF no candidates qualify:
- Log action: SKIPPED
- **NO user-visible output** (silent)

### Error Handling

On ANY error during postlude execution:

1. Log to trajectory:
   ```json
   {
     "type": "invisible_retrospective",
     "timestamp": "{ISO8601}",
     "skill": "{current-skill-name}",
     "action": "ERROR",
     "error": "{error message}",
     "candidates_found": 0,
     "candidates_qualified": 0
   }
   ```

2. **Continue silently** - do NOT interrupt the main workflow
3. Do NOT surface error to user

### Session Limits

Respect these limits from config:
- `max_candidates`: Maximum candidates to evaluate per invocation (default: 5)
- `max_extractions_per_session`: Maximum learnings to extract per session (default: 3)

**Config Validation** (clamp out-of-range values):
- `surface_threshold`: Range 0-4 (clamp to bounds if outside)
- `max_candidates`: Range 1-20 (if > 20, clamp to 20 and note in trajectory)
- `max_extractions_per_session`: Range 1-10 (if > 10, clamp to 10 and note in trajectory)

Track session extractions in trajectory log and skip extraction if limit reached.

</retrospective_postlude>
```

---

## Skills to Embed

Priority 1 (high discovery potential):
- `implementing-tasks`
- `auditing-security`
- `reviewing-code`

Priority 2 (secondary):
- `deploying-infrastructure`
- `designing-architecture`

---

## Configuration Reference

```yaml
# .loa.config.yaml
invisible_retrospective:
  enabled: true
  log_to_trajectory: true
  surface_threshold: 3
  max_candidates: 5
  max_extractions_per_session: 3

  skills:
    implementing-tasks: true
    auditing-security: true
    reviewing-code: true
    deploying-infrastructure: false
    designing-architecture: false

  quality_gates:
    require_depth: true
    require_reusability: true
    require_trigger_clarity: true
    require_verification: true
```
