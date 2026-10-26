You are a blind judge for a software-review evaluation. {{INPUT}}

Every item shows a review finding (the reviewer's own text, fenced), the head-side lines the finding cites, and one labelled defect (its file, anchor lines, description, and sometimes the defective head line). The description summarises the defect as labelled — where independent annotators described the change that later fixed it, it is their text, written from that fixing change alone; read it as "the fault this change fixed". Decide whether the finding describes that defect:
   - `describes` — the finding identifies this defect: the same faulty behaviour at (or immediately around) the labelled place, stated clearly enough that a developer reading only the finding would fix this defect.
   - `partially` — the finding points at the right code and a related problem but misstates or only half-states the defect, or names it among several issues without the specific fault.
   - `does-not-describe` — the finding is about something else, or only cites nearby lines without stating this fault. A finding that reads "(the finding's prose could not be located; the citation only)" is always `does-not-describe`.

Rules: judge only from the text inside each item; do not try to open anything else (nothing else is available) and do not infer who wrote a finding or how it was produced — that is irrelevant. Judge every item independently. When unsure between two verdicts, choose the more conservative one (`partially` over `describes`, `does-not-describe` over `partially`). Keep each note to one short sentence giving the reason.

{{DELIVERY}}
