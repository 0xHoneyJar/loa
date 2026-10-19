# Mechanism read: pr-12 (review-03), bare vs full pipeline

Sources: the pointer file, the six runs' files and transcripts (full = `batches/priority-v2-p1b/`, t1 = `-t1-r2`), and the human review behind the labels (`grimoires/loa/a2a/sprint-248/engineer-feedback-round-1.md`). A replica of the grader's citation rule reproduces the published grade exactly.

## (a) Answer

Most of the 18-versus-6 gap comes from WHERE each arm puts its line numbers, not from what it found. I compared each credited citation's prose with the human review finding behind each label. On that semantic reading, bare found about 9 of 24 defect-trials and full about 17. **None of bare's 6 credits is the labelled defect.** Each is a different finding that happens to sit on an anchor line. Five of full's 18 credits are coincidences of the same kind. Meanwhile, bare's 9 real finds were all graded misses. Bare cited the line where the bug lives, while the manifest anchors the function header or a fix-region line. Examples: `verdict-derive.sh:137` vs anchor 131, `:502` vs 487, `:1914` vs 1898/1906. Bare also writes one single-line citation per finding, as review.md's format requires. Full writes three files whose findings carry `**File:**` lines with ranges and several `:N` continuations, and that widens its catch window.

The real gap that remains is d2, d6, d7, and d3/d4 in t1. In every full trial, the Fable reviewer had most of its catches in `reviewer-concerns.md` before the dissent ran: d1, d3, d4 in t1; d1, d3, d4, d6, d7 in t2; d1, d2, d3, d7 and the wait half of d4 in t3. The t1 review dissent failed outright. The t2 draft was written before the dissent returned. So the dissent's causal contribution is two defect-trials: t2 d2, which came through the audit gate's dissent, and the trap half of t3 d4. One more defect-trial came from the auditor alone: t3 d6.

Three confounds sit under the remaining gap:
- **Different model.** Fable 5.1 does the full arm's reading. Opus 5.5 is the bare model.
- **Different workspace.** Bare's `/workspace` holds only `pr/`, so the PR's bats could not load their libraries. Bare t1 said: "The bats suites couldn't run here because the repo's shared libraries aren't in `pr/`". Full had the framework and ran the bats plus stub-harness reproductions.
- **Two gates.** Full gets a second reader, the auditor.

Execution reproduced d3 and d4 in full, but bare found both by reading alone in two trials. Execution raised confidence. It did not drive discovery.

## (b) Per-defect table

Cell = grader credit / semantic catch · mechanism · `c`=in reviewer-concerns before dissent (full only) · `d`=dissent named it (voice/id; `late`=arrived after the draft).
Codes: **R** reviewer's own reading; **X** reproduced by execution; **Dr/Da** review/audit dissent; **A** auditor only; **L** credit by location coincidence (different finding); **M** semantic catch at a line outside ±3 (graded miss); **–** absent. `C*` = credit is L.

