# Audit Moat Positioning — Two-Tier, Honest (2026-06-29)

> **Cycle**: `cycle-115-okf-followup-mempalace` · **Deliverable**: D3 · **Bead**: `bd-audit-moat-positioning-sji4`
> **Status**: STATE-zone positioning note. Changes no verification path. The reviewer greps in `sprint.md` (Task 1.3) are the acceptance check.

## Why this lives here, not in `memory-reference.md`

`memory-reference.md` is System Zone (`.claude/`) — framework-managed, agents
MUST NOT edit it directly (`.claude/rules/zone-system.md`). Positioning prose —
claims about *what the moat is* and *how we should talk about it* — is a
judgment that evolves with the system and gets re-litigated each cycle. That
belongs in a dated STATE-zone proposal under `grimoires/loa/proposals/`, where
it is versioned alongside the rest of the cycle's artifacts and supersedable by
the next dated note. Mixing positioning narrative into a System-Zone reference
would (a) require a cycle-authorized System write for every wording revision and
(b) entangle durable framework documentation with time-stamped strategy claims
that age out. Keep them separate.

---

## Tier 1 — TRUE TODAY (claim this now): hash-chain integrity / tamper-evidence at zero cost

The differentiator we can stand behind **right now** is **integrity**: any
edit, reorder, or deletion of a past log entry is *detected* on the next walk.
This requires no keys, no signing, no per-writer identity — it is a property of
the chain structure itself. Every mechanism claim below cites the resolving
line in `.claude/scripts/audit-envelope.sh`.

| Mechanism | What it gives | Resolves at |
|-----------|---------------|-------------|
| RFC 8785 JCS canonicalization of chain-input | Byte-stable hashing input regardless of key order / whitespace, so the same logical entry always hashes identically | `audit-envelope.sh:72-74` (sources `lib/jcs.sh`); applied in `_audit_chain_input` at `audit-envelope.sh:169-177` |
| `signature` + `signing_key_id` stripped *before* hashing | The chain hashes only content, not the (optional, later-added) signature fields — so integrity holds whether or not an entry is ever signed | `audit-envelope.sh:169-177` (`jq -c 'del(.signature, .signing_key_id)'` then `jcs_canonicalize`) |
| SHA-256 over the canonical chain-input | Cryptographically strong digest of each entry's content | `audit-envelope.sh:150-167` (`_audit_sha256`) |
| GENESIS anchor + `prev_hash` continuity | Each entry pins the SHA-256 of its predecessor's chain-input; an empty/absent log starts at the literal `GENESIS` anchor | `audit-envelope.sh:184-203` (`_audit_compute_prev_hash` — emits `GENESIS` when the log is missing/empty, else hashes the previous line's chain-input) |
| Verify-walk fails on first break | Walking the chain from GENESIS, the first entry whose `prev_hash` does not equal the recomputed predecessor digest returns non-zero | `audit-envelope.sh:939-943` (`_audit_chain_validates_lines`; the break returns non-zero at `audit-envelope.sh:951`) |

**The property, stated plainly:** because each entry's content is SHA-256'd and
the next entry pins that digest in its `prev_hash`, any after-the-fact mutation
of a past entry breaks the link from that point forward. The verify-walk starts
at `GENESIS` and stops at the first mismatch — so tampering is not silent, it is
*structurally surfaced* on the next walk. This holds at **zero cost**: no key
material, no signing step, no identity infrastructure is involved in detecting a
tamper. Integrity is a free property of the chain.

### The structural difference vs store-and-trust memory tools

mempalace and its peers **store text and trust it**. They persist a memory and
read it back later as authoritative; there is no mechanism to prove a stored
memory was not altered between write and read. Their durability story is "we
saved it." Ours is "we saved it *and any change to what we saved is detectable*."
That tamper-evidence — not the storage itself — is the moat. It is the property
a store-and-trust design structurally cannot offer without retrofitting exactly
this kind of chain.

---

## Tier 2 — DEFERRED (do NOT claim yet): per-writer authorship / non-repudiation

> Everything in this section is **deferred**. The verbs of authorship — "signed
> by", "proves authorship", "non-repudiation", "attributable to writer" — are
> confined to this section on purpose. Tier 1 above makes no such claim.

The longer-term capability is **authorship**: per-writer non-repudiation via
Ed25519 signatures over the chain-input, validated against a root-signed
trust-store. The point of authorship is to answer "*who* wrote this entry, and
can they deny it?" — a question that is only meaningful once more than one
writer shares a log.

Today, **signing is ARMED but authorship is not yet a meaningful claim**:

- `LOA_AUDIT_SIGNING_KEY_ID=deep-name` is live.
- The trust-store (`grimoires/loa/trust-store.yaml`) is VERIFIED.
- The `trust_cutoff` of `2026-06-29T00:00:00Z` is now PAST.

So the *next* cheval emit will produce the first signed entry. But the log is
**single-operator and gitignored** — there is exactly one writer, and the log is
not shared. With one writer, "who wrote this" has a trivial, uninteresting
answer. A signature here would be attributable-to-writer in a setting where the
writer is never in question, so it proves nothing a reader cares about yet.

**Two-trigger unlock — do not use Tier-2 (authorship / non-repudiation)
language until BOTH hold:**

1. **(a)** New entries are verifiably signed (the signed-count below is > 0 and
   the signatures validate against the trust-store), **AND**
2. **(b)** A shared, multi-writer log exists (more than one writer, log not
   single-operator-gitignored), so "who wrote this" is a real question.

Until both are true, the public claim stays Tier 1 only.

---

## Honest limit — root-of-trust is bootstrap-grade

The cycle-098 root **private** key is still on disk at
`~/.config/loa/audit-keys/cycle098-root.priv` (mode `600`, single operator). The
offline-move is tracked as an OPERATOR-ONLY bead (`bd-root-key-offline-n9nf`) and
the agent MUST NOT run it. Until that move is done, the root-of-trust is
**bootstrap-grade**: anyone with the operator's disk could mint a trust-store
that the verifier would accept. The pinned root **public** key
(`.claude/data/maintainer-root-pubkey.txt`, sourced via
`_LOA_AUDIT_PINNED_PUBKEY` in `audit-envelope.sh:83`) is public and fine to
reference; no private-key material appears in this document, and none should.

This limit constrains Tier 2, not Tier 1. Tamper-evidence (Tier 1) does not
depend on the root key at all — it is a property of the SHA-256 `prev_hash`
chain, which holds with or without any signing infrastructure.

---

## Reproducible signed-count

A reviewer can count signed vs. unsigned envelopes over the live audit log
(`.run/model-invoke.jsonl`) with:

```bash
# Total envelope (non-marker) lines:
grep -v '^\[' .run/model-invoke.jsonl | wc -l

# Entries carrying a non-null signature field:
grep -v '^\[' .run/model-invoke.jsonl \
  | jq -rc 'select(.signature != null) | .signing_key_id' \
  | wc -l
```

(`grep -v '^\['` drops chain seal/recovery markers like `[CHAIN-RECOVERED]`,
which are not envelopes; the `jq` filter counts only entries whose `signature`
field is present and non-null.)

**Measured 2026-06-29: `0` of `1143` envelope entries carry a signature today.**

This is the empirical anchor for the Tier-2 unlock condition (a): the count is
`0`, signing has been ARMED but not yet exercised, so the Tier-2 claim remains
deferred. Re-run the commands after the next cheval emit to watch the count of
signature-carrying entries rise above `0` — and even then, trigger (b) (a shared
multi-writer log) must also hold before the Tier-2 section's language is used.
