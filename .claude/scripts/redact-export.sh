#!/usr/bin/env bash
# redact-export.sh - Fail-closed redaction pipeline for export content
# path-lib: exempt
#
# Three-tier detection (BLOCK/REDACT/FLAG) with allowlist sentinel protection,
# Shannon entropy analysis, and post-redaction safety verification.
#
# Shared by: trajectory-export.sh, memory-bootstrap.sh, /propose-learning
#
# Usage: redact-export.sh [OPTIONS] < input > output
#   Exit codes: 0 = clean, 1 = blocked (BLOCK finding), 2 = error
#   Stdin: text content to redact
#   Stdout: redacted content (only on exit 0)
#   Stderr: error/warning messages
#
# Options:
#   --strict          Fail-closed mode (default: true)
#   --no-strict       Permissive mode (BLOCK → REDACT)
#   --audit-file PATH Write JSON audit report to file
#   --allow-pattern REGEX  Override for false positives (logged)
#   --quiet           Suppress non-error output
#   -h, --help        Show help
#
set -uo pipefail

# === Constants ===
MAX_INPUT_SIZE=$((50 * 1024 * 1024))  # 50MB
MAX_LINE_LENGTH=10000
ENTROPY_THRESHOLD="4.5"
ENTROPY_MIN_LENGTH=20

# === Colors ===
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# === Logging ===
QUIET=false
warn() { echo -e "${YELLOW}[redact]${NC} WARNING: $*" >&2; }
err() { echo -e "${RED}[redact]${NC} ERROR: $*" >&2; }

# === Defaults ===
STRICT=true
AUDIT_FILE=""
ALLOW_PATTERNS=()

# === Argument Parsing ===
while [[ $# -gt 0 ]]; do
  case $1 in
    --strict)     STRICT=true; shift ;;
    --no-strict)  STRICT=false; shift ;;
    --audit-file)
      AUDIT_FILE="$2"
      shift 2 ;;
    --allow-pattern)
      ALLOW_PATTERNS+=("$2")
      shift 2 ;;
    --quiet)      QUIET=true; shift ;;
    -h|--help)
      echo "Usage: redact-export.sh [OPTIONS] < input > output"
      echo ""
      echo "Fail-closed redaction pipeline for export content."
      echo ""
      echo "Options:"
      echo "  --strict          Fail-closed mode (default)"
      echo "  --no-strict       Permissive mode (BLOCK → REDACT)"
      echo "  --audit-file PATH Write JSON audit report"
      echo "  --allow-pattern R Override specific patterns (logged)"
      echo "  --quiet           Suppress non-error output"
      echo ""
      echo "Exit codes: 0=clean, 1=blocked, 2=error"
      exit 0 ;;
    *) warn "Unknown option: $1"; shift ;;
  esac
done

# === Read Input ===
# Use temp file to preserve NUL bytes for binary detection
_INPUT_TMPFILE=$(mktemp) || { err "Failed to create temp file"; exit 2; }
_cleanup_input() { rm -f "$_INPUT_TMPFILE"; }
trap '_cleanup_input' EXIT

cat > "$_INPUT_TMPFILE"

if [[ ! -s "$_INPUT_TMPFILE" ]]; then
  err "Empty input"
  exit 2
fi

# === Input Validation ===

# Check for binary content (NUL bytes) — byte count comparison approach
# grep -Pq '\x00' doesn't reliably detect NUL bytes in files, so we compare
# original byte count with NUL-stripped byte count
_ORIG_BYTES=$(wc -c < "$_INPUT_TMPFILE")
_STRIPPED_BYTES=$(tr -d '\0' < "$_INPUT_TMPFILE" | wc -c)
if [[ "$_ORIG_BYTES" -ne "$_STRIPPED_BYTES" ]]; then
  err "Binary content detected (NUL bytes). Only UTF-8 text is accepted."
  exit 2
fi

