# Checker Specifications — Implementation Constraints

> Status: ACCEPTED FOR IMPLEMENTATION by
> [`Decision 0003`](../../decisions/0003-architecture-build-kit-implementation.md).
> These specs define each kernel increment (K1-K6 from
> [`../06-verification-and-conformance.md`](../06-verification-and-conformance.md) §2),
> precisely enough that no design decisions remain — only code. Each
> increment lands **in lockstep with its motivating fixture, in the same
> PR**, never ahead of it.

## Non-negotiable implementation constraints (inherited from slices 3–4)

1. **Node built-ins only** (`node:fs`, `node:path`, `node:url`). No
   `package.json`, no lockfile, no dependency, no build step, no network, no
   subprocess.
2. **Read-only.** The checker writes nothing and mutates no repo state.
3. **Fail-closed.** Exit 0 only when every applicable check passes. Any
   violation prints a `FAIL` line and exits non-zero.
4. **Exact failure lines.** Format (extends the existing convention):
   `FAIL <scope> <check-id> (<label>): <what> <where>` — e.g.
   `FAIL run-slice-2 K2.4 (packet resolution): PKT-0031 locator L44-L48 hash mismatch in ledgers/packet-index.md`.
   Every spec below fixes its check-ids; batteries grep for these exact ids.
5. **Targeted parsing, not a framework.** Small readable helpers + targeted
   regexes, in the existing script's style. Reuse the existing helpers
   (`tableCells`, `isSeparatorRow`, `headingSection`, `envelopeSection`)
   before writing new ones. Table rows parse with the hardened
   optional-trailing-pipe rule already in the script (non-empty trailing
   fragments count as cells; exact column counts enforced).
6. **`--root <dir>`** keeps working for every new mode — the battery runs the
   real checker against temp copies.
7. **False-positive guards are part of every check.** Each spec lists
   legitimate patterns that must NOT fire; the battery includes them as
   must-stay-green cases.
8. **No semantic judgment.** If a proposed check needs to understand meaning
   rather than structure/accounting/reference, it is mis-tiered — move it to
   the T2 harness and strike it from the spec.

## File layout decision (for the builder)

Keep `scripts/validate-precis-fixtures.ts` as-is for the fixture layer.
Implement run-directory mode as a **new sibling script**
`scripts/validate-run.ts` (invoked `node scripts/validate-run.ts
[--root <dir>] --run <path-to-run-dir>`), sharing nothing by copy-paste that
can be shared by a small `scripts/lib/` module **only if** both scripts stay
dependency-free and each remains runnable standalone. If sharing forces
complexity, duplicate the few helpers instead — smallness beats DRY here.
`--json` (K7) is a flag on both scripts emitting
`{ result, checks: [{id, scope, status, message}] }` to stdout; human output
unchanged by default.

## Negative-battery protocol (every increment)

For each battery case: copy the target tree to a temp root; inject exactly
one violation; run the **real** checker with `--root`; assert (a) non-zero
exit and (b) the intended check-id appears in a `FAIL` line (grep the id,
not just the exit code); finally run an unmutated copy and assert exit 0.
Batteries are documented in the increment's PR description. This implementation
also keeps the cross-group battery executable at
`scripts/test-conformance-mutations.ts` so future kernel changes can replay it
locally.

## Increment index

| spec | check groups | motivating fixture | roadmap slice |
|------|--------------|--------------------|---------------|
| [`K1-K2-fixtures-and-runs.md`](K1-K2-fixtures-and-runs.md) | K1 discovered-fixtures; K2 run-directory | golden run `docs/fixtures/run-slice-2/` | 9 (K2), 12 (K1) |
| [`K3-evidence-roles.md`](K3-evidence-roles.md) | K3 | evidence-role fixture | 10 |
| [`K4-K5-route-cards-and-gate.md`](K4-K5-route-cards-and-gate.md) | K4 cards; K5 taint gate | routed-corpus fixture | 11 |
| [`K6-projection-trace.md`](K6-projection-trace.md) | K6 | first projection fixture | 16 |
