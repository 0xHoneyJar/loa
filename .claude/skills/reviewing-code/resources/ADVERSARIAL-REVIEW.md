# Adversarial Cross-Model Review — Phase 2.5 mechanics

Referenced from `reviewing-code/SKILL.md` Phase 2.5. Runs when
`flatline_protocol.code_review.enabled: true` in `.loa.config.yaml`.

**Objective**: Invoke a cross-model dissenter to catch reviewer blind spots before the final decision.

**Steps**:
1. Prepare git diff of sprint changes: `git diff main...HEAD > /tmp/adversarial-diff.txt`
2. Invoke adversarial review:
   ```bash
   findings=$(.claude/scripts/adversarial-review.sh \
     --type review \
     --sprint-id "$sprint_id" \
     --diff-file /tmp/adversarial-diff.txt \
     --context-file "$reviewer_concerns_file" \
     --json)
   ```
3. Parse findings:
   - If `findings` array is empty or invocation failed: log and continue to Phase 3
   - If BLOCKING findings exist: incorporate into Phase 4 decision (forces CHANGES_REQUIRED)
   - If ADVISORY findings only: append as "Cross-Model Observations" section in feedback
4. Clean up temp files

**Failure must produce a record.** If `adversarial-review.sh` fails (timeout, API error, budget exceeded) and left NO `grimoires/loa/a2a/{sprint_id}/adversarial-review.json` of its own, write one with `{"findings": [], "metadata": {"status": "failed", "reason": "...", "rejected_summary": []}}` BEFORE proceeding (never overwrite an envelope the script did write — its `rejected_summary` carries the triage aids). Then list `adversarial-rejected-review*.jsonl` beside it: an aborted run may have left rows (the primary's, or a companion's `-companion.jsonl`); triage each row under `## Rejected dissent payloads` or remove the file — the sidecar-ownership rule under "Rejected rows" in the hardening list applies, and the verdict self-check will demand it. Do NOT silently skip — the gate hook has no way to distinguish "not attempted" from "attempted and failed", and the distinction matters for audit trail.

**Parameter Derivation**:
| Script Parameter | SKILL Derivation |
|-----------------|-----------------|
| `--sprint-id` | From SKILL invocation args, resolved via ledger |
| `--diff-file` | `git diff main...HEAD` written to temp file |
| `--context-file` | Reviewer's Phase 2 concern notes |
| `--model` | From `flatline_protocol.code_review.model` config |
| `--budget` | From `flatline_protocol.code_review.budget_cents` config |
| `--timeout` | From `flatline_protocol.code_review.timeout_seconds` config |

**Output**: Findings written to `grimoires/loa/a2a/{sprint_id}/adversarial-review.json`

**Failure mode**: If adversarial review is unavailable (timeout, API error, budget exceeded), proceed with single-model assessment and log warning. No DEGRADED marker for review (only audit).

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

**Round-1 hardening (sprint-248 review, sixteen live two-voice runs).** One list, by envelope field; both skills' copies of
this block are generated from the same text.

- **Two voices, one envelope.** The companion runs in its own sub-workdir with a log and its own copies of the prompt files.
  The envelope's `cost_usd` / tokens are BOTH voices; the per-voice spend stays under `companion_voice.cost_cents`, and
  `budget_cents` is a per-voice cap (a malformed cap is 0 cents — the run fails closed with `status: budget_exceeded`).
  Findings carry `voice` (the outer hop, matching `final_model`) and `answered_by` (the model that produced them);
  `companion_voice.answered_by` is the companion's own succeeded id. An operator may set
  `flatline_protocol.<block>.companion_chain: {anthropic: [...], openai: [...]}` to replace the default chains (used as
  given); the default OpenAI-family chain is `gpt-5.5` → `codex-headless` (KF-002: `gpt-5.5-pro` returns empty content on
  review prompts). A family with neither a credential nor its CLI on PATH is `reason: no_route`; a prompt copy that fails
  is `reason: prompt_copy_failed` (no fork). `LOA_ADVERSARIAL_KEEP_WORKDIR=1` keeps the `/tmp` workdir's files, never a
  process.
