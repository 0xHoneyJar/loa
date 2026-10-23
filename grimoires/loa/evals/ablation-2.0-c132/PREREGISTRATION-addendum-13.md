# Pre-registration addendum 13 — cycle-132

**Supersedes:** `REGISTRATION-11.json` sha256 `2f6909d23efcadc0c65e34c5f49811e80b4b4c927c2a37eaed49f4fe040d521b` (pipeline pin `fbd36a0c9880b244af08133013f3b6959b085c94`, tree `c1948aa7…`). **Registered as:** `REGISTRATION-12.json`. **Governing text:** `PREREGISTRATION.md` is unchanged. **Scope:** the judge sampler (`evals/harness/judge-sample.sh`) only. No arm runs it, and the pipeline pin is unchanged.

## What the pilot judge session found

The sampler drew 1,903 items from the 140 Phase 1 rows. One pilot session judged the first 64 packets, and a spot-check of its packets found that 302 of the 1,903 (16 %) print "the file is not in the PR's head tree" where the cited code should be. The cause is in how the sampler looks up a cited path: it requires an exact match under the head tree. Reviewers often cite a partial path (`flatline-orchestrator.sh:525`), and the grader accepts such a citation when the defect's file ends with it (`recall-vs-defects.sh`: `cited == defect_file or defect_file.endswith("/" + cited)`). A packet without the cited code leaves the blind judge unable to check the finding. That pushes it toward "does not describe" or "wrong", against whichever arm's reviewers cite short paths.

## What changed

The sampler resolves a cited path the way the grader does. It takes the exact path first. Failing that, it takes the labelled defect's file when that file ends with the cited path, then the unique head-tree file whose path ends with it, and maps `pr/PR.md` and `pr/head.diff` to the fixture's own files. Zero or several matches keep today's text. The packet header names the resolved path beside the cited one, and `key.json` records the resolution per item. The universe, units, strata, inclusion probabilities, item ids and packet order are byte-identical to the previous output, and a test proves it.

## Both reads

The pilot's 64 labels were judged on the old packets. They are kept on disk as the pilot and are not used, and every chunk is judged on the regenerated packets. The pilot's spend stays in the meter.

## Why this is a correction, not a design change

Under §9 the judge is the semantic audit of the grader's proximity rule, and it can only do that with the code the grader matched in front of it. Nothing about sampling, strata, the judge model, the agreement measures or the corrections changes.
