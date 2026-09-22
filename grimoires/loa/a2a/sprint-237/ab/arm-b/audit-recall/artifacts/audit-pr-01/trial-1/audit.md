# Security Audit — chore(hooks,scripts): simplify carrier-value regexes, redaction patterns and sprint counting

**Scope**: `head.diff` (3 files) — `.claude/hooks/safety/block-destructive-bash.sh`, `.claude/scripts/lib/invoke-diagnostics.sh`, `.claude/scripts/workflow-state.sh`. No sprint plan, beads DB, or `grimoires/loa/a2a/` present; audited directly against `base/` → `head/` per AUDIT-INSTRUCTIONS.md. Only the three touched files were supplied — external call sites of `redact_secrets`/`get_total_sprints` could not be enumerated; noted as a scope limit below, not treated as evidence of absence.

## Findings

### HIGH-1 — AWS STS/IAM secret-redaction coverage silently dropped

`head/.claude/scripts/lib/invoke-diagnostics.sh:50`

```sed
-e 's/AKIA[A-Z0-9]{16}/AKIA***REDACTED***/g' \
```

Base (`base/.claude/scripts/lib/invoke-diagnostics.sh:37`) redacted seven official AWS ID-type prefixes:

```sed
-e 's/(AKIA|ASIA|AROA|AGPA|AIPA|ANPA|ANVA)[A-Z0-9]{16}/\1***REDACTED***/g' \
```

`redact_secrets()` is documented (`invoke-diagnostics.sh:8`) as the mechanism that "strip[s] API keys and tokens" from the model-invoke diagnostic log before it is written to disk (`setup_invoke_log`, mode 600, but retained on failure per `log_invoke_failure`/`cleanup_invoke_log` — i.e. exactly the failure path most likely to contain a raw credential from a failing API call). Of the seven prefixes removed, `ASIA` is the most consequential: it identifies **AWS STS temporary session credentials** — the exact credential shape produced by GitHub-OIDC-to-AWS federation, assumed-role sessions, and most modern CI pipelines, and one of the highest-value secrets to leak because it is immediately usable with no further exchange. `AROA`/`AGPA`/`AIPA`/`ANPA`/`ANVA` (role/group/instance-profile/policy IDs) are also now unredacted. The PR description's claim that the pattern is being "trimmed back to the documented AWS access-key shape" is incorrect — all seven prefixes are AWS's own documented [resource-identifier prefixes](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_identifiers.html), not an undocumented superset.

