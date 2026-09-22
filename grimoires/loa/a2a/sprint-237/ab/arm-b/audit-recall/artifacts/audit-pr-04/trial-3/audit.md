# Security Audit: chore(cheval,flatline,status) — shorten env scrub, temp-file handling, flag parsing

**Scope:** `head.diff` (3 files) — `.claude/adapters/loa_cheval/providers/base.py`, `.claude/scripts/flatline-orchestrator.sh`, `.claude/scripts/loa-status.sh`. No sprint plan/beads/a2a artifacts present; audited directly against `base/` → `head/`.

## Findings

### 1. CRITICAL — Headless-adapter env scrub drops the auth-mode-selector vars, reopening issues #879/#880

`head/.claude/adapters/loa_cheval/providers/base.py:472-476` (`_HEADLESS_STRIPPED_AUTH_VARS`) now reads:

```python
_HEADLESS_STRIPPED_AUTH_VARS: tuple = (
    "ANTHROPIC_API_KEY",
    "OPENAI_API_KEY",
    "GOOGLE_API_KEY",
    "GEMINI_API_KEY",
    "GOOGLE_APPLICATION_CREDENTIALS",
)
```

The diff removes `GOOGLE_GENAI_USE_VERTEXAI`, `GOOGLE_GENAI_USE_GCA`, `GOOGLE_GEMINI_BASE_URL`, and `GEMINI_CLI_USE_COMPUTE_ADC` from this tuple. `build_headless_subprocess_env()` (`head/.claude/adapters/loa_cheval/providers/base.py:481-503`) still only strips whatever is left in the tuple:

```python
for var in _HEADLESS_STRIPPED_AUTH_VARS:
    base.pop(var, None)
```

The surrounding comment block (`head/.claude/adapters/loa_cheval/providers/base.py:465-471`) is unchanged and still explains *why* this matters: "if any of these vars are exported in the parent process the CLI falls back to API mode — defeating the headless adapter's purpose." The four removed vars are exactly the Gemini CLI auth-mode selectors that force Vertex AI / Google Cloud Auth / a custom Gemini endpoint / Compute-ADC routing **independent of whether an API key is present**. If the parent process (or its ambient environment, e.g. a GCP Compute Engine / Cloud Run host with default service-account credentials) has `GOOGLE_GENAI_USE_VERTEXAI=1` or `GEMINI_CLI_USE_COMPUTE_ADC=1` set, that setting now survives into the headless subprocess untouched, and the Gemini CLI will route through Vertex AI/ADC instead of the intended OAuth-subscription path — even with zero API keys in scope. `GOOGLE_GEMINI_BASE_URL` surviving is worse: it lets an ambient env var silently redirect the "headless" subprocess's Gemini traffic to an arbitrary endpoint.

This is not a new vulnerability introduced from scratch — the pre-image (`base/.claude/adapters/loa_cheval/providers/base.py:475-478`) explicitly stripped these same four vars, and the removed docstring text (`base/.claude/adapters/loa_cheval/providers/base.py:487-491`) says so in as many words: "remove every entry in `_HEADLESS_STRIPPED_AUTH_VARS` — both the credential sub-class … and the auth-mode-selector sub-class (e.g., `GOOGLE_GENAI_USE_VERTEXAI`)." The PR silently reverts a fix that was landed for tracked issues #879/#880 (per the still-present comment at `head/.claude/adapters/loa_cheval/providers/base.py:463`), without updating the issue references, without a compensating control, and without the PR description mentioning the behavior change (it's framed only as "shorten the headless env scrub"). `LOA_HEADLESS_KEEP_API_KEY=1` also now preserves a narrower set of vars than the docstring at `head/.claude/adapters/loa_cheval/providers/base.py:485-486` implies ("preserves the auth vars verbatim") — it's verbatim preservation of a set that no longer contains the mode selectors, so the operator opt-in and the default-strip path silently changed together.

Reference: CWE-668 (Exposure of Resource to Wrong Sphere) — https://cwe.mitre.org/data/definitions/668.html; also relevant CWE-923 (Improper Restriction of Communication Channel to Intended Endpoint) for the `GOOGLE_GEMINI_BASE_URL` case — https://cwe.mitre.org/data/definitions/923.html.

**Remediation:** restore the four auth-mode-selector vars to `_HEADLESS_STRIPPED_AUTH_VARS`, or, if the intent really is to narrow scope to credentials only, update the surrounding comment (`head/.claude/adapters/loa_cheval/providers/base.py:463-471`) to stop citing the mode-selector rationale, re-open/reference #879/#880 in the PR description, and get explicit sign-off that the auth-mode-selector bypass is an accepted risk.

### 2. MEDIUM — `mktemp` failure guards removed from flatline-orchestrator.sh under `set -euo pipefail`

`head/.claude/scripts/flatline-orchestrator.sh:47` sets `set -euo pipefail`. Two call sites lost their explicit `mktemp` failure handling:

