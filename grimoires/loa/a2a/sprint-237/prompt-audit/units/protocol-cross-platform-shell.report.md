# Prompt audit report — `protocol-cross-platform-shell`

**Scope**: `.claude/protocols/cross-platform-shell.md` only (no `resources/`). **Target model**: Claude Fable 5.1. **Bytes**: 10956 → 7354 (target ≤7669, met).

No keep-list row matches this path; no `@constraint-generated`/`@skill-include` blocks present. No text in the file reads as an instruction to the auditor.

## Findings

| Location | Pattern | Evidence | Why obsolete for Fable 5.1 | Confidence | Action |
|---|---|---|---|---|---|
| L3-5, L30, L47, L231, L296-299 | Group 2: history narrative (incident IDs, PR#) | `Issue: .../195`, `Origin: ...(#194)`, `(since Issue #240)`, `(since PR #199)`, "Related" list of Issue/PR pointers | Per the brief's History rule, `#NNNN`/PR tokens in rule text belong only in a `## Provenance` footer | High | move → footer; drop the two decorative external links (Google Style Guide, Kubernetes) that added no instruction |
| L17-18, L58, L82, L100 (x2) | Step 3 / Group 1c reinforcement-by-authority padding | "the same principle Kubernetes/Bazel applies...", "...caused CloudFlare's 2017 leap-second outage", "Google's Shell Style Guide recommends...", "the same approach Node.js uses..." | Decorative analogy citations add no actionable content beyond the reason already stated next to each; current models don't need appeals to authority to follow a plain instruction | Medium | remove (the substantive reason/rule beside each is kept) |
| L84-164 (Canonical Paths, File Mtime, Version Sorting, Temp Files, Find+Sort, Regex-in-grep) | Step 3 core test ("could the model already know this?") + Group 2 duplicated-info | 6 sections pairing a well-known GNU/BSD flag divergence (`readlink -f`, `stat -c/-f`, `sort -V`, `mktemp --suffix`, `find -printf`, `grep -P`) with a WRONG/RIGHT block | These are common Unix portability facts, unlike the Timestamps/Bash-guard/Timeout/Curl cases (kept in full — genuinely non-obvious gotchas). `readlink -f` absence is already stated in Overview L9 — a direct duplicate | Medium | rewrite → one `Other compat-lib.sh Wrappers` table keeping every exact wrapper function/signature (the only-the-author-knows contract) and dropping only the illustrative WRONG lines |
| L263-270 | Group 1c: step choreography for a non-fragile task | `1. Add... 2. Add... 3. Document... 4. Update...` | 4-item maintenance checklist, not an order-critical/destructive sequence | Medium | rewrite → one prose sentence |
| L272-280 | Group 1c: duplicated boilerplate | prose "verified on the CI matrix" immediately followed by a YAML block stating the same fact | Same fact stated twice | Medium | rewrite → one sentence |
| L219-225 | Group 1c: duplicated boilerplate | Already-Portable row `grep -E \| Extended regex...` | Duplicates the consolidated wrapper table's `grep -P → grep -E` row | Medium | remove row |
| L240-244 | Step 3 over-specification (internal, not actionable by script authors) | "Each library detects once...debug output via `LOA_*_DEBUG=1`" | Debug-var fact is already demonstrated concretely in Testing; caching/dispatch internals aren't acted on by script authors | Medium | remove |

## MUST/NEVER/ALWAYS

No literal tokens in this file. The closest, "Use `compat-lib.sh` functions instead of inline platform checks," is kept verbatim — its enforcing mechanism (`shell-compat-lint.yml`, cited later in the same file) already sits nearby, so no rewrite needed.

## Deliberately kept despite a grep hit

- The four "Why it's subtle" explanations (Bash-guard, Timestamps, Timeout, Curl-config) — each documents a non-obvious failure mode (silent garbage output, exit-code semantics, `ps aux` credential exposure): reasons only the author knows, not trained-default restatements.
- Curl Auth Config's full validation contract (CR/LF/null-byte/backslash rejection, quote escaping) — security control; never simplify away.
- "Patterns That Are Already Portable" table (minus the deduped `grep -E` row) — the boundary stopping the library-first rule from over-triggering on commands needing no wrapper.
- `**Version**: 1.0.0` — no named pattern justifies removing it; byte count alone isn't a valid reason.
- CI Enforcement table — the cited enforcing mechanism for the WRONG patterns above it.

## Residual

None — target met (7354 ≤ 7669 bytes).
