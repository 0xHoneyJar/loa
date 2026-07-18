# Hook Cache-Prefix Hygiene Runbook (cycle-116 sprint D6)

> **Status:** Audit + mechanical backstop landed. No functional hook-content
> fixes were required by this sprint (the one defect found — loa-kf-surface.sh
> routing its payload to stderr instead of stdout — is a D1 fix, cross-
> referenced below, not a cache-prefix volatility issue).
> **Bead:** bd-c116-d6-cache-prefix-4yq2
> **Audience:** Loa maintainers touching `.claude/hooks/**` or
> `.claude/settings.json`'s `SessionStart` / `UserPromptSubmit` sections.
> **Mechanical backstop:** `check_hook_cache_hygiene` in
> `.claude/scripts/lint-invariants.sh` (WARN-level) +
> `tests/unit/hook-cache-prefix.bats`.

---

## 1. Why this matters

Anthropic prompt caching keys off a stable prefix. Every SessionStart hook's
stdout (on its non-block, exit-0 path) and every UserPromptSubmit hook's
stdout become part of that prefix. If a hook places volatile content there —
a raw `$(date)`, `$RANDOM`, a PID, or unsorted directory-listing output — the
prefix mutates on every session or turn and cache hits collapse to zero for
that portion of the prompt. This is a correctness-adjacent performance
property with no test coverage prior to this sprint: nothing previously
asserted that a hook's stdout, given fixed inputs, is byte-identical run to
run.

## 2. Per-event hook enumeration

The live `.claude/settings.json` (this repo's own dogfooding config; the
distributable template `.claude/hooks/settings.hooks.json` has no
`SessionStart` key at all — see §5) wires these hooks:

| Event | Script | async/once | Stdout on happy path? |
|---|---|---|---|
| Setup | `upgrade-health-check.sh` | — | CLI-lifecycle event, not per-session/per-turn model context. Out of scope. |
| SessionStart | `check-updates.sh --notify` (:481) | async, once | Async + 24h-TTL cache-file gated (`check-updates.sh:39-40,100,125,136,289-336`); content stable for a full day even under the least-favorable assumption that async-hook stdout reaches context (unconfirmed either way). Low priority. |
| SessionStart | `session-start/loa-l6-surface-handoffs.sh` (:487) | async, once | **Yes** — see §3.1. |
| SessionStart | `session-start/loa-l7-surface-soul.sh` (:493) | async, once | **Yes** — see §3.2. |
| SessionStart | `session-start/loa-run-mode-session-title.sh` (:499) | async, once | Uses `hookSpecificOutput.sessionTitle` (terminal tab title UI metadata), not model context. Irrelevant to cache prefix. |
| SessionStart | `loa-kf-surface.sh` (:505) | async, once | Gated OFF by default (`known_failures.surface_at_session_start`). See §4 for the routing defect found here. |
| PreCompact | `pre-compact-marker.sh` (:512) | — | Writes only `.run/compact-pending` + `~/.local/state/loa-compact/compact-pending`; no stdout. Not context-relevant. |
| UserPromptSubmit | `post-compact-reminder.sh` (:523) | — | **Yes, every turn** — see §3.3. |
| PreToolUse | 8 guard scripts (:534-595) | — | Grep-verified: no unconditional top-level `echo`/`printf` on the allow path; visible text is deny/BLOCKED-path only. Out of scope per this audit's own rubric (block-path text isn't cached prefix — it terminates the turn). |
| PostToolUse | `mutation-logger.sh`, `write-mutation-logger.sh`, `karpathy-surgical-diff-check.sh` (:597-633) | — | File-only (`.run/audit.jsonl`) or a single `>&2` line behind an unconditional `exit 0`. Zero stdout ever. |
| Stop | `run-mode-stop-guard.sh`, `settings-cleanup.sh` (:635-649) | — | JSON `{"decision":"block",...}` only when blocking a stop (rare; built from already-loaded `.run/*.json` state, no date/random); `settings-cleanup.sh` logs to stderr + a file-redirected audit JSON. No context path. |
| PermissionRequest | `permission-audit.sh` (:650-660) | async | UI permission-dialog event, log-only, not conversation-turn content. |

