# Hook safety: fixes, limits and permission diagnosis

This runbook accompanies the hook issue sweep based on `76458ff2`.
`block-destructive-bash.sh` is a mistake fence over submitted command text.
It does not parse the complete shell language, inspect archive contents, resolve
interpreter APIs, intercept filesystem writes, or certify read freshness.

## Inert carriers (#1245)

The State/System Zone write checks use the same scrubbed decision text as the
destructive-command patterns. Raw command text is retained for audit records.
Known commit/bead/PR message values can therefore mention protected paths without
being mistaken for writes, including when another protected path appears outside
the message.

Metadata quoting consumes escaped double quotes as part of the value. Carrier
names must occur at a command position with balanced preceding quotes; names
inside another value or an interpreter/eval argument are not exempt. Message
scrubbing precedes echo/printf scrubbing so embedded `; echo` text cannot erase
a quote boundary and hide a following live redirect. This repairs the independent
P1 finding; both its exact git/bead payloads again block, while escaped inert
metadata still allows.

A complete, standalone `cat` command with a single quoted heredoc delimiter is
also recognized as a data carrier:

```sh
cat <<'EXAMPLE' > notes.md
git push --force origin main
echo x > .claude/hooks/example.sh
EXAMPLE
```

Supported forms include single/double quoted delimiters, `<<-` tab stripping,
and an optional output redirect before or after the heredoc operator. The
redirect remains visible: a destination under `.claude/hooks/` or
`.run/cron.d/` still blocks.

This exemption requires the entire command to match that small grammar.
Interpreter heredocs, pipelines, nested contexts, multiple heredocs, incomplete
delimiters, arbitrary flags, and trailing commands retain conservative matching.
An unquoted heredoc retains its body because expansions can execute there.
`$(...)` and backtick substitutions in quoted flag values remain visible;
direct catastrophic `rm` inside backticks is now detected too. Text inside a
single quoted heredoc does not undergo those expansions.

Two additional complete programs have restricted data-carrier grammars:

```sh
for c in 'rm -rf /' 'rm -rf ~'; do printf '%s\n' "$c"; done
python3 -c 'cases = ["git reset --hard origin/main"]; print(cases)'
```

The loop requires single-quoted items, a lowercase variable name, and exactly
one fixed-format `printf '%s\n'` of that same variable. Python accepts `python`
or `python3`, exactly `-c` with single-quoted source, and a list of double-quoted
string literals without escapes. The list can stand alone or be assigned to a
lowercase name and optionally printed with `print(name)`. The recognizers inspect
the entire submitted command and evaluate no supplied code.

Extra statements, other loop bodies, shell redirects, pipelines, Python imports,
function calls within lists, f-strings, and double-quoted shell program arguments
do not receive this exemption. Existing matching still applies to those forms.
Tests pair inert programs with actual harmless marker writes through expanding
arguments and `os.system`; the writes block. No interpreter-wide exemption is
introduced. This assumes the named shell builtin/interpreter has its usual
semantics; it is not a proof about user-defined functions or interpreter startup.

Remaining false positives include other loop/Python programs, unrecognized flag
values, and comments. Globally deleting quoted text would hide execution through
interpreters, `eval`, shell variables, or later consumers.
For documentation/fixtures, use a standalone quoted `cat` heredoc or the file
writing tool under its normal permissions. Do not disable the guard to document it.

The minimal reported sed-label form (`echo 'rm -rf'; sed -n '335,350p' script.sh`)
already passes at this baseline. The issue does not include its full failing
command, so the specific sed-range diagnostic is not claimed fixed. It also omits
the original loop body and Python program. The complete print-only examples above
are bounded reproductions of those data shapes, not reconstructions of the
missing original commands. A hook-probing loop with `H=...` and an unspecified
body cannot be certified from the issue excerpt alone.

`test-safety-hooks.sh` now explicitly allows the three bounded `/tmp/foo` forms.
Catastrophic `/`, `~`, `$HOME`, and `.` deletion controls remain blocked;
`rm --force --recursive .` was never a bounded-path case.

## Hook command locations (#1172)

Both `.claude/hooks/settings.hooks.json` and `.claude/settings.json` anchor hook
executables and wrapped hook arguments to the quoted git toplevel:

```sh
"$(git rev-parse --show-toplevel)"/.claude/hooks/hook-guard.sh "$(git rev-parse --show-toplevel)"/.claude/hooks/safety/block-destructive-bash.sh
```

This preserves cwd, stdin, arguments, stdout/stderr and the target exit status.
The dedicated tests run the shipped commands from a main root and a nested
linked worktree root, including each root's `.claude` and `.claude/worktrees`
directories, with spaces in paths and an intentionally incorrect
`CLAUDE_PROJECT_DIR`. The real wrapped fence is also exercised.
The existing mount/update copy set carries both settings and hooks; no installer
rewrite is needed. The hook-cache linter strips this exact anchor statically
before inspecting scripts; it never executes hook commands to find their paths.

