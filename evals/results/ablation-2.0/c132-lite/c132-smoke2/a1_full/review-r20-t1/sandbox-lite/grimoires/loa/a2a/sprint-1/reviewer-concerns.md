# Reviewer concerns — sprint-1 (PR: cycle-129 sprint-256)

Scope: 68 files; large rewrites of karpathy-surgical-diff-check.sh, block-destructive-bash.sh
(fail-closed heredoc classifier), run-checkpoint.sh (file-authoritative run position),
implement-gate.sh (deny mode), profile-lib.sh (profiles), lint-invariants.sh, constraints generation,
prompt-budget tooling, and many SKILL.md prose edits plus bats tests.

Areas to probe:
- heredoc classifier fail-closed semantics: unterminated heredocs, quoted delimiters, nested
  redirections, `<<<` here-strings, `<<-` tabs, delimiter inside the body.
- run-checkpoint.sh derive logic: state file vs. argument precedence, missing/corrupt state,
  round numbering off-by-one, race between record-round and derive.
- implement-gate.sh deny mode: bypass paths (Bash writes), path normalisation, symlinks,
  zone matching for paths with spaces or relative segments.
- profile-lib.sh: knob resolution order (env > config > profile > default), floor enforcement,
  malformed YAML, missing profiles.yaml.
- karpathy-surgical-diff-check.sh: diff parsing with renames/binaries, bead id derivation,
  JSONL append atomicity, exit code on error paths.
- test coverage: assertions that cannot fail, tests that only test the fixture, missing
  negative cases.
- docs/skill prose consistent with the mechanics now implemented (stale references, wrong flag names).
