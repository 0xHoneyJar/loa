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
`adversarial-review-gate.sh` hook checks that this file parses and carries `metadata.type` and `metadata.model` — a `--record-fallback` record names no model, so it never opens the gate: re-run the dissent (or the operator sets `LOA_ADVERSARIAL_REVIEW_ENFORCE=false`, noted in sprint notes). When `adversarial-audit.json` is ABSENT after the script exits — an aborted run leaves none: at start the script moves the previous round's envelope and sidecars aside as `.prev` and never restores them — record the failure with the script itself (a call this skill's allowlist holds; never a hand-written file):

```bash
.claude/scripts/adversarial-review.sh --type audit --sprint-id <sprint_id> --record-fallback failed --reason "<what happened>"
```

before proceeding. Branch on the `status` line the script prints on stdout, never on exit 2 alone (exit 2 with no status line is a usage error, or a standing envelope that stderr names):

- **An envelope stands after a run that took the run lock** — it is the script's own: triage it; never overwrite it.
- **`failed`** (no envelope: the run aborted) — the call above writes `{"findings": [], "metadata": {"status": "failed", "reason": "<what happened>", "rejected_summary": [], "rejected_sidecars": []}}` under the per-(sprint, gate) run lock. It never writes over an envelope that stands (exit 2), unless the run died before its lock with no status on stdout: what stands is then the previous round's — add `--since <the time on the run's "run started" stderr line>` and an envelope older than that goes aside as `.prev`.
- **`refused_concurrent_run`** (another run — a detached or backgrounded one — holds the run lock; nothing recorded, nothing moved; a `--record-fallback` made meanwhile is refused the same way) — wait until the holding run has exited: an envelope that then stands with a `metadata.timestamp` after your refusal is that run's: triage it as this round's dissent only when its `metadata.scope` is what you asked for (the same `diff_range` and `diff_oids` as your refusal's own `metadata.scope` — the commits, not just the ref names — and `run_tag` null: a chunk driver's tagged run reviewed one chunk); otherwise, or when none stands, run again.
- **`workdir_unavailable`, `nothing_to_review`, `budget_exceeded`, `diff_range_failed`** (the range's `git diff` failed — e.g. a base ref a shallow clone lacks; written BEFORE the run lock; non-zero exit, stdout only; nothing moved aside, so any envelope at the path is the PREVIOUS run's and never this round's evidence) — record it: `--record-fallback <the status> --reason "<its stdout line>" --since <the run started time>` (it never displaces an envelope written after that) moves that envelope and its `adversarial-rejected-audit*.jsonl` sidecars aside as `<name>.prev` (as a run does at start) before it writes, so `verdict-derive.sh` judges this round's record, not the last round's.

A record names what it moved aside (`metadata.displaced`: status, timestamp, findings, rejected); `verdict-derive.sh` warns when that held findings. `verdict-derive.sh` never scans `.prev` files (they are the previous round's evidence, already triaged in that round's feedback) and reports `.prev` files with NO envelope as a `dissent_aborted` violation, which a fallback record clears; `rejected_sidecars: []` does not silence a canonical `adversarial-rejected-audit*.jsonl` beside it — that is this run's own partial work, counted whether listed or not: triage its rows under `## Rejected dissent payloads`.

Then set a `DEGRADED_SECURITY_REVIEW` marker in the audit report. Empty
findings from a run that completed are a normal pass, not a degraded review.

A bare `planned: false` (the block opted out, `companion_voice: false`) is the operator's choice, not a degradation.
Otherwise a completed run is still a degraded audit when its second voice is missing: `companion_voice.status` `failed`
or `fold_failed`, `counted_as` `duplicate_voice` or `sole_voice`, or `planned: false` WITH a `reason` (a companion that
never started: `no_workdir`, `no_route`, `prompt_copy_failed`) — set the `DEGRADED_SECURITY_REVIEW` marker and name the
reason. On a host with no route to the other family at all (`no_route`: no key and no CLI for it) that marker is set on
every audit; `companion_voice: false` on the block is the operator's way to say one voice is the host's shape.

## Two voices and the rejected-payload contract (cycle-126 FR-2)

