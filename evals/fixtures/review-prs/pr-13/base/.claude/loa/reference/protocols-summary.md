# Protocols Summary

Complete index of `.claude/protocols/` (one row per file — regenerate this table when adding/removing protocols; cycle-121 replaced the old partial table + prose restatements, which covered 20 of 57 files and had drifted).

| File | Purpose | Loaded by |
|------|---------|-----------|
| `agent-ergonomics.md` | Mechanical agent hygiene: wait-loops, cd discipline, fan-out budgets | CLAUDE.loa.md Karpathy section pointer |
| `beads-integration.md` | br task lifecycle command reference | implementing-tasks / reviewing-code beads_workflow blocks |
| `beads-preflight.md` | Beads health statuses, opt-out, MIGRATION_NEEDED repair (KF-005/014/022 recovery) | CLAUDE.loa.md Beads-First section |
| `change-validation.md` | Post-change validation sweeps | validate command flow |
| `citations.md` | Word-for-word citation format; self-audit (≥0.95 ratio); negative grounding (two-query absence); EDD scenarios | implementing-tasks + reviewing-code resources |
| `constructs-integration.md` | Loa Constructs skill loading | constructs command flow |
| `continuous-learning.md` | Learning-signal quality gates | continuous-learning skill; retrospective postludes |
| `cross-platform-shell.md` | bash/zsh/BSD portability rules (KF-012 class) | CI shell-compat-lint; shell authors |
| `danger-level.md` | Skill danger-level taxonomy | danger-level-enforcer.sh documentation |
| `feedback-loops.md` | Review/audit quality-gate loop semantics | review/audit flows |
| `flatline-protocol.md` | Multi-model adversarial review pipeline | flatline skills + orchestrator docs |
| `git-safety.md` | Upstream-detection layers, template protection | git-safety.sh; mounting flows |
| `grounding-enforcement.md` | Grounding-ratio enforcement detail (gated deletion — see cycle-121 Scope Contract) | ck-family survivors; review skills |
| `helper-scripts.md` | Comprehensive script documentation | scripts-reference.md pointer |
| `implementation-compliance.md` | C-PROC enforcement checklist (generated from constraints.json) | CLAUDE.loa.md Process Compliance pointer |
| `input-guardrails.md` | Guardrails orchestrator detail (PII/injection/danger) | guardrails-reference.md; skill preludes |
| `karpathy-principles.md` | Enforcement map + config keys (canonical TEXT lives in CLAUDE.loa.md) | implementing-tasks pointer; CLAUDE.loa.md pointer |
| `recommended-hooks.md` | Optional Claude Code hook patterns | hooks-reference.md; operators |
| `ride-translation.md` | /ride codebase-translation flow | riding-codebase skill |
| `safe-file-creation.md` | Write-tool-vs-heredoc decision tree | shell-conventions.md pointer; implementing-tasks |
| `session-continuity.md` | Tiered recovery (L1/L2/L3), fork detection | structured-memory.md pointer; skills' context_discipline |
| `structured-memory.md` | NOTES.md contract: where durable knowledge goes, required sections, write discipline | notes-template tests; NOTES.md.template pointer |
| `subagent-invocation.md` | Subagent dispatch patterns | parallel-execution sections of skills |
| `synthesis-checkpoint.md` | Pre-clear validation (BLOCKING, 7-step) | check-loa v0.9.0 required; context_discipline |
| `tool-result-clearing.md` | Clearing thresholds + 4-step synthesis + edge cases | 10 skills' context_discipline blocks; validate-ck-integration required |
| `trajectory-evaluation.md` | ADK-style reasoning audit trail | implementing-tasks + reviewing-code resources |
| `visual-communication.md` | Mermaid diagram standards | review feedback authoring |
