**[1/3] Review by anthropic (claude-headless)**

<!-- bridge-findings-start -->
```json
{
  "schema_version": 1,
  "findings": [
    {
      "id": "F-001",
      "title": "Pricing/cap chain fails open: unknown or malformed price yields '0 0 0' instead of an error",
      "severity": "MEDIUM",
      "category": "correctness",
      "file": "evals/harness/lib/session-exec.sh:37-48,54-68",
      "description": "price_for returns the literal string null whenever LOA_EVAL_PRICING_JSON is not valid JSON, the model key is absent, or pricing.py produces no line. price_events then receives --argjson p null, the jq program errors on `number * null`, stderr is discarded, and the `|| echo \"0 0 0\"` fallback reports zero turns and zero spend. A caller using this as the D-4.10 cap watchdog will never see the budget crossed when pricing is unavailable, which is the opposite of the fail-closed posture the harness claims elsewhere. The same fallback also masks any unrelated jq failure (truncated events file, schema change) as 'within budget'.",
      "suggestion": "Have price_for return a non-zero status (or print an explicit sentinel) when pricing resolves to null, and have price_events refuse to run with a null/invalid price table. Replace the blanket `|| echo \"0 0 0\"` with a distinct sentinel (e.g. `ERR`) so the watchdog can halt or mark the run degraded rather than silently proceeding. Since this is a verbatim copy, apply the same fix to pipeline-run.sh so the drift test keeps passing.",
      "confidence": 0.5
    },
    {
      "id": "F-002",
      "title": "ENV_SHIM allowlist omits PATH/HOME and non-bearer AWS credentials; fd close bound is hardcoded",
      "severity": "LOW",
      "category": "correctness",
      "file": "evals/harness/lib/session-exec.sh:21-29",
      "description": "The shim execs with only the named keys. If PATH is not in the keys-csv, os.execvpe falls back to os.defpath (/bin:/usr/bin), so a `claude` binary under /usr/local/bin or ~/.local/bin is only found when the caller passes an absolute path. HOME is likewise not in PASS_KEYS, yet AWS_PROFILE (which is) resolves via ~/.aws, and the claude CLI reads ~/.claude. PASS_KEYS also carries only the bearer-token Bedrock credential; an operator authenticated with AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY/AWS_SESSION_TOKEN would get a silent auth failure inside the session. os.closerange(3, 65536) ignores the real RLIMIT_NOFILE. The call site in blind-session.sh is not visible in this diff, so these may be supplied there.",
      "suggestion": "Document in the header which keys the caller must always add (PATH, HOME, TMPDIR) or add them to PASS_KEYS explicitly, extend the Bedrock set to cover IAM keys (and add them to SECRET_KEYS), and derive the closerange upper bound from resource.getrlimit(RLIMIT_NOFILE) or os.sysconf('SC_OPEN_MAX').",
      "confidence": 0.35
    },
    {
      "id": "F-003",
      "title": "Duplicated session mechanics guarded by a drift test rather than shared by sourcing",
      "severity": "REFRAME",
      "category": "maintainability",
      "file": "evals/harness/lib/session-exec.sh:7-12",
      "description": "The header states every definition is a verbatim copy of pipeline-run.sh and that blind-session.bats fails when they diverge. The drift test is a reasonable stopgap, but it only fires when evals/tests runs, and any future fix (such as F-001) must now be applied in two places. The stated reason for not sourcing is that pipeline-run.bats copies only the files it sources today.",
      "suggestion": "Consider making pipeline-run.sh source lib/session-exec.sh and adding the lib to pipeline-run.bats' copy list. That removes the duplicate and the drift test becomes unnecessary. If the duplication stays, keep the drift test byte-exact (not whitespace-normalised) so a one-character divergence is caught.",
      "confidence": 0.5
    },
    {
      "id": "F-004",
      "title": "Secret handling in the exec shim is well designed",
      "severity": "PRAISE",
      "category": "security",
      "file": "evals/harness/lib/session-exec.sh:18-29",
      "description": "Secret values never appear on argv: only key names are passed to the python shim, values are read from the inherited environment, and SECRET_KEYS are recorded as <set> in captures. Descriptors above 2 are closed before exec, and the python runs with -I so no planted module can be imported. This is the right shape for a trust boundary around a headless model session.",
      "suggestion": "None required.",
      "confidence": 0.9
    },
    {
      "id": "F-005",
      "title": "Synthetic power-mini diffs have hunk headers that contradict their bodies",
      "severity": "LOW",
      "category": "testing",
      "file": "evals/analysis/c132/tests/fixtures/power-mini/fixtures/pr-93/head.diff:4",
      "description": "The fixture declares `@@ -1,1 +1,1 @@` and then carries 750 removed and 750 added lines (pr-94 is 3004 lines and pr-92 404 lines under the same shape). Any consumer that trusts the hunk header for size estimation, or that validates diffs with `git apply --check`/`patch --dry-run`, will either miscount the diff as two lines or reject it outright. The power analysis presumably counts +/- lines directly, so this only matters if the fixture is reused by a stricter parser later.",
      "suggestion": "Generate the fixtures with correct hunk counts (`@@ -1,750 +1,750 @@`) so they are valid unified diffs, or add a comment in the generator and a test asserting the size metric used does not read the header.",
      "confidence": 0.4
    },
    {
      "id": "F-006",
      "title": "Several corpus files render as zero-length; confirm intentional empties versus truncated rendering",
      "severity": "SPECULATION",
      "category": "testing",
      "file": "evals/fixtures/review-prs/manifests/pr-26.json",
      "description": "manifests/pr-26.json and pr-27.json, manifests/c131/pr-12/13/17/18.json, labels/review/pr-12/13/17/18.tsv, incidents/pr-13/evidence/I04..I13 and the pr-24 and pr-25 fixture trees all appear as +0 -0 while their siblings (manifests/review/pr-26.json at +392, pr-24 head/base harness scripts) are populated. This may be the diff renderer dropping patches for a 2188-file PR, or genuine empties (e.g. PRs with no review-track labels), but an empty manifest for a PR that has review labels would silently drop it from the reads.",
      "suggestion": "Verify every one of these paths is listed in evals/fixtures/review-prs/SHA256SUMS with a non-empty hash, and have validate-suite.sh (or seed-corpus-from-record.sh) refuse a corpus entry whose manifest or label file is zero bytes.",
      "confidence": 0.3
    },
    {
      "id": "F-007",
      "title": "Ground-truth labels for already-analysed PRs changed and the pre-registration has 18 addenda",
      "severity": "SPECULATION",
      "category": "methodology",
      "file": "evals/fixtures/review-prs/labels/pr-15.tsv",
      "description": "labels/pr-11, pr-14, pr-15 and pr-16 are rewritten (pr-15: +580 -254), and manifests/pr-14.json and pr-15.json change substantially, while PREREGISTRATION-addendum-1 through -18 and judge/run-1-invalid/ show the protocol and a judge run were revised during the study. The c131/ snapshots of the old labels and manifests indicate the prior state was preserved, which is good practice, but the headline 'pre-registered reads INCONCLUSIVE (+0.097)' should state whether the relabelled PRs move the estimate and which addenda post-date the first look.",
      "suggestion": "Add a sensitivity row to reads.md computed against the c131 labels, and a table in registration-timeline.md mapping each addendum to the look it preceded, so a reader can judge how much of the pre-registration survived contact with the data.",
      "confidence": 0.35
    },
    {
      "id": "F-008",
      "title": "Fixture corpus vendors multiple multi-thousand-line copies of framework files",
      "severity": "LOW",
      "category": "maintainability",
      "file": "evals/fixtures/review-prs/SHA256SUMS",
      "description": "This PR adds four copies of model-config.yaml (~1.5k lines each), three copies of .loa.config.yaml.example (~3k), cheval.py (3.3k), adversarial-review.sh (4.9k), two copies of block-destructive-bash.sh, and compiled dist/*.js and *.js.map for the bridgebuilder skill. Each new review PR in the corpus repeats this. The content is already pinned by SHA256SUMS and the fixture.yaml records base/head, so the trees are reconstructible.",
      "suggestion": "Consider materialising base/ and head/ trees at harness time from the pinned commits into the sandbox (verifying against SHA256SUMS), or moving the trees to git-lfs. If vendoring stays, exclude build outputs (dist/, *.map) from fixtures unless a task reads them.",
      "confidence": 0.4
    },
    {
      "id": "F-009",
      "title": "Fixture trees contain live hook code that must not run inside the reviewer's session",
      "severity": "SPECULATION",
      "category": "security",
      "file": "evals/fixtures/review-prs/pr-20/head/.claude/hooks/session-start/loa-l7-surface-soul.sh",
      "description": "pr-19/pr-20 fixtures ship executable SessionStart and safety hooks, a .loa.config.yaml, and skill trees under .claude/. If the sandbox mounts a fixture tree as the project root for `claude -p`, Claude Code may discover and execute the subject PR's own hooks. That would both run untrusted fixture code on the harness host and inject fixture-authored context into the reviewer, confounding the review-catch measurement.",
      "suggestion": "Confirm sandbox-mount.sh mounts fixture trees read-only at a path Claude Code does not treat as the project root (or strips .claude/settings*.json and hooks/), and add a bats assertion that no fixture hook executes during a blind session.",
      "confidence": 0.25
    },
    {
      "id": "F-010",
      "title": "Pre-registration hash chain and reproduction artefacts are thorough",
      "severity": "PRAISE",
      "category": "methodology",
      "file": "grimoires/loa/reports/review-catch-c132/registration-timeline.md",
      "description": "Each registration is hashed (REGISTRATION-N.sha256.txt), the chain is tested (tests/test_registration_chain.py), a timeline script regenerates the ordering, reproduce.sh with environment.json and live-runs.jsonl supports the byte-identical fresh-clone claim, and the invalidated judge run is kept under run-1-invalid/ rather than deleted. This is the right level of auditability for a study whose conclusion is INCONCLUSIVE.",
      "suggestion": "None required.",
      "confidence": 0.85
    }
  ]
}
```
<!-- bridge-findings-end -->
**[2/3] Review by openai (gpt-5.5-pro)**

I’ll check the new session helper and treat the historical fixture files as evaluation data when assessing impact.

<!-- bridge-findings-start -->
```json
{
  "schema_version": 1,
  "findings": [
    {
      "id": "F-001",
      "title": "Descriptor cleanup leaves high-numbered descriptors inherited",
      "severity": "MEDIUM",
      "category": "security",
      "file": "evals/harness/lib/session-exec.sh:24",
      "description": "os.closerange(3, 65536) only closes descriptors through 65535. On hosts permitting higher descriptor numbers, an inheritable descriptor above that bound survives exec, violating the stated isolation contract and potentially exposing an open file or socket to the child.",
      "suggestion": "Close descriptors through the process descriptor limit or enumerate open descriptors. Add a regression using an inheritable descriptor above 65535 on supported hosts.",
      "confidence": 0.99
    },
    {
      "id": "F-002",
      "title": "Pricing failures are reported as zero spend",
      "severity": "MEDIUM",
      "category": "budget-enforcement",
      "file": "evals/harness/lib/session-exec.sh:68",
      "description": "Any jq failure or failure to read the events file produces a successful \"0 0 0\" result. Consumers cannot distinguish unavailable metering from a session with no usage, allowing the cap watchdog to continue without a valid spend estimate.",
      "suggestion": "Return a distinguishable metering error and require the watchdog to stop or explicitly mark enforcement unavailable. Preserve tolerance for incomplete trailing stream records separately.",
      "confidence": 0.95
    },
    {
      "id": "F-003",
      "title": "Child environment uses an explicit allowlist",
      "severity": "PRAISE",
      "category": "security",
      "file": "evals/harness/lib/session-exec.sh:21",
      "description": "The exec shim constructs the child environment exclusively from named keys and passes credential values through the environment instead of command arguments, reducing accidental environment and argv disclosure.",
      "suggestion": "Retain this allowlist boundary as additional authentication mechanisms are supported."
    }
  ]
}
```
<!-- bridge-findings-end -->
**Verdict Quality**: ✓ APPROVED — 2/2 voices, chain ok · not planned: google/gemini-3.1-pro-preview (agy opt-in off: hounfour.headless.agy_opt_in)

**[3/3] Multi-Model Consensus Review**

Models: anthropic/claude-headless, openai/gpt-5.5-pro

<details>
<summary>Consensus Statistics</summary>

| Classification | Count |
|---|---|
| HIGH_CONSENSUS | 0 |
| DISPUTED | 4 |
| BLOCKER | 0 |
| LOW_VALUE | 9 |
| Unique perspectives | 13 |

</details>

---

I'll check whether the repository is available locally for verification, then produce the enriched Bridgebuilder review from the convergence findings.


<invoke name="Bash">
<invoke name="command">ls -la /run/user/1000/loa-claude-ws 2>/dev/null | head -40; echo "---"; find /run/user/1000/loa-claude-ws -maxdepth 3 -name 'session-exec.sh' 2>/dev/null | head</invoke>
<invoke name="description">Check whether PR source is available locally</invoke>
</invoke>
 total 0
drwx------  2 Bridgebuilder  0 Oct 24 09:34 Bridgebuilder 4096 Oct 24 09:34 .
drwxr-xr-x 14 Bridgebuilder  0 Oct 24 09:34 Bridgebuilder 4096 Deliberative Council 20:05 ..
---
