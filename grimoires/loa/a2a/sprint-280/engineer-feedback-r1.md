CHANGES_REQUIRED

# sprint-280 (cycle-136 Sprint 1) — Senior Technical Lead Review, round 1

**Reviewer:** lead (Fable 5.1) · **Head reviewed:** `9279db32e` on `feature/cycle-136-bridgebuilder-followups` (contract `3982334a0`; A `4e81a0df5` → `90b259222`; B `92b8ab78f` → `66c35c9c4`, `52e988057` → `5d5080b69`, `613ffad95` → `63f6d1ae3`; lead `81ef8f47d`) · **Report:** `reviewer.md` · **Dissent:** two `adversarial-review.sh --type review` runs (A diff, B diff), each 2/2 voices, consensus, non-degraded — envelopes `~/.cache/loa/cycle-136/dissent/{a,b}-review-envelope.json`.

## Summary

The three beads are implemented as the SDD specifies, every change was red first and reproduced on the landed shas, and FR-5 landed with the lead's `main.ts` hand-off. One correctness gap blocks: the scaffold's single-line check reads only the candidate's first physical line, so an unquoted `if:` whose value continues on the next indented line — a customised multi-line guard beginning with the exact legacy text — is identified as the legacy guard and, with the flag, rewritten into a broken workflow. Three MEDIUM items tighten the same feature's evidence and UX and two of B's tests; the LOWs are a doc mismatch, a test-helper hygiene point and a temp-file leak window. One round.

## Findings

- **HIGH** (confidence: high) `.claude/scripts/lib/scaffold-post-merge-workflow.sh:100` — the candidate `if:` is accepted when its first physical line is single-line, without checking that the next non-blank, non-comment line in the block is not deeper than the child indentation (a plain-scalar continuation). Failure: when a downstream workflow carries `if: needs.classify.outputs.pr_type != 'cycle' && needs.classify.outputs.pr_number != ''` followed by an indented `&& github.ref == 'refs/heads/main'` continuation line then the check reports the legacy guard, and with the flag set it rewrites the first line and leaves the continuation dangling, producing an invalid workflow.
- **MEDIUM** (confidence: high) `tests/unit/mount-workflow-scaffold.bats:199` — every fixture is generated from the synthetic `_wf` template or the hand-written 4-space variant; no case runs the detection over the real pre-cycle-135 `post-merge.yml` that downstream mounts carry. Failure: when the real workflow's indentation, `permissions:` / `outputs:` maps or `run: |` bodies differ from the template in a way the J/C inference or the block tracking mishandles then the suite stays green while production mounts get a wrong verdict.
- **MEDIUM** (confidence: medium) `.claude/scripts/lib/scaffold-post-merge-workflow.sh:134` — with the flag set and the rewrite succeeding, the function prints the full legacy WARN (whose text tells the operator to set the flag they have set) and then the `fixed` notice. Failure: when a CI mount runs with `LOA_SCAFFOLD_FIX_RELEASE_GUARD=1` then every log shows an instruction to set the flag followed by a line saying the rewrite was done, which reads as a contradiction; FR-1 asks for a one-line notice on the flag path.
- **MEDIUM** (confidence: high) `.claude/skills/bridgebuilder-review/resources/__tests__/paged-fetch-contents.test.ts:309` — the WARN-silence case covers `budget`, `skipped_cap` and `aborted` but not `deadline`, and no case pins that an empty-content `text` answer with `additions > 0` is `error` and WARNs. Failure: when a refactor makes a `deadline` outcome WARN or an empty answer stay silent then the suite stays green while the documented contract changes.
- **LOW** (confidence: high) `grimoires/loa/sdd.md:4` — § 4 publishes the failed-read line with an unquoted `<file>` while the implementation and `resources/exclusions-and-coverage.md` quote it through `boundedForLog`. Failure: when an operator or a later implementer reads § 4 as the UI contract then they pin or parse the unquoted form and disagree with the shipped line.
- **LOW** (confidence: medium) `.claude/skills/bridgebuilder-review/resources/__tests__/paged-fetch-contents.test.ts:323` — the `captured` helper swaps `process.stderr.write` and drops the `encoding` and `callback` arguments, with no `{ concurrency: 1 }` on the describe. Failure: when a write site awaits the write callback or node:test runs the describe concurrently then the test hangs or interleaves instead of failing.
- **LOW** (confidence: medium) `.claude/scripts/lib/scaffold-post-merge-workflow.sh:163` — between `mktemp` and `mv -f` no signal handler removes the temp file. Failure: when the installer is interrupted in that window then `.github/workflows/.post-merge.XXXXXX` is left behind and a later `git add .github` commits a duplicate of the workflow.

## Dispositions requested

1. A (HIGH): in the awk pass, after a candidate `if:` line, a following non-blank, non-comment line with indentation deeper than the child indentation C (before the next key at C) makes the candidate multi-line → `notsingle` (silent; with the flag the refuse WARN). Red-first: a fixture with the legacy text and an indented `&& github.ref == 'refs/heads/main'` continuation → silent, byte-identical with and without the flag.
2. A (MEDIUM): add the real pre-cycle-135 workflow as a fixture (`git show 4256a1b3:.github/workflows/post-merge.yml` — the negative-list guard — saved under `tests/fixtures/` or embedded) and assert WARN, byte-identical, and with the flag a one-line rewrite whose result equals the same file with the `simple-release` `if:` swapped to the allowlist text.
3. A (MEDIUM): with the flag set and the rewrite succeeding print only the `fixed` notice; print the legacy WARN only when the flag is off or the rewrite refuses/fails. Update T17, T26, T29 accordingly.
4. B (MEDIUM): add the `deadline` WARN-silence case and the empty-content `text` → `error` + WARN case.
5. B (LOW): make `captured` forward the callback (call it) and pin `{ concurrency: 1 }` on the describe.
6. Lead (LOW): sdd.md § 4 — quote `<file>` in the failed-read line (done in this round).
7. Lead (LOW): the temp-file leak window is filed as a follow-up bead; closing it needs a trap inside a sourced library function, which touches the callers' trap state — not a sprint change.

## Rejected dissent payloads

- A ADVISORY "a legacy guard written as a block scalar or a two-line plain scalar gets no WARN at all": by design — DEC-1067 / DEC-1078 make anything the single-line grammar does not reduce to the two shipped texts "customised and silent"; the two texts Loa ever shipped are single-line, and warning on a prefix match of a multi-line value is exactly the false positive the BLOCKING finding above protects against. Recorded as an operator note (the CHANGELOG line names the single-line form that is detected).

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":3,"low":3},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-280","ts":"2026-10-27T02:19:38Z"} -->
