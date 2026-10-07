# Bridgebuilder pass on PR #1274 (cycle-126): triage

- **Run.** `bridgebuilder-20261007T062030-4327`, 2026-10-07T06:20:30Z–06:40:27Z, on `8675d7c5`, `BRIDGEBUILDER_MODEL=codex-headless`, two-pass mode, three voices planned: openai/gpt-5.5-pro (45 s, 188,333 input tokens — the whole PR fit under the new budget), anthropic/claude-headless (693 s, 48,553 output tokens), google/gemini-3.1-pro-preview (**failed**: the agy CLI is not on this host — by the operator's instruction it is never run here). Verdict quality DEGRADED (2/3 voices). Consensus: 23 findings — 1 HIGH_CONSENSUS, 7 DISPUTED, 0 blocker.
- **Posted.** Three PR comments by the authenticated user (`[1/4]` claude-headless review, `[2/4]` gpt-5.5-pro review, `[4/4]` multi-model consensus); local copies in `~/.cache/loa/cycle-126-dissent/bb-1274/`, findings JSON in `bb-1274/findings.json`. BB's verdict: REQUEST_CHANGES, highest severity HIGH.
- **Budget.** One pass, per the standing directive. Fixes land as round r250-11; CI re-runs; no second pass.

## Rulings

| ID | Sev | Class | Where | Ruling | Action |
|---|---|---|---|---|---|
| F1 / BB-001 | HIGH / MEDIUM | HIGH_CONSENSUS / DISPUTED | `implement-gate.sh` `${rel,,}` | **REAL** — round r250-8 introduced a bash-4 expansion; on macOS bash 3.2 it is a bad substitution, `rel_forms` stays empty and the gate exits 0: fail-open on the fail-ask path. Both voices found it independently. | **FIX** (r250-11): portable `tr '[:upper:]' '[:lower:]'` helper; IG-23 pins the absence of bash-4 case expansions in the hook; a sweep of the hook for other bash-4 constructs. |
| BB-002 | MEDIUM | DISPUTED | `headless_cli.py` `private_workspace()` | DECLINED as a blocker; real visibility gap | Fail-closed on a non-empty stable workspace is the sprint-247/248 design. Bead **bd-hxpa** (with BB-007): `/loa` surfacing, one WARNING with the path, quarantine instead of refusal. |
| BB-003 | MEDIUM | DISPUTED | `cheval.py` `except RateLimitError` | **REAL** — the `RATE_LIMIT_UNVERIFIED` short-circuit applies to every 429 on an unverified hop, not only token-limit 429s as the PRD scopes it, so an ordinary RPM 429 on a large input ends the chain instead of walking. | **FIX** (r250-11): `RateLimitError.token_limited` set from the provider message's token/context-limit markers; only those short-circuit; test-first. |
| F2 | MEDIUM | DISPUTED | `verdict-derive.sh:289` `${listed_names[@]+"${listed_names[@]}"}` | **REFUTED** — the consensus writer itself notes this: the form is the standard `set -u`-safe idiom and the inner quotes preserve each element, spaces included. | None. |
| F3 | MEDIUM | DISPUTED | `ceiling.py:249` lock open with `O_NOFOLLOW` fallback 0 | **REAL (LOW on supported hosts)** — Linux and macOS both have `O_NOFOLLOW`; on a platform without it a planted symlink at the lock path is followed although the comment says it is refused. | **FIX** (r250-11): `fstat`/`lstat` identity, regular-file and owner checks after the open; test with `O_NOFOLLOW` removed. |
| BB-004 | LOW | LOW_VALUE | `check_implementation_active` ordering | DECLINED | A stale `sprint-plan-state.json` returning 1 before the other two files are read is the conservative outcome (ask); checking the others could only allow more. Pre-existing structure. |
| BB-005 | LOW | LOW_VALUE | `ceiling.py` `fit_max_tokens` dead branch | Bead | **bd-1sc9**. |
| BB-006 | LOW | LOW_VALUE | `implement-gate.bats` IG-14 `touch -d '2 hours ago'` | **REAL (test portability)** | **FIX** (r250-11): POSIX `touch -t`. |
| BB-007 | LOW | LOW_VALUE | `headless_cli.py` default ACL read as access ACL | Bead | **bd-hxpa**. |
| BB-008 | LOW | LOW_VALUE | `implement-gate.sh` builds ~200 strip sequences per invocation | **REAL (perf)** | **FIX** (r250-11): lazy init on first `strip_controls` use, as `lib-content.sh` does. |
| BB-009 | LOW | LOW_VALUE | raw control bytes as sentinels in `verdict-derive.sh` / bats | Bead | **bd-1sc9**. |
| BB-010 | LOW | LOW_VALUE | `loa-context-class.sh --show` falls back to `--line` (writes state, may block on stdin) | **REAL** | **FIX** (r250-11): `--show` is read-only and never reads stdin; test under `timeout`. |
| BB-011 | LOW | LOW_VALUE | `recommended-hooks.md` duplicate section numbers | **DOC** | **FIX** (r250-11): renumber. |
| BB-012 | LOW | LOW_VALUE | review-round ordinals as provenance in comments | DECLINED | Repo convention since cycle-114: the ordinals resolve through the a2a record branches (`record/cycle-NNN-a2a`), which this PR pushes for cycle-126. |
| F4 | LOW | LOW_VALUE | `headless_cli.py:154` Windows tempdir failure | Bead | **bd-1sc9** (Windows is not a supported host). |
| BB-013 | SPECULATION | — | context-limit markers catch other 4xx bodies | Noted | The marker list is the one the r250-11 token-limit flag reuses; an over-broad match only tightens (observes a lower bound). Watch under soak. |
| BB-014 | SPECULATION | — | observed-bound store may over-tighten | Noted | Over-tightening is the safe direction; the operator-only live probe resets it. |
| BB-015 | REFRAME | DISPUTED | G-3 partially unmet after the Task 4.8 revert; PRD KPI and ticked ACs silent | **DOC, partly refuted** — sprint.md's Sprint 3 ACs already carry the "superseded / waived" notes; the PRD KPI line did not. | PRD G-3 KPI line now carries the outcome note (`prd.md`). |
| BB-016 | REFRAME | DISPUTED | the core behavioural change sits in truncated files (`adversarial-review.sh` +2,515; the 5,974-line companion suite) | Noted | Those files were the subject of sprint-248's 39 two-voice dissent runs and its Fable review and audit (`record/cycle-126-a2a`, `a2a/sprint-248/`); BB's truncation is the expected behaviour of the budget clamp this PR adds. |
| BB-019, BB-020, F5 | PRAISE | — | `/tmp` eviction; atomic observed-bound store; tighten-only gate | Noted | — |

**Counts.** FIX 7 (F1/BB-001, BB-003, F3, BB-006, BB-008, BB-010, BB-011), DOC 1 (BB-015), REFUTED 1 (F2), DECLINED 3 (BB-002 as blocker, BB-004, BB-012), beads 4 (BB-002/007 → bd-hxpa; BB-005/009/F4 → bd-1sc9), noted 5.

## Round r250-11 outcome

Committed as `050dde35` (pushed). One Opus 5.5 implementer on `wt-r250-12`; the lead reviewed the patch, applied it, regenerated REPO-MAP and checksums, ran the suites and the CI gates locally. Each item was red first where a behavioural test applies.

| ID | Outcome |
|---|---|
| F1 / BB-001 | **Fixed.** `_ig_lower()` = `printf '%s' "$1" \| LC_ALL=C tr '[:upper:]' '[:lower:]'` at both sites; the hook was swept for other bash-4 constructs (none). IG-23 pins the absence of bash-4 case expansions (`${v,,}`, `${v^^}`, `${v,}`, `${v^}`) in the hook and, when a 3.x bash is on the host, runs the `LIB/x.js` case under it (none here; the lint pin alone). Live: `/bin/bash` 5.2 on `Src/probe3.ts` → ask. |
| BB-003 | **Fixed.** `RateLimitError(provider, retry_after, token_limited=False)`; `is_token_limit_message()` in `ceiling.py` (markers: `tokens per min`, `tokens per day`, `(tpm)`, `context_length_exceeded`, `max_tokens`, plus the context-limit set); the Anthropic and OpenAI adapters and `dispatch_provider_stream_error` set it from the 429 body; `cheval.py` short-circuits only when `_hop_unverified and token_limited`. Tests: `test_request_rate_429_while_unverified_walks_to_the_next_hop` (red first: it ended the chain), `test_token_limit_429_messages_are_told_apart_from_request_rate_ones`, `test_adapters_mark_a_token_limit_429`; the existing unverified-429 test now uses `token_limited=True`. |
| F3 | **Fixed.** `_refuse_unsafe_lock(lock_path, fd)` before the open (lstat: symlink / non-regular / other owner) and after it (fstat–lstat identity). Tests: a planted symlink with `O_NOFOLLOW` removed, a dangling symlink (target never created), a FIFO at the lock path; the normal path still records. |
| BB-006 | **Fixed.** `touch -t 202601010000` in IG-9 and IG-14. |
| BB-008 | **Fixed.** `_ig_strip_seqs_init` on first `strip_controls` use. |
| BB-010 | **Fixed.** `--show` with no usable record prints `Context: no record (… long is the default)` and exits 0 without reading stdin or writing `.run/`; CC-7 follows, CC-18 holds stdin on a FIFO under `timeout 5` and asserts exit within 2 s and no `.run/`. |
| BB-011 | **Fixed.** Sections 6 and 7 renumbered. |
| BB-015 | **Recorded.** PRD G-3 KPI outcome note. |

**Suites, real tree, serial (ok / not ok / skip):** implement-gate 23/0/0, compliance-hook 14/0/0, context-class 18/0/0, hook-wiring 10/0/0, repo-map-gen 6/0/0, loa-status-providers 4/1/0 in the batch (LSP-1, the recorded load flake; it passed when run right after the context-class suite alone). Adapters pytest `-k 'ceiling or rate or limit or policy or stream or types or anthropic or openai'`: 720 passed. `py_compile` clean; `bash -n` clean; `tools/check-no-raw-sha256sum.sh` exit 0; `grep -P` 0 hits; `regen-checksums --check` changed=0.

**Not re-run:** the directive allows one Bridgebuilder pass; CI re-runs on `050dde35` and the merge follows CI.
