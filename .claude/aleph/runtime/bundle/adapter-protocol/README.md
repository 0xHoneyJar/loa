# Aleph adapter protocol

> **Protocol version:** `1.0.0-provisional`
>
> **Run-format version:** `1.0.0-provisional`
> **Status:** accepted foundation; the Loa host adapter is implemented but not
> validated or sanctioned, while the other registered host remains planned

This directory defines the boundary between the one complete,
harness-neutral Aleph Core and a host adapter. It implements the boundary
accepted by
[Decision 0004](../docs/decisions/0004-core-adapter-and-bundle-boundary.md).
The source classification is recorded in
[`core.manifest.json`](../core.manifest.json), and immutable assembly is
defined by the [packaging contract](../packaging/README.md).

Read:

1. this overview;
2. the [capability contract](capability-contract.md);
3. the machine-readable [adapter manifest schema](adapter.schema.json); and
4. the selected manifest in the [adapter catalog](../adapters/README.md).

## The boundary

| Core owns | An adapter may own |
|-----------|--------------------|
| Accepted doctrine and decisions | A host-native entrypoint and installation |
| S0–S13 and P1–P3 contracts | Worker creation and fresh-context isolation |
| Run and artifact formats | Blind-bundle assembly from Core allowlists |
| Prompts, templates, and projections | Validation of structured worker returns |
| Authority gates and verification boundaries | Single-writer ledger mechanics |
| Checkers and checker specifications | Invocation of the pinned Core checker |
| Fixtures, mutation tests, and goldens | Host model, context, and effort mapping |
| Replay, audit, and reconstruction evidence | Human-gate presentation and durable pause/resume |
| The complete manual execution path | Immutable runtime capture and bundle installation |

An adapter consumes all Core bytes selected by the source manifest. It may
invoke and present those bytes, but it may never alter, override, summarize,
restate, duplicate, fork, transform, or weaken them. It may not replace a Core
prompt, template, checker, fixture, golden, stage contract, or authority gate
with a host-local version. Host runtime, model, context, effort, cache, batch,
and installation requirements belong only to an adapter profile.

An adapter must be independent of every other adapter. Its owned paths,
manifest references, installation, and runtime may not name or require a
foreign adapter.

## Full-mode preflight

The [capability contract](capability-contract.md) defines thirteen required
capabilities. A host invocation may call itself **full Aleph** only when:

- the installed bundle and every digest in its bundle lock verify;
- all thirteen capabilities are present at the lifecycle state claimed by the
  adapter manifest;
- the executable entrypoint, installation, profiles, and evidence support that
  claim;
- the corpus snapshot, model identities, and runtime snapshot have been frozen;
  and
- all required human gates remain blocking.

If any requirement is absent or fails at runtime, preflight fails closed. An
adapter may expose a development or partial mode, but it may not silently
downgrade and continue under a full-Aleph label.

## Lifecycle

Adapter and capability states are monotonic:

| State | Required meaning |
|-------|------------------|
| `planned` | Contract or reservation only. No runnable entrypoint or installation exists. |
| `implemented` | The complete adapter exists and passes structural preflight. This is not validation. |
| `validated` | Accepted replay evidence demonstrates the implemented capabilities. |
| `sanctioned` | Human authority explicitly permits the validated adapter as an execution path. |

Manifest claims may not run ahead of executable paths, installation paths,
capability states, replay evidence, or authority evidence. A planned manifest
therefore uses null executable and installation paths, empty evidence, planned
capability states, and `full_mode.claimed: false`.

Manual mode remains the only sanctioned execution path. The Loa manifest now
records structural implementation only; it carries no accepted replay,
validation, or sanction evidence. The other host manifest remains a planned
reservation.

## Run identity and resumption

Before S0 closes, every new run must pin:

- Core ID, version, and tree digest;
- adapter ID, version, and tree digest;
- bundle ID and digest;
- checker digest;
- adapter-protocol and run-format versions;
- exact host and model identity for every role, or `human`;
- an immutable runtime-snapshot path and digest; and
- the original bundle lock or a content-addressed reference to it.

Aliases such as `latest` are invalid. Core, adapter, checker, bundle, model, or
runtime changes apply only to successor runs. A paused run resumes from its
original verified bundle and runtime snapshot.
