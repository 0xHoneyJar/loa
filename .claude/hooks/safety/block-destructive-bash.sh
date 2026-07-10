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
# perf pass-2 (2026-07-05, skill-loop): fork/exec reduction. The boolean
# `echo | grep -qE` pattern dispatches (15 spawns on every benign Bash call)
# are replaced by bash [[ =~ ]] via the _match/_match_ci helpers below, which
# preserve grep's PER-LINE match model byte-for-byte (see helper comments).
# `\b` was translated to explicit POSIX boundary classes because bash =~
# compiles with the SYSTEM regex library — glibc supports \b, BSD libc does
# NOT, and this hook commits to macOS/BSD (header above). Each translated
# pattern carries an equivalence note. Deliberately NOT converted (grep
# retained): P10 DELETE-FROM segment extraction (grep -oiE multi-match with
# original-case output is not provably reproducible in bash — no match-offset
# primitive), the FR-SZ inner write-intent tests (their `X\b[^|;&]*` shapes
# make consuming \b-translation non-isomorphic; they only run when the
# command already mentions a protected path), and all `grep -oE | head -1`
# matched-substring extractions (block path only — the hook exits 2 right
# after). Also: stdin now streams straight into the Path-A jq (no cat spawn),
# audit timestamps use printf %(...)T (no date spawn), cwd uses $PWD.
# =============================================================================
# perf pass-8 (2026-07-05, skill-loop): provably-complete literal pre-filters
# on the pattern dispatch. After pass 2 the ~95% benign path still paid 13
# sequential ERE evaluations (~0.4 ms) plus the one unconditional P10 grep
# spawn (~3 ms). Each pattern group is now guarded by a cheap bash substring
# test on literal(s) PROVABLY NECESSARY for the group to match: each guard
# literal appears in the group's regex as a mandatory concatenation element —
# outside every alternation branch, optional (?) group and starred group — so
# any MATCHING LINE must contain it verbatim, hence the whole $command must
# contain it. Absence from the whole string therefore proves no line can
# match, and the group is skipped — outcome-identical by construction.
# Where a guard uses an alternation's literals (P6 drop|clear, FR-SZ
# .run/|grimoires/loa/skills), the guard tests ALL branch literals and any
# hit evaluates the group. Guards only ever SKIP, never accept: when the
# literal is present the group evaluates exactly as before, in the original
# order (first match still wins, block messages byte-identical).
# Case-insensitive groups (P8/P9/P10) guard on the same C-locale ASCII fold
# (${command,,}) that _match_ci applies per line and grep -i applies under
# the LC_ALL=C pin — folding is per-character and leaves \n untouched, so
# the folded whole string is exactly the folded lines joined by \n, and a
# literal absent from the folded whole is absent from every folded line.
# Per-group necessity proofs sit next to each guard. The P10 DELETE-FROM
# grep — the last unconditional spawn on the benign path — now runs only
# when the folded command contains both "delete" and "from" (both mandatory
# in its -i pattern). The log-redactor stays block-path-only (verified: it
# is exec'd only inside emit_block and the FR-SZ bypass audit branch).
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
# perf pass-11 (skill-loop, 2026-07-06): HIGH-002 fix (BB review of PR #1176).
# Passes 2 & 8 introduced bash-4-only constructs into this fence (${x,,}
# case-folding, `mapfile`); pre-loop it was bash-3.2-portable (echo|grep -i).
# macOS ships bash 3.2. This guard runs BEFORE any bash-4 expansion executes
# (bash 3.2 defers ${,,} validation and the mapfile builtin lookup to runtime,
# so a runtime guard at the first executable line runs first and never reaches
# them). If a bash >=4 exists (the framework already requires it — beads-health
# etc. source bash-version-guard.sh), re-exec under it; stdin (the hook payload)
# and argv survive exec. Otherwise FAIL CLOSED (exit 2 = block): a
# destructive-command fence must never silently allow when it cannot evaluate.
# The generic bash-version-guard.sh exits 1, which is a NON-blocking PreToolUse
# hook error (fail-OPEN) — wrong direction for this hook, hence the inline form.
if [ "${BASH_VERSINFO:-0}" -lt 4 ]; then
    for _bh_cand in /opt/homebrew/bin/bash /usr/local/bin/bash /usr/bin/bash bash; do
        if command -v "$_bh_cand" >/dev/null 2>&1; then
            _bh_major="$("$_bh_cand" -c 'echo "${BASH_VERSINFO:-0}"' 2>/dev/null || echo 0)"
            if [ "${_bh_major:-0}" -ge 4 ]; then exec "$_bh_cand" "$0" "$@"; fi
        fi
    done
    echo "[block-destructive-bash] BLOCKED: bash >=4 required to evaluate the destructive-command fence (found ${BASH_VERSION:-unknown}); refusing to run degraded rather than allow a command unchecked. Install bash>=4 (macOS: brew install bash)." >&2
    exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  if [[ -z "${LOA_BLOCK_DESTRUCTIVE_JQ_MISSING_WARNED:-}" ]]; then
    echo "WARNING: block-destructive-bash: jq not in PATH — destructive-command pattern matching is DISABLED for this session. Install jq to restore safety guards." >&2
    export LOA_BLOCK_DESTRUCTIVE_JQ_MISSING_WARNED=1
  fi
  exit 0  # Existing fail-open behavior preserved.
fi

# perf pass-2: pin byte-oriented ASCII regex/case-fold semantics for both the
# remaining greps and the bash [[ =~ ]]/${var,,} conversions. All patterns in
# this file are pure-ASCII; C-locale folding is the semantics they were
# written for (and what the test/golden harness already pins).
export LC_ALL=C

# Read tool input from stdin (JSON with tool_input.command).
# Path A jq call (SDD §6.4): failure here → empty $command → allow.
# perf pass-2: jq reads the hook's stdin directly — identical bytes reach the
# same jq program; the interim $(cat) copy and echo-pipe only added 2 forks.
command=$(jq -r '.tool_input.command // empty' 2>/dev/null) || true

# If we can't parse the command, allow (don't block on parse errors).
if [[ -z "$command" ]]; then
  exit 0
fi

