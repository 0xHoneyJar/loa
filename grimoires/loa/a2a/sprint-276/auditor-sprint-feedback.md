APPROVED - LET'S FUCKING GO

# Sprint 276 (cycle-134 Sprint 1) — Security Audit (Paranoid Cypherpunk Auditor), round 1

**Auditor:** lead (Fable 5.1) · **Head audited:** `c87cc20c` on `feature/cycle-134-post-ship-fixes` (landing `5fc05dc9`, KF-034 follow-up `a601702d`, review-round fix `c87cc20c`) · **Review:** `engineer-feedback.md` (APPROVED, 6 LOW observations) · **Dissent:** no separate audit run — the sprint's cap of three cross-model runs was spent on the review gate (A, C, D code-only diffs, each 2/2 voices APPROVED, 17 advisories, all dispositioned); recorded as a decision row (dissent cap) · **Code read:** the four code-only diffs in full (`~/.cache/loa/cycle-134/review/diff-{a,b,c,d}.patch`) plus the review-round hunk, the new bats files and fixtures · **Mechanical checks:** `bash -n` on the eight changed shell scripts (ok); no `eval`, raw network tool, or recursive delete through a variable added; every new embedded Python runs under `python3 -I`; the seeder's `GIT_NO_LAZY_FETCH=1` boundary intact; detect-secrets and the audit-key scanner over the staged files (digests and old CHANGELOG lines only)

## Summary

No finding above LOW. The sprint hardens guards and keeps every refusal before its write: the validator fails closed on unknown hook groups, damaged transcripts and an unbindable integrity record; the publisher refuses tag-identity conflicts, unreachable remotes and non-integer numbers before `PUBLISHING` is written and never overwrites a tag; the classifier stops a bot push from running the release pipeline; the supervisor signals a process group only after an identity match and documents the residual numeric-pgid window; the seeder keeps its provenance boundary and writes nothing partial; the proxy keeps a pid limit on its `NET_ADMIN` container. System Zone files were regenerated under the bounded marker in the landing commit, the secret scans are clean, and no credential, token or key appears in code, fixtures or evidence.

## Security checklist

| Area | Result | Evidence |
|---|---|---|
| Secrets | none hard-coded; the real rc.8 candidate fixture holds digests and public URLs only; detect-secrets hits are hex SHAs and two pre-existing CHANGELOG lines (an example placeholder, a PEM-header description) | staged-file scans at landing |
| Auth / authz | no new privilege; the publisher still requires the operator's approved digest; the workflow guard narrows what runs on a push | `post-merge.yml:182-187`; `validate_candidate_v2` |
| Input validation | classifier: fixed bash regexes over the untrusted subject, number validated `^[1-9][0-9]*$`, type from a fixed set; orchestrator: number tokens read through the `json` parse hooks (no regex over free text), paths named, exit 2; validator: transcript lines parsed as JSON objects with a size cap, hook queries compared as text (never compiled as regex), hex ids for matchers; supervisor: `record-job` validates the name (`[A-Za-z0-9_.-]`) and pgid (`^[1-9][0-9]*$`); seeder: paths NUL-safe, blobs charged against bounds before any fetch | the diffs; `took-effect-hooks.bats` TEH-3/TEH-7/TEH-10; `classify-merge-pr.bats` KF063-T5/T6/T7 |
| Path and symlink safety | the retained-HOME walk uses `lstat`, `followlinks=False`, refuses symlinks, special files and unreadable paths by name, stays under `<run>/{meta/home,home}`; transcripts that are symlinks are refused; `r3_pinned` rejects `..` components; record writes go through temp files and `mv -f` | `took-effect-integrity.bats` TEI-7; `took-effect-transcripts.bats` TET-10 |
| Network egress | one new read: `git ls-remote` (and a fetch into a scratch ref) against the candidate's `remote_push_url`, bounded by `timeout 60`, before any write; the seeder fetches only the checked blob set in one batch; the proxy's limits unchanged except the pid bound | `post-merge-orchestrator.sh:1665-1700`; `seed-corpus-from-external.sh:533-545` |
| Error handling / disclosure | every refusal is one stderr line naming the repair; git's stderr is suppressed in the remote lookup (the URL and the cause class are named); the seeder quotes at most 300 chars of git stderr | the diffs |
| Process safety | TERM/KILL only to a pgid whose leader's identity matches the record, re-read before each signal; legacy, leaderless and unsettled groups are never signalled and are listed for the operator; the residual check-then-signal window is documented in the lib header | `batch-supervisor.bats` BSV-14 … BSV-19 |
| System Zone discipline | `.claude/` and `.github/` edits under the bounded marker (DEC-0824); `checksums.json` and REPO-MAP regenerated in the landing commit; the gates (`guard-yield --check`, knob-readers, manifest-paths, `gen-checksums --check`, swallowed-jq) pass | landing commit `5fc05dc9`; mirror gates log |
| Tests of the error paths | every refusal path above has a red-first fixture (fails-before verified by the lead in a scratch worktree) | `landing.md`; the per-implementer reports |

