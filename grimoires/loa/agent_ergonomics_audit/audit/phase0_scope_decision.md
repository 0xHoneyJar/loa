# Phase 0 — Scope Decision & Policy Adaptations (pass 1)

Operator directive (2026-07-11): *"as fable delegating to sufficient models for
tasks but keeping review and audit as fable to ensure fable quality please
/agent-ergonomics-and-intuitiveness-maximization-for-cli-tools applied to loa"*.

Mode: **full** (intent = "applied to" ⇒ apply, not audit-only).
Tier: **Swarm-scale surface** (373 scripts, 53 commands, 28 hooks) — Phase 4
prioritization narrows to the ~9 highest-frequency agent-facing families below;
mode stays `full` (Rule 4: size never downgrades mode).

## Delegation model (operator-mandated)

- Mechanical work (inventory, scoring drafts, corpus generation, appliers):
  **Sonnet** subagents via Workflow.
- Verdict-bearing work (score reconciliation, recommendation synthesis, review,
  audit, fresh-eyes): **Fable lead** — matches loa's own C13 rule
  (review/audit never pinned to a cheaper model).

## Policy adaptations (skill ⇄ loa CLAUDE.md; CLAUDE.md takes precedence)

| # | Skill policy | loa adaptation | Rationale |
|---|--------------|----------------|-----------|
| 1 | Axiom 1: commit directly to current branch (main), never branch | **One feature branch + PR to main** | loa's main is protected (44 required checks); repo convention across 20+ operator sessions is branch → PR → CI green → admin-merge. Axiom 1's *intent* (no orphaned side-branches, single history) is preserved: exactly one branch, folded to main via PR in the same pass. |
| 2 | Axiom 2: workspace at `<target>/agent_ergonomics_audit/` | **`grimoires/loa/agent_ergonomics_audit/`** | Still in-tree, same git history (Axiom 2 intent intact). loa's three-zone model routes state artifacts to `grimoires/`; repo root stays clean; `.claude/` is the System Zone where audit artifacts don't belong. |
| 3 | Axiom 17: regression tests in `audit/regression_tests/` | **bats tests in `.claude/scripts/tests/`** (CI "Shell Tests" job) + pointer manifest in `audit/regression_tests/` | loa CI does not execute the audit dir; putting tests where CI runs them *strengthens* the pinning intent. |
| 4 | preflight.sh expects a single `<TOOL>` binary | Skipped; per-script `--help` probes instead | loa is a script-family framework, not one binary (Variant H shape). |
| 5 | Intake questions asked verbatim | Answered from operator directive + session context | Operator's standing autonomy pattern ("proceed", "don't stop to ask"); mode/target/scope unambiguous. |

## Scope: the 9 agent-facing families (pass 1)

| Family | Representative surfaces |
|--------|------------------------|
| F1 golden-path/status | `golden-path.sh` (/loa /plan /build /review /ship routing), doctor |
| F2 beads | `beads/beads-health.sh`, beads wrappers |
| F3 knowledge | `grimoire-index.sh`, `lib/kf-write-lib.sh`, `memory-query.sh`, `repo-map-gen.sh` |
| F4 memory/qmd | `memory-admin.sh`, `qmd-sync.sh`, `memory-sync.sh` |
| F5 release | `semver-bump.sh`, `post-merge-orchestrator.sh`, `release-notes-gen.sh`, `classify-merge-pr.sh` |
| F6 validators | `validate-skill-capabilities.sh`, `verdict-derive.sh`, `butterfreezone-validate.sh` |
| F7 hook error surfaces | `block-destructive-bash.sh`, `hook-guard.sh`, zone guards (error PEDAGOGY only) |
| F8 construct/session | `construct-resolve.sh`, `session-limit-capture.sh` |
| F9 installer | `mount-loa.sh`, `mount-submodule.sh` |

## Must-not-touch (scope guardrails)

1. **Never weaken a security gate.** Hook error-message rewrites must preserve
   exit codes and blocking behavior byte-for-byte on the decision path.
2. **L1–L7 agent-network primitives** (audit chain, trust, handoffs, SOUL):
   out of scope for mutation — reference-read requirement makes them Pass-2+.
3. **cheval dispatch SoT / model catalog**: out of scope (own governance).
4. **Additive only**: new flags (`--json`, `--help`, `--robot-*`) may be added;
   no renames/removals without a deprecation path (loa fleet compatibility).
5. **No feature work** — anything that adds capability beyond the ergonomic
   surface is filed as a bead, not bundled (skill anti-pattern + loa C-PROC).
6. Copy-set files (`.claude/hooks/*`, `settings.json`) — changes must respect
   the copy-set drift gate (cycle-117 G).

## Seed findings (evidence from the live session that triggered this pass)

- **S-1 (error_pedagogy / intent_inference)**: `block-destructive-bash.sh`
  FR-2-AMBIGUOUS blocked `rm -rf "$T"` and instructed *"Use './path/' explicit
  form"* — then **also blocked** `rm -rf ./.loa/qmd/`. The error teaches a fix
  that does not work (operator session 2026-07-10, v1.196.0 release prep).
  Workaround used: `find ./.loa/qmd -mindepth 0 -delete`.
- **S-2 (composability / determinism)**: `beads-health.sh --json` reports
  DEGRADED on `jsonl_stale` computed from **mtime age** while `br sync` reports
  "JSONL is current (hash unchanged)" — same family, contradictory signals;
  agent cannot tell whether remediation is needed (this session, 2026-07-11).
- **S-3 (self_documentation)**: no `capabilities --json`-style surface exists
  for the framework script family; agents discover contracts by reading source.
