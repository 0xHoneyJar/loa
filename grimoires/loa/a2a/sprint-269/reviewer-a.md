# Sprint 1 (global 269) implementer A — Tasks 1.1, 1.2, 1.3

Model: global.anthropic.claude-opus-5-5.
Patch `~/.cache/loa/cycle-132/patches/s1-a.patch`. The copy at `grimoires/loa/a2a/sprint-1/reviewer-a.md` is gitignored, so not in the patch.

## What was built
- **Task 1.1** `evals/harness/seed-corpus-from-record.sh`: `--feedback` record-root paths; `--paths` scope; `--allow-no-labels`; `MODEL_AVAILABILITY` + `exposure`/`contamination_note`; `--stamp-exposure pr-NN` (idempotent); parser reads `### SEV-n —` and `**SEV-n — …**` findings. `--build-manifest`/`--sync-labels` untouched. `record-pairs.tsv`: rows 255–264, a `paths` column, the derivation comments. Seeded pr-19 … pr-28, stamped pr-11 … pr-18, refrozen.
- **Task 1.2** `evals/harness/incident-scan.sh` (new); `evals/fixtures/review-prs/incidents/pr-11 … pr-28.{tsv,meta.json}` + `evidence/` (scanned at origin/main 13673960, live read-only gh).
- **Task 1.3** `evals/harness/annotation-packets.sh`, `evals/harness/annotation/codebook.md`, `evals/harness/schemas/annotation.schema.json` (all new). Scratch packets for all 18 fixtures at `/tmp/s1a/packets/` (not committed) all pass the leak check.

## How it was tested
| file | cases |
|---|---|
| evals/tests/seed-corpus.bats | 24 (18 existing + SC-P1 … SC-P6) |
| evals/tests/incident-scan.bats | 8 (new) |
| evals/tests/annotation-packets.bats | 8 (new) |
| whole `evals/tests/` | 562 / 562 green |
Commands: `bats evals/tests/{seed-corpus,incident-scan,annotation-packets}.bats`, then `bats evals/tests/` (bats = `~/.cache/loa/cycle-128/s2d/bin/bats`); `bash -n` on the three scripts; `no-secrets.sh` over pr-19 … pr-28, new labels/manifests, `incidents/` (pass). The scanner and packet scripts were drafted before their bats files; 10 mutants (window, fix filter, redaction, truncation, merge choice, leak check, ±3 slack, snippets, code exemption, hunk merge) each turn ≥ 1 case red.

## AC evidence
- FR-1 AC1: PASS — every new row `--dry-run` exit 0; `--feedback` outside `a2a/sprint-<N>/` in SC-P1 and pr-27/28.
- FR-1 AC2: PASS — pr-19 … pr-28 complete (fixture.yaml, head.diff, PR.md, both INSTRUCTIONS, base/, head/), labels pending.
- FR-1 AC3: PASS — yq parses exposure + note on pr-11 … pr-28; SC-P2, SC-P3.
- FR-1 AC4: PASS — refrozen 1,776 files, `--check` OK, 562/562.
- Task 1.2 (window, sources, evidence, meta, exits): PASS — IS-1 … IS-8.
- FR-2 AC1: PASS — AP-1 byte-identical reruns; AP-4/AP-5 leak fails closed, nothing written.
- Task 1.3: PASS — review_driven outside the packet (AP-3); sample label file validates (AP-7); no if/then in the schema (AP-8).

