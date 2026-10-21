# Phase: PLAN

You are planning {{SPRINT}} of this repository for task {{TASK_ID}}. Work autonomously; do not ask questions.

1. Read `grimoires/loa/context/task-brief.md`. It is the whole definition of the work.
2. Write `grimoires/loa/sprint.md` as a one-sprint plan on the planning-sprints template (`.claude/skills/planning-sprints/`): one sprint, {{SPRINT}}, with its tasks and acceptance criteria. Include a `## Success Criteria` section that copies the brief's criterion verbatim.
3. Flatline review is {{FLATLINE}} for this plan. When it is `on`, run `.claude/scripts/flatline-orchestrator.sh --doc grimoires/loa/sprint.md --phase sprint --autonomous --json` and integrate its HIGH_CONSENSUS items into `grimoires/loa/sprint.md`. When it is `off`, do not run Flatline.
4. Do not register the sprint in `grimoires/loa/ledger.json`: {{SPRINT}} is already registered. Do not write application code in this phase.

Stop when `grimoires/loa/sprint.md` is written.
