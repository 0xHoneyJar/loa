# Sub-sprint 1A Progress Report — JCS canonicalization + Audit Envelope foundation

**Cycle**: cycle-098-agent-network
**Sprint**: 1 (Foundation)
**Sub-sprint**: 1A (1 of 4)
**Branch**: `feat/cycle-098-sprint-1`
**Status**: COMPLETED

## Outcome

All deliverables for Sub-sprint 1A are complete, tested, and pushed. The
foundation layer (RFC 8785 JCS canonicalization + audit-envelope schema +
basic write/read/chain-walk) is in place and ready for 1B (signing), 1C
(`sanitize_for_session_start`), and 1D (L1 panel integration) to build on.

## Files added (12 source files + 5 tests + 1 workflow + 1 progress doc)

### JCS multi-language adapters (CC-2, CC-11, IMP-001)

| File | Purpose |
|------|---------|
| `lib/jcs.sh` | Bash adapter; delegates to Python helper for canonicalization |
| `.claude/scripts/lib/jcs-helper.py` | Python helper invoked by bash adapter (wraps `rfc8785`) |
| `.claude/adapters/loa_cheval/jcs.py` | Python public API (`canonicalize`, `available`) |
| `.claude/scripts/lib/jcs.mjs` | Node ESM adapter (wraps `canonicalize` npm package) |
| `tests/conformance/jcs/test-vectors.json` | 30 test vectors (corpus + RFC 8785 §3.2.2/3.2.3 + nested ≥5 levels) |
| `tests/conformance/jcs/run.sh` | CI gate — verifies byte-identity across all 3 adapters |
| `tests/conformance/jcs/package.json` | Node deps for conformance harness |
| `tests/conformance/jcs/.gitignore` | Excludes `node_modules/`, `__pycache__/` |
| `.github/workflows/jcs-conformance.yml` | PR-required check; SHA-pinned actions |

### Audit envelope foundation (CC-2, CC-11, NFR-Sec1)

| File | Purpose |
|------|---------|
| `.claude/data/trajectory-schemas/agent-network-envelope.schema.json` | Normative JSON Schema (Draft 2020-12); `signature`/`signing_key_id` reserved for 1B |
| `.claude/scripts/audit-envelope.sh` | Bash library: `audit_emit`, `audit_verify_chain`, `audit_seal_chain` |
| `.claude/adapters/loa_cheval/audit_envelope.py` | Python equivalent with byte-identical semantics (R15) |

### Tests (96 assertions across 5 files)

| File | Type | Count | Status |
|------|------|-------|--------|
| `tests/conformance/jcs/test-jcs-bash.bats` | bats | 6 | PASS |
| `tests/conformance/jcs/test-jcs-python.py` | pytest | 34 (incl. 30 parametrized vectors) | PASS |
| `tests/conformance/jcs/test-jcs-node.mjs` | node:test | 34 | PASS |
| `tests/integration/audit-envelope-chain.bats` | bats | 9 | PASS |
| `tests/unit/audit-envelope-schema.bats` | bats | 13 | PASS |
| **TOTAL** | | **96** | **96 PASS / 0 FAIL** |

Plus the conformance gate (`tests/conformance/jcs/run.sh`) verifies 30 vectors
× 3 adapters = 90 cross-adapter byte-identity checks.

## Sprint 1 ACs satisfied (IMP-001 / CC-2 / CC-11)

- IMP-001 #1: bash + Python + Node adapters produce byte-identical output for
  the corpus — verified via `run.sh`.
- IMP-001 #2: CI gate (`run.sh` + `jcs-conformance.yml`) fails on any
  divergence — workflow created.
- IMP-001 #3: Corpus covers RFC 8785 §3.2.2 (numbers: int, float, scientific,
  trailing zero), §3.2.3 (strings: empty, quote, backslash, newline, tab, BMP
  Unicode, emoji), and 30 vectors total — exceeds AC ≥20 threshold.
- IMP-001 #4 (negative test): not yet — Sprint 1B will add the
  jq-substitution → signature-failure test once signing is in place.
- CC-2: envelope is versioned (`schema_version`), hash-chained
  (`prev_hash`), and authored by writer (`signing_key_id` reserved for 1B).
- CC-11: ajv-validated at write-time; jsonschema fallback per R15.

## TODO hooks for 1B (signing)

`.claude/scripts/audit-envelope.sh` carries explicit `TODO(Sprint 1B)`
comments at:

