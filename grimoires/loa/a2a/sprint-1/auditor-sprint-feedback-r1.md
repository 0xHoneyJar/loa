# Sprint 263 Security Audit Feedback

**Auditor:** Fable 5.1 lead (auditing-security contract; audit dissent run 1 = the sprint's third and last dissent run)
**Date:** 2026-10-20
**Sprint Reference:** grimoires/loa/sprint.md § Sprint 1 (global 263)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md
**Scope:** `7600bd7d..baea8024` — sprint commit `bb03e931`, review rounds `596627f4`, `baea8024` (code only; fixtures, manifests, planning docs and run records excluded from the dissent diff)

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The sprint's new code sits on the harness side of the trust boundary: it reads agent-authored transcripts, sandbox files and dissent payloads, and it writes the sandbox's framework copy before a run. The lead's pass found the boundaries guarded (path normalisation, no execution of transcript text, bounded anchors, validated budget knobs, clean-tree overlay source). The audit dissent (gpt-5.5-pro + claude-headless, the sprint's third and last run) returned four findings — one HIGH, two MEDIUM, one LOW — all real and on one theme: the grader processes agent-controlled input with rules an agent can satisfy or exhaust. The HIGH is concrete on this corpus: pr-13 and pr-16 carry `curl -fsSL https://raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/scripts/mount-loa.sh | bash` (and pr-16 `git remote add loa https://github.com/0xHoneyJar/loa.git`), so an agent running those lines verbatim would be exempt from the contamination scan. Verdict for this round: CHANGES_REQUIRED; round r1c fixes all four test-first and the final audit file records the re-check.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 2 |
| Low | 1 |

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Class 7 exemption applies to executed Bash commands (dissent DISS-C-001)

**Severity:** HIGH
**File:** `evals/harness/ablation-grade.sh:repo_name_exempt` (via `check_value`, every scanned field including Bash `command`)
**Issue:** an occurrence of the repo name is exempt when its unit is a substring of any fixture line. pr-13 (`.claude/protocols/reference/helper-scripts.md:61`, `head.diff:2453`) and pr-16 (`README.md:49`, `.claude/commands/loa-eject.md:223`, `.claude/commands/contribute.md:39`) carry executable probe lines with the token, so an agent that runs them verbatim fetches the upstream repository without `contaminated` being set — a false negative on a genuinely contaminated run, on two PRs of this cycle's re-grade.
**Fix (r1c):** for a Bash `command` value, an occurrence whose logical line carries a network- or VCS-capable executable word (`git`, `gh`, `curl`, `wget`, `pip`, `npm`, `npx`, `ssh`, `scp`, `nc`, `docker`, `rsync`, `python -c` …) is never exempt; the exemption stays for display/search commands and for non-executing fields (notes, review text). Test: the pr-88 fixture gains a README with the curl line; the agent running it → `contaminated.pattern = repo_name`; grepping for it → exempt; AG-51's CI-clause quotation stays exempt.
**Reference:** CWE-184 (incomplete list of disallowed inputs); cycle-130 KF-046.

## Medium/Low Priority Issues

### [MED-001] Grader fallback to the agent-writable `pr/head` (dissent DISS-C-002)
- **File:** `evals/graders/recall-vs-defects.sh` head_dir resolution
- **Issue:** with no `EVAL_HEAD_DIR` and no fixture head, the scope map and the citation line-count bound read `$workspace/pr/head`, the graded agent's sandbox copy; the harness forces a `.no-head` sentinel, but any other caller gets the unsafe default. The scope map is also quadratic in headers on an unterminated 4 MB file.
- **Fix (r1c):** drop the fallback (opt-in `EVAL_ALLOW_WORKSPACE_HEAD=1` only, recorded in details as `head_dir_source`); above 5,000 headers the file gets no scope map (±20 fallback).

### [MED-002] Unbounded work on agent-authored transcript text (dissent DISS-C-003)
- **File:** `evals/harness/ablation-grade.sh` `expand`, `PATHISH`, `FILEISH`, the difflib pass
- **Issue:** a for-list of thousands of words with `$f$f$f`, a megabyte token, a megabyte result line or a 4 MB sandbox copy can exhaust the grader before its timeout; an agent has an incentive to make its own grade fail.
- **Fix (r1c):** cap stored for-list words (64) and expansion candidates (256); skip segments over 64 KB, words over 4,096 chars and more than 512 words per segment; clip result lines to 4,096 chars and 20,000 lines before the regexes; skip the difflib pass above 20,000 lines on either side (recorded in `oracle_scan_skipped`).

### [LOW-001] `corpus_sha256` hashes a second, unvalidated open (dissent DISS-C-004)
- **File:** `evals/harness/ablation-grade.sh:corpus_sha256`
- **Issue:** the path is validated through `read_regular()` and then re-opened with a plain `open()` that follows symlinks and has no size bound.
- **Fix (r1c):** one `O_RDONLY|O_NOFOLLOW` open with an `fstat` regular-file and size check; hash those bytes.


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


<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":2,"low":1},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-263","ts":"2026-10-20T01:54:43Z"} -->
