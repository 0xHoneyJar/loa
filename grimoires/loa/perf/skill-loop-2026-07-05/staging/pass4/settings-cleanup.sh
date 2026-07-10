#!/usr/bin/env bash
# settings-cleanup.sh — Clean settings.local.json after each session (SDD §2.3)
# Trigger: Stop event (async, fail-open)
# Closes: #339
#
# perf pass-4 (2026-07-05, skill-loop): redundant-I/O elimination on the
# >64KB path. Was: jq x6 (extract allow + length + pattern-array build +
# filter + length + rewrite) + grep x12-24 post-scan + date + dirname +
# mkdir ≈ 35 spawns / ~90-155ms per Stop. Now: stat + jq x3 + mv (+ mkdir
# only when .run is missing) ≈ 5 spawns:
#   - jq#1 (analysis) replicates the ENTIRE old extract→gate→reparse→count→
#     filter pipeline in one pass, emitting NUL-delimited
#     status/original/filtered_count/filtered-array. Old intermediate
#     semantics preserved exactly: `jq -r` RENDERED the allow value and bash
#     compared the rendering against ""/"null"/"[]" (so an empty-string,
#     "null"-string or "[]"-string allow exits like an empty array — the $a1
#     gate), then downstream jq calls RE-PARSED that rendering (so a
#     string-typed allow containing JSON was silently promoted to that JSON
#     value — replicated by the type=="string" fromjson branch; fromjson
#     failure == the old downstream parse-error → fail-open exit 0, no
#     write; jq `length` on the reparsed value keeps old semantics, e.g.
#     abs() for numbers, key-count for objects).
#   - The filter expression (length<=200 / test("\n") / credential-any /
#     unique) is byte-for-byte the old program — ordering (unique's sort)
#     and codepoint-length semantics unchanged.
#   - jq#2 (writer) is the UNCHANGED old writer command, so the rewritten
#     file's bytes are identical by construction ($filtered is passed
#     compact instead of pretty; --argjson parses both to the same value).
#   - jq#3 (post-scan) replaces the 12-24 grep spawns. grep's reference
#     semantics are LINE-model: "some line matches". For any pattern that
#     cannot match a newline character, a whole-text test is exactly
#     equivalent (a match lies within one line ⇔ some line matches) and is
#     ~8x faster than per-line any() in Oniguruma (profiled 17.7 → 2.3 ms
#     on the 901-entry fixture). A pattern is scanned per-line (reference
#     model) whenever it COULD match \n or carries line anchors —
#     conservatively detected as: a negated class "[^", any
#     backslash-letter escape (\s \n \d \w ... — note "\." is
#     backslash-DOT and stays whole-text-safe: neither it, positive
#     classes, literals, nor Oniguruma's default "." can match \n), or a
#     ^/$ anchor. Of the 12 patterns only '://[^:]+:[^@]+@' triggers the
#     line model. The 12 patterns use only char-class/quantifier constructs
#     that behave identically in PCRE (grep -qP), POSIX ERE (grep -qE
#     fallback) and Oniguruma (jq test) — host-verified hit-for-hit against
#     the grep pair. The scanned file is always jq#2 output (valid UTF-8),
#     so raw-byte vs UTF-8 reading cannot diverge.
#     PRESERVED DEFECT (behavior parity, found by pass-4 differential
#     testing): the old `grep -qP "$pat" || grep -qE "$pat"` calls passed
#     the pattern as the FIRST argument without `--`, so the one pattern
#     beginning with "-" ('-----BEGIN .* PRIVATE KEY') was parsed as
#     options — both greps exited 2 (silenced) and that pattern could NEVER
#     produce a post-scan warning, on GNU and BSD grep alike. Replicated
#     here (leading-dash patterns report no-match) so this pass stays
#     purely behavior-preserving; the real fix (warn on remaining private
#     keys) needs its own test-first /bug cycle.
#   - CREDENTIAL_PATTERNS stays the ONE source of truth (BB-201); it is
#     passed to both jq programs newline-joined via printf -v (no spawn),
#     re-split with the same split/select the old `printf | jq -R -s`
#     construction used.
#   - audit_log: bash strftime replaces the date spawn (byte-identical
#     format, pass-2 precedent); a [[ -d ]] guard skips the dirname+mkdir
#     spawns when .run exists (falls back to the old command otherwise).
#   - Fail-open shape preserved: trap-ERR + pipefail untouched; every
#     analysis failure (malformed JSON, non-iterable allow, multi-document
#     file) exits 0 WITHOUT writing, exactly as before. Accepted divergence
#     (out-of-contract inputs only; no-write parity proven by differential
#     corpus): the old code leaked jq/bash-arithmetic noise on stderr for
#     garbage-typed allow values where the new code exits silently.
#   - The <64KB early-exit path (file check + stat threshold check) is
#     byte-for-byte untouched.

