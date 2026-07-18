---
name: loa-aleph
description: Drive Aleph through the verified Loa host adapter and its durable run record.
---

# Loa Aleph host orchestration

Invoke the adapter through:

```text
node .claude/aleph/bin/loa-aleph.mjs --json <start|status|resume|validate> ...
```

For a new run, provide the exact host-capability receipt at
`grimoires/loa/aleph/host-capabilities.json`, or pass its unmanaged path with
`--capabilities`. Never create that receipt from a guessed model alias. A
missing exact host, model, effort, isolation, or runtime capability is a
preflight failure without fallback.

After `start`, present the persisted S0 request to the human. Collect only the
scope, exclusions, per-source sensitivity rulings, human authority identity,
and freeze decision named by that request. Submit the resulting JSON through
the adapter's `--authority-response <path> RUN-id` control surface. The adapter,
not a worker, performs the transaction-journaled freeze and canonical writes;
`resume` rolls any prepared S0 after-image forward before continuing.

For later Core-required stops, persist the exact request and open it through:

```text
node .claude/aleph/bin/loa-aleph.mjs --json --open-gate <request.json> RUN-id
```

The adapter accepts only the implemented Core combinations: S8
external-referent resolution, S13 Precis acceptance, P1 projection commission,
P3 projection acceptance, and budget-exhaustion or suspected-contamination at
the current Core stage. Present the resulting persisted gate artifact to the
human, then submit the exact file-driven decision with
`--authority-response <response.json> RUN-id`. Do not synthesize, reinterpret,
or fill missing authority fields. Gate records bind directly to the retained
bundle's canonical stage section, and prepared gate transactions are recovered
before resume. Fixture-simulated responses remain tainted and cannot confer
Precis or projection acceptance.

For `resume`, use the run-local verified bundle reported by the adapter. Load
the canonical Core orchestrator prompt, agent runbook, stage contract, role
prompt, templates, and output contract directly from that bundle. Do not make
host-local copies or summaries. Ask the runtime to build each blind worker
bundle, then prepare the native handoff:

```text
node <run-local-bundle>/runtime-js/adapters/loa/src/worker-dispatch.js prepare \
  --worker-bundle <sealed-worker-bundle> \
  --return-root <run>/control/worker-returns/<CALL-id> \
  --capabilities <run>/control/runtime/host-capabilities.json \
  --json
```

`prepare` verifies both the sealed worker bundle and the retained exact host
capability receipt. It writes a canonical, read-only `invocation.json`. Pass
that JSON object, unchanged, to Loa's native fresh-context/subagent primitive.
Do not translate it into a broader prompt, add inherited conversation, expose
another readable path, add a writable path, or substitute a model alias. The
primitive must support every requested mechanic, including the exact resolved
model identity and effort. If that primitive or any mechanic is unavailable,
stop with a preflight failure. There is no in-conversation worker, fake worker,
default model, retry downgrade, or other fallback.

The worker itself has `readable_paths=[<sealed-worker-bundle>]` and
`writable_paths=[]`. After the native call returns, this installed skill, in
the orchestrator context, persists the host result at the two exact paths in
`invocation.json`:

- `native-dispatch.json` is canonical JSON with exactly `format`,
  `invocation_digest`, `worker_bundle_digest`,
  `host_capability_receipt_digest`, and `receipt`. Its `format` is
  `aleph-loa-native-worker-dispatch/v1`. The three digests are copied exactly
  from the invocation, and `receipt` contains exactly the native context ID,
  producer-context ID, fresh/no-inherited-context flags, read-only filesystem
  attestation, exact resolved model identity, and simulation marker required by
  `aleph-loa-worker-dispatch/v1`.
- `native-return.json` is the worker's structured JSON value, serialized as
  canonical JSON. The skill writes it; the worker never receives a file handle.

Write both result files atomically and remove all write bits before `accept`.
They are immutable handoff evidence, not scratch files.

Then accept the handoff:

```text
node <run-local-bundle>/runtime-js/adapters/loa/src/worker-dispatch.js accept \
  --worker-bundle <sealed-worker-bundle> \
  --return-root <run>/control/worker-returns/<CALL-id> \
  --json
```

`accept` re-verifies the bundle, immutable invocation, retained host receipt,
and exact native dispatch binding before it quarantines and validates the raw
return against the bundled Core contract. It exposes no ledger-writing API.
Only a separately authenticated return with a passing validation report may be
given to the orchestrator's single ledger writer. A refuter always receives a
new context that does not inherit or reuse the producer context.

Stop whenever the adapter reports `BLOCKED`. Human authority responses are
never model-generated. Any capability receipt, native dispatch receipt,
authority response, or worker marked `fixture-simulated` must keep that marker
through prepare, native handoff, accept, validation, and any later structural
test record. It remains structural implementation evidence only and may not be
described as a real replay, validation, acceptance, sanction, or full live
execution.

`validate` invokes the checker from the run's retained original bundle. Report
its exact exit status and artifact paths without upgrading a deterministic pass
into semantic judgment or authority acceptance.
