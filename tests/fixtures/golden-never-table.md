| Rule | Why |
|------|-----|
| NEVER write application code outside of `/implement` skill invocation (OR when a construct with declared `workflow.gates` owns the current workflow) | Code written outside `/implement` bypasses review and audit gates |
| NEVER use Claude's `TaskCreate`/`TaskUpdate` for sprint task tracking when beads (`br`) is available | Beads is the single source of truth for task lifecycle; TaskCreate is for session progress display only |
| NEVER skip from sprint plan directly to implementation without `/run sprint-plan`, `/run sprint-N`, or `/bug` triage (OR when a construct with `workflow.gates` declares pipeline composition) | `/run` wraps implement+review+audit in a cycle loop with circuit breaker. `/bug` produces a triage handoff that feeds directly into `/implement`. |
| NEVER skip `/review-sprint` and `/audit-sprint` quality gates (Yield when construct declares `review: skip` or `audit: skip`) | These are the only validation that code meets acceptance criteria and security standards |
| NEVER use `/bug` for feature work that doesn't reference an observed failure | `/bug` bypasses PRD/SDD gates; feature work must go through `/plan` |
| NEVER implement code directly when `/spiraling` is invoked with a task — dispatch through the harness pipeline (`/run sprint-plan`, `/simstim`, or `spiral-harness.sh`) | `/spiraling` loads as context, not as an orchestrator. Without mechanical dispatch, the agent bypasses all quality gates (Flatline, Review, Audit, Bridgebuilder) — the fox-guarding-the-henhouse antipattern that the harness was built to prevent. |
