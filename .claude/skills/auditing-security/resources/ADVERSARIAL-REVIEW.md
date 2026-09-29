# auditing-security — Security Dissenter (Phase 1C) detail

SKILL.md Phase 1C names the gate, the hook, the override and the invocation. This file carries
the merge rules and the failed-run record.

## Independence

The dissenter receives the diff only — never `--context-file` with your Phase 1A/1B findings —
so it evaluates the code without anchoring on your conclusions.

## Merging dissenter findings into Phase 2

1. CRITICAL/HIGH findings go into the audit report as findings of your own (they may change the
   verdict and must appear in the Phase 2.5 tally).
2. MEDIUM/LOW findings go under a "Cross-Model Security Observations" section.
3. A dissenter finding that duplicates one of yours is marked "Confirmed by cross-model review".

## Failed or unavailable dissenter

Output file: `grimoires/loa/a2a/{sprint_id}/adversarial-audit.json`. The
`adversarial-review-gate.sh` hook checks that this file exists, not its contents, so on a
timeout, API error or exhausted budget write:

```json
{"findings": [], "metadata": {"status": "failed", "reason": "<what happened>", "rejected_summary": []}}
```

before proceeding, and set a `DEGRADED_SECURITY_REVIEW` marker in the audit report. Empty
findings from a run that completed are a normal pass, not a degraded review.

## Two voices and the rejected-payload contract (cycle-126 FR-2)

**Companion voice (D-2.1).** Every dissent plans a second chain from the *other* provider
family — the primary configured on the block decides: an OpenAI-family primary gets the
Anthropic chain (`opus` → `claude-headless`), an Anthropic-family primary gets the OpenAI chain
(`gpt-5.5` → `codex-headless`; KF-002 keeps `gpt-5.5-pro` out of the default). Credential *presence* (env → `.env.local` →
`.env`; the value is never read) decides only where the companion chain starts — with no key it
starts at the CLI hop. Both chains walk in parallel; the two completed envelopes are aggregated
(`verdict_quality.voices_planned: 2`, `voices_succeeded_ids` lists only completed voices). The
companion's findings arrive re-numbered `DISS-C-NNN` with a `voice` field; the primary's carry
`voice` too. `metadata.companion_voice` records `{planned, family, family_basis, chain, model,
status: succeeded|failed, failure_class: auth|model_unavailable|quota|timeout|malformed|null,
cost_cents, attempts}`; a companion whose chain fails is a dropped voice (degraded for an audit,
never blocking a review). Opt-out per block: `flatline_protocol.{code_review,security_audit}.companion_voice: false`
(the YAML boolean spellings in any case; a value that is none of them is reported and the voice stays on).

**Tolerant schema (D-2.2).** A finding missing only `failure_mode` is no longer dropped: the
first sentence of its `description` (≤ 200 chars) becomes `failure_mode` and the finding is
marked `failure_mode_derived: true` (a missing `id` is filled positionally, `id_derived: true`).
Severity, category and description are never touched. Payloads that still fail go to the
sidecar (`adversarial-rejected-<type>.jsonl`, `-companion` suffix for the second voice) **and**
to `metadata.rejected_summary[]` as `{severity, title, anchor, reason, description_head}`.

**The contract (D-2.3).** When `rejected_summary` is non-empty the feedback file MUST contain a
`## Rejected dissent payloads` section with one line per entry — `- <title> (<severity>, <anchor>)
— <reason>: triaged as <real defect → counted under the matching heading | not a defect → why>`.
`verdict-derive.sh` reads the sibling envelope (`adversarial-<gate>.json`, or `--envelope <path>`)
and marks the trailer INCONSISTENT (exit 1) when the section is missing. Reading a sidecar row:
`payload` is the model's finding as normalised, `reject_reason` the clause it failed, and
`repair_attempted` / `repair_succeeded` whether the bounded repair round-trip ran.