- `head/.claude/scripts/flatline-orchestrator.sh:577`: `tmp=$(mktemp "${TEMP_DIR:-/tmp}/vq-input.XXXXXX.json")` — previously (`base/.claude/scripts/flatline-orchestrator.sh:577-580`) a failed `mktemp` logged a warning and `continue`d to the next input file; now a single `mktemp` failure (e.g. `/tmp` or `$TEMP_DIR` full, unwritable, or a hardened sandbox disallowing predictable-prefix temp creation) trips `set -e` and kills the *entire* orchestrator run instead of degrading gracefully by skipping one voice's verdict-quality envelope.
- `head/.claude/scripts/flatline-orchestrator.sh:2282`: `arbiter_prompt_file=$(mktemp)` — previously (`base/.claude/scripts/flatline-orchestrator.sh:2282-2285`) a failed `mktemp` logged an error and `continue`d, skipping just the arbiter step for that phase; now the same failure aborts the whole flatline run.

Functionally this converts a per-item degrade-gracefully path into a whole-process abort on a condition (temp-dir exhaustion) that's plausible in CI/containers with small `/tmp` tmpfs allocations, so it's a robustness/availability regression on the review pipeline rather than a directly exploitable vulnerability. Given flatline is a security-relevant quality gate (`auditing-security` gate enforcement depends on it completing), an attacker who can exhaust `/tmp` on the runner (e.g. a prior stage that fills disk) can now use it to fail the whole audit/review cycle rather than just degrade one envelope.

Reference: CWE-703 (Improper Check for Unusual or Exceptional Conditions) — https://cwe.mitre.org/data/definitions/703.html.

**Remediation:** restore the `if ! tmp=$(mktemp …); then log …; continue; fi` guards at both sites (or wrap in `set +e`/explicit `${?}` check if the surrounding function shouldn't hard-fail the whole script).

### 3. LOW — `loa-status.sh` always emits ANSI color codes, ignoring `NO_COLOR` and non-TTY output

`head/.claude/scripts/loa-status.sh:29-35` unconditionally sets `RED`/`GREEN`/`YELLOW`/`CYAN`/`BOLD`/`NC` to their escape-sequence values. The removed guard (`base/.claude/scripts/loa-status.sh:29-41`) checked `[[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]` and blanked all six vars otherwise. Downstream consumers that capture `loa-status.sh` stdout for machine parsing (log files, piping into `jq`/other tooling, `NO_COLOR`-respecting terminals/CI logs) will now receive raw ANSI escapes mixed into otherwise-plain-text output. This is a correctness/UX regression, not attacker-controlled — no injection vector, since the color values are fixed literals, not built from input — but it can corrupt scraped output or accessibility tooling that used `NO_COLOR` to get clean text.

**Remediation:** restore the `NO_COLOR`/`-t 1` conditional.

### 4. LOW — Unknown CLI flags to `loa-status.sh` are now silently accepted instead of erroring

`head/.claude/scripts/loa-status.sh:62-65`, the `*)` case now only does `ECONOMY_ARGS+=("$arg")` with no error path. The removed logic (`base/.claude/scripts/loa-status.sh:74-84`, including the `UNKNOWN_ARGS` array and the `dx_unknown_flag`/usage-and-`exit 2` fallback) meant an unrecognized flag in non-`--economy` mode caused a hard usage error. Now such a flag is silently swallowed (stored in `ECONOMY_ARGS`, which is discarded unless `--economy` mode is later entered), so a typo'd flag (e.g. `--jso`) produces no diagnostic and status output proceeds as if nothing was wrong. Low severity — this is a status/reporting script, not a trust boundary, and the failure mode is "no error printed," not privilege or data exposure — but it removes an existing input-validation control at a CLI entry point with no replacement.

**Remediation:** restore the `UNKNOWN_ARGS` tracking and the usage/exit-2 path for non-economy-mode unknown flags.

## Coverage / Scope Notes

- Reviewed all three files in full context (not just diff hunks) in both `base/` and `head/` to confirm no compensating control exists elsewhere in the touched files for Finding 1 (confirmed: none of the four removed var names appear anywhere else under `head/`).
- No sprint plan, beads issues, or prior audit artifacts were available for cross-reference per the task framing; Finding 1's issue references (#879/#880) are taken directly from source comments still present in `head/`, not independently verified against an issue tracker.
- No blockchain/crypto-specific surface in this diff.

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 1 |
| High | 0 |
| Medium | 1 |
| Low | 2 |

## Verdict

**CHANGES_REQUIRED** — Finding 1 silently reopens a previously-fixed credential/auth-routing isolation gap in the headless adapter (tracked issues #879/#880) and must be reverted or explicitly re-justified before merge. Finding 2 should be fixed in the same pass since it's a direct regression in the same diff.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":0,"medium":1,"low":2},"ts":"2026-09-22T00:00:00Z"} -->