| | bare t1 | bare t2 | bare t3 | full t1 | full t2 | full t3 |
|---|---|---|---|---|---|---|
| d1 | –/S M`:137` | –/S M`:137` | –/S M`:137` | C*/S R, M`:137`; credit from LOW-007 `:134-136` · c✓ · Da DISS-001, DISS-C-002 (review dissent failed) | C/S R+X `:131-139` · c✓ · Dr DISS-002, DISS-C-006 late | C/S R `:131-140` · c✓ · Dr DISS-002 before feedback |
| d2 | –/– | C*/– L (`:2183` text is d3) | C*/– L (`:2182` text is d4; `:2183` voice tag) | C*/– L (`:2182` unbounded wait) | C/S **Da** (auditor LOW-008 from audit DISS-C-006) · c✗ | C/S R `:2183` · c✓ (item 4) · not in review dissent |
| d3 | –/– | –/S M`:2183` (credited as d2) | –/S M`:1914` | –/S R+X M`:1911-1916` · c✓ · dissent failed | C/S R+X `:1908-1916` · c✓ · Dr DISS-C-002 late | C/S R+X `:1908` · c✓ · Dr DISS-001 (codex) before feedback |
| d4 | –/– (region read, toy trap probe ev163, not reported) | C*/S: credit L (`:2140` prompt budget); real find M`:2001` | C*/S: credit L (`:2140`); real find `:2182` (credited as d2) | C/S R+X (orphan probe) · c✓ | C/S R+X (kill -TERM probe) · c✓ · Dr DISS-C-003 late | C/S **Dr** trap half (DISS-C-001, claude-headless); wait half c✓ |
| d5 | –/– | –/– | –/– | C*/– L (`:1837` family basis) | C*/– L (`:1835-1840` shared hop) | C*/– L (`:1837`; `:1847-1851` exit-code map) |
| d6 | –/partial (prose "line 2140", no path) | C*/– L (`:2140` prompt budget) | C*/– L (`:2140`) | C/S R `:2140` · c✗ · pre-arrival, dissent failed | C/S R · c✓ (item 8) · not named | C/S **A** (auditor LOW-006) · c✗ · not named |
| d7 | –/S M`:502` | –/partial M`:502` | –/– (`:499` precedence only) | –/S R M`:502` · c✗ · Da DISS-C-004 | C/S R+X `:487-507` · c✓ (item 4) · Dr DISS-C-004 late | –/S R M`:502` · c✓ (item 13) · Da DISS-C-007 |
| d8 | –/– | –/– | –/– | –/– | –/– (Dr DISS-C-009 hit `setup`, different defect) | –/– |
| **credit / semantic** | 0 / 3 (+1 partial) | 3 / 3 (+1 partial) | 3 / 3 | 5 / 5 | 7 / 6 | 6 / 6 |

Key events. In full t1 REVIEW, concerns were written at 515, the dissent launched at 516, the feedback went down at 714, and the dissent returned at 730 (envelope `status: failed`). In full t2 REVIEW, concerns are at 521, the draft at 604, and the dissent returned at 651. In full t3 REVIEW, concerns are at 408, the dissent launched at 440, it returned at 533, and feedback was written at 667.

## (c) Per-defect narrative

**d1, the heading-only `rejected_summary_check`.** Every one of the six runs found it. Bare wrote the same thing in all three trials at `verdict-derive.sh:137`, the `grep -qE` line. Bare t1 review.md line 11 reads: "enforced only through the presence of the `## Rejected dissent payloads` heading … (confirmed: a file with just the heading and no entries comes out CONSISTENT)". Bare t1 confirmed it by running the head script at event 163, with the result at event 164. Full t1 also wrote `:137`. Its only credit comes from a different finding, auditor LOW-007, which lists `verdict-derive.sh:134-136` as "reads only `rejected_summary`". Full t2 and t3 cite the ranges `:131-139` and `:131-140`. The ranges are the whole mechanism here.

**d2, `result=$(_fold_companion …)` unguarded under `set -e`.** Bare never wrote it in any trial, although it printed the region: t1 event 47 (`sed -n 1930,2241p`), t2 event 27, t3 event 13. To see it you need line 36's `set -euo pipefail`, which is outside the hunk. In full t3 it was concern item 4, written pre-dissent at event 408: "`_fold_companion` failing under `set -e` aborts `main` after the primary completed". The t3 auditor also confirmed it by probe. In full t2 it appears only in the auditor's LOW-008, which says it was prompted by the audit dissent: "The concrete triggers proposed by the dissent (DISS-C-006) were examined … the finding is the missing guard". That claude-headless finding was about `cost_cents` and `--argjson` failing inside the fold. Full t1's credit is the unbounded-wait finding at `:2182`.

**d3, an exhausted primary buries a completed companion.** Bare t2 found it by reading: "`metadata.status` stays `api_failure`/`malformed_response`". It cited `:2183`, the fold call site, so it was credited as d2. Bare t3 found it at `:1914`, which falls outside the ±3 window. Bare t1 did not have it. Full had it in its concerns in all three trials, and each trial reproduced it:
- **t1** ran custom scenario tests at event 403. Feedback line 57 reads: "Reproduced (`EXH-1`: every primary hop `unavailable`, companion `ok`): `metadata.status = api_failure`". The citation `:1911-1916` misses the window by two lines.
- **t2** ran the probes at event 428.
- **t3** ran the probe at event 466, and its feedback adds "Confirmed independently by the primary dissent vo[ice]".