## Candidate table (seeded order; dates UTC)
| fixture | sprint | head date | fix date | merge date | maturity d | seeded labels | fix hunks | review-driven | incidents | exposure.fable_5_1 | files | diff lines |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| pr-11 | 247 | 2026-09-25 | 2026-09-25 | 2026-10-07 | 13 | 5 | 18 | 12 | 15 | post-cutoff | 65 | 5325 |
| pr-12 | 248 | 2026-09-25 | 2026-10-05 | 2026-10-07 | 13 | 8 | 139 | 118 | 12 | post-cutoff | 15 | 1077 |
| pr-13 | 249 | 2026-10-05 | 2026-10-05 | 2026-10-07 | 13 | 5 | 38 | 30 | 13 | post-cutoff | 54 | 5880 |
| pr-14 | 250 | 2026-10-06 | 2026-10-07 | 2026-10-07 | 13 | 2 | 95 | 63 | 26 | post-cutoff | 88 | 3881 |
| pr-15 | 251 | 2026-10-07 | 2026-10-07 | 2026-10-07 | 13 | 3 | 227 | 146 | 12 | post-cutoff | 45 | 3847 |
| pr-16 | 252 | 2026-10-13 | 2026-10-13 | 2026-10-13 | 7 | 4 | 18 | 9 | 8 | post-cutoff | 39 | 4174 |
| pr-17 | 253 | 2026-10-13 | 2026-10-13 | 2026-10-13 | 7 | 20 | 99 | 57 | 10 | post-cutoff | 41 | 4437 |
| pr-18 | 254 | 2026-10-13 | 2026-10-13 | 2026-10-13 | 7 | 8 | 103 | 39 | 2 | post-cutoff | 29 | 2194 |
| pr-19 | 255 | 2026-10-14 | 2026-10-14 | 2026-10-14 | 6 | 11 | 20 | 18 | 10 | post-cutoff | 81 | 8031 |
| pr-20 | 256 | 2026-10-14 | 2026-10-14 | 2026-10-14 | 6 | 4 | 56 | 23 | 1 | post-cutoff | 68 | 7124 |
| pr-21 | 257 | 2026-10-14 | 2026-10-14 | 2026-10-14 | 6 | 2 | 105 | 45 | 3 | post-cutoff | 80 | 8686 |
| pr-22 | 258 | 2026-10-15 | 2026-10-15 | 2026-10-18 | 2 | 11 | 79 | 56 | 9 | post-cutoff | 72 | 7885 |
| pr-23 | 259 | 2026-10-15 | 2026-10-15 | 2026-10-18 | 2 | 1 | 66 | 16 | 11 | post-cutoff | 16 | 3674 |
| pr-24 | 260 | 2026-10-16 | 2026-10-16 | 2026-10-18 | 2 | 4 | 31 | 21 | 8 | post-cutoff | 17 | 4685 |
| pr-25 | 261 | 2026-10-18 | 2026-10-18 | 2026-10-18 | 2 | 1 | 29 | 19 | 10 | post-cutoff | 12 | 1620 |
| pr-26 | 262 | 2026-10-18 | 2026-10-18 | 2026-10-18 | 2 | 0 | 54 | 20 | 2 | post-cutoff | 5 | 1780 |
| pr-27 | 263 | 2026-10-19 | 2026-10-20 | 2026-10-20 | 0 | 7 | 28 | 16 | 3 | post-cutoff | 35 | 5873 |
| pr-28 | 264 | 2026-10-20 | 2026-10-20 | 2026-10-20 | 0 | 2 | 9 | 7 | 2 | post-cutoff | 11 | 584 |
Labels are review-derived; hunk counts come from the scratch packets. Corpus ceiling: all 18 have exposure and ≥ 9 fix hunks, so the cap of 15 binds. All are `post-cutoff` for Fable 5.1.

