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
`--capabilities`. For a live run, create that receipt only with the entrypoint
inside the installed verified bundle:

```text
node .claude/aleph/runtime/bundle/runtime-js/adapters/loa/src/host-attestation.js attest \
  --profile .claude/aleph/runtime/bundle/adapters/loa/profiles/loa-default.json \
  --output grimoires/loa/aleph/host-capabilities.json \
  --model claude-opus-4-8 \
  --provider amazon-bedrock \
  --json
```

The command requires `AWS_BEARER_TOKEN_BEDROCK`, `AWS_REGION`, and
`CLAUDE_CODE_USE_BEDROCK`, attests the exact Claude Code and bubblewrap
binaries, and makes schema-constrained model probes. Never hand-author the
receipt, invent a model SHA, substitute an alias, or overwrite an existing
receipt. A missing exact host, model, effort, isolation, or runtime capability
is a preflight failure without fallback.

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

The adapter accepts only the implemented Core combinations: S4 internal-
ambiguity procedural decisions, S8 external-referent resolution, S13 Precis
acceptance, P1 projection commission, P3 projection acceptance, and budget-
exhaustion or suspected-contamination at the current Core stage. Present the
resulting persisted gate artifact to the human, then submit the exact file-
driven decision with
`--authority-response <response.json> RUN-id`. Do not synthesize, reinterpret,
or fill missing authority fields. Gate records bind directly to the retained
bundle's canonical stage section, and prepared gate transactions are recovered
before resume. Fixture-simulated responses remain tainted and cannot confer
Precis or projection acceptance.

For `resume`, use the run-local verified bundle reported by the adapter. Load
the canonical Core orchestrator prompt, agent runbook, stage contract, role
prompt, templates, and output contract directly from that bundle. Do not make
host-local copies or summaries.

For run-format 1.5 S4, obey the `slice5` next-work object returned by
`resume`. When it names the four bounded roles, dispatch the pinned
`ambiguity-producer`, fresh `ambiguity-reviewer`,
`material-impact-producer`, and fresh `material-impact-reviewer` through the
same prepare/dispatch/accept path below, in the order required by the first
unmet DoD. Give accepted structured returns only to the orchestrator's
canonical writer. Repeated `resume` applies a persisted human response to
T5.3 exactly once, creates a legal Q+1 when required, and otherwise advances
C2/C3 under the same retained bundle. A successor-run halt is terminal for
the current run, not resumable current-run work.

For S5 or later work with retained procedural restrictions, provide the
worker-bundle assembler the exact typed downstream operation tuples. The
assembler derives the restriction set from exact retained Core
request/response/T5.3 bindings, refuses a prohibited tuple before dispatch,
and seals permitted neighboring operations plus the read-only restriction
set into the worker request. Never infer these tuples from task prose, and
never translate a restriction into an S5 disposition or S6 evidence role.

For each exact next-work item, retain one canonical assembly input at
`<run>/control/worker-assembly-inputs/<CALL-id>.json`:

```json
{"format":"aleph-loa-worker-assembly-input/v1","call_id":"CALL-…","run_id":"RUN-…","stage":"S4","role":"ambiguity-producer","kind":"producer","allowlist":[],"withheld":[],"task_line":"One exact Core-authorized task sentence.","producer_context_id":null,"downstream_operations":[]}
```

Populate `allowlist`, `withheld`, `task_line`, reviewer
`producer_context_id`, and any S5-or-later `downstream_operations` only from
the exact resumed Core work item and retained run state. Then invoke the
manifest-declared internal `loa-aleph-worker-handoff` tool:

```text
node <run-local-bundle>/runtime-js/adapters/loa/src/worker-dispatch.js assemble \
  --bundle <run-local-bundle> \
  --run <run> \
  --input <run>/control/worker-assembly-inputs/<CALL-id>.json \
  --json
```

`assemble` verifies the retained bundle and run pins, selects the exact pinned
model for the named role, delegates sealed-bundle construction to the
canonical assembler, derives retained restrictions, validates typed downstream
operations, and writes only
`<run>/control/worker-bundles/<CALL-id>`. Reviewer roles require `kind =
refuter` and a nonempty producer context. Use the returned
`worker_bundle_root` as `<sealed-worker-bundle>` below.

Write every stage output only to the exact Core path named by its stage
contract and template. In particular, S1 finalizes `corpus/manifest.md` and
writes `ledgers/extraction-criteria.md`; do not create a substitute
`ledgers/source-inventory.md`. Strip template instruction comments before
filling fields, and never retain an HTML comment inside a canonical field
value. Before closing a stage, invoke the pinned checker and resolve every
failure for an artifact or invariant due at that stage. Missing artifacts from
future stages may remain incomplete; current-stage failures may not be
deferred.

```text
node <run-local-bundle>/runtime-js/adapters/loa/src/worker-dispatch.js prepare \
  --worker-bundle <sealed-worker-bundle> \
  --return-root <run>/control/worker-returns/<CALL-id> \
  --capabilities <run>/control/runtime/host-capabilities.json \
  --json
```

`prepare` verifies both the sealed worker bundle and the retained exact host
capability receipt. It writes a canonical, read-only `invocation.json`. Do not
translate it into a broader prompt, add inherited conversation, expose another
readable path, add a writable path, or substitute a model alias.

Dispatch that prepared invocation through the binary-attested host binding:

```text
node <run-local-bundle>/runtime-js/adapters/loa/src/worker-dispatch.js dispatch \
  --worker-bundle <sealed-worker-bundle> \
  --return-root <run>/control/worker-returns/<CALL-id> \
  --json
```

`dispatch` starts the pinned Claude Code executable as a fresh,
nonpersistent process inside the pinned bubblewrap policy. The worker receives
only the sealed bundle mounted read-only at `/worker`; it has no durable
writable path and no inherited conversation. The command rejects any binary
drift, model mismatch, fallback, refusal, permission denial, malformed or
truncated stream, unapproved tool, or incomplete `StructuredOutput` return. It
writes immutable `claude-stream.jsonl`, `native-return.json`, and
`native-dispatch.json` evidence in quarantine. Do not create or modify those
files manually. If dispatch fails, stop; there is no in-conversation worker,
fake worker, default model, retry downgrade, or other fallback.

Then accept the handoff:

```text
node <run-local-bundle>/runtime-js/adapters/loa/src/worker-dispatch.js accept \
  --worker-bundle <sealed-worker-bundle> \
  --return-root <run>/control/worker-returns/<CALL-id> \
  --json
```

`accept` re-verifies the bundle, immutable invocation, retained host receipt,
raw event stream, structured return, and exact dispatch binding before it
validates the return against the bundled Core contract. It exposes no
ledger-writing API. Only a separately authenticated return with a passing
validation report may be given to the orchestrator's single ledger writer. A
refuter always receives a new context that does not inherit or reuse the
producer context.

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
