# Reviewer concerns — sprint-1 (PR: cycle-126 sprint-250 tasks 4.1–4.8)

Scope: pr/head.diff (88 files). Areas the primary reviewer wants a second voice on:

1. evals/graders/recall-vs-defects.sh — new bare `:N` / `head:N` citation binding. A number after a colon that is not glued to a word (e.g. JSON `"critical":1` in the LOA-VERDICT trailer, or `port :8080`) binds to the last cited path. Confirmed by running the regex. Is this a defect in the grader or acceptable noise?
2. .claude/hooks/compliance/implement-gate.sh — new evidence recorder runs three jq invocations before the file_path check; mode now read from .loa.config.yaml via yq (opt-in `implement_gate.mode: authoritative`, deliberately undocumented per IG-11). Authoritative mode trusts model-authored tool_input.active_skill. Any bypass or state-clobber?
3. .claude/scripts/check-permissions.sh — rule_key grammar (Bash(<body>) with trailing ":*" or " *"). Bare `Bash` / `Bash(*)` rules are not recognised. Is any required rule ever non-Bash (rule_key returns 1 under set -e)?
4. .claude/defaults/model-config.yaml — claude-opus-5-5 entry: no long_context tier (vendor says 4.6+ at standard pricing) while sibling 4.6+ entries (opus-5, sonnet-5, fable-5-1) still carry a 2.0x/1.5x long_context tier. Internal contradiction?
5. .claude/scripts/model-adapter.sh — stderr capture via mktemp under set -e; only the agy WARN line is forwarded.
6. .claude/scripts/lib-content.sh — canonical-decimal index guard and control-byte stripping for log lines; verified by running the test bodies.
7. tools/check-prompt-budget.sh — CLAUDE.loa.md budget raised 9,216 → 10,240; head file is 10,225 bytes (15 bytes headroom).
8. Generated artefacts: model-config.yaml.checksum, generated-model-maps.sh (regenerated from head catalog: identical), bridgebuilder dist, SHA256SUMS all verified consistent.