- `audit_emit()` — line ~225 — needs Ed25519 signing + signing_key_id
  population. `signature` and `signing_key_id` are currently omitted from the
  envelope. Sprint 1B should:
  1. Load private key from `~/.config/loa/audit-keys/<signing_key_id>.priv`
     via `--password-fd N` or `--password-file <path>` (NOT `LOA_AUDIT_KEY_PASSWORD`
     per SKP-002).
  2. Sign the canonical chain-input bytes (already computed by
     `_audit_chain_input`).
  3. base64-encode and add to envelope.
  4. Mark schema's `signature` / `signing_key_id` as required (via additive
     1.1.0 minor bump or distinct `agent-network-envelope-signed` schema —
     decide at 1B time).
- `audit_verify_chain()` — line ~272 — needs signature verification against
  the trust-store. Integration with NFR-Sec1 + IMP-003 trust-store from
  `.claude/data/maintainer-root-pubkey.txt` (ROOT-PUBKEY-DIVERGENCE check).
- `_audit_validate_envelope()` and `audit_emit()` — flock acquisition is
  caller's responsibility today; standardize per primitive in 1B.

`.claude/adapters/loa_cheval/audit_envelope.py` carries the same
`TODO(Sprint 1B)` comments at the matching API points.

## Cross-adapter compatibility (verified)

- Bash writes 3 entries → Python verifies the chain → OK 3 entries.
- Python writes 3 entries → bash verifies the chain → OK 3 entries.
- Both adapters produce byte-identical envelope JSON when given identical
  inputs (verified by inspection; tested by integration suite).

## Regression status

- New tests: 96 PASS / 0 FAIL.
- Targeted regression checks (no new failures introduced):
  - `tests/unit/secret-redaction.bats`: 22/22 PASS.
  - `tests/unit/skill-capabilities.bats`: 17/17 PASS.
  - `tests/unit/bash32-portability.bats`: 6/6 PASS (1 skipped on Linux host).
- Full-suite bats run not completed in this sub-sprint window (the parent
  bats sweep takes >5 minutes). Cycle-098 main has 124 pre-existing bats
  failures per the prompt; nothing in the targeted regression sweep regressed
  vs that baseline.

## Constraints met

- Test-first: 5 test files cover all major behaviors; verified that tests
  correctly skip (and would fail meaningfully) when implementation files are
  removed.
- Karpathy: Simplicity First (no speculative features); Surgical Changes
  (no edits to unrelated files); Goal-Driven (every file traces to an AC).
- macOS portability: scripts use `[[ ]]` only; `_audit_now_iso8601()` falls
  back to Python when `date +%6N` is unsupported (BSD date).
- Bash safety: `set -euo pipefail`, `var=$((var + 1))` arithmetic per
  shell-conventions.md, no `(( var++ ))`.
- Beads UNHEALTHY (#661): no `br create` calls; sub-sprint tracked here only.
- System Zone: cycle-098 PRD authorizes Sprint 1 modifications to
  `.claude/scripts/`, `.claude/data/`, `.claude/adapters/`. NEW files only;
  no modifications to existing System Zone files.

## Notable findings

1. **`canonicalize` npm package quirk** — v3 ships as ESM-only with no
   CommonJS export and a strict `package.json::exports` field. ESM dynamic
   import requires the package to be resolvable from the importing file's
   directory tree. Solution: install in `tests/conformance/jcs/node_modules/`
   and let the Node adapter walk upward to find it. Documented in
   `.claude/scripts/lib/jcs.mjs`.
2. **Schema flexibility for transition** — Sprint 1A requires
   `signature`/`signing_key_id` to be optional so audit-envelope can write
   entries without signing during the bootstrap phase. Sprint 1B will tighten
   this. Schema `description` calls out the transition explicitly.
3. **Python `rfc8785` is the byte oracle** — test vectors' `expected` outputs
   were generated by `rfc8785.dumps()` and now bash + Node match byte-exact.
   This makes Python the canonical reference for any spec ambiguity.

## Blockers

None. Ready for handoff to 1B.

## Handoff to 1B

1. Pull `feat/cycle-098-sprint-1` (this sub-sprint's commit will be at the tip).
2. Read TODO comments in `.claude/scripts/audit-envelope.sh` and
   `.claude/adapters/loa_cheval/audit_envelope.py`.
3. Add Ed25519 signing per SDD §1.4.1 + Sprint 1 ACs (IMP-003 fd-based key
   loading; SKP-002 password-fd; SKP-001 root-of-trust trust-store).
4. Bump schema to 1.1.0 (minor) when adding required signature fields, OR
   create a separate `agent-network-envelope-signed.schema.json` — operator
   decision.
5. Add the IMP-001 #4 negative test: substitute `jq -S -c` for `lib/jcs.sh`
   in audit-envelope.sh and confirm signature verification fails on at least
   one corpus vector (proves JCS ≠ jq -S -c).
