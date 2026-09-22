# Prompt audit report — `protocol-karpathy-principles` (lead-authored, landed in `c6ac82f4`)

**Target model**: Claude Fable 5.1. **Bytes**: 1,858 → 6,247 — this unit *received* text: the full principle statement that CLAUDE.loa.md used to carry every session now lives here (v3.0), and the always-loaded kernel points at it. Against its own 70 % target the file grew by design; the aggregate protocol budget absorbs it (the demand-loaded protocol is read only when a principle needs its full wording).

| Line | Pattern | Action |
|---|---|---|
| header | 1d version narrative (`v2 gutted…`, PR numbers in prose) | a one-line version note; history tokens in a `<!-- provenance: … -->` comment at the end |
| enforcement map | kept — the mechanism table (config keys, hook, gate, trajectory schema) is the reason this protocol exists |
| principles | moved in verbatim from CLAUDE.loa.md; "applies on every code-touching turn" kept as the routing sentence |

MUST lines keep their mechanism (`MUST leave at least one runnable check` → sprint acceptance tests). Keep-list: no rows match. Untrusted input: none.
