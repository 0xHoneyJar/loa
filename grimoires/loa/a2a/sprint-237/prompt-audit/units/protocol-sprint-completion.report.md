# Prompt audit report — `protocol-sprint-completion` (`.claude/protocols/sprint-completion.md`, lead-authored archival, landed in `c6ac82f4`)

**Disposition**: archived to `grimoires/loa/archive/protocols/sprint-completion.md` (`git mv`, history preserved); its row in `.claude/loa/reference/protocols-summary.md` removed; `protocol-refs-resolve.bats` PR-1/PR-3 assert that no live reference to `protocols/sprint-completion.md` remains and that the file is gone from `.claude/protocols/`.

**Why archive rather than trim**: its live rule — the verdict trailer is what the gate reads, `verdict-derive.sh` is fail-closed, audit implies review — is the only part still enforced by code; the rest described the pre-trailer prose heuristics that cycle-119 retired.

**Kept elsewhere**: the live rule moved verbatim into `.claude/protocols/feedback-loops.md` (`## Verdict Trailers and the Gate`), and the doc-lock test that pinned this file (`golden-path-c8-verdict-trailer.bats` FR-5) was retargeted there.

Untrusted input: none.