**d4, a forked companion with no trap and an unbounded `wait`.** Bare t1 read main at event 47 and ran a toy probe at event 163 (`trap "echo bye" EXIT; (echo sub) & wait`), but never reported the defect. Bare t2 and t3 did report it, at `:2001` ("the EXIT trap only does `rm -rf` … never kills `$companion_pid`") and at `:2182`. Both bare credits for d4 come instead from a `:2140` finding about prompt budget. Full t1 and t2 had it in their concerns and reproduced the orphan: t1 at events 458 and 513, t2 at events 433 and 468, where t2 records "after `kill -TERM` … the companion's hop process stayed alive". Full t3's concerns had only "wait unbounded". The trap half came from the review dissent, added post-dissent through an Edit at event 694: "(companion dissent DISS-C-001, confirmed by reading `:2001` …)".

**d5, the CLI hop is always planned.** No run wrote it. Every full credit falls inside `_companion_chain` (1835) or the exit-code map (1851), but the prose is about something else: family basis, shared hops, or the cheval exit codes. All three full reviewers checked `which claude codex` (t1 event 460, t2 event 509, t3 event 406). None turned that into "plan the CLI hop only when its binary is on PATH". Anchor 1851 is a fix-region line in `_companion_failure_class`.

**d6, companion output sent to `>/dev/null 2>&1`.** In full t1 the reviewer found it alone. It was not in the concerns but was in the feedback at event 714, which came before the failed dissent: "`>/dev/null 2>&1` discards every companion log line". In full t2 it was concern item 8: "companion logs discarded (>/dev/null 2>&1)". In full t3 only the auditor had it, as LOW-006 "The companion's diagnostics are discarded", and no dissent voice raised it. Bare t1 mentions it in passing as "(line 2140)", with no path, so the grader cannot credit it.

**d7, the secret is materialised in `val`.** Bare t1 has it exactly: "`_adv_cred_present` does read the credential value: grep/sed extract it into `val`". The citation is `:502`, which is 15 lines from anchor 487. Full t1 and t3 have the same content at the same `:502`. Full t1 has it in feedback line 84; full t3 has it as concern item 13, then feedback line 110 and auditor LOW-001. Both are graded misses. Full t2 is the only credit, and only because its finding cites the range `:487-507`. The t2 auditor also reproduced the trace: "under `set -x` the trace contains the key's value". The two full "misses" on d7 are therefore pure mislocation.

## (d) The converse: d8 and d7

**d8 (low): the stub speaks review vocabulary to the audit gate.** Nobody found it. The stub's `ok` branch, at bats lines 79 and 85, emits `"severity":"ADVISORY"` whatever `$type` is. Under `--type audit`, CMP-7's finding is therefore rejected and repaired through the stubbed `invoke_dissenter`. To see this you need three things together: the audit wire schema's severity enum, which is not in `pr/` and which only full had, under `/workspace/.claude/schemas`; the knowledge that CMP-7 runs the audit type; and a check of `rejected_count` after CMP-7. All three full reviewers ran the companion suite and stopped at "7/7 pass". An example is full t1 auditor line 253. The t2 review dissent's DISS-C-009 hit the `setup` function, but its point was that the stub ignores the prompt-file arguments. Separately, the anchors 26 (the `eval "$(sed …)"` line) and 63 (`_vq`) are 16 or more lines from the real site at 79. A correct citation at `:79` would still have been graded a miss.

**d7 in full t1 and t3** was found and cited at `:502`, the `val=$(grep …)` line. No extra effort was needed to find it. The fix is in how the defect is anchored or how the citation is written.

## (e) Mislocated-catch candidates

Each of these is the correct defect, cited outside the ±3 window.

