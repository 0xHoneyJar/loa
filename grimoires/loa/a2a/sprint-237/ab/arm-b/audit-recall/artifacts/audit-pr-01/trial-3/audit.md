# Security Audit — chore(hooks,scripts): simplify carrier-value regexes, redaction patterns and sprint counting

**Scope**: `head.diff` touching three System-Zone shell helpers:
`.claude/hooks/safety/block-destructive-bash.sh`, `.claude/scripts/lib/invoke-diagnostics.sh`,
`.claude/scripts/workflow-state.sh`. No sprint plan / beads / a2a context exists for this audit; PR
files are the entire input.

## Findings

### 1. [HIGH] Secret-redaction regex narrowed: AWS temporary/role credential prefixes no longer redacted

`head/.claude/scripts/lib/invoke-diagnostics.sh:50`:

```sh
-e 's/AKIA[A-Z0-9]{16}/AKIA***REDACTED***/g' \
```

The base version (`base/.claude/scripts/lib/invoke-diagnostics.sh:39`) redacted six AWS credential-ID
prefixes:

```sh
-e 's/(AKIA|ASIA|AROA|AGPA|AIPA|ANPA|ANVA)[A-Z0-9]{16}/\1***REDACTED***/g' \
```

`redact_secrets()` is the sanitization gate applied to model-invoke diagnostic output before it is
surfaced (per the file's own header, `head/.claude/scripts/lib/invoke-diagnostics.sh:6-8`: "strip API
keys and tokens from log output"). Dropping `ASIA` (STS temporary access keys — directly usable,
short-lived but live AWS credentials), `AROA` (role IDs), `AGPA` (group IDs), `AIPA`/`ANPA`/`ANVA`
means any of these that appear in a captured stderr/stdout stream (e.g. an AWS SDK error dump, an
env-var leak in a stack trace) will now pass through `redact_secrets` completely unredacted.

**Failure scenario**: A model-invoke call fails while `AWS_SESSION_TOKEN`/`AWS_ACCESS_KEY_ID`
(an `ASIA…` temporary key) is present in the process environment and gets echoed into the invoke
log by a library error message. `log_invoke_failure` runs the log through `redact_secrets`; the
`ASIA` key is no longer matched by any pattern and is printed verbatim in the surfaced diagnostic.
CWE-532 (Insertion of Sensitive Information into Log File), CWE-312 (Cleartext Storage of Sensitive
Information). Reference: https://cwe.mitre.org/data/definitions/532.html

The PR description ("trimmed back to the documented AWS access-key shape") does not describe this as
a security-negative change, but the removed prefixes were live redaction targets in `base`, not dead
code — this is a coverage regression, not a cleanup of unused patterns.

### 2. [HIGH] Bearer-token redaction regex narrowed: tokens containing `=` are only partially redacted

`head/.claude/scripts/lib/invoke-diagnostics.sh:48`:

```sh
-e 's/(Bearer )[A-Za-z0-9._-]+/\1***REDACTED***/g' \
```

vs. `base/.claude/scripts/lib/invoke-diagnostics.sh:37`:

```sh
-e 's/(Bearer )[A-Za-z0-9=._-]+/\1***REDACTED***/g' \
```

`=` was removed from the allowed character class. Because `sed`'s greedy match simply stops at the
first character outside the class, this doesn't just fail to redact `=`-containing tokens — it
truncates the redaction and leaves the remainder of the token in cleartext immediately after the
`***REDACTED***` marker.

**Failure scenario**: A log line reads `Authorization: Bearer abC123=xyzSECRETsuffix` (base64-padded
or otherwise `=`-bearing bearer token, common for standard-base64 OAuth tokens). The new regex matches
only `abC123` and replaces it, producing `Bearer ***REDACTED***=xyzSECRETsuffix` — the tail of the
real token (`xyzSECRETsuffix`) is emitted in cleartext in the diagnostic output. This is strictly worse
than "not redacting" because it gives a false impression that the token was fully scrubbed. CWE-532.

### 3. [MEDIUM] `block-destructive-bash.sh` carrier-value scrub loses multi-flag coverage (availability/robustness regression in a security fence)

`head/.claude/hooks/safety/block-destructive-bash.sh:210-212` widen the carrier prefix classes from
`[^;&|'"]*` (base, `base/.claude/hooks/safety/block-destructive-bash.sh:210-212`) to `[^;&|]*`,
allowing the prefix between `git`/`gh`/`br`/`bd` and the target flag to cross an earlier quoted
string. Combined with deleting `_bdb_re_tail` and the tail `while` loop that used to run after each
primary match (`base/.claude/hooks/safety/block-destructive-bash.sh:216,247-259`, fully removed in
head), a command carrying **more than one** quoted-value flag in the same shell segment — e.g. a
multi-paragraph `git commit -m "para1" -m "para2"`, or `gh pr create --title "T" --body "B"` — now has
only the *last* flag/value pair scrubbed by `_bdb_scrub` (`head/.claude/hooks/safety/block-destructive-bash.sh:219-235`);
earlier quoted values in the same segment are left in the scrub-copy unredacted.

