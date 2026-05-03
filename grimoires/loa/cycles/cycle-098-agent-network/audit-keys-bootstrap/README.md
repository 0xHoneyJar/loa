# cycle-098-agent-network — Audit Root Key Bootstrap

**Status**: STAGED — awaiting operator sign-off + release-tag ceremony before Sprint 1 commit.

## Generated artifacts

| File | Location | Permission | Purpose |
|------|----------|------------|---------|
| `cycle098-root.priv` | `~/.config/loa/audit-keys/cycle098-root.priv` | 0600 (owner-only) | Maintainer offline root key — signs trust-store releases |
| `cycle098-root.pub` | `grimoires/loa/cycles/cycle-098-agent-network/audit-keys-bootstrap/cycle098-root.pub` | 0644 | Public key (PEM) — to be committed during Sprint 1 |
| `README.md` (this file) | same dir | 0644 | Operator review notes |

## Cryptographic details

- **Algorithm**: Ed25519 (RFC 8032)
- **Generated**: 2026-05-03T00:00:42.992683+00:00
- **Generator**: Python `cryptography.hazmat.primitives.asymmetric.ed25519` on Loa development workstation
- **Encryption**: NONE (private key is unencrypted PEM). Operator MUST re-encrypt with passphrase before Sprint 1 production use.
  - Recommended path: `openssl pkcs8 -topk8 -in cycle098-root.priv -out cycle098-root.priv.enc` (then replace + audit)
  - OR migrate to YubiKey / hardware token (preferred per SDD §1.9.3.1)

## Public key fingerprint (SHA-256 of SPKI DER)

```
e76eec460b34eb610f6db1272d7ef364b994d51e49f13ad0886fa8b9e854c4d1
```

**Colon-separated** (for display in the 3 fingerprint channels):
```
e7:6e:ec:46:0b:34:eb:61:0f:6d:b1:27:2d:7e:f3:64:b9:94:d5:1e:49:f1:3a:d0:88:6f:a8:b9:e8:54:c4:d1
```

## Sign-off checklist

- [ ] Operator has reviewed this artifact and the fingerprint matches expectations
- [ ] Operator has verified `~/.config/loa/audit-keys/cycle098-root.priv` permissions are `0600`
- [ ] Operator has chosen passphrase OR hardware-token migration plan before Sprint 1
- [ ] Sprint 1 implementation will:
  - Re-encrypt private key with operator passphrase OR move to hardware token
  - Move `cycle098-root.pub` from this staging location to `.claude/data/maintainer-root-pubkey.txt` (System Zone, gated by Sprint 1 review/audit)
  - Create signed git tag `cycle-098-root-key-v1` carrying the pubkey
  - Publish the fingerprint in the 3 channels (PR description, NOTES.md, release notes)

## Threat model reminder

A repo compromise alone CANNOT legitimize a malicious signing key, because:
1. The pubkey will be carried by a release-signed git tag (`git tag -v` validates against maintainer's GitHub-registered GPG key)
2. The fingerprint is published in 3 independent channels — at install time, operators cross-check
3. Trust-store updates require this root key's signature; unsigned trust-store changes fail-closed at runtime

## Public key (PEM)

```
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAdXgpsndtu9p+fI3Rw/rqr+LjQYtOrZKsXgHKN974o+M=
-----END PUBLIC KEY-----
```

## Public key (base64 SPKI)

```
MCowBQYDK2VwAyEAdXgpsndtu9p+fI3Rw/rqr+LjQYtOrZKsXgHKN974o+M=
```
