# Reviewer concerns — sprint-1 (PR: cycle-129 sprint-255)

Scope: pr/head.diff (81 files): guard register (guard-yield.sh, guard-origins.yaml, floor.yaml, fence @guard markers), control arms (execute-agent.sh toggles, run-arms.sh, arms-report.py, compare-ab.py, seed-corpus-from-record.sh), task kinds (validate-artifact.sh validate_sprint_kinds, cycle-ratio.sh), path-scoped rule files.

Verified: generated hooks table byte-identical to the PR's hooks-reference.md; register --check in sync (95 guards); floor.yaml sha pin matches; bats suites guard-yield, guard-origins, validate-artifact-sprint-kinds, cycle-ratio, loa-status-guards, rule-paths, arm-toggles, arms-report, seed-corpus, execute-agent (EA-1..EA-12 minus run-eval cases) pass on a synthetic head tree.

Concerns to probe:
1. guard-yield.sh sources .claude/scripts/lib/heredoc-classifier.sh in the main shell under set -e; a lib (or anything it sources, e.g. the fence hook without a lib-only mode) that exits kills the generator silently with exit 0 and no outputs written. Reproduced when the lib sources the head fence.
2. run-arms.sh is_transport_failure greps agent-output.json for words like "network"; a failed trial whose review text mentions networking is retried as a transport failure.
3. validate_sprint_kinds: judgment heuristic (files==code or verbs script/lint/generate) — false WARNs? E2E detection regex.
4. execute-agent.sh ARM_MODE copies the prompt tree's .loa.config.yaml over the sandbox's; toggles verified absent; karpathy_block removes section to next H2 only.
5. seed-corpus-from-record.sh: binary rename path parsing in numstat; redact() rewrites tracked fixture bytes; label anchoring heuristics.
6. implementing-tasks SKILL.md zones.app.permission read -> read-write, not mentioned in PR description.
7. tasks/suites reference fixtures pr-11..pr-18, record-pairs.tsv, labels/, manifests/, corpus.tsv — none in the diff.
8. arms-report.py verdict logic: bootstrap seed, coverage gaps when a fixture has no rows, informational arm handling.
