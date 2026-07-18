# Decision 0004 — One immutable Aleph Core with host-only adapters

- **Status:** Accepted for implementation; at this decision's 2026-07-16
  baseline, Loa and Hermes adapters were planned, not implemented
- **Date:** 2026-07-16
- **Authority:** Eileen (product / architecture authority), explicit direction
  to establish the Core/adapter/bundle foundation
- **Resolves:** Q12 in
  [`12-risks-open-questions-do-not-build.md`](../architecture/12-risks-open-questions-do-not-build.md)
- **Relates to:** Decisions 0001–0003; the architecture tree; the manual-only
  sanction boundary
- **Narrowly supersedes:** mutable-`main` delivery language and any reading of
  the Fable 5 profile as universal Core runner doctrine

## Implementation-status note — 2026-07-17

The boundary and lifecycle decision below are unchanged. Since the decision
baseline, the Loa adapter has advanced to `implemented` on structural
implementation evidence only. It has no accepted replay, validation, sanction,
or authority permission to make agent mode a sanctioned execution path. The
Hermes adapter remains `planned`, and manual mode remains the only sanctioned
execution path. This note records implementation progress; it does not advance
either adapter beyond its evidence-gated lifecycle state.

## Context

The accepted method is already larger than a prompt pack. Its doctrine,
S0–S13 and P1–P3 contracts, artifacts, prompts, templates, projection
packages, authority gates, deterministic checks, fixtures, mutation batteries,
and goldens form one interdependent body. Splitting that body by host would
create multiple Alephs whose rules and evidence could drift.

The architecture also mixed two different concerns:

1. the harness-neutral method and evidence needed to execute, inspect, audit,
   validate, replay, and reconstruct Aleph; and
2. Fable-specific context, model, effort, cache, batch, worker, installation,
   and checkpoint mechanics.

Those mechanics are useful as one reference profile. They are not universal
requirements of the method. Q12 therefore cannot be resolved by choosing
plain documents *or* one harness-native package as the canonical Aleph.

Mutable installation from a branch such as `main` is also incompatible with
replay and durable resumption. A run cannot honestly pin its procedure if the
procedure may change underneath it.

## Decision

### 1. Aleph has one complete, harness-neutral Core

There is one Aleph Core. The source inventory and its exact classification are
recorded in [`core.manifest.json`](../../core.manifest.json).

Core owns, without host-specific forks:

- accepted doctrine and decisions;
- the S0–S13 distillation and P1–P3 projection contracts;
- run and artifact formats, ledgers, prompts, templates, and projection
  authoring packages;
- deterministic, adversarial, and human authority boundaries;
- the conformance checkers and their specifications;
- accepted fixtures, complete goldens, verifier/audit evidence, and mutation
  tests; and
- the material required to execute manually, inspect, audit, validate, replay,
  and reconstruct the method.

No fixture, golden, checker-evidence surface, or mutation battery may be
removed from Core merely to reduce a bundle's size.

### 2. Adapters contain host mechanics only

An adapter may own only the mechanics required to execute unchanged Core on
one host:

- a native entrypoint and installation;
- worker creation and fresh-context isolation;
- blind-bundle assembly from Core allowlists;
- structured-return validation;
- single-writer ledger serialization;
- deterministic checker invocation;
- host model/context/effort mapping;
- human-gate presentation;
- durable pause/resume; and
- immutable runtime capture.

An adapter may invoke and present Core. It may never alter, override,
summarize, restate, duplicate, fork, or weaken Core doctrine, contracts,
prompts, templates, checks, fixtures, goldens, or authority gates. An adapter
must not depend on another host's adapter paths or requirements.

Runtime, model, context, effort, cache, batch, and installation requirements
belong to adapter profiles. The Fable 5 design in
[`05-orchestration-on-fable-5.md`](../architecture/05-orchestration-on-fable-5.md)
is retained as a reference profile, not as a universal Core requirement.

The binding protocol and lifecycle rules are in
[`adapter-protocol/`](../../adapter-protocol/README.md).

### 3. Lifecycle claims are evidence-gated

Adapters use four monotonic states:

