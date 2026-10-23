# Reviewer concerns — sprint-1 (review-r19)

Scope: pr/head.diff — sprint-255: guard register with origin and yield (guard-origins.yaml, guard-yield.sh, floor.yaml), pre-registered control arms on a record corpus (run-arms.sh, arms-report.py, seed-corpus-from-record.sh), task kinds (validate-artifact.sh sprint kinds), path-scoped rule files (rule-paths.bats), block-destructive-bash.sh changes, loa-status.sh guard surface.

Initial areas of concern (pre-read):
- block-destructive-bash.sh: any weakening of fence rules or a new bypass path; yield logic must fail closed.
- guard-yield.sh: yield must require origin + floor check; floor guards must never be yieldable.
- seed-corpus-from-record.sh / run-arms.sh: path handling, quoting, temp dirs, exit codes, grader arithmetic.
- validate-artifact.sh: kind parsing regressions on existing sprint.md files.
- Tests: assertions that cannot fail (tautologies), fixtures that don't match what the script reads.
