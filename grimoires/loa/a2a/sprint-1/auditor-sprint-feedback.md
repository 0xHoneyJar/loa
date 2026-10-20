# Sprint 263 Security Audit Feedback

**Auditor:** Fable 5.1 lead (auditing-security contract; audit dissent run 1 = the sprint's third and last dissent run; round-1 record `auditor-sprint-feedback-r1.md` CHANGES_REQUIRED 0/1/2/1; this file is the re-check after round r1c)
**Date:** 2026-10-20
**Sprint Reference:** grimoires/loa/sprint.md § Sprint 1 (global 263)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md
**Scope:** `7600bd7d..HEAD` — sprint commit `bb03e931`, review rounds `596627f4`, `baea8024`, audit round r1c `cddec367` (code only; fixtures, manifests, planning docs and run records excluded from the dissent diff)

---

## Verdict: APPROVED - LET'S FUCKING GO

---

## Executive Summary

The sprint's new code sits on the harness side of the trust boundary: it reads agent-authored transcripts, sandbox files and dissent payloads, and it writes the sandbox's framework copy before a run. The lead's pass found those boundaries guarded (path normalisation, no execution of transcript text, bounded anchors, validated budget knobs, clean-tree overlay source). The audit dissent (gpt-5.5-pro + claude-headless; the sprint's third and last dissent run) returned one HIGH, two MEDIUM and one LOW — all real, all on one theme: the grader applied rules to agent-controlled input that an agent could satisfy or exhaust. The HIGH was concrete on this corpus (pr-13 and pr-16 carry `curl … raw.githubusercontent.com/0xHoneyJar/loa … | bash` lines that the class 7 exemption would have licensed). Round r1c fixed all four test-first (AG-54, AG-55, RG-44); the re-check below is by reading and by test, the dissent cap being reached. No open finding remains.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 0 |

---

## Findings of the audit dissent run and their re-check (round r1c)

| Id | Severity (as found) | Finding | Fix | Re-check |
|---|---|---|---|---|
| HIGH-001 (DISS-C-001) | HIGH | class 7 exemption applied to executed Bash commands; pr-13 `helper-scripts.md:61`, pr-16 `README.md:49`, `contribute.md:39` carry probe lines with the token | a Bash logical line (heredoc bodies removed) holding the token and a network/VCS executable word is never exempt; quotations in notes stay PR content | `executes_network()` + `repo_name_exempt(val, tool)`; AG-54 (curl line run → `repo_name`; `git remote add` → `repo_name`; the curl line quoted in a notes heredoc → exempt, `head/README.md:3`; a grep carrying the token → hit as before); AG-51 unchanged. **Resolved.** |
| MED-001 (DISS-C-002) | MEDIUM | `recall-vs-defects.sh` fell back to the agent-writable `$workspace/pr/head`; quadratic scope map on huge files | fallback only under `EVAL_ALLOW_WORKSPACE_HEAD=1`, `details.head_dir_source` ∈ env/fixture/workspace/none; > 5,000 headers → ±20 fallback | RG-44 (default: not detected, source `none`; opt-in: detected, `workspace`; fixture: `fixture`). **Resolved.** |
| MED-002 (DISS-C-003) | MEDIUM | unbounded work on agent-authored transcript text | caps: for-list 64, expansion 256, segment 64 KB, word 4,096 chars / 512 per segment, result lines 4,096 chars / 20,000 lines, difflib skipped > 20,000 lines → `oracle_scan_skipped` | AG-55 (300-word for-list with `$f$f$f$f`, 100 KB token, 25,000-line copy → grades to completion; skipped path recorded; no exposure). **Resolved.** |
| LOW-001 (DISS-C-004) | LOW | `corpus_sha256` re-opened the path unvalidated | one `O_NOFOLLOW` open, `fstat` regular + size bound, hash those bytes | AG-45 still pins the digest of the real SHA256SUMS. **Resolved.** |

Re-validation after r1c: `evals/tests/` full suite green (see the sprint record), the 36-run re-grade reproduced every stored `recall` as `recall_pm3_v1` and changed no row (0 of 36) across rounds r1a, r1b and r1c; the detector pins of AG-50 are unchanged.

## Open Issues

None. The severity tally below counts open findings at this verdict.


## Trust boundaries read (lead pass)

- **Overlay inputs** (`evals/harness/lib/sandbox-mount.sh`): paths from `head.diff` headers and `git show --name-only` pass `norm()` (no absolute, `..`, backslash, control bytes), `in_scope()` (`.claude/` only, `checksums.json` excluded), `safe_dst()` (no symlink or non-directory component in the sandbox path) and `O_NOFOLLOW|O_EXCL` writes; the source tree must be a clean git checkout whose HEAD equals `source_commit`; git runs with empty global/system config, `--literal-pathspecs`, `core.fsmonitor=false`, no pager, no prompt. The sandbox `.git` is checked for exactly the base commit, no remotes, no alternates, no unreachable objects, no pinned blob.
- **Detector and contamination scan** (`evals/harness/ablation-grade.sh`): transcript JSON is parsed, never executed; shell command strings are tokenised by `shlex` and regexes; `expand()` substitutes only variables seen in the same transcript; the class 7 exemption compares strings against the immutable fixture; the KF-046 scan still fails closed on any unexempted repo-name token.
- **Dissent anchors** (`.claude/scripts/adversarial-review.sh`): `anchor_line` bounded 1 … 10,000,000 and dropped otherwise; the symbol anchor, the hallucination filter and anchor stability are unchanged; wire schemas take the field as nullable-required; the budget formula uses validated whole numbers (≤ 15 digits) and a maximum; a malformed knob falls back to `fixed` with a WARN that strips the value to a safe character set.
- **Eval config variant** (`apply_eval_config_variant`): `yq -i` with `strenv(G)` for the gate name (no interpolation of untrusted text); it writes only the two budget keys into the sandbox copy of `.loa.config.yaml`.
- **Credentials:** no change to the credential copies or the codex pre-flight; no secret appears in evidence lines, envelopes, rows or NOTES (hashes and paths only).
- **System Zone:** six `.claude/` files changed under the recorded marker and DEC-0625/0633; `tools/gen-checksums.sh --check` OK; no implementer wrote outside its listed files.

## Security Checklist for This Sprint

- [x] No hardcoded secrets added
- [x] Input validation on every new boundary (overlay paths, transcript tokens, anchor integers, budget knobs)
- [x] No new privilege: the harness runs as before; the overlay writes only inside the sandbox
- [x] No injection path: no shell interpolation of transcript or config text; yq expressions take env values
- [x] Error handling leaks paths and hashes only
- [x] Tests cover the security paths (sandbox-mount 12 cases incl. symlink refusal; took-effect clauses a–d; AG-47 … AG-53; NRM-68 … 74; BSC-1 … 10)

---

## Rejected dissent payloads

The audit dissent's sidecar holds no rows; the review sidecar's single stray row is triaged in `engineer-feedback.md` (a unit-test leak, bead bd-faa4j).


<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-263","ts":"2026-10-20T02:03:47Z"} -->
