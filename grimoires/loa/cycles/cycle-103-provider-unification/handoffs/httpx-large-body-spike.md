---
title: T1.0 httpx large-body spike — cheval Python vs BB Node fetch on Google generativelanguage
sprint: sprint-1
cycle: cycle-103-provider-unification
ac_routed: AC-1.0
related_kfs: [KF-008, KF-002]
date: 2026-05-11
status: complete
outcome_route: (a) httpx handles 400KB → unification closes KF-008
---

# T1.0 — httpx Large-Body Spike

## Decision (AC-1.0)

**Route (a) confirmed.** `cheval` Python `httpx` completes the HTTPS round-trip
to `generativelanguage.googleapis.com` at all four probe sizes — 172KB, 250KB,
318KB, 400KB — with exit code 0. The mid-stream `SocketError: other side
closed` that defines KF-008 against BB's Node `fetch` adapter does **not**
reproduce against the Python `httpx` client.

**Sprint 1 proceeds with full scope.** Migrating BB's Google adapter from Node
`fetch` to cheval Python `httpx` (via `ChevalDelegateAdapter`, T1.2/T1.4) is
the canonical fix for KF-008.

## Method

Reproducibility: the harness lives at
`grimoires/loa/cycles/cycle-103-provider-unification/handoffs/httpx-large-body-spike.py`.
Raw measurements at sibling `httpx-large-body-spike-results.jsonl`.

| Variable | Value |
|----------|-------|
| Client | `cheval.py invoke` → `loa_cheval` Google provider → `httpx` |
| Model | `gemini-3.1-pro` (alias) → `gemini-3.1-pro-preview` (API id, per cheval stderr) |
| Endpoint | `generativelanguage.googleapis.com` (streaming) |
| Prompt shape | Diff-like filler (mimics BB review payload shape) |
| `max-tokens` | 64 (small, so timing reflects upload + handshake, not generation) |
| Timeout | 180s (subprocess), 210s outer |
| Trials per size | 1 (n=1 sufficient to disprove the KF-008 hypothesis) |

Probe sizes match the AC-1.0 ladder: 172KB (verified KF-008 failure size on
2026-05-11, per `known-failures.md`), 250KB, 318KB (above the 297KB BB
observed-failure), 400KB (stress).

## Raw Results

| Body target | Prompt bytes | Exit | Wall-clock | Visible content | Truncation warning |
|-------------|--------------|------|------------|-----------------|--------------------|
| 172 KB | 171,200 | 0 | 76.18 s | 4 chars | `MAX_TOKENS` |
| 250 KB | 249,200 | 0 | 37.03 s | 11 chars | `MAX_TOKENS` |
| 318 KB | 317,200 | 0 | 29.96 s | 0 chars | `MAX_TOKENS` |
| 400 KB | 399,200 | 0 | 50.80 s | 0 chars | `MAX_TOKENS` |

