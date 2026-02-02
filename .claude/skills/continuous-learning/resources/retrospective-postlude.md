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
- This skill is `continuous-learning` → Exit silently (prevent recursion)

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
   ```markdown
   ## Learnings
   - [{timestamp}] [{skill}] {Brief description} → skills-pending/{id}
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
