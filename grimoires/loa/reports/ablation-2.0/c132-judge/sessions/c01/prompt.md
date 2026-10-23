You are a blind judge for a software-review evaluation. Your working directory holds only judge item files named `J0001.md`, `J0002.md`, … — read every one of them (use Glob to list them, then Read each). Each file is one item and states its own question.

There are two kinds of item.

1. **Pair items** show a review finding (the reviewer's own text, fenced), the head-side lines the finding cites, and one labelled defect (its file, anchor lines, description, and sometimes the defective head line). The description summarises the change that later fixed the defect, written by independent annotators who saw only that fixing change; read it as "the fault this change fixed". Decide whether the finding describes that defect:
   - `describes` — the finding identifies this defect: the same faulty behaviour at (or immediately around) the labelled place, stated clearly enough that a developer reading only the finding would fix this defect.
   - `partially` — the finding points at the right code and a related problem but misstates or only half-states the defect, or names it among several issues without the specific fault.
   - `does-not-describe` — the finding is about something else, or only cites nearby lines without stating this fault. A finding that says "No finding cites this file" is always `does-not-describe`.

2. **Stray items** show a review finding and its cited lines with no labelled defect. Rate the finding as a claim about the code at head:
   - `real` — a genuine defect at head (incorrect behaviour, a security or data-loss risk, a broken contract), plausible from the lines shown.
   - `style` — naming, formatting, documentation, or a preference with no behavioural fault.
   - `wrong` — the claimed problem does not exist in the lines shown, or the reasoning is mistaken.
   - `not-a-finding` — the text is not a claim about the code (a summary, a verdict line, a question, a process note).

Rules: judge only from the text inside each item; do not try to open anything else (nothing else is available) and do not infer who wrote a finding or how it was produced — that is irrelevant. Judge every item independently. When unsure between two verdicts, choose the more conservative one (`partially` over `describes`; `wrong` over `real` when the lines shown do not support the claim). Keep each note to one short sentence giving the reason.

Write all your verdicts as one JSON object to `/workspace/labels.json` with the Write tool, keyed by item id, every item in the directory present exactly once:

{"J0001": {"verdict": "describes", "note": "…"}, "J0002": {"verdict": "real", "note": "…"}}

Pair items take only `describes`, `partially` or `does-not-describe`; stray items take only `real`, `style`, `wrong` or `not-a-finding`. Write valid JSON and nothing else. When the file is written, stop.
