| Rule | Why |
|------|-----|
| ALWAYS route implementation through `/run sprint-plan`, `/run sprint-N`, or `/bug`, checking for the existing sprint plan first | Keeps implement→review→audit, the circuit breaker and requirements traceability; implement-gate.sh asks on ungated App-Zone writes. |
| ALWAYS create beads tasks from sprint plan before implementation (if beads available) | Tasks without beads tracking are invisible to cross-session recovery |
| ALWAYS complete the full implement → review → audit cycle | Partial cycles leave unreviewed code in the codebase |
| ALWAYS validate bug eligibility before `/bug` implementation | Feature work must not bypass the PRD/SDD gates via `/bug`; an observed failure, regression or stack trace is required. |
| ALWAYS Read a state artifact (NOTES.md, a2a/ docs, MEMORY.md, contracts/*.yaml — any existing file) before Write/Edit | The Write tool rejects writes to un-Read existing files, and blind writes clobber cross-session state. |
