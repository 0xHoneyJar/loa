# Pre-registration addendum 14 — cycle-132

**Supersedes:** `REGISTRATION-12.json` sha256 `9a0dda4bcedcf319f08a08774b049657020739040f5eaa457c52fb5046169e7a` (pipeline pin `fbd36a0c9880b244af08133013f3b6959b085c94`, tree `fc31c990…`). **Registered as:** `REGISTRATION-13.json`. **Governing text:** `PREREGISTRATION.md` is unchanged. **Scope:** the judge's packet content (`evals/harness/judge-sample.sh`, the new `evals/harness/defect-descriptions.py`) and the judge report's title (`judge_agree.py`). No arm runs these, and the pipeline pin, the corpus, the manifests and the grader are unchanged.

## What the first judge run showed

The first full judge run labelled all 1,903 items. Agreement with the grader was low (κ 0.22) and the judge-corrected recall collapsed for every arm. Reading the packets showed why: every pair packet described its labelled defect only by its id (`Description: V03`). The v2 manifests carry no description field, so the sampler fell back to the id, and the judge was asked whether a finding describes a defect without being told what the defect is. Those labels measure the packet, not the grader. They are kept and reported as an invalid run, and they enter no read.

## What changed

`defect-descriptions.py` builds one description per registered defect from the blind Phase 0 annotators' own records. For each hunk or incident the manifest names as the defect's source, it takes the description both annotators wrote (deduplicated, without their identity) and the lead's adjudication reason when one exists, and appends the manifest's category and severity. The file lives outside the hashed corpus, at `grimoires/loa/reports/ablation-2.0/c132-judge-inputs/defect-descriptions.json`, and is committed. `judge-sample.sh --descriptions` puts that text in each pair packet and records the description's source per item. The universe, units, strata, inclusion probabilities, item ids and order are byte-identical to the first run, so the second run judges the same sampled items. The judge prompt says the description summarises the change that later fixed the defect. `judge_agree.py` titles its report with the grader version found on the rows (the title hard-coded 1.3.2).

## Both reads

The first run's result (`judge/run-1-no-descriptions/`) is reported beside the second run's, as the record of a packet defect. Only the second run is the §9 judge.

## Why this is a correction, not a design change

§9 asks whether a finding describes the labelled defect, and that question needs the defect's description. The descriptions come from the same blind annotation that produced the key, so the judge gains no information the key's authors did not have, and nothing about sampling, strata, the judge model or the measures changes.
