| Rule | Why |
|------|-----|
| ALWAYS route implementation through `/run sprint-plan`, `/run sprint-N`, or `/bug`, checking for the existing sprint plan first | Ensures the implement→review→audit cycle with circuit-breaker protection and requirements traceability (absorbs the former separate check-sprint-plan row; implement-gate.sh asks on ungated App-Zone writes). |
| ALWAYS create beads tasks from sprint plan before implementation (if beads available) | Tasks without beads tracking are invisible to cross-session recovery |
| ALWAYS complete the full implement → review → audit cycle | Partial cycles leave unreviewed code in the codebase |
| ALWAYS validate bug eligibility before `/bug` implementation | Prevents feature work from bypassing PRD/SDD gates via `/bug`. Must reference observed failure, regression, or stack trace. |
| ALWAYS Read a state artifact (NOTES.md, a2a/ docs, MEMORY.md, contracts/*.yaml — any existing file) before Write/Edit | The Write tool rejects writes to un-Read existing files (hundreds of failed writes a month across mounts) and blind writes clobber cross-session state. |
