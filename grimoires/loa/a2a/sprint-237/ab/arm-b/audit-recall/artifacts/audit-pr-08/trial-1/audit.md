# Security Audit: chore(ledger,tools,cheval) — lighter ledger content check, simpler heredoc skipping, fewer except clauses

**Scope:** `head.diff` against `base/` for three files:
- `.claude/scripts/ledger-lib.sh`
- `tools/check-no-swallowed-jq.sh`
- `.claude/adapters/loa_cheval/providers/agy_headless_adapter.py`

No sprint plan, beads database, or `grimoires/loa/a2a/` directory exists in this workspace; this audit is grounded entirely in `head.diff` and the `base/`/`head/` file contents provided.

**Framing:** the PR title calls this a `chore` — three unrelated simplifications. All three touched files are exactly the kind of safety/guard code that earns its complexity from a documented prior incident (the ledger truncation bug 20260808-a008c6, the KF-004/KF-015 swallowed-verdict class, and this same adapter's own "walkable vs. hard-crash" design invariant). Each simplification removes a piece of that prior hardening rather than merely tidying style.

---

## Findings

### HIGH — `_write_ledger` content guard downgraded from "must be a JSON object" to "must be any valid JSON", reopening a variant of the truncation bug the guard exists to prevent

`head/.claude/scripts/ledger-lib.sh:157`

```bash
if [[ -z "$content" ]] || ! echo "$content" | jq empty 2>/dev/null; then
    echo "ERROR: refusing to write empty or unparseable ledger content" >&2
    return $LEDGER_ERROR
fi
```

The `base/` version additionally required the parsed content to be a single JSON *object*:

```bash
if [[ -z "$content" ]] || \
   ! printf '%s' "$content" | jq -es 'length == 1 and (.[0] | type == "object")' >/dev/null 2>&1; then
```

`jq empty` only validates that the input is syntactically valid JSON — it accepts `null`, numbers, strings, booleans, and arrays, not just objects. The comment retained directly above the new check (`head/.claude/scripts/ledger-lib.sh:152-156`) explains exactly why the object-type check existed: an earlier incident (bug 20260808-a008c6) let malformed content slip through the `last_updated` jq stamp and silently truncate the ledger to near-nothing while every caller reported success.

That mechanism is reachable again through a different input shape. `.last_updated = $ts` at `head/.claude/scripts/ledger-lib.sh:179` is applied to whatever `$content` is. For a non-null non-object (array/number/string/bool) jq raises a type error (`Cannot index array with string "last_updated"`), `updated_content` comes back empty, and the `-z "$updated_content"` guard at line 180 aborts the write safely — so most non-object shapes are still caught, just one level later than before.

`null` is the exception jq treats specially: object-key assignment on `null` **auto-vivifies** an object instead of erroring —

```
$ echo null | jq '.last_updated = "x"'
{
  "last_updated": "x"
}
```

If `$content` is ever the literal 4-byte string `null` (a legitimate, `jq empty`-valid JSON document — e.g. a jq filter earlier in the pipeline that selects nothing and defaults to `null`, or a caller accidentally capturing jq's own `null` stdout), the new guard now waves it through, and `_write_ledger` proceeds to atomically replace the entire ledger file with `{"last_updated": "<timestamp>"}` — discarding `version`, `next_sprint_number`, `active_cycle`, and every `cycles`/`sprints` entry. This is the same failure class (all-green callers, catastrophic silent data loss) the object-type check and the `20260808-a008c6` guard comment were written to close, just entered via `null` instead of an empty string.

**Failure scenario:** any `_write_ledger` caller (e.g. a future edit to `create_cycle`, `update_cycle_field`, `add_sprint`, `update_sprint_status`, `archive_cycle`) that can produce a bare jq `null` for `$content` — for instance a `select()` filter that matches nothing and is piped through `// null`, or a copy-paste of the `resolve_sprint`-style `... || echo "UNRESOLVED"` fallback pattern applied to ledger content instead of a sprint id — will now pass the guard and truncate the on-disk ledger (`grimoires/loa/ledger.json`) to a single field, with the caller believing the write succeeded (`_write_ledger` returns `$LEDGER_OK` since `mv` itself succeeds).

**Remediation:** restore the object-type check (`jq -es 'length == 1 and (.[0] | type == "object")'`, or equivalently `jq -e 'type == "object"'`), not just JSON-well-formedness. If `echo`/`printf` behavior was the motivation for touching this line, that can be fixed independently of loosening the type constraint.

Standard reference: [CWE-20: Improper Input Validation](https://cwe.mitre.org/data/definitions/20.html) (weakened validation of a value flowing into a destructive write); [CWE-1287: Improper Validation of Specified Type of Input](https://cwe.mitre.org/data/definitions/1287.html).

---

### MEDIUM — security tripwire scanner now unconditionally skips *all* heredoc bodies, including heredocs that are executed, on the exact gate-critical files it exists to protect

`head/tools/check-no-swallowed-jq.sh:138-146` (and the removed exec-classification helpers that used to feed it)

```awk
in_heredoc {
    if ($0 == hd_term) { in_heredoc = 0; next }
    if (hd_dash) {
        no_tabs = $0
        gsub(/^\t+/, "", no_tabs)
        if (no_tabs == hd_term) { in_heredoc = 0; next }
    }
    next
}
```

The `base/` version distinguished two kinds of heredoc: inert fixture/documentation text (e.g. planted "bad" examples inside `.bats` test files), which was skipped, and heredocs whose body is actually **executed** — piped to `sh`/`bash`/`python`/etc., or fed to a known interpreter command — which continued to be scanned line-by-line for the swallowed-jq shape (`hd_exec`, driven by `_hd_command()`/`_start_heredoc()` in `base/tools/check-no-swallowed-jq.sh:123-165`). That distinction, and the corresponding scan-inside-executed-heredocs behavior, has been deleted entirely; every heredoc body is now unconditionally skipped regardless of whether its content is documentation or runnable code.

This tool's stated job (`head/tools/check-no-swallowed-jq.sh:5-17`) is to tripwire the exact shape (`jq … || echo <default>`) responsible for two named prior incidents (KF-004, KF-015 — "zero-findings canonical verdicts masking real findings" and "silent-clean red-team gate pass"), specifically on the gate-critical enforcement set: `adversarial-review.sh`, `flatline-orchestrator.sh`, `scoring-engine.sh`, `post-pr-triage.sh`, and all `red-team-*` scripts (`head/tools/check-no-swallowed-jq.sh:66-71`). Any of those scripts assembling and then executing shell code via a heredoc (a common pattern for templating a script that's piped to `bash` or written out and `source`d) can now embed the `jq ... || echo <default>` verdict-swallowing shape inside that heredoc and this scanner will never see it — silently reducing coverage on precisely the files where a missed instance reproduces KF-004/KF-015.

**Failure scenario:** a future edit to `adversarial-review.sh` (or a `red-team-*` script) builds an executed heredoc block (`cmd <<EOF ... | bash`) containing `jq -r '.verdict' foo.json || echo "PASS"`. `check-no-swallowed-jq.sh` runs clean (exit 0) in CI/pre-commit even though the exact incident shape it was built to catch is present and reachable, because the new code treats every heredoc — fixture or executable — identically.

**Remediation:** restore heredoc-body scanning for heredocs whose content is piped to or invoked as an interpreter (the removed `_hd_command`/`hd_exec` classification), or narrow the "skip" behavior specifically to `--root`-mode bats-fixture scans (its documented motivation, `head/tools/check-no-swallowed-jq.sh:135-137`) rather than applying it unconditionally in default (enforced-file) mode too.

Standard reference: [CWE-693: Protection Mechanism Failure](https://cwe.mitre.org/data/definitions/693.html).

---

### MEDIUM — removed `ValueError` handler lets an embedded-NUL prompt crash the adapter instead of walking the provider fallback chain

`head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:123-166` (the `except ValueError` clause that sat between the `OSError` clause ending at line 164 and `except _SemaphoreExhausted` at line 165 in `base/` has been deleted)

```python
except OSError as exc:
    # E2BIG (ARG_MAX — a huge diff on argv; agy is argv-transport, no
    # --prompt-file exists) or another exec failure → WALK the chain,
    # never crash with a raw OSError. The gemini-api HTTP fallback
    # covers oversized diffs. (FileNotFoundError is handled above.)
    raise ProviderUnavailableError(
        self.provider,
        f"agy -p exec failed (likely ARG_MAX on an oversized prompt): {exc}",
    ) from exc
except _SemaphoreExhausted as exc:
    ...
```

`base/` additionally caught `ValueError` here and converted it to a `ProviderUnavailableError` ("agy -p got un-execable argv (embedded NUL in the prompt?)"). The prompt built at `_build_command()` (`head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:274-282`) is placed directly on `argv` (`"-p", prompt, ...`) and passed to `run_subprocess_pgkill`, which on POSIX ultimately calls into `os.exec*`; a string argument containing an embedded NUL byte (`\x00`) raises `ValueError: embedded null byte`, not `OSError` — so it is **not** caught by the `except OSError` clause directly above. `ValueError` does not subclass `OSError`, so with the handler removed this exception now propagates out of `complete()` uncaught.

The file's own repeated design invariant (documented at lines 21-24, 267-273, 393-396: "prompt is untrusted review content"; "never crash with a raw OSError"; classification comments throughout `_raise_for_error`) is that provider failures must be typed and **walkable** so the multi-provider fallback chain can advance to the next provider — a hard crash defeats that chain instead of letting it fail over. Removing this handler reintroduces exactly the "raw exception instead of a walkable error" failure mode the surrounding code goes out of its way to avoid for every other exec-failure class (`FileNotFoundError`, `OSError`/E2BIG, `TimeoutExpired`, `SubprocessOutputCapExceeded`).

**Failure scenario:** the flattened prompt (`_build_prompt`, built from message content that can include arbitrary upstream/tool/review text per lines 300-326) contains an embedded NUL byte — plausible for content sourced from binary-adjacent diffs, tool output, or any upstream producer that doesn't strip control characters. `agy -p <prompt>` exec raises `ValueError`, which now propagates unhandled out of `AgyHeadlessAdapter.complete()`, crashing the calling cheval dispatch instead of raising `ProviderUnavailableError` and letting the fallback chain (e.g. the `gemini-api` HTTP path mentioned at line 160) take over.

**Remediation:** restore the `except ValueError as exc: raise ProviderUnavailableError(...)` clause removed from `base/`.

Standard reference: [CWE-248: Uncaught Exception](https://cwe.mitre.org/data/definitions/248.html); [CWE-755: Improper Handling of Exceptional Conditions](https://cwe.mitre.org/data/definitions/755.html).

---

## Observations (not tallied)

- **`head/.claude/scripts/ledger-lib.sh:157,179`** — `printf '%s' "$content"` was replaced with `echo "$content"` in both the guard check and the `last_updated` stamping. Under bash's builtin `echo` (non-`xpg_echo`), leading `-n`/`-e`/`-E` sequences are option-parsed and backslash sequences are left literal by default, so this is very unlikely to be exploitable in practice given ledger content always begins with `{`. Flagged as speculative/low-confidence because it depends on shell/`echo` implementation details this audit didn't execute-test; not excluded from future review if `_write_ledger` content sourcing ever changes to allow attacker-influenced leading bytes.

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 2 |
| Low | 0 |

(1 observation excluded as speculative/low-confidence per the excluded-count rule; see Observations above.)

## Verdict

**CHANGES_REQUIRED** — the HIGH finding reopens a variant of a previously-fixed silent-data-loss bug in the sprint ledger's core write path, and the two MEDIUM findings each remove hardening (a security-tripwire scanner's coverage of executed heredocs; a typed-exception fallback path) that the surrounding code's own comments identify as deliberately added in response to a named prior incident. None of the three changes are safe to land as a `chore` without restoring the removed safety property (object-type validation, executed-heredoc scanning, `ValueError` handling respectively).

**Immediate (before merge):**
1. Restore the JSON-object type check in `_write_ledger`'s content guard.
2. Restore executed-heredoc scanning in `check-no-swallowed-jq.sh`, or scope the new unconditional heredoc-skip to `--root` bats-fixture mode only.
3. Restore the `except ValueError` handler in `AgyHeadlessAdapter.complete()`.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":2,"low":0},"excluded":1,"ts":"2026-09-22T00:00:00Z"} -->
