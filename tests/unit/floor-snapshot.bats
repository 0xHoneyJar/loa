#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# =============================================================================
# tests/unit/floor-snapshot.bats — cycle-129 Sprint 1 (PRD AC-1.5, SDD §1.6, D-9.2)
# The floor does not move: every floor_files entry of .claude/data/floor.yaml
# and the fence-corpus rows named under floor_corpus are byte-identical to
# origin/main; the register disables nothing, so the .claude/settings.json hook
# registrations and the fence's pattern-id call-site list are identical too.
# Skipped, with a message, when origin/main is not reachable (a shallow CI
# checkout); the floor.yaml sha256 pin in guard-origins.bats still runs there.
# =============================================================================

setup() {
  export LOA_AUDIT_REPLAY=1
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
  FLOOR="$ROOT/.claude/data/floor.yaml"
  if ! git -C "$ROOT" rev-parse --verify -q 'origin/main^{commit}' >/dev/null 2>&1; then
    skip "origin/main is not reachable from this checkout (shallow clone?): the floor snapshot needs it — run 'git fetch origin main'"
  fi
  BASE="$(git -C "$ROOT" rev-parse 'origin/main^{commit}')"
}

base_show() { git -C "$ROOT" show "$BASE:$1"; }

@test "FS-1 every floor_files entry is byte-identical to origin/main" {
  n=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    n=$((n + 1))
    git -C "$ROOT" cat-file -e "$BASE:$f" || { echo "$f is not on origin/main" >&2; false; }
    base_show "$f" | cmp -s - "$ROOT/$f" || { echo "floor file $f differs from origin/main" >&2; false; }
  done < <(yq -r '.floor_files[]' "$FLOOR")
  [ "$n" -ge 4 ]
}

@test "FS-2 the fence-corpus rows named in floor_corpus (FR-1.2b, FR-SZ*) are identical to origin/main" {
  corpus="$(yq -r '.floor_corpus.file' "$FLOOR")"
  rules="$(yq -o=json -I0 '.floor_corpus.rules' "$FLOOR")"
  sel='def m($r): $r | any(.[]; . as $p | if ($p | endswith("*")) then ($in.rule // "" | startswith($p | rtrimstr("*"))) else ($in.rule // "") == $p end);
       . as $in | select(m($rules))'
  diff <(base_show "$corpus" | jq -c --argjson rules "$rules" "$sel") <(jq -c --argjson rules "$rules" "$sel" "$ROOT/$corpus")
}

@test "FS-3 the register disables nothing: settings.json hook registrations are identical to origin/main" {
  diff <(base_show .claude/settings.json | jq -c '.hooks') <(jq -c '.hooks' "$ROOT/.claude/settings.json")
}

@test "FS-4 the fence's pattern-id call-site list (in order) is identical to origin/main" {
  ids() { grep -oE 'emit_block "[A-Za-z0-9._-]+"|pattern_id(: |=)"[A-Za-z0-9._-]+"'; }
  diff <(base_show .claude/hooks/safety/block-destructive-bash.sh | ids) <(ids < "$ROOT/.claude/hooks/safety/block-destructive-bash.sh")
}

@test "FS-5 the live permission deny list (policy:permission-deny-list) is identical to origin/main" {
  # review r1 DISS-C-003: floor_files pins the deny template, not the live rules
  diff <(base_show .claude/settings.json | jq -c '.permissions.deny') <(jq -c '.permissions.deny' "$ROOT/.claude/settings.json")
}

@test "FS-6 every floor gate implemented as a hook is registered in settings.json" {
  # review r1 DISS-C-003: a gate present on disk but unregistered never runs
  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    grep -qF -- "$s" "$ROOT/.claude/settings.json" || { echo "floor gate script $s is not registered in settings.json" >&2; return 1; }
  done < <(yq -r '.guards[] | select(.floor == true and .kind == "gate") | .script' "$ROOT/.claude/data/guard-origins.yaml" | grep '^\.claude/hooks/' | sed 's#^\.claude/##')
}