## Observations

- **LOW** (confidence: medium) `.claude/scripts/post-merge-orchestrator.sh:2070` — `validate_tag_identity` contacts the candidate's `remote_push_url` (read-only `ls-remote`, then a fetch into a scratch ref) before the existing checkout/origin equality check at `:2279`. Failure: when an approved candidate carries a hostile `remote_push_url`, then the publisher performs a bounded read against that host before refusing on the origin mismatch. The approval digest binds the URL, so the attacker would need the operator's approval; ordering the origin check first would close it for free in a later sprint.
- **LOW** (confidence: low) `evals/harness/took-effect.sh:702` — extra file names from a retained HOME copy are joined into the evidence text unsanitised (also noted at review). Failure: when a retained copy holds a file named with control characters, then the evidence line is multi-line and a line-based consumer can be misled. The retained copy is an operator-side debugging option; sanitise at the join before the walk becomes a measurement input.
- **LOW** (confidence: medium) `evals/harness/took-effect.sh:435` — the pin's source order admits the batch `MANIFEST.json` (written by `run-ablation.sh` from the lead's `--source-commit`) when the suite names no hex pin. Failure: when a run's suite lacks `arms[].source_commit` and a tampered batch manifest names a different commit that also exists in the source repository, then the record is cross-checked against that commit's manifest instead of the operator's pin. The suite's pin wins when present, the chosen commit must also equal `pipeline.json`'s, and the manifest is the lead's own artefact (DEC-0990); for a claimed measurement the suite should always carry the pin.

## Dissent

No audit-type run: the three permitted runs were spent at the review gate on the three largest code diffs (A, C, D), whose payloads already carried the security questions (TOCTOU on pgids, the v1 publish path, remote lookup failure modes, evidence forging); each was dispositioned in `engineer-feedback.md`. The decision is recorded in `decisions.yaml` (the dissent-cap row of this sprint).

## Rejected dissent payloads

None at this gate (none run).

## Round 2 — post-approval fix (head `dad9136f`)

The portability fix touches one System Zone file under the marker: an optional `source` of a sibling library (path fixed, `$SCRIPT_DIR`), a fallback that runs the given command under `command timeout` / `gtimeout` or plainly, no new input, no new network use. Manifests regenerated in the commit. Verdict unchanged.

## Round 3 — Bridgebuilder round-2 fixes (head `5e3f44f5`)

Five small changes, two in System Zone files under the marker: a first-line subject match in the classifier (less input reaches the regex), bounded fetches (a stalling remote cannot hang the publisher), a URL fallback that avoids probing the literal `null`, quoted/truncated untrusted text in evidence lines, and record cleanup. No new input surface, no new network use. Verdict unchanged.

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":3},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-276","ts":"2026-10-25T08:27:51Z"} -->
