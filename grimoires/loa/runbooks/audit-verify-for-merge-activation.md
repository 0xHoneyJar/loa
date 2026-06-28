# Runbook — Activating the `verify-for-merge` audit gate

**Cycle:** OKF/ICM adoption, Sprint 9 (rec #2). **Status:** capability shipped; activation is **maintainer-gated**.

This runbook hands off the part of audit activation an autonomous agent **cannot** do. The agent-doable half shipped; the rest is a maintainer ceremony that depends on an **air-gapped root private key**.

## What shipped this sprint (agent-doable)

- **Bash strict-mode parity** — `audit-envelope.sh audit_verify_chain` now takes `--verify-for-merge` (or `LOA_AUDIT_STRICT_VERIFY=1`) and mirrors the Python reference (`audit_envelope.py` / `test_audit_envelope_strict_verify.py`):
  - **ATK-3** — refuses a `BOOTSTRAP-PENDING` trust-store (`[TRUST-STORE-BOOTSTRAP-PENDING]`) instead of permitting it.
  - **ATK-3** — refuses a producer-writable **local `<key-dir>/<id>.pub` fallback**; only trust-store-rooted writer keys are trusted.
  - **ATK-4** — fails closed on a missing/non-VERIFIED trust-store under strict. (In practice a *missing* store resolves to `BOOTSTRAP-PENDING`, so it reports `[TRUST-STORE-BOOTSTRAP-PENDING]`/ATK-3 — still fail-closed; this mirrors Python, whose ATK-4 missing-branch is likewise shadowed by the status check.)
  - Non-strict `verify-chain` is **unchanged** (install-time `BOOTSTRAP-PENDING` writes still permitted; the real callers — audit-snapshot, recover-chain, graduated-trust, loa-status — are unaffected).
  - **Env-toggle is verify-path only.** `LOA_AUDIT_STRICT_VERIFY=1` is honored solely by `audit_verify_chain` — it can NOT leak into the `audit_emit` write path. Even so, prefer the explicit `--verify-for-merge` flag over exporting the env var process-wide.
- **Opt-in fail-closed gate** — `.claude/scripts/audit-verify-for-merge.sh`. **DEFAULT OFF.** Runs the strict verify over the MODELINV log (+ extras) only when `LOA_AUDIT_VERIFY_FOR_MERGE=1`, and exits non-zero (fail-closed) on any failure.
- Tests: `tests/integration/audit-verify-for-merge.bats`.

## Why it is not live yet (the blocker)

The active trust-store (`grimoires/loa/trust-store.yaml`) is **BOOTSTRAP-PENDING** (empty `root_signature`, `keys: []`, `revocations: []`). Two preconditions block a green strict gate, and **neither can be completed by an agent**:

1. **Maintainer secret (hard blocker).** Flipping `BOOTSTRAP-PENDING → VERIFIED` requires signing the trust-store with the **offline root private key** held only by the maintainer (@janitooor). `LOA_AUDIT_KEY_PASSWORD` is a *red herring* — it decrypts a per-writer key (deprecated, SKP-002), **not** the root.
2. **Cutoff / strip-attack trap.** `trust_cutoff.default_strict_after = 2026-05-03`, but all ~1143 existing `.run/model-invoke.jsonl` entries are post-cutoff **and unsigned**. Even a perfectly bootstrapped trust-store will report `[STRIP-ATTACK-DETECTED]` on the first legacy entry under strict verify until the cutoff is advanced or the pre-signing history is sealed.

> **Wiring the gate before signing is live would hard-fail every merge.** That is by design (fail-closed), which is exactly why the gate ships **off** and is wired only at the end of the ceremony below.

## Maintainer ceremony (in order)

Base reference: `grimoires/loa/runbooks/audit-keys-bootstrap.md`.

### Steps 1–3 — keys[] PR prep *(agent MAY prepare; does not require the root key)*
1. Generate a per-writer Ed25519 keypair → `~/.config/loa/audit-keys/<writer_id>.priv` (0600) + `.pub`.
2. Add the writer to `grimoires/loa/operators.md`.
3. Draft the `keys[]` entry in `grimoires/loa/trust-store.yaml` (leave `root_signature` untouched):

   ```yaml
   keys:
     - writer_id: <writer_id>          # e.g. ci-release-bot
       pubkey_pem: |
         -----BEGIN PUBLIC KEY-----
         <base64 SubjectPublicKeyInfo of the writer .pub>
         -----END PUBLIC KEY-----
       added_at: "<YYYY-MM-DDTHH:MM:SSZ>"
       role: writer
   ```

### Step 4 — offline root-sign *(MAINTAINER ONLY — an agent CANNOT do this)*
Follow **`grimoires/loa/runbooks/audit-keys-bootstrap.md` Step 4** (the authoritative ceremony): on the air-gapped workstation, sign the JCS canonicalization of `{schema_version, keys, revocations, trust_cutoff}` with the **root private key** (`~/.cycle-098-root-keys/root.priv`) and fill `root_signature.{algorithm,signature,signed_at,signer_pubkey}`. The pinned root pubkey (`.claude/data/maintainer-root-pubkey.txt`, fingerprint `e7:6e:ec:46…`) is the verification anchor. After this, `_audit_trust_store_status` flips `BOOTSTRAP-PENDING → VERIFIED` and `audit-signing-helper.py trust-store-verify` passes.

> **Tooling note (verify before the ceremony):** both this runbook and `audit-keys-bootstrap.md` Step 4 reference a `audit-signing-helper.py trust-store-sign` subcommand, but the helper currently exposes only `sign` / `verify` / `verify-inline` / `trust-store-verify`. The root-signing in practice is `sign` over the canonical core bytes (its base64 output becomes `root_signature.signature`). The maintainer should confirm the exact command — or land the `trust-store-sign` convenience subcommand — as part of the ceremony.

### Step 5 — enable MODELINV signing going forward
Set `LOA_AUDIT_SIGNING_KEY_ID=<writer_id>` in the cheval emit environment so `modelinv.py` signs **new** `model-invoke.jsonl` entries. Until this is set, new entries stay unsigned and the cutoff trap persists.

### Step 6 — resolve the cutoff precondition (pick one)
- **(a, recommended)** Advance `trust_cutoff.default_strict_after` to the bootstrap date so the legacy ~1143 unsigned entries are **grandfathered** and only new (signed) entries are strict-checked; **or**
- **(b)** Seal / rotate the pre-signing log so history is no longer walked under strict.

### Step 7 — activate the gate
Only now: set `LOA_AUDIT_VERIFY_FOR_MERGE=1` and wire the gate into the release path. Minimal wiring (post-merge / CI), e.g. a step that runs:

```bash
LOA_AUDIT_VERIFY_FOR_MERGE=1 bash .claude/scripts/audit-verify-for-merge.sh
```

and treats a non-zero exit as a blocking failure. (To add it as a `post-merge-orchestrator.sh` phase, register it in the phase matrix + ordered list after the existing phases; keep it gated on the env flag so it stays inert until activated.)

## Verifying the handoff locally (no root key needed)
- `bash .claude/scripts/audit-envelope.sh verify-chain --verify-for-merge .run/model-invoke.jsonl` → today this **fails closed** with `[TRUST-STORE-BOOTSTRAP-PENDING] … (ATK-3)`. That failure **is** the correct pre-ceremony behavior.
- `bash .claude/scripts/audit-verify-for-merge.sh` → prints `DISABLED` and exits 0 (opt-in off).

## Tracking
- Agent-doable half: OKF cycle Sprint 9 (this commit).
- Maintainer ceremony (Steps 4–7) + keys[] PR: hand off to **@janitooor**.