**Companion voice (D-2.1).** Every dissent plans a second chain from the *other* provider
family — the primary configured on the block decides: any primary outside the Anthropic family (OpenAI,
Google, xAI, unknown) gets the Anthropic chain (`opus` → `claude-headless`), an Anthropic-family primary gets the OpenAI chain
(`gpt-5.5` → `codex-headless`; KF-002 keeps `gpt-5.5-pro` out of the default). Credential *presence* (env → `.env.local` →
`.env`; the value is never read) decides only where the companion chain starts — with no key it
starts at the CLI hop. Both chains walk in parallel; the two completed envelopes are aggregated
(`verdict_quality.voices_succeeded_ids` lists only completed voices). `companion_voice.status` is `succeeded`,
`failed` or `fold_failed`; `verdict_quality.voices_planned` counts the aggregated envelopes — 2 whenever the companion ran,
completed or not (a failed one is listed in `voices_dropped`) — except a failed companion whose id is one of the primary's
succeeded voices: INV-5 lets it feed no envelope, so `voices_planned` stays 1 and `companion_voice` is its only record; a `duplicate_voice` companion contributes none, and a
dropped entry naming the model the companion answered with is removed (INV-5). `companion_voice.counted_as`
(`independent_voice`, `duplicate_voice`, `sole_voice` — the primary never answered) names the outcome, and `planned: false` with a `reason` (`no_workdir`, `no_route`,
`prompt_copy_failed`) is a companion that never started; a bare `planned: false` is the opt-out. The
companion's findings arrive re-numbered `DISS-C-NNN` with a `voice` field; the primary's carry
`voice` too. `metadata.companion_voice` records `{planned, family, family_basis, chain, model,
status: succeeded|failed|fold_failed, failure_class: auth|model_unavailable|quota|timeout|lock_wait|malformed|null,
cost_cents, attempts}`; a companion whose chain fails is a dropped voice (degraded for an audit,
never blocking a review). Opt-out per block: `flatline_protocol.{code_review,security_audit}.companion_voice: false`
(the YAML boolean spellings in any case; a value that is none of them is reported and the voice stays on).

**Tolerant schema (D-2.2).** A finding missing only `failure_mode` is no longer dropped: the
first sentence of its `description` (≤ 200 chars) becomes `failure_mode` and the finding is
marked `failure_mode_derived: true` (a missing `id` is filled positionally, `id_derived: true`).
Severity, category and description are never touched. Payloads that still fail go to the
sidecar (`adversarial-rejected-<type>.jsonl`, `-companion` suffix for the second voice) **and**
to `metadata.rejected_summary[]` as `{index, severity, title, title_derived, anchor, reason, description_head}`.

**The contract (D-2.3).** When `rejected_summary` is non-empty the feedback file MUST contain a
`## Rejected dissent payloads` section with one line per entry — `- <title> (<severity>, <anchor>)
— <reason>: triaged as <real defect → counted under the matching heading | not a defect → why>`.
`verdict-derive.sh` reads the sibling envelope (`adversarial-<gate>.json`, or `--envelope <path>`)
and marks the trailer INCONSISTENT (exit 1) when the section is missing. Reading a sidecar row:
`payload` is the model's finding as normalised, `reject_reason` the clause it failed, and
`repair_attempted` / `repair_succeeded` whether the bounded repair round-trip ran.

**Round-1 hardening (sprint-248 review, sixteen live two-voice runs).** One list, by envelope field; both skills' copies of
this block are kept byte-identical (CMP-138 fails on any drift).

