# Submodule mount cancellation and workspace cleanup

`mount-loa.sh` retains the submodule mount lock and downloaded scripts until its
installer child and all live members of that process group have stopped. The
group remains supervised after direct-child success, failure, or signal exit.
Ordinary descendants have five seconds to finish naturally; remaining workers
then receive TERM. INT, TERM and HUP sent to the wrapper are forwarded immediately
to a running group. Five seconds after cancellation, remaining members receive KILL.
Repeated cancellation does not interrupt cleanup.

The wrapper requires Python 3 and `lib/mount-supervisor.py`, included in the
required pipe-bootstrap downloads. The helper uses standard-library process and
terminal primitives without detaching the caller's session. For a foreground
invocation, it assigns the child's group the controlling terminal before exec:
stdin, `/dev/tty`, foreground queries and terminal-generated INT work. It restores
the caller's foreground group before confirming completion. It never takes the
terminal from another foreground job. A stopped child suspends the wrapper job;
`fg` transfers the terminal back before the child receives CONT. Missing
Python/helper stops before launch.
This requirement applies to the default submodule route.

Interpreter startup has a separate five-second deadline. The helper acknowledges
installed INT/TERM/HUP handlers with an ownership-bound `ready` marker, then waits
up to five seconds for the wrapper's matching `start` grant before forking or
changing the terminal foreground. The wrapper retains the first cancellation
through startup and forwards it after acknowledgement without granting launch.
The helper can then confirm that no installer started and write its completion
receipt. PID assignment alone is not treated as readiness.

If startup stalls, the wrapper kills and reaps the unacknowledged helper; no
launch grant exists. An early helper exit, failed readiness write, missing/wrong
launch grant or startup timeout exits with supervision status 125 (or the recorded
cancellation status). Without a valid completion receipt, the lock and downloads
remain for inspection. The wrapper never fabricates a receipt for startup failure.

`.loa-mount-lock` at the consumer root is an atomically created directory with an `owner` file
containing the wrapper PID and a per-acquisition token. Only that acquisition
removes its marker. Competing callers, non-owners and callers seeing a replacement
lock leave it intact. The location stays fixed when installation replaces a
top-level `.claude` symlink with a directory. This coordinates callers of the outer submodule mount
wrapper; direct `mount-submodule.sh`, migration and vendored invocations do not
acquire this outer lock. Memory Stack relocation has its own lock.
The generated submodule ignore rules exclude this transient ownership marker
from the install commit.

An existing lock, including a legacy `.claude/.mount-lock` marker, is never automatically removed.
After an uncatchable interruption, inspect its contents and the installer
processes. Stop all mounts and remaining installer children before manually
removing an abandoned marker. PID absence alone does not prove that descendants
have stopped, and removal while another caller starts is unsafe. Do not run old
and new wrappers concurrently: older versions do not coordinate at the new path.

The helper writes a completion receipt bound to the lock's acquisition token
only after group termination and terminal restoration. A failed/empty/malformed
process inspection, helper failure, or missing/wrong receipt preserves the lock
and downloaded scripts with a diagnostic and nonzero exit. Inspect them before
manual recovery. An uncatchable KILL, deliberate move to another process group
or session, or concurrent manual lock replacement is outside this coordination
contract. Zombies cannot perform installer work and do not hold resources open.

Workspace cleanup uses `du -sk` and `df -Pk`, checks command status and numeric
results, and converts KiB to bytes for its existing JSON fields and disk-space
margin. Sizes now represent allocated space rounded to KiB. A failed or malformed
measurement exits with a diagnostic before archiving; it is not reported as a
successful cleanup or as insufficient space. Source artifacts remain intact.

Focused offline checks:

```bash
bats tests/unit/mount-submodule-lock-lifecycle.bats \
     tests/unit/workspace-cleanup-portability.bats
```

The mount suite runs actual local processes, signals and a Linux PTY against
disposable fixture repositories. It exercises delayed descendants after direct
child exit, the actual `create_symlinks` layout transition, `/dev/tty` input,
terminal INT, parent TERM and foreground restoration after success/failure.
An interpreter-exec gate reproduces Bash's inherited ignored INT before Python
handlers install; startup INT/TERM/HUP and an already-ready cancellation control
exercise both sides of the handshake. Stalled startup, early exit, readiness
write failure and missing/wrong launch grants must terminate within bounded waits.
Installer payloads are harmless local fixtures.
The cleanup suite rejects GNU-only realpath/du/df options with command shims and
checks archive bytes and failure preservation. These checks do not establish
native macOS, BSD or Bash 3.2 behavior. Cleanup already requires Bash 4 and `flock`;
its remaining retention/date/sort portability requirements are separate.