I traced whether this reopens the "quote-blindness" bypass the surrounding comments
(`head/.claude/hooks/safety/block-destructive-bash.sh:155-186`) describe at length: it does not,
because `_bdb_scrub` only ever blanks the *trailing quoted capture group* (`val`, quotes included) and
always preserves everything else in the match (`po`) verbatim — so no unquoted, real destructive text
can be swallowed into the redacted span, regardless of how far the prefix class reaches. The
practical effect is the opposite of a bypass: earlier legitimate quoted content (e.g. `para1` of a
multi-paragraph commit message) stays exposed to the destructive-pattern checks below and can now
trigger a **false-positive block** it previously would not have (base's tail loop scrubbed it). Given
this file's stated purpose and its own documentation trail (`cycle-120 C-D3a`, `bd-bdb-quote-blindness-pt1g`)
around exactly this scrub behavior, removing tested coverage without any accompanying rationale in
the diff (no comment update explains why multi-flag carriers are no longer supported, nor whether this
was intentionally scoped out) is a process/quality concern for a fence explicitly documented as
security-relevant, even though I did not find an exploitable bypass. Recommend restoring the tail-loop
behavior or explicitly documenting the newly-accepted false-positive class the way the rest of the file
documents its accepted bypass classes (`head/.claude/hooks/safety/block-destructive-bash.sh:33-38`).
CWE-1023 (Incomplete Comparison with Missing Factors) as the closest fit for the regex-coverage gap;
no CWE claimed for "vulnerability" since none was confirmed.

### 4. [MEDIUM] `get_total_sprints` emits two lines instead of one when the sprint file has zero matches, corrupting downstream arithmetic

`head/.claude/scripts/workflow-state.sh:70-76`:

```sh
get_total_sprints() {
    if [[ -f "${SPRINT_FILE}" ]]; then
        grep -c "^## Sprint [0-9]" "${SPRINT_FILE}" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}
```

`grep -c` prints the match count to stdout regardless of outcome, but exits status **1** when the
count is zero (GNU/BSD grep: "Exit status is 0 if selected lines are found, 1 otherwise"). When
`SPRINT_FILE` exists but contains no `^## Sprint [0-9]` line, `grep -c` already printed `0` to stdout
before returning exit 1, so `|| echo "0"` fires *in addition*, producing two lines of output (`"0\n0"`)
from a single call. The base version (`base/.claude/scripts/workflow-state.sh:70-74`) avoided this by
capturing into a variable first and using `${n:-0}` on the string, always yielding exactly one line.

**Failure scenario**: `determine_state()` (`head/.claude/scripts/workflow-state.sh:145-158`) calls
`total_sprints=$(get_total_sprints)` and then does `[[ "${completed_sprints}" -ge "${total_sprints}" ]]`
and `for i in $(seq 1 "${total_sprints}")`. With `total_sprints` bound to the two-line string `"0\n0"`,
both the `-ge` integer test and `seq 1 "0\n0"` fail with a shell integer-expression error rather than
behaving as "zero sprints" — corrupting the golden-path phase/gate state calculation the moment a
sprint plan file exists with no sprint headers yet (a normal transient state right after
`/sprint-plan` scaffolds the file before the first `## Sprint 1` section is written). Same call sites
recur at `head/.claude/scripts/workflow-state.sh:86` and `:147,369`. CWE-393 (Detection of Error
Condition Without Action) / CWE-670 (Always-Incorrect Control Flow Implementation).
Reference: https://cwe.mitre.org/data/definitions/393.html

## Observations

- The PR is a pure System-Zone (`.claude/`) shell simplification; no App-Zone code is touched. Given
  the CLAUDE.loa.md three-zone model, this is process-appropriate content for these files, but two of
  the three files (`block-destructive-bash.sh`, `invoke-diagnostics.sh`) are explicitly security
  controls (destructive-command fence, secret redaction), so "simplify" changes to them carry higher
  scrutiny than ordinary refactors — confirmed warranted here (findings 1–3).

## Phase 2.5: Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 2 |
| Low | 0 |

## Verdict

CHANGES_REQUIRED — findings 1 and 2 restore the AWS/Bearer redaction coverage present in `base`
before this hook's output can be trusted for anything that touches `redact_secrets()`; finding 3
should either restore multi-flag scrub coverage or be explicitly documented as an accepted
false-positive tradeoff; finding 4 is a straightforward one-line fix (`n=$(...); echo "${n:-0}"`,
matching `base`) needed before merge.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":2,"low":0},"ts":"2026-09-22T00:00:00Z"} -->
