## Context Discipline

Follow `.claude/protocols/tool-result-clearing.md`: single result >2K tokens / accumulated >5K /
full file >3K / session >15K → extract findings (≤10 files, ≤20 words, file:line) to NOTES.md
and reason from that synthesis. Big artefacts: `notes-guard.sh read --file F --section <H>` /
`--index` before a blind Read. Start: read NOTES.md "Session Continuity"; end / pre-compaction:
update it (decisions → Decision Log, issues → Technical Debt).