| State | Meaning |
|-------|---------|
| `planned` | Contract and reservation only. No runnable entrypoint or installation exists. |
| `implemented` | The adapter exists and passes its structural preflight. This is not validation. |
| `validated` | Accepted replay evidence demonstrates the claimed adapter capabilities. |
| `sanctioned` | The authority explicitly permits the validated adapter as an execution path. |

A lifecycle label may not run ahead of its entrypoint, installation,
capabilities, or evidence. Missing full-mode capabilities fail preflight. A
partial or degraded execution may not be called full Aleph.

At this decision's 2026-07-16 baseline, the Loa and Hermes manifests were both
`planned`. Neither native runner was implemented, validated, or sanctioned,
and manual mode was the only sanctioned execution path. The dated
implementation-status note above records later lifecycle progress without
changing that sanction boundary.

### 4. Distribution uses immutable host bundles

Two host bundles are defined:

```text
aleph-for-loa    = complete Aleph Core bytes + Loa adapter bytes
aleph-for-hermes = the same byte-identical Aleph Core bytes + Hermes adapter bytes
```

Each bundle receives a generated, bundle-local lock. The repository-wide
`core.manifest.json` is source packaging metadata and is not copied verbatim
as a host bundle inventory because it names both host adapters.

Every lock records at least:

- Core ID, version, and tree digest;
- selected adapter ID, version, lifecycle, and tree digest;
- complete bundle digest;
- checker digest;
- adapter-protocol version;
- run-format version; and
- source provenance sufficient to reconstruct the assembly.

Both locks must independently compute the same Core tree digest. A Loa bundle
must exclude Hermes adapter-owned bytes and any Loa-adapter, lock, profile,
installation, or entrypoint dependency on Hermes; the symmetric rule applies
to Hermes. Common Core may name both adapter families when defining the
protocol and release invariant. Core-digest equality and foreign-adapter
payload/dependency exclusion are release-blocking.

A Core change rebuilds both bundles. A host-only adapter change rebuilds only
that host's bundle. Release identity is determined by the Core, adapter, and
bundle digests, not by global repository `HEAD` alone.

Fetching mutable content from `main`, another branch, a moving tag, or a
served runtime endpoint is forbidden. Bundle assembly consumes exact frozen
source bytes and produces immutable locks.

### 5. Every new run pins its complete execution identity

Before S0 closes, every new run records:

- Core ID/version/digest;
- adapter ID/version/digest;
- bundle ID/digest;
- checker digest;
- adapter-protocol version;
- run-format version;
- exact host identity;
- exact model identity per role, or `human`;
- the immutable runtime-snapshot path and digest; and
- the original bundle lock or a content-addressed reference to it.

Agent and hybrid runs name a real host adapter. Manual runs use the reserved
`core-manual` execution binding declared by `core.manifest.json`. That binding
is not a third native adapter and claims no agent capability; it makes the
absence of host-runner mechanics explicit while still pinning the sanctioned
manual procedure and immutable Core bundle.

Aliases such as `latest` are forbidden. A model fallback, adapter update,
Core update, checker update, runtime update, or bundle replacement cannot be
applied in place. It blocks the current run or begins a successor run.

Existing runs and historical fixtures are not silently migrated. They retain
their original recorded format and evidence. A resumable run resumes with its
original bundle and runtime snapshot, even after newer bundles exist.

## Consequences

- Q12 is resolved: Core prompt packs remain canonical Core documents;
  harness-native entrypoints and profiles are adapters.
- The architecture can be implemented on more than one host without creating
  competing doctrine or checker forks.
- A green Core/adapter manifest check proves inventory, ownership, lifecycle,
  reference, and bundle-boundary structure. It does not prove agent mode,
  rendering quality, semantic judgment, or v1.
- Decision 0003 still authorizes implementation of the accepted build kits.
  Its description of document 05 as runner doctrine is narrowed to a Fable
  adapter reference profile.
- Decision 0001's product goal remains, but “sync `main`” is no longer an
  allowed delivery mechanism.
- At the decision baseline, manual mode remained sanctioned while the planned
  Loa and Hermes manifests reserved future integration surfaces without
  implementing either runner. The dated implementation-status note above
  records subsequent structural progress separately.
