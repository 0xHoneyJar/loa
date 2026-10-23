# Reviewer concerns — sprint-1 (PR: cycle-126 sprint-250 tasks 4.1–4.8)

1. evals/graders/recall-vs-defects.sh:74 — the new bare `:N` alternative accepts a `:` preceded by `"` (only [A-Za-z0-9_./:] are excluded), so the mandatory LOA-VERDICT trailer `"counts":{"critical":0,"high":0,...}` yields bare citations (lines 0,1,2,...) bound to the last cited path. Spurious recall credit for any defect anchored in the first ~10 lines of the last-cited file.
2. evals/graders/recall-vs-defects.sh:73 — comma continuation `path:40, 3 of which` credits line 3 (prose number after a comma).
3. tests/unit/skill-capabilities.bats:850 — `yq ... | tostring` is not a Mike Farah yq v4.40 operator; SC-T-AGENT-7 fails with "invalid input text" on that yq.
4. .claude/scripts/check-permissions.sh:235 — `rule_key "$perm"` unguarded under set -e; a future non-Bash requirement aborts the preflight.
5. .claude/defaults/model-config.yaml:509 — cache_read 0.05× of input departs from the 0.1× rule on a comment-only citation.
6. .claude/loa/CLAUDE.loa.md is 10,225 B against a 10,240 B budget (15 B headroom).
