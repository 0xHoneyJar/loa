# Audit-Keys Bootstrap Runbook

> Operator runbook for bootstrapping per-writer Ed25519 audit keys + the trust-store anchor. Covers IMP-003 #2/#3/#4 from cycle-098 Sprint 1.

## When to read this

- First-time install of cycle-098 audit envelope (`enabled: true` for any L1-L7 primitive)
- Adding a new writer/operator to the trust-store
- Rotating a compromised writer key
- CI/CD environment where audit keys come from a secret store (not interactive bootstrap)
- Diagnosing `[BOOTSTRAP-PENDING]` exit-78 errors from `audit-signing-helper.py`

## Error category table

When audit envelope writes/verification fail, check the error markers in stderr:

| Marker | Meaning | Recovery |
|--------|---------|----------|
| `[BOOTSTRAP-PENDING]` | Configured signing key file missing at `<key-dir>/<writer_id>.priv` | Generate keypair (Step 1 below) or set `LOA_AUDIT_SIGNING_KEY_ID=""` to disable signing temporarily |
| `[UNVERIFIED-WRITER]` | Writer's pubkey not in trust-store (or trust-store unsigned) | Maintainer runs Step 4 (offline trust-store sign) |
| `[ROOT-PUBKEY-MISSING]` | Pinned root pubkey at `.claude/data/maintainer-root-pubkey.txt` not found | Reinstall framework or restore file from upstream |
| `[ROOT-PUBKEY-DIVERGENCE]` | Trust-store's `root_signature.signer_pubkey` does not match pinned pubkey | DO NOT proceed; contact maintainer out-of-band — possible supply-chain attack |
| `[STRIP-ATTACK-DETECTED]` | Post-trust-cutoff entry missing `signature` or `signing_key_id` | An attacker may have rewritten history; do not accept the chain. Restore log from latest signed snapshot via `audit_recover_chain` |
| `[CHAIN-BROKEN]` | Both git-history and snapshot recovery failed | Operator manual review; primitive enters degraded mode (reads OK, writes blocked) |
| `[CHAIN-GAP-RECOVERED-FROM-GIT commit=...]` | Recovery succeeded from git log of TRACKED log | Informational — verify the recovered state is the expected one |
| `[CHAIN-GAP-RESTORED-FROM-SNAPSHOT-RPO-24H snapshot=...]` | Recovery from snapshot archive (RPO 24h) | Informational — entries between snapshot and now are LOST |

Exit codes:

| Exit code | Constant | Meaning |
|-----------|----------|---------|
| 0 | — | Success |
| 1 | `EX_VERIFY_FAIL` | Generic verification failure |
| 2 | `EX_USAGE` | Bad arguments |
| 3 | `EX_KEY_LOAD` | Key file present but unloadable (mode bits / corruption / wrong type) |
| 78 | `EX_CONFIG` | `[BOOTSTRAP-PENDING]` — configured key not found, OR cryptography package missing |

## Step 1 — Operator generates Ed25519 keypair

```bash
WRITER_ID="$(git config user.email | tr '[:upper:]' '[:lower:]' | tr '@.' '-' | tr -dc 'a-z0-9_-')"
KEY_DIR="${HOME}/.config/loa/audit-keys"
mkdir -p "$KEY_DIR"
chmod 700 "$KEY_DIR"

python3 - "$KEY_DIR" "$WRITER_ID" <<'PY'
import sys
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.hazmat.primitives import serialization

key_dir, writer_id = Path(sys.argv[1]), sys.argv[2]
priv = ed25519.Ed25519PrivateKey.generate()

# Encrypt the private key with a passphrase from stdin (best practice for
# operator desktop). For unencrypted (CI): replace BestAvailableEncryption()
# with NoEncryption() and load from a tmpfs secret-mounted path.
import getpass
pw = getpass.getpass("Passphrase for new audit key (empty for unencrypted): ").encode()
encalg = serialization.NoEncryption() if not pw else serialization.BestAvailableEncryption(pw)

priv_bytes = priv.private_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PrivateFormat.PKCS8,
    encryption_algorithm=encalg,
)
pub_bytes = priv.public_key().public_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PublicFormat.SubjectPublicKeyInfo,
)
priv_path = key_dir / f"{writer_id}.priv"
pub_path = key_dir / f"{writer_id}.pub"
priv_path.write_bytes(priv_bytes)
priv_path.chmod(0o600)
pub_path.write_bytes(pub_bytes)
print(f"Wrote {priv_path} (mode 0600) + {pub_path}")
print(f"Public key (paste into trust-store-update PR):")
print(pub_bytes.decode())
PY
```

