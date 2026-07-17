# 06 — Verification and Conformance

> Status: ACCEPTED FOR IMPLEMENTATION by
> [`Decision 0003`](../decisions/0003-architecture-build-kit-implementation.md).
> The implemented K1-K6 substrate extends the existing checker in lockstep
> with fixtures; semantic judgment and authority remain outside T1.

## 1. The three tiers, and the boundary that matters

| Tier | Instrument | Question it answers | Failure posture |
|------|------------|---------------------|-----------------|
| T1 | Conformance kernel (deterministic script(s), Node built-ins, read-only) | "Is the artifact structurally sound — IDs resolve, accounting balances, boundaries hold?" | fail-closed, exact `FAIL` lines |
| T2 | Verification harness (fresh-context model judges) | "Does the judgment survive attack — is the disposition defensible, the merge real, the synthesis faithful?" | refutations force `unresolved`/flags; disagreement surfaces, never smooths |
| T3 | Human authority | "Is this accepted? Is this referent supplied? Is this scope right?" | recorded sign-offs at PR checkpoints |

The boundary rule, inherited from the checker doc and made stack-wide:

> **T1 never judges semantic truth. T2 never gates merges to `main`. T3 is
> never asked to re-derive what T1 can check.**
> Allowed for T1: "`CC-107` exists in §4 and the ledger agrees." Not allowed:
> "`CC-107` was correctly judged excluded" — that is T2's question, and even
> T2 answers only "the judgment survived adversarial review", never "it is
> true."

This division is also the answer to the open hard-vs-soft conformance
question, stated as a proposal: **hard checks live in T1 and are few, stable,
and fail-closed; everything judgment-shaped is T2 and produces evidence, not
exit codes.** A T2 finding blocks a run through the DoD, not through the
kernel — so the kernel never accretes brittle prose-policing.

## 2. Conformance-kernel roadmap

The kernel starts from `scripts/validate-precis-fixtures.ts` exactly as it
is. Growth is additive check groups, each landing **in lockstep with the
fixture that motivates it** and each shipping with a negative battery run
through the real checker via `--root` temp-copy mutation (the established
protocol — every case must fire its intended `FAIL` line; a clean copy must
stay green).

| Increment | Check group (names provisional) | Motivating fixture (doc 10 slice) | What it enforces |
|-----------|--------------------------------|-----------------------------------|------------------|
| K1 | discovered-fixtures mode | none (pure generalization) | today's checks over any `docs/fixtures/*/` set, per-fixture expectations declared in the fixture README rather than hardcoded — the checker doc already lists this as deferred |
| K2 | `RUN-*`: run-directory mode | hand-authored golden run | layout present; manifest well-formed; state log ordered; fixed-home ID integrity across `RUN` through `PRJ`; ledger accounting |
| K3 | `E-*`: evidence-role checks | evidence-role fixture | role-coverage accounting; bounded role vocabulary; decorative-never-counts; unresolved-source-never-confirms; removal-effect declarations present for load-bearing edges; merge keeps per-source roles |
| K4 | `RC-*`: route-card checks | routed-corpus fixture | card invariants (≥1 packet ID; IDs resolve; closed posture set; pending-referent ⇒ `REF` row); tags-not-documents; the smallest manual-mode invariant, now enforced |
| K5 | `G-*`: gate checks | same fixture as K4 | taint computation: no "externally complete" marker while an unresolved `REF` sits in the provenance cone |
| K6 | `PT-*`: projection-trace checks | first projection fixture | commissioned `PRJ-*`/trace/hash binding; selection coverage; statement→claim resolution; no-new-claims; negative-boundary honor |
| K7 | `--json` machine report + run-in-CI decision | with K2 | deferred items from the checker doc, picked up only when run mode makes them useful |

