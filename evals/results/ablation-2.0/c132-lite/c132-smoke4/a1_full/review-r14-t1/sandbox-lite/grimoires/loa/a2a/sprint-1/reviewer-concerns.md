# Reviewer concerns — sprint-1 (PR: cycle-126 sprint-250 tasks 4.1–4.8)

1. evals/graders/recall-vs-defects.sh (1.1.0): the new bare `:N` citation alternative matches JSON pairs inside the LOA-VERDICT trailer (`"critical":0`, `"low":2`), producing phantom citations at lines 0–2 of the last cited path. Reproduced: a defect anchored at line 3 is credited although never cited; base grader 1.0.0 does not credit it.
2. .claude/data/agent-types.yaml lists eight agent types; a read-only `chart-researcher` agent definition exists in `.claude/agents/` on this install and is not listed, which would fail SC-T-AGENT-7's "every project agent is listed" loop.
3. .claude/loa/CLAUDE.loa.md is 10,225 B against the raised 10,240 B budget (15 B headroom).
4. implement_gate.mode: authoritative is an intentionally undocumented config key (IG-11 asserts it stays out of docs) that lets a model-authored tool_input.active_skill allow App Zone writes.
5. check-permissions.sh rule_key: base derivation for an exact (`=`) requirement key yields `*=cmd`; no exact requirement exists today, so dead path.
6. No CHANGELOG entry in the diff although a commit message references the CHANGELOG.
