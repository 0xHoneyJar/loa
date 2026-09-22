# refactor(ledger,mount,classify): trim write-guard checks, symlink resolution and PR classification

Simplifies _write_ledger and its callers, resolves symlink targets directly from the working directory in mount-submodule.sh, and removes the release-merge special case from classify-pr-type.sh.