# Fail-open: never delay exit
trap 'exit 0' ERR

set -o pipefail

SETTINGS_FILE=".claude/settings.local.json"
AUDIT_LOG=".run/audit.jsonl"
SIZE_THRESHOLD=65536  # 64KB — skip cleanup for small files

# Credential patterns (SDD §2.3, Flatline IMP-004)
CREDENTIAL_PATTERNS=(
    'AKIA[A-Z0-9]{16}'
    'ghp_[a-zA-Z0-9]{36}'
    'gho_[a-zA-Z0-9]{36}'
    'ghs_[a-zA-Z0-9]{36}'
    'ghr_[a-zA-Z0-9]{36}'
    'eyJ[a-zA-Z0-9_-]*\.'
    '://[^:]+:[^@]+@'
    'Bearer [a-zA-Z0-9_.-]+'
    'sk-[a-zA-Z0-9]{20,}'
    'xoxb-[a-zA-Z0-9-]+'
    'xoxp-[a-zA-Z0-9-]+'
    '-----BEGIN .* PRIVATE KEY'
)

log() {
    echo "[settings-cleanup] $*" >&2
}

audit_log() {
    local event="$1" detail="$2"
    local ts
    # perf pass-4: bash strftime replaces the date spawn (byte-identical
    # format); [[ -d ]] guard skips dirname+mkdir when .run already exists.
    TZ=UTC0 printf -v ts '%(%Y-%m-%dT%H:%M:%SZ)T' -1
    [[ -d "${AUDIT_LOG%/*}" ]] || mkdir -p "$(dirname "$AUDIT_LOG")"
    printf '{"timestamp":"%s","event":"%s","detail":%s}\n' \
        "$ts" "$event" "$detail" >> "$AUDIT_LOG"
}

# --- Main ---

# Check file exists
if [[ ! -f "$SETTINGS_FILE" ]]; then
    exit 0
fi

# Size check — exit early if below threshold
file_size=$(stat -c%s "$SETTINGS_FILE" 2>/dev/null || stat -f%z "$SETTINGS_FILE" 2>/dev/null || echo "0")
if [[ "$file_size" -lt "$SIZE_THRESHOLD" ]]; then
    exit 0
fi

# Validate jq is available
if ! command -v jq >/dev/null 2>&1; then
    log "WARNING: jq not found, skipping cleanup"
    exit 0
fi

# Credential patterns, newline-joined for jq (single source: the array above).
printf -v CRED_JOINED '%s\n' "${CREDENTIAL_PATTERNS[@]}"