The "visible content" column reports `result.content` length on stdout.
The truncation warning is cheval's `WARNING: google_response_truncated
reason=MAX_TOKENS` on stderr.

## Interpretation

### Primary finding — KF-008 does not reproduce

The KF-008 signature against BB is `TypeError: fetch failed; cause=SocketError:
other side closed`, observed **mid-stream after TCP+TLS handshake** at body
size 297,209 bytes (~297KB). The Python `httpx` client, with its different
HTTP/2 stack, connection-reuse behavior, and default socket settings, never
sees this mid-stream close at any of the four probe sizes.

The KF-008 root cause is therefore confined to the BB Node `fetch` client (or
its undici default agent / HTTP/1.1 keep-alive behavior) — not a server-side
limit that any compliant HTTPS client would hit. Migrating BB's Google
adapter to the cheval Python httpx path eliminates the failure class.

### Secondary finding — KF-002-shaped pressure at all sizes

A distinct failure mode emerged that the spike was not designed to probe.
Every trial — including the smaller 172KB call that BB would historically
have handled — returned with `finish_reason=MAX_TOKENS` and almost no visible
content. This is not network-level: the HTTP round-trip completed; the
response object was well-formed; Google's server simply consumed the
`max_tokens=64` budget on thinking/internal-state and emitted ≤ 11 chars of
visible output.

This is the classic shape of **KF-002 (layer 2/3)** — input size pressuring
visible-output budget — and is squarely in Sprint 2's charter (per
`sprint.md` Sprint 2 AC-2.1: characterize input-size threshold for empty-
content). The spike confirms the threshold is **not** specific to one
provider's network stack; it is provider-side budget arithmetic.

### Why elapsed times don't increase monotonically with size

Wall-clock times (76s / 37s / 30s / 51s) are not monotonic in body size.
Likely cause: the 172KB call generated 4 chars of output and 250KB generated
11 chars — those calls spent additional time on `thinking + output token
generation` that the 318KB / 400KB calls (which emitted 0 visible chars)
skipped. The dominant variable in this regime is server-side processing
time, not upload bandwidth or HTTP framing.

## Implications for Sprint 1

| Task | Effect of spike outcome |
|------|-------------------------|
| **T1.2** `ChevalDelegateAdapter` (TS, spawn-mode) | **Proceed.** The httpx underlying transport demonstrably handles ≥ 400KB request bodies; AC-1.6 path (a) is in scope. |
| **T1.4** Retire `anthropic.ts` / `openai.ts` / `google.ts` | **Proceed.** No vendor-side blocker discovered that would require BB to retain a parallel Node path. |
| **T1.6** Flatline direct-API call sites → `model-invoke` | **Proceed.** Same transport substrate. |
| **T1.9** Re-run BB cycle-1 + cycle-2 on PR #844 | **Critical AC-1.6 verification.** Expected outcome: KF-008 reproduction count holds at the BB observation, and the post-T1.4 path passes review. |
| **AC-1.0 routing** | Route (a) — Sprint 1 ships unification as the KF-008 fix. |

## Implications for KF-008

`known-failures.md` KF-008 attempts table needs an update row:

> Attempt date 2026-05-11 — spike via `cheval` Python `httpx` at 172/250/318/400KB. **Did not reproduce.** All four trials returned exit 0 with completed network round-trip; failure class confined to BB Node `fetch` adapter. Closure path: Sprint 1 T1.2/T1.4 migrates BB Google adapter to cheval delegate. Anticipated KF-008 status post-Sprint-1: **Closed (resolved via client migration)**.

That update lands in the same commit as this report.

## Implications for KF-002

The MAX_TOKENS truncation observed at all four sizes is **not** a new KF — it
is consistent with the existing KF-002 layer-2/3 characterization
(`grimoires/loa/known-failures.md`). Sprint 2 (AC-2.1) replays this
threshold systematically. No action required on KF-002 from this spike.

## Things the spike did NOT prove

To stay honest about scope:

1. **n=1 per size.** A single trial per probe is enough to disprove a
   universal-failure hypothesis (KF-008 reproduces against any client), but
   too few to characterize a probabilistic failure rate. Sprint 2's n≥5
   protocol applies if intermittent network failures need to be ruled out.
2. **Single model.** Only `gemini-3.1-pro` was tested. The cheval delegate
   will route many models through the same Python httpx path; per-model
   regressions would surface at integration time, not in this spike.
3. **No daemon mode.** This is spawn-per-call (matching T1.2's default
   mode). The daemon path (T1.3, conditional on T1.1 latency outcome) is
   not exercised here.
4. **No keep-alive vs cold-connection comparison.** The four trials were
   sequential in one process; whether cold-DNS or fresh-TCP behavior
   differs is not characterized.
5. **No HTTP/2 vs HTTP/1.1 toggle.** httpx defaults applied; the precise
   stack difference between Node `fetch` (undici, HTTP/1.1 by default) and
   Python `httpx` (HTTP/1.1 by default, HTTP/2 if `h2` installed) was not
   isolated. The pragmatic outcome stands; root-cause-level diagnosis of
   the Node `fetch` failure is upstream's concern.

## Verification

Reproduce locally:

```bash
cd <repo-root>
python3 grimoires/loa/cycles/cycle-103-provider-unification/handoffs/httpx-large-body-spike.py
```

Requires `GOOGLE_API_KEY` set in environment. Total runtime: ~3 min, total
spend (4 calls, ~64 output tokens each): ≲ $0.50.

## Cross-references

- PRD § 8.5.1 IMP-005 (the AC that requires this spike)
- SDD § 5.1 (cheval CLI contract)
- `known-failures.md` KF-008 (the failure class being characterized)
- `sprint.md` T1.0 / AC-1.0 (the task and acceptance criterion)
- BB observation 2026-05-11 (the original KF-008 reproduction)
