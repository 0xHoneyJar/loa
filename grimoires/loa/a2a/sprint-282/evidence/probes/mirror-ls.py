#!/usr/bin/env python3
"""Build two mirrors (old = a git rev, new = the working tree) under /tmp/c137-par-ls/{old,new}:
real .claude/scripts, .claude/scripts/lib and .claude/hooks/quality dirs holding the changed scripts (and the
unchanged entry points that source them) as files, every other script/lib/hook dir and top-level entry symlinked
to the live checkout. Python writes avoid the shell fence on redirects into paths containing .claude/."""
import pathlib, shutil, subprocess, sys
ROOT = pathlib.Path('/home/merlin/Documents/thj/code/loa'); P = pathlib.Path('/tmp/c137-par-ls')
OLD_REV = sys.argv[1] if len(sys.argv) > 1 else '747b5db0d'
# files whose OLD side comes from OLD_REV (changed by Sprint 282) and entry points copied as real files on both sides
FILES = ['.claude/scripts/loa-status.sh', '.claude/scripts/audit-envelope.sh', '.claude/scripts/lib/agy-gate-lib.sh',
         '.claude/scripts/lib/profile-lib.sh', '.claude/scripts/run-preflight.sh', '.claude/hooks/quality/karpathy-surgical-diff-check.sh']
shutil.rmtree(P, ignore_errors=True)
for side in ('old', 'new'):
    base = P / side
    (base / '.claude/scripts/lib').mkdir(parents=True); (base / '.claude/hooks/quality').mkdir(parents=True)
    for rel in FILES:
        dst = base / rel
        if side == 'old':
            dst.write_bytes(subprocess.run(['git', '-C', str(ROOT), 'show', f'{OLD_REV}:{rel}'], check=True, capture_output=True).stdout)
        else:
            dst.write_bytes((ROOT / rel).read_bytes())
        dst.chmod(0o755)
    for entry in (ROOT / '.claude/scripts').iterdir():
        rel = f'.claude/scripts/{entry.name}'
        if rel in FILES or entry.name == 'lib':
            continue
        (base / rel).symlink_to(entry)
    for entry in (ROOT / '.claude/scripts/lib').iterdir():
        rel = f'.claude/scripts/lib/{entry.name}'
        if rel in FILES:
            continue
        (base / rel).symlink_to(entry)
    for entry in (ROOT / '.claude/hooks').iterdir():
        if entry.name == 'quality':
            for q in entry.iterdir():
                rel = f'.claude/hooks/quality/{q.name}'
                if rel in FILES:
                    continue
                (base / rel).symlink_to(q)
            continue
        (base / '.claude/hooks' / entry.name).symlink_to(entry)
    for d in ('adapters', 'defaults', 'data', 'schemas', 'protocols', 'loa', 'skills', 'settings.json'):
        src = ROOT / '.claude' / d
        if src.exists():
            (base / '.claude' / d).symlink_to(src)
    for top in ('grimoires', '.run', '.loa.config.yaml', '.beads', 'CHANGELOG.md', 'README.md', '.loa-version.json', '.git', 'tools', 'tests'):
        src = ROOT / top
        if src.exists():
            (base / top).symlink_to(src)
print(f'mirrors built under {P} (old={OLD_REV}, new=working tree)')