# Check size
INPUT_SIZE=$(wc -c < "$_INPUT_TMPFILE")
if [[ "$INPUT_SIZE" -gt "$MAX_INPUT_SIZE" ]]; then
  err "Input exceeds 50MB limit (${INPUT_SIZE} bytes)"
  exit 2
fi

# Read into variable (safe now — no NUL bytes)
INPUT=$(cat "$_INPUT_TMPFILE")
rm -f "$_INPUT_TMPFILE"
trap '' EXIT  # Clear trap since file is cleaned up

# === Tracking ===
BLOCK_COUNT=0
REDACT_COUNT=0
FLAG_COUNT=0
BLOCK_RULES=()
REDACT_RULES=()
FLAG_RULES=()
OVERRIDE_LOG=()

# === Load External Allowlist ===
ALLOWLIST_PATTERNS=()
ALLOWLIST_FILE="${REDACT_ALLOWLIST_FILE:-}"
if [[ -n "$ALLOWLIST_FILE" && -f "$ALLOWLIST_FILE" ]]; then
  while IFS= read -r pattern || [[ -n "$pattern" ]]; do
    [[ -z "$pattern" || "$pattern" == \#* ]] && continue
    ALLOWLIST_PATTERNS+=("$pattern")
  done < "$ALLOWLIST_FILE"
fi

# === Sentinel Extraction ===
# Extract sentinel-protected regions and replace with placeholders
# Sentinels only protect REDACT/FLAG rules, NOT BLOCK rules
# Format: <!-- redact-allow:CATEGORY -->...<!-- /redact-allow -->
# No nesting allowed; malformed sentinels treated as plain text

declare -A SENTINEL_MAP
SENTINEL_COUNT=0
PROCESSED="$INPUT"

extract_sentinels() {
  local content="$1"
  local result="$content"

  # Match non-nested sentinels only (no sentinel markers inside)
  # Use a simple line-based approach for portability
  local temp_file
  temp_file=$(mktemp) || return
  printf '%s' "$content" > "$temp_file"

  # Extract well-formed sentinels using awk
  local extracted
  extracted=$(awk '
    BEGIN { in_sentinel = 0; category = ""; buffer = "" }
    /<!-- redact-allow:[A-Za-z0-9_-]+ -->/ {
      if (in_sentinel) {
        # Nested sentinel — treat outer as plain text, reset
        in_sentinel = 0
        buffer = ""
      }
      match($0, /<!-- redact-allow:([A-Za-z0-9_-]+) -->/, arr)
      if (RSTART > 0) {
        category = arr[1]
        in_sentinel = 1
        buffer = ""
        next
      }
    }
    /<!-- \/redact-allow -->/ {
      if (in_sentinel) {
        printf "SENTINEL:%s:%s\n", category, buffer
        in_sentinel = 0
        category = ""
        buffer = ""
        next
      }
    }
    in_sentinel { buffer = buffer (buffer == "" ? "" : "\n") $0 }
  ' "$temp_file" 2>/dev/null)

  rm -f "$temp_file"

  # Replace sentinel regions with placeholders in content
  if [[ -n "$extracted" ]]; then
    while IFS= read -r line; do
      if [[ "$line" == SENTINEL:* ]]; then
        local cat="${line#SENTINEL:}"
        cat="${cat%%:*}"
        local sentinel_content="${line#SENTINEL:*:}"
        local placeholder="__SENTINEL_${SENTINEL_COUNT}__"
        SENTINEL_MAP["$placeholder"]="$sentinel_content"
        SENTINEL_COUNT=$((SENTINEL_COUNT + 1))
        # Remove the sentinel markers and content from result
        result=$(printf '%s' "$result" | sed "s|<!-- redact-allow:${cat} -->${sentinel_content}<!-- /redact-allow -->|${placeholder}|g" 2>/dev/null || printf '%s' "$result")
      fi
    done <<< "$extracted"
  fi

  printf '%s' "$result"
}

# Extract sentinels before processing
PROCESSED=$(extract_sentinels "$INPUT")

# === Truncate long lines ===
PROCESSED=$(printf '%s' "$PROCESSED" | awk -v max="$MAX_LINE_LENGTH" '{
  if (length($0) > max) print substr($0, 1, max)
  else print
}')

# === Check if content matches allow patterns ===
is_allowed() {
  local content="$1"
  # Check --allow-pattern arguments
  for pat in "${ALLOW_PATTERNS[@]}"; do
    if printf '%s' "$content" | grep -qE "$pat" 2>/dev/null; then
      OVERRIDE_LOG+=("$pat")
      return 0
    fi
  done
  # Check external allowlist
  for pat in "${ALLOWLIST_PATTERNS[@]}"; do
    if printf '%s' "$content" | grep -qE "$pat" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

# === Built-in Safe Patterns (allowlisted) ===
# sha256 hashes, diagram URLs, schema_version
is_safe_pattern() {
  local match="$1"
  # SHA256 hashes
  [[ "$match" =~ ^[a-f0-9]{64}$ ]] && return 0
  # sha256: prefixed hashes
  [[ "$match" =~ ^sha256:[a-f0-9]{64}$ ]] && return 0
  # Mermaid diagram URLs
  [[ "$match" =~ ^https://mermaid\.ink/img/ ]] && return 0
  # UUIDs
  [[ "$match" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] && return 0
  return 1
}

# =============================================================================
# BLOCK Rules — Halt export on match (exit 1 in strict mode)
# =============================================================================

apply_block_rules() {
  local content="$1"
  local blocked=false

  # AWS Access Keys: AKIA followed by 16 uppercase alphanumeric
  if printf '%s' "$content" | grep -qP 'AKIA[0-9A-Z]{16}' 2>/dev/null; then
    if ! is_allowed "AKIA"; then
      BLOCK_COUNT=$((BLOCK_COUNT + 1))
      BLOCK_RULES+=("aws_key")
      blocked=true
    fi
  fi

  # GitHub PATs: ghp_, gho_, ghs_, ghr_ followed by 36+ chars
  if printf '%s' "$content" | grep -qP 'gh[psor]_[A-Za-z0-9_]{36,}' 2>/dev/null; then
    if ! is_allowed "ghp_"; then
      BLOCK_COUNT=$((BLOCK_COUNT + 1))
      BLOCK_RULES+=("github_pat")
      blocked=true
    fi
  fi

  # JWT tokens: eyJ...eyJ pattern
  if printf '%s' "$content" | grep -qP 'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+' 2>/dev/null; then
    if ! is_allowed "eyJ"; then
      BLOCK_COUNT=$((BLOCK_COUNT + 1))
      BLOCK_RULES+=("jwt")
      blocked=true
    fi
  fi

  # Bearer tokens
  if printf '%s' "$content" | grep -qiP 'Bearer\s+[A-Za-z0-9_-]{20,}' 2>/dev/null; then
    if ! is_allowed "Bearer"; then
      BLOCK_COUNT=$((BLOCK_COUNT + 1))
      BLOCK_RULES+=("bearer_token")
      blocked=true
    fi
  fi

  # Private keys
  if printf '%s' "$content" | grep -qP '-----BEGIN\s+(RSA\s+)?PRIVATE\s+KEY-----' 2>/dev/null; then
    if ! is_allowed "PRIVATE KEY"; then
      BLOCK_COUNT=$((BLOCK_COUNT + 1))
      BLOCK_RULES+=("private_key")
      blocked=true
    fi
  fi

  # OpenAI/Anthropic API keys: sk- followed by 40+ chars
  if printf '%s' "$content" | grep -qP 'sk-[A-Za-z0-9]{40,}' 2>/dev/null; then
    if ! is_allowed "sk-"; then
      BLOCK_COUNT=$((BLOCK_COUNT + 1))
      BLOCK_RULES+=("api_key_sk")
      blocked=true
    fi
  fi

  # Slack tokens: xoxb-, xoxp-, xoxs-
  if printf '%s' "$content" | grep -qP 'xox[bps]-[A-Za-z0-9-]+' 2>/dev/null; then
    if ! is_allowed "xox"; then
      BLOCK_COUNT=$((BLOCK_COUNT + 1))
      BLOCK_RULES+=("slack_token")
      blocked=true
    fi
  fi

  # Slack webhooks
  if printf '%s' "$content" | grep -qP 'hooks\.slack\.com/services/T[A-Z0-9]+/B[A-Z0-9]+/' 2>/dev/null; then
    if ! is_allowed "slack_webhook"; then
      BLOCK_COUNT=$((BLOCK_COUNT + 1))
      BLOCK_RULES+=("slack_webhook")
      blocked=true
    fi
  fi

  # Stripe keys: sk_live_, pk_live_, rk_live_
  if printf '%s' "$content" | grep -qP '[srp]k_live_[A-Za-z0-9]{20,}' 2>/dev/null; then
    if ! is_allowed "sk_live_"; then
      BLOCK_COUNT=$((BLOCK_COUNT + 1))
      BLOCK_RULES+=("stripe_key")
      blocked=true
    fi
  fi

  # Twilio SIDs: SK followed by 32 hex chars
  if printf '%s' "$content" | grep -qP 'SK[a-f0-9]{32}' 2>/dev/null; then
    if ! is_allowed "twilio"; then
      BLOCK_COUNT=$((BLOCK_COUNT + 1))
      BLOCK_RULES+=("twilio_sid")
      blocked=true
    fi
  fi

  # SendGrid keys: SG. followed by specific pattern
  if printf '%s' "$content" | grep -qP 'SG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}' 2>/dev/null; then
    if ! is_allowed "sendgrid"; then
      BLOCK_COUNT=$((BLOCK_COUNT + 1))
      BLOCK_RULES+=("sendgrid_key")
      blocked=true
    fi
  fi

  if [[ "$blocked" == "true" ]]; then
    return 1
  fi
  return 0
}

# =============================================================================
# REDACT Rules — Replace matched content with placeholders
# =============================================================================

apply_redact_rules() {
  # Operates on PROCESSED global variable directly (avoids subshell)
  local before="$PROCESSED"

  # Absolute paths: /home/*, /Users/*, /root/*
  PROCESSED=$(printf '%s' "$PROCESSED" | sed -E 's|/home/[^[:space:]/]+/[^[:space:]]*|<redacted-path>|g' 2>/dev/null || printf '%s' "$PROCESSED")
  PROCESSED=$(printf '%s' "$PROCESSED" | sed -E 's|/Users/[^[:space:]/]+/[^[:space:]]*|<redacted-path>|g' 2>/dev/null || printf '%s' "$PROCESSED")
  PROCESSED=$(printf '%s' "$PROCESSED" | sed -E 's|/root/[^[:space:]]*|<redacted-path>|g' 2>/dev/null || printf '%s' "$PROCESSED")

  # Windows absolute paths: C:\, D:\, etc.
  PROCESSED=$(printf '%s' "$PROCESSED" | sed -E 's|[A-Z]:\\[^[:space:]]*|<redacted-path>|g' 2>/dev/null || printf '%s' "$PROCESSED")

  # Tilde paths: ~/
  PROCESSED=$(printf '%s' "$PROCESSED" | sed -E 's|~/[^[:space:]]+|<redacted-path>|g' 2>/dev/null || printf '%s' "$PROCESSED")

  # Email addresses
  PROCESSED=$(printf '%s' "$PROCESSED" | sed -E 's|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|<redacted-email>|g' 2>/dev/null || printf '%s' "$PROCESSED")

  # .env assignments: KEY=value (uppercase key, non-comment lines)
  PROCESSED=$(printf '%s' "$PROCESSED" | sed -E 's|^([A-Z][A-Z0-9_]{2,})=(.+)$|\1=<redacted-env>|gm' 2>/dev/null || printf '%s' "$PROCESSED")

  # IPv4 addresses (but not version numbers like 1.2.3)
  PROCESSED=$(printf '%s' "$PROCESSED" | sed -E 's|([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})|<redacted-ip>|g' 2>/dev/null || printf '%s' "$PROCESSED")

  # Track redactions
  if [[ "$PROCESSED" != "$before" ]]; then
    REDACT_COUNT=$((REDACT_COUNT + 1))
    REDACT_RULES+=("path_email_env_ip")
  fi
}

# =============================================================================
# FLAG Rules — Log to audit, pass through content
# =============================================================================

apply_flag_rules() {
  # Operates on PROCESSED global variable directly (avoids subshell)

  # Token/password params in URLs or configs
  if printf '%s' "$PROCESSED" | grep -qiP '(token|password|secret|api_key|apikey)[[:space:]]*[=:]' 2>/dev/null; then
    FLAG_COUNT=$((FLAG_COUNT + 1))
    FLAG_RULES+=("credential_param")
  fi

  # Shannon entropy check on high-entropy strings
  local entropy_output
  entropy_output=$(printf '%s' "$PROCESSED" | awk -v min_len="$ENTROPY_MIN_LENGTH" -v threshold="$ENTROPY_THRESHOLD" '
    function entropy(s,    i, n, freq, c, h, p) {
      n = length(s)
      if (n == 0) return 0
      delete freq
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        freq[c]++
      }
      h = 0
      for (c in freq) {
        p = freq[c] / n
        if (p > 0) h -= p * (log(p) / log(2))
      }
      return h
    }

    function is_safe(token) {
      # SHA256 hashes (64 hex chars)
      if (token ~ /^[a-f0-9]{64}$/) return 1
      # sha256: prefixed
      if (token ~ /^sha256:[a-f0-9]+$/) return 1
      # UUIDs
      if (token ~ /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/) return 1
      # Already redacted
      if (token ~ /^<redacted/) return 1
      # URLs
      if (token ~ /^https?:\/\//) return 1
      # Mermaid diagram URLs
      if (token ~ /mermaid\.ink/) return 1
      # Sentinel placeholders
      if (token ~ /^__SENTINEL_/) return 1
      return 0
    }

    {
      split($0, words, /[[:space:]]+/)
      for (i in words) {
        w = words[i]
        if (length(w) >= min_len && !is_safe(w)) {
          h = entropy(w)
          if (h + 0 >= threshold + 0) {
            print w
          }
        }
      }
    }
  ' 2>/dev/null)

  if [[ -n "$entropy_output" ]]; then
    FLAG_COUNT=$((FLAG_COUNT + 1))
    FLAG_RULES+=("high_entropy")
  fi
}

# =============================================================================
# Post-Redaction Safety Check
# =============================================================================

post_redaction_check() {
  local content="$1"

  # Scan for known secret prefixes that should have been caught
  local missed=false
  local missed_patterns=()

  # Check each prefix — skip if explicitly allowed via --allow-pattern
  _check_prefix() {
    local prefix="$1"
    local regex="$2"
    if printf '%s' "$content" | grep -qP "$regex" 2>/dev/null; then
      # Skip if this prefix was explicitly allowed
      if is_allowed "$prefix" 2>/dev/null; then
        return 0
      fi
      missed=true
      missed_patterns+=("$prefix")
    fi
  }

  _check_prefix "ghp_" 'ghp_[A-Za-z0-9]'
  _check_prefix "gho_" 'gho_[A-Za-z0-9]'
  _check_prefix "ghs_" 'ghs_[A-Za-z0-9]'
  _check_prefix "ghr_" 'ghr_[A-Za-z0-9]'
  _check_prefix "AKIA" 'AKIA[0-9A-Z]'
  _check_prefix "eyJ" 'eyJ[A-Za-z0-9]'
  _check_prefix "xoxb-" 'xoxb-[A-Za-z0-9]'
  _check_prefix "sk_live_" 'sk_live_[A-Za-z0-9]'

  if [[ "$missed" == "true" ]]; then
    err "Post-redaction check FAILED: missed patterns: ${missed_patterns[*]}"
    return 1
  fi
  return 0
}

# =============================================================================
# Audit Report
# =============================================================================

write_audit() {
  local audit_path="$1"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local block_rules_json="[]"
  if [[ ${#BLOCK_RULES[@]} -gt 0 ]]; then
    block_rules_json=$(printf '%s\n' "${BLOCK_RULES[@]}" | jq -R . | jq -s . 2>/dev/null || echo "[]")
  fi

  local redact_rules_json="[]"
  if [[ ${#REDACT_RULES[@]} -gt 0 ]]; then
    redact_rules_json=$(printf '%s\n' "${REDACT_RULES[@]}" | jq -R . | jq -s . 2>/dev/null || echo "[]")
  fi

  local flag_rules_json="[]"
  if [[ ${#FLAG_RULES[@]} -gt 0 ]]; then
    flag_rules_json=$(printf '%s\n' "${FLAG_RULES[@]}" | jq -R . | jq -s . 2>/dev/null || echo "[]")
  fi

  local override_json="[]"
  if [[ ${#OVERRIDE_LOG[@]} -gt 0 ]]; then
    override_json=$(printf '%s\n' "${OVERRIDE_LOG[@]}" | jq -R . | jq -s . 2>/dev/null || echo "[]")
  fi

  local tmp="${audit_path}.tmp.$$"
  cat > "$tmp" <<AUDIT_EOF
{
  "timestamp": "$timestamp",
  "strict": $STRICT,
  "input_size": $INPUT_SIZE,
  "findings": {
    "block": $BLOCK_COUNT,
    "redact": $REDACT_COUNT,
    "flag": $FLAG_COUNT
  },
  "block_rules": $block_rules_json,
  "redact_rules": $redact_rules_json,
  "flag_rules": $flag_rules_json,
  "overrides": $override_json,
  "post_check_passed": true
}
AUDIT_EOF
  mv "$tmp" "$audit_path"
}

# =============================================================================
# Main Pipeline
# =============================================================================

main() {
  # Layer 1: BLOCK rules (on original content — sentinels do NOT protect against BLOCK)
  if ! apply_block_rules "$INPUT"; then
    if [[ "$STRICT" == "true" ]]; then
      err "BLOCKED: Content contains secrets (rules: ${BLOCK_RULES[*]})"
      if [[ -n "$AUDIT_FILE" ]]; then
        write_audit "$AUDIT_FILE"
      fi
      # No stdout output on block
      exit 1
    else
      # Permissive mode: log but continue
      warn "BLOCK-level findings in permissive mode (rules: ${BLOCK_RULES[*]})"
    fi
  fi

  # Layer 2: REDACT rules (on sentinel-extracted content — sentinels protect REDACT)
  apply_redact_rules

  # Layer 3: FLAG rules (on processed content — sentinels protect FLAG)
  apply_flag_rules

  # Layer 3.5: Restore sentinel content
  for placeholder in "${!SENTINEL_MAP[@]}"; do
    local sentinel_content="${SENTINEL_MAP[$placeholder]}"
    PROCESSED=$(printf '%s' "$PROCESSED" | sed "s|${placeholder}|${sentinel_content}|g" 2>/dev/null || printf '%s' "$PROCESSED")
  done

  # Layer 4: Fail-closed gate (already handled above for BLOCK)
  # Layer 5: Post-redaction safety check
  if ! post_redaction_check "$PROCESSED"; then
    if [[ -n "$AUDIT_FILE" ]]; then
      # Update audit to reflect post-check failure
      write_audit "$AUDIT_FILE"
      # Fix the post_check field
      local tmp="${AUDIT_FILE}.tmp.$$"
      jq '.post_check_passed = false' "$AUDIT_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$AUDIT_FILE"
    fi
    exit 1
  fi

  # Write audit report if requested
  if [[ -n "$AUDIT_FILE" ]]; then
    write_audit "$AUDIT_FILE"
  fi

  # Output redacted content
  printf '%s\n' "$PROCESSED"
  exit 0
}

main
