# Cycle Plan — OKF/ICM Adoption & Audit Activation

**Source of truth:** `grimoires/loa/proposals/okf-icm-comparative-analysis-2026-06-27.md` (PR #1155) + grounding brief `okf-cycle-grounding-brief-2026-06-28.md`.
**Base:** origin/main `1eeadff8`. **Ledger counter at start:** 226.
**Theme:** normalize + index the knowledge corpus, speak the settled interop standards on the wire, and *activate* (or honestly relabel) the dormant audit moat — without weakening any fail-closed gate.

This plan turns the 14 report recommendations into **9 sprints**. Each code-touching sprint runs `/implement` → `/review-sprint` → `/audit-sprint`. System-Zone (`.claude/`) writes are cycle-authorized here.

---

## Folded inbound issues (verified)
The "machine-verify a hand-maintained doc claim, fail CI on drift" cluster folds into **Sprint 2** (one primitive, not per-issue machinery): **#1143** (umbrella AC), **#1132** (Quick Start 5-vs-4 golden-path commands), **#1135** (command-count generated verification), **#1149** (docs-generation proof), **#1130/#1124** (version-surface parity).
**NOT absorbed** (separate installer/update-reconcile cycle): #1138/#1150/#1123/#1131/#1136/#1144/#1151 + codex audit-lane PRs #1152/#1153. zkSoju #1108/#1109/#1110 are independent (zero file overlap).

---

## Sprint 1 — Quick wins: doctrine + honest relabel  *(effort S, no blockers, fully agent-doable)*
**Goal:** land the cheap, high-confidence boundary-making changes.
- **R11** — write the OKF fail-soft **non-adoption** rule into `.claude/rules/zone-state.md`: "OKF §5.3/§9 fail-soft consumption MUST NOT enter any loa validator or decision gate; dangling internal references remain defects."
- **R12** — **OKF ingest contract** (doc only) in `grimoires/loa/proposals/`: parse-soft / promote-strict, route through `cross-repo-status-lib.sh` boundary, `audit_emit` "fields-NOT-validated" at ingest, no code until a real feed exists.
- **R6b** — relabel the dormant **Ed25519/L4** tier EXPERIMENTAL/build-ahead in `graduated-trust-lib.sh` header + `agent-network-reference.md` (L4 §, lines ~55-74); delete nothing; note `enabled:false` default + standards-contribution intent.
- **R8-precursor** — write the **file-presence-authority contract** (filesystem markers authoritative for position; `.run` position fields are a derived cache; circuit-breaker/autonomy counters stay first-class) into a runbook.
**Acceptance:** the 4 docs/relabels exist with the exact wording; no behavior change; `validate-framework` + markdown lint green; L4 still loads but reads as EXPERIMENTAL.

## Sprint 2 — Generated truth surface: AGENTS.md + drift gate  *(effort M, closes 6 issues)*
**Goal:** emit the 2026 lingua-franca file as a *generated* artifact and machine-check doc claims.
- **R3** — new `.claude/scripts/agents-md-gen.sh` (sibling of `butterfreezone-gen.sh`; determinism LC_ALL=C/TZ=UTC, lock, atomic_write, `--check`/`--json`). Emits root `AGENTS.md`: purpose, Quick Start, Commands (golden-5 table + generated count), Project Governance (NEVER/ALWAYS/MAY + Three-Zone from CLAUDE.loa.md), Conventions, Context-Intake (known-failures-first). Keeps BUTTERFREEZONE.md as the codebase-map sibling (different audience; not replaced). *(Operator note: "convert butterzone to agents" implemented as the butterfreezone generator-pattern reused to emit AGENTS.md; BUTTERFREEZONE retained — flag for confirmation.)*
- `.claude/data/golden-path.json` — canonical golden-5 + excluded-from-count list (operator decides the 5 exclusions; reconciles 53 command files → README's "48").
- **MUST-FIX** operator-detection collision: patch `autonomous-agent/operator-detection.md` + SKILL.md so a *generated* AGENTS.md (carrying the generated-by sentinel) does NOT count as an AI_OPERATOR signal.
- `.github/workflows/agents-md-drift.yml` (copy `model-registry-drift.yml`): checksum lockfile (`AGENTS.md.checksum`, body-only) + `--check` regen job.
- **Folds #1132/#1135/#1143/#1149/#1130/#1124**: a `--check` consistency assertion (README golden list == golden-path.json; "48 total" == files-minus-excludes; version surfaces agree) that fails CI on drift; fix README #1132 (include `/loa` or reword).
**Acceptance:** `agents-md-gen.sh` byte-deterministic; AGENTS.md present + drift gate fails on tampered claim; #1132 doc fixed; operator-detection no longer flips on generated AGENTS.md.

## Sprint 3 — Global cross-family grimoire index  *(effort M, keystone)*
- **R1** — new `.claude/scripts/grimoire-index.sh` (skeleton from `construct-index-gen.sh`): walks 6 families (KF / vision / lore / handoff / obs / L-NNNN), emits `grimoires/loa/INDEX.md` + `.run/grimoire-index.json` with id/type/path/raw-outbound-refs; per-field control-byte sanitization (L5/L6/L7 untrusted-body rule); obs surrogate key; `--validate` (flag KF Index-vs-heading drift); flock + atomic write; bats tests; wire to a workflow boundary.
**Acceptance:** valid JSON+MD over the real grimoire; never interprets body prose; validate catches a planted drift; idempotent.

## Sprint 4 — OKF read-only export skin  *(effort M)*
- **R4** — new `.claude/scripts/okf-export.sh` (mirror `butterfreezone-gen.sh`) → `.run/okf-bundle/` (State zone), v1 scoped to **handoffs + observations** (already-typed). Conformant OKF v0.1: one `.md`/concept, path-as-identity, `type` + recommended fields, per-dir `index.md`, root `okf_version`. Grimoire stays source of truth (derived projection, downstream of gates).
**Acceptance:** output passes OKF conformance (parseable frontmatter + non-empty `type`); round-trips handoffs+observations; no secret shapes (MODELINV redaction discipline).

## Sprint 5 — KF/NOTES minimal-conformance writer  *(effort M)*
- **R7** — new `.claude/scripts/kf-write-lib.sh`: append-only KF entry writer (per `## Schema`, insert Index row, recurrence increment, Attempts-row append) that blocks ONLY on the load-bearing Evidence cell (SHA/PR/run-ID) + non-empty id/Status; free-text the rest. Reuse `kf-auto-link.py` parse grammar. NOTES: date+cycle header helper (advisory). Never bot-auto-appends (preserve anti-tamper).
**Acceptance:** idempotent; never rewrites existing entries; blocks a KF append missing Evidence; bats coverage.

## Sprint 6 — ICM Layer-2 inputs manifest (advisory)  *(effort M)*
- **R5** — add advisory `inputs:` block to SKILL.md frontmatter (known-failures-first), authored via `/implement` (System Zone). WARN-only rot-lint in `validate-skill-capabilities.sh` (flags a declared path absent on disk; NEVER flags an undeclared read — conditional-by-phase reads make that wrong-by-construction). Sold as glass-box/drift, NOT token budget.
**Acceptance:** manifest present on representative skills; lint WARNs on a planted missing-path; no fail-closed declared-but-not-read gate.

## Sprint 7 — File-presence authority + next-bug-sprint-id fix  *(effort L, has mandatory test)*
- **R8** — make filesystem markers authoritative for workflow POSITION; `.run/sprint-plan-state.json` position fields = derived cache reconciled before use; circuit-breaker/autonomy counters stay first-class. reconcile-before-trust in run-mode/simstim resume (extend `--sync-run-mode` to use COMPLETED/APPROVED markers). **Mandatory drift-repro bats test** (RUNNING-while-committed → filesystem wins; counters preserved).
- Fix `next-bug-sprint-id.sh` in-file body grep (harvests `sprint-bug-622` → next=623; true next from ledger+1); regression test.
**Acceptance:** drift-repro test passes; next-id = ledger+1 given a stray body token.

## Sprint 8 — Cross-session recurrence detector (propose-only)  *(effort L)*
- **R9** — new read-only detector scanning trajectory/a2a JSONL + KF Attempts for a normalized finding recurring ≥3× across sessions; SURFACES a proposed source edit (KF Attempts-row draft / skill amendment) for human review. NEVER writes `.claude/` or auto-appends known-failures.md. Conservative matching + human-applies-via-/implement.
**Acceptance:** emits a proposal artifact, writes nothing authoritative; over-classification guardrails.

## Sprint 9 — Audit activation (agent-doable half) + maintainer handoff  *(effort L, PARTIALLY BLOCKED)*
- **R2** — **bash strict-mode parity**: give `audit-envelope.sh` `audit_verify_chain` a strict/`--verify-for-merge` mode mirroring Python (refuse BOOTSTRAP-PENDING with `[TRUST-STORE-BOOTSTRAP-PENDING]`/ATK-3; refuse local-pubkey fallback). Wire an **operator-opt-in** gate (post-merge / run-mode PR path) that **fails closed on BOOTSTRAP-PENDING** until bootstrapped — never the producer-writable fallback. Prepare the `keys[]` PR (runbook Steps 1-3).
- **MAINTAINER-COMPLETABLE (cannot be done by an agent — flag):** Step 4 offline root-sign of the trust-store (needs the air-gapped root private key held by @janitooor); enable `LOA_AUDIT_SIGNING_KEY_ID` going forward; resolve the `trust_cutoff` / pre-signing-history `[STRIP-ATTACK-DETECTED]` precondition (advance cutoff or seal history). Documented as the operator ceremony.
**Acceptance:** bash strict mode refuses BOOTSTRAP-PENDING under test; gate is opt-in + fails closed; ceremony doc complete; maintainer step clearly handed off.

---

## Sequencing & dependencies
1 (no deps) → 2 (independent) → 3 (keystone; 4 depends on 3's normalization for richer export but v1 doesn't) → 4 → 5 → 6 → 7 → 8 (benefits from 3) → 9 (independent; partial blocker).
**Recommended order:** 1, 2, 3, then 4–9 as capacity allows. 1+2 are the highest value-to-risk.

## Cross-cutting guardrails (apply to every sprint)
- KEEP (R10): never collapse cheval/Flatline substrate or the review/audit gates; simplify only prose wrappers.
- Every System-Zone (`.claude/`) write goes through `/implement` (cycle-authorized) via the Bash-patcher (zone-write-guard blocks Edit/Write, not Bash).
- Every generated artifact ships with a determinism + drift gate (the `model-config.yaml.checksum` pattern).
- No recommendation justified on token-budget grounds.
