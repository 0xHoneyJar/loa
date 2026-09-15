# Runner capability contract

This contract states the host-neutral floor for executing Aleph agent mode.
It is subordinate to
[Decision 0004](../docs/decisions/0004-core-adapter-and-bundle-boundary.md)
and complements the manifest-level
[adapter capability contract](capability-contract.md). It does not sanction
agent mode, replace the manual path, or make a green deterministic check proof
of research quality.

The run directory and its pinned Core contracts are the center. A runner is a
replaceable host mechanism around those files. Manual mode is the existence
proof that the method does not depend on one model provider; agent mode adds
dispatch, isolation, validation, and durable automation without changing what
the artifacts must prove.

## Capability floor

A full agent-mode runner must provide all of the following:

| Floor | Required behavior |
|-------|-------------------|
| Immutable Core access | Load one verified bundle and execute its exact Core prompts, stage contracts, templates, and checker bytes without fetching mutable replacements. |
| Durable file I/O | Read and write the run directory as the authoritative record. Session memory, hidden state, or a provider thread is never the only copy of run state. |
| Bounded subtask dispatch | Invoke a worker over an explicit file allowlist and return its result to the single writer. Dispatch may be serial; parallel fan-out is an optimization. |
| Context isolation | Prevent inherited producer context where Core requires blindness, and create genuinely fresh-context refuters. Serial execution does not relax isolation. |
| Return-shape enforcement | Either constrain the worker at generation time or capture pure JSON text and run the pinned deterministic fallback below before any ledger write. |
| Single-writer persistence | Keep workers read-only with respect to canonical ledgers. Only the orchestrator serializes validated values into Core artifacts. |
| Deterministic checker invocation | Run the checker bytes pinned by the bundle, retain commands and reports, and fail closed on a nonzero result or digest mismatch. |
| Human-gate stop and resume | Stop at every Core authority gate, persist the question and response, and resume from verified files without impersonating the authority. |
| Exact execution identity | Pin the adapter, runtime, provider, model, context, budget, and fallback policy actually used. A host alias or silent fallback does not qualify. |

The thirteen manifest capabilities in
[`capability-contract.md`](capability-contract.md) are the machine-recorded,
full-mode expansion of this floor. Satisfying the table above does not permit
an adapter to omit corpus freezing, blind bundles, immutable installation,
runtime capture, or any other manifest capability.

## Structured-return fallback

Native strict tools or schema-constrained generation are optional. Validation
before persistence is not. A runner without native structured outputs must:

1. materialize the exact `Output contract` JSON exemplar from the pinned Core
   role prompt and verify its recorded digest;
2. instruct the worker to return only one JSON value, with no prose or code
   fence;
3. retain the raw returned bytes outside canonical ledgers;
4. invoke the validator from the same immutable bundle; and
5. on `PASS`, consume only `canonical_value` from the JSON report. On `FAIL`,
   retain the report and retry or block without appending.

Node 22 source bundles use:

```bash
node scripts/validate-worker-return.ts \
  --contract control/worker-bundles/CALL-ID/contracts/output.json \
  --return control/worker-returns/CALL-ID/raw.json \
  --json
```

The generated Node 20 runtime uses the byte-matched entrypoint:

```bash
node runtime-js/scripts/validate-worker-return.js \
  --contract control/worker-bundles/CALL-ID/contracts/output.json \
  --return control/worker-returns/CALL-ID/raw.json \
  --json
```

The validator is dependency-free, read-only, and import-safe. It rejects
malformed JSON, missing or additional fields, wrong primitive and collection
types, empty required strings, invalid Core literal placeholders, malformed
judgment rationales, and unsupported contract roots. Its report binds the raw
contract and return bytes by SHA-256. A pass proves only conformance to that
pinned return shape; semantic judgment still belongs to fresh-context
verification and human authority.

## Fable feature mapping

The Fable profile is one first reference runner, not the runner contract:

| Fable-specific feature | Portable classification |
|------------------------|-------------------------|
| `claude-fable-5` as the default model | Optional profile choice. Every runner must instead pin the exact realized model identity and prove its role-to-capability mapping. |
| 1M context and 128K output | Optional optimization. A smaller host shards at Core boundaries and records the shard plan. |
| Long-running turns and server-side compaction | Optional optimization. Durable file checkpoints and resumable stage state are required. |
| Parallel asynchronous subagents | Optional optimization. Serial worker dispatch is conforming when barriers, blindness, and fresh contexts are preserved. |
| Fresh-context verifier subagents | Host mechanism for a required isolation invariant; another host may use separate processes or sessions. |
| File-based memory | Required durable-record invariant; the Fable profile's exact memory-file layout is optional. |
| `low` through `max` effort controls | Optional host control. Every runner still records its exact role-to-capability and budget mapping. |
| Fable-specific instruction-following guidance | Profile evidence, not a platform requirement. Every runner receives the same pinned Core prompt bytes. |
| Hidden chain of thought | Provider trait. The Core requirement is a concise written rationale in judgment returns. |
| Schema-constrained outputs and strict tools | Optional generation-time enforcement. The deterministic fallback above is portable. |
| Native task budgets | Optional host control. Budget exhaustion must still block rather than silently truncate coverage. |
| Prompt caching | Optional cost optimization with no effect on Core bytes or outcomes. |
| Batch API and provider pricing | Optional scheduling and cost optimization; never a stage or correctness requirement. |
| Provider safety classifiers | Provider trait. Refusals must be retained and handled fail-closed under the Core failure policy. |

## Conformance and lifecycle

Artifact conformance is necessary, not sufficient. A new runner must first pass
adapter preflight, then produce accepted replay evidence before it may claim
`validated`, and finally receive explicit authority sanction before it becomes
a sanctioned execution path. Existing runs keep their original immutable
runner and bundle pins.

## Slice 7 semantic review (1.7)

For 1.7 semantic-unit-review, Core owns exact native/fallback schemas, subject/context construction, structural predicates and write plans. Host transport sends only the sealed L2S allowlist with the fixed Core task and existing fresh refuter infrastructure. Retain actual execution evidence and quarantine invalid returns; standalone binding not-checked cannot authorize admission. No provider abstraction or new autonomous orchestrator is introduced.