- **`companion_voice.independent` / `counted_as`.** Independence compares the two `answered_by` families (the primary's
  succeeded id, not its configured hop). Same family: the companion's findings are kept (tagged) but its envelope
  contributes no voice to verdict quality — `counted_as: duplicate_voice` (the aggregator counts distinct voices; its
  INV-5 forbids one id both succeeded and dropped, so a failed companion whose id is one of the primary's succeeded voices
  feeds no dropped-voice envelope either, and a MIXED attempt envelope keeps its own voice: a copy without the conflicting
  dropped entry is aggregated — `primary_attempts_rewritten` / `companion_attempts_rewritten`; an envelope with no
  succeeded voice that dropped the other side's voice is excluded — `primary_attempts_excluded` /
  `companion_attempts_excluded`). A primary that never answered leaves the companion `counted_as: sole_voice`
  (`independent: null`). A primary chain that exhausts while the companion completes is promoted (`status: reviewed`,
  `degraded: true`, `primary_voice: {status: failed}`) so the completed voice is never buried. An aggregator failure is
  named on the envelope (`verdict_quality_error`). A fold that fails keeps the primary envelope
  (`companion_voice.status: fold_failed`) and counts the companion as a dropped voice.
- **Shared hops (`companion_voice.shared_hops`, `primary_voice.status: ceded`).** A hop both chains hold (typically the
  other family's CLI as the primary's last resort) stays in the companion chain and is listed under `shared_hops`,
  compared by canonical name (a provider prefix or a catalog alias is the same hop). When the primary reaches a shared hop
  it waits for the companion to settle (bounded by the wait cap) and skips the hop only when the companion ANSWERED with
  it — `model_attempts` records `<hop>:skipped_shared_with_companion` and the envelope says `primary_voice: {status:
  ceded, hop}` with `degraded: false`; a companion that failed the hop, or never reached it, leaves it to the primary; a
  companion still ON the hop past the wait cap is reaped where the primary stands and the primary runs the hop; a
  companion that already answered and is finishing (its post phase) is left to the post budget. The binary is never run
  twice for the same prompt.
