| Rule | Why |
|------|-----|
| ALWAYS use `/run sprint-plan` or `/run sprint-N` for implementation | Ensures review+audit cycle with circuit breaker protection |
| ALWAYS create beads tasks from sprint plan before implementation (if beads available) | Tasks without beads tracking are invisible to cross-session recovery |
| ALWAYS complete the full implement → review → audit cycle | Partial cycles leave unreviewed code in the codebase |
| ALWAYS check for existing sprint plan before writing code | Prevents ad-hoc implementation without requirements traceability |