# -----------------------------------------------------------------------------
# quote-blindness scrub (bd-bdb-quote-blindness-pt1g) — SAFE-BY-CONSTRUCTION.
# Produce _cmd_match, a LOCAL scrub-copy of $command used SOLELY for the
# block/allow decision below. $command itself is left byte-for-byte intact so
# emit_block's audit row and every matched-substring extraction still record
# the operator's real text.
#
# The fence is quote-blind: it sees a destructive TOKEN (rm -rf, DROP/TRUNCATE
# TABLE, DELETE FROM, git branch -D, ...) inside an INERT data carrier — an
# echo argument, a git commit message, a bead description, a gh PR body — and
# blocks a harmless command. The GENERAL problem (deciding whether an arbitrary
# quoted string will be executed) is NOT tractable in a regex fence — any
# allowlist of *execution* shapes (ssh/su -c/sh -c/xargs/...) is unbounded and
# reintroduces bypass (issue #1047). This is the INVERSE: a curated allowlist
# of KNOWN-INERT data carriers, whose value we redact into the scrub-copy.
#
# Load-bearing bypass defense: the ONLY way to smuggle real danger through an
# allowlisted carrier is command-substitution inside the value —
# `git commit -m "$(rm -rf /)"`. $( and backtick are caught by the (-boundary
# subshell branch of FR-2 (quote-independent). So we redact a carrier value
# ONLY when — POST-HOC CONTENT TEST (cycle-120 C-D3a) — it contains NEITHER the
# literal 2-byte sequence `$(` NOR a backtick. A LONE `$` (a dollar amount, an
# $ENV mention, a bare `$` right before the closing quote) is now permitted
# inside a redacted value: the value is captured with a quote-BOUNDED class
# (`'[^']*'` / `"[^"]*"`) that stops at the closing quote and therefore CANNOT
# swallow past a string terminator — the failure mode the adversarial panel
# rejected for the naive `\$[^(]` consuming ERE (a value ending in a bare `$`
# would eat the closing quote + a following real `&& rm -rf`). A plain
# substring gate then decides; anything holding `$(` or a backtick is left
# INTACT and falls through to normal detection. The substring gate also rejects
# `$$(…` (it contains the substring `$(`) — an ERE `\$[^(]` alternation would
# have wrongly accepted it. (Backtick command-substitution is itself a
# PRE-EXISTING, quote-independent bypass this fence does NOT catch in either
# direction — tracked in bd-bdb-backtick-bypass; leaving backtick values
# un-redacted keeps that behaviour byte-identical, opening nothing new.) An
# INCOMPLETE allowlist therefore only PRESERVES a false positive (today's safe
# behavior) — it can never open a bypass.
#
# Carrier exemption is PER-SEGMENT (bounded by ^ ; && || |): the scrub never
# crosses a shell statement separator, so `echo 'safe' && rm -rf /` still
# blocks the real second segment. Word-boundaries ((^|[^[:alnum:]_])git…) keep
# `notgit commit -m '…'` from matching (anti-spoof). echo/printf stays a sed
# scrub (rest-of-segment, not a quoted value); the git/br/gh quoted-value
# carriers use the content-gated bash loop `_bdb_scrub` below (replace the value
# with a single SPACE, never empty). BSD/GNU ERE only — no \b (BSD libc lacks
# it; header §).
# -----------------------------------------------------------------------------
# Bare echo/printf carrier: from a segment-start echo/printf to the end of its
# segment. The rest-class excludes ; & | (segment separators — per-segment
# scoping), $ and backtick (command-substitution — never redact past them), and
# < > (redirect operators — leave redirects + their targets intact so the FR-SZ
# State-Zone write guard, which keys off the raw path, still fires on
# `echo x >> .run/cron.d/job.sh`).
_bdb_sed_echo='s/(^|;|&&|\|\||\|)([[:space:]]*(sudo[[:space:]]+)?(echo|printf)[[:space:]]+)[^;&|<>$`]*/\1\2 /g'

# Quoted-value carriers (git commit -m / br|bd … -d / gh … create --body|--title).
# cycle-120 C-D3a: content-gated redaction. The value is captured with a
# quote-BOUNDED permissive class (permits `$`, stops at the closing quote — no
# terminator swallow); _bdb_scrub then applies the POST-HOC content gate. The
# quoted value is the LAST capture group (no group follows it). [^;&|]* keeps
# the prefix within one segment; (^|[^[:alnum:]_]) is the anti-spoof boundary.
# cycle-120 R1 fix (CRITICAL): the pre-flag prefix classes ALSO exclude quotes
# (`[^;&|'"]*`). Without that, POSIX leftmost-longest lets the prefix walk PAST
# the real flag+opening-quote and re-anchor on a decoy flag literal embedded in
# the value (`git commit -m "-m " && rm -rf "/"`), so the value capture spans
# from the string's real closing quote to the NEXT quote — swallowing a live
# `&& rm -rf "` into a redacted "carrier value". Barring quotes from the prefix
# means a flag can only be matched before any quote in the segment is opened.
_bdb_qval_perm="('[^']*'|\"[^\"]*\")"
_bdb_re_git="(^|[^[:alnum:]_])git[[:space:]][^;&|'\"]*commit[^;&|'\"]*(-m|--message)[[:space:]]+${_bdb_qval_perm}"
_bdb_re_brbd="(^|[^[:alnum:]_])(br|bd)[[:space:]][^;&|'\"]*(create|update)[^;&|'\"]*(-d|--description)[[:space:]]+${_bdb_qval_perm}"
_bdb_re_gh="(^|[^[:alnum:]_])gh[[:space:]][^;&|'\"]*(issue|pr)[^;&|'\"]*create[^;&|'\"]*(--body|--title)[[:space:]]+${_bdb_qval_perm}"

# Tail-run of contiguous message flags after the primary carrier match. A
# single `git commit`/`gh create`/… can carry MULTIPLE `-m/--message`/`-d`/
# `--body`… pairs (git concatenates multi-`-m` into paragraphs). The primary
# regex, now that the prefix bars quotes (R1 fix), only anchors the FIRST pair;
# this tail consumes further contiguous `flag <quoted-value>` pairs so all of a
# genuine multi-flag message is redacted. It is anchored at the START of the
# remaining text (`^[[:space:]]*flag …`), so it CANNOT cross a statement
# separator: the moment the remainder begins with anything other than another
# message flag (e.g. `&& rm -rf`), the tail stops and that text is left INTACT
# for FR-2. This keeps multi-`-m` benign commits allowed WITHOUT reopening the
# `&&`-crossing bypass.
_bdb_re_tail="^[[:space:]]*(-m|--message|-d|--description|--body|--title)[[:space:]]+${_bdb_qval_perm}"