Standing rules (unchanged from today's discipline):

- No check without a fixture. No fixture without its README self-checks.
- Every new group extends the negative battery; the old batteries keep
  passing.
- The kernel encodes the *accepted provisional* shape — when the envelope or a
  ledger shape is amended, checker and fixtures move in the same slice.
- Deferred-as-brittle stays deferred: disposition-themed prose-section
  membership, wording-match checks, and anything the checker doc already
  rejected as prose-policing stays out of T1 (T2 covers the same risks with
  judgment instead of regexes).

## 3. Verification-harness specification

The harness is *procedure plus evidence format*, not a service:

- **Unit:** a verdict (artifact 15) — target, lens, fresh-context attestation,
  outcome (`upheld` / `refuted` / `cannot-determine`), written rationale,
  ledger consequence.
- **Lenses:** the slice-2 risk families operationalized — silent
  disappearance, lazy merge, false certainty, unsupported exclusion,
  projection leakage, duplicate conviction, contradiction hidden by synthesis
  — plus evidence-removal and entailment. Each lens has a one-paragraph
  charter in the prompt-pack; lens diversity is preferred over redundant
  identical refuters (different failure modes need different eyes).
- **Sampling policy per stage** (dials owned by the manifest; defaults set at
  the dry-run slice): exhaustive review for `excluded-with-reason`,
  contradictions, merges above a size threshold, and every load-bearing
  evidence edge in adversarial clusters; stratified samples elsewhere.
  Sampling rates are honesty-critical: they appear in the Précis verification
  summary, so a reader can see how much was checked, not just that checking
  happened (T12 — expose the burden).
- **Quorum:** default 1 refuter per sampled target, 3-refuter quorum
  (majority) for exhaustive-class targets; `cannot-determine` from any refuter
  on an exhaustive-class target escalates to a second round, then to
  `unresolved`. Numbers are starting points to be tuned on replay evidence.
- **Independence:** verifiers are fresh-context (no run history), see only
  what their lens requires, and where the lens is re-derivation they do not
  see the original verdict at all. Verifier-of-verifier recursion is
  explicitly out — one adversarial layer plus quorum, then a human, is the
  ceiling (bureaucratic overgrowth is a named risk).

## 4. Disagreement is a result

The harness never averages away conflict. Outcomes and their forced
consequences:

| Situation | Consequence |
|-----------|-------------|
| Refuter upholds | note on the verdict ledger; nothing changes |
| Refuter refutes, producer's judgment cannot be defended | superseding ledger entry (e.g. disposition → `unresolved`), run-log entry, and — if a pattern — a lessons entry |
| Quorum splits | `unresolved` + flag; the split itself is recorded (it is information about the corpus, not noise) |
| `cannot-determine` dominates | the claim/merge/card is marked and the known-incompleteness section must mention the class |

## 5. Golden replay protocol (the eval harness)

Replay is how capability claims earn "validated" (T11):

- **Golden corpus:** a frozen corpus + an accepted run directory (produced by
  hand or by an accepted supervised run). Slice-1 and slice-2 fixtures are
  proto-goldens; the roadmap adds a full run-directory golden, a real-corpus
  golden (instance #1), and the convergent-arm golden.
- **Replay:** execute the pipeline (agent mode; or manual mode for
  mode-equivalence checks) against the frozen corpus with pinned Core, adapter,
  bundle, checker, protocol/run-format, host/model, and runtime-snapshot
  identities; diff the resulting ledgers against the golden. Do not substitute
  a newer bundle into an existing replay.
- **Metrics (defined with the first replay slice, reported per run):**
  - extraction recall against golden packets (misses are the cardinal sin);
  - claim coverage and normalization equivalence (same claims found, allowing
    wording variance — matched by provenance sets);
  - disposition agreement rate, overall and per disposition class;
  - merge precision/recall against the golden merge map;
  - phantom rate (IDs or assertions with no golden counterpart — fabrication);
  - evidence-role agreement (once K3 exists);
  - kernel-clean rate and harness-flag rate;
  - cost and wall-clock (so tiering decisions are evidence-based).
- **Acceptance thresholds are authority decisions per slice** — this plan
  deliberately does not invent numbers. The rule it does fix: **a capability
  is "validated" only when its replay metrics met the thresholds the
  authority set for that slice, and the validation ledger entry cites the
  replay.**
- **Regression:** goldens are permanent. Any change to prompts, contracts, or
  models re-runs affected replays before the change is accepted (the
  research-pipeline analogue of a test suite).

## 6. Mode-equivalence verification

The T7 invariant is tested, not presumed: on a designated golden corpus, a
manual-mode run and an agent-mode run are both executed; equivalence is judged
on the contract level (same completeness accounting, equivalent claim
inventories by provenance-set matching, same taints surfaced) with divergences
adjudicated by the authority and folded into either the runbooks (if a mode
was under-specified) or the validation ledger (if a mode has a real
limitation). Reconstructability is tested in the same exercise: an agent must
rebuild the full derivation graph from the human run's sparse cards plus raw
source, with zero unresolvable references.

## 7. The validation ledger, extended

`docs/routing-and-clustering.md` §12 stays the format. This plan extends its
scope from routing arms to pipeline capabilities. Illustrative future shape
(content set only by evidence):

```
validated:
  - heavy adversarial arm                      (Straylight precedent; slice-2)
  - deterministic projection trace contracts  (fixtures: run-slice-2 and projection-adversarial)
  - <capability>                               (replay: <golden>, <date>, PR #NN)

not yet validated:
  - heavy convergent competitor/category reconciliation
  - known-category plus novel-delta hybrid
  - agent-mode extraction recall at corpus scale
  - manual↔agent mode equivalence
  - accepted real Tier-2 output traceability
  - every model/effort tier-down
```

Nothing moves up without a cited replay. Nothing above is presented as proven
anywhere in the repo while it sits in the lower list — the Popperian
discipline, mechanically inconvenient and deliberately so.
