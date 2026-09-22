#!/usr/bin/env bats
# =============================================================================
# tests/unit/notes-size-guard.bats — cycle-124 Sprint 4 (PRD FR-10, AC-10.1)
#
# .claude/hooks/safety/notes-size-guard.sh — PreToolUse Write|Edit|MultiEdit|
# NotebookEdit hook. Acts only when the payload's file_path realpath-resolves to
# the grimoire's NOTES.md (LOA_GRIMOIRE_DIR is the configurable dir); denies
# (exit 2) only when the file is ≥ 200 KiB AND the write would grow it (or a
# growing write would cross the line); every other path, a missing file or an
# unparseable payload exits 0. Fail-open under hook-guard.sh.
# =============================================================================

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$PROJECT_ROOT/.claude/hooks/safety/notes-size-guard.sh"
  GUARDWRAP="$PROJECT_ROOT/.claude/hooks/hook-guard.sh"
  GEN="$PROJECT_ROOT/tests/fixtures/notes/make-large-notes.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/nsg.XXXXXX")"
  G="$T/grim"
  mkdir -p "$G"
  N="$G/NOTES.md"
  export LOA_GRIMOIRE_DIR="$G"
}

teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

# Payloads are large (hundreds of KB), well past the 128 KiB single-argument
# limit, so they travel through files exactly as the real hook input does
# (stdin), never through argv.
# run_hook <tool_name> <tool_input-json-file>
run_hook() {
  jq -c --arg t "$1" '{tool_name: $t, tool_input: .}' "$2" > "$T/payload.json"
  run bash -c '"$1" < "$2"' _ "$HOOK" "$T/payload.json"
}

# write_input <bytes> — a Write tool_input for $N whose content is that many bytes; prints the file
write_input() {
  head -c "$1" /dev/zero | tr '\0' 'x' > "$T/content"
  jq -cn --arg p "${2:-$N}" --rawfile c "$T/content" '{file_path:$p, content:$c}' > "$T/input.json"
  echo "$T/input.json"
}
# edit_input <json> — any small tool_input given inline; prints the file
edit_input() { printf '%s' "$1" > "$T/input.json"; echo "$T/input.json"; }

@test "NSG-1 Write that grows NOTES.md at 250 KiB is denied with the remedy; a shrinking Write is allowed" {
  "$GEN" "$N" 250k
  local cur; cur=$(stat -c%s "$N")
  run_hook Write "$(write_input $((cur + 100)))"
  [ "$status" -eq 2 ]
  [[ "$output" == *"NOTES-BLOCK"* ]]
  [[ "$output" == *"rotate"* ]]
  run_hook Write "$(write_input 1000)"
  [ "$status" -eq 0 ]
}

@test "NSG-2 Edit: growing denied, shrinking allowed at 250 KiB" {
  "$GEN" "$N" 250k
  run_hook Edit "$(edit_input "$(jq -cn --arg p "$N" '{file_path:$p, old_string:"D-0905", new_string:"D-0905 plus a longer replacement"}')")"
  [ "$status" -eq 2 ]
  run_hook Edit "$(edit_input "$(jq -cn --arg p "$N" '{file_path:$p, old_string:"- D-0905 newest decision — selected first", new_string:"- D-0905"}')")"
  [ "$status" -eq 0 ]
}

@test "NSG-3 Edit replace_all multiplies the delta by the occurrence count (crossing the line only with replace_all)" {
  "$GEN" "$N" 204700          # just under 200 KiB; thousands of 'pad ' occurrences
  run_hook Edit "$(edit_input "$(jq -cn --arg p "$N" '{file_path:$p, old_string:"pad ", new_string:"pad!! ", replace_all:false}')")"
  [ "$status" -eq 0 ]
  run_hook Edit "$(edit_input "$(jq -cn --arg p "$N" '{file_path:$p, old_string:"pad ", new_string:"pad!! ", replace_all:true}')")"
  [ "$status" -eq 2 ]
}

