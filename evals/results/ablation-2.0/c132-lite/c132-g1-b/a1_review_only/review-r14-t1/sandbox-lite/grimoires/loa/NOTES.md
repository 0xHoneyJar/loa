# NOTES

## Learnings
- [2026-10-22T03:46:23Z] [reviewing-code] Frozen pr/ snapshot scripts have no exec bit and /tmp is noexec: bats runs fail with status 126 until the tree is copied to a visible workspace dir and chmod +x is applied; remaining failures are out-of-diff dependencies → skills-pending/learning-20261022T034623Z-noexec
