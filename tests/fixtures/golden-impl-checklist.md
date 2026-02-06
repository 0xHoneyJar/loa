| # | Check | Required? | How to Verify |
|---|-------|-----------|---------------|
| 1 | Sprint plan exists | ALWAYS | `test -f grimoires/loa/sprint.md` |
| 2 | Beads tasks created | When beads HEALTHY | `br list` shows sprint tasks |
| 3 | No unaddressed audit feedback | ALWAYS | Check `auditor-sprint-feedback.md` |
| 4 | No unaddressed review feedback | ALWAYS | Check `engineer-feedback.md` |
| 5 | On feature branch | ALWAYS | `git branch --show-current` is not main/master |
| 6 | Using /run (not direct /implement) | For autonomous/simstim | /run wraps implement+review+audit |
