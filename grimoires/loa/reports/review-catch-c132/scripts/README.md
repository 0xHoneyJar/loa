# cycle-132 Phase 1 drivers (copies)

Lead-side drivers that ran the Phase 1 batches, looks, judge and registrations. They were kept under `~/.cache/loa/cycle-132/scripts/` during the cycle and are copied here verbatim so that a fresh clone can re-run every step. Paths inside them are absolute to the lead's checkout (`/home/merlin/Documents/thj/code/loa`), so a reproducer substitutes its own root.

| script | what it does |
|---|---|
| `batch-c132.sh <mode> <pin> [--resume …]` | one Phase 1 batch (`smoke`, `smoke3`, `smoke4`, `g{1,2,3}-{a1,a2,a3,b}`) through `evals/harness/run-ablation.sh` under the binding registration |
| `look.sh <k> [name]` | the pre-registered look k over groups 1..k (`reads-c132.py --make-inputs`, then `--look k`) |
| `final.sh <placebo\|judge-sample\|final>` | the Sprint 271 reads and the judge sample |
| `run-judge.sh` | the blind judge: packets in chunks of ≤ 64, one `blind-session.sh` per chunk, three at a time, idempotent |
| `register.sh`, `register-addendum.sh`, `register-addendum-analysis.sh` | build `REGISTRATION*.json` (the analysis-only variant keeps the pipeline pin and verifies the pipeline paths are byte-identical) |
| `batch-scans.py`, `batch-scans-md.py` | the contamination hand-read table |
| `smoke-check.sh` | the smoke summary |
| `prompts/judge.md`, `prompts/annotator.md` | the blind judge and annotator prompts |
| `run-annotation.sh`, `adjudicate.py`, `dispute-dump.py` | Phase 0 (Sprint 269): the blind two-annotator runs, dispute dump and lead adjudication |
