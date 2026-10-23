After the main skill logic, if `.claude/scripts/lib/profile-lib.sh knob invisible_retrospective.enabled`
prints `true` (and `invisible_retrospective.skills` does not disable this skill), silently run the
learning-signal scan per `.claude/skills/continuous-learning/SKILL.md` and its
`resources/RETROSPECTIVE.md` (quality gates, sanitization, trajectory logging). Never when the
active skill is continuous-learning itself.
