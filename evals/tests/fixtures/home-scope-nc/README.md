# home-scope negative control (cycle-133 Sprint 274 Task 3.1, SDD C-10, PRD FR-10 AC 1)

One PR (`pr-nc/`: `head.diff`, `head/`, `base/`, `PR.md`) and one pinned framework (`pinned/`) that hold
**distinct bytes for the same path**, `.claude/protocols/nc-guard.md`:

| copy | line 8 |
|---|---|
| `pr-nc/base/` | the original rule |
| `pr-nc/head/` | the planted defect (`manifests/pr-nc.json`, `NC1`, anchor 8) |
| `pinned/` | the later fix, plus one inserted line: both are later-only lines |

`evals/tests/sandbox-mount-home-scope.bats` HS-8 commits `pinned/` as the source tree. Under the cycle-132
mount (`pinned-root`) the workspace root's `.claude/protocols/nc-guard.md` holds the pinned bytes, so a reviewer
Read of it exposes the fix and the grader's `oracle_scan` must fire (`oracle_exposed_defects` = `d1`). Under
`home-scope` the root holds the PR's head bytes, the same Read exposes nothing, and took-effect clause (f)
credits the read in `pr_bytes_read`.

`SHA256SUMS` pins every file of this fixture (the test verifies it first); regenerate it only when the
fixture is deliberately changed:

    cd evals/tests/fixtures/home-scope-nc
    python3 -I -c 'import hashlib,os
    for r,d,f in sorted(os.walk(".")):
        d.sort()
        for n in sorted(f):
            p=os.path.join(r,n)[2:]
            if p not in ("SHA256SUMS","README.md"): print(hashlib.sha256(open(p,"rb").read()).hexdigest()+"  "+p)' > SHA256SUMS
