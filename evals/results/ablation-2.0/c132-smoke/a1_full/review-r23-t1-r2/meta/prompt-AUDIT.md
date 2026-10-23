# Phase: AUDIT

Run `/audit-sprint sprint-1` for task review-r23. Work autonomously; do not ask questions.

The change under review is the pull request in `pr/`: `pr/head.diff` is the complete change (base to head), `pr/base/` and `pr/head/` hold every touched file before and after it, and `pr/PR.md` is its description (also carried as the implementation report). Cite findings as `head/<path>:<line>` with line numbers from the `pr/head/` files. When your skill runs the adversarial dissent, pass `--diff-file pr/head.diff`.

The sprint is defined by `grimoires/loa/sprint.md`; when that file does not exist, the brief at `grimoires/loa/context/task-brief.md` is the sprint's definition. Write your feedback to `grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md` and end it with the LOA-VERDICT trailer line your skill specifies. Stop when the feedback file is written.
