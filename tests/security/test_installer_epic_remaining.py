"""Offline regressions for #1168's remaining download/relocation defects."""

import hashlib
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
SCRIPTS = REPO / ".claude/scripts"


class InstallerRemaining(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        EPIC_CASE=str(self.root), TMPDIR=str(self.root))
        self.env.pop("_LOA_MOUNT_REEXEC", None)

    def tool(self, name, text):
        path = self.bin / name
        path.write_text("#!/usr/bin/env bash\nset -eu\n" + text)
        path.chmod(0o755)

    def pipe_install(self, failed=""):
        self.tool("curl", """
out=""; url=""
while (( $# )); do
  case "$1" in -o) out="$2"; shift 2;; *) url="$1"; shift;; esac
done
if [[ -n "${EPIC_FAILED:-}" && "$url" == *"/${EPIC_FAILED}" ]]; then
  printf 'partial download\\n' > "$out"
  exit 22
fi
printf '#!/usr/bin/env bash\\nprintf reached > "$EPIC_CASE/child"\\n' > "$out"
""")
        return subprocess.run(
            ["bash", "-s", "--", "--ref", "main"],
            input=(SCRIPTS / "mount-loa.sh").read_text(),
            cwd=self.root, env=dict(self.env, EPIC_FAILED=failed),
            text=True, capture_output=True,
        )

    def test_auxiliary_download_failure_never_executes_partial_install(self):
        for name in ("bootstrap.sh", "bash-version-guard.sh", "lib/symlink-manifest.sh",
                     "lib/scaffold-post-merge-workflow.sh", "lib/portable-realpath.sh"):
            with self.subTest(name=name):
                (self.root / "child").unlink(missing_ok=True)
                proc = self.pipe_install(name)
                self.assertNotEqual(proc.returncode, 0, proc.stdout)
                self.assertFalse((self.root / "child").exists())
                self.assertIn(name, proc.stderr)

    def test_complete_pipe_download_reaches_child(self):
        proc = self.pipe_install()
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertTrue((self.root / "child").exists())

    def dependency_install(self, payload):
        expected = b"verified release fixture\n"
        digest = hashlib.sha256(expected).hexdigest()
        source = (SCRIPTS / "mount-loa.sh").read_text()
        function = re.search(r"^auto_install_deps\(\) \{.*?^\}", source, re.M | re.S).group()
        # Use a small local release artifact with its actual checksum. This
        # changes only fixture pins, not the production verification branch.
        function = re.sub(r"\b[0-9a-f]{64}\b", digest, function)
        (self.root / "payload").write_bytes(payload)
        self.tool("curl", """
out=""
while (( $# )); do
  case "$1" in -o) out="$2"; shift 2;; *) shift;; esac
done
[[ "$out" != /usr/local/bin/yq ]] || out="$EPIC_CASE/installed"
cp "$EPIC_CASE/payload" "$out"
""")
        self.tool("sudo", """
printf '%s\\n' "$*" >> "$EPIC_CASE/sudo.log"
case "$1" in
  curl) shift; exec curl "$@";;
  chmod) exit 0;;
  install) cp "${@: -2:1}" "$EPIC_CASE/installed";;
  *) exit 99;;
esac
""")
        harness = """
set -euo pipefail
NO_AUTO_INSTALL=false
detect_os() { printf linux-apt; }
uname() { printf x86_64; }
command() {
  if [[ "$1" == -v && "$2" == yq ]]; then return 1; fi
  builtin command "$@"
}
step() { :; }
log() { :; }
warn() { printf '%s\\n' "$*" >&2; }
err() { printf '%s\\n' "$*" >&2; exit 1; }
sha256_portable() { /usr/bin/sha256sum "$@"; }
""" + function + "\nauto_install_deps\n"
        return subprocess.run(["bash", "-c", harness], cwd=self.root, env=self.env,
                              text=True, capture_output=True)

    def test_yq_checksum_mismatch_cannot_install_or_chmod_download(self):
        proc = self.dependency_install(b"substituted release bytes\n")
        self.assertFalse((self.root / "installed").exists(), proc.stdout + proc.stderr)
        self.assertIn("checksum", proc.stderr.lower())
        self.assertFalse((self.root / "sudo.log").exists())

    def test_verified_yq_uses_unprivileged_download_then_install(self):
        payload = b"verified release fixture\n"
        proc = self.dependency_install(payload)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual((self.root / "installed").read_bytes(), payload)
        calls = (self.root / "sudo.log").read_text()
        self.assertIn("install -m 0755", calls)
        self.assertNotIn("curl ", calls)

    def relocation(self, copy_mode="", rename_fail=False, target_arrival=False):
        source = (SCRIPTS / "mount-submodule.sh").read_text()
        function = source.split("relocate_memory_stack() {", 1)[1].split(
            "\n# Issue #669", 1)[0]
        function = "relocate_memory_stack() {" + function
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        if copy_mode:
            self.tool("cp", """
printf '%s\\n' "$*" > "$EPIC_CASE/copy.args"
[[ ! -e .loa-state ]] || printf exposed > "$EPIC_CASE/exposed"
/bin/cp "$@"
dest="${@: -1}"
if [[ "$EPIC_COPY_MODE" == corrupt ]]; then
  printf CORRUPTED > "$dest/data"
fi
if [[ "$EPIC_COPY_MODE" == root-mode ]]; then chmod 0777 "$dest"; fi
[[ "$EPIC_COPY_MODE" != fail ]] || exit 23
""")
        if rename_fail:
            # The actual publish rename must fail without source removal.
            self.tool("python3", "exit 23\n")
        if target_arrival:
            wrapper = self.bin / "python3"
            wrapper.write_text("""#!/usr/bin/python3
import ctypes, os, sys
from pathlib import Path
sys.argv.pop(0)
real_rename = os.rename
real_cdll = ctypes.CDLL
def arrive():
    target = Path(sys.argv[3])
    target.mkdir(mode=0o700)
    Path(os.environ["EPIC_CASE"], "target-inode").write_text(str(target.stat().st_ino))
def rename(*args):
    arrive()
    return real_rename(*args)
class Library:
    def __init__(self, *args, **kwargs):
        self.library = real_cdll(*args, **kwargs)
    def __getattr__(self, name):
        function = getattr(self.library, name)
        if name not in ("renameat2", "renamex_np"):
            return function
        def invoke(*args):
            arrive()
            return function(*args)
        return invoke
os.rename = rename
ctypes.CDLL = Library
exec(compile(sys.stdin.read(), "<relocation>", "exec"))
""")
            wrapper.chmod(0o755)
        harness = """
set -euo pipefail
step() { :; }
log() { :; }
warn() { printf '%s\\n' "$*" >&2; }
err() { printf '%s\\n' "$*" >&2; exit 1; }
""" + function + "\nrelocate_memory_stack\n"
        return subprocess.run(["bash", "-c", harness], cwd=self.root,
                              env=dict(self.env, EPIC_COPY_MODE=copy_mode),
                              text=True, capture_output=True)

    def memory(self):
        path = self.root / ".loa"
        path.mkdir()
        (path / "data").write_text("original\n")
        return path

    def test_existing_target_is_preserved_and_not_merged(self):
        source = self.memory()
        target = self.root / ".loa-state"
        target.mkdir()
        (target / "sentinel").write_text("existing\n")
        proc = self.relocation()
        self.assertNotEqual(proc.returncode, 0)
        self.assertEqual((source / "data").read_text(), "original\n")
        self.assertEqual((target / "sentinel").read_text(), "existing\n")
        self.assertFalse((target / "data").exists())

    def test_same_count_corruption_preserves_source_and_rejects_target(self):
        source = self.memory()
        proc = self.relocation("corrupt")
        self.assertNotEqual(proc.returncode, 0, proc.stdout)
        self.assertEqual((source / "data").read_text(), "original\n")
        self.assertFalse((self.root / ".loa-state").exists())

    def test_partial_copy_failure_preserves_source(self):
        source = self.memory()
        proc = self.relocation("fail")
        self.assertNotEqual(proc.returncode, 0)
        self.assertEqual((source / "data").read_text(), "original\n")
        self.assertFalse((self.root / ".loa-state").exists())

    def test_copy_remains_private_until_verified(self):
        source = self.memory()
        (source / "empty").mkdir()
        (source / "data").chmod(0o640)
        (source / "link").symlink_to("data")
        proc = self.relocation("ok")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertFalse((self.root / "exposed").exists())
        self.assertFalse(source.exists())
        target = self.root / ".loa-state"
        self.assertEqual((target / "data").read_text(), "original\n")
        self.assertEqual((target / "data").stat().st_mode & 0o777, 0o640)
        self.assertEqual(os.readlink(target / "link"), "data")
        self.assertTrue((target / "empty").is_dir())

    def test_symlink_only_source_is_not_discarded_as_empty(self):
        source = self.root / ".loa"
        source.mkdir()
        (source / "link").symlink_to("missing")
        proc = self.relocation()
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(os.readlink(self.root / ".loa-state/link"), "missing")

    def test_failed_verification_preserves_source(self):
        source = self.memory()
        proc = self.relocation(rename_fail=True)
        self.assertNotEqual(proc.returncode, 0)
        self.assertEqual((source / "data").read_text(), "original\n")
        self.assertFalse((self.root / ".loa-state").exists())

    def test_root_only_mode_corruption_is_rejected(self):
        source = self.memory()
        source.chmod(0o700)
        proc = self.relocation("root-mode")
        self.assertNotEqual(proc.returncode, 0, proc.stdout)
        self.assertEqual(source.stat().st_mode & 0o777, 0o700)
        self.assertFalse((self.root / ".loa-state").exists())

    def test_destination_arrival_cannot_be_overwritten_at_publish(self):
        source = self.memory()
        proc = self.relocation(target_arrival=True)
        self.assertNotEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        target = self.root / ".loa-state"
        self.assertEqual(str(target.stat().st_ino), (self.root / "target-inode").read_text())
        self.assertEqual(list(target.iterdir()), [])
        self.assertEqual((source / "data").read_text(), "original\n")

    def test_source_on_another_filesystem_is_staged_at_destination(self):
        shared = Path("/dev/shm")
        if not shared.is_dir() or shared.stat().st_dev == self.root.stat().st_dev:
            self.skipTest("second writable filesystem unavailable")
        try:
            other = tempfile.TemporaryDirectory(prefix="loa-relocation-test-", dir=shared)
        except OSError:
            self.skipTest("second filesystem is not writable")
        self.addCleanup(other.cleanup)
        external = Path(other.name)
        (external / "data").write_text("cross-filesystem\n")
        (self.root / ".loa").symlink_to(external, target_is_directory=True)
        proc = self.relocation()
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertFalse((self.root / ".loa").exists())
        self.assertEqual((self.root / ".loa-state/data").read_text(), "cross-filesystem\n")
        # Relocation removes the logical source symlink, never its external target.
        self.assertEqual((external / "data").read_text(), "cross-filesystem\n")


if __name__ == "__main__":
    unittest.main(verbosity=2)
