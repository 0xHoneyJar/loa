# Reviewer concerns — sprint-1 (PR: cycle-126 sprint-250 tasks 4.1–4.8)

Scope: `pr/head.diff` (88 files). `pr/head/` holds only the non-dotfile files; `.claude/` and
`.loa.config.yaml.example` changes were reviewed from the diff and the workspace `.claude/` tree
(which carries the PR's `.claude/` files except the Python adapter package, whose snapshot is
incoherent and could not be exercised).

## Concerns to dissent on

1. `evals/graders/recall-vs-defects.sh:71-90` — the 1.1.0 citation parser's bare `:N` alternative
   uses the lookbehind `(?<![A-Za-z0-9_./:])`, which does not exclude `"`, `'`, `}`, `]` or `)`.
   Any JSON after a cited path — including the LOA-VERDICT trailer every graded review carries
   (`"critical":0,"high":0,"medium":7`) — yields bare citations bound to the last cited file.
   Reproduced: `c.sh:100 is odd.` + a trailer with `"medium":7` credits a defect anchored at
   `c.sh:7`; `d.sh:300 … {"line":1,"count":2}` credits a defect anchored at `d.sh:2`.
2. `.claude/data/constraints.json:1235-1320` (C-TEAM-001..005 rationales reverted) vs
   `.claude/loa/CLAUDE.loa.md:124-131` — the rendered `agent_teams_constraints` block still
   carries the trimmed text; `generate-constraints.sh --validate-only` reports STALE (stored
   `c020`, expected `19641576807c2086`). Pre-existing at base, but the PR edits exactly these
   five rationales and its IDR-4 test only covers the seven C-PROC rows.
3. `.claude/data/agent-types.yaml` lists three project agents; the review tree also has
   `.claude/agents/chart-researcher.md`, so `SC-T-AGENT-7`'s completeness loop fails here.
4. `.claude/hooks/compliance/implement-gate.sh` evidence recorder and the `yq`-read opt-in —
   any way `.run/` or a model-authored payload can still select authoritative mode?
5. `.claude/scripts/check-permissions.sh` `rule_key` grammar — any rule shape where a narrower
   deny suppresses a generic requirement, or an exact rule is credited as a wildcard?
6. `.claude/defaults/model-config.yaml:470-510` — Opus 5.5 entry: pricing, ceiling, fallback
   chain, missing `long_context` tier; the `loa:shortcut` comment calls Opus 5's bound
   "measured" while Opus 5's calibration source is `kf_derived`.
7. `tests/fixtures/ensure_license_fixtures.sh` freshness guard — sourced and executed contexts.
8. `.claude/scripts/model-adapter.sh:655-660` stderr capture — anything leaked or lost?
