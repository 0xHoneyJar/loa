#!/usr/bin/env bash
# =============================================================================
# PreToolUse:Bash Safety Hook — Block Destructive Commands (v1.38.0)
# =============================================================================
# Blocks dangerous patterns and suggests safer alternatives.
# Exit 0 = allow, Exit 2 = block (stderr message fed back to agent).
#
# Cycle-111 (sprint-164, 2026-05-16) — ports Anthropic DCG public pattern
# set inline. Source: github.com/anthropics/destructive-command-guard
# Pattern port reference SHA: HEAD as of 2026-05-16 (no specific commit
# pin available — DCG ships rule packs, not single-file source).
# REVIEW-BY: 2026-08-16 — re-sync against upstream DCG every quarter.
#
# IMPORTANT: No set -euo pipefail — this hook must never fail closed.
# A grep or jq failure must result in exit 0 (allow), not an error.
#
# WHY fail-open (not fail-closed): A safety hook that crashes or encounters
# a parse error must NOT block the agent from operating. The alternative —
# fail-closed — would make jq/grep bugs into denial-of-service attacks
# against the agent. Fail-open with logging is the standard pattern for
# inline security hooks (cf. ModSecurity DetectionOnly mode).
# (Source: bridge-20260213-c011he iter-1 HIGH-1 fix)
#
# WHY GNU/BSD ERE (NOT strict POSIX): grep -P (PCRE) is a GNU extension not
# available on macOS/BSD or minimal containers. grep -E (Extended Regex)
# with `\s`, `\S`, `\b` extensions works on both GNU grep (Linux) and BSD
# grep (macOS Sonoma+). Strict-POSIX ERE (busybox without -E extensions)
# is NOT in scope per cycle-111 SDD §5.0 honest-scope decision.
# (Source: bridge-20260213-c011he iter-1 HIGH-1 fix; cycle-111 SDD §5.0)
#
# WHY single script for all patterns: NFR-5 single-file invariant. Multiple
# hooks would each read stdin, parse JSON, and run regex — multiplying
# latency per command. A single emit_block helper with sequential patterns
# is simpler and faster. (cycle-111 SDD §5/§6.)
#
# Defense-in-depth posture (cycle-111 SDD §11): this hook is a fence
# against routine destructive-command mistakes by autonomous agents, NOT
# a hardened security boundary against intentional bypass. Known accepted
# bypass classes: newline statement separators, subshell wrapping
# (`bash -c '...'`, `$(...)`), eval/base64 decode, SQL comments containing
# WHERE, jq absent from PATH. See SDD §11 for full table.
#
# Registered in settings.hooks.json as PreToolUse matcher: "Bash"
# Part of Loa Harness Engineering (cycle-011, issue #297)
# Source: Trail of Bits claude-code-config safety patterns
# =============================================================================

# -----------------------------------------------------------------------------
# jq presence probe (SDD §6.5 — SKP-008 mitigation, not full fix).
# If jq is absent, the input parse on line ~120 returns empty → existing
# fail-open guard exits 0. v1.38.0 adds a one-shot stderr WARNING so the
# operator / agent sees the safety guard is disabled this session.
# Tracked as cycle-112 candidate (filesystem-marker variant for cross-
# invocation persistence; env-var doesn't propagate across hook subprocess
# invocations per Flatline SKP-002 round-3 finding).
# -----------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  if [[ -z "${LOA_BLOCK_DESTRUCTIVE_JQ_MISSING_WARNED:-}" ]]; then
    echo "WARNING: block-destructive-bash: jq not in PATH — destructive-command pattern matching is DISABLED for this session. Install jq to restore safety guards." >&2
    export LOA_BLOCK_DESTRUCTIVE_JQ_MISSING_WARNED=1
  fi
  exit 0  # Existing fail-open behavior preserved.
fi

# Read tool input from stdin (JSON with tool_input.command).
# Path A jq call (SDD §6.4): failure here → empty $command → allow.
input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || true

# If we can't parse the command, allow (don't block on parse errors).
if [[ -z "$command" ]]; then
  exit 0
fi

