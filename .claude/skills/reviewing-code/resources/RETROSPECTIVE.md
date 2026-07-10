# Invisible Retrospective — Steps 3-5, Error Handling, Session Limits

Detailed procedure for the `reviewing-code` invisible-retrospective postlude. Steps 1-2 (config check, session scan) live in the skill body; this file holds the remainder. Before writing ANY learning content to disk, apply Step 3.5 sanitization (redact API keys/JWTs/secrets) first.

### Step 3: Apply Lightweight Quality Gates

For each candidate, evaluate these 4 gates:

| Gate | Question | PASS Condition |
|------|----------|----------------|
| **Depth** | Required multiple investigation steps? | Not just a quick glance - involved analysis, comparison, tracing |
| **Reusable** | Generalizable beyond this instance? | Applies to similar code patterns, not specific to this review |
| **Trigger** | Can describe when to apply? | Clear code patterns or conditions that indicate this applies |
| **Verified** | Solution confirmed working? | Fix verified or pattern validated in this session |

**Scoring**: Each gate passed = 1 point. Max score = 4.

**Threshold**: From config `surface_threshold` (default: 3)

### Step 3.5: Sanitize Descriptions (REQUIRED)

**CRITICAL**: Before logging or surfacing ANY candidate, sanitize descriptions to prevent sensitive data leakage.

Apply these redaction patterns:

| Pattern | Replacement |
|---------|-------------|
| API Keys (`sk-*`, `ghp_*`, `AKIA*`) | `[REDACTED_API_KEY]` |
| Private Keys (`-----BEGIN...PRIVATE KEY-----`) | `[REDACTED_PRIVATE_KEY]` |
| JWT Tokens (`eyJ...`) | `[REDACTED_JWT]` |
| Webhook URLs (`hooks.slack.com/*`, `hooks.discord.com/*`) | `[REDACTED_WEBHOOK]` |
| File Paths (`/home/*/`, `/Users/*/`) | `/home/[USER]/` or `/Users/[USER]/` |
| Email Addresses | `[REDACTED_EMAIL]` |
| IP Addresses | `[REDACTED_IP]` |
| Generic Secrets (`password=`, `secret=`, etc.) | `$key=[REDACTED]` |

If any redactions occur, add `"redactions_applied": true` to trajectory log.

### Step 4: Log to Trajectory (ALWAYS)

Write to `grimoires/loa/a2a/trajectory/retrospective-{YYYY-MM-DD}.jsonl`:

```json
{
  "type": "invisible_retrospective",
  "timestamp": "{ISO8601}",
  "skill": "reviewing-code",
  "action": "DETECTED|EXTRACTED|SKIPPED|DISABLED|ERROR",
  "candidates_found": N,
  "candidates_qualified": N,
  "candidates": [
    {
      "id": "learning-{timestamp}-{hash}",
      "signal": "error_resolution|multiple_attempts|unexpected_behavior|workaround|pattern_discovery",
      "description": "Brief description of the review learning",
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

### Step 5: Surface Qualified Findings

IF any candidates score >= `surface_threshold`:

1. **Add to NOTES.md `## Learnings` section**:

   **CRITICAL - Markdown Escape**: Before inserting description, escape these characters:
   - `#` → `\#`, `*` → `\*`, `[` → `\[`, `]` → `\]`, `\n` → ` `

   ```markdown
   ## Learnings
   - [{timestamp}] [reviewing-code] {ESCAPED Brief description} → skills-pending/{id}
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
         "skill": "reviewing-code",
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
     "skill": "reviewing-code",
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
