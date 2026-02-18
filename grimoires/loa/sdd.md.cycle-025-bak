# SDD: Cross-Codebase Feedback Routing

> Cycle: cycle-025 | PRD: grimoires/loa/prd.md
> Source: [#355](https://github.com/0xHoneyJar/loa/issues/355)

## 1. Architecture Overview

This feature extends the existing feedback routing pipeline with construct-aware attribution. The design adds 2 new scripts, extends 2 existing scripts, and extends 1 command — all within the `.claude/` System Zone.

```
User Feedback Path:
  /feedback → feedback.md Phase 0.5 → feedback-classifier.sh
                                          ↓ (construct detected)
                                    construct-attribution.sh
                                          ↓
                                    feedback-redaction.sh
                                          ↓
                                    user confirmation prompt
                                          ↓
                                    gh issue create (external repo)
                                          ↓
                                    feedback-ledger.json (dedup)
```

### Component Map

| Component | Type | Action |
|-----------|------|--------|
| `.claude/scripts/construct-attribution.sh` | NEW | Attribution engine — maps findings to constructs |
| `.claude/scripts/feedback-redaction.sh` | NEW | Content redaction for external repos |
| `.claude/scripts/feedback-classifier.sh` | MODIFY | Add `construct` category, call attribution |
| `.claude/commands/feedback.md` | MODIFY | Extend Phase 0.5 for construct routing + redaction preview |
| `.run/feedback-ledger.json` | NEW DATA | Dedup/rate-limit tracking |

### Zone Compliance

All new/modified files are in the System Zone (`.claude/`). The only State Zone file is `.run/feedback-ledger.json` (ephemeral state). No App Zone changes.

## 2. Component Design

### 2.1 construct-attribution.sh (NEW)

**Location**: `.claude/scripts/construct-attribution.sh`
**Purpose**: Given feedback text, determine if it relates to an installed construct.

**Interface**:
```bash
construct-attribution.sh --context <file_or_->
# Output: JSON attribution record
```

**Algorithm**:

```bash
# 1. Load installed constructs from .constructs-meta.json
constructs=$(get_registry_meta '.installed_skills + .installed_packs')

# 2. Build lookup tables
#    - skill_names: {name → vendor/pack}
#    - pack_names: {slug → source_repo}
#    - path_prefixes: [".claude/constructs/skills/", ".claude/constructs/packs/"]
#    - vendor_names: unique vendor strings

# 3. Score context against signals
score=0; max_possible=3.0; signals=[]

# Signal: path match (weight 1.0)
if context matches ".claude/constructs/(skills|packs)/{vendor_or_pack}/"; then
    score += 1.0
    signals += "path_match:{matched_path}"
    # Extract vendor/pack from path
fi

# Signal: skill name match (weight 0.6)
for skill_name in installed_skill_names; do
    if context contains skill_name; then
        score += 0.6
        signals += "skill_name:{skill_name}"
    fi
done

# Signal: vendor name match (weight 0.4)
for vendor in known_vendors; do
    if context contains vendor; then
        score += 0.4
        signals += "vendor_name:{vendor}"
    fi
done

# Signal: explicit user mention (weight 1.0)
for pack in installed_pack_names; do
    if context contains "construct:{pack}" or "pack:{pack}"; then
        score += 1.0
        signals += "explicit_mention:{pack}"
    fi
done

# 4. Normalize: confidence = min(score / max_possible, 1.0)
# 5. Resolve source_repo from manifest.yaml (if pack identified)
# 6. Output JSON
```

**Output format**:
```json
{
  "attributed": true,
  "construct": "artisan/observer",
  "construct_type": "pack",
  "source_repo": "0xHoneyJar/observer-pack",
  "confidence": 0.53,
  "signals": ["path_match:.claude/constructs/packs/observer/", "vendor_name:artisan"],
  "trust_warning": null,
  "version": "1.2.0"
}
```

**Trust validation** (FR-2, hardened per Flatline SKP-002):

```bash
# Level 1: Format validation
if ! echo "$source_repo" | grep -qE '^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$'; then
    trust_warning="source_repo format invalid: must be 'owner/repo'"
    source_repo=""  # Block routing
fi

# Level 2: Org match check
repo_org=$(echo "$source_repo" | cut -d'/' -f1)
if [[ "$repo_org" != "$vendor" ]]; then
    trust_warning="source_repo org '$repo_org' does not match vendor '$vendor'"
fi

# Level 3: Repo existence check (if gh available, non-blocking)
if command -v gh &>/dev/null && [[ -n "$source_repo" ]]; then
    if ! gh repo view "$source_repo" --json name >/dev/null 2>&1; then
        trust_warning="source_repo '$source_repo' does not exist or is not accessible"
    fi
fi
```

Trust warnings are cumulative — all warnings shown to user in confirmation prompt. Any Level 1 failure (invalid format) blocks routing entirely.

**Dependencies**: `constructs-lib.sh` (for `get_registry_meta`, directory functions), `jq`.

**False positive mitigation** (Flatline SKP-003): Skill/vendor name matches require word-boundary matching (`\b{name}\b`) to avoid incidental substring matches. Names shorter than 4 characters are excluded from name matching (path match and explicit mention still apply).

**Disambiguation** (Flatline IMP-001): When multiple constructs match:
1. Pick the construct with highest confidence score
2. If top two scores are within 0.1 of each other, set `"ambiguous": true` in output
3. Include `"candidates": [...]` array with all matches sorted by confidence
4. Caller (feedback.md) presents all candidates to user for selection

**Exit codes** (Flatline IMP-002):
- 0: Attribution successful (attributed=true or attributed=false)
- 1: Invalid input (missing --context, unreadable file)
- 2: Corrupt .constructs-meta.json (invalid JSON)

**No-construct fast path**: If `.constructs-meta.json` doesn't exist or has no installed skills/packs, output `{"attributed": false}` immediately.

### 2.2 feedback-redaction.sh (NEW)

**Location**: `.claude/scripts/feedback-redaction.sh`
**Purpose**: Strip sensitive content from feedback before filing on external repos.

**Interface**:
```bash
feedback-redaction.sh --input <file> --config <yaml_path> [--preview]
# Output: redacted text to stdout
# --preview: show diff of what was redacted
```

**Redaction rules** (applied in order):

| Rule | Pattern | Replacement |
|------|---------|-------------|
| Absolute paths | `/home/`, `/Users/`, `/tmp/` prefixes | `<redacted-path>/` + relative portion |
| Home directory | `~/` or `$HOME` | `~/<redacted>` |
| AWS keys | `AKIA[0-9A-Z]{16}` | `<redacted-aws-key>` |
| GitHub tokens | `gh[ps]_[A-Za-z0-9_]{36,}` | `<redacted-github-token>` |
| JWT tokens | `eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+` | `<redacted-jwt>` |
| Generic secrets | `(password\|secret\|token\|key)\s*[=:]\s*\S+` | `$1=<redacted>` |
| Environment vars | `[A-Z_]{3,}=[^\s]+` (in env context) | `$var=<redacted>` |
| SSH paths | `~/.ssh/`, `~/.gnupg/` | `<redacted-credential-path>` |
| Git credentials | `https://[^@]+@` | `https://<redacted>@` |

**User toggles** (from config):
```bash
# Read from .loa.config.yaml
include_snippets=$(yq '.feedback.routing.construct_routing.redaction.include_snippets // false')
include_file_refs=$(yq '.feedback.routing.construct_routing.redaction.include_file_refs // true')
include_environment=$(yq '.feedback.routing.construct_routing.redaction.include_environment // false')
```

If `include_snippets=false`: strip all fenced code blocks.
If `include_file_refs=true`: keep file references but replace absolute paths with relative.
If `include_environment=false`: strip any "Environment" section entirely.

**Second-pass entropy validation** (Flatline IMP-003 / SKP-001):

After regex-based redaction, run a second pass that scans for high-entropy strings (potential leaked secrets that regex missed):

```bash
# For each word/token > 20 chars in redacted output:
#   Calculate Shannon entropy
#   If entropy > 4.5 bits/char: flag as potential secret
#   Replace with <high-entropy-redacted> unless on allowlist
#
# Allowlist (not secrets):
#   - SHA256 hashes (64 hex chars)
#   - UUIDs (8-4-4-4-12 format)
#   - Base64 URLs (known patterns like github.com URLs)
#   - Known jq/bash syntax tokens
```

This catches secrets that don't match known patterns (custom API keys, internal tokens, base64-encoded credentials).

**Exit codes** (Flatline IMP-002):
- 0: Redaction successful
- 1: Invalid input (missing --input, unreadable file)
- 2: Redaction produced empty output (input was entirely sensitive)

**Dependencies**: `grep`, `sed`, `awk` (for entropy calculation), `yq`. No external API calls.

### 2.3 feedback-classifier.sh (MODIFY)

**Changes**: Add `construct` category to the signal pattern system.

**New signal patterns** (added to `SIGNAL_PATTERNS` array):
```bash
# construct signals
"construct:.claude/constructs/:3"
"construct:constructs/skills/:3"
"construct:constructs/packs/:3"
```

**New routing logic** (after existing classification):
```bash
# If construct signals detected OR attribution confidence >= threshold
if [[ "${scores[construct]}" -gt 0 ]]; then
    # Run full attribution
    attribution=$(construct-attribution.sh --context "$context_file")
    attributed=$(echo "$attribution" | jq -r '.attributed')
    confidence=$(echo "$attribution" | jq -r '.confidence')

    threshold=$(yq '.feedback.routing.construct_routing.attribution_threshold // 0.33' \
        "$CONFIG_FILE" 2>/dev/null)

    if [[ "$attributed" == "true" ]] && \
       awk "BEGIN{exit !($confidence >= $threshold)}"; then
        # Override classification to construct
        classification="construct"
        recommended_repo=$(echo "$attribution" | jq -r '.source_repo // empty')
        # Include attribution in output
    fi
fi
```

**Output extension** (backward compatible — new fields added):
```json
{
  "classification": "construct",
  "confidence": 0.53,
  "signals_matched": ["construct path +3"],
  "recommended_repo": "0xHoneyJar/observer-pack",
  "scores": {
    "loa_framework": 0,
    "loa_constructs": 0,
    "forge": 0,
    "project": 0,
    "construct": 3
  },
  "attribution": {
    "construct": "artisan/observer",
    "source_repo": "0xHoneyJar/observer-pack",
    "confidence": 0.53,
    "trust_warning": null,
    "version": "1.2.0"
  }
}
```

When no constructs are installed, the `construct` score is always 0 and `attribution` is absent. Backward compatible.

### 2.4 feedback.md (MODIFY)

**Changes to Phase 0.5** (Smart Routing Classification):

```
Phase 0.5 (existing):
  1. Call feedback-classifier.sh
  2. Present 4 repo options to user

Phase 0.5 (new — when classification == "construct"):
  1. Call feedback-classifier.sh (now returns attribution)
  2. If construct detected:
     a. Check dedup ledger (feedback-ledger.json)
     b. If duplicate: show "Already filed" message, offer options
     c. If rate-limited: show warning, require extra confirmation
     d. Run feedback-redaction.sh --preview on draft content
     e. Show redaction preview:
        "This feedback will be filed on {source_repo}:"
        [redacted preview]
     f. If trust_warning: show prominent warning
     g. AskUserQuestion:
        - "Route to {source_repo}" (default)
        - "Route to 0xHoneyJar/loa instead"
        - "Route to current project"
        - "Copy to clipboard"
  3. On confirmation: apply redaction, create issue, update ledger
```

**New Phase 5.1** (after GitHub submission, construct-only):
```
Phase 5.1: Update Dedup Ledger
  1. Calculate fingerprint (sha256 of redacted body)
  2. Append to .run/feedback-ledger.json
  3. If file doesn't exist, create with empty submissions array
```

### 2.5 feedback-ledger.json (NEW DATA)

**Location**: `.run/feedback-ledger.json`
**Purpose**: Track external submissions for dedup and rate limiting.

```json
{
  "schema_version": 1,
  "submissions": [
    {
      "repo": "0xHoneyJar/observer-pack",
      "fingerprint": "sha256:abc123...",
      "timestamp": "2026-02-17T12:00:00Z",
      "issue_url": "https://github.com/0xHoneyJar/observer-pack/issues/1",
      "construct": "artisan/observer",
      "feedback_type": "user_feedback"
    }
  ]
}
```

**Dedup check** (in feedback.md Phase 0.5):
```bash
# Check for duplicate
fingerprint=$(echo "$redacted_body" | sha256sum | cut -d' ' -f1)
existing=$(jq --arg fp "$fingerprint" --arg repo "$repo" \
    '.submissions[] | select(.fingerprint == $fp and .repo == $repo)' \
    .run/feedback-ledger.json 2>/dev/null)
if [[ -n "$existing" ]]; then
    echo "This feedback was already filed: $(echo $existing | jq -r .issue_url)"
fi

# Rate limit check (cross-platform date handling per Flatline SKP-004)
# Use portable epoch arithmetic instead of GNU date -d
now_epoch=$(date +%s)
cutoff_epoch=$((now_epoch - 86400))  # 24 hours in seconds
count_24h=$(jq --argjson cutoff "$cutoff_epoch" \
    --arg repo "$repo" \
    '[.submissions[] | select(.repo == $repo and (.epoch // 0) > $cutoff)] | length' \
    .run/feedback-ledger.json 2>/dev/null)
```

**Atomic writes** (Flatline SKP-004 concurrency): All ledger updates use write-to-temp + `mv` pattern:
```bash
jq '...' .run/feedback-ledger.json > .run/feedback-ledger.json.tmp
mv .run/feedback-ledger.json.tmp .run/feedback-ledger.json
```

Submissions include `epoch` field (Unix timestamp) alongside ISO `timestamp` for portable date comparison.

## 3. Data Flow

### Happy Path: User files construct feedback

```
1. User: /feedback "The observer pack's interview skill crashes on empty input"
2. feedback.md Phase 0.5:
   → feedback-classifier.sh --context <context>
     → detects ".claude/constructs" patterns (score: 3)
     → calls construct-attribution.sh
       → reads .constructs-meta.json: observer pack installed
       → checks .claude/constructs/packs/observer/manifest.yaml: source_repo exists
       → confidence: 0.67 (path_match=1.0 + skill_name=0.6, normalized)
       → trust: org "0xHoneyJar" matches vendor pattern ✓
     → returns classification: "construct", repo: "0xHoneyJar/observer-pack"
3. feedback.md dedup check:
   → reads .run/feedback-ledger.json: no duplicate
   → 24h count for repo: 0 (under threshold)
4. feedback.md redaction preview:
   → feedback-redaction.sh --preview
   → strips absolute paths, env vars
   → shows: "Filing on 0xHoneyJar/observer-pack (observer v1.2.0)"
   → shows redacted preview
5. User confirms
6. feedback.md Phase 5:
   → gh issue create --repo 0xHoneyJar/observer-pack --title "[Loa Feedback] ..." --body "..."
7. feedback.md Phase 5.1:
   → append to .run/feedback-ledger.json
8. Success: "Filed: https://github.com/0xHoneyJar/observer-pack/issues/1"
```

### Degraded Path: No source_repo in manifest

```
1-2. Same as above, but manifest.yaml has no source_repo field
3. construct-attribution.sh returns:
   {"attributed": true, "construct": "artisan/observer", "source_repo": null, ...}
4. feedback-classifier.sh: source_repo is null → fall back to existing 4-repo routing
5. Log: "WARN: observer pack has no source_repo field. Falling back to default routing."
6. User sees standard 4-repo options (loa, loa-constructs, forge, project)
```

### Degraded Path: gh lacks write access

```
1-5. Same as happy path through user confirmation
6. gh issue create → exit code 1 (permission denied)
7. feedback.md catches error:
   "Cannot file on 0xHoneyJar/observer-pack — gh CLI lacks write access."
   Options: [Copy to clipboard] / [Route to loa instead] / [Cancel]
```

## 4. manifest.yaml Extension

Constructs that want to receive feedback declare `source_repo`:

```yaml
# .claude/constructs/packs/{pack}/manifest.yaml (or manifest.json)
name: observer
vendor: artisan
version: 1.2.0
source_repo: "0xHoneyJar/observer-pack"   # NEW OPTIONAL FIELD
# ... existing fields unchanged
```

**Reading logic** (in construct-attribution.sh):
```bash
# Check manifest.yaml first, then manifest.json
manifest_path="$pack_dir/manifest.yaml"
if [[ ! -f "$manifest_path" ]]; then
    manifest_path="$pack_dir/manifest.json"
fi

if [[ -f "$manifest_path" ]]; then
    if [[ "$manifest_path" == *.yaml ]]; then
        source_repo=$(yq -r '.source_repo // ""' "$manifest_path" 2>/dev/null)
    else
        source_repo=$(jq -r '.source_repo // ""' "$manifest_path" 2>/dev/null)
    fi
fi
```

## 5. Configuration Schema

```yaml
# .loa.config.yaml additions
feedback:
  routing:
    # Existing fields unchanged
    enabled: true
    auto_classify: true
    require_confirmation: true

    # NEW: construct routing section
    construct_routing:
      enabled: true               # Master toggle
      attribution_threshold: 0.33 # Min confidence for construct routing
      redaction:
        strip_absolute_paths: true
        strip_secrets: true
        strip_env_vars: true
        include_snippets: false    # Code blocks stripped for external repos
        include_file_refs: true    # File refs kept but paths redacted
        include_environment: false # Environment section stripped
      rate_limits:
        per_repo_daily: 5         # Warn after N issues to same repo in 24h
        per_repo_daily_hard: 20   # Block at N issues
        dedup_window_hours: 24    # Dedup fingerprint window
```

## 6. Testing Strategy

### Unit Tests

| Test | Script | What it validates |
|------|--------|-------------------|
| Attribution with path match | construct-attribution.sh | Returns correct construct + confidence for path-based detection |
| Attribution with no constructs | construct-attribution.sh | Returns `{"attributed": false}` when no constructs installed |
| Attribution with multiple matches | construct-attribution.sh | Picks highest confidence, reports disambiguation |
| Trust warning on org mismatch | construct-attribution.sh | Sets trust_warning when repo org != vendor |
| Redaction strips secrets | feedback-redaction.sh | AWS keys, GitHub tokens, JWTs removed |
| Redaction strips absolute paths | feedback-redaction.sh | `/home/user/...` → relative paths |
| Redaction preserves useful content | feedback-redaction.sh | Finding description, severity, construct info kept |
| Classifier backward compat | feedback-classifier.sh | Existing 4-category routing unchanged when no constructs |
| Classifier construct detection | feedback-classifier.sh | Returns `classification: "construct"` when construct paths present |
| Dedup blocks duplicate | feedback-ledger.json | Same fingerprint within window → blocked |
| Rate limit warns at threshold | feedback-ledger.json | 5th issue in 24h → warning |
| Rate limit blocks at hard limit | feedback-ledger.json | 20th issue in 7d → blocked |

### Integration Tests

| Test | What it validates |
|------|-------------------|
| End-to-end /feedback with mock construct | Full pipeline: classify → attribute → redact → confirm → file |
| Fallback when source_repo missing | Falls back to 4-repo routing gracefully |
| Fallback when gh lacks access | Offers clipboard, doesn't crash |

## 7. Security Considerations

| Threat | Control | Location |
|--------|---------|----------|
| Supply-chain: tampered manifest | Org-mismatch warning + user confirmation | construct-attribution.sh |
| Information exfiltration via feedback | Content redaction engine | feedback-redaction.sh |
| Spam/abuse of vendor repos | Dedup ledger + rate limits | feedback.md + feedback-ledger.json |
| Secret leakage in issue body | gitleaks-style pattern matching | feedback-redaction.sh |
| Path traversal in construct paths | Existing `validate_symlink_target` | constructs-install.sh (unchanged) |

## 8. File Changes Summary

| File | Action | Lines (est.) |
|------|--------|-------------|
| `.claude/scripts/construct-attribution.sh` | CREATE | ~200 |
| `.claude/scripts/feedback-redaction.sh` | CREATE | ~150 |
| `.claude/scripts/feedback-classifier.sh` | MODIFY | +40 |
| `.claude/commands/feedback.md` | MODIFY | +60 |
| `.loa.config.yaml.example` | MODIFY | +15 |
| `.claude/tests/hounfour/run-tests.sh` | MODIFY | +2 (add new scripts to syntax check) |

**Total estimated new/modified lines**: ~470