# =============================================================================
# emit_block — SDD §6.1 helper
# =============================================================================
# Args: pattern_id, matched_substring, message
# Emits BLOCKED stderr for the agent, appends a sanitized audit row to
# .run/audit.jsonl, then exit 2.
#
# Path B jq call (SDD §6.4): the audit-emit jq runs inside a `|| true`-
# wrapped subshell. Failures here drop the audit row but the exit 2
# (block decision) still fires. Path A and Path B failure modes are
# distinct and CANNOT collapse: Path B only runs after Path A succeeded
# (otherwise $command is empty and the hook already exited 0).
emit_block() {
  local pattern_id="$1"
  local matched="$2"
  local message="$3"

  # Stderr to the agent — pattern_id + message gives enough to pick an alternative.
  echo "BLOCKED [$pattern_id]: $message" >&2

  # Audit row emission — best-effort, never affects block decision.
  {
    local redactor="${LOA_REPO_ROOT:-.}/.claude/scripts/lib/log-redactor.sh"

    local sanitized_cmd
    sanitized_cmd=$(printf '%s' "$command" | "$redactor" 2>/dev/null) || sanitized_cmd="[REDACTOR-FAILED]"

    # SDD §6.1 v1.1 SKP-008 closure: also redact the matched substring.
    local sanitized_match
    sanitized_match=$(printf '%s' "$matched" | "$redactor" 2>/dev/null) || sanitized_match="[REDACTOR-FAILED]"

    # Truncate AFTER redaction (so partial AKIA prefixes can't slip through).
    if [[ ${#sanitized_cmd} -gt 2048 ]]; then
      sanitized_cmd="${sanitized_cmd:0:2048}[...TRUNCATED]"
    fi
    if [[ ${#sanitized_match} -gt 256 ]]; then
      sanitized_match="${sanitized_match:0:256}[...TRUNCATED]"
    fi

    mkdir -p "${LOA_REPO_ROOT:-.}/.run" 2>/dev/null || true

    jq -cn \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg cmd "$sanitized_cmd" \
      --arg cwd "$(pwd)" \
      --arg model "${LOA_CURRENT_MODEL:-}" \
      --arg provider "${LOA_CURRENT_PROVIDER:-}" \
      --arg trace_id "${LOA_TRACE_ID:-}" \
      --arg team_id "${LOA_TEAM_ID:-}" \
      --arg team_member "${LOA_TEAM_MEMBER:-}" \
      --arg pattern_id "$pattern_id" \
      --arg matched "$sanitized_match" \
      '{ts: $ts, tool: "Bash", command: $cmd, exit_code: 2, cwd: $cwd, model: $model, provider: $provider, trace_id: $trace_id, team_id: $team_id, team_member: $team_member, hook: "block-destructive-bash", action: "block", pattern_id: $pattern_id, matched: $matched}' \
      >> "${LOA_REPO_ROOT:-.}/.run/audit.jsonl" 2>/dev/null || true
  } 2>/dev/null || true

  exit 2
}

# Backward-compat helper: existing call sites used check_and_block. Keep it
# as a thin wrapper that funnels through emit_block with pattern_id="LEGACY".
# All new direct callers should use emit_block with a real pattern_id.
check_and_block() {
  local pattern="$1"
  local message="$2"
  if echo "$command" | grep -qE "$pattern" 2>/dev/null; then
    local matched
    matched=$(echo "$command" | grep -oE "$pattern" | head -1)
    emit_block "LEGACY" "$matched" "$message"
  fi
}

# =============================================================================
# Pattern dispatch — SDD §6.2 order: high-frequency-first / FR-2 last.
# =============================================================================

# -----------------------------------------------------------------------------
# P2 / P2b — git push --force / git push -f  (existing; pattern_id back-fill)
# -----------------------------------------------------------------------------
if echo "$command" | grep -qE '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+push[[:space:]]+.*--force($|[^-])' 2>/dev/null; then
  matched=$(echo "$command" | grep -oE 'git[[:space:]]+push[[:space:]]+.*--force[^-]?' | head -1)
  emit_block "P2" "$matched" "git push --force detected. Use --force-with-lease for safer force push, or push to a feature branch."
fi
if echo "$command" | grep -qE '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+push[[:space:]]+.*-f($|[[:space:]])' 2>/dev/null; then
  matched=$(echo "$command" | grep -oE 'git[[:space:]]+push[[:space:]]+.*-f' | head -1)
  emit_block "P2b" "$matched" "git push -f detected. Use --force-with-lease for safer force push, or push to a feature branch."
fi

# -----------------------------------------------------------------------------
# P3 — git reset --hard  (existing; pattern_id back-fill)
# -----------------------------------------------------------------------------
if echo "$command" | grep -qE '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+reset[[:space:]]+--hard' 2>/dev/null; then
  matched=$(echo "$command" | grep -oE 'git[[:space:]]+reset[[:space:]]+--hard[^[:space:]]*' | head -1)
  emit_block "P3" "$matched" "git reset --hard discards uncommitted work. Use 'git stash' to save changes, or 'git reset --soft' to keep them staged."
fi

# -----------------------------------------------------------------------------
# P4 — git clean -f without -n dry-run  (existing; pattern_id back-fill)
# -----------------------------------------------------------------------------
has_clean_f=false
has_clean_n=false
if echo "$command" | grep -qE '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*f' 2>/dev/null; then
  has_clean_f=true
fi
if echo "$command" | grep -qE '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*n' 2>/dev/null; then
  has_clean_n=true
fi
if [[ "$has_clean_f" == "true" && "$has_clean_n" == "false" ]]; then
  matched=$(echo "$command" | grep -oE 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]+' | head -1)
  emit_block "P4" "$matched" "git clean -f without dry-run. Run 'git clean -nd' first to preview what would be deleted."
fi

# -----------------------------------------------------------------------------
# P5 — git branch -D / force-delete  (FR-1.1)
# Covers grouped -D, --delete --force / --force --delete, split -d -f / -f -d.
# -----------------------------------------------------------------------------
if echo "$command" | grep -qE '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+branch[[:space:]]+(-[a-zA-Z]*D[a-zA-Z]*|--delete[[:space:]]+--force|--force[[:space:]]+--delete|-d[[:space:]]+-f|-f[[:space:]]+-d|--delete\b.*--force|--force\b.*--delete)' 2>/dev/null; then
  matched=$(echo "$command" | grep -oE 'git[[:space:]]+branch[[:space:]]+[^[:space:]&|;]+([[:space:]]+[^[:space:]&|;]+)?' | head -1)
  emit_block "FR-1.1" "$matched" "git branch -D loses unmerged work. Use 'git branch -d' (lowercase) — it refuses to drop branches with unmerged commits."
fi

# -----------------------------------------------------------------------------
# P6 — git stash drop / git stash clear  (FR-1.2)
# Note: git stash pop is NOT included (recoverable from reflog per SDD §5.3).
# -----------------------------------------------------------------------------
if echo "$command" | grep -qE '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+stash[[:space:]]+(drop|clear)\b' 2>/dev/null; then
  matched=$(echo "$command" | grep -oE 'git[[:space:]]+stash[[:space:]]+(drop|clear)([[:space:]]+[^[:space:]&|;]+)?' | head -1)
  emit_block "FR-1.2" "$matched" "git stash {drop,clear} permanently destroys stashed work. Run 'git stash list' first; consider 'git stash show' / 'git stash apply' before dropping."
fi

# -----------------------------------------------------------------------------
# P7 — git checkout -- <path>  (FR-1.3) — legacy form, overwrites uncommitted
# Refined ERE per SDD §5.4 v1.3: path must NOT start with `-` (so --quiet
# and similar flag-shaped tokens don't trigger).
# -----------------------------------------------------------------------------
if echo "$command" | grep -qE '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+checkout[[:space:]]+--[[:space:]]+[^-][^[:space:]]*' 2>/dev/null; then
  matched=$(echo "$command" | grep -oE 'git[[:space:]]+checkout[[:space:]]+--[[:space:]]+[^[:space:]&|;]+' | head -1)
  emit_block "FR-1.3" "$matched" "git checkout -- <file> overwrites uncommitted changes irreversibly. Use 'git stash push <file>' to save first, or 'git restore --source=HEAD <file>' (explicit source)."
fi

# -----------------------------------------------------------------------------
# P8 — DROP DATABASE / DROP TABLE / DROP SCHEMA  (FR-1.4)
# Case-insensitive via -iE. Accepted false-positive: `cat | grep DROP TABLE`
# (read-only inspection of schema files). Documented as known limitation.
# -----------------------------------------------------------------------------
if echo "$command" | grep -qiE '\b(DROP[[:space:]]+(DATABASE|TABLE|SCHEMA))\b' 2>/dev/null; then
  matched=$(echo "$command" | grep -oiE '\b(DROP[[:space:]]+(DATABASE|TABLE|SCHEMA))[[:space:]]+[^;]*' | head -1)
  emit_block "FR-1.4" "$matched" "DROP {DATABASE,TABLE,SCHEMA} is irreversible. If this is a migration, run via your migration tool with explicit confirmation; otherwise temporarily disable the hook for the next command only."
fi

# -----------------------------------------------------------------------------
# P9 — TRUNCATE TABLE  (FR-1.5)
# Case-insensitive. SDD §5.6 v1.3: quoted-ident coverage for Postgres
# ("users") + MySQL (`users`) + bare unquoted.
# -----------------------------------------------------------------------------
if echo "$command" | grep -qiE '\bTRUNCATE[[:space:]]+(TABLE[[:space:]]+)?("[^"]+"|`[^`]+`|[a-zA-Z_][a-zA-Z0-9_]*)' 2>/dev/null; then
  matched=$(echo "$command" | grep -oiE '\bTRUNCATE[[:space:]]+(TABLE[[:space:]]+)?("[^"]+"|`[^`]+`|[a-zA-Z_][a-zA-Z0-9_]*)' | head -1)
  emit_block "FR-1.5" "$matched" "TRUNCATE wipes the table. Use 'DELETE FROM <table> WHERE ...' for scoped row removal, or run in a transaction with explicit operator approval."
fi

# -----------------------------------------------------------------------------
# P10 — DELETE FROM <table> without WHERE  (FR-1.6)
# Two-pass per SDD §5.7 v1.3: iterate ALL DELETE FROM segments (multi-
# statement bypass closure). For each segment, fail if no WHERE present.
# Quoted-ident extended via the ("[^"]+"|`[^`]+`|...) alternation.
# -----------------------------------------------------------------------------
delete_stmts=$(echo "$command" | grep -oiE '\bDELETE[[:space:]]+FROM[[:space:]]+("[^"]+"|`[^`]+`|[a-zA-Z_][a-zA-Z0-9_]*)[^;]*' 2>/dev/null)
if [[ -n "$delete_stmts" ]]; then
  while IFS= read -r delete_stmt; do
    [[ -z "$delete_stmt" ]] && continue
    if ! echo "$delete_stmt" | grep -qiE '\bWHERE\b' 2>/dev/null; then
      emit_block "FR-1.6" "$delete_stmt" "DELETE FROM without WHERE removes all rows. Add a WHERE clause."
    fi
  done <<<"$delete_stmts"
fi

# -----------------------------------------------------------------------------
# P11 — kubectl delete namespace  (FR-1.7)
# SDD §5.8 v1.3: global-flag placement covered via the
# ([[:space:]]+(-X[[:space:]]+|--X)*) optional-flag-block between kubectl
# and delete. Catches `kubectl --kubeconfig=foo delete ns prod`.
# -----------------------------------------------------------------------------
if echo "$command" | grep -qE '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?kubectl([[:space:]]+(-[a-zA-Z]+([[:space:]]+|=)[^[:space:]]+|--[a-zA-Z][a-zA-Z0-9-]*(=[^[:space:]]+|[[:space:]]+[^[:space:]-]+)?))*[[:space:]]+delete[[:space:]]+(ns|namespace|namespaces)[[:space:]]+[a-zA-Z0-9_-]+' 2>/dev/null; then
  matched=$(echo "$command" | grep -oE 'kubectl[^;&|]*delete[[:space:]]+(ns|namespace|namespaces)[[:space:]]+[a-zA-Z0-9_-]+' | head -1)
  emit_block "FR-1.7" "$matched" "kubectl delete namespace wipes the entire namespace and everything inside it. Use 'kubectl delete -n <ns> -l <selector>' for scoped deletion, or temporarily disable the hook."
fi

# -----------------------------------------------------------------------------
# P12 — kubectl delete --all / -A  (FR-1.8)
# SDD §5.9 v1.3: `[^;&|]*` cross-statement bound (closes SKP-003 unbounded
# `.*`) + global-flag placement coverage. Verb-or-resource MUST appear in
# the same shell statement as the --all/-A token.
# -----------------------------------------------------------------------------
if echo "$command" | grep -qE '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?kubectl([[:space:]]+(-[a-zA-Z]+([[:space:]]+|=)[^[:space:]]+|--[a-zA-Z][a-zA-Z0-9-]*(=[^[:space:]]+|[[:space:]]+[^[:space:]-]+)?))*[[:space:]]+delete[[:space:]]+[^[:space:]]+[^;&|]*([[:space:]]--all\b|[[:space:]]-A\b)' 2>/dev/null; then
  matched=$(echo "$command" | grep -oE 'kubectl[^;&|]*delete[^;&|]*(--all|-A)' | head -1)
  emit_block "FR-1.8" "$matched" "kubectl delete --all / -A removes all resources in scope. Use label selectors instead: 'kubectl delete <type> -l app=<X>'."
fi

# -----------------------------------------------------------------------------
# FR-SZ — State-Zone executable/lifecycle write guard (sprint-bug-213 / #1044)
# -----------------------------------------------------------------------------
# Blocks DIRECT inline agent writes to the executable / lifecycle-controlled
# subset of the State Zone, which the shipped Bash allow-list (cp/tee/cat/echo/
# python3/bash/sh/ln/dd/tar/sed/...) otherwise permits with no prompt:
#   - .run/cron.d           deferred-execution cron scripts (dir + descendants)
#   - .run/...*.sh          sourced for model routing (incl. merged-model-aliases.sh)
#   - grimoires/loa/skills  skill-approval lifecycle (dir + descendants)
# Companion tool-layer half: the Write/Edit deny rules in .claude/settings.json
# (deny > allow). A Write-only deny without this Bash guard is theater (#1044).
#
# SCOPE (validated): the PreToolUse:Bash hook sees only the agent's OUTER command
# string. A generator invoked as `python3 .../model-overlay-hook.py` or `bash X.sh`
# that writes these paths INTERNALLY is invisible here (the redirect lives inside an
# already-approved subprocess) — so this guard blocks only DIRECT inline writes and
# leaves the legitimate generators frictionless (recon: zero inline callers).
#
# Coverage (sprint-bug-213 iter-2, cross-model dissent CR-1..CR-5): directory
# destinations with or without a trailing slash; option-form destinations
# (-t/--target-directory for the copy family, -C/--directory for tar, -d for unzip);
# tee long-options and non-first operands; grouped/long in-place editor flags
# (-Ei, --in-place); and a trailing shell comment as a statement terminator.
#
# Accepted bypass classes (defense-in-depth fence, NOT a hardened boundary; cf. the
# header section-11 list): post-cd relative writes, variable-indirected targets,
# obfuscated interpreter writes (base64/concat path in -c), a pipe-delimited sed
# in-place edit (the statement-bound stops at the first pipe), git checkout of a
# tracked path, non-allow-listed writers (truncate/sponge/ex/ed already prompt),
# and a trailing comment that merely mentions a protected path. Sanctioned override
# for the skill-audit approve move + operator use: LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1.
# -----------------------------------------------------------------------------
# Path fragments (ERE; substring match also covers absolute / $PWD-prefixed forms).
_sz_pc="[^[:space:]'\";&|#]"                              # one path character
_sz_sh="\\.run/${_sz_pc}*\\.sh"                          # a .sh file anywhere under .run/
_sz_root="(\\.run/cron\\.d|grimoires/loa/skills)"        # protected directory roots
_sz_tgt="(${_sz_sh}|${_sz_root}(/${_sz_pc}*)?)"          # a protected target (file OR dir[/desc])
_sz_file="(${_sz_sh}|${_sz_root}/${_sz_pc}*)"            # a protected descendant FILE
_sz_b="([[:space:]]|['\"]|[;&|#]|\$)"                    # right token boundary (NOT '/')
_sz_end="([[:space:]]+--?[a-zA-Z][a-zA-Z0-9-]*)*[[:space:]]*([;&|#]|\$)"  # end-of-stmt; allows trailing option flags (GNU options-after-operands)
_sz_pre="${_sz_pc}*"                                     # optional leading path prefix (./, abs, $PWD/, repo-root)

if echo "$command" | grep -qE "(${_sz_sh}|\\.run/cron\\.d|grimoires/loa/skills)" 2>/dev/null; then
  if [[ "${LOA_ALLOW_STATE_ZONE_EXEC_WRITE:-}" == "1" ]]; then
    # Sanctioned override — allow, warn once, audit the bypass (best-effort).
    if [[ -z "${LOA_SZ_EXEC_WRITE_BYPASS_WARNED:-}" ]]; then
      echo "WARNING: block-destructive-bash: LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1 — State-Zone executable/lifecycle write guard bypassed this session." >&2
      export LOA_SZ_EXEC_WRITE_BYPASS_WARNED=1
    fi
    {
      _sz_redactor="${LOA_REPO_ROOT:-.}/.claude/scripts/lib/log-redactor.sh"
      _sz_cmd=$(printf '%s' "$command" | "$_sz_redactor" 2>/dev/null) || _sz_cmd="[REDACTOR-FAILED]"
      [[ ${#_sz_cmd} -gt 2048 ]] && _sz_cmd="${_sz_cmd:0:2048}[...TRUNCATED]"
      mkdir -p "${LOA_REPO_ROOT:-.}/.run" 2>/dev/null || true
      jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg cmd "$_sz_cmd" --arg cwd "$(pwd)" \
        '{ts: $ts, tool: "Bash", command: $cmd, exit_code: 0, cwd: $cwd, hook: "block-destructive-bash", action: "bypass", pattern_id: "FR-SZ"}' \
        >> "${LOA_REPO_ROOT:-.}/.run/audit.jsonl" 2>/dev/null || true
    } 2>/dev/null || true
  else
    # Write-intent tests — first match blocks (emit_block exits 2). Anchored to write
    # operations so read-only references (cat/ls/grep/source/cp-FROM) pass through.

    # SZ-REDIR: redirect (any fd / append / noclobber-override) INTO a protected file.
    if echo "$command" | grep -qE "([0-9]*|&)?>>?\\|?[[:space:]]*['\"]?${_sz_pre}${_sz_file}${_sz_b}" 2>/dev/null; then
      matched=$(echo "$command" | grep -oE ">>?[[:space:]]*['\"]?${_sz_pre}${_sz_file}" | head -1)
      emit_block "FR-SZ-REDIR" "$matched" "Redirect-write to a State-Zone executable/lifecycle path. These are generator/approval-only. Run the owning generator/skill, or set LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1 for an audited override."
    fi

    # SZ-TEE: tee writes ALL its file operands (any position, short or long flags).
    if echo "$command" | grep -qE "\\btee\\b[^|;&]*[[:space:]]['\"]?${_sz_pre}${_sz_file}${_sz_b}" 2>/dev/null; then
      matched=$(echo "$command" | grep -oE "${_sz_file}" | head -1)
      emit_block "FR-SZ-TEE" "$matched" "tee-write to a State-Zone executable/lifecycle path. Use the owning generator/skill, or LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1."
    fi

    # SZ-COPY: cp/mv/install/rsync. (a) protected DESTINATION as last operand
    # (end-anchored, so reading a protected file OUT stays allowed); (b) protected
    # directory via -t / --target-directory.
    if echo "$command" | grep -qE "\\b(cp|mv|install|rsync)\\b[^|;&]+[[:space:]]['\"]?${_sz_pre}${_sz_tgt}['\"]?${_sz_end}" 2>/dev/null \
       || echo "$command" | grep -qE "\\b(cp|mv|install|ln)\\b[^|;&]*[[:space:]](-t|--target-directory)(=|[[:space:]]+)['\"]?${_sz_pre}${_sz_tgt}${_sz_b}" 2>/dev/null; then
      matched=$(echo "$command" | grep -oE "${_sz_tgt}" | head -1)
      emit_block "FR-SZ-COPY" "$matched" "copy/move into a State-Zone executable/lifecycle path. Use the owning generator/skill, or LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1."
    fi

    # SZ-LINK: ln with a protected linkname as last operand (positional dest).
    if echo "$command" | grep -qE "\\bln\\b[^|;&]+[[:space:]]['\"]?${_sz_pre}${_sz_tgt}['\"]?${_sz_end}" 2>/dev/null; then
      matched=$(echo "$command" | grep -oE "${_sz_tgt}" | head -1)
      emit_block "FR-SZ-LINK" "$matched" "symlink/hardlink into a State-Zone executable/lifecycle path. Use the owning generator/skill, or LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1."
    fi

    # SZ-DD: dd of=<protected file>.
    if echo "$command" | grep -qE "\\bdd\\b[^|;&]*of=['\"]?${_sz_pre}${_sz_file}${_sz_b}" 2>/dev/null; then
      matched=$(echo "$command" | grep -oE "of=['\"]?${_sz_pre}${_sz_file}" | head -1)
      emit_block "FR-SZ-DD" "$matched" "dd-write to a State-Zone executable/lifecycle path. Use the owning generator/skill, or LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1."
    fi

    # SZ-INPLACE: sed/perl/awk in-place edit of a protected file. Recognizes grouped
    # short clusters (-Ei) and the long --in-place[=...] form; end-anchors the file
    # operand so a sed EXPRESSION that merely mentions a protected path while editing
    # another file is NOT blocked.
    if echo "$command" | grep -qE "\\b(sed|perl|awk|gawk)\\b[^|;&]*[[:space:]](-[a-zA-Z]*i[a-zA-Z.]*|--in-place)(=|[[:space:]]|['\"])[^|;&]*[[:space:]]['\"]?${_sz_pre}${_sz_tgt}['\"]?${_sz_end}" 2>/dev/null; then
      matched=$(echo "$command" | grep -oE "${_sz_tgt}['\"]?${_sz_end}" | head -1)
      emit_block "FR-SZ-INPLACE" "$matched" "in-place edit of a State-Zone executable/lifecycle path (tamper with an approved skill or the sourced overlay). Use the owning generator/skill, or LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1."
    fi

    # SZ-EXTRACT: archive extraction INTO a protected dir (tar -C/--directory, unzip -d).
    if echo "$command" | grep -qE "\\btar\\b[^|;&]*[[:space:]](-C|--directory)(=|[[:space:]]+)['\"]?${_sz_pre}${_sz_tgt}${_sz_b}" 2>/dev/null \
       || echo "$command" | grep -qE "\\bunzip\\b[^|;&]*[[:space:]]-d(=|[[:space:]]+)['\"]?${_sz_pre}${_sz_tgt}${_sz_b}" 2>/dev/null; then
      matched=$(echo "$command" | grep -oE "(-C|--directory|-d)(=|[[:space:]]+)['\"]?${_sz_pre}${_sz_tgt}" | head -1)
      emit_block "FR-SZ-EXTRACT" "$matched" "archive extraction into a State-Zone executable/lifecycle path (drops cron-eligible / lifecycle files). Extract elsewhere, or set LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1."
    fi

    # SZ-INTERP: naive interpreter -c/-e literal write (fence value vs. injected agents;
    # obfuscated/variable-built interpreter writes remain an accepted bypass).
    if echo "$command" | grep -qE "\\b(python3?|python|perl|ruby|node|bash|sh)\\b[^|;&]*[[:space:]]-[ce].*(${_sz_sh}|\\.run/cron\\.d|grimoires/loa/skills)" 2>/dev/null \
       && echo "$command" | grep -qE "(,[[:space:]]*['\"][wax]|>>?[[:space:]]*['\"]?${_sz_pre}${_sz_file}|write_text|\\.write\\b|O_WRONLY|O_CREAT|write_bytes|copyfile|copy2|shutil.copy)" 2>/dev/null; then
      emit_block "FR-SZ-INTERP" "interpreter-inline" "naive interpreter inline write to a State-Zone executable/lifecycle path. Use the owning generator/skill, or LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1. (Obfuscated interpreter writes are an accepted bypass — fence, not boundary.)"
    fi
  fi
fi

# -----------------------------------------------------------------------------
# FR-2 — Context-aware rm -rf (P1 refined)
# SDD §5.1 v1.3: multi-invocation iteration + per-arg classification.
# Replaces the v1.37.0 blanket-block. Block on catastrophic paths; allow
# clearly-bounded subpaths; conservative-block on ambiguous shapes.
#
# Limitations (SDD §5.0.1 / §11):
# - `read -r -a` does NOT shell-parse quotes — paths with embedded spaces
#   get split into multiple tokens, falling into the AMBIGUOUS branch
#   (conservative block, NOT incorrect allow). Acceptable behavior.
# - The ALLOW list now EXCLUDES `./`, `./*`, `./.git`, `./.ssh`, `./.env`
#   (SKP-002 round-3 closure) — these were dangerous shapes that v1.0
#   incorrectly hit the `^\./` allow-prefix.
# -----------------------------------------------------------------------------
if echo "$command" | grep -qE '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?rm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r|--recursive[[:space:]]+--force|--force[[:space:]]+--recursive|-[a-zA-Z]*r[a-zA-Z]*[[:space:]]+-[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*[[:space:]]+-[a-zA-Z]*r)' 2>/dev/null; then

  # Collect ALL rm invocation segments (one per line).
  rm_segments=$(echo "$command" | grep -oE '(^|;|&&|\|\||\||[[:space:]]|\(|'\''|")[[:space:]]*(sudo[[:space:]]+)?(/[^[:space:]]*/)?rm[[:space:]][^;&|)]*')

  any_block=0
  any_ambiguous=0
  matched_arg=""

  while IFS= read -r rm_segment; do
    [[ -z "$rm_segment" ]] && continue
    rm_args_raw="${rm_segment#*rm}"
    # shellcheck disable=SC2086,SC2206 — intentional word-split on rm args
    read -r -a rm_args <<<"$rm_args_raw"

    for arg in "${rm_args[@]}"; do
      # Skip flag tokens.
      [[ "$arg" == -* ]] && continue
      # Strip outer balanced quotes for pattern-matching (does NOT shell-parse).
      unquoted="${arg#\'}"; unquoted="${unquoted%\'}"
      unquoted="${unquoted#\"}"; unquoted="${unquoted%\"}"
      # ..-segment escape → conservative block.
      if echo "$unquoted" | grep -qE '(^|/)\.\.(/|$)'; then
        any_ambiguous=1; matched_arg="$arg"; continue
      fi
      # BLOCK list (catastrophic paths).
      # cycle-114 FR-6: the home-root trailing-slash forms ($HOME/, ${HOME}/,
      # ~/) are catastrophic-equivalent to bare $HOME/~ and must hit BLOCK, not
      # the AMBIGUOUS fallback. A CHILD path (e.g. $HOME/projects, ~/subdir) is
      # NOT matched here and correctly falls through to AMBIGUOUS. Mirrors the
      # Claude Code 2.1.154 $HOME-trailing-slash fix.
      if echo "$unquoted" | grep -qE '^(/|\$HOME|\$\{HOME\}|~|~/|/etc|/usr|/var|/home|\*|\.)$|^(/etc/|/usr/|/var/|/home/|~/|\$HOME/$|\$\{HOME\}/$)'; then
        any_block=1; matched_arg="$arg"; break
      fi
      # ALLOW-EXCLUDE (was bypassing via `./` prefix).
      if echo "$unquoted" | grep -qE '^\./($|\*|\.|\.git$|\.git/|\.ssh$|\.ssh/|\.env)'; then
        any_ambiguous=1; matched_arg="$arg"; continue
      fi
      # ALLOW list (bounded subpaths).
      if echo "$unquoted" | grep -qE '^(\./[^/*.][^*]*|node_modules$|node_modules/|dist$|dist/|build$|build/|target$|target/|\.next$|\.next/|/tmp/.+|out$|out/|coverage$|coverage/)'; then
        continue
      fi
      # Ambiguous → conservative block.
      any_ambiguous=1; matched_arg="$arg"
    done

    [[ $any_block -eq 1 ]] && break
  done <<<"$rm_segments"

  if [[ $any_block -eq 1 ]]; then
    emit_block "FR-2-BLOCK" "$matched_arg" "rm -rf on catastrophic path '$matched_arg' (system root / home / glob / current-dir). Refuse."
  elif [[ $any_ambiguous -eq 1 ]]; then
    emit_block "FR-2-AMBIGUOUS" "$matched_arg" "rm -rf on an unclear path '$matched_arg'. Use './path/' explicit form, 'trash', or remove targeted children."
  fi
  # else: every arg matched the allow list → fall through.
fi

# All checks passed — allow execution.
exit 0