- **Two voices, one envelope.** The companion runs in its own sub-workdir with a log and its own copies of the prompt files.
  The envelope's `cost_usd` / tokens are BOTH voices; the per-voice spend stays under `companion_voice.cost_cents`, and
  `budget_cents` is a per-voice cap (a malformed cap is 0 cents — the run fails closed with `status: budget_exceeded`).
  Findings carry `voice` (the outer hop, matching `final_model`) and `answered_by` (the model that produced them);
  `companion_voice.answered_by` is the companion's own succeeded id. An operator may set
  `flatline_protocol.<block>.companion_chain: {anthropic: [...], openai: [...]}` to replace the default chains of D-2.1
  (used as given; only those two keys are read — keyed by the companion's family). A family with neither a credential nor its CLI on PATH is `reason: no_route`; a prompt copy that fails
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
  (`rejected_sidecars`): at start the run moves the previous run's envelope and its two sidecars aside (`.prev`) and it
  lists the sidecars it produced; a run that writes its envelope drops the `.prev` files; a run that aborts leaves NO envelope
  at the path and the `.prev` files beside it (the previous round's evidence, already triaged in that round's feedback);
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
  the fallback for a hop no catalog lists; a listed hop without the key is bound by the formula, 610 s) — each HTTP hop `timeout_seconds`, plus its lock wait and the CLI bound when its catalog chain falls through to a CLI
  hop (it takes that binary's lock before its request, as a `queue` phase; cheval walks the chain inside one call), plus
  30 s (`LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS` pins it). The deadline follows the companion's phase (queue → hop → post) under a global ceiling; the post-hop work
  (validation, repair round-trips) has its own budget, so a model that answered is never reaped mid-processing; the
  primary's wait on a shared hop applies the same model (a companion in `post` on another hop frees the hop at once; on
  the shared hop the primary waits for the settled record). The previous run's envelope and sidecars are moved aside at
  start (`.prev`) and never restored — see "Rejected rows". Every
  numeric knob (`timeout_seconds`, the context-escalation sizes, the operator seconds) is a whole number
  without a leading zero, or its default applies with a warning — except `budget_cents` / `--budget`, which fail closed
  (0 cents, `status: budget_exceeded`, exit 4).
- **Locks.** `*-headless` hops — the dissent hops, the repair round-trips, and an HTTP alias whose catalog chain falls
  through to a CLI hop — are serialised per CLI binary across the two walks (a per-user flock under
  `$XDG_RUNTIME_DIR`/`$TMPDIR`, 0700, ours, never a symlink); a lock not acquired within the hop's bound fails that hop as
  `lock_wait` — no request was sent (the chain walks on); a model that merely resolves to a CLI hop, and a repair, wait only their own call
  timeout; queueing for the lock is not charged to the hop's cap; without `flock` (or a lock directory that is not ours)
  the serialisation is off and said once per run. The queue is one hop deep by design: a chunk driver runs dissents
  sequentially when any chain holds a `*-headless` hop. The envelope `adversarial-<gate>.json` and the two sidecars are
  single-writer per (sprint, gate) — the tag scopes the sidecar names only, never the envelope — so a second live run for
  the same sprint and gate is refused before it removes anything (`status: refused_concurrent_run` under `--json`; a
  dead run's lock is taken over; the token is the acquiring pid and its start time; a lock directory with no token yet is a
  holder in flight for `LOA_ADVERSARIAL_RUN_LOCK_GRACE_SECONDS`, default 5). A diff that prepares to no content is refused
  before the run lock (`status: nothing_to_review` under `--json`, exit 1, no call made); a top-priority file not even one
  hunk of which fits the budget is sent as its PARTIAL marker alone (`0 of N hunks shown`).
- **`failure_class` and `last_error`.** The class follows cheval's exit codes — 4 (`MISSING_API_KEY`) `auth`; 6
  (`BUDGET_EXCEEDED` / `RATE_LIMITED`) or a diagnostic saying "rate limit" / "429" / "quota" `quota`; 3 / 124 `timeout`,
  and a diagnostic saying "timed out" (cheval reports its own CLI-hop timeout as `PROVIDER_UNAVAILABLE`) too; 5
  (`INVALID_RESPONSE`) or a `malformed_response` status `malformed`; anything else (1: API error, provider unavailable,
  token revoked) `model_unavailable`; a hop whose CLI lock was never acquired is `lock_wait` (no request was sent).
  `last_error` is an allowlisted summary of the provider's own line — cheval's error
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
  repairs share a wall-clock budget (`LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS`, default 5 × timeout × 2 or twice the heaviest hop's charge
  (below) plus a timeout if that is more; a hop whose estimate — twice its last observed duration, at least the timeout,
  at most its bound — exceeds what is left is not started and is named `<hop>:over_budget`; spent, the rest are rejected
  unrepaired and counted in `repair_budget_exhausted`, a payload none of whose hops started for want of budget among them;
  one none of whose hops started for any other reason — every hop retired or being run by the companion — is counted in
  `repair_skipped_no_hop`). `LOA_ADVERSARIAL_REPAIR_MODEL` is filtered by the retired hops too. A hop is charged by what it
  can reach, in the repair budget and the companion's post budget alike: a `*-headless` hop its CLI bound, an HTTP alias
  whose chain falls through to a CLI its lock wait, its timeout and that CLI's bound. A derived
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