This fixes framework command location. It does not certify Claude Code's
reported nested-worktree cwd/project-root bug or every hook's interpretation of
relative tool-input paths. Git and the hook files must exist in the current
worktree; an out-of-repository cwd or a missing/sparse hook installation remains
an environment prerequisite.

## Structural limits (#1047)

The executable tests in `tests/unit/test_hook_limit_assessments.py` write only
`safe` into disposable fixture files. They prove these effective-path gaps:

| Class | Hook-visible form | Observed limit |
|---|---|---|
| Quoted concatenation | `printf safe > .r""un/cron.d/probe.sh` | Allows; shell writes `.run/cron.d/probe.sh`. |
| Line continuation | `.r` plus backslash-newline plus `un/cron.d/probe.sh` | Allows; shell joins the path. |
| Archive member | `tar -xf fixture.tar` | Allows; the fixture archive contains `.run/cron.d/probe.sh`. |
| Interpreter path construction | `Path('.r' + 'un/cron.d/probe.sh').write_bytes(b'safe')` | Allows; Python computes the protected path. |

The direct literal redirect is a paired blocking control. Other known limits
include variable-indirected commands/paths, script-file contents, `eval`/encoded
code, and SQL comments that fool the WHERE check. Missing jq still follows the
existing warn-and-allow policy; the parse wrapper still warns and allows a
syntactically broken hook. Passing this suite does not make those paths safe.

Closing effective-write gaps requires a separately designed enforcement layer,
such as filesystem permissions or interception. A tokenizer could improve
lexical coverage but would not inspect arbitrary archives or interpreter effects.
No such layer is implemented or claimed by this patch.

## Permission diagnosis (#1088)

An identical tool payload does not imply identical hook inputs. Cwd, environment,
zones, authorization expiry, and `.run/` sentinels are also inputs. The dedicated
test uses one unchanged App Zone payload and observes:

1. No Spiral sentinel: allow.
2. `spiral-dispatch-active` present, dispatch marker absent: block with the named
   Spiral diagnostic.
3. `spiral-harness-dispatched` present: allow.

Two local defects were reproduced and fixed:

- The Spiral guard accepted absolute State Zone paths but denied root-relative
  `grimoires/...`, `.run/...`, `.beads/...`, and `.claude/plans/...` paths when
  active. Both spellings now receive the intended exemption. App writes still
  require dispatch while that sentinel is active.
- The zone guard passed jq-only expressions to Mike Farah yq v4 (`tostring`
  fails with installed v4.40.5). It silently classified declared framework paths
  as unclassified. yq now decodes YAML and jq evaluates the row expression.
  Cache v2 prevents reuse of empty v1 rows left by that failed parse.

Neither finding establishes the cause of the historical incident. The present
`implement-gate.sh` can also emit an advisory ask for
`scripts/lib/segment-emitter.py` without active implementation state; stdout
must be inspected along with exit status and stderr.

For a recurrence, retain the host version, tool-call identity, exact sanitized
payload, cwd, permission mode and effective settings; record each matching
hook's exit/stdout/stderr plus relevant sentinel/config/authorization state.
Capture the host's permission-denial event separately. A conversational approval
alone is not evidence that the host permission engine changed its state.
The local tests do not exercise that engine, `AskUserQuestion` handoff, or the
original macOS session. Those session traces are the outstanding evidence needed
to assign the intermittent denial to a host or hook.

## Read-before-write residuals (#1031)

The issue reports that the host now rejects Write overwrites without a preceding
in-session Read. That host behavior was not exercised in this local sweep.
The current Loa hooks do not maintain a completed-read ledger or content revision
binding.

| Residual | Assessment |
|---|---|
| Parallel Read + Write of one path | Submission in one batch does not prove Read completed before Write. Host ordering/enforcement needs a host test. Serialize dependent operations. |
| Bash `cp`/redirect overwrite | Tool Read-before-Write enforcement does not automatically cover shell I/O. A harmless test overwrites ordinary `grimoires/loa/NOTES.md` through Bash with hook exit 0. Protected lifecycle paths have only the fence described above. |
| Edit after a stale Read | These hooks compare neither read bytes nor file revision. Edit matching/atomicity and concurrent-change behavior require host evidence. Re-read before a destructive change; use explicit revision checks where the workflow supports them. |

No speculative read-history hook is added. Such a hook cannot prove all three
properties from the present command/path-only decision inputs. Disposition:
primary shape is reported host-superseded, with this residual inventory retained;
this is not full read-before-write closure.

## Out-of-scope feature requests

#1207, #1208, #1209 and #1030 require new provenance/instrument/publish gates or
evidence-bound state transitions. The present mutation logger, advisory surfaces,
and completion gates do not prove those requested properties. These requests
are not implemented, registered, or marked resolved by the hook bug fixes.
