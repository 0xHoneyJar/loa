# Trust-Root Review — Worldline Harness + loa-laplas

> Ken-Thompson-lens review, 2026-07-01, for RFC 0xHoneyJar/loa#1169

```json
{ "lens": "ken-thompson",
  "verdict": "unsound (as-deployed) · sound-with-caveats (as-designed)",
  "trust_root": "Default posture bottoms out in agent-writable keys under .run/poteau/ (gate.key, reviewers/*.key, run-state.json's reviewer_keys), fenced only by a subshell-bypassable bash hook. The ONE unforgeable anchor (pinned maintainer-root-pubkey + rooted trust-store via resolveGatekeeperPubkey) is proven correct but UNWIRED into every production gate and UNPROVISIONED on disk.",
  "reproduction": "Only compose-bridge's content_receipt and legba's CAS/challenge are true verify-by-reproduction. Segments carry wall-clock authored_at (not byte-reproducible); the ready receipt binds input-hashes, not source->artifact; the kit's ledger and MANIFEST.md are unsigned self-attestations.",
  "one_thing_to_fix": "Wire resolveGatekeeperPubkey (already proven by trust-root-proof.mjs) into poteau-gatekeeper G4/G5, poteau-verify-receipts, and compose-verify's --poteau path, and evict the live reviewer private keys from .run/poteau/reviewers/ — until then every 'cryptographic'/'valid_run' verdict is signed by a key the judged agent can mint." }
```

## Ranked findings (most severe trust-root gap first)

