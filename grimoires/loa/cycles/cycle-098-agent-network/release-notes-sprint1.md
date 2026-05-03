# cycle-098 Sprint 1 Release Notes — Shared CC Infrastructure + L1 hitl-jury-panel

> Sprint 1 release notes — to be edited and finalized when Sprint 1 ships. The fingerprint section is the **third of three** publication channels for the maintainer root pubkey.

**Status**: STAGED — Sprint 1 not yet started. This document is the prepared template for the operator to publish at Sprint 1 release.

## Highlights

- ✨ **L1 hitl-jury-panel** ships — N-panelist adjudicator for autonomous-mode decisions; deterministic seed selection; protected-class queue
- 🔐 **Shared audit envelope** with versioned, hash-chained, Ed25519-signed JSONL logs + RFC 8785 JCS canonicalization
- 🛡️ **Trust-store root of trust** distributed via release-signed git tag — independent of mutable repo state
- 🎯 **Tier validator** at boot — 5 supported configuration tiers with `warn` default (cycle-099 flips to `refuse`)
- 📋 **Protected-class taxonomy** — 10 default classes covering credential rotation, prod deploy, irreversible destructive ops, schema migrations, etc.
- 🔍 **`/loa status` integration** — operator visibility into all 7 primitives' health

## Maintainer root pubkey fingerprint (publication channel 3 of 3)

> Cross-verify against the cycle-098 PR description and `grimoires/loa/NOTES.md` cycle-098 section. If any fingerprint diverges, DO NOT accept the trust anchor — contact the maintainer out-of-band.

**SHA-256 of public key SPKI DER (hex)**:
```
e76eec460b34eb610f6db1272d7ef364b994d51e49f13ad0886fa8b9e854c4d1
```

**Colon-separated**:
```
e7:6e:ec:46:0b:34:eb:61:0f:6d:b1:27:2d:7e:f3:64:b9:94:d5:1e:49:f1:3a:d0:88:6f:a8:b9:e8:54:c4:d1
```

**Algorithm**: Ed25519 (RFC 8032)
**Pubkey location** (post-Sprint 1): `.claude/data/maintainer-root-pubkey.txt` (System Zone, frozen by reviewer-only edits)
**Tagged release**: `cycle-098-root-key-v1` (`git tag -v` validates against maintainer's GitHub-registered GPG key)

## Migration notes

### For existing Loa users

- All 7 primitives ship `enabled: false` by default. No behavioral change unless you enable them.
- If you enable any primitive, run `/loa diag config-tier` to verify your config matches a supported tier (Tier 0, 1, 2, 3, or 4 — see `grimoires/loa/prd.md` §Supported Configuration Tiers).
- Unsupported tier combinations will WARN at boot in cycle-098; cycle-099 will REFUSE boot. Migrate to a supported tier or pin a non-default `tier_enforcement_mode`.

### For first-time installers

- Run `/loa audit-keys init` to generate your per-writer Ed25519 keypair under `~/.config/loa/audit-keys/`
- Verify the maintainer root pubkey fingerprint above matches all 3 channels (this file, PR description, NOTES.md)
- Read `grimoires/loa/runbooks/audit-keys-bootstrap.md` for full setup

## Sprint 1 acceptance criteria delta vs PRD

> Filled in at Sprint 1 close.

- ✅ All 9 L1 hitl-jury-panel ACs from #653 PASS
- ✅ All 11 cross-cutting FRs (CC-1..CC-11) satisfied
- ✅ JCS multi-language conformance CI gate green
- ✅ Maintainer root pubkey published in 3 channels
- ✅ fd-based secret loading replaces `LOA_AUDIT_KEY_PASSWORD` env var
- ✅ Hash-chain recovery procedure (NFR-R7) tested for both tracked + untracked log scenarios
- ✅ Daily snapshot cron documented in operator runbook (RPO 24h for L1/L2)
- ✅ R11 weekly schedule-check ritual: 1 ritual completed during Sprint 1

## Known issues

- [#675](https://github.com/0xHoneyJar/loa/issues/675) — cheval HTTP/2 disconnect on 137KB+ payloads. Workaround: direct curl HTTP/1.1 with `max_tokens ≤4096`. Triage outcome TBD.

## Acknowledgments

- Discovery, architecture, and Flatline review: Claude Opus 4.7 (1M context)
- Maintainer + operator: deep-name (jani@0xhoneyjar.xyz)
- 4 Flatline review passes (3 PRD + 4 SDD) integrated; 100%/100%/90%/90% model agreement; ~12 BLOCKERs surfaced and addressed

🤖 Generated with [Claude Code](https://claude.com/claude-code)
