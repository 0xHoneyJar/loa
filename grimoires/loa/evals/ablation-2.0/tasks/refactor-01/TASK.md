# Task: one implementation of the record rules

`ledgerio` (under `src/ledgerio/`) reads ledger entries from CSV and JSON and keeps an in-memory ledger. All three entry points apply the same record rules: the four required fields, a non-empty id, a non-negative number amount, a three-letter upper-case currency code and an ISO date. Each module carries its own copy of those rules, under a different name or inline. The copies have already been written three different ways, and the next rule change has to be made three times.

**Refactor:** move the rules into one function, `validate_record(record)`, defined at module level in a new module `ledgerio.validation`. It raises `RecordError` with the existing messages and returns `None` for a valid record. The CSV reader, the JSON reader and the ledger API (`create_entry`, `update_entry`) import it and call it. None of them keeps a copy of the rules: no rule messages, no date parsing and no private validator of its own.

**Unchanged behaviour:** every public function returns the same values and raises the same `RecordError` messages as today, including the `line N: ` and `item N: ` prefixes the readers add. The existing suite must stay green without edits. Run it with `python3 -m pytest -q tests`.