**Conclusion:** the actual per-turn/per-session context-injecting surface is
three scripts, not "every registered hook": `loa-l6-surface-handoffs.sh` and
`loa-l7-surface-soul.sh` (SessionStart, `once: true` — paid once at the very
start of the session's cache-critical prefix), and `post-compact-reminder.sh`
(UserPromptSubmit, executes every turn but is empty-output on the common
no-marker path).

## 3. Classification of the three reachable emitters

Three buckets, applied per emitter:

- **Load-bearing freshness** — content that must legitimately vary run to
  run because it reflects real state change (e.g. "3 unread handoffs" after
  a 4th arrives). Not a defect; caching still works because the prefix only
  changes when the underlying state actually changes.
- **Volatile-not-load-bearing** — content that varies for no reason tied to
  real state (wall-clock jitter, PID, unsorted iteration order). This is the
  class the lint invariant (§6) exists to catch.
- **Load-bearing-but-reorderable** — content whose *presence* is load-bearing
  but whose *internal ordering* could drift without a sort, silently
  fragmenting the cache prefix across otherwise-identical states.

### 3.1 `loa-l6-surface-handoffs.sh` → `structured-handoff-lib.sh:surface_unread_handoffs` (lines ~1190-1339)

Iterates `INDEX.md` rows via `awk` in file-append order (no `sort`/`glob`/
`find`) — deterministic given fixed `INDEX.md` + handoff bodies (**load-
bearing freshness**, reorderable risk not present since append-order is
already file-order, not glob-order). One `mktemp
"${dir}/.surface-body.tmp.XXXXXX"` (line ~1294) creates a random-suffixed
temp path, but it is `sed`-replaced with the canonical `rel_path` *before*
the banner text is emitted — the random suffix never reaches the cached
prefix. `tests/unit/hook-cache-prefix.bats` exercises
`surface_unread_handoffs` (the exact function the wrapper hook calls)
directly against a fixed fixture and confirms byte-identical output across
two runs.

### 3.2 `loa-l7-surface-soul.sh` → `soul-identity-lib.sh:soul_load` (lines ~497-526)

Reads `SOUL.md` verbatim minus frontmatter via a Python heredoc, passes
through `sanitize_for_session_start` (pure regex/text transforms) — no
date/random/glob anywhere in the path. **Load-bearing freshness only** (the
content is whatever SOUL.md currently says). `tests/unit/hook-cache-prefix.bats`
runs the wrapper hook itself twice against a fixed `SOUL.md` fixture and
confirms byte-identical output.

### 3.3 `post-compact-reminder.sh` (UserPromptSubmit hot path)

The visible reminder text contains no raw timestamps/PIDs — only allowlist-
validated (`validate_state`) state strings pulled from the marker JSON
(**load-bearing freshness**: the reminder legitimately differs by
`run_mode.state` / `simstim.phase`). The one genuine timestamp in the file
(`_pc_ts`) is written *only* to `grimoires/loa/a2a/trajectory/compact-events.jsonl`
— never into the injected text; confirmed by
`tests/unit/hook-cache-prefix.bats`' "no raw ISO-8601 timestamp" assertion.

Step 5 splices in `trajectory-gen.sh --condensed` output.
`generate_condensed()` uses `is_stale()` (a coarse 7-day boolean threshold)
to append `(stale: memory,visions,ledger)` — this **can** flip between two
compaction events with unchanged underlying data purely from wall-clock
drift (**volatile-not-load-bearing**, technically), but it's weekly-grained
and confined to a rare one-shot path (each firing is already a cache-reset
event by definition, since compaction just happened). Accepted, documented,
no code fix mandated by this sprint.

The genuinely continuous-drift function, `compute_age_label()` (produces
"2h ago" / "3d ago" strings from `date +%s` on every call), is used only by
`generate_prose()`, which only `golden-path.sh` (a user-typed `/loa` command,
not a hook) invokes. `generate_condensed` never calls `compute_age_label`.
**Not currently hook-reachable** — footnote only, no action needed unless a
future edit wires `--prose` into a hook.

## 4. loa-kf-surface.sh — functional defect, not a volatility defect (D1 scope)

`loa-kf-surface.sh`'s entire output on the healthy path — including the
table its own docstring says exists "so an agent sees the operational-failure
log before triaging" — is wrapped in `{ ... } >&2`, and its two WARNING paths
are also explicit `>&2`. Every sibling SessionStart hook in this repo
(`loa-l6-surface-handoffs.sh`, `loa-l7-surface-soul.sh`) routes its payload
through unredirected **stdout**, suppressing only its *own* stderr
(`2>/dev/null || true`). Empirically reproduced during this audit: stdout was
0 bytes, stderr carried the full table. Under Claude Code's documented
SessionStart contract (stdout on exit 0 = additionalContext; stderr = not fed
to the model), this means the KF surface most likely never reached the agent
even when `known_failures.surface_at_session_start` is flipped on.

This is a **functional correctness gap, not a cache-prefix volatility
issue** — nothing volatile reaches context if nothing reaches context at
all — so it is out of D6's scope. **D1 (same wave, cycle-116) owns the fix
and its test** (`.claude/hooks/loa-kf-surface.sh`, `tests/unit/kf-surface.bats`).
At the time this runbook was written, D1's fix was already landed in the
shared working tree (`tests/unit/kf-surface.bats` TEST-8 asserts the healthy
table now lands on stdout, not stderr) — this section is left as the
narrative record of the finding for anyone reading this runbook in isolation.
The underlying content generation (file-order `awk` parse, no date/RANDOM/PID)
was already deterministic before the routing fix, so no additional
cache-prefix work was needed once routing was corrected.

## 5. Out of scope: template/live SessionStart parity

`.claude/hooks/settings.hooks.json` (the distributable template) has no
`SessionStart` key at all — the 5 SessionStart hooks enumerated in §2 exist
only in this repo's live `.claude/settings.json`. Whether the template should
gain them, and whether `tests/unit/hook-wiring.bats`' template/live parity
checks (currently PreToolUse + safety/compliance only) should extend to
`SessionStart`, is a real gap surfaced by this audit but explicitly **out of
scope** for D6. The lead files a follow-up bead for it.

## 6. Mechanical backstop: `check_hook_cache_hygiene`

`.claude/scripts/lint-invariants.sh` gained a new WARN-level invariant,
`check_hook_cache_hygiene`, registered in `check_all_invariants()`. It:

1. Reads the LIVE `.claude/settings.json`'s `.hooks.SessionStart[]` and
   `.hooks.UserPromptSubmit[]` command lists via `jq`.
2. Statically scans **only those entry-point scripts** (not sourced
   libraries — library-level data flow is out of scope for a `grep`/`awk`
   static scan; the by-hand audit in §3 is what covers libraries) for
   `$(date`/`` `date` ``, `$RANDOM`, `$$`, `$(mktemp`/`` `mktemp` ``, and
   unsorted `` $(find `` / `` $(ls `` command substitutions.
3. Applies a two-pass heuristic so a `date`/`mktemp` result that only ever
   feeds a file-write heredoc (e.g. `check-updates.sh`'s cache-file
   timestamp) is **not** flagged: heredoc bodies are mapped to "safe" (their
   opener line redirects to a file or pipe) vs "unsafe" (a bare `cat <<EOF`
   that goes straight to stdout); a bare `var=$(volatile...)` assignment is
   deferred to its next usage site rather than flagged at the assignment
   line itself.
4. Reports **WARN, never ERROR** — a human reviews every hit via its
   `file:line` citation. `date`/`mktemp` used only for a file-write
   timestamp or path is legitimate and common.

**Known heuristic limitations** (documented so a future false-positive or
false-negative isn't mistaken for a bug in the invariant itself):

- No `\b` word-boundary regex is used anywhere in the scanner — the awk
  binary that resolves to plain `awk` on many Linux distros is `mawk`, which
  treats `\b` as a literal backspace character, not a boundary assertion,
  and silently never matches. Boundaries are spelled out as an explicit
  `([^A-Za-z0-9_]|$)` class instead. If you extend this scanner, do not
  reach for `\b`.
- Once a bare assignment's variable is deferred to its next usage line, the
  heuristic classifies that *one* usage line and stops watching the
  variable — a script using the same volatile-derived variable in two
  places (one safe, one not) is only guaranteed to be caught if the unsafe
  usage happens to be the *first* one textually after the assignment.
- A usage line's "own redirect safety" is a same-line character-class check
  for `>&2` / a bare `>` / `>>` anywhere on the line — it does not verify
  the redirect target is actually *that* variable (e.g. `rm -f "$tmpfile"`
  has no redirect and would be flagged as unsafe if `$tmpfile` were tracked,
  even though `rm` only consumes the path as an argument, not as printed
  content). This produces conservative false positives (more WARNs, never
  fewer), which is the intended failure direction for a WARN-level
  backstop — verified against the current 6-script surface, where it
  produces zero WARNs.
- Only `$(...)`/backtick-wrapped `find`/`ls` are scanned; a bare
  `find . | somecommand` pipeline outside a command substitution is not
  covered (none of the 6 scanned scripts currently do this).

Verified during D6: running the full lint against the current 6 scanned
scripts (`check-updates.sh`, `loa-l6-surface-handoffs.sh`,
`loa-l7-surface-soul.sh`, `loa-run-mode-session-title.sh`,
`loa-kf-surface.sh`, `post-compact-reminder.sh`) reports `PASS` with zero
hits, and a synthetic fixture containing `$(date)`, `$RANDOM`, and an
unsorted `$(find ...)` feeding a variable correctly produces three WARNs.

## 7. Test coverage

`tests/unit/hook-cache-prefix.bats` — byte-determinism regression suite for
the three reachable emitters (fixtures under `tests/fixtures/hook-cache-prefix/`):

- `surface_unread_handoffs` (L6) against a fixed seed handoff, run twice,
  byte-compared.
- `loa-l7-surface-soul.sh` (L7) against a fixed `SOUL.md` + config, run
  twice, byte-compared.
- `post-compact-reminder.sh` against a fixed marker JSON (re-seeded between
  runs — the hook deletes the marker after each run by design, one-shot
  delivery), run twice, byte-compared.
- `post-compact-reminder.sh` output asserted to contain no raw ISO-8601
  timestamp substring (regression guard for §3.3's finding).

## 8. Cache-token telemetry scope split (item 5)

A **separate, easily-confused** concept: `cache_read_input_tokens` /
`cache_creation_input_tokens` exist on the `Usage` dataclass at
`.claude/adapters/loa_cheval/types.py:56-57` and are populated in
`.claude/adapters/loa_cheval/providers/anthropic_streaming.py:148-149,168-169,320-321`
(cycle-114 FR-12). **This instruments the cheval multi-model substrate** —
Loa's own outbound calls to *other* models for BB/Flatline/red-team/
post-pr-triage — architecturally separate from **the interactive Claude Code
session's own prompt-cache health**, which is internal to the
Anthropic-hosted Claude Code harness and is **not observable from any script
in this repo**. This runbook's §2-§6 audit (the interactive-session hook
surface) and FR-12's telemetry (the cheval outbound-call surface) do not
overlap and neither substitutes for the other.

Additionally, FR-12 was "surfacing only" per its own commit message:
`.claude/adapters/loa_cheval/economy.py` and
`.claude/adapters/loa_cheval/audit/modelinv.py` have **zero references** to
either field (grep-confirmed), and `.claude/scripts/cost-report.sh` doesn't
surface them either — the promised roll-up hasn't landed. This is a
**pre-existing gap, tracked by the bd-b04l/bd-w7bh/bd-kyn5 lineage** — D6
documents it here for discoverability and does **not** attempt to close it;
that is separate work with its own review surface.

### How to measure (interactive session — informational only)

There is no in-repo script that reads interactive-session cache hit/miss;
the only *observable proxy* today is the cheval outbound-call fields above,
which measure a different call path entirely. If you need to reason about
this repo's own hooks' cache-prefix stability, the tool is
`.claude/scripts/lint-invariants.sh`'s `hook-cache-hygiene` check (static,
§6) plus `tests/unit/hook-cache-prefix.bats` (dynamic, §7) — not the cheval
`Usage` fields.
