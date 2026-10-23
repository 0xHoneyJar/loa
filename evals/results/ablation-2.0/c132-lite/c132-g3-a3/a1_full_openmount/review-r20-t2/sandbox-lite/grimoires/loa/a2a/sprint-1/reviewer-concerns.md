# Reviewer concerns (Phase 2 notes, sprint-1)

Scope: pr/head.diff — sprint-256 (implement-gate modes, run-checkpoint derive/mark, heredoc classifier fail-closed, profile-lib, karpathy surgical hook, block-destructive-bash).

Concerns to probe:
- implement-gate.sh: deny mode fallbacks, marker sanction, derived_at freshness, ordering of claim_ask vs sanction.
- run-checkpoint.sh: derive/mark/unmark correctness, atomic writes, stale_hours.
- heredoc-classifier.sh: fail-closed behaviour; false positives on legitimate heredocs.
- profile-lib.sh: knob resolution order, YAML parsing without yq, floor-key handling.
- karpathy-surgical-diff-check.sh: diff accounting, bead resolution, JSONL writes.
- block-destructive-bash.sh: new patterns; bypasses; false positives.
