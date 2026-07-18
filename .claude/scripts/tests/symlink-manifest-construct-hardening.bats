#!/usr/bin/env bats

setup() {
  export TEST_ROOT="$BATS_TEST_TMPDIR/repo"
  mkdir -p \
    "$TEST_ROOT/.claude/constructs/reject-absolute" \
    "$TEST_ROOT/.claude/constructs/reject-empty" \
    "$TEST_ROOT/.claude/constructs/reject-null" \
    "$TEST_ROOT/.claude/constructs/accept"
}

@test "construct manifest rejects absolute target" {
  cat > "$TEST_ROOT/.claude/constructs/reject-absolute/.loa-construct-manifest.json" <<'JSON'
{
  "symlinks": {
    "files": [
      { "link": ".claude/constructs/reject-absolute/file.md", "target": "/tmp/file.md" }
    ]
  }
}
JSON

  source "$BATS_TEST_DIRNAME/../lib/symlink-manifest.sh"
  get_symlink_manifest ".loa" "$TEST_ROOT"

  [ "${#MANIFEST_CONSTRUCT_SYMLINKS[@]}" -eq 0 ]
}

@test "construct manifest rejects empty target" {
  cat > "$TEST_ROOT/.claude/constructs/reject-empty/.loa-construct-manifest.json" <<'JSON'
{
  "symlinks": {
    "files": [
      { "link": ".claude/constructs/reject-empty/file.md", "target": "" }
    ]
  }
}
JSON

  source "$BATS_TEST_DIRNAME/../lib/symlink-manifest.sh"
  get_symlink_manifest ".loa" "$TEST_ROOT"

  [ "${#MANIFEST_CONSTRUCT_SYMLINKS[@]}" -eq 0 ]
}

@test "construct manifest rejects null link" {
  cat > "$TEST_ROOT/.claude/constructs/reject-null/.loa-construct-manifest.json" <<'JSON'
{
  "symlinks": {
    "files": [
      { "link": null, "target": ".claude/constructs/reject-null/source.md" }
    ]
  }
}
JSON

  source "$BATS_TEST_DIRNAME/../lib/symlink-manifest.sh"
  get_symlink_manifest ".loa" "$TEST_ROOT"

  [ "${#MANIFEST_CONSTRUCT_SYMLINKS[@]}" -eq 0 ]
}

@test "construct manifest accepts bounded target" {
  cat > "$TEST_ROOT/.claude/constructs/accept/.loa-construct-manifest.json" <<'JSON'
{
  "symlinks": {
    "files": [
      { "link": ".claude/constructs/accept/file.md", "target": ".claude/constructs/accept/source.md" }
    ]
  }
}
JSON

  source "$BATS_TEST_DIRNAME/../lib/symlink-manifest.sh"
  get_symlink_manifest ".loa" "$TEST_ROOT"

  [ "${#MANIFEST_CONSTRUCT_SYMLINKS[@]}" -eq 1 ]
  [ "${MANIFEST_CONSTRUCT_SYMLINKS[0]}" = ".claude/constructs/accept/file.md:.claude/constructs/accept/source.md" ]
}
