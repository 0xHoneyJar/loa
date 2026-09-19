# fix(bug-725): handle ajv-cli@5+ in loa-doctor version probe

ajv-cli 5 changed its version output; loa-doctor misreported it as missing. Probe both shapes and pin the behaviour with tests.
