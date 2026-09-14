#!/usr/bin/env python3
"""Supervise a mount process group without detaching its controlling terminal."""
import errno
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


def signal_group(group, sig):
    try:
        os.killpg(group, sig)
    except ProcessLookupError:
        pass


def group_is_running(group):
    # ps has this form on GNU and BSD. Zombies cannot mutate the installation;
    # an empty/failed inspection is not proof that our group has stopped.
    result = subprocess.run(
        ["ps", "-ax", "-o", "pgid=", "-o", "stat="],
        check=True, stdout=subprocess.PIPE, text=True,
    )
    rows = result.stdout.splitlines()
    if not rows:
        raise RuntimeError("empty process inspection")
    running = False
    for row in rows:
        fields = row.split()
        if len(fields) != 2 or not fields[0].isdigit():
            raise RuntimeError("invalid process inspection")
        if int(fields[0]) == group and not fields[1].startswith("Z"):
            running = True
    return running


def supervise(receipt, owner, command):
    cancelled = 0

    def cancel(sig, _frame):
        nonlocal cancelled
        if not cancelled:
            cancelled = sig

    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, cancel)
    # An asynchronous Bash launch may inherit ignored INT until these handlers
    # exist. Acknowledge them before accepting the wrapper's owner-bound grant;
    # without that grant no installer process (or terminal handoff) can start.
    lock = Path(receipt).parent
    (lock / "ready").write_text(owner)
    startup_deadline = time.monotonic() + 5
    while not cancelled:
        try:
            if (lock / "start").read_text() == owner:
                break
        except FileNotFoundError:
            pass
        if time.monotonic() >= startup_deadline:
            raise RuntimeError("mount startup launch acknowledgement timed out")
        time.sleep(0.05)
    if cancelled:
        # There has been no fork or foreground transfer to drain/restore.
        Path(receipt).write_text(owner)
        return 128 + cancelled

    # Foreground transfer/restoration is performed by this background supervisor.
    signal.signal(signal.SIGTTOU, signal.SIG_IGN)
    tty = None
    foreground = None
    child = None
    child_status = None
    gate_read, gate_write = os.pipe()
    try:
        try:
            tty = os.open("/dev/tty", os.O_RDWR | os.O_NOCTTY)
        except OSError as exc:
            if exc.errno not in (errno.ENXIO, errno.ENODEV, errno.ENOENT):
                raise
        if tty is not None:
            current = os.tcgetpgrp(tty)
            # A background invocation must not steal another job's terminal.
            if current == os.getpgrp():
                foreground = current
        child = os.fork()
        if child == 0:
            try:
                os.close(gate_write)
                os.setpgid(0, 0)
                for sig in (signal.SIGINT, signal.SIGQUIT, signal.SIGTERM,
                            signal.SIGHUP, signal.SIGTTOU, signal.SIGTTIN,
                            signal.SIGTSTP, signal.SIGPIPE):
                    signal.signal(sig, signal.SIG_DFL)
                # No installer code or terminal read runs before foreground
                # ownership is assigned. EOF means setup failed in the parent.
                if os.read(gate_read, 1) != b"1":
                    os._exit(125)
                os.close(gate_read)
                if tty is not None:
                    os.close(tty)
                os.execv(command[0], command)
            except OSError as exc:
                print("Mount child launch failed: {}".format(exc), file=sys.stderr)
            os._exit(125)

        os.close(gate_read)
        gate_read = None
        os.setpgid(child, child)
        if foreground is not None:
            os.tcsetpgrp(tty, child)
        os.write(gate_write, b"1")
        os.close(gate_write)
        gate_write = None
        # Keep the group ID after waitpid reaps the direct child. Descendants
        # may still be using both the consumer lock and downloaded scripts.
        group = child
        drain_deadline = None
        kill_deadline = None
        cancel_forwarded = False
        while True:
            if child_status is None:
                waited, status = os.waitpid(child, os.WNOHANG | os.WUNTRACED)
                if waited and os.WIFSTOPPED(status):
                    if not cancelled:
                        if foreground is not None and os.tcgetpgrp(tty) == group:
                            os.tcsetpgrp(tty, foreground)
                        # Let the caller's shell observe a stopped wrapper job.
                        # SIGSTOP also works when its process group is orphaned.
                        os.killpg(os.getpgrp(), signal.SIGSTOP)
                        # On `fg`, hand the terminal back before resuming reads.
                        # On `bg`, leave the foreground job's terminal alone.
                        if tty is not None and os.tcgetpgrp(tty) == os.getpgrp():
                            foreground = os.getpgrp()
                            os.tcsetpgrp(tty, group)
                    signal_group(group, signal.SIGCONT)
                elif waited:
                    child_status = (os.WEXITSTATUS(status) if os.WIFEXITED(status)
                                    else 128 + os.WTERMSIG(status))
                    drain_deadline = time.monotonic() + 5
            if child_status is not None and not group_is_running(group):
                break
            now = time.monotonic()
            if cancelled and not cancel_forwarded:
                signal_group(group, cancelled)
                signal_group(group, signal.SIGCONT)
                cancel_forwarded = True
                if kill_deadline is None:
                    kill_deadline = now + 5
            elif kill_deadline is None and drain_deadline is not None and now >= drain_deadline:
                # Allow ordinary descendants to finish after direct-child exit;
                # abandoned workers then get the same bounded cancellation.
                signal_group(group, signal.SIGTERM)
                signal_group(group, signal.SIGCONT)
                kill_deadline = now + 5
            if kill_deadline is not None and now >= kill_deadline:
                signal_group(group, signal.SIGKILL)
            time.sleep(0.05)
    except (OSError, RuntimeError, subprocess.SubprocessError):
        if child is not None and child > 0:
            signal_group(child, signal.SIGKILL)
            if child_status is None:
                try:
                    os.kill(child, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                os.waitpid(child, 0)
        # No receipt: the wrapper must retain resources for inspection.
        raise
    finally:
        for fd in (gate_read, gate_write):
            if fd is not None:
                os.close(fd)
        if tty is not None:
            try:
                if foreground is not None and os.tcgetpgrp(tty) == child:
                    os.tcsetpgrp(tty, foreground)
            finally:
                os.close(tty)

    # The wrapper checks the acquisition token after reaping this supervisor.
    # A failed write/foreground restore must not look like completed supervision.
    Path(receipt).write_text(owner)
    return 128 + cancelled if cancelled else child_status


if __name__ == "__main__":
    try:
        sys.exit(supervise(sys.argv[1], sys.argv[2], sys.argv[3:]))
    except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
        print("Mount supervision failed; retaining resources: {}".format(exc), file=sys.stderr)
        sys.exit(125)