| run | defect | cited | anchor(s) | file:line of prose |
|---|---|---|---|---|
| bare t1, t2, t3 | d1 | `verdict-derive.sh:137` | 131 | review.md 11 / 8 / 14 |
| full t1 | d1 | `:137` | 131 | engineer-feedback 68; auditor MED-001 (line 87) |
| bare t1 | d7 | `:502` | 487 | review.md 9 |
| bare t2 | d7 (partial) | `:502` | 487 | review.md 14 |
| full t1 | d7 | `:502` | 487 | engineer-feedback 84; auditor 143 |
| full t3 | d7 | `:502` | 487 | engineer-feedback 110; auditor 228 |
| bare t2 | d3 | `:2183` | 1898/1906 | review.md 6 (credited to d2) |
| bare t3 | d3 | `:1914` | 1898/1906 | review.md 3 |
| full t1 | d3 | `:1911-1916` | 1898/1906 | engineer-feedback 55-56 |
| bare t2 | d4 | `:2001` | 2140 | review.md 11 |
| bare t3 | d4 | `:2182` | 2140 | review.md 9 (credited to d2) |
| bare t1 | d6 | "line 2140" (bare prose, no path) | 1868/2140 | review.md 10 |

The opposite case also occurs: credits whose prose is a different finding, which section (b) marks `C*`. There are 6 in bare (t2 d2, d4, d6; t3 d2, d4, d6) and 5 in full (t1 d1, d2, d5; t2 d5; t3 d5). One structural cause is that d4 and d6 share line 2140. Any finding cited at the fork line, such as the prompt-budget finding in bare t2 and t3, credits both.

## (f) Counts, and what could not be determined

| run | turns | tool calls | bats runs | exec probes |
|---|---|---|---|---|
| bare t1 / t2 / t3 | 23 / 23 / 25 | 22 / 22 / 24 | 0 / 0 / 0 | 2 / 0 / 0 |
| full t1 review + audit | 56 + 43 | 55 + 42 | 18 + 9 by pointer | 8 + 8 |
| full t2 review + audit | 57 + 46 | 56 + 45 | 18 + 10 by pointer | 8 + 3 |
| full t3 review + audit | 70 + 48 | 69 + 47 | 18 + 10 by pointer | 5 + 3 |

Hand-counted tool calls match the pointers in all nine transcripts. Bare t1's pointer `n_test_runs: 3` is wrong: its only bats command was `which bats`, and it ran 2 probes (events 163, 171), not 1. Full REVIEW transcripts hold 5 to 8 bats commands each, so the pointer's 18 likely counts per-test.

More turns alone do not explain the gap. Bare read the d2, d4 and d6 region in every trial and still missed d2 three times. The differences that matter are a different kind of action and a different reader:
- **Concerns pass.** Full wrote an explicit concerns list before the dissent, with 7, 8 and 15 items.
- **Reproductions.** Full ran harness reproductions, which bare's workspace could not support.
- **Second reader.** The auditor added d6 in t3 and d2 in t2.
- **Model.** Fable reads in full; Opus reads in bare. This is not separable from the rest here.

What I could not determine:
1. **Partial attributions.** Bare t2's d7 and bare t1's d6 are judgement calls. I counted each as half.
2. **The d5 call.** Full t1 auditor MED-002 ("default-on egress … consider defaulting to `companion_voice: false` on blocks whose chain is single-family") is adjacent to d5's upgrade consequence. I did not count it.
3. **Pointer gaps.** Bare t1's `diff_seen_event` is null, yet event 7 (`sed -n 1,500p head.diff`) returned 29,877 characters untruncated at event 8, which covers every new-function hunk. Bare t1's second diff read at event 10 was truncated to `<persisted-output>`, but events 11 and 13 re-read that span. Pointer region and diff events should be treated as lower bounds.
4. **Thinking blocks.** Assistant thinking was not inspected. Why bare t1 probed trap semantics at event 163 and then dropped d4 is not recoverable from the tool calls or text.
5. **Full t2's final feedback** was assembled from the draft by Bash/python edits (events 653, 704). Timing is taken from the draft at event 604.
