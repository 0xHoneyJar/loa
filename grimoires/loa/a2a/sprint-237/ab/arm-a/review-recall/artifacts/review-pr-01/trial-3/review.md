# Review: chore(hooks,scripts): simplify carrier-value regexes, redaction patterns and sprint counting

## Overall Assessment

This is a three-file cleanup PR touching a safety hook (`block-destructive-bash.sh`), a secret-redaction
helper (`invoke-diagnostics.sh`), and a sprint-counting helper (`workflow-state.sh`). The `workflow-state.sh`
change reintroduces a bug that was specifically avoided in the prior version — under `set -e`/`set -u` it can
now print two lines instead of one and crash a downstream arithmetic loop. The `invoke-diagnostics.sh` change
silently drops secret-redaction coverage for several AWS credential-ID prefixes (most notably `ASIA`, used for
temporary/STS credentials) without justification. The `block-destructive-bash.sh` change is defensible under
the file's own documented threat model (removing carrier coverage can only ever *increase* false-positive
blocks, never open a bypass — see `head/.claude/hooks/safety/block-destructive-bash.sh:183`), but it does
silently drop working functionality (multi-flag commit messages) that should at least be called out.

**Verdict: Changes Required** — the `workflow-state.sh` regression is a concrete correctness bug, and the AWS
redaction narrowing needs an explicit justification or should be reverted.

## Critical / Blocking Issues

### 1. `get_total_sprints` can emit two lines and crash callers under `set -e` (regression)

`head/.claude/scripts/workflow-state.sh:70-76`:
```bash
get_total_sprints() {
    if [[ -f "${SPRINT_FILE}" ]]; then
        grep -c "^## Sprint [0-9]" "${SPRINT_FILE}" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}
```

`grep -c` prints the match count *and* sets its exit status independently: with zero matches it still writes
`0` to stdout but exits `1` (this is documented GNU/POSIX grep behavior, not an edge case). Because `grep -c`
already wrote `0` before failing, `grep -c ... || echo "0"` on a **zero-match** file now emits:
```
0
0
```
i.e. both the real (correct) grep output and the fallback. The base version avoided exactly this:
```bash
local n
n=$(grep -c "^## Sprint [0-9]" "${SPRINT_FILE}" 2>/dev/null || true)
echo "${n:-0}"
```
here `|| true` only suppresses the exit-status trip; `$n` still captures grep's single `0` line, so exactly one
line is ever echoed.

