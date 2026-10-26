APPROVED - LET'S FUCKING GO

# sprint-bug-277 (bug 20261025-c47e71, bd-ahxmh) — Security Audit (Paranoid Cypherpunk Auditor)

**Auditor:** lead (Fable 5.1) · **Head audited:** `4cf08e1c4` on `fix/post-ship-bugs-classifier-bb-glob` (red `893a68eb3`, fix `cfdd94f9d`, review round `b1acf9a64`, audit round `4cf08e1c4`) · **Review:** `engineer-feedback.md` (APPROVED after one round) · **Dissent:** one audit run (`adversarial-audit.json`, codex-headless + claude-headless 2/2, chain ok, consensus APPROVED, 1 LOW payload) · **Code read:** the rule and its comment (`.claude/scripts/classify-pr-type.sh:52-74`), the header rule list, PCT-T28 … T38, the wrapper's call site (`classify-merge-pr.sh:118-160`, unchanged), the workflow guard (`post-merge.yml`, unchanged) · **Mechanical:** `bash -n`; no `eval`, no network, no new input (the subject comes from `git log -1 --format=%s` as before); `gen-checksums.sh --check`, `check-manifest-paths.sh`, `repo-map-gen.sh --validate` pass on the head; detect-secrets over the branch's added lines clean

## Summary

No finding above LOW. The change is one fixed-regex rule over the untrusted merge subject, placed after the labels rule (a `cycle` label still wins) and before the cycle-id rule. The attack surface the classifier guards is the release route: a subject that can push a non-cycle merge onto the cycle pipeline or a release onto the simple path. The new rule only moves `chore/` branch merges and three housekeeping prefixes to `other`; the dissent found the one way it could over-reach — `[^ ]+` spanning path segments so a `release/chore/…` branch would be caught — and the audit round anchored the owner part (`[^ /]+`), pinned by PCT-T37/T38. Nothing is tagged on either path (the orchestrator prepares candidates only; publication needs the operator's approved digest), so a misclassification costs cycle-only pipeline phases, never a tag. System Zone edits under the bounded marker (DEC-0824), manifests regenerated in every commit, no secrets.

## Security checklist

| Area | Result | Evidence |
|---|---|---|
| Secrets | none; subjects and run ids only | detect-secrets over `/tmp/bugs-added.txt` (495 added lines): no hits |
| Auth / authz | no change; the publish path still requires the approved digest | `post-merge-orchestrator.sh validate_candidate_v2` (unchanged) |
| Input validation | fixed `grep -qE` regexes over the subject; anchored at `^`; owner part cannot span segments after the audit round | `classify-pr-type.sh:71`; PCT-T37 |
| Release-route integrity | release merges (`from …/release/…`, `release:` prefixes), `feat(cycle|sprint`, `Run Mode`, `Sprint Plan`, labelled PRs and `chore(release):` named releases keep the cycle route | PCT backtest, T33, T34, T36, T37 |
| Error handling | none new; the function stays a pure classifier | diff |
| System Zone discipline | marker on for every landing; `checksums.json`/`REPO-MAP.md` regenerated in `cfdd94f9d`, `b1acf9a64`, `4cf08e1c4` | landing logs |
| Tests of the error paths | red-first (`893a68eb3`, 5 red) → `red-test-check` VERIFIED; audit-round case red first (T37) | `reviewer.md`, implementer report a-r2 |

## Findings

- **LOW** (confidence: high) `.claude/scripts/classify-pr-type.sh:71` — the branch clause `from [^ ]+/chore/` matched a `chore` segment anywhere in the branch path, before the release-merge clause (fixed in `4cf08e1c4`). Failure: when a release branch is named `release/chore/v2.1.0`, then the merge classifies `other` and skips the cycle pipeline (the R-005 incident shape; today a candidate is still prepared and nothing is tagged, so the cost is the cycle-only phases). Fix landed: `from [^ /]+/chore/`; PCT-T37 (`…/release/chore/v2.1.0` → cycle, red before) and T38 (`…/chore/release/v2.1.0` → other) pin it (DEC-1008).

## Observations

- `chore(cycle-NNN):` squash subjects and `fix/`-branch merges naming a cycle keep classifying cycle (out of the observed failure; DEC-1002 alternative; no writer emits the former).

## Dissent dispositions (1 LOW)

- Branch clause spans segments → fixed (above). The payload's remark that the orchestrator was "not available in the audit material" is answered by the lead's dry run recorded in the review: the `other` path prepares a candidate and tags nothing.

## Rejected dissent payloads

None.

## Round 2 — post-approval (Bridgebuilder round on PR #1299, head `ced408300`)

Bridgebuilder's non-degraded round (2/2 voices, verdict COMMENT, 11 findings, 0 blocker) touched this sprint twice: a MEDIUM (disputed) "the branch rule is broader than the prefix rule — any chore/ branch merge is forced to other" (rejected: deliberate, DEC-1002 — every first-parent chore/ merge on main is housekeeping and a cycle label is the escape hatch; the segment-spanning part was already fixed in the audit round, `4cf08e1c4`), and a LOW "no test pins label precedence for the prefix form or the case-sensitivity" (accepted: PCT-T39/T40 in `ced408300`, tests only). A REFRAME proposing a distinct housekeeping classifier value that lets the workflow skip candidate preparation is a design question for the operator: bead bd-nr5i6. No code change in this round; manifests regenerated under the marker. Verdict unchanged.

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":1},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-bug-277","ts":"2026-10-26T01:20:00Z"} -->
