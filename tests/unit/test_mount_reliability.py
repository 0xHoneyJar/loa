"""Local process/barrier fixtures; no network or downstream installation."""
import os
import json
from pathlib import Path
import pty
import re
import select
import shutil
import signal
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / ".claude/scripts/mount-loa.sh"
LOCK_NAME = re.search(r'^MOUNT_LOCK_FILE="([^"]+)"', SOURCE.read_text(), re.M)[1]


class MountReliabilityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="loa-mount-reliability-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.download = self.root / "download"
        self.work = self.root / "consumer"
        self.download.mkdir()
        self.work.mkdir()
        (self.download / "lib").mkdir()
        for name in ("mount-loa.sh", "compat-lib.sh", "lib/scaffold-post-merge-workflow.sh"):
            shutil.copy2(ROOT / ".claude/scripts" / name, self.download / name)
        helper = ROOT / ".claude/scripts/lib/mount-supervisor.py"
        if helper.exists():
            shutil.copy2(helper, self.download / "lib/mount-supervisor.py")
        subprocess.run(["git", "init", "-q", str(self.work)], check=True)
        self.lock = self.work / LOCK_NAME
        self.processes = []
        self.addCleanup(self.stop_processes)

    def stop_processes(self):
        # Only signal fixture-owned processes, including detached installer jobs.
        for path in self.work.glob("*.pid"):
            try:
                os.kill(int(path.read_text()), signal.SIGKILL)
            except (ProcessLookupError, ValueError):
                pass
        for proc in self.processes:
            if proc.poll() is None:
                proc.kill()
            proc.communicate(timeout=5)

    def wait_for(self, predicate, message, timeout=5):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.01)
        self.fail(message)

    @staticmethod
    def process_is_live(pid):
        result = subprocess.run(["ps", "-p", str(pid), "-o", "stat="],
                                capture_output=True, text=True, check=False)
        state = result.stdout.strip()
        return bool(state) and not state.startswith("Z")

    def start_mount(self, extra_env=None):
        env = dict(os.environ, _LOA_MOUNT_TMPDIR=str(self.download))
        env.update(extra_env or {})
        proc = subprocess.Popen(
            ["bash", str(self.download / "mount-loa.sh"), "--no-commit"],
            cwd=self.work, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, start_new_session=True,
        )
        self.processes.append(proc)
        return proc

    def startup_fixture(self):
        """Pause exec of the real helper, preserving Bash's signal inheritance."""
        self.restore_download()
        bin_dir = self.root / "startup-bin"
        bin_dir.mkdir(exist_ok=True)
        real_python = shutil.which("python3")
        shim = bin_dir / "python3"
        shim.write_text(f"""#!{real_python}
import json, os, signal, sys, time
from pathlib import Path
Path("fixture-supervisor.pid").write_text(str(os.getpid()))
Path("fixture-helper-starting").write_text(json.dumps({{
    "sigint_ignored": signal.getsignal(signal.SIGINT) == signal.SIG_IGN,
}}))
while not Path("fixture-helper-release").exists():
    time.sleep(0.01)
os.execv({real_python!r}, [{real_python!r}] + sys.argv[1:])
""")
        shim.chmod(0o755)
        child = self.download / "mount-submodule.sh"
        child.write_text("""#!/bin/bash
printf '%s' "$$" > fixture-child.pid
trap 'touch fixture-child-cancelled; exit 130' INT
touch fixture-child-ready
while [[ ! -e fixture-child-exit ]]; do sleep 0.02; done
""")
        child.chmod(0o755)
        proc = self.start_mount({"PATH": str(bin_dir) + ":" + os.environ["PATH"]})
        self.wait_for(lambda: (self.work / "fixture-helper-starting").exists(),
                      "helper did not reach the interpreter startup gate")
        self.assertTrue(json.loads((self.work / "fixture-helper-starting").read_text())[
            "sigint_ignored"], "fixture did not reproduce async Bash signal inheritance")
        return proc

    def test_startup_cancellation_is_retained_before_handlers_install(self):
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            with self.subTest(signal=sig.name):
                proc = self.startup_fixture()
                try:
                    os.kill(proc.pid, sig)
                    time.sleep(0.15)
                    self.assertTrue(self.lock.exists())
                    self.assertTrue(self.download.exists())
                    (self.work / "fixture-helper-release").touch()
                    self.wait_for(lambda: proc.poll() is not None or
                                  (self.work / "fixture-child-ready").exists(),
                                  "startup cancellation never completed", timeout=8)
                    self.assertFalse((self.work / "fixture-child-ready").exists(),
                                     "installer launched after startup cancellation")
                    out, err = proc.communicate(timeout=3)
                    self.assertEqual(proc.returncode, 128 + sig, out + err)
                    self.assertFalse(self.lock.exists(), out + err)
                    self.assertFalse(self.download.exists(), out + err)
                finally:
                    (self.work / "fixture-helper-release").touch()
                    (self.work / "fixture-child-exit").touch()
                    self.stop_processes()
                    if self.lock.is_dir():
                        shutil.rmtree(self.lock)

    def test_ready_startup_control_forwards_cancellation(self):
        proc = self.startup_fixture()
        (self.work / "fixture-helper-release").touch()
        self.wait_for(lambda: (self.work / "fixture-child-ready").exists(),
                      "ready control did not start the installer")
        os.kill(proc.pid, signal.SIGINT)
        out, err = proc.communicate(timeout=3)
        self.assertEqual(proc.returncode, 130, out + err)
        self.assertTrue((self.work / "fixture-child-cancelled").exists())
        self.assertFalse(self.lock.exists())
        self.assertFalse(self.download.exists())

    def test_stalled_interpreter_startup_is_bounded(self):
        for sig in (None, signal.SIGINT):
            with self.subTest(signal=sig):
                proc = self.startup_fixture()
                try:
                    started = time.monotonic()
                    if sig is not None:
                        os.kill(proc.pid, sig)
                    out, err = proc.communicate(timeout=8)
                    self.assertLess(time.monotonic() - started, 8)
                    self.assertEqual(proc.returncode, 128 + sig if sig else 125, out + err)
                    self.assertFalse(self.process_is_live(
                        int((self.work / "fixture-supervisor.pid").read_text())))
                    self.assertFalse((self.work / "fixture-child-ready").exists())
                    self.assertTrue(self.lock.exists())
                    self.assertTrue(self.download.exists())
                    self.assertFalse((self.lock / "terminated").exists())
                    self.assertIn("startup", out + err)
                    self.assertIn("retaining", out + err)
                finally:
                    self.stop_processes()
                    if self.lock.is_dir():
                        shutil.rmtree(self.lock)

    def test_pre_ready_exit_and_readiness_write_failure_are_bounded(self):
        for failure in ("early_exit", "ready_write"):
            with self.subTest(failure=failure):
                proc = self.startup_fixture()
                if failure == "early_exit":
                    (self.download / "lib/mount-supervisor.py").write_text(
                        "raise SystemExit(42)\n")
                else:
                    (self.lock / "ready").mkdir()
                try:
                    (self.work / "fixture-helper-release").touch()
                    out, err = proc.communicate(timeout=8)
                    self.assertEqual(proc.returncode, 125, out + err)
                    self.assertFalse((self.work / "fixture-child-ready").exists())
                    self.assertTrue(self.lock.exists())
                    self.assertTrue(self.download.exists())
                    self.assertFalse((self.lock / "terminated").exists())
                    self.assertIn("retaining", out + err)
                finally:
                    self.stop_processes()
                    if self.lock.is_dir():
                        shutil.rmtree(self.lock)

    def test_helper_requires_owner_bound_launch_acknowledgement(self):
        for grant in (None, "another-owner"):
            with self.subTest(grant=grant):
                self.restore_download()
                self.lock.mkdir()
                if grant is not None:
                    (self.lock / "start").write_text(grant)
                child = self.download / "mount-submodule.sh"
                child.write_text("#!/bin/bash\ntouch fixture-unexpected-child\n")
                child.chmod(0o755)
                proc = subprocess.Popen(
                    ["python3", str(self.download / "lib/mount-supervisor.py"),
                     str(self.lock / "terminated"), "fixture-owner", str(child)],
                    cwd=self.work, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                )
                self.processes.append(proc)
                try:
                    out, err = proc.communicate(timeout=8)
                    self.assertEqual(proc.returncode, 125, out + err)
                    self.assertEqual((self.lock / "ready").read_text(), "fixture-owner")
                    self.assertFalse((self.work / "fixture-unexpected-child").exists())
                    self.assertFalse((self.lock / "terminated").exists())
                finally:
                    self.stop_processes()
                    shutil.rmtree(self.lock)

    def test_cancellation_keeps_resources_until_child_and_descendant_stop(self):
        for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            with self.subTest(signal=sig.name):
                self.check_cancellation(sig)

    def test_interactive_child_can_read_the_terminal(self):
        child = self.download / "mount-submodule.sh"
        child.write_text("""#!/usr/bin/env bash
printf '%s' "$$" > fixture-child.pid
printf 'Answer: '
read -r answer
printf '%s' "$answer" > fixture-answer
""")
        child.chmod(0o755)
        pid, master = pty.fork()
        if pid == 0:
            os.chdir(self.work)
            os.environ["_LOA_MOUNT_TMPDIR"] = str(self.download)
            os.execvp("bash", ["bash", str(self.download / "mount-loa.sh"), "--no-commit"])
        reaped = False
        try:
            output = b""
            deadline = time.monotonic() + 5
            while b"Answer:" not in output and time.monotonic() < deadline:
                if select.select([master], [], [], 0.1)[0]:
                    output += os.read(master, 65536)
            self.assertIn(b"Answer:", output)
            os.write(master, b"yes\n")
            self.wait_for(lambda: (self.work / "fixture-answer").exists(),
                          "child could not read the controlling terminal")
            self.assertEqual((self.work / "fixture-answer").read_text(), "yes")
            self.wait_for(lambda: not self.lock.exists(), "interactive mount never completed")
            _, status = os.waitpid(pid, 0)
            reaped = True
            self.assertEqual(os.waitstatus_to_exitcode(status), 0)
        finally:
            if not reaped:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
            os.close(master)

    def test_child_ignoring_cancellation_is_killed_before_cleanup(self):
        child = self.download / "mount-submodule.sh"
        child.write_text("""#!/usr/bin/env python3
import os, signal, time
from pathlib import Path
signal.signal(signal.SIGTERM, signal.SIG_IGN)
Path("fixture-child.pid").write_text(str(os.getpid()))
while True:
    time.sleep(0.1)
""")
        child.chmod(0o755)
        proc = self.start_mount()
        self.wait_for(lambda: (self.work / "fixture-child.pid").exists(), "child never ready")
        child_pid = int((self.work / "fixture-child.pid").read_text())
        os.kill(proc.pid, signal.SIGTERM)
        time.sleep(0.1)
        self.assertIsNone(proc.poll())
        self.assertTrue(self.lock.exists())
        self.assertTrue(self.download.exists())
        out, err = proc.communicate(timeout=10)
        self.assertEqual(proc.returncode, 143, out + err)
        with self.assertRaises(ProcessLookupError):
            os.kill(child_pid, 0)
        self.assertFalse(self.lock.exists())
        self.assertFalse(self.download.exists())

    def test_direct_child_exit_keeps_group_and_resources_until_descendant_stops(self):
        for outcome in ("success", "failure", "signal"):
            with self.subTest(outcome=outcome):
                self.check_direct_child_exit(outcome)

    def test_cancellation_after_direct_child_exit_reaches_the_group(self):
        self.check_direct_child_exit("success", cancel=signal.SIGINT)

    def test_cancellation_during_descendant_drain_reaches_the_group(self):
        self.check_direct_child_exit("success", cancel=signal.SIGINT, wait_for_drain=True)

    def restore_download(self):
        self.download.mkdir(exist_ok=True)
        (self.download / "lib").mkdir(exist_ok=True)
        for name in ("mount-loa.sh", "compat-lib.sh", "lib/scaffold-post-merge-workflow.sh",
                     "lib/mount-supervisor.py"):
            source = ROOT / ".claude/scripts" / name
            if source.exists():
                shutil.copy2(source, self.download / name)
        for path in self.work.glob("fixture-*"):
            path.unlink()

    def check_direct_child_exit(self, outcome, cancel=None, wait_for_drain=False):
        self.restore_download()
        child = self.download / "mount-submodule.sh"
        child.write_text(f"""#!/usr/bin/env python3
import json, os, signal, subprocess, sys, time
from pathlib import Path
if len(sys.argv) > 1 and sys.argv[1] == "leaf":
    def receive(sig, frame):
        Path("fixture-leaf-signal").write_text(str(sig))
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, receive)
    Path("fixture-leaf.pid").write_text(str(os.getpid()))
    Path("fixture-leaf-ready").touch()
    while not Path("fixture-leaf-exit").exists():
        time.sleep(0.01)
    Path("fixture-late-write").write_text(json.dumps([
        Path({str(self.lock)!r}).exists(), Path({str(self.download)!r}).exists()]))
    sys.exit(0)
Path("fixture-child.pid").write_text(str(os.getpid()))
subprocess.Popen([sys.executable, __file__, "leaf"])
while not Path("fixture-leaf-ready").exists():
    time.sleep(0.01)
if {outcome!r} == "signal":
    os.kill(os.getpid(), signal.SIGTERM)
sys.exit(23 if {outcome!r} == "failure" else 0)
""")
        child.chmod(0o755)
        proc = self.start_mount()
        self.wait_for(lambda: (self.work / "fixture-leaf-ready").exists(), "leaf never ready")
        child_pid = int((self.work / "fixture-child.pid").read_text())
        self.wait_for(lambda: not self.process_is_live(child_pid),
                      "direct child did not exit before the descendant check")
        try:
            self.assertIsNone(proc.poll(), "wrapper exited while its descendant was live")
            self.assertTrue(self.lock.exists())
            self.assertTrue(self.download.exists())
            if cancel:
                if wait_for_drain:
                    self.wait_for(
                        lambda: (self.work / "fixture-leaf-signal").exists() and
                        (self.work / "fixture-leaf-signal").read_text() == str(signal.SIGTERM),
                        "descendant did not receive TERM after its natural drain interval",
                        timeout=7,
                    )
                os.kill(proc.pid, cancel)
                self.wait_for(
                    lambda: (self.work / "fixture-leaf-signal").exists() and
                    (self.work / "fixture-leaf-signal").read_text() == str(cancel),
                    "cancellation after direct-child exit lost the group",
                )
            else:
                self.assertFalse((self.work / "fixture-leaf-signal").exists())
            (self.work / "fixture-leaf-exit").touch()
            out, err = proc.communicate(timeout=8)
            expected = 128 + cancel if cancel else {"success": 0, "failure": 23, "signal": 143}[outcome]
            self.assertEqual(proc.returncode, expected, out + err)
            self.assertEqual(json.loads((self.work / "fixture-late-write").read_text()), [True, True])
            self.assertFalse(self.process_is_live(int((self.work / "fixture-leaf.pid").read_text())))
            self.assertFalse(self.lock.exists())
            self.assertFalse(self.download.exists())
        finally:
            (self.work / "fixture-leaf-exit").touch()
            self.stop_processes()
            if self.lock.is_dir():
                shutil.rmtree(self.lock)

    def test_actual_claude_layout_transition_keeps_one_physical_lock(self):
        old_layout = self.work / "old-claude"
        old_layout.mkdir()
        (self.work / ".claude").symlink_to(old_layout, target_is_directory=True)
        child = self.download / "mount-submodule.sh"
        child.write_text(f"""#!/usr/bin/env bash
set -euo pipefail
source {str(ROOT / '.claude/scripts/mount-submodule.sh')!r} --source-only
get_symlink_manifest() {{
    MANIFEST_DIR_SYMLINKS=() MANIFEST_FILE_SYMLINKS=()
    MANIFEST_SKILL_SYMLINKS=() MANIFEST_CMD_SYMLINKS=() MANIFEST_AGENT_SYMLINKS=()
}}
refresh_copy_set() {{ :; }}
touch fixture-before-transition
while [[ ! -e fixture-transition ]]; do sleep 0.01; done
create_symlinks
touch fixture-after-transition
while [[ ! -e fixture-child-exit ]]; do sleep 0.01; done
""")
        child.chmod(0o755)
        proc = self.start_mount()
        self.wait_for(lambda: (self.work / "fixture-before-transition").exists(), "child never ready")
        physical_lock = self.lock.resolve()
        owner = (physical_lock / "owner").read_text()
        (self.work / "fixture-transition").touch()
        try:
            self.wait_for(lambda: (self.work / "fixture-after-transition").exists(),
                          "actual create_symlinks transition failed")
            self.assertFalse((self.work / ".claude").is_symlink())
            result = subprocess.run(["bash", "-c", r'''
set -euo pipefail
err() { printf '%s\n' "$*" >&2; exit 1; }
source "$1"
acquire_mount_lock
release_mount_lock
''', "_", self.lock_script()], cwd=self.work, capture_output=True, text=True, timeout=5)
            self.assertNotEqual(result.returncode, 0, "second owner acquired across layout transition")
            self.assertEqual((physical_lock / "owner").read_text(), owner)
            self.assertEqual(self.lock.resolve(), physical_lock)
        finally:
            (self.work / "fixture-child-exit").touch()
        out, err = proc.communicate(timeout=8)
        self.assertEqual(proc.returncode, 0, out + err)
        self.assertFalse(physical_lock.exists(), "original lock was stranded")
        self.assertFalse(self.lock.exists())

    def test_controlling_terminal_foreground_and_restoration(self):
        for outcome in ("success", "failure", "terminal_int", "parent_term"):
            with self.subTest(outcome=outcome):
                self.check_controlling_terminal(outcome)

    def read_pty_until(self, master, marker):
        output = b""
        deadline = time.monotonic() + 5
        while marker not in output and time.monotonic() < deadline:
            if select.select([master], [], [], 0.05)[0]:
                try:
                    output += os.read(master, 65536)
                except OSError:
                    break
        self.assertIn(marker, output)
        return output

    def test_terminal_suspend_resume_preserves_foreground_job(self):
        child = self.download / "mount-submodule.sh"
        child.write_text("""#!/usr/bin/env python3
import os, signal
from pathlib import Path
Path("fixture-child.pid").write_text(str(os.getpid()))
Path("fixture-supervisor.pid").write_text(str(os.getppid()))
def resumed(sig, frame):
    assert os.getpgrp() == os.tcgetpgrp(0)
    Path("fixture-resumed").touch()
signal.signal(signal.SIGCONT, resumed)
with os.fdopen(os.open("/dev/tty", os.O_RDWR), "r") as tty:
    assert os.getpgrp() == os.tcgetpgrp(tty.fileno())
    os.write(tty.fileno(), b"TTY answer: ")
    Path("fixture-answer").write_text(tty.readline().strip())
    assert os.getpgrp() == os.tcgetpgrp(tty.fileno())
""")
        child.chmod(0o755)
        pid, master = pty.fork()
        if pid == 0:
            os.chdir(self.work)
            os.environ.update(PS1="FIXTURE-PROMPT>", HISTFILE="/dev/null",
                              _LOA_MOUNT_TMPDIR=str(self.download))
            os.execvp("bash", ["bash", "--noprofile", "--norc", "-i"])
        reaped = False
        try:
            self.read_pty_until(master, b"FIXTURE-PROMPT>")
            # The interactive shell creates a real job group for this wrapper.
            command = ("bash -c 'echo $$ > fixture-wrapper.pid; exec bash \"$1\" --no-commit' "
                       "_ " + str(self.download / "mount-loa.sh") + "\n")
            os.write(master, command.encode())
            self.read_pty_until(master, b"TTY answer:")
            os.write(master, b"\x1a")
            stopped = self.read_pty_until(master, b"FIXTURE-PROMPT>")
            self.assertIn(b"Stopped", stopped)
            self.assertTrue(self.lock.exists())
            self.assertTrue(self.download.exists())
            os.write(master, b"fg\n")
            self.wait_for(lambda: (self.work / "fixture-resumed").exists(),
                          "resumed child did not regain the terminal foreground")
            os.write(master, b"yes\n")
            self.read_pty_until(master, b"FIXTURE-PROMPT>")
            self.assertEqual((self.work / "fixture-answer").read_text(), "yes")
            self.assertFalse(self.lock.exists())
            self.assertFalse(self.download.exists())
            os.write(master, b"exit\n")
            _, status = os.waitpid(pid, 0)
            reaped = True
            self.assertEqual(os.waitstatus_to_exitcode(status), 0)
        finally:
            if not reaped:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
            os.close(master)
            self.stop_processes()

    def check_controlling_terminal(self, outcome):
        self.restore_download()
        child = self.download / "mount-submodule.sh"
        child.write_text(f"""#!/usr/bin/env python3
import json, os, signal, sys
from pathlib import Path
Path("fixture-child.pid").write_text(str(os.getpid()))
with os.fdopen(os.open("/dev/tty", os.O_RDWR), "r") as tty:
    Path("fixture-terminal").write_text(json.dumps([
        os.getsid(0), os.getpgrp(), os.tcgetpgrp(0), os.tcgetpgrp(tty.fileno())]))
    signal.signal(signal.SIGINT, lambda sig, frame: sys.exit(128 + sig))
    os.write(tty.fileno(), b"TTY answer: ")
    answer = tty.readline().strip()
    Path("fixture-answer").write_text(answer)
sys.exit(23 if {outcome!r} == "failure" else 0)
""")
        child.chmod(0o755)
        harness = f"""
import json, os, subprocess, sys
from pathlib import Path
with os.fdopen(os.open("/dev/tty", os.O_RDWR), "r") as tty:
    original = os.tcgetpgrp(tty.fileno())
    Path("fixture-caller-session").write_text(str(os.getsid(0)))
    proc = subprocess.Popen(["bash", {str(self.download / 'mount-loa.sh')!r}, "--no-commit"],
        env=dict(os.environ, _LOA_MOUNT_TMPDIR={str(self.download)!r}))
    Path("fixture-wrapper.pid").write_text(str(proc.pid))
    status = proc.wait()
    Path("fixture-restored").write_text(json.dumps([status, original, os.tcgetpgrp(tty.fileno())]))
    os.write(tty.fileno(), b"Restored answer: ")
    Path("fixture-restored-answer").write_text(tty.readline().strip())
"""
        pid, master = pty.fork()
        if pid == 0:
            os.chdir(self.work)
            os.execvp("python3", ["python3", "-c", harness])
        reaped = False
        try:
            self.read_pty_until(master, b"TTY answer:")
            session, group, stdin_foreground, tty_foreground = json.loads(
                (self.work / "fixture-terminal").read_text())
            self.assertEqual(session, int((self.work / "fixture-caller-session").read_text()))
            self.assertEqual(group, stdin_foreground)
            self.assertEqual(group, tty_foreground)
            if outcome == "terminal_int":
                os.write(master, b"\x03")
            elif outcome == "parent_term":
                os.kill(int((self.work / "fixture-wrapper.pid").read_text()), signal.SIGTERM)
            else:
                os.write(master, b"yes\n")
            self.read_pty_until(master, b"Restored answer:")
            status, original, restored = json.loads((self.work / "fixture-restored").read_text())
            self.assertEqual(status, {"success": 0, "failure": 23, "terminal_int": 130,
                                      "parent_term": 143}[outcome])
            self.assertEqual(original, restored)
            os.write(master, b"restored\n")
            self.wait_for(lambda: (self.work / "fixture-restored-answer").exists(),
                          "caller could not read its restored controlling terminal")
            self.assertEqual((self.work / "fixture-restored-answer").read_text(), "restored")
            _, status = os.waitpid(pid, 0)
            reaped = True
            self.assertEqual(os.waitstatus_to_exitcode(status), 0)
            self.assertFalse(self.lock.exists())
            self.assertFalse(self.download.exists())
        finally:
            if not reaped:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
            os.close(master)
            self.stop_processes()
            if self.lock.is_dir():
                shutil.rmtree(self.lock)

    def check_cancellation(self, sig):
        # setUp-like isolation for each signal because successful cleanup removes
        # the downloaded scripts. Keep all process handles for failure cleanup.
        self.restore_download()
        child = self.download / "mount-submodule.sh"
        child.write_text("""#!/usr/bin/env python3
import os, signal, subprocess, sys, time
from pathlib import Path
role = "leaf" if len(sys.argv) > 1 and sys.argv[1] == "leaf" else "child"
def stop(sig, frame):
    Path("fixture-" + role + "-signal").write_text(str(sig))
    while not Path("fixture-" + role + "-exit").exists():
        time.sleep(0.01)
    Path("fixture-" + role + "-stopped").touch()
    sys.exit(0)
for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
    signal.signal(sig, stop)
Path("fixture-" + role + ".pid").write_text(str(os.getpid()))
if role == "child":
    subprocess.Popen([sys.executable, __file__, "leaf"])
Path("fixture-" + role + "-ready").touch()
while True:
    time.sleep(0.01)
""")
        child.chmod(0o755)
        proc = self.start_mount()
        self.wait_for(lambda: (self.work / "fixture-leaf-ready").exists(), "child never ready")
        os.kill(proc.pid, sig)
        try:
            self.wait_for(
                lambda: all((self.work / f"fixture-{role}-signal").exists()
                            for role in ("child", "leaf")),
                "cancellation was not forwarded to the child process group",
            )
            self.assertIsNone(proc.poll())
            self.assertTrue(self.lock.exists())
            self.assertTrue(self.download.exists())
            for role in ("child", "leaf"):
                self.assertEqual(int((self.work / f"fixture-{role}-signal").read_text()), sig)
            (self.work / "fixture-child-exit").touch()
            self.wait_for(lambda: (self.work / "fixture-child-stopped").exists(), "child did not stop")
            time.sleep(0.1)
            self.assertIsNone(proc.poll(), "parent exited while descendant was still working")
            self.assertTrue(self.lock.exists(), "lock released while descendant was still working")
            self.assertTrue(self.download.exists())
            # Repeated cancellation must not interrupt the termination wait.
            os.kill(proc.pid, sig)
            (self.work / "fixture-leaf-exit").touch()
            out, err = proc.communicate(timeout=5)
            self.assertEqual(proc.returncode, 128 + sig, out + err)
            self.assertTrue((self.work / "fixture-leaf-stopped").exists())
            self.assertFalse(self.lock.exists())
            self.assertFalse(self.download.exists())
        finally:
            # Ensure a failed baseline leaves no long-running fixture children.
            (self.work / "fixture-child-exit").touch()
            (self.work / "fixture-leaf-exit").touch()
            self.stop_processes()
            if self.lock.is_dir():
                shutil.rmtree(self.lock)
            elif self.lock.exists():
                self.lock.unlink()

    def lock_script(self):
        text = SOURCE.read_text()
        text = text[text.index("# === Mount Lock"):text.index("# === Graceful Degradation")]
        script = self.root / "lock-functions.sh"
        script.write_text(text)
        return str(script)

    def test_competing_acquisitions_have_one_owner(self):
        script = self.lock_script()
        # Pause both writers at parent-directory creation, in the original
        # absence-check/write gap. Hold the winner until both results exist.
        harness = r'''
set -euo pipefail
err() { printf '%s\n' "$*" >&2; exit 1; }
warn() { :; }
source "$1"
caller="$2"
mkdir() {
    if [[ "${1:-}" == "-p" ]]; then
        command mkdir "$@"
        touch "$caller-at-create"
        while [[ ! -e one-at-create || ! -e two-at-create ]]; do sleep 0.01; done
    else
        command mkdir "$@"
    fi
}
while [[ ! -e start ]]; do sleep 0.01; done
acquire_mount_lock
touch "$2-owned"
while [[ ! -e finish ]]; do sleep 0.01; done
release_mount_lock
'''
        for name in ("one", "two"):
            self.processes.append(subprocess.Popen(
                ["bash", "-c", harness, "_", script, name],
                cwd=self.work, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            ))
        (self.work / "start").touch()
        try:
            self.wait_for(lambda: len(list(self.work.glob("*-owned"))) >= 1, "no lock owner")
            self.wait_for(
                lambda: any(p.poll() is not None for p in self.processes)
                or len(list(self.work.glob("*-owned"))) == 2,
                "second caller never resolved acquisition",
            )
            self.assertEqual(len(list(self.work.glob("*-owned"))), 1, "both mounts acquired the lock")
        finally:
            (self.work / "finish").touch()
        results = [p.communicate(timeout=5) for p in self.processes]
        self.assertEqual(sorted(p.returncode for p in self.processes), [0, 1], results)
        self.assertFalse(self.lock.exists())

    def test_nonowner_and_replacement_lock_are_preserved(self):
        script = self.lock_script()
        result = subprocess.run(["bash", "-c", r'''
set -euo pipefail
err() { exit 1; }
warn() { :; }
source "$1"
acquire_mount_lock
bash -c 'source "$1"; release_mount_lock' _ "$1"
[[ -e "$MOUNT_LOCK_FILE" ]] || exit 90
mv "$MOUNT_LOCK_FILE" original-lock
mkdir "$MOUNT_LOCK_FILE"
printf 'different-owner\n' > "$MOUNT_LOCK_FILE/owner"
release_mount_lock
[[ "$(cat "$MOUNT_LOCK_FILE/owner")" == different-owner ]]
''', "_", script], cwd=self.work, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_legacy_stale_lock_is_not_unsafely_reclaimed(self):
        self.lock.parent.mkdir(exist_ok=True)
        self.lock.write_text("99999999\n")
        script = self.lock_script()
        result = subprocess.run(["bash", "-c", r'''
set -euo pipefail
err() { printf '%s\n' "$*" >&2; exit 1; }
warn() { :; }
source "$1"
acquire_mount_lock
''', "_", script], cwd=self.work, capture_output=True, text=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.lock.read_text(), "99999999\n")
        self.assertIn("inspect", result.stderr.lower())

    def test_legacy_claude_marker_is_preserved_after_lock_migration(self):
        legacy = self.work / ".claude/.mount-lock"
        legacy.parent.mkdir()
        legacy.write_text("99999999\n")
        proc = self.start_mount()
        out, err = proc.communicate(timeout=5)
        self.assertEqual(proc.returncode, 1, out + err)
        self.assertEqual(legacy.read_text(), "99999999\n")
        self.assertIn("legacy", err)

    def test_unconfirmed_supervisor_completion_retains_resources(self):
        for token in ("missing", "wrong"):
            with self.subTest(token=token):
                self.restore_download()
                child = self.download / "mount-submodule.sh"
                child.write_text("#!/usr/bin/env bash\ntouch fixture-unexpected-child\n")
                child.chmod(0o755)
                helper = self.download / "lib/mount-supervisor.py"
                helper.write_text(
                    "import sys\nfrom pathlib import Path\n" +
                    ("Path(sys.argv[1]).write_text('another-owner')\n" if token == "wrong" else "")
                )
                proc = self.start_mount()
                out, err = proc.communicate(timeout=5)
                self.assertEqual(proc.returncode, 125, out + err)
                self.assertTrue(self.lock.exists())
                self.assertTrue(self.download.exists())
                self.assertFalse((self.work / "fixture-unexpected-child").exists())
                self.assertIn("retaining lock", out + err)
                shutil.rmtree(self.lock)

    def test_failed_or_ambiguous_process_inspection_retains_resources(self):
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        for output in ("exit 1", "exit 0", "printf 'invalid\\n'"):
            with self.subTest(ps=output):
                self.restore_download()
                ps = bin_dir / "ps"
                ps.write_text("#!/usr/bin/env bash\n" + output + "\n")
                ps.chmod(0o755)
                child = self.download / "mount-submodule.sh"
                child.write_text("#!/usr/bin/env bash\nexit 0\n")
                child.chmod(0o755)
                proc = self.start_mount({"PATH": str(bin_dir) + ":" + os.environ["PATH"]})
                out, err = proc.communicate(timeout=5)
                self.assertEqual(proc.returncode, 125, out + err)
                self.assertTrue(self.lock.exists())
                self.assertTrue(self.download.exists())
                self.assertFalse((self.lock / "terminated").exists())
                self.assertIn("retaining", out + err)
                shutil.rmtree(self.lock)


if __name__ == "__main__":
    unittest.main()