**F1 [HIGH] — The council's cryptographic root is minted inside the attacker's reach; reviewer private keys are live on the agent-writable filesystem.** `reviewer-keys.mjs:41-52` (`ensureKeypair`) writes both `<provider>.key` and `.pub` to `.run/poteau/reviewers/` (default `REPO/.run`); `seed-runstate.mjs:59-64` calls `pubPem()` which *generates* them; G4 (`poteau-gatekeeper.mjs:120-150`) verifies council signatures against those keys. Confirmed live: `claude.key`, `codex.key`, `gemini.key` sit on disk right now. The only barrier is `tool-gate.sh:22-35`, which the file itself calls "FENCE-grade (subshell-bypassable), not hard isolation." The signer of the council is the thing G4 is trying to catch lying. *Close:* from a governed run, read `.run/poteau/reviewers/claude.key` via any path the substring-grep misses (a script file, base64'd path, `find`) -> if it yields the key, the council is forgeable.

**F2 [HIGH] — `run_state.review_routing.reviewer_keys` is an unsigned agent-zone file; G4 reads its own trust anchor from a file the agent can rewrite.** Even without touching the reviewers dir: `run-state.json` lives at `.run/poteau/<run_id>/` (agent-writable), nothing signs it, and G4 (`poteau-gatekeeper.mjs:122-127`) trusts `rs.review_routing.reviewer_keys` verbatim. Rewrite it to keys you hold, self-sign the `councilSubject` (`:136`), pass. `tool-gate.sh:62-70` "protects" `.run/poteau/` but is the same fence, plus the `packet.json` carve-out and same-uid subagents. *Close:* rewrite `reviewer_keys` + self-sign -> gate mints a pass.

**F3 [HIGH] — Default gate mint and gate verify both root in a co-located, agent-writable key.** G5 default (`poteau-gatekeeper.mjs:216-228`) signs with `.run/poteau/gate.key` unless `LEGBA_SIGNER_SOCKET` is set; `POTEAU_REQUIRE_CUSTODY=1` is needed to fail-closed — both off by default. The verifiers (`poteau-verify-receipts.mjs:47-51`, `compose-verify-run.sh:567`) check against `.run/poteau/gate.key.pub`, sitting next to the private key. A subverted agent regenerates a keypair, writes `gate.key.pub`, re-signs the whole `receipts.jsonl` -> verify exits 0 "authentic." The code prints a WARNING (`:217`) but does not fail. *Close:* regenerate keypair, re-sign chain, run `poteau-verify-receipts.mjs <chain> gate.key.pub` -> exit 0.

**F4 [MED] — `proof_class:"cryptographic"` is stamped on file-presence, not on a rooted verification.** `compose-verify-run.sh:233` sets `cryptographic` whenever `POTEAU_GOVERNANCE=="armed"`, and `armed` is set purely by `run-state.json` existing (`:208`) — independent of whether any signature verified or whether the key is rooted. A co-located agent-writable `gate.key.pub` earns the identical label as a daemon-held key. The word "cryptographic" is the claim; the substrate emitting it can forge the state the word describes. *Close:* verify an armed run with the default on-disk pubkey -> output says `proof_class:cryptographic` with no rooted anchor anywhere.

**F5 [MED] — The one sound trust root is proven, unwired, and unprovisioned.** `resolveGatekeeperPubkey` (`legba-core.mjs:326-374`) + `trust-root-proof.mjs` demonstrate the cure end-to-end; the proof's own closing text says it is "what poteau/settle/compose-verify do not yet reach for ... The cure is real; it is unwired." Confirmed: `~/.config/loa/trust-store.yaml` and `~/.config/loa/maintainer-root-pubkey.txt` **do not exist**. Worse, legba's pinned path (`~/.config/loa/...`) is a *different* file from the one loa already ships and pins (`.loa/.claude/data/maintainer-root-pubkey.txt`) — two roots, neither wired to the other. And the `--legba` compose gatekeeper key is per-run ephemeral (`compose-bridge.mjs:125`, `legba:compose:${runId}`), so it can *never* appear in an operator store -> strict `verifyRun` returns `key_not_rooted` -> the `--legba` terminal gate cannot pass in strict mode over a compose run. The anchoring machinery is inert in the deployed state. *Close:* provision the two files, wire the resolver, and the ephemeral-key contradiction surfaces immediately.

**F6 [MED] — The ready receipt binds input hashes, not source->artifact, and is unsigned.** `laplas-ready.mjs:90-99` hashes `jcs(quest/party/dungeon)` and writes `.run/poteau/ready.json` unsigned. It proves "these three inputs had these hashes," not that the emitted `.workflow.js` segments were compiled *from* them. Segments stamp wall-clock `authored_at` (`compose-dispatch.sh:418,429`), so recompiling the same module does **not** byte-reproduce. There is no diverse-double-compilation analog for segments — only `room_id` (fixed `created_at`, `:318`) and `content_receipt` are reproducible. *Close:* recompile a module twice, diff segments -> `authored_at` differs; `ready.json` names no segment hash.

**F7 [MED] — The kit's ledger is unsigned with no external anchor; a wholesale rewrite verifies clean.** `loa_harness.py:505-533` recomputes `event_hash` and checks `prev_hash` linkage, but there is no signature and the `head_hash` lives in the same SQLite the same process writes (`:294-297`). An agent that writes `events.jsonl` recomputes the chain forward from `"genesis"` -> verify passes. This is exactly the wholesale-rebuild weakness `compose-bridge`'s content-receipt was built to close — and the kit has no anchor at all, despite the machinery report flagging loa's signed `audit-envelope.sh` as the STRONG reuse candidate. *Close:* edit event 2, recompute all hashes forward, `loa_harness.py verify` -> exit 0.

**F8 [LOW] — The kit's Stop-transition evidence is a substring in an agent-authored file.** `policy.example.json:67-78` gates REVIEWING->AUDITING on `engineer-feedback.md` containing `"APPROVED"`; the agent writes that file (`loa_harness.py:393-412` = exists + min_bytes + substring). `ARCHITECTURE.md:188` says review/audit "should require either deterministic checks or a fresh independent session ... captured as evidence" — the reference policy implements neither. "Agent proposes, harness disposes" is defeated by writing the magic word. *Close:* `echo APPROVED >> .../auditor-feedback.md`; request AUDITING->SHIPPING -> advances.

**F9 [LOW] — MANIFEST.md is a self-attestation with no signer.** `MANIFEST.md` is SHA-256-per-file generated by the same toolchain that produced the files; nothing signs it and no `verify` checks against it. A subverted generator emits a matching manifest — Thompson's exact move. Useful as an accidental-drift index, not an authorship proof.

**Praise (genuine trust->reproduction):**
- `compose-bridge.mjs:59-112` `content_receipt` — a *pure* function of ordered envelope content, anchored in a **different writer's** append-only trail and best-effort into loa's signed audit chain. Honest re-derivation reproduces it; a rebuilt `legba/` over tampered envelopes does not (`checkAnchor:172-179`). This is the one place trust is reduced to reproduction, not assertion.
- `legba-core.mjs:387-397` (CAS rejects a blob whose content != its hash-name) + `:578-589` `challenge()` (fraud-proof by re-execution). Reproduction is the verdict there.
- `trust-root-proof.mjs` — an honest artifact that proves the cure *and* names its own unwired regress. The self-awareness is the asset.

## Minimal TCB for a `valid_run` (default/deployed posture)

| Must be trusted (not verified) | Location | Why it's TCB, not verifiable |
|---|---|---|
| `node` + `node:crypto`, `python3` | runtime | primitives; unverified floor |
| `poteau-gatekeeper.mjs` | the judge | mints every pass; subvert it, forge all |
| `.run/poteau/gate.key(.pub)` | agent-zone | signer key AND verify anchor, co-located, agent-writable (F3) |
| `.run/poteau/reviewers/*.key` | agent-zone | council private keys, live on same FS (F1) |
| `.run/poteau/<run_id>/run-state.json` | agent-zone | unsigned; carries `reviewer_keys`, `task`, `mandated_reads` (F2) |
| `tool-gate.sh` | fence | the ONLY barrier over the above; subshell-bypassable bash |
| `laplas` `ready.json`, `seed-runstate.mjs`, `reviewer-keys.mjs` | emitter/agent-zone | generate the keys they later trust; unsigned receipt (F6) |
| kit `MANIFEST.md`, `events.jsonl` chain | self-attested | unsigned; head in same store (F7, F9) |

With daemon custody + rooted store wired, this collapses to the set worth aiming at: `node:crypto`, the **signer daemon process** (in-memory key, `legba-signer-daemon.mjs`), and the **out-of-band pinned `maintainer-root-pubkey.txt`**. Everything else becomes verified.

## Recommendations

**(a) worldline-harness PR:**
1. **Do not ship the kit's parallel unsigned chain.** Emit through loa's existing `audit-envelope.sh` (`audit_emit_signed`) + `jcs.sh` — the machinery report already marks this STRONG reuse. One signed, trust-store-rooted ledger; the wholesale-rewrite test (F7) then fails because the head is signed by a key outside the agent's reach.
2. **Implement the trust boundary the ARCHITECTURE already states (`:188`).** Replace substring-marker evidence (F8) with a fresh-independent-session transcript, hashed and signed — the same agent must not both perform and self-certify a gate.
3. **Sign MANIFEST.md with the pinned root and add `verify --manifest`.** An unsigned manifest is a drift index only — say so in-file; require the signature before install.

**(b) loa-laplas:**
1. **Wire `resolveGatekeeperPubkey` into G4/G5, `poteau-verify-receipts`, and compose-verify's `--poteau` path** — the cure `trust-root-proof.mjs` already proves. Provision `~/.config/loa/{trust-store.yaml,maintainer-root-pubkey.txt}` (currently absent) and reconcile the two pinned-root locations. This resolves F2, F3, F5 together and exposes the ephemeral-compose-key contradiction that must be fixed for `--legba` to mean anything.
2. **Default `POTEAU_REQUIRE_CUSTODY=1` and run the signer daemon for any competitive-REL run; move reviewer signing behind the same daemon.** No gate or reviewer private key should ever land in `.run/`. The live `claude.key`/`codex.key`/`gemini.key` are the standing forge — evict them (fixes F1, F3).
3. **Gate `proof_class:"cryptographic"` on `resolved.status=="rooted"`, not run-state presence or a co-located pubkey** (fixes F4). Sign `run-state.json` or bind its hash into the ready receipt + gate receipts so `reviewer_keys` cannot be rewritten mid-run undetected (reinforces F2).
4. **Bind source->artifact and make emission byte-deterministic** (fixes F6): put the ready receipt's three manifest hashes *and* a hash of each emitted segment into `form-c-manifest.json`, and drop/pin the wall-clock `authored_at`. That gives a real diverse-double-compilation check — a second toolchain recompiles the module and diffs to byte-identity, which today only `room_id` and `content_receipt` support.

## Key files (absolute)

loa-laplas: `/Users/zksoju/bonfire/loa-laplas/poteau/bin/poteau-gatekeeper.mjs`, `.../poteau/bin/reviewer-keys.mjs`, `.../poteau/bin/poteau-verify-receipts.mjs`, `.../poteau/hooks/tool-gate.sh`, `.../poteau/hooks/exit-gate.sh`, `.../laplas/bin/laplas-ready.mjs`, `.../laplas/lib/seed-runstate.mjs`, `.../scripts/legba/legba-core.mjs`, `.../scripts/legba/compose-bridge.mjs`, `.../scripts/legba/legba-signer-daemon.mjs`, `.../scripts/trust-root-proof.mjs`, `.../scripts/compose-verify-run.sh`, `.../scripts/compose-dispatch.sh`.

kit: `/Users/zksoju/bonfire/grimoires/loa/context/loa-claude-harness-kit/bin/loa_harness.py`, `.../config/policy.example.json`, `.../docs/ARCHITECTURE.md`, `.../MANIFEST.md`.