# jq#1 — single analysis pass (see header). Emits NUL-delimited fields:
#   "OK" original_count filtered_count filtered_json   (proceed)
#   "SKIP"                                             (old empty/null/[] gate)
#   "ERR"                                              (old fail-open paths)
# Parse failure emits nothing (0 fields) — the old silenced-jq exit-0 path.
mapfile -d '' -t _sc < <(
    jq -j --arg pats "$CRED_JOINED" '
        ([0] | implode) as $z |
        ($pats | split("\n") | map(select(length > 0))) as $patterns |
        (try [ .permissions.allow ] catch null) as $aw |
        if $aw == null then "ERR" + $z
        else
          (($aw[0]) // []) as $a1 |
          if ($a1 == [] or $a1 == "" or $a1 == "null" or $a1 == "[]") then "SKIP" + $z
          else
            (try [ (if ($a1 | type) == "string" then ($a1 | fromjson) else $a1 end) ] catch null) as $a2w |
            if $a2w == null then "ERR" + $z
            else
              $a2w[0] as $a2 |
              (try [ ($a2 | length) ] catch null) as $ocw |
              if $ocw == null then "ERR" + $z
              else
                (try [ ($a2 | map(select(
                    (length <= 200) and
                    (test("\n") | not) and
                    (. as $entry | [$patterns[] | . as $pat | ($entry | test($pat))] | any | not)
                  )) | unique) ] catch null) as $fw |
                if $fw == null then "ERR" + $z
                else
                  "OK" + $z + ($ocw[0] | tostring) + $z
                       + ($fw[0] | length | tostring) + $z
                       + ($fw[0] | tojson) + $z
                end
              end
            end
          end
        end
    ' "$SETTINGS_FILE" 2>/dev/null
)

# Exactly 4 fields with OK status = the old "proceed to filter" state; every
# other shape (SKIP, ERR, parse failure, multi-document file) exited 0
# without writing in the old pipeline too.
[[ "${#_sc[@]}" -eq 4 && "${_sc[0]}" == "OK" ]] || exit 0
original_count="${_sc[1]}"
filtered_count="${_sc[2]}"
filtered="${_sc[3]}"
# Defensive: counts are always integers when status is OK (a non-iterable
# allow value fails the filter step and never reaches OK).
[[ "$original_count" =~ ^[0-9]+$ && "$filtered_count" =~ ^[0-9]+$ ]] || exit 0

removed_count=$((original_count - filtered_count))

if [[ "$removed_count" -eq 0 ]]; then
    exit 0
fi

# Write filtered array back via temp file + atomic rename
tmp_file="${SETTINGS_FILE}.cleanup-tmp"
jq --argjson filtered "$filtered" '.permissions.allow = $filtered' "$SETTINGS_FILE" > "$tmp_file"
mv "$tmp_file" "$SETTINGS_FILE"

log "Cleaned $removed_count entries from permissions.allow ($original_count → $filtered_count)"

# Post-cleanup scan: check for remaining suspected secrets (BB-201: derive from CREDENTIAL_PATTERNS)
# Uses the same source array as the main filter — single source of truth.
# jq#3 replaces the per-pattern grep pair (see header: line-model + regex
# dialect equivalence host-verified). One "0"/"1" per pattern, in order.
scan_hits=$(jq -Rrs --arg pats "$CRED_JOINED" '
    ($pats | split("\n") | map(select(length > 0))) as $patterns |
    . as $txt |
    ($txt | split("\n")) as $lines |
    [ $patterns[] | . as $pat |
      (if ($pat | startswith("-"))
       then false                              # preserved defect (see header)
       elif (($pat | test("\\[\\^")) or ($pat | test("\\\\[a-zA-Z]")) or ($pat | test("[\\^$]")))
       then any($lines[]; test($pat))          # line model (reference)
       else ($txt | test($pat)) end)           # whole-text, provably ==
      | if . then "1" else "0" end ] | join("")
' "$SETTINGS_FILE" 2>/dev/null) || scan_hits=""

remaining_suspects=0
_pi=0
for pat in "${CREDENTIAL_PATTERNS[@]}"; do
    if [[ "${scan_hits:$_pi:1}" == "1" ]]; then
        log "WARNING: Suspected secret pattern '$pat' still present after cleanup"
        remaining_suspects=$((remaining_suspects + 1))
    fi
    _pi=$((_pi + 1))
done

# Log summary to audit file
audit_log "settings_cleanup" "$(printf '{"original":%d,"filtered":%d,"removed":%d,"remaining_suspects":%d,"file_size":%d}' \
    "$original_count" "$filtered_count" "$removed_count" "$remaining_suspects" "$file_size")"

exit 0
