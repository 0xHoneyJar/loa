#!/usr/bin/env bats
# Tests for .gitattributes `-merge` conflict-safety on .claude/hooks/** and
# .claude/settings.json (Issue #1180 / bd-c1180-gitattributes-merge-60j1).
#
# The hazard: `git merge loa/main` (the /update-loa VENDORED flow) can splice
# literal <<<<<<< conflict markers into a LIVE hook/settings file when a
# downstream customization diverges from an upstream edit. The corrupted
# script then fails `bash -n` and every subsequent Bash call dies at
# PreToolUse. `-merge` (the git-native "binary" driver) converts a two-sided
# divergence into a reported CONFLICT (UU) that leaves the pre-merge ("ours")
# content on disk untouched and still parseable, instead of embedding
# markers — while a one-sided upstream-only edit still auto-merges cleanly.
#
# This file is deliberately kept separate from gitattributes-merge-protection.bats
# (a different theme: static merge=ours identity-file assertions, no live
# git-merge fixture).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

  # Fixture repo for the dynamic (live git-merge) tests below. Static tests
  # ignore this and query the real repo via REPO_ROOT instead.
  FIXTURE_DIR=$(mktemp -d)
  cd "$FIXTURE_DIR"
  git init -q -b main
  git config user.email test@test
  git config user.name test

  cat > .gitattributes <<'EOF'
.claude/hooks/** -merge
.claude/settings.json -merge
EOF

  mkdir -p .claude/hooks
  cat > .claude/hooks/foo.sh <<'EOF'
#!/usr/bin/env bash
echo "base version"
EOF
  chmod +x .claude/hooks/foo.sh

  cat > .claude/settings.json <<'EOF'
{"hooks": {}, "version": 1}
EOF

  git add -A
  git commit -q -m base
}

teardown() {
  cd /
  rm -rf "$FIXTURE_DIR"
}

# =============================================================================
# Static — real repo .gitattributes resolves `-merge` for the protected paths
# =============================================================================

@test "static: .claude/hooks/** resolves merge: unset (not unspecified)" {
  run git -C "$REPO_ROOT" check-attr merge -- .claude/hooks/safety/block-destructive-bash.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"merge: unset"* ]]
}

@test "static: .claude/settings.json resolves merge: unset (not unspecified)" {
  run git -C "$REPO_ROOT" check-attr merge -- .claude/settings.json
  [ "$status" -eq 0 ]
  [[ "$output" == *"merge: unset"* ]]
}

# =============================================================================
# Dynamic — live git-merge fixture, two-sided divergence
# =============================================================================

@test "dynamic: two-sided .claude/hooks divergence reports UU conflict, no markers, bash -n still passes" {
  git checkout -q -b upstream main
  cat > .claude/hooks/foo.sh <<'EOF'
#!/usr/bin/env bash
echo "upstream version"
EOF
  git commit -q -am "upstream edit"

  git checkout -q main
  cat > .claude/hooks/foo.sh <<'EOF'
#!/usr/bin/env bash
echo "local version"
EOF
  git commit -q -am "local edit"

  run git merge upstream --no-commit --no-ff
  [ "$status" -ne 0 ]

  run git status --porcelain
  [[ "$output" == *"UU .claude/hooks/foo.sh"* ]]

  run grep -c '<<<<<<<' .claude/hooks/foo.sh
  [ "$status" -ne 0 ]

  grep -qF "local version" .claude/hooks/foo.sh

  bash -n .claude/hooks/foo.sh
}

@test "dynamic: two-sided .claude/settings.json divergence reports UU conflict, no markers, still valid JSON" {
  git checkout -q -b upstream main
  cat > .claude/settings.json <<'EOF'
{"hooks": {"foo": true}, "version": 1}
EOF
  git commit -q -am "upstream settings edit"

  git checkout -q main
  cat > .claude/settings.json <<'EOF'
{"hooks": {}, "version": 2}
EOF
  git commit -q -am "local settings edit"

  run git merge upstream --no-commit --no-ff
  [ "$status" -ne 0 ]

  run git status --porcelain
  [[ "$output" == *"UU .claude/settings.json"* ]]

  run grep -c '<<<<<<<' .claude/settings.json
  [ "$status" -ne 0 ]

  jq empty .claude/settings.json
}

@test "dynamic: one-sided upstream-only edit still auto-merges cleanly (regression)" {
  git checkout -q -b upstream main
  cat > .claude/hooks/foo.sh <<'EOF'
#!/usr/bin/env bash
echo "upstream only version"
EOF
  git commit -q -am "upstream only edit"

  git checkout -q main
  run git merge upstream --no-ff -m "merge upstream"
  [ "$status" -eq 0 ]

  grep -qF "upstream only version" .claude/hooks/foo.sh
}
