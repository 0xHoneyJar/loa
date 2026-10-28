# ESO skill-loop — independent reviewer contract

You are reviewing ONE optimization pass on /home/merlin/Documents/thj/code/loa (branch perf/eso-skill-loop-2026-10-27).
The implementer's claims are NOT evidence. Re-derive everything yourself. You have the uncommitted diff (`git diff`), the
mission text, and the implementer's scratch dir ~/.cache/loa/eso-loop/pass-<K>/ (REPORT.md, golden/, golden_checksums.txt,
before.json, after.json). HARD TIME BUDGET: 20 minutes wall clock — do the bounded checks, then report; anything unfinished goes in an UNVERIFIED line, never into more experiments. Do NOT edit repo files. You may write under ~/.cache/loa/eso-loop/pass-<K>/review/.

Check, in this order, and cite file:line for every finding:
1. ISOMORPHISM — read the diff line by line. For every changed branch ask: same output bytes? same ordering and tie-breaking?
   same exit code and stderr on the degraded/error paths (missing file, no jq/yq, malformed stdin, empty input)? same
   sanitisation of untrusted text (control bytes, length caps, `|`, `<`, `>`, tab/newline)? same file-write semantics
   (atomic tmp+mv, flock, umask, symlink refusal)? Construct at least 2 adversarial inputs the implementer's golden matrix
   did not cover and run old-vs-new on them (`git stash` is forbidden — use `git show HEAD:<path> > /tmp/old-<name>` and
   run the old copy from a temp location with the same env/cwd).
2. GOLDEN — re-run `sha256sum -c golden_checksums.txt` yourself after regenerating the outputs with the new code.
3. TESTS — run the bats/pytest files that cover the target (`npx --no-install bats <files>`); report pass/fail counts.
4. SPEED — re-run the before/after hyperfine yourself (old copy vs new) with the same flags; confirm the claimed gain is real
   and not measurement noise (≥ 3σ apart or ≥ 20%). A pass with no measurable gain is CHANGES_REQUIRED (revert).
5. CI LINT — no raw sha256sum, no swallowed-jq shape, no bare `sed -i`/`readlink -f`, no bash-4-only syntax in bash-3.2 files,
   comments updated to describe the new implementation, no debris (`git status` shows only intended files).
6. SECURITY — hooks are trust boundaries. Any widening of what untrusted input can do, any new eval/source of data, any TOCTOU
   on the atomic-write paths, any change to fail-open/fail-closed semantics = CHANGES_REQUIRED.
7. SCOPE — exactly one lever, only the mission's files; anything else = CHANGES_REQUIRED.

ALSO write the identical report to ~/.cache/loa/eso-loop/pass-<K>/review/VERDICT.md (the orchestrator reads the FILE; chat messages may not arrive).
Final message format:
VERDICT: APPROVE | CHANGES_REQUIRED
Findings (severity CRITICAL/HIGH/MEDIUM/LOW, file:line, what breaks, how you verified): …
Verified independently: goldens N/N, bats X/Y, hyperfine old=…ms new=…ms, adversarial inputs tried: …