- **Rejected rows (`metadata.rejected_summary`, `metadata.rejected_sidecars`).** Every rejected payload lands in a sidecar
  row and in `rejected_summary` (each entry carries the row's `index` and the raw payload's title —
  `title_derived` when only the normaliser's positional id names it; an empty id or title is absent); the companion's
  rows are in its own `-companion.jsonl`, named on the envelope (`companion_voice.rejected_sidecar`, `null` and the file
  removed when nothing was rejected). `verdict-derive.sh` counts the rows of the sidecars the envelope names
  (`rejected_sidecars`): the run removes its own two sidecars at start and lists the ones it produced;
  `LOA_ADVERSARIAL_RUN_TAG` scopes the NAMES — `adversarial-rejected-<gate>[-companion][-<tag>].jsonl` — so a chunk driver
  passes its chunk key and nothing is renamed afterwards (a tag outside `[A-Za-z0-9_-]{1,64}` becomes a short hash of its
  raw value, said once, so distinct tags never share a file). A non-empty sidecar a listing envelope does not name is never
  silent whatever its age: its rows count toward the section and a warning names the file (newer than the envelope: the
  envelope may be stale — re-run; older: an earlier run's rows that were never folded — triage them or remove the file; a
  chunk driver clears the directory's rejected set at the start of a round). Without an envelope, or without that field,
  every `adversarial-rejected-<gate>*.jsonl` beside the envelope's place counts. A pre-FR-2 envelope (no metadata at all,
  or a metadata without a `rejected_summary` key and without any FR-2 marker) counts none of the rows as old as itself,
  with a warning — historical sprints keep their verdicts — but a sidecar NEWER than it counts. Rows whose repair succeeded
  never count; a trailer-less file is held to the contract too; the same section with one top-level bullet per payload
  clears it in every case.
- **Wait cap and reaping (`failure_class: timeout`).** The second voice is reaped on INT/TERM/EXIT (one cleanup trap for
  the whole run, the whole process tree — re-collected after the freeze and before KILL — TERM then KILL after
  `LOA_ADVERSARIAL_REAP_GRACE_SECONDS`, the companion's pid trusted only while its start token matches the one recorded at
  the fork) and by a wait cap measured from its start: each `*-headless` hop counts the CLI adapter's bound — connect +
  max(600 s, the catalog's per-model `headless_timeout_seconds`, CLI hops only, capped at 3,600 s when the catalog loads;
  `claude-headless` carries 900 s because a dissent on `claude -p` takes 6–10 minutes; `LOA_ADVERSARIAL_CLI_HOP_TIMEOUT` is
  the fallback for a hop no catalog lists; a listed hop without the key is bound by the formula, 610 s) — each HTTP hop `timeout_seconds`, plus 30 s (`LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS`
  pins it). The deadline follows the companion's phase (queue → hop → post) under a global ceiling; the post-hop work
  (validation, repair round-trips) has its own budget, so a model that answered is never reaped mid-processing. Every
  numeric knob (`timeout_seconds`, `budget_cents`, the context-escalation sizes, the operator seconds) is a whole number
  without a leading zero, or its default applies with a warning.
- **Locks.** `*-headless` hops — the dissent hops, the repair round-trips, and an HTTP alias whose catalog chain falls
  through to a CLI hop — are serialised per CLI binary across the two walks (a per-user flock under
  `$XDG_RUNTIME_DIR`/`$TMPDIR`, 0700, ours, never a symlink); a lock not acquired within the hop's bound fails that hop as
  a `timeout` (the chain walks on); a model that merely resolves to a CLI hop, and a repair, wait only their own call
  timeout; queueing for the lock is not charged to the hop's cap; without `flock` (or a lock directory that is not ours)
  the serialisation is off and said once per run. The queue is one hop deep by design: a chunk driver runs dissents
  sequentially when any chain holds a `*-headless` hop. The envelope `adversarial-<gate>.json` and the two sidecars are
  single-writer per (sprint, gate) — the tag scopes the sidecar names only, never the envelope — so a second live run for
  the same sprint and gate is refused before it removes anything (`status: refused_concurrent_run` under `--json`; a
  dead run's lock is taken over; the token is the acquiring pid and its start time).
- **`failure_class` and `last_error`.** The class follows cheval's exit codes — 4 (`MISSING_API_KEY`) `auth`; 6
  (`BUDGET_EXCEEDED` / `RATE_LIMITED`) or a diagnostic saying "rate limit" / "429" / "quota" `quota`; 3 / 124 `timeout`,
  and a diagnostic saying "timed out" (cheval reports its own CLI-hop timeout as `PROVIDER_UNAVAILABLE`) too; 5
  (`INVALID_RESPONSE`) or a `malformed_response` status `malformed`; anything else (1: API error, provider unavailable,
  token revoked) `model_unavailable`. `last_error` is an allowlisted summary of the provider's own line — cheval's error
  tokens, "timed out after Ns", HTTP / exit codes — read from the MODELINV ledger row cheval wrote for the call (the
  model-adapter shim discards cheval's stderr; the row is matched by model, primitive and the window of the companion's
  LAST hop, so a repair on the same model during its post phase is not its row; concurrent dissents on one host could still
  supply each other's line — another reason drivers run sequentially), else from the last non-banner line of the
  companion's log; it also masks bare provider-key shapes (`sk-…`, `xai-…`, `gsk_…`, `AIza…`) the shared redactor does not
  cover. The redacted raw line is printed to stderr and stays in the `/tmp` workdir, removed on exit; the a2a directory
  receives the envelope and the sidecars.
- **Repairs (`repair_hops_skipped`, `repair_budget_exhausted`).** The repair round-trip walks `tiny` (with an Anthropic
  credential) → `claude-headless` (with the binary on PATH) → the voice that answered, always last, one bounded attempt
  each (by canonical name: a prefixed answering voice is not appended twice); a hop that failed with an explicit auth /
  quota code is retired for the run's remaining repairs, the answering voice never; a repair skips a hop the companion is
  running at that moment (`repair_hops_skipped` names it, once) and waits for a CLI lock only its own timeout; the run's
  repairs share a wall-clock budget (`LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS`, default 5 × timeout × 2 or one full CLI
  repair plus a timeout if that is more; a hop whose estimate — twice its last observed duration, at least the timeout,
  at most its bound — exceeds what is left is not started and is named `<hop>:over_budget`; spent, the rest are rejected
  unrepaired and counted in `repair_budget_exhausted`, a payload none of whose hops started among them). A derived
  finding id never collides with one the model supplied; the normaliser's `id_derived` / `failure_mode_derived` markers are
  not part of the repair's byte-diff; a derived `failure_mode` shorter than 20 characters (an enumerator, an abbreviation)
  gives way to the description's 200-character head (counted in characters, never bytes).
- **Credentials and ledgers.** Presence resolves per alias with override precedence (env → `.env.local` → `.env`: the
  first place that assigns a variable decides it, an empty assignment disables that alias; a provider with several
  aliases — `GOOGLE_API_KEY` / `GEMINI_API_KEY` — is present when any alias resolves non-empty; the value is never
  expanded). Both cheval invocations append to `.run/cost-ledger.jsonl` and `.run/model-invoke.jsonl` under the writers'
  flock (issue #689), so the hash chain stays linear.

**Repair loop (D-2.4).** The repair chain is `tiny` (when an Anthropic credential is present) →
`claude-headless` (when the binary is on PATH) → the voice that answered, always last — one bounded
attempt per hop, so a host with neither still repairs through its own primary; `LOA_ADVERSARIAL_REPAIR_MODEL`
pins the whole chain to one model (the round-1 hardening above has the retirement, lock and budget rules).
KF-004 evidence: the three real rejected payloads under `tests/fixtures/dissent-rejected/` now pass without a repair.