- **Failure scenario**: a model-invoke call fails after AWS credentials (e.g. an `ASIA...` STS token embedded in a header or env dump) reach stderr; `log_invoke_failure` preserves the log file for debugging (`invoke-diagnostics.sh:85`, "On failure, the log is preserved for debugging") and `redact_secrets` (if piped over the content, per its stated purpose) no longer masks the `ASIA...` value, leaving a live, immediately-usable temporary AWS credential in a world-readable-by-owner (mode 600, but unencrypted, retained) diagnostic file instead of a redacted placeholder.
- **Standard**: [CWE-532: Insertion of Sensitive Information into Log File](https://cwe.mitre.org/data/definitions/532.html); [CWE-200: Exposure of Sensitive Information to an Unauthorized Actor](https://cwe.mitre.org/data/definitions/200.html).
- **Fix**: restore the full alternation `(AKIA|ASIA|AROA|AGPA|AIPA|ANPA|ANVA)[A-Z0-9]{16}` (or at minimum re-add `ASIA`, the temporary-credential prefix).

### MEDIUM-1 — Bearer-token redaction now stops at embedded `=`, leaking the remainder

`head/.claude/scripts/lib/invoke-diagnostics.sh:48`

```sed
-e 's/(Bearer )[A-Za-z0-9._-]+/\1***REDACTED***/g' \
```

Base (`base/.claude/scripts/lib/invoke-diagnostics.sh:35`) allowed `=` inside the matched token:

```sed
-e 's/(Bearer )[A-Za-z0-9=._-]+/\1***REDACTED***/g' \
```

`sed -E` greedily matches the character class and stops at the first character outside it. Any `Bearer <token>` value that contains a `=` — standard base64 padding at minimum, and not guaranteed to be padding-only for every non-JWT bearer scheme this hook may see (only `eyJ...` JWTs get a dedicated, more specific pattern on `invoke-diagnostics.sh:51`) — now redacts only the prefix up to the first `=` and leaves everything from that `=` onward, verbatim, in the diagnostic log.

- **Failure scenario**: `Authorization: Bearer abcXYZ123==` logged by a failing invoke call is now written as `Authorization: Bearer ***REDACTED***==` if `=` sits at the very end (low-impact — only padding leaks), but a token where `=` is not confined to the trailing edge is truncated mid-secret and everything after the first `=` survives redaction in cleartext.
- **Standard**: [CWE-532](https://cwe.mitre.org/data/definitions/532.html).
- **Fix**: restore `=` in the character class: `[A-Za-z0-9=._-]+`.

### LOW-1 — Carrier-value quote scrub in the destructive-command fence no longer redacts multi-value commits per-value

`head/.claude/hooks/safety/block-destructive-bash.sh:210-236` (compare `base/.claude/hooks/safety/block-destructive-bash.sh:210-251`)

The base version excluded quote characters from the carrier-prefix classes (`[^;&|'\"]*` — `base/.claude/hooks/safety/block-destructive-bash.sh:210-212`) and paired the main regex with a `_bdb_re_tail` loop (`base:214`, consumed inside `_bdb_scrub` at `base:236-248`) that re-applied the same flag/value/content-gate logic to every subsequent `-m`/`-d`/`--body`/`--title` occurrence in the same shell segment, one at a time.

`head` drops both: the prefix class is now `[^;&|]*` (quotes permitted) and the tail loop is deleted entirely (`head:219-236`). Because POSIX ERE matching is leftmost-longest, and the prefix between `commit`/`create` and the target flag can now itself contain quoted text, `_bdb_re_git`/`_bdb_re_brbd`/`_bdb_re_gh` will match through an *earlier* quoted value straight to the **last** occurrence of the flag in the segment (e.g. `git commit -m "first" -m "second"` — the whole span from `git` through `"second"` becomes one match, with `"second"` as the only value evaluated by the `$(`/backtick content gate). The text spanning any earlier `-m`/`-d`/`--body` value (`po` in `_bdb_scrub`, `head:230`) is appended to the scrub output **unmodified** — i.e. never passed through the content gate at all, and never scrubbed even if benign.

This is fail-safe with respect to the fence's own bypass model (nothing is hidden that wasn't already visible — an unredacted earlier value can only cause the fence to over-block, never to miss a real destructive pattern, matching the file's own "an incomplete allowlist can only preserve a false positive" invariant, `head:183-184`), so it is not a bypass. It is, however, an availability/quality regression: any multi-paragraph `git commit -m "..." -m "..."`, multi-flag `br create ... -d "..." ... -d "..."`, or `gh pr create --title "..." --body "..."` whose non-last value happens to contain a destructive-looking substring (e.g. a commit body quoting `rm -rf /` or `DROP TABLE` for documentation purposes) will now be incorrectly blocked, where the base implementation would have redacted it. No comment in the surrounding design rationale (`head:148-193`) was updated to describe the new single-shot-last-value behavior.

- **Failure scenario**: `git commit -m "wip" -m "note: previous script did rm -rf /tmp/cache, do not repeat"` gets its second `-m` value swallowed unredacted into the fence's match, and the literal text `rm -rf /tmp/cache` — despite being commit-message prose, not a command — can trigger a downstream destructive-pattern block (denial of a legitimate commit), where before the tail loop would have scrubbed it.
- **Standard**: not a CWE-classed vulnerability (no confidentiality/integrity/availability-of-attacker-controlled-resource impact) — flagged as a correctness/availability regression in security-relevant code.
- **Fix**: either restore the quote-exclusion in the prefix classes and the `_bdb_re_tail` loop, or explicitly document that only the last quoted value per segment is content-gated and accept the narrower false-positive envelope.

### LOW-2 — `get_total_sprints` can emit two lines instead of one when the sprint count is zero

`head/.claude/scripts/workflow-state.sh:72`

```bash
grep -c "^## Sprint [0-9]" "${SPRINT_FILE}" 2>/dev/null || echo "0"
```

`grep -c` prints the match count to stdout *unconditionally*, but exits `1` when the count is `0` (no lines selected). When `SPRINT_FILE` contains zero `## Sprint N` headers, this line prints `0` from `grep -c` itself, and then — because grep's exit status is `1` — the `||` branch fires too, printing a second `0`. `get_total_sprints` therefore returns the two-line string `"0\n0"` instead of `"0"` in the empty-sprint-plan case. The base version (`base/.claude/scripts/workflow-state.sh:71-73`) captured grep's stdout into a variable with `|| true` specifically to swallow grep's exit code without discarding or duplicating its (already-correct) output — this is the exact failure mode being reintroduced.

- **Failure scenario**: `get_completed_sprints()` (`head/.claude/scripts/workflow-state.sh:83-94`) calls `total=$(get_total_sprints)` and then uses `total` as a C-style-for-loop bound: `for ((i = 1; i <= total; i++))`. With `total="0\n0"`, bash arithmetic evaluation of a multi-line operand is a syntax error, which — under any caller running with `set -e`/`errexit` — aborts the script; under `set +e` it silently misreports sprint progress to any consumer of `get_completed_sprints`/`get_total_sprints` JSON output.
- **Standard**: correctness bug, not a CWE-classed security defect; flagged because it lives in `.claude/scripts` state-tracking code that other automation (golden-path progress, run-mode resume) may depend on for control flow.
- **Fix**: revert to capturing output first — `local n; n=$(grep -c "..." "${SPRINT_FILE}" 2>/dev/null || true); echo "${n:-0}"` — or use `grep -c ... | tail -1` / `grep -c ... ; :` idioms that don't re-invoke a value-producing command on the `||` branch.

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 1 |
| Low | 2 |

## Verdict

One-way rule: critical + high > 0 ⇒ **CHANGES_REQUIRED**.

HIGH-1 (dropped AWS STS/IAM credential-prefix redaction) and MEDIUM-1 (Bearer-token redaction truncated at embedded `=`) both regress a security-purpose function (`redact_secrets`) in a way that can leave live credentials in cleartext diagnostic logs. Recommend restoring the full AKIA/ASIA/AROA/AGPA/AIPA/ANPA/ANVA alternation and the `=` character in the Bearer class before merge; LOW-1 and LOW-2 should be fixed but do not block on their own.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":1,"low":2},"ts":"2026-09-22T00:00:00Z"} -->