**Round-1 hardening (sprint-248 review, companion voice DISS-C-001 … C-011).** The companion
runs in its own sub-workdir with a log; a failed companion carries `last_error` (last diagnostic
line, redacted) beside `failure_class`. The envelope's `cost_usd` / tokens are BOTH voices; the
per-voice spend stays under `companion_voice.cost_cents` and `budget_cents` is a per-voice cap.
A hop the primary chain also holds (typically the other family's CLI as the primary's last
resort) stays in the companion chain and is listed under `companion_voice.shared_hops` — a keyless
primary usually answers earlier, and the second voice is worth having; a family with neither a
credential nor its CLI on PATH is `reason: no_route`. `companion_voice.independent` says whether
the two voices that answered belong to different families (the primary's succeeded id, not its
configured hop); when they do not, the companion's findings are kept (tagged) but its envelope contributes no
voice to verdict quality (`counted_as: duplicate_voice`; the aggregator counts distinct voices) so
one model is never reported as cross-family consensus. A primary chain that exhausts while the companion
completes is promoted (`status: reviewed`, `degraded: true`, `primary_voice: {status: failed}`) so
the completed voice is never buried. The companion's rejected rows are named on the envelope
(`companion_voice.rejected_sidecar`, the `-companion.jsonl` file) — triage them like the primary's:
`verdict-derive.sh` counts the rows of the sidecars the envelope names (`metadata.rejected_sidecars`
— the run removes its own two sidecars at start and lists the ones it produced — `LOA_ADVERSARIAL_RUN_TAG`
scopes the names, `adversarial-rejected-<gate>[-companion][-<tag>].jsonl`, so a chunk driver passes
its chunk key and nothing is renamed afterwards — a tag outside `[A-Za-z0-9_-]{1,64}` is replaced by a
short hash of its raw value, with a warning, so distinct tags never share a file; the envelope
`adversarial-<gate>.json` and the two sidecars are single-writer per (sprint, gate) — the tag scopes the sidecar
names only, never the envelope — so a second live run for the same sprint and gate is refused before it removes
anything (a dead run's lock is taken over); without `flock` the per-binary serialisation is off and said once; a stale file from a writer that did not run is never
this run's); without an envelope, or without that field, every `adversarial-rejected-<gate>*.jsonl` beside the
envelope's place counts (a pre-FR-2 envelope — a metadata without a `rejected_summary` key — counts none, with a
warning: historical sprints keep their verdicts); a non-empty sidecar a listing envelope does not name is never silent whatever its age: its
rows count toward the section and a warning names the file (newer than the envelope: the envelope may be stale — re-run;
older: an earlier run's rows that were never folded — triage them or remove the file; a chunk driver clears the
directory's rejected set at the start of a round); an envelope without
a metadata object is the legacy shape and counts nothing; rows whose repair
succeeded never count; a trailer-less file is held to the contract too; the same section with one
top-level bullet per payload clears it in every case. The second voice is reaped on INT/TERM/EXIT (one cleanup trap for the whole run;
`LOA_ADVERSARIAL_KEEP_WORKDIR=1` retains the `/tmp` workdir) and by a wait cap measured from its
start: each `*-headless` hop counts the CLI adapter's bound — connect 10 s + max(600 s, the catalog's
per-model `headless_timeout_seconds` — CLI hops only, capped at 3,600 s when the catalog loads; `claude-headless`
carries 900 s because a dissent on `claude -p` takes 6–10 minutes; `LOA_ADVERSARIAL_CLI_HOP_TIMEOUT` is the
fallback for an unsized hop) — each HTTP
hop `timeout_seconds`, plus 30 s (`LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS` pins it;
`failure_class: timeout`). The default OpenAI-family companion chain is `gpt-5.5` → `codex-headless`
(KF-002: `gpt-5.5-pro` returns empty content on review prompts); `companion_chain.openai` can still
name it. The companion reads its own copies of the prompt files. A failed companion whose id is one
of the primary's succeeded voices feeds no dropped-voice envelope (INV-5) — `counted_as:
duplicate_voice`. `companion_voice.answered_by` is the companion's own succeeded id (its inner chain
may differ from `model`); independence compares the two `answered_by` families. An
operator may set `flatline_protocol.<block>.companion_chain: {anthropic: [...], openai: [...]}`
to replace the default chains (used as given). A fold that fails keeps the primary envelope
(`companion_voice.status: fold_failed`). `failure_class` follows cheval's exit codes — 4
(`MISSING_API_KEY`) `auth`, 6 (`BUDGET_EXCEEDED`) `quota`, 3 / 124 `timeout`, 5
(`INVALID_RESPONSE`) or a `malformed_response` status `malformed`, anything else (1: API error, rate-limited, provider unavailable, token revoked)
`model_unavailable` — except that a diagnostic saying "timed out" (cheval reports its own CLI-hop
timeout as `PROVIDER_UNAVAILABLE`) is `timeout`. `last_error` is an allowlisted summary of the provider's own line — cheval's error tokens, "timed out
after Ns", HTTP / exit codes — read from the MODELINV ledger row cheval wrote for the call (the model-adapter shim discards cheval's
stderr; the row is matched by model, primitive and time window, so concurrent dissents on one host
could supply each other's line — another reason drivers run sequentially), else from the last non-banner line of the companion's
log; the redacted raw line is printed to stderr and stays in the `/tmp` workdir. `*-headless` hops — the dissent hops, the repair round-trips, and an HTTP alias whose catalog chain
falls through to a CLI hop — are serialised per CLI binary across the two walks (a per-user flock under `$XDG_RUNTIME_DIR`/`$TMPDIR`); a lock not acquired within the hop's bound fails that hop as a `timeout` (the chain walks on) rather
than running unserialised; queueing for the lock is not charged to the hop's cap; the lock directory
is per user (0700, ours, never a symlink — otherwise the hop runs unserialised). The queue is one hop
deep by design: a chunk driver runs dissents sequentially when any chain holds a `*-headless` hop. The companion's post-hop work (validation, repair round-trips) has its own budget, so
a model that answered is never reaped mid-processing. A primary that never answered leaves the
companion `counted_as: sole_voice` (`independent: null`), the primary skips a hop the live companion shares (`model_attempts` records
`skipped_shared_with_companion`), a model that merely resolves to a CLI hop waits for the lock only as long
as its own call timeout, and an attempt on either side that dropped a voice the other side answered with
is excluded from verdict quality (`primary_attempts_excluded` / `companion_attempts_excluded`); an aggregator failure
is named on the envelope (`verdict_quality_error`). `LOA_ADVERSARIAL_KEEP_WORKDIR=1` keeps files, never
a process. A derived finding id never collides
with one the model supplied. The repair round-trip walks `tiny` (with an Anthropic credential) → `claude-headless` (with the
binary on PATH) → the voice that answered, always last, one bounded attempt each — a hop that failed with
an explicit auth / quota code is retired for the run's remaining repairs, the answering voice never; a repair skips
a hop the companion is running at that moment (`repair_hops_skipped` names it) and waits for a CLI lock only its own timeout; the run's repairs share a wall-clock
budget (`LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS`, default 5 × timeout × 2 — spent, the rest are rejected unrepaired
and counted in `repair_budget_exhausted`); each `rejected_summary` entry carries its sidecar row's `index`; credential
presence resolves per alias with override precedence (env → `.env.local` → `.env`: the first place
that assigns a variable decides it, an empty assignment disables that alias; a provider with several
aliases — `GOOGLE_API_KEY` / `GEMINI_API_KEY` — is present when any alias resolves non-empty); the normaliser's
`id_derived` / `failure_mode_derived` markers are not part of the repair's byte-diff; a derived
`failure_mode` shorter than 20 characters (an enumerator, an abbreviation) gives way to the
description's 200-character head. Findings carry `voice` (the outer hop, matching `final_model`) and
`answered_by` (the model that actually produced them). A duplicate companion leaves `verdict_quality`
untouched (the aggregator counts distinct voices; its INV-5 forbids one id both succeeded and dropped)
— `companion_voice.counted_as` is the record. The companion's raw stderr lives only in the run's
`/tmp` workdir, removed on exit; the a2a directory receives the envelope and the sidecars. Both
cheval invocations append to `.run/cost-ledger.jsonl` and `.run/model-invoke.jsonl` under the
writers' flock (issue #689), so the hash chain stays linear. `last_error` also masks
bare provider-key shapes (`sk-…`, `xai-…`, `gsk_…`, `AIza…`) the shared redactor does not cover;
the reap takes the companion's whole process tree; `companion_voice.rejected_sidecar` is `null`
(and the file removed) when nothing was rejected.

**Repair loop (D-2.4).** The repair chain is `tiny` (when an Anthropic credential is present) →
`claude-headless` (when the binary is on PATH) → the voice that answered, always last — one bounded
attempt per hop, so a host with neither still repairs through its own primary; `LOA_ADVERSARIAL_REPAIR_MODEL`
pins the whole chain to one model (the round-1 hardening below has the retirement, lock and budget rules).
KF-004 evidence: the three real rejected payloads under `tests/fixtures/dissent-rejected/` now pass without a repair.
