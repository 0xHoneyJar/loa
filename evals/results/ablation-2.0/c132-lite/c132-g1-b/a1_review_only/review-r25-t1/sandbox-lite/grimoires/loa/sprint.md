# Sprint Plan

## Sprint 1: Review the pull request in pr/

The change under review is `pr/head.diff` (unified diff, base to head). The files before the change are under `pr/base/`, after it under `pr/head/`; `pr/PR.md` is the pull request description and is the implementation report for this sprint.

### Tasks

- [x] Task 1.1: the change in `pr/head.diff`

### Review scope

The gates review `pr/head.diff` (pass `--diff-file pr/head.diff` to the adversarial review). Cite findings as `head/<path>:<line>` with lines from the `pr/head/` files.

## Success Criteria

review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict
