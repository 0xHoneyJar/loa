# sprint-250 review dissent run 3: triage

- **Run.** The round r250-3 fix delta `4b347efc..64c2eb09`, 2026-10-06T09:56:41Z–10:08:01Z, in two chunks: s3-shell (19,618 B) and e3-eval (8,845 B). Coverage check: every changed file is in a chunk or in GENERATED.
- **Voices.** Both chunks were two-voice [codex-headless, claude-headless], with the companion on `claude-bedrock` (KF-040).
- **Envelope.** `adversarial-review-run3-merged.json`, which is also the current `adversarial-review.json`.
- **Findings.** 5 in total: 1 BLOCKING and 4 ADVISORY, all from claude-headless.
- **Rejected payloads.** None. `rejected_summary` is 0 on both chunks, and the five sidecars in the directory are all 0 bytes.
- **Budget.** This is review dissent run 3 of 3, the last allowed for this sprint. Round r250-4's fixes are therefore covered by the Fable review, the audit dissent and the audit, not by a fourth review run.
- **Size cap.** The dissenter's size cap skipped full-file context for `model-adapter.sh` (28,677 B) and `reviewer.test.ts` (70,988 B). The diff hunks were still reviewed.

| # | Sev | Where | Verdict | Action (round r250-4) |
|---|---|---|---|---|
| 1 | BLOCKING | `recall-vs-defects.sh:113` URL token | **REAL**, verified by the lead | Without MULTILINE, Python `$` also matches before a string-final `\n`. So `\S*$` over a window that ends `…url\n` returns the previous line's URL token, and a citation at the start of the next line is skipped. Fix: extract the token linearly (split on whitespace). Red: a new RG case for a line-leading citation after a URL line. |
| 2 | ADV | same line | **REAL (perf)** | `\S*$` backtracks quadratically on long runs of non-whitespace. The same linear extraction fixes it. |
| 3 | ADV | grader header and `grader_version` | **REAL (record)** | Round r250-3 changed which citations are credited but kept "1.1.1". Bump to 1.1.2. |
| 4 | ADV | `check-permissions.sh` header :26 | **DOC** | The header's statement of the universal rule omits `Bash(:*)`. Align it with `rule_key`. |
| 5 | ADV | `model-adapter.bats` MA-9 | **REAL (test gap)** | The failure case proves only the restore path, so the chained handler body is never exercised. Add a TERM-mid-call case with a prior trap, and prove it can fail with a mutation. |

## Round r250-4 outcome (`27ff5a4b`, pushed)

| # | Outcome |
|---|---|
| 1 | **Fixed.** `tok = re.split(r'\s', window)[-1] + path`. RG-25 was red first: line-leading citations after a URL line in LF, CRLF and tab layouts, plus a line-leading URL that is still not a citation. CRLF also missed, because text-mode reading normalises `\r\n` to `\n`. |
| 2 | **Fixed by the same change.** A 4,000-char token followed by 200 citations took 4.91 s before and 0.074 s after. RG-26 (400 citations under `timeout 3`) was red first, with status 124. |
| 3 | **Fixed.** `grader_version` is 1.1.2 on the success path and on both error paths, and RG-17 follows. The only code consumer, `evals/harness/grade.sh:133`, passes the value through. |
| 4 | **Fixed.** The header now names `Bash(:*)`. `usage()` does not describe universal rules. |
| 5 | **Fixed (test).** MA-10 uses a prior EXIT trap and TERM mid-call, then asserts the temp file is removed and the prior handler ran. Mutation check: dropping the prior body from the chain left MA-9 green and turned MA-10 red, after which the code was restored. |

- **Suites, real tree, serial:** eval-recall-grader 26/0/0, check-permissions 14/0/0, model-adapter 10/0/0, json-schema-forwarding 4/0/0, probe-integration 13/0/0, skill-forwarding 3/0/0, repo-map-gen 6/0/0. `regen-checksums --check` reports changed=0.
- **Re-score:** of the 16 stored A/B runs, 0 detection change against 1.1.0 and 0 citation change against the `64c2eb09` grader. No stored run has a line-leading citation after a URL line. The table is in `replay-ab-rerun.md`.
