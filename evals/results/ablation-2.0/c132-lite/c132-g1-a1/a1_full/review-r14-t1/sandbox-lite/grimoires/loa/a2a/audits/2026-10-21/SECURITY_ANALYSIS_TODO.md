# Security analysis working file — sprint-1 audit (task review-r14), 2026-10-21

Scope: pr/head.diff (88 files). Trust levels: MODEL = model-authored tool_input / LLM output; OPERATOR = .loa.config.yaml, settings.json; REPO = checked-in catalog/data; EXTERNAL = provider stderr.

| # | Source / sink | file:line (head) | Trust | Status | Note |
|---|---------------|------------------|-------|--------|------|
| 1 | tool_input.active_skill → allow decision | .claude/hooks/compliance/implement-gate.sh:123-129 | MODEL | CONFIRMED | opt-in authoritative branch trusts a model-authored field (MED) |
| 2 | tool_input.active_skill → .run/platform-features.json write | implement-gate.sh:40-50 | MODEL | SAFE | fixed strings + timestamp, mktemp+mv, once; detector keeps only the same two keys |
| 3 | $active_skill / $file_path → stderr echo | implement-gate.sh:134 | MODEL | N/A | pre-existing (base:171), unchanged |
| 4 | .loa.config.yaml implement_gate.mode → mode | implement-gate.sh:114-116 | OPERATOR | PARTIAL | silent heuristic when yq absent (LOW) |
| 5 | settings.json allow/deny → rule_key keys | .claude/scripts/check-permissions.sh:162-173,197-204 | OPERATOR | SAFE | assoc-array keys, no arithmetic; `|| continue` guards |
| 6 | REQUIRED_* → rule_key under set -e | check-permissions.sh:235 | REPO | CONFIRMED | latent abort on first non-Bash requirement (MED) |
| 7 | exact requirement → base key | check-permissions.sh:237 | REPO | CONFIRMED | `*=git` never matches (LOW, latent) |
| 8 | review.md text → citation regex | evals/graders/recall-vs-defects.sh:71-92 | MODEL | CONFIRMED | bare `:N` credits trailer / quoted JSON keys (HIGH) |
| 9 | agent-types.yaml → WRITE_CAPABLE_AGENTS | .claude/scripts/validate-skill-capabilities.sh:110-117 | REPO | SAFE | regex allowlist on names; fallback general-purpose |
| 10 | cheval stderr → caller stderr | .claude/scripts/model-adapter.sh:655-659 | EXTERNAL | SAFE | one fixed-prefix line, 600 chars, mktemp file removed |
| 11 | platform-features.json → /loa line | .claude/scripts/detect-platform-features.sh:30-37 | REPO(.run) | SAFE | control chars stripped, cut 120 |
| 12 | top_path → log | .claude/scripts/lib-content.sh:295 | MODEL(diff) | SAFE | C0/DEL stripped |
| 13 | fixture JSON field → grep | tests/fixtures/ensure_license_fixtures.sh:47-55 | REPO | SAFE | $2 is a literal from the caller |
| 14 | catalog claude-opus-5-5 pricing/long_context | .claude/defaults/model-config.yaml:474-478,562 | REPO | CONFIRMED | two pricing models from one vendor sentence (MED) |
| 15 | fallback chain → anthropic:claude-headless | model-config.yaml:485-488 | REPO | N/A | pre-existing on every Anthropic entry (base has 10) |
| 16 | model-permissions claude-headless row | .claude/data/model-permissions.yaml:~447-470 | REPO | SAFE | informational unless context_filtering on; caveat stated in notes |
| 17 | agent_teams_constraints generated block | .claude/loa/CLAUDE.loa.md:124-131 | REPO | CONFIRMED | STALE per generate-constraints.sh --validate-only (LOW) |
| 18 | LOA_LIMIT 10,240 vs 10,225 B | tools/check-prompt-budget.sh:53 | REPO | CONFIRMED | 15 B headroom (LOW) |
| 19 | SC-T-AGENT-7 yq expression | tests/unit/skill-capabilities.bats:850 | REPO | CONFIRMED | `tostring` rejected by mikefarah yq v4.40.5 (MED) |
| 20 | tier_aliases example pin | .loa.config.yaml.example:2717 | REPO | CONFIRMED | `anthropic: claude-opus-5` after opus → 5-5 (LOW) |
| 21 | hook-guard fail-open on parse error | .claude/hooks/hook-guard.sh:46-49 | REPO | N/A | message-only change; design pre-existing |
| 22 | Bridgebuilder dist/manifest, catalog checksum, fixture SHA256SUMS | various | REPO | SAFE | all hashes verified against head files |

Deferred: none. Scope limits: grimoires/loa/known-failures.md absent (ICM surface degraded); Python adapter tests not runnable here (overlay package revision differs); tsx/cheval-dependent bats not run.
