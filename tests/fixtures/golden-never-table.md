| Rule | Why |
|------|-----|
| NEVER write application code outside of `/implement` skill invocation | Code written outside `/implement` bypasses review and audit gates |
| NEVER use Claude's `TaskCreate`/`TaskUpdate` for sprint task tracking when beads (`br`) is available | Beads is the single source of truth for task lifecycle; TaskCreate is for session progress display only |
| NEVER skip from sprint plan directly to implementation without `/run sprint-plan` or `/run sprint-N` | `/run` wraps implement+review+audit in a cycle loop with circuit breaker |
| NEVER skip `/review-sprint` and `/audit-sprint` quality gates | These are the only validation that code meets acceptance criteria and security standards |
