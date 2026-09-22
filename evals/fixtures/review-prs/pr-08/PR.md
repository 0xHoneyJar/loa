# chore(ledger,tools,cheval): lighter ledger content check, simpler heredoc skipping, fewer except clauses

Relaxes the _write_ledger content check to a plain jq parse, simplifies the swallowed-jq scanner heredoc state machine, and removes the ValueError handler around the agy CLI exec.