# _bdb_scrub <carrier-ere> <input> — echo the input with every carrier value
# that passes the content gate replaced by a single SPACE (never empty, never
# crossing a segment). A value containing `$(` (this catches `$$(` too — the
# substring is present) or a backtick is left INTACT. bash =~ exposes no match
# offset, so the split is by string slice on the matched text.
_bdb_scrub() {
  local re="$1" rest="$2" out="" m val inner pre po vi
  while [[ "$rest" =~ $re ]]; do
    m="${BASH_REMATCH[0]}"
    vi=$(( ${#BASH_REMATCH[@]} - 1 ))   # trailing group = the quoted value
    val="${BASH_REMATCH[$vi]}"
    pre="${rest%%"$m"*}"                 # text before this match
    rest="${rest#*"$m"}"                 # text after this match
    inner="${val:1:${#val}-2}"          # strip the outer quotes
    if [[ "$inner" == *'$('* || "$inner" == *'`'* ]]; then
      out+="$pre$m"                     # command-sub value — leave INTACT
    else
      po="${m%"$val"}"                  # matched text minus the trailing value
      out+="$pre$po "                   # value → single space
    fi
    # Consume any contiguous trailing message-flag pairs (multi-`-m`), each
    # content-gated the same way. Stops at the first non-flag token (separator
    # or real content), so it never crosses a statement boundary.
    while [[ "$rest" =~ $_bdb_re_tail ]]; do
      m="${BASH_REMATCH[0]}"
      vi=$(( ${#BASH_REMATCH[@]} - 1 ))
      val="${BASH_REMATCH[$vi]}"
      rest="${rest#"$m"}"
      inner="${val:1:${#val}-2}"
      if [[ "$inner" == *'$('* || "$inner" == *'`'* ]]; then
        out+="$m"                       # command-sub value — leave INTACT
      else
        po="${m%"$val"}"
        out+="$po "
      fi
    done
  done
  printf '%s' "$out$rest"
}

# echo/printf scrub first (sed), then the content-gated quoted-value carriers
# (bash loops, each guarded by a cheap literal test so the benign path pays
# nothing beyond the substring check).
_cmd_match=$(printf '%s' "$command" | sed -E -e "$_bdb_sed_echo" 2>/dev/null) || _cmd_match="$command"
[[ -z "$_cmd_match" ]] && _cmd_match="$command"
[[ "$_cmd_match" == *"git"* ]] && _cmd_match=$(_bdb_scrub "$_bdb_re_git" "$_cmd_match")
if [[ "$_cmd_match" == *"br "* || "$_cmd_match" == *"bd "* ]]; then
  _cmd_match=$(_bdb_scrub "$_bdb_re_brbd" "$_cmd_match")
fi
[[ "$_cmd_match" == *"gh "* ]] && _cmd_match=$(_bdb_scrub "$_bdb_re_gh" "$_cmd_match")
# Fail-safe: an empty scrub on a non-empty command → fall back to RAW (stricter
# matching), never to an empty scrub that would silence every pattern.
[[ -z "$_cmd_match" ]] && _cmd_match="$command"

# -----------------------------------------------------------------------------
# perf pass-2 line-model helpers.
#
# `echo "$cmd" | grep -qE PAT` tests PAT against each LINE; bash [[ =~ ]]
# tests the WHOLE string, where a `[[:space:]]` would match the newline
# itself, negated classes like [^-] would cross line boundaries, and ^/$
# anchor only at string edges. To keep byte-identical semantics we split
# $command into grep's line model ONCE (trailing \n is a terminator, not an
# extra empty line; a final fragment without \n is still a line) and test
# per line. Invalid-regex behavior also matches the old `grep -qE …
# 2>/dev/null`: [[ =~ ]] returns non-zero silently.
# -----------------------------------------------------------------------------
# quote-blindness fix: derive the line model from the scrub-copy _cmd_match so
# every pattern that goes through _match/_match_ci (P2-P9, P11, P12, FR-2 gate)
# sees inert carrier values redacted, with ZERO change to their own regexes.
_cmd_lines=()
if [[ "$_cmd_match" == *$'\n'* ]]; then
  mapfile -t _cmd_lines <<<"${_cmd_match%$'\n'}"
else
  _cmd_lines=("$_cmd_match")
fi

# _match <ere> — exit 0 iff any line matches; ≡ echo "$command" | grep -qE <ere>
_match() {
  local _l
  for _l in "${_cmd_lines[@]}"; do
    [[ "$_l" =~ $1 ]] && return 0
  done
  return 1
}

# _match_ci <lowercase-ere> — ≡ echo "$command" | grep -qiE <ere>.
# Case-insensitivity via ${line,,} against a pre-lowercased pattern: ASCII
# fold under the LC_ALL=C pin above, exactly grep -i's C-locale fold.
_match_ci() {
  local _l
  for _l in "${_cmd_lines[@]}"; do
    [[ "${_l,,}" =~ $1 ]] && return 0
  done
  return 1
}

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

    # perf pass-2: UTC timestamp via bash strftime (was `date -u` spawn);
    # cwd via $PWD (bash keeps it identical to the pwd builtin's output).
    local _ts
    TZ=UTC0 printf -v _ts '%(%Y-%m-%dT%H:%M:%SZ)T' -1

    jq -cn \
      --arg ts "$_ts" \
      --arg cmd "$sanitized_cmd" \
      --arg cwd "$PWD" \
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
# pass-8 git-family pre-filter (wraps P2, P2b, P3, P4, P5, P6, P7).
# NECESSITY PROOF (`git`): each of the eight EREs inside this block contains
# the literal run `git` as a mandatory concatenation element (it sits outside
# every alternation and every optional group), so any matching line contains
# "git". "git" absent from $command ⇒ absent from every line ⇒ all eight
# _match calls return 1 ⇒ skipping the block is outcome-identical (P4's
# has_clean_f/has_clean_n are initialized false inside and its block
# condition cannot fire). Interior sections keep their original order;
# only skip-guards were added — no pattern byte changed.
# -----------------------------------------------------------------------------
if [[ "$command" == *"git"* ]]; then  # ── pass-8 git-family pre-filter ──

# -----------------------------------------------------------------------------
# P2 / P2b — git push --force / git push -f  (existing; pattern_id back-fill)
# pass-8 pre-filters: `push` is a mandatory concatenation element of both
# EREs. P2 additionally mandates the literal `--force` (its trailing ($|[^-])
# matches AFTER the complete literal), P2b the literal `-f` — each appears
# in its ERE outside any alternation/optional group.
# -----------------------------------------------------------------------------
if [[ "$command" == *"push"* ]]; then
  if [[ "$command" == *"--force"* ]] \
     && _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+push[[:space:]]+.*--force($|[^-])'; then
    matched=$(echo "$command" | grep -oE 'git[[:space:]]+push[[:space:]]+.*--force[^-]?' | head -1)
    emit_block "P2" "$matched" "git push --force detected. Use --force-with-lease for safer force push, or push to a feature branch."
  fi
  if [[ "$command" == *"-f"* ]] \
     && _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+push[[:space:]]+.*-f($|[[:space:]])'; then
    matched=$(echo "$command" | grep -oE 'git[[:space:]]+push[[:space:]]+.*-f' | head -1)
    emit_block "P2b" "$matched" "git push -f detected. Use --force-with-lease for safer force push, or push to a feature branch."
  fi
fi

# -----------------------------------------------------------------------------
# P3 — git reset --hard  (existing; pattern_id back-fill)
# pass-8 pre-filter: `reset` and `--hard` are both mandatory concatenation
# elements of the ERE (adjacent, joined by [[:space:]]+).
# -----------------------------------------------------------------------------
if [[ "$command" == *"reset"* && "$command" == *"--hard"* ]] \
   && _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+reset[[:space:]]+--hard'; then
  matched=$(echo "$command" | grep -oE 'git[[:space:]]+reset[[:space:]]+--hard[^[:space:]]*' | head -1)
  emit_block "P3" "$matched" "git reset --hard discards uncommitted work. Use 'git stash' to save changes, or 'git reset --soft' to keep them staged."
fi

# -----------------------------------------------------------------------------
# P4 — git clean -f without -n dry-run  (existing; pattern_id back-fill)
# pass-8 pre-filter: `clean` is a mandatory concatenation element of BOTH
# EREs; when absent, both flags provably stay false and the block condition
# below cannot fire — identical to two failed matches. The final check stays
# outside the guard so the flag semantics are untouched.
# -----------------------------------------------------------------------------
has_clean_f=false
has_clean_n=false
if [[ "$command" == *"clean"* ]]; then
  if _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*f'; then
    has_clean_f=true
  fi
  if _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*n'; then
    has_clean_n=true
  fi
fi
if [[ "$has_clean_f" == "true" && "$has_clean_n" == "false" ]]; then
  matched=$(echo "$command" | grep -oE 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]+' | head -1)
  emit_block "P4" "$matched" "git clean -f without dry-run. Run 'git clean -nd' first to preview what would be deleted."
fi

# -----------------------------------------------------------------------------
# P5 — git branch -D / force-delete  (FR-1.1)
# Covers grouped -D, --delete --force / --force --delete, split -d -f / -f -d.
# pass-2 \b translation: `--delete\b.*--force` → `--delete([^[:alnum:]_].*)?--force`
# (existence-equivalent: either --force follows immediately — its '-' IS the
# non-word boundary char — or a non-word char then anything then --force.
# The naive consuming form `--delete[^[:alnum:]_].*--force` would MISS
# `--delete--force`; the optional-group form does not). Same for the
# mirrored `--force\b.*--delete`.
# pass-8 pre-filter: `branch` is a mandatory concatenation element; every
# branch of the flags alternation begins with the literal `-`.
# -----------------------------------------------------------------------------
if [[ "$command" == *"branch"* && "$command" == *"-"* ]] \
   && _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+branch[[:space:]]+(-[a-zA-Z]*D[a-zA-Z]*|--delete[[:space:]]+--force|--force[[:space:]]+--delete|-d[[:space:]]+-f|-f[[:space:]]+-d|--delete([^[:alnum:]_].*)?--force|--force([^[:alnum:]_].*)?--delete)'; then
  matched=$(echo "$command" | grep -oE 'git[[:space:]]+branch[[:space:]]+[^[:space:]&|;]+([[:space:]]+[^[:space:]&|;]+)?' | head -1)
  emit_block "FR-1.1" "$matched" "git branch -D loses unmerged work. Use 'git branch -d' (lowercase) — it refuses to drop branches with unmerged commits."
fi

# -----------------------------------------------------------------------------
# P6 — git stash drop / git stash clear  (FR-1.2)
# Note: git stash pop is NOT included (recoverable from reflog per SDD §5.3).
# pass-2 \b translation: trailing `(drop|clear)\b` at regex end →
# `(drop|clear)($|[^[:alnum:]_])` (word-boundary-after ≡ end-of-line or a
# consumed non-word char; nothing follows in the regex, so consuming is safe).
# pass-8 pre-filter: `stash` is a mandatory concatenation element; the
# mandatory (drop|clear) alternation has exactly two branch literals, so the
# guard tests BOTH — either present ⇒ evaluate the group.
# -----------------------------------------------------------------------------
if [[ "$command" == *"stash"* && ( "$command" == *"drop"* || "$command" == *"clear"* ) ]] \
   && _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+stash[[:space:]]+(drop|clear)($|[^[:alnum:]_])'; then
  matched=$(echo "$command" | grep -oE 'git[[:space:]]+stash[[:space:]]+(drop|clear)([[:space:]]+[^[:space:]&|;]+)?' | head -1)
  emit_block "FR-1.2" "$matched" "git stash {drop,clear} permanently destroys stashed work. Run 'git stash list' first; consider 'git stash show' / 'git stash apply' before dropping."
fi

# -----------------------------------------------------------------------------
# P7 — git checkout -- <path>  (FR-1.3) — legacy form, overwrites uncommitted
# Refined ERE per SDD §5.4 v1.3: path must NOT start with `-` (so --quiet
# and similar flag-shaped tokens don't trigger).
# pass-8 pre-filter: `checkout` and `--` are both mandatory concatenation
# elements (`--` is the two-char literal between the [[:space:]] runs).
# -----------------------------------------------------------------------------
if [[ "$command" == *"checkout"* && "$command" == *"--"* ]] \
   && _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+checkout[[:space:]]+--[[:space:]]+[^-][^[:space:]]*'; then
  matched=$(echo "$command" | grep -oE 'git[[:space:]]+checkout[[:space:]]+--[[:space:]]+[^[:space:]&|;]+' | head -1)
  emit_block "FR-1.3" "$matched" "git checkout -- <file> overwrites uncommitted changes irreversibly. Use 'git stash push <file>' to save first, or 'git restore --source=HEAD <file>' (explicit source)."
fi

fi  # ── end pass-8 git-family pre-filter ──

# -----------------------------------------------------------------------------
# pass-8: one C-locale fold of the whole command for the case-insensitive
# groups (P8, P9, P10). ${command,,} applies the same per-character ASCII
# fold that _match_ci applies per line and grep -i applies under LC_ALL=C;
# folding leaves \n untouched, so a literal absent from this folded whole
# string is absent from every folded line.
# -----------------------------------------------------------------------------
_cmd_lc="${_cmd_match,,}"  # quote-blindness fix: fold the scrub-copy (see above)

# -----------------------------------------------------------------------------
# P8 — DROP DATABASE / DROP TABLE / DROP SCHEMA  (FR-1.4)
# Case-insensitive via -iE. Accepted false-positive: `cat | grep DROP TABLE`
# (read-only inspection of schema files). Documented as known limitation.
# pass-2: -i → _match_ci with lowercased literals; leading/trailing \b →
# `(^|[^[:alnum:]_])`/`($|[^[:alnum:]_])` (leading \b before a word char ≡
# start-of-line or preceded by non-word; trailing \b at regex end ≡
# end-of-line or followed by non-word — consuming forms are existence-
# equivalent since nothing else competes for the boundary char).
# pass-8 pre-filter: folded `drop` is a mandatory concatenation element of
# the folded ERE (the (database|table|schema) alternation is deliberately
# NOT used — `drop` alone is the necessary literal).
# -----------------------------------------------------------------------------
if [[ "$_cmd_lc" == *"drop"* ]] \
   && _match_ci '(^|[^[:alnum:]_])(drop[[:space:]]+(database|table|schema))($|[^[:alnum:]_])'; then
  matched=$(echo "$command" | grep -oiE '\b(DROP[[:space:]]+(DATABASE|TABLE|SCHEMA))[[:space:]]+[^;]*' | head -1)
  emit_block "FR-1.4" "$matched" "DROP {DATABASE,TABLE,SCHEMA} is irreversible. If this is a migration, run via your migration tool with explicit confirmation; otherwise temporarily disable the hook for the next command only."
fi

# -----------------------------------------------------------------------------
# P9 — TRUNCATE TABLE  (FR-1.5)
# Case-insensitive. SDD §5.6 v1.3: quoted-ident coverage for Postgres
# ("users") + MySQL (`users`) + bare unquoted.
# pass-2: -i → _match_ci (literals lowercased; the ident classes already
# cover both cases so folding the text cannot change their outcome);
# leading \b → (^|[^[:alnum:]_]) as in P8.
# pass-8 pre-filter: folded `truncate` is a mandatory concatenation element
# (the optional table group and the ident alternation share no literal —
# `truncate` alone is the necessary literal).
# -----------------------------------------------------------------------------
if [[ "$_cmd_lc" == *"truncate"* ]] \
   && _match_ci '(^|[^[:alnum:]_])truncate[[:space:]]+(table[[:space:]]+)?("[^"]+"|`[^`]+`|[a-zA-Z_][a-zA-Z0-9_]*)'; then
  matched=$(echo "$command" | grep -oiE '\bTRUNCATE[[:space:]]+(TABLE[[:space:]]+)?("[^"]+"|`[^`]+`|[a-zA-Z_][a-zA-Z0-9_]*)' | head -1)
  emit_block "FR-1.5" "$matched" "TRUNCATE wipes the table. Use 'DELETE FROM <table> WHERE ...' for scoped row removal, or run in a transaction with explicit operator approval."
fi

# -----------------------------------------------------------------------------
# P10 — DELETE FROM <table> without WHERE  (FR-1.6)
# Two-pass per SDD §5.7 v1.3: iterate ALL DELETE FROM segments (multi-
# statement bypass closure). For each segment, fail if no WHERE present.
# Quoted-ident extended via the ("[^"]+"|`[^`]+`|...) alternation.
# pass-2: NOT converted — grep -oiE extracts every match per line with the
# ORIGINAL case preserved (the segment text feeds emit_block/audit); bash
# =~ exposes no match offset, so case-preserving multi-match extraction
# cannot be reproduced provably. One grep spawn retained by design.
# pass-8 pre-filter: folded `delete` and `from` are both mandatory
# concatenation elements of the -i pattern (\b is zero-width and does not
# affect literal necessity), so when either is absent the grep provably
# emits nothing → delete_stmts="" → the [[ -n ]] branch was already dead.
# This removes the last unconditional spawn on the benign path.
# delete_stmts is pre-initialized so an inherited environment value can
# never leak into the skipped branch.
# -----------------------------------------------------------------------------
delete_stmts=""
if [[ "$_cmd_lc" == *"delete"* && "$_cmd_lc" == *"from"* ]]; then
  # quote-blindness fix (step 3, CRITICAL): P10's raw grep does NOT go through
  # _cmd_lines, so it must read the scrub-copy _cmd_match too — otherwise a
  # DELETE FROM inside a redacted carrier value (e.g. git commit -m '…DELETE
  # FROM users…') stays a false positive while everything else is fixed.
  delete_stmts=$(echo "$_cmd_match" | grep -oiE '\bDELETE[[:space:]]+FROM[[:space:]]+("[^"]+"|`[^`]+`|[a-zA-Z_][a-zA-Z0-9_]*)[^;]*' 2>/dev/null)
fi
if [[ -n "$delete_stmts" ]]; then
  while IFS= read -r delete_stmt; do
    [[ -z "$delete_stmt" ]] && continue
    if ! echo "$delete_stmt" | grep -qiE '\bWHERE\b' 2>/dev/null; then
      emit_block "FR-1.6" "$delete_stmt" "DELETE FROM without WHERE removes all rows. Add a WHERE clause."
    fi
  done <<<"$delete_stmts"
fi

# -----------------------------------------------------------------------------
# pass-8 kubectl pre-filter (wraps P11, P12).
# NECESSITY PROOF (`kubectl` AND `delete`): both are mandatory concatenation
# elements of BOTH EREs below (the optional global-flag block sits between
# them; neither literal is inside it). Either literal absent ⇒ neither group
# can match ⇒ skip. Original evaluation order preserved inside.
# -----------------------------------------------------------------------------
if [[ "$command" == *"kubectl"* && "$command" == *"delete"* ]]; then  # ── pass-8 kubectl pre-filter ──

# -----------------------------------------------------------------------------
# P11 — kubectl delete namespace  (FR-1.7)
# SDD §5.8 v1.3: global-flag placement covered via the
# ([[:space:]]+(-X[[:space:]]+|--X)*) optional-flag-block between kubectl
# and delete. Catches `kubectl --kubeconfig=foo delete ns prod`.
# -----------------------------------------------------------------------------
if _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?kubectl([[:space:]]+(-[a-zA-Z]+([[:space:]]+|=)[^[:space:]]+|--[a-zA-Z][a-zA-Z0-9-]*(=[^[:space:]]+|[[:space:]]+[^[:space:]-]+)?))*[[:space:]]+delete[[:space:]]+(ns|namespace|namespaces)[[:space:]]+[a-zA-Z0-9_-]+'; then
  matched=$(echo "$command" | grep -oE 'kubectl[^;&|]*delete[[:space:]]+(ns|namespace|namespaces)[[:space:]]+[a-zA-Z0-9_-]+' | head -1)
  emit_block "FR-1.7" "$matched" "kubectl delete namespace wipes the entire namespace and everything inside it. Use 'kubectl delete -n <ns> -l <selector>' for scoped deletion, or temporarily disable the hook."
fi

# -----------------------------------------------------------------------------
# P12 — kubectl delete --all / -A  (FR-1.8)
# SDD §5.9 v1.3: `[^;&|]*` cross-statement bound (closes SKP-003 unbounded
# `.*`) + global-flag placement coverage. Verb-or-resource MUST appear in
# the same shell statement as the --all/-A token.
# pass-2 \b translation: `--all\b` / `-A\b` sit at the end of their
# alternation branches AND of the whole regex → `($|[^[:alnum:]_])`
# consuming form is existence-equivalent (nothing follows).
# -----------------------------------------------------------------------------
if _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?kubectl([[:space:]]+(-[a-zA-Z]+([[:space:]]+|=)[^[:space:]]+|--[a-zA-Z][a-zA-Z0-9-]*(=[^[:space:]]+|[[:space:]]+[^[:space:]-]+)?))*[[:space:]]+delete[[:space:]]+[^[:space:]]+[^;&|]*([[:space:]]--all($|[^[:alnum:]_])|[[:space:]]-A($|[^[:alnum:]_]))'; then
  matched=$(echo "$command" | grep -oE 'kubectl[^;&|]*delete[^;&|]*(--all|-A)' | head -1)
  emit_block "FR-1.8" "$matched" "kubectl delete --all / -A removes all resources in scope. Use label selectors instead: 'kubectl delete <type> -l app=<X>'."
fi

fi  # ── end pass-8 kubectl pre-filter ──

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
#
# pass-2: only the cheap OUTER gate below was converted to _match (it runs on
# every Bash call). The inner write-intent greps fire only when the command
# already mentions a protected path — left as grep because their `\btee\b…`,
# `\bdd\b…[^|;&]*` shapes do not admit a provably-isomorphic consuming \b
# translation (the boundary char can be the first char of the next element).
# pass-8 pre-filter: the outer-gate ERE is a three-branch alternation whose
# branches mandate, respectively, the literals `.run/` (from \.run/…\.sh),
# `.run/cron.d` (⊃ `.run/`), and `grimoires/loa/skills`. The guard tests the
# two distinct covering literals — either present ⇒ evaluate the gate.
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

if [[ "$command" == *".run/"* || "$command" == *"grimoires/loa/skills"* ]] \
   && _match "(${_sz_sh}|\\.run/cron\\.d|grimoires/loa/skills)"; then
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
      TZ=UTC0 printf -v _sz_ts '%(%Y-%m-%dT%H:%M:%SZ)T' -1
      jq -cn --arg ts "$_sz_ts" --arg cmd "$_sz_cmd" --arg cwd "$PWD" \
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
# - FR-2-REDIR (bd-c117-e, #1177): before segment extraction a scrub removes
#   shell `&`-redirect operators (`2>&1`/`>&2` fd-dups, `&>file`/`&>>file`)
#   from a LOCAL copy of the command, and a per-arg pre-pass below strips the
#   remaining non-`&` redirects (`2>/dev/null`, `>log`, spaced `2> /dev/null`)
#   so none are misclassified as rm operands. The scrub runs FIRST precisely
#   so an `&` cannot truncate rm_segments and hide a catastrophic operand that
#   FOLLOWS the redirect (`rm -rf 2>&1 /` — the `/` would otherwise be lost).
#   `&&` command separators survive the scrub (fd-dup needs `>` before the `&`,
#   `&>` needs `>` after), so multi-statement detection stays intact.
# - C15/cycle-119 panel amendment: `find ROOT ... -exec rm -rf {} [+|\;]`
#   shapes previously misclassified the {} / + PLACEHOLDER tokens (never real
#   paths) as ambiguous rm operands, blocking even a fully safe root (e.g.
#   `find ./build -exec rm -rf {} +`). When an rm segment's only non-flag
#   operands are find-exec placeholders AND that segment is immediately
#   preceded (same statement) by `find ROOT ... -exec`, the FIND ROOT is
#   classified through this SAME ladder instead of the placeholders. A root
#   containing `$` matches none of the ladder's branches (never a bypass —
#   see _re_find_exec_prefix below), so it always falls to AMBIGUOUS, same as
#   today: $-expansion roots are NEVER allowed. Backslash-semicolon
#   (`-exec ... {} \;`) is not covered by the ALLOW path — the segment
#   extraction below already stops at the bare `;` (pre-existing, unrelated
#   to this change), so that shape keeps its prior conservative-block
#   behavior unchanged.
#
# pass-2: gate + per-arg classification tests converted to [[ =~ ]]. The
# per-arg tests match DIRECTLY (no line loop): $unquoted derives from
# `read -r -a` word-splitting, so it can never contain a newline — a
# 1-token string IS grep's single-line input. The rm_segments grep -oE
# multi-match extraction is retained (same rationale as P10).
# pass-8 pre-filter: `rm` is a mandatory concatenation element of the gate
# ERE; every branch of its flags alternation begins with the literal `-`.
# -----------------------------------------------------------------------------
if [[ "$command" == *"rm"* && "$command" == *"-"* ]] \
   && _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?rm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r|--recursive[[:space:]]+--force|--force[[:space:]]+--recursive|-[a-zA-Z]*r[a-zA-Z]*[[:space:]]+-[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*[[:space:]]+-[a-zA-Z]*r)'; then

  # FR-2-REDIR (bd-c117-e-redirect-1pq8, #1177 item E): scrub shell
  # `&`-redirect operators from a LOCAL copy of the command BEFORE segment
  # extraction. (a) `[0-9]*>&[0-9]*` — N>&M fd-dups (`2>&1`, `>&2`, `>&`);
  # (b) `&>>?[^space]*` — `&>file` / `&>>file` operator+attached target.
  # These are pure shell syntax, never rm operands. Scrubbing first stops the
  # rm_segments `[^;&|)]*` class (below) from truncating a segment at the
  # first bare `&` and thereby dropping a catastrophic operand that FOLLOWS an
  # `&`-redirect (e.g. `rm -rf 2>&1 /`). `&&` separators survive both patterns
  # ((a) needs `>` before the `&`, (b) needs `>` after). cycle-120 C-D3b:
  # derive from $_cmd_match (the quote-blindness scrub-copy), NOT raw $command,
  # so the FR-2 GATE (which tests _cmd_match via _match) and this segment
  # EXTRACTOR read the SAME text — a redacted inert carrier can no longer feed
  # the extractor an rm operand the gate never saw (gate/extractor can't
  # disagree toward ALLOW). $command itself stays intact so emit_block's audit
  # row still records the operator's real text.
  _fr2_cmd=$(printf '%s' "$_cmd_match" | sed -E -e 's/[0-9]*>&[0-9]*/ /g' -e 's/&>>?[^[:space:]]*/ /g')

  # Collect ALL rm invocation segments (one per line).
  rm_segments=$(echo "$_fr2_cmd" | grep -oE '(^|;|&&|\|\||\||[[:space:]]|\(|'\''|")[[:space:]]*(sudo[[:space:]]+)?(/[^[:space:]]*/)?rm[[:space:]][^;&|)]*')

  # pass-2: per-arg EREs in variables (regex-in-variable is the safe [[ =~ ]]
  # form — inline |/(/$ are conditional-command parse hazards). Bytes are
  # identical to the former grep -qE arguments.
  _re_dotdot='(^|/)\.\.(/|$)'
  _re_block_list='^(/|\$HOME|\$\{HOME\}|~|~/|/etc|/usr|/var|/home|\*|\.)$|^(/etc/|/usr/|/var/|/home/|~/|\$HOME/$|\$\{HOME\}/$)'
  _re_allow_exclude='^\./($|\*|\.|\.git$|\.git/|\.ssh$|\.ssh/|\.env)'
  _re_allow_list='^(\./[^/*.][^*]*|node_modules$|node_modules/|dist$|dist/|build$|build/|target$|target/|\.next$|\.next/|/tmp/.+|out$|out/|coverage$|coverage/)'

  # C15/cycle-119: matches the text immediately preceding an rm segment
  # (bounded to the SAME statement, via the identical boundary-alternation
  # style used by every other pattern in this file) when it is a
  # `find <span> -exec` prefix. `$`-anchored: nothing may sit between
  # `-exec` and this rm invocation (sudo / an absolute /path/to/rm are
  # consumed by the rm_segment extraction itself, not this prefix). Group 3
  # is the FULL span between `find` and `-exec`; a token-walk below extracts
  # the start-point roots from it — find accepts MULTIPLE start paths, so a
  # single-token regex capture would classify only the first root and
  # silently allow `find ./build /etc -exec ...` (lead-review catch,
  # cycle-119). Eligibility requires EXACTLY ONE root; zero roots (GNU
  # default `.`, or flags-before-root like `find -L root`) and multi-root
  # shapes stay conservative-blocked.
  _re_find_exec_prefix='(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?find[[:space:]]+([^;&|)]*)-exec$'
  # Left-to-right cursor over _fr2_cmd so repeated identical rm segments each
  # resolve against THEIR OWN preceding text, not the first occurrence's.
  _fr2_remaining="$_fr2_cmd"

  # FR-2-REDIR (bd-c117-e-redirect-1pq8, issue #1177 item E): syntactic
  # redirect-token EREs for the rm_args strip loop below. Matched against
  # the RAW token (before quote-stripping), so a genuinely-quoted operand
  # like "2>weird" — which starts with a literal quote char, not a
  # digit/operator — never matches and falls through unchanged to the
  # existing ambiguous path. `&`-forms (`&>`, `&>>`, `N>&M`) need no branch
  # here: the scrub above already removed them from the extraction input, so
  # only non-`&` redirects (`2>/dev/null`, `>log`, spaced `2> /dev/null`)
  # can reach this array.
  _re_redir_bare='^([0-9]*(>>|>|<<<|<<|<))$'
  _re_redir_attached='^([0-9]*(>>|>|<<<|<<|<))[^[:space:]]+$'

  any_block=0
  any_ambiguous=0
  matched_arg=""

  while IFS= read -r rm_segment; do
    [[ -z "$rm_segment" ]] && continue

    # C15/cycle-119: isolate the text preceding THIS occurrence of rm_segment
    # (cursor-advance so a later identical segment doesn't re-match the first
    # occurrence's prefix), then test for a find-exec shape ending right here.
    _seg_prefix="${_fr2_remaining%%"$rm_segment"*}"
    _fr2_remaining="${_fr2_remaining#*"$rm_segment"}"
    _seg_find_root=""
    if [[ "$_seg_prefix" =~ $_re_find_exec_prefix ]]; then
      # Token-walk the find span: start-point roots are the LEADING tokens up
      # to the first primary/flag/paren token (-*, !, (, ), \-escaped).
      # Exactly one root => eligible; zero or many => _seg_find_root stays
      # empty and the segment falls to the untouched conservative ladder.
      # NESTED-find disqualifier (R3 review catch, cycle-119): in
      # `find <safe> -exec find <dangerous> ... -exec rm ...` the {} paths
      # come from the INNER find's root, which this walk never reaches (it
      # breaks at the first `-exec`). Any `find` token inside the span means
      # the outer root does not govern the deletions => ineligible.
      # SYMLINK-FOLLOW disqualifier (audit catch, cycle-119): -L / -H /
      # -follow make find traverse symlinks, so deletions can escape the
      # classified root through a planted link ({} resolves OUTSIDE the safe
      # tree). GNU find tolerates these after the root, where the leading-
      # flag break below never sees them => scan the whole span.
      read -r -a _find_span_toks <<<"${BASH_REMATCH[3]}"
      _find_root_count=0
      _find_nested=0
      for _ftok in ${_find_span_toks[@]+"${_find_span_toks[@]}"}; do
        [[ "$_ftok" == "find" || "$_ftok" == */find ]] && _find_nested=1
        [[ "$_ftok" == "-L" || "$_ftok" == "-H" || "$_ftok" == "-follow" ]] && _find_nested=1
      done
      for _ftok in ${_find_span_toks[@]+"${_find_span_toks[@]}"}; do
        case "$_ftok" in
          -*|'!'*|'('*|')'*|'\'*) break ;;
          *) _find_root_count=$((_find_root_count + 1)); _seg_find_root="$_ftok" ;;
        esac
      done
      [[ "$_find_root_count" -ne 1 || "$_find_nested" -eq 1 ]] && _seg_find_root=""
    fi

    rm_args_raw="${rm_segment#*rm}"
    # shellcheck disable=SC2086,SC2206 — intentional word-split on rm args
    read -r -a rm_args <<<"$rm_args_raw"

    # FR-2-REDIR: strip shell-redirect tokens before per-arg classification.
    # A bare operator (empty tail, e.g. "2>", ">", "<<") consumes ITSELF
    # plus the NEXT array element (the separate-word target of "2> /dev/null");
    # an attached operator (non-empty tail glued on, e.g. "2>/dev/null",
    # ">log", "2>&1") consumes only itself. A token that does not start
    # with an optional fd-digit run immediately followed by an operator
    # char is untouched — a real operand named "2" (no operator) or a
    # filename with '>' NOT at the token start (e.g. "./build>x", one
    # token because read -a doesn't split on it) is never mistaken for a
    # redirect and falls through to the existing block/allow/ambiguous
    # ladder unchanged.
    rm_args_filtered=()
    _skip_next=0
    for ((_i = 0; _i < ${#rm_args[@]}; _i++)); do
      _tok="${rm_args[_i]}"
      if [[ $_skip_next -eq 1 ]]; then
        _skip_next=0
        continue
      fi
      if [[ "$_tok" =~ $_re_redir_bare ]]; then
        _skip_next=1
        continue
      fi
      if [[ "$_tok" =~ $_re_redir_attached ]]; then
        continue
      fi
      rm_args_filtered+=("$_tok")
    done
    rm_args=(${rm_args_filtered[@]+"${rm_args_filtered[@]}"})

    # C15/cycle-119: this segment is find-exec-governed ONLY when a root was
    # detected AND every non-flag operand of THIS rm invocation is a find-exec
    # placeholder ({}, +, \;, ;) — i.e. the rm has no operand of its own.
    # Any segment with a real operand (find-exec or not) keeps the untouched
    # per-arg ladder below, so this can never suppress a genuine dangerous arg.
    _seg_placeholder_only=0
    if [[ -n "$_seg_find_root" ]]; then
      _seg_placeholder_only=1
      for arg in "${rm_args[@]}"; do
        [[ "$arg" == -* ]] && continue
        case "$arg" in
          '{}'|'+'|'\;'|';') ;;
          *) _seg_placeholder_only=0 ;;
        esac
      done
    fi

    if [[ $_seg_placeholder_only -eq 1 ]]; then
      # Classify the FIND ROOT through the EXACT SAME ladder as any rm operand
      # (never a bypass path — see _re_find_exec_prefix comment: a `$`-bearing
      # root matches none of these branches and falls to AMBIGUOUS, same as
      # every other unrecognized shape).
      unquoted="${_seg_find_root#\'}"; unquoted="${unquoted%\'}"
      unquoted="${unquoted#\"}"; unquoted="${unquoted%\"}"
      if [[ "$unquoted" =~ $_re_dotdot ]]; then
        any_ambiguous=1; matched_arg="$_seg_find_root"
      elif [[ "$unquoted" =~ $_re_block_list ]]; then
        any_block=1; matched_arg="$_seg_find_root"
      elif [[ "$unquoted" =~ $_re_allow_exclude ]]; then
        any_ambiguous=1; matched_arg="$_seg_find_root"
      elif [[ "$unquoted" =~ $_re_allow_list ]]; then
        : # explicit safe relative root — allow this find-exec segment
      else
        any_ambiguous=1; matched_arg="$_seg_find_root"
      fi
    else
      for arg in "${rm_args[@]}"; do
        # Skip flag tokens.
        [[ "$arg" == -* ]] && continue
        # Strip outer balanced quotes for pattern-matching (does NOT shell-parse).
        unquoted="${arg#\'}"; unquoted="${unquoted%\'}"
        unquoted="${unquoted#\"}"; unquoted="${unquoted%\"}"
        # ..-segment escape → conservative block.
        if [[ "$unquoted" =~ $_re_dotdot ]]; then
          any_ambiguous=1; matched_arg="$arg"; continue
        fi
        # BLOCK list (catastrophic paths).
        # cycle-114 FR-6: the home-root trailing-slash forms ($HOME/, ${HOME}/,
        # ~/) are catastrophic-equivalent to bare $HOME/~ and must hit BLOCK, not
        # the AMBIGUOUS fallback. A CHILD path (e.g. $HOME/projects, ~/subdir) is
        # NOT matched here and correctly falls through to AMBIGUOUS. Mirrors the
        # Claude Code 2.1.154 $HOME-trailing-slash fix.
        if [[ "$unquoted" =~ $_re_block_list ]]; then
          any_block=1; matched_arg="$arg"; break
        fi
        # ALLOW-EXCLUDE (was bypassing via `./` prefix).
        if [[ "$unquoted" =~ $_re_allow_exclude ]]; then
          any_ambiguous=1; matched_arg="$arg"; continue
        fi
        # ALLOW list (bounded subpaths).
        if [[ "$unquoted" =~ $_re_allow_list ]]; then
          continue
        fi
        # Ambiguous → conservative block.
        any_ambiguous=1; matched_arg="$arg"
      done
    fi

    [[ $any_block -eq 1 ]] && break
  done <<<"$rm_segments"

  if [[ $any_block -eq 1 ]]; then
    emit_block "FR-2-BLOCK" "$matched_arg" "rm -rf on catastrophic path '$matched_arg' (system root / home / glob / current-dir) refused. Use 'trash <path>' for a recoverable delete, or an explicit './<path>/' form scoped to a real subdirectory."
  elif [[ $any_ambiguous -eq 1 ]]; then
    emit_block "FR-2-AMBIGUOUS" "$matched_arg" "rm -rf on an unclear path '$matched_arg'. Use './path/' explicit form, 'trash', or remove targeted children."
  fi
  # else: every arg matched the allow list → fall through.
fi

# All checks passed — allow execution.
exit 0