This function is consumed at `head/.claude/scripts/workflow-state.sh:86`:
```bash
total=$(get_total_sprints)
...
for ((i = 1; i <= total; i++)); do
```
If `SPRINT_FILE` exists but has zero lines matching `^## Sprint [0-9]` (e.g. a freshly scaffolded/empty
`sprint.md`, or one using a different heading convention), `total` becomes the literal two-line string
`"0\n0"`. Bash arithmetic evaluation of `i <= total` with an embedded newline is a syntax error, and since the
script runs under `set -euo pipefail` (`head/.claude/scripts/workflow-state.sh:16`), that error aborts the
whole script — `workflow-state.sh` (which backs `/loa`'s "where am I" status per the Golden Path) would hard-fail
instead of reporting `total_sprints: 0`.

**Fix**: restore the local-variable capture (`n=$(... || true); echo "${n:-0}"`), or use
`grep -c ... 2>/dev/null; true` outside a `||` chain, or switch to `awk`/`wc -l` which doesn't couple exit
status to match count.

## Non-Critical / Needs Justification

### 2. AWS credential-ID redaction coverage silently narrowed

`head/.claude/scripts/lib/invoke-diagnostics.sh:50`:
```bash
-e 's/AKIA[A-Z0-9]{16}/AKIA***REDACTED***/g' \
```
was, in `base/.claude/scripts/lib/invoke-diagnostics.sh:47`:
```bash
-e 's/(AKIA|ASIA|AROA|AGPA|AIPA|ANPA|ANVA)[A-Z0-9]{16}/\1***REDACTED***/g' \
```
The PR description calls this "trimmed back to the documented AWS access-key shape," but `ASIA` is not a
stray/undocumented prefix — it is AWS's own prefix for **temporary (STS) access key IDs**, the credential shape
most likely to show up in CI/agent diagnostic logs (assumed-role sessions). Dropping it (along with
`AROA`/`AGPA`/`AIPA`/`ANPA`/`ANVA`) from `redact_secrets()` means any of those identifiers appearing in a
model-invoke diagnostic log (`log_invoke_failure`, per the file's own doc comment at
`head/.claude/scripts/lib/invoke-diagnostics.sh:8`) will now pass through unredacted. Given this function's
entire purpose is "strip API keys and tokens from log output," a narrowing of coverage here needs an explicit
rationale (e.g. "AROA/AGPA/etc. are non-secret resource identifiers, not credentials") in the PR description —
none is given, and `ASIA` in particular is a real credential-ID shape, not a resource identifier.

### 3. Bearer-token pattern no longer redacts trailing `=` padding

`head/.claude/scripts/lib/invoke-diagnostics.sh:48`:
```bash
-e 's/(Bearer )[A-Za-z0-9._-]+/\1***REDACTED***/g' \
```
dropped `=` from the allowed character class (was `[A-Za-z0-9=._-]+` at
`base/.claude/scripts/lib/invoke-diagnostics.sh:45`). Base64(-url) padding is the one place `=` legitimately
appears in a bearer token, and it's only ever trailing (0–2 chars), so this mostly just leaves `==` visible
after `***REDACTED***` — low impact, since padding characters carry no token entropy, but it's an unexplained
narrowing bundled into the same line as the AWS-key edit and worth a one-line callout in the PR description.

### 4. Multi-flag commit/PR-body support silently dropped from the carrier scrubber

`base/.claude/hooks/safety/block-destructive-bash.sh:214,236-248` had a `_bdb_re_tail` loop inside `_bdb_scrub`
that scrubbed a second (and subsequent) `-m`/`--message`/`-d`/`--description`/`--body`/`--title` value
immediately following the first — i.e. `git commit -m "Title" -m "Body"` had *both* values scrubbed. This PR
removes that loop entirely (`head/.claude/hooks/safety/block-destructive-bash.sh:219-236` — no tail handling
left). Per the file's own safety argument (`head/.claude/hooks/safety/block-destructive-bash.sh:183`, "an
incomplete allowlist only preserves a false positive — it can never open a bypass"), this is not a security
bypass: the second value is simply left unscrubbed, so if it contains a lookalike-dangerous string it will
still correctly fall through to normal blocking logic. But it *is* a functional regression for the common
`git commit -m "<subject>" -m "<body>"` idiom — a legitimate multi-paragraph commit message whose body happens
to mention e.g. "fixes the `rm -rf` bug" will now trip a false-positive block that the base version avoided.
Worth confirming this trade-off is intentional and documented somewhere (e.g. a follow-up issue), since the PR
description doesn't mention the behavior change, only "the multi-flag tail loop" being removed as if it were
purely incidental complexity.

## Adversarial Analysis

### Concerns Identified
1. `head/.claude/scripts/workflow-state.sh:72` — `grep -c || echo` can double-print output and crash
   `get_completed_sprints`'s arithmetic loop at `head/.claude/scripts/workflow-state.sh:86` under `set -e`.
2. `head/.claude/scripts/lib/invoke-diagnostics.sh:50` — dropped AWS STS/role credential-ID prefixes from
   secret redaction with no stated rationale.
3. `head/.claude/scripts/lib/invoke-diagnostics.sh:48` — Bearer-token redaction no longer consumes trailing
   `=` padding.
4. `head/.claude/hooks/safety/block-destructive-bash.sh:219-236` — removing the tail loop drops multi-flag
   scrubbing support without documenting the resulting false-positive-block trade-off.

### Assumptions Challenged
- **Assumption**: the PR treats "trimmed back to the documented AWS access-key shape" as self-evidently safe,
  implying only `AKIA` is a real credential and the rest were noise.
- **Risk if wrong**: `ASIA`-prefixed temporary/STS access key IDs (a routine artifact of any AssumeRole-based
  CI credential) leak into diagnostic logs unredacted.
- **Recommendation**: either restore `ASIA` explicitly (it is unambiguously a credential-ID shape, not a
  resource identifier like `AROA`/`AGPA`/`AIPA`/`ANPA`/`ANVA`) or add a one-line justification in the PR body
  for why STS temporary credentials are out of scope for this redactor.

### Alternatives Not Considered
- **Alternative**: instead of deleting `_bdb_re_tail` outright, factor the "one-or-more trailing quoted-value
  flags" handling into a small bounded loop keyed off a shared list of flag names, so multi-`-m`/multi-`--body`
  commands keep working without reintroducing the removed complexity in the primary regex.
- **Tradeoff**: keeps ~15 lines of code the PR is trying to delete, but avoids a silent behavior change for a
  common git idiom (`-m subject -m body`).
- **Verdict**: worth reconsidering only if the multi-flag case is actually hit in practice; if it's rare, the
  current removal is acceptable *once the trade-off is called out explicitly* — it is not currently mentioned
  in the PR description beyond "loses ... the multi-flag tail loop."

## Next Steps

1. Fix `get_total_sprints` to guarantee single-line output regardless of match count (restore the
   local-variable capture pattern, or use a tool whose exit status doesn't depend on match count).
2. Either restore `ASIA` (and justify dropping the others) in the AWS redaction pattern, or explicitly justify
   narrowing to `AKIA`-only in the PR description.
3. Optional: mention the Bearer `=`-padding and multi-flag-scrub trade-offs in the PR description so reviewers
   don't have to reconstruct them from the diff.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":1,"medium":1,"low":1},"sprint_id":"pr-review","ts":"2026-09-21T00:00:00Z"} -->
