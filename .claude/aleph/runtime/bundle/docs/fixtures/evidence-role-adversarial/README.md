# Evidence-Role Adversarial Fixture

```aleph-fixture
kind: evidence-role
src_ids: SRC-201..SRC-206
cc_ids: CC-201..CC-205
ledger_total: 5
```

This bounded synthetic fixture exercises the mechanical acceptance criteria from
issue #18. It distinguishes source presence from actual support without asking
the kernel to judge whether a research conclusion is true.

## Seeded cases

| Case | Fixture evidence | Expected clean behavior |
|------|------------------|-------------------------|
| Load-bearing primary observation | CC-201 to SRC-201 | Counts toward support and declares a removal effect |
| Independent corroboration | CC-201 to SRC-202 | Counts toward support without a removal effect |
| Decorative citation | CC-201 to SRC-203 | Remains visible but never counts toward support |
| Synthetic or unverifiable source | CC-202 to SRC-204 | Claim remains unresolved rather than confirmed |
| Contradictory source | CC-204 and CC-205 to SRC-205 | Contradiction survives the merge |
| Independent restatement | CC-204 and CC-205 to SRC-206 | Provenance remains explicit instead of inflating evidence |

The valid baseline has three active carried-or-merged claims, all three with
qualifying support, no inference markers, and a `NEITHER` count of zero.

## Mutation battery contract

Temporary-copy mutations must fail on the intended K3 check:

1. unknown role;
2. edge to a missing or inactive claim;
3. blank removal effect on a load-bearing edge;
4. decorative-only support for a carried claim;
5. accounting that counts a decorative edge;
6. carried claim supported only by an unresolved source;
7. canonical merge claim missing the absorbed contradiction;
8. inference marker with a dangling basis ID.

The source files and all conclusions are synthetic. This fixture validates an
honesty ledger, not factual truth, causal model influence, or a universal source
taxonomy.
