# Reviewer concerns — sprint-1 (PR: cycle-129 sprint-256)

Scope: pr/head.diff (68 files). Focus areas for dissent:

1. implement-gate.sh deny mode: read_position() only checks derived_at freshness, not state; a cache
   with state RUNNING but stale/absent timestamps.last_activity yields a DENY whose reason says
   "derived position: RUNNING". Does run-checkpoint.sh derive always stamp last_activity?
2. implement-gate.sh marker sanction: check_implement_marker requires started_at within 7200 s; an
   /implement session longer than two hours loses sanction unless the marker is refreshed.
3. block-destructive-bash.sh heredoc consumer classifier: fail-closed claim — any consumer shapes
   (eval, source, env bash, sudo bash, ssh, xargs, process substitution, $(cat <<EOF) into eval,
   heredoc into a variable later executed) that classify as nonexec?
4. heredoc-classifier.sh sources the 2689-line fence with BDB_LIB_ONLY=1: does the fence's main body,
   set -e, or exit paths run when sourced?
5. profile-lib.sh: floor-glob construction, explicit false handling, cache staleness, missing floor.yaml.
6. run-checkpoint.sh: derive/record-round/mark/unmark lifecycle; atomic writes; derived_at and
   timestamps consistency with implement-gate.sh; stale_hours parsing.
7. karpathy-surgical-diff-check.sh shrink from ~1000 to 208 lines: behaviours tests still expect.
8. Removed C-TEAM constraints from constraints.json vs generated blocks in CLAUDE.loa.md / docs.
9. SKILL.md allowed-tools must literally permit the new profile-lib.sh knob calls.
