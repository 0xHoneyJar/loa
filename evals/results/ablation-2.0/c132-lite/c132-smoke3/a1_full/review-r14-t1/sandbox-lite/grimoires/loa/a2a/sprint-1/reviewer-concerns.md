# Reviewer concerns — sprint-1 (PR: cycle-126 sprint-250 tasks 4.1–4.8)

Scope: 88 files; catalog `opus` → claude-opus-5-5, `cheap` → claude-sonnet-5; model-permissions rows for every Anthropic entry;
implement-gate rewrite (heuristic default, undocumented `implement_gate.mode: authoritative` opt-in, evidence recorder);
check-permissions.sh rule grammar (`Bash(x:*)` ≡ `Bash(x *)`); flatline script defaults → catalog aliases; eval grader 1.1.0;
Task 4.8 revert of the CLAUDE.loa.md trim and twelve constraint rationales; prompt-budget limit 9,216 → 10,240 B.

Concerns found so far:
1. constraints.json restores the five C-TEAM-00x `why` texts, but the rendered `agent_teams_constraints` block in
   .claude/loa/CLAUDE.loa.md (marked "DO NOT EDIT — generated", hash c020-teamcreate) still carries the short text.
   generate-constraints.sh --validate-only reports the section STALE; regenerating it makes CLAUDE.loa.md 10,715 B,
   over the 10,240 B budget this PR sets in tools/check-prompt-budget.sh. IDR-4 only checks the seven C-PROC rows.
2. implement-gate.sh authoritative branch (opt-in) still trusts model-authored tool_input.active_skill and silently
   allows App-Zone writes on `implement|bug|run|simstim`; the PR itself documents that the field is model-authored.
3. check-permissions.sh: for a requirement without a wildcard, `base="*${key#\*}"` yields a key like "*=git push";
   harmless today (all requirements are wildcard) but the grammar comment claims generic coverage.
4. CLAUDE.loa.md is 10,225 B against a 10,240 B limit — 15 bytes of headroom.
5. tests/fixtures/prompt-budget/{over,under} sentinels not updated for the new 10,240 B limit (not in the diff; unverifiable here).
6. model-adapter.sh: `mktemp` under `set -e` with no fallback — a failed mktemp aborts the shim without the usual error line.
