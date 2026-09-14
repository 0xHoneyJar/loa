# Flatline and Bridgebuilder result handling

Flatline counts only schema-qualified review content toward its configured
voice denominator. DEGRADED results remain nonzero exits. Partial findings
are advisory evidence and do not establish consensus or implementation
readiness.

## Flatline artifacts and partial results

- Canonical consensus: `<output-dir>/<phase>-<run-id>-final_consensus.json`.
  Each invocation reads and invalidates only its own canonical artifact.
- The legacy `<phase>-final_consensus.json` name is an atomic latest symlink,
  published after the owning run consumes its verdict. It describes the
  latest consumed result, which may be an older run; use the run-scoped path
  for evidence ownership.
- `execution.run_id` in stdout identifies the run. `--run-id` accepts 1–128
  letters, digits, underscores and hyphens, starting with a letter or digit.
  Concurrent invocations must use distinct IDs; omission generates one.
- `LOA_FLATLINE_OUTPUT_DIR_OVERRIDE` retains its isolated-output behavior.
- `--keep-temp` or `KEEP_FLATLINE_TEMP=1` retains intermediate responses and
  prints the directory on stderr for offline investigation.
- When consensus is skipped or scoring is degraded, `raw_reviews` contains
  every qualified voice, including a qualified tertiary voice and findings
  omitted by scorers. `verdict_quality` preserves the configured denominator
  and degradation.
- The beads loop preserves a nonzero invocation's JSON and stops with its
  failure code. It does not apply suggestions or declare stabilization from
  that result. Diagnostics go to stderr.
- Rejected verdict schemas report `VERDICT_SCHEMA_REJECTED`, the field path
  (at most 128 ASCII characters), and validator (at most 32). Both the direct
  Python CLI and its standard-library fallback exclude rejected values and raw
  validator messages. Schema rejection still exits 2 with no stdout result.

Project `hounfour.providers.*.models` declarations and chained aliases are
merged with system declarations for validation and dispatch-name resolution.
A new bare model ID must identify one provider; use a provider-qualified name
when ambiguous. These checks read declarations without credential resolution
or model calls. Provider capabilities and invocation success remain downstream
checks.

Scoring counts available, validated scorer votes separately from the review
quorum. Each scorer file must contain exactly one transport envelope. Inside
its content, fenced or prefixed score JSON can follow a metadata object;
JSON-encoded fenced strings are also accepted. Invalid, missing, or duplicate-ID
responses are marked unavailable. Their scores remain `null`; real zero scores
remain part of the average.

Before Phase 2 dispatch, finding IDs gain a review-source and position prefix
(for example `gpt:0:IMP-001`). Both cross-scorers receive that same ID. Returned
IDs must match the dispatched input; finding descriptions, `review_source`
and `original_id` come from that input. Two authors' local `IMP-001` IDs never
combine into one finding. Each scorer supplies at most one vote per finding,
and two independent scores above the high threshold establish HIGH_CONSENSUS.
Each response is also checked for complete coverage of its dispatched IDs.
An incomplete response retains its validated scores and marks scoring
degraded; missing votes are never filled with zero. Findings without any
scores remain available in the qualified `raw_reviews`.
The standalone scoring engine expects callers to supply globally unique IDs.
`scorers_available` and `consensus_summary.models_available` expose participation.
A lone scorer cannot establish agreement or `would_integrate`; those findings
remain visible in `medium_value`. Rejected scorer responses remain visible
through `degraded` and `degraded_models`.

Incomplete or rejected scoring also sets canonical
`verdict_quality.scoring_degraded`, prevents APPROVED, and makes main exit 6.
The configured review denominator, qualified voice IDs and reported chain
health remain unchanged. The run-owned consensus artifact and stdout carry
the same verdict. Qualified reviews with substantive no-findings evidence and
valid empty score arrays remain a successful empty result; a malformed scorer
or empty scores for nonempty findings cannot use that exception.

Cursor's `--output-format json` wraps the CLI response in a JSON transport
envelope. The adapter returns the envelope's `result` as model text and does not
pass or enforce an output schema. Its models therefore retain `[chat, code]`
capabilities: requests requiring native `structured_json` are rejected by the
capability gate. Prompted JSON still goes through Flatline's content validation.

## Bridge handoff

Bridgebuilder's summary includes PR/head-bound `verdicts`. A successful
transport or `COMMENTED` GitHub review is not approval. Consumers must inspect
the explicit verdict, highest severity and `mergeBlocked` field.

Post-PR triage extraction failures emit DEGRADED convergence even when the
findings array is empty. Post-PR orchestration retains a
`.run/post-pr-degraded-summary.json` marker and surfaces it at READY_FOR_HITL.
This adds visibility at the human checkpoint.

An undriven bridge with no current-run findings, recorded sprints or commits
since JACK_IN halts with exit 3. `--allow-empty` explicitly permits that case;
the existing `--no-silent-noop-detect` opt-out remains available.
