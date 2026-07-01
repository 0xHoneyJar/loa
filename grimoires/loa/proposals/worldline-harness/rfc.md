**Title:** RFC: Worldline Harness — evidence-checked, hook-enforced workflow transitions

**Labels:** rfc, enhancement

## Problem

Loa's workflow gates are mostly prose. The NEVER/ALWAYS tables in `CLAUDE.loa.md` instruct the model; they don't bind it. Surveying the framework's enforcement surface today:

- Exactly **one** wired mechanical evidence gate exists: `adversarial-review-gate.sh` on the `COMPLETED` marker.
- `.claude/hooks/compliance/implement-gate.sh` is complete but **referenced in no settings file** — the "no app code outside /implement" boundary is prose-only despite ready code.
- The spiral harness proved "gates run in bash, unskippable" (`grimoires/loa/proposals/spiral-harness-architecture.md`), but its enforcement only lives while a spiral is dispatched, and its flight recorder is seq+checksum, not hash-chained.
- The strong ledger Loa already owns — `audit-envelope.sh` (RFC-8785 JCS, prev_hash chain, Ed25519, trust-store) — covers the L1–L7 primitives but **not the workflow state machine itself**.

The failure mode: the agent says "I reviewed," "I audited," "I advanced to build" — and no external mechanism verifies the evidence exists. Prose is roleplay-vulnerable; the test is *delete the prompt — does the behavior hold?*

## Strawman

A portable harness kit (co-designed by the operator + Codex; dependency-free Python, ~750 lines, hash-manifested) exists and works end-to-end in a sandbox. Its one genuinely net-new primitive for Loa:

**Evidence-checked transitions.** The workflow state machine lives in an executable `policy.json` (states 1:1 with the golden path; review/audit back-edges first-class). The agent cannot advance state by writing prose — it writes a transition request:

```json
{
  "schema_version": "loa-harness.transition-request/v0.1",
  "from": "PLANNING",
  "to": "ARCHITECTING",
  "actor": "claude-cli",
  "reason": "PRD exists and acceptance criteria are ready.",
  "evidence": [
    {"path": "grimoires/loa/prd.md", "min_bytes": 500, "contains_any": ["Acceptance", "Requirements", "PRD"]}
  ]
}
```

The **Stop hook** validates it (source state matches; destination allowed; evidence files exist, meet `min_bytes`, contain markers). Valid → state advances, request archived, event recorded. Invalid → `{"decision":"block","reason":…}` and the agent keeps working with the harness reason. Every event lands in a hash-chained, verifiable ledger with continuity re-injected at SessionStart/compaction.

**Agent proposes. Harness disposes.**

Proposed integration posture (opt-in, `.loa.config.yaml`, default off):

| Kit piece | Upstream fate |
|---|---|
| Stop-hook transition engine | **Adopt** — nothing in Loa does this today |
| policy.json state machine + evidence map | **Adopt as config** — already maps 1:1 to prd/sdd/sprint/a2a artifacts |
| Hash-chained events ledger | **Emit through `audit_emit`/`audit_emit_signed`** — kit's own chain becomes the portable fallback for bare repos |
| deny-regex / zone globs | **Defer** to `block-destructive-bash.sh` + `zone-write-guard.sh` — declarative references, not reimplementations |
| 9-event portable adapter protocol (`portable_gate.sh`) | **Adopt as contract** — Loa born from Claude Code, runnable under Cursor/Codex/Gemini wrappers |
| Independent review/audit trust rule | **Satisfy with existing machinery** — fagan council / adversarial-review artifacts as transition evidence |

Cheap opener, valuable standalone: **wire `implement-gate.sh`** — zero new code, closes the largest prose-only gap.

## Threat model (what the gate does and doesn't defend)

**In scope:** drift (forgetting the artifact), context-loss (compaction amnesia), and roleplay-under-pressure (prose-asserted completion). **Out of scope for v1:** deliberate evidence fabrication — content markers are spoofable by construction (a 500-byte stub containing "Acceptance" passes the predicate). Three commitments keep the claim honest:

1. **The enforcement surface is not agent-writable.** `policy.json`, harness state, ledger, and hook wiring sit behind the existing zone guards (system-zone protected globs); the harness refuses to run if its own policy file is writable by the actor it constrains. Every ledger event records the policy hash, so "which rules validated this transition" is always reproducible.
2. **Evidence is hashed at validation time** (closes the check-then-mutate window), and high-value transitions (out of REVIEWING/AUDITING) require **provenance-bound evidence** — artifacts produced by an independent actor (fagan council verdicts, adversarial-review JSON, `audit_emit_signed` envelopes) — never content markers alone.
3. **Failure semantics are enumerated, not vibes.** Evidence gates fail closed on policy parse failure, missing state, ledger write failure, or validator crash; flow-preserving hooks (loggers, continuity) fail open. The operator override exists and is itself a ledger event — an audited bypass, never a silent env var.

**State authority (no split-brain):** once the harness is enabled, `policy.json` state is authoritative; `.run/sprint-plan-state.json` and golden-path detection become derived views, with a doctor check that fails loudly on divergence. The opt-in does not ship with both writable.

**Concurrency:** state advancement is single-writer — atomic compare-and-swap keyed on the `from` state, with idempotent transition-request IDs, so multi-session or autonomous runs cannot double-advance or fork the chain.

**Portability honesty:** non-Claude runtimes get these guarantees only once their wrapper calls the gate before side effects; until then the adapter protocol offers reduced guarantees, and the RFC says so rather than implying parity.

## Non-goals

- Not a spiral replacement. Spiral is an orchestrator (drives phases); this is the enforcement floor (validates advancement). They compose — spiral's transitions should eventually emit into the same ledger.
- No cross-repo coordination, no memory/estate governance — workflow state only.
- No new gates on soft seams (judgment, creative latitude, FEEL iteration, operator pairing). Hardening targets transitions, not taste.

## Adjacent findings (independently PR-able, surfaced while grounding this)

1. `implement-gate.sh` — wired nowhere (above).
2. `settings.json` vs `hooks/settings.hooks.json` ship divergent hook sets (karpathy-surgical-diff-check, zone-write-guard, adversarial-review-gate absent from the template).
3. Spiral flight recorder: architecture doc says "immutable audit trail"; implementation is seq+checksum with no prev_hash — `audit-envelope.sh` could close the gap.
4. Construct `workflow.gates` enforcement asymmetry: harness skills get mechanical `disallowed-tools` barriers; construct-declared gates are advisory (`construct-workflow-read.sh` validates, nothing blocks). A hook consuming `.run/construct-workflow.json` would close it.
5. Nothing indexes `.run/*.jsonl` (audit, model-invoke, flight recorders) — a SQLite mirror makes the ledgers queryable.
6. `SessionEnd` / `SubagentStop` / `Notification` hook events are unclaimed surface.

## Open questions (please push back)

1. **Naming** — "Worldline Harness"? The kit calls its state trajectory a worldline; happy to bikeshed.
2. **Fail posture** — proposal: flow-preserving hooks fail-open (Loa's existing invariant), named evidence gates fail-closed. Is that split right for autonomous runs?
3. **Stop-block contract** — keep stdout `{"decision":"block"}` (never exit 2) to preserve the Ctrl+C escape hatch; keep the `stop_hook_active` block-loop guard permissive by default with a strict-mode flag?
4. **State SoT** — policy.json owns *states*, golden-path stays *routing*, spiral converges onto the ledger later. Reasonable ownership split?
5. **Sequencing** — RFC → **shadow mode** (log would-block decisions without blocking; gather false-block data) → sandbox proof (full PLANNING→ARCHIVED cycle, zero prose transitions, tamper test on the ledger) → opt-in enforcement PR train. Anything you'd want proven first?

Kit + reference implementation ready to share as a draft PR if the shape lands. Provenance notes: implementation is Codex-authored — every kit-derived diff goes through the fagan cross-model council before merge; this RFC itself passed a 3-model Flatline review (opus + gpt-5.4-codex + gemini-3.0-pro), whose 6 blockers are folded into the threat-model section above.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
