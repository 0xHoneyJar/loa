# Adapter capability contract

This contract defines the host mechanics required for a full Aleph adapter.
It is subordinate to
[Decision 0004](../docs/decisions/0004-core-adapter-and-bundle-boundary.md)
and is represented in each adapter's
[machine-readable manifest](adapter.schema.json). It does not add to, restate,
or replace Core doctrine.

## Manifest representation

Every capability is a required property under `capabilities`:

```json
{
  "durable_file_io": {
    "state": "planned",
    "evidence": []
  }
}
```

`state` is one of `planned`, `implemented`, `validated`, or `sanctioned`.
`evidence` contains exact repository-relative evidence paths and is empty for
a planned capability. Capability states are monotonic and may not exceed the
adapter's own lifecycle claim.

## The thirteen full-mode capabilities

| Manifest key | Required behavior |
|--------------|-------------------|
| `durable_file_io` | Read and write the run directory as the durable record. Ledger and control writes survive process or session loss and do not depend on model-session memory. |
| `frozen_corpus_snapshots` | Freeze the S0 corpus bytes, inventory, locators, and digests before downstream work. Later mutable source changes cannot enter the current run. |
| `fresh_context_workers` | Create context-isolated workers and genuinely fresh-context refuters where Core requires independent judgment. Reusing the producer's hidden or conversational context does not qualify. |
| `blind_bundles` | Assemble each worker bundle from the explicit Core allowlist, withhold forbidden artifacts, and record enough bundle identity to reproduce what the worker saw. Telling a worker to ignore supplied material is not blinding. |
| `validated_structured_returns` | Validate every worker return against the applicable Core return contract before any ledger write. Host-native constrained output is optional; validation before persistence is not. |
| `single_writer_ledgers` | Keep one authoritative ledger writer. Workers return data and never race, append to, or rewrite shared Core ledgers directly. |
| `deterministic_checker_invocation` | Invoke the checker bytes pinned by the bundle, preserve the command, inputs, exit status, and report, and fail closed on checker failure or digest mismatch. |
| `human_authority_gates` | Stop at every Core authority gate, present the required record to the designated human authority, and persist the authority response. An adapter or model may not impersonate acceptance. |
| `durable_pause_resume` | Persist stage and gate state so a run can resume after process, session, or host interruption. Resume verifies and reuses the original bundle and runtime snapshot before writing. |
| `exact_model_identity` | Record the exact provider, model identifier, resolved version or immutable equivalent, and role assignment actually used. Aliases and unrecorded fallback models are forbidden. |
| `immutable_runtime_snapshot` | Capture a content-addressed snapshot of the host runtime, toolchain, adapter configuration, and execution-relevant dependencies sufficient to reproduce or audit the run. |
| `host_model_effort_mapping` | Map Core roles and judgment requirements to exact host model, context, effort, budget, cache, and batch mechanics in an adapter profile. These mappings are host mechanics, never universal Core requirements. |
| `immutable_bundle_installation` | Install and verify one exact Core-plus-adapter bundle from its lock without fetching mutable content from a branch, moving tag, service, or runtime endpoint. |

## Full-mode rule

`full_mode.claimed: true` means all thirteen manifest capabilities are present
and preflight-clean for that adapter version. If any capability is absent,
planned, unavailable, misconfigured, or fails its runtime check, full-mode
preflight stops. The host may report a partial development surface, but it may
not call that execution full Aleph.

Full-mode completeness and lifecycle sanction are separate:

- `implemented` establishes that the complete mechanics exist and pass
  structural preflight;
- `validated` additionally requires accepted replay evidence for those
  mechanics; and
- `sanctioned` additionally requires an explicit authority decision.

A structurally complete but unsanctioned adapter remains unavailable as a
sanctioned execution path.

## Profiles

Runtime, model, context, effort, budget, cache, batch, and installation details
belong to adapter profiles. A profile may strengthen host mechanics to meet
Core requirements; it may not alter the Core stage graph, prompts, artifacts,
checks, authority gates, or definitions of done.

Each executed run records the selected profile and its immutable runtime
snapshot. Changing a profile, resolved model, runtime, or fallback policy
starts a successor run. It does not mutate or transparently resume an existing
run.

## Evidence requirements

Evidence must be inspectable and content-addressed. At minimum:

- implementation evidence identifies the executable and installation that
  pass structural preflight;
- validation evidence identifies accepted replay inputs, outputs, checker
  records, independent audit, and capability coverage; and
- sanction evidence identifies the explicit human authority decision.

Self-assertion, a green deterministic checker alone, a planned path, or a
documented profile does not advance lifecycle state.