## DECISION bullets
- DECISION: pairs (base/head/fix) follow the 247–254 convention, from each PR's `merge^1..merge^2` log and the round-1 headers: 255 ee1625a0^/ee1625a0/b6802e4f; 256 40df53ed^/40df53ed/9c4ed319; 257 163656ff^/163656ff/2fb03b5c; 258 05442536^/05442536/ffe162ef; 259 a293df09^/6be23186/05830914; 260 c02d12bb^/4c279606/53600ea3; 261 4434d450/4af3294b/e95139fe; 262 0fda13a0^/82c5cd7d/56ce0b8f; 263 bb03e931^/bb03e931/cddec367; 264 0281ea57^/0281ea57/798d88cf.
- DECISION: feedback is the round-1 review plus the round-1 audit (`-r1` where present). Later rounds read trees after head.
- DECISION: 257 carries its PR's Bridgebuilder triage (bb-triage.md, fix 2fb03b5c), as 254 did. The BB rounds of PR #1283/#1286 (76ba937e, aac80f4c) have no triage file and are left out; no file means their hunks could not be tagged review_driven.
- DECISION: 261/262 share base 4434d450 and interleave, so a new `--paths` scope splits them on disjoint files. 262 gets its row writer, report, their bats and fixtures (unchanged between 4af3294b and 82c5cd7d). 261 gets the rest minus README.md. Rejected: one merged fixture (one fewer cluster), overlapping fixtures (double counting).
- DECISION: scope exclusions. 255 and 263 drop `evals/fixtures/review-prs/*` (other fixtures' hidden keys). 263 drops `evals/tests/fixtures/c131-oracle/*` (arm transcripts). 258 drops `evals/tests/fixtures/ablation-runs/runs/*` (341 dirs regen.sh generates).
- DECISION: 265 is skipped. Its change lives under grimoires/, which the seeder scopes out, so it has no in-scope file.
- DECISION: the parser gained the `### SEV-n —` / `**SEV-n — …**` forms. Without them 6 of 10 sprints parsed zero findings and would not build. `--allow-no-labels` builds pr-26, the one fixture still at zero; annotation supplies the key.
- DECISION: seeding wrote tasks to a scratch `--tasks-dir`. `evals/tasks/` is not mine, and the c132 suite root defines its own tasks (Task 1.11).
- DECISION: exposure uses the head commit's committer date (UTC); after 2026-06 is post-cutoff; Opus is always unverified.
- DECISION: `--window-days` is an optional cap with no default (D-7.8's merge→scan window wins over §5.2's "30"). Merge = oldest first-parent commit containing fix. Source (a) uses the range merge..main, bounded by the window.
- DECISION: gh queries OR up to 5 basenames with `created:>=` the merge day; a hit must name a full changed path; PRs count as `issue`.
- DECISION: a BB round counts only when the PR number is in its file name or first heading; a body mention is not enough. Dated by its `bridgebuilder-<ts>` run id; `bb-triage*` included.
- DECISION: incident ids I01… come from the scan (sorted by date, kind, ref); packets reuse them.
- DECISION: hunks come from `git diff -U0 --inter-hunk-context=3`, matching the seeder's ≤ 3-line merge. Context is from the fixture's head/ copy so anchors resolve there. Fix messages never enter a packet.
- DECISION: `hunks.meta.json` is written beside the packet directory (`<out>/pr-NN.hunks.meta.json`), not inside it. The brief says outside; SDD §1.4 says inside.
- DECISION: review_driven reads every feedback-family file in the feedback directories: engineer/auditor/bridgebuilder/bb-triage plus `adversarial-review*`/`adversarial-audit*` JSON. Cycle-131's round-1 findings live in the dissent envelopes. A snippet needs ≥ 8 chars and the basename within 1,500 chars. Over-tagging only shrinks the pipeline-independent set.
- DECISION: the leak check compares whole lines (normalised, ≥ 20 chars, raw and prefix-stripped). The fixture's own code lines are exempt. Incident summaries sit on their own line. Rejected: substring containment (cost, and the spec says lines).

## CHANGELOG entry text (### Added)
- `seed-corpus-from-record.sh` gained `--feedback` record-root paths, `--paths`, `--allow-no-labels`, `--stamp-exposure` and the `exposure`/`contamination_note` fields (cycle-132 FR-1).
- Record fixtures pr-19 … pr-28 were seeded from sprints 255–264, and pr-11 … pr-18 gained exposure provenance (SHA256SUMS refrozen).
- `incident-scan.sh` compiled post-merge incidents per fixture over one merge→scan window, with evidence and a completeness meta (FR-2, D-7.8).
- `annotation-packets.sh`, the codebook and `annotation.schema.json` built deterministic, leak-checked blind packets with an out-of-packet `review_driven` tag (FR-2, D-7.6).

## What the lead must do
- Merge with implementer B by hand: B also edits the seeder. My bats cases are SC-P1 … SC-P6 at the end of seed-corpus.bats.
- `incidents/` holds later fix diffs, so treat it like `labels/`/`manifests/`. It must never be mounted, and the grader's hidden-path tokens do not cover it today.
- Packets pr-12 (1.36 MB, 139 hunks) and pr-15 (0.89 MB, 227 hunks) exceed one session's context; split them or pick other fixtures. Rescan pr-27/pr-28 (0 days mature) before annotation.
- origin/main moved mid-session (to 13673960, PR #1288); every meta records it.
- PRD FR-1 AC3 still says `post_cutoff`; I wrote `exposure` per the brief and SDD §3.2.

## Round 1

DISS-C-004 (Sprint 269 dissent review, confirmed by the lead): the review_driven detector capped citation extensions at 6 characters. Citations of `.loa.config.yaml.example:N` or `evals/harness/Dockerfile.ablation:N` therefore never matched, and those hunks were tagged review_driven=false.

- **Fix:** `CITE_RX` in `evals/harness/annotation-packets.sh` now allows extensions of 1–12 characters, as grader 1.3.3 does. Line-number caps and every other boundary rule are unchanged. The leak check has no extension cap.
- **Sibling regex:** the snippet filter's "bare path" test now covers 7–12 character extensions only when the token names a fixture file. Widened unconditionally, it dropped dotted identifiers such as `red_test.command` as snippets. That flipped pr-18 H54 to false, so I rejected it.
- **Test:** new case AP-9 cites `.loa.config.yaml.example:127` and `evals/harness/Dockerfile.ablation:19` and expects both hunks tagged true. It was red before the fix. annotation-packets.bats now passes 9 of 9, and AP-1 … AP-8 are unchanged. `bash -n` passes.
- **Packets:** I rebuilt all 18 fixtures and diffed them against a pre-fix build. Every `codebook.md`, `hunks.md` and `incidents.md` is byte-identical. Only `hunks.meta.json` changes, and only in fixtures with hunks in long-extension files.

| fixture | long-extension hunk files | review_driven changes |
|---|---|---|
| pr-12 | .loa.config.yaml.example | none (cited_by gains on H106/H108/H109; H125 drops a bare-filename snippet hit) |
| pr-14 | .claude/defaults/model-config.yaml.checksum | none (H81 drops a bare-filename snippet hit) |
| pr-15 | model-config.yaml.checksum, .loa.config.yaml.example | H171 false → true |
| pr-16 | .loa.config.yaml.example | none (cited_by on H07) |
| pr-20 | .loa.config.yaml.example | none (H51/H52 drop a bare-filename snippet hit) |
| pr-21 | .loa.config.yaml.example | H92 false → true |
| pr-22 | evals/harness/Dockerfile.ablation | none (cited_by on H01) |

pr-11, pr-13, pr-17, pr-18, pr-19 and pr-23 … pr-28 have no long-extension hunk files and their meta files are byte-identical. The lead should rebuild hunks.meta.json for pr-12, 14, 15, 16, 20, 21 and 22; the merge changes only for pr-15 and pr-21.

- DECISION: a quoted bare file name with a 7–12 character extension is a path, not a code snippet, when it resolves to a fixture file; otherwise it stays a snippet. Rejected: widening the snippet filter unconditionally, because it loses dotted identifiers (pr-18 H54 true → false).

Patch: `~/.cache/loa/cycle-132/patches/s1-a-r1.patch`, incremental over s1-a.patch (2 files, +41/−3). It applies with `git apply --check` after s1-a.patch on 346dbb87.

## Round 2

DISS-C-004 (Sprint 269 security audit, A5): `safe()` in `evals/harness/annotation-packets.sh` stripped C0/C1 controls and U+2028/U+2029. It let Trojan Source characters through to a blind annotator: bidi embeddings and overrides U+202A–U+202E, isolates U+2066–U+2069, and the zero-width U+200B–U+200D and U+FEFF.

- **Fix, part 1:** `safe()` now replaces each of those code points with the visible marker U+FFFD before redaction and control stripping; nothing is silently dropped. This covers head context, hunk diff lines, incident references, files, summaries and evidence.
- **Fix, part 2:** a backstop runs before the leak check. Any packet line that still carries one of those code points, from a field that bypassed `safe()`, refuses the packet: exit 1, `trojan: <file>:<line>: U+XXXX in …` printed, nothing written. The header comment documents both rules.
- **Tests:** AP-10 puts a U+202E override in a head line, a ZWJ and an LRI in an incident summary, and a ZWSP and a BOM in an evidence diff line. Each shows as U+FFFD, and a Python scan finds none left in the packet. AP-11 puts a ZWJ in an incident row's `kind` column, which reaches the heading unsanitised, and expects a refusal with the U+200D line printed and nothing written. Both cases were red before the fix. annotation-packets.bats passes 11 of 11; AP-1 … AP-9 are unchanged, including AP-1's determinism. `bash -n` passes. Removing either half of the fix turns its case red.
- **Real packets:** all 18 fixtures rebuilt byte-identical to the Round 1 build, consistent with the lead's scan finding no such code points.

- DECISION: the refusal test uses an unsanitised field (the incident `kind` column), not an excerpt. Since `safe()` now marks every excerpt, a ZWJ in an excerpt becomes U+FFFD and is written; AP-10 proves that. The refusal is the backstop for text that bypasses `safe()`. Rejected: leaving excerpts unsanitised so they refuse, which would contradict the marker rule.

Patch: `~/.cache/loa/cycle-132/patches/s1-a-r2.patch`, incremental over s1-a-r1.patch (2 files, +48/−2). It applies with `git apply --check` after s1-a.patch and s1-a-r1.patch on 346dbb87.