After generation:

- `~/.config/loa/audit-keys/<writer_id>.priv` is mode 0600
- `~/.config/loa/audit-keys/<writer_id>.pub` is mode 0644
- Operator passphrase is held only in operator's memory / password manager

## Step 2 — Operator adds entry to OPERATORS.md

Add yourself to `grimoires/loa/operators.md`:

```yaml
- id: <writer_id>
  display_name: <Your Name>
  github_handle: <your-handle>
  git_email: <your-git-email>
  capabilities: [implement, review, audit]   # or subset
  active_since: 2026-05-03
```

Commit + open PR.

## Step 3 — Operator drafts trust-store update

Update `grimoires/loa/trust-store.yaml` (in the same PR or a follow-up):

```yaml
keys:
  - writer_id: <writer_id>
    pubkey_pem: |
      -----BEGIN PUBLIC KEY-----
      <paste from Step 1 output>
      -----END PUBLIC KEY-----
    operator_id: <writer_id>
    valid_from: "2026-05-03T00:00:00Z"
    valid_until: null
    notes: "Initial bootstrap"
```

The trust-store's `root_signature` must remain unchanged. The maintainer will re-sign it in Step 4.

## Step 4 — Maintainer signs trust-store offline

> **Maintainer-only**. Performed by the operator listed in
> `.claude/data/maintainer-root-pubkey.txt`. The signing ceremony happens on an
> air-gapped workstation; the offline root key NEVER touches a network-connected
> machine.

```bash
# On air-gapped workstation, operator brings the JCS canonicalization of
# {keys, revocations, trust_cutoff} from the latest PR head:
python3 .claude/scripts/lib/audit-signing-helper.py trust-store-sign \
    --root-priv ~/.cycle-098-root-keys/root.priv \
    --trust-store grimoires/loa/trust-store.yaml \
    --signer-pubkey-from .claude/data/maintainer-root-pubkey.txt \
    --signed-at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --output-mode in-place

# Inspect the new root_signature block, then commit + push the merge of
# operator's PR.
```

After Step 4, all writers in the new `keys[]` can sign envelopes; verifiers will accept their signatures.

## Step 5 — CI/CD bootstrap

CI environments lack interactive secret entry. Use one of the following patterns; **NEVER** commit private keys to git or pass them via env vars.

### GitHub Actions

```yaml
jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Decrypt audit key from GitHub Secrets
        env:
          AUDIT_KEY_B64: ${{ secrets.LOA_AUDIT_KEY_B64 }}
        run: |
          # tmpfs mount so the key never touches durable storage
          sudo mount -t tmpfs -o size=8m tmpfs "$HOME/audit-keys-secure"
          chmod 700 "$HOME/audit-keys-secure"
          printf '%s' "$AUDIT_KEY_B64" | base64 -d > "$HOME/audit-keys-secure/ci-writer.priv"
          chmod 600 "$HOME/audit-keys-secure/ci-writer.priv"
      - name: Run audit emit
        env:
          LOA_AUDIT_KEY_DIR: ${{ env.HOME }}/audit-keys-secure
          LOA_AUDIT_SIGNING_KEY_ID: ci-writer
        run: |
          .claude/scripts/audit-envelope.sh emit-signed L3 cycle.start \
              '{"sprint":"sprint-1"}' \
              grimoires/loa/audit/cycles.jsonl \
              --password-file "$HOME/audit-keys-secure/.passphrase"
```

