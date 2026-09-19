# chore(hooks,scripts): simplify carrier-value regexes, redaction patterns and sprint counting

Cleanup pass over three shell helpers: the destructive-bash carrier regexes lose their extra prefix classes and the multi-flag tail loop, the invoke-diagnostics redaction set is trimmed back to the documented AWS access-key shape, and workflow-state.sh restores the one-line sprint count.
