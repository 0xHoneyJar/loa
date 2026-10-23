# Pre-registration addendum 12 — cycle-132

**Supersedes:** `REGISTRATION-10.json` sha256 `13cbd850f82513e8788322e9ea60ac28bba044a14c83b42e11e311611a19401c` (pipeline pin `fbd36a0c9880b244af08133013f3b6959b085c94`, analysis tree `0d1fe51e…`). **Registered as:** `REGISTRATION-11.json`. **Governing text:** `PREREGISTRATION.md` is unchanged; §9's "packets blind to arm, trial and decision" is read with the PR-native exemption below. **Scope:** the judge sampler (`evals/harness/judge-sample.sh`) only. No arm runs it; the pipeline pin stays `fbd36a0c…` and every other harness file is byte-identical to the pin.

## What the first sampler run found

On the Phase 1 rows the sampler refused to write any packet: `packet J0008 would carry a provenance field (a1_full)`. It already removes the quoted head-tree lines from its provenance scan, but not the reviewer's finding prose, and that prose quotes the pull request under review. Seven registered pull requests (pr-22 … pr-28) built this evaluation harness, so their code and documents name the arms. The arms never see their own names (the runner's prompt and sandbox guard, addendum 1), so an arm id in a finding comes from the pull request and does not reveal which arm wrote it.

## What changed

An arm-id token in a packet's scan text is exempt when the same token occurs in the task's pull-request fixture (`PR.md`, `head.diff`, and the regular files under `head/` and `base/`). A provenance field line (`arm:`, `trial:`, `batch:`, `run_id:`, `stratum:`, `grader decision:`) is exempt only when the whole line occurs verbatim in that fixture. Batch names, run ids and cell keys are never exempt. Every exemption is recorded in `key.json` (`provenance_exempt`, with item, token and reason `pr_native`), and packets are written unchanged. The bats suite covers each case (JS-9 … JS-13).

## Why this is a correction, not a design change

It is the addendum-1 correction applied to the one remaining guard that scanned pull-request text: the guard protects the judge from learning a finding's arm, and a token the pull request itself contains cannot tell it that. Strata, sample sizes, inclusion probabilities, the judge model, the agreement measures and the Horvitz–Thompson corrections are untouched, and no judge label exists yet.

## Also recorded: the sample size the registered rule produces

§9 draws `min(all, 10)` per stratum over arm × PR × class, with a total of at least 150. On the Phase 1 rows that is about 1,750 items, which is far above the 150 floor. The rule stands as registered. The §7 judge reserve (USD 30) was sized on the floor, so the judge's spend runs over its reserve. It stays inside the binding cap, and the spend table reports it.
