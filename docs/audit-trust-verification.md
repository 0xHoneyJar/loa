# Audit trust verification

Use strict verification when consuming an audit chain as signed evidence:

```bash
source .claude/scripts/audit-envelope.sh
audit_verify_chain --verify-for-merge path/to/audit.jsonl

tools/modelinv-rollup.sh --require-signed --input path/to/model-invoke.jsonl
```

The Python equivalent is
`audit_verify_chain(log_path, verify_for_merge=True)`.
`LOA_AUDIT_STRICT_VERIFY=1` also enables strict verification. An explicit
strict argument cannot be disabled by the environment.

Strict verification requires:

- A readable, root-signed trust-store verified against the pinned root key.
- A nonempty `trust_cutoff.default_strict_after` containing a valid UTC
  timestamp that is already in effect.
- Both signature fields for every post-cutoff entry, with a valid Ed25519
  signature under its registered writer key.
- Rejection of a writer's signatures at or after its `revoked_at` timestamp.

`LOA_AUDIT_VERIFY_SIGS=0` cannot disable these checks in strict mode.
`--require-signed` rejects `--no-chain-verify` and refuses to produce a rollup
if verification fails or its verifier is unavailable.

Unsigned pre-cutoff history remains grandfathered. A successful strict result
does not authenticate that unsigned prefix or establish an external checkpoint.

Outside strict mode, the legacy signature toggle remains available for chain
migration. Signed history still requires a verified store: deleting the store
or replacing it with an empty bootstrap document cannot authorize local keys.
A registered store is authoritative on lookup misses; a producer's local
`<key_id>.pub` cannot add or replace a root-approved writer.
Verification authenticates a snapshot of the store's bytes and uses that same
parsed document for writer bindings, revocations and cutoff policy throughout
the chain walk. Changing the original file between verification and lookup
cannot substitute an unverified policy.
The authentication cache also includes the pinned root's path and contents.
Authentication uses the captured pin bytes; changing, removing or repairing
the original pin invalidates the prior result on the next verification.

Bootstrap writes remain available before the trust-store is signed. Those
writes do not become trusted signed evidence until the root-signed writer
binding is installed. Unreadable or malformed stores are invalid, not bootstrap.

Quote all YAML timestamps when signing a store. Unquoted YAML timestamps can
be coerced to non-JSON objects; the signer/verifier reject them with a
structured diagnostic rather than changing the signed bytes.

The Bash verifier delegates to the Python audit adapter, using the existing
PyYAML, RFC 8785, and cryptography dependencies. Key resolution is independent
of the installed `yq` flavor.

Regression commands:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 tests/security/test_audit_trust_policy.py
bats tests/integration/audit-envelope-signing.bats tests/security/audit-envelope-strip-attack.bats
```