The `LOA_AUDIT_KEY_B64` secret is set in repo Settings → Secrets and variables → Actions → New repository secret.

### GitLab CI

```yaml
audit-job:
  before_script:
    - mkdir -p $HOME/audit-keys-secure
    - chmod 700 $HOME/audit-keys-secure
    - echo "$LOA_AUDIT_KEY_B64" | base64 -d > $HOME/audit-keys-secure/ci-writer.priv
    - chmod 600 $HOME/audit-keys-secure/ci-writer.priv
  variables:
    LOA_AUDIT_KEY_DIR: $HOME/audit-keys-secure
    LOA_AUDIT_SIGNING_KEY_ID: ci-writer
  script:
    - .claude/scripts/audit-envelope.sh emit-signed ...
```

`LOA_AUDIT_KEY_B64` is a CI/CD variable (Settings → CI/CD → Variables, marked Masked + Protected).

### CircleCI

```yaml
jobs:
  audit:
    docker:
      - image: cimg/base:2024.10
    steps:
      - checkout
      - run:
          name: Set up audit key from secret store
          command: |
            mkdir -p $HOME/audit-keys-secure
            chmod 700 $HOME/audit-keys-secure
            printf '%s' "$LOA_AUDIT_KEY_B64" | base64 -d > $HOME/audit-keys-secure/ci-writer.priv
            chmod 600 $HOME/audit-keys-secure/ci-writer.priv
      - run:
          name: Audit emit
          environment:
            LOA_AUDIT_KEY_DIR: /home/circleci/audit-keys-secure
            LOA_AUDIT_SIGNING_KEY_ID: ci-writer
          command: .claude/scripts/audit-envelope.sh emit-signed ...
```

`LOA_AUDIT_KEY_B64` is set in the project context (Project Settings → Environment Variables) or in an org-level Context.

### Common patterns across all CI providers

- **Always** decrypt to a private mode-700 directory (tmpfs preferred — `/dev/shm` works on most Linux runners)
- **Always** chmod the `.priv` to 0600 — `_load_private_key` refuses anything more permissive
- **Never** echo the secret to logs (CI providers redact masked vars but not raw stderr from helper)
- **Never** check the encrypted blob into git — it's still subject to offline brute-force if the secret leaks via another vector
- For long-running runs, consider rotating the per-job ephemeral key after each job rather than reusing a long-lived CI writer-id

## Step 6 — Rotation (compromise playbook)

If a writer key is compromised:

1. Operator generates new keypair (Step 1) with a new `writer_id` (do NOT reuse the compromised id)
2. Operator drafts revocation entry in `grimoires/loa/trust-store.yaml::revocations[]`:
   ```yaml
   revocations:
     - writer_id: <compromised_writer_id>
       pubkey_pem: |
         -----BEGIN PUBLIC KEY-----
         <old pubkey>
         -----END PUBLIC KEY-----
       revoked_at: "2026-05-03T12:00:00Z"
       reason: "Possible compromise — laptop lost"
       revocation_signature: <base64 signature signed by NEW key>
   ```
3. Maintainer signs the updated trust-store (Step 4)
4. Old key's signatures remain VALID for entries with `ts_utc < revoked_at`. Entries with `ts_utc >= revoked_at` signed by the revoked key are REJECTED at verify time

## Reference

- Schema: `.claude/data/trajectory-schemas/agent-network-envelope.schema.json`
- Retention: `.claude/data/audit-retention-policy.yaml`
- Helper: `.claude/scripts/lib/audit-signing-helper.py`
- Bash adapter: `.claude/scripts/audit-envelope.sh`
- Python adapter: `.claude/adapters/loa_cheval/audit_envelope.py`
- SDD: `grimoires/loa/sdd.md` §1.4.1, §1.9.3.1
- PRD: `grimoires/loa/prd.md` Cross-cutting Operator Identity Model