@test "NSG-4 MultiEdit sums its edits: net growth denied, net shrink allowed at 250 KiB" {
  "$GEN" "$N" 250k
  run_hook MultiEdit "$(edit_input "$(jq -cn --arg p "$N" '{file_path:$p, edits:[{old_string:"D-0905", new_string:"D-0905 and fifty more bytes of text to grow the file............"},{old_string:"D-0904 second-newest", new_string:"D-0904"}]}')")"
  [ "$status" -eq 2 ]
  run_hook MultiEdit "$(edit_input "$(jq -cn --arg p "$N" '{file_path:$p, edits:[{old_string:"D-0905", new_string:"D-0905!"},{old_string:"- D-0904 second-newest decision — selected", new_string:"- D-0904"}]}')")"
  [ "$status" -eq 0 ]
}

@test "NSG-5 other paths, a missing NOTES.md and an unparseable payload exit 0 fast" {
  "$GEN" "$G/other.md" 250k
  run_hook Write "$(write_input 300000 "$G/other.md")"
  [ "$status" -eq 0 ]
  run_hook Write "$(write_input 300000)"
  [ "$status" -eq 0 ]              # NOTES.md does not exist yet
  run bash -c 'printf "not json" | "$1"' _ "$HOOK"
  [ "$status" -eq 0 ]
  run bash -c 'printf "{}" | "$1"' _ "$HOOK"
  [ "$status" -eq 0 ]
}

@test "NSG-6 symlinked path, relative path and a custom LOA_GRIMOIRE_DIR reach the same decision" {
  "$GEN" "$N" 250k
  local cur; cur=$(stat -c%s "$N")
  ln -s "$N" "$T/link.md"
  run_hook Write "$(write_input $((cur + 100)) "$T/link.md")"
  [ "$status" -eq 2 ]
  write_input $((cur + 100)) "NOTES.md" >/dev/null
  jq -c '{tool_name:"Write", tool_input:.}' "$T/input.json" > "$T/payload.json"
  run bash -c 'cd "$3" && "$1" < "$2"' _ "$HOOK" "$T/payload.json" "$G"
  [ "$status" -eq 2 ]
  # a different custom dir: the same absolute file is no longer the grimoire's NOTES.md
  mkdir -p "$T/grim2"
  export LOA_GRIMOIRE_DIR="$T/grim2"
  run_hook Write "$(write_input $((cur + 100)))"
  [ "$status" -eq 0 ]
}

@test "NSG-7 below 200 KiB a growing Write is allowed (warn line only)" {
  "$GEN" "$N" 100k
  local cur; cur=$(stat -c%s "$N")
  run_hook Write "$(write_input $((cur + 100)))"
  [ "$status" -eq 0 ]
}

@test "NSG-8 fails open under hook-guard.sh when the hook cannot parse" {
  "$GEN" "$N" 250k
  local cur; cur=$(stat -c%s "$N")
  cp "$HOOK" "$T/broken.sh"; printf '\nif [[ ; then\n' >> "$T/broken.sh"; chmod +x "$T/broken.sh"
  write_input $((cur + 100)) >/dev/null
  jq -c '{tool_name:"Write", tool_input:.}' "$T/input.json" > "$T/payload.json"
  run bash -c '"$1" "$2" < "$3"' _ "$GUARDWRAP" "$T/broken.sh" "$T/payload.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN"* ]]
}

@test "NSG-9 settings.json wires the hook behind hook-guard.sh in the Write|Edit|MultiEdit|NotebookEdit array" {
  local cmds
  cmds=$(jq -r '.hooks.PreToolUse[] | select(.matcher=="Write|Edit|MultiEdit|NotebookEdit") | .hooks[].command' "$PROJECT_ROOT/.claude/settings.json")
  grep -q 'hook-guard.sh.*hooks/safety/notes-size-guard.sh' <<<"$cmds"
}

@test "NSG-10 the hook denies with exit 2 and never touches the file" {
  "$GEN" "$N" 250k
  cp "$N" "$T/orig"
  local cur; cur=$(stat -c%s "$N")
  run_hook Write "$(write_input $((cur + 100)))"
  [ "$status" -eq 2 ]
  cmp -s "$N" "$T/orig"
}
