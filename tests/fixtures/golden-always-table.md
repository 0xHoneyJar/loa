| Rule | Why |
|------|-----|
| ALWAYS use `/run sprint-plan`, `/run sprint-N`, or `/bug` for implementation | Ensures review+audit cycle with circuit breaker protection. `/bug` enforces the same cycle for bug fixes. |
| ALWAYS create beads tasks from sprint plan before implementation (if beads available) | Tasks without beads tracking are invisible to cross-session recovery |
| ALWAYS complete the full implement → review → audit cycle | Partial cycles leave unreviewed code in the codebase |
| ALWAYS check for existing sprint plan before writing code (Yield when construct declares `sprint: skip`) | Prevents ad-hoc implementation without requirements traceability |
| ALWAYS validate bug eligibility before `/bug` implementation | Prevents feature work from bypassing PRD/SDD gates via `/bug`. Must reference observed failure, regression, or stack trace. |
| ALWAYS Read a state artifact (NOTES.md, a2a/ docs, MEMORY.md, contracts/*.yaml — any existing file) before Write/Edit | The Write tool rejects writes to un-Read existing files (~570 errors/month fleet-wide, issue #1177 item F) and blind writes clobber cross-session state. |
