# Pre-registration addendum 15 — cycle-132

**Supersedes:** `REGISTRATION-13.json` sha256 `05fa23fe8c69ce300fd3f704234d9b477e5394ccd2980b4eee383b0f0839a33a` (pipeline pin `fbd36a0c9880b244af08133013f3b6959b085c94`, tree `6ee50833…`). **Registered as:** `REGISTRATION-14.json`. **Governing text:** `PREREGISTRATION.md` is unchanged. **Scope:** the analysis module's input validator and one sensitivity dispatch (`evals/analysis/c132`), and the judge-description builder (`evals/harness/defect-descriptions.py`). No arm runs any of these, and the pipeline pin is unchanged.

## What the Sprint 270 audit found

The audit's dissent rated one finding medium. Since addendum 11, the validator accepts a row whose registration hash appears anywhere in the declared `supersedes` chain, including a predecessor the chain names but no file backs. It also never checks that a `supersedes` value is a sha256. A registration could therefore admit rows stamped with a hash that no inspectable registration has. No row of this cycle carries such a hash: every Phase 1 row sits under REGISTRATION-8 or REGISTRATION-10, and the chain resolves on disk with nothing unresolved. The gap is still in the gate the final read relies on, so it closes before that read.

The audit also rated one finding low, in the description builder. Its leak check exempted a token found anywhere in the PR content as a substring, including tokens the operator had forbidden outright, whereas the judge sampler never exempts batch or run ids.

## What changed

- **Validator.** A row is accepted only under the passed registration, or under a predecessor whose file was found by its bytes. Every `supersedes` value must match `^[0-9a-f]{64}$`. An unresolved predecessor stays in the reported lineage and is refused for rows.
- **Description builder.** Forbidden tokens are never exempt. An arm or trial token is exempt only when the PR content contains it as a whole token. A malformed manifest entry or an unreadable PR file is refused instead of crashing.
- **Legacy sensitivity name.** `class9_nonrepo_egress_reincluded` computes its one read directly; its output is byte-identical.

The descriptions file rebuilt with the new builder is byte-identical to the committed one, so the judge's packets and labels are untouched.

## Why this is a correction, not a design change

A validator meant to bind rows to inspectable registrations should not accept a hash nothing backs. The change only narrows what is accepted, and no Phase 1 row is affected.
