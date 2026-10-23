# Annotation result — pr-15

| measure | n | kappa | observed agreement |
|---|---|---|---|
| hunks | 227 | 0.9296 | 0.9692 |
| incidents | 12 | n/a | 1.0000 |
| severity | 70 | 0.7621 | 0.8714 |

- localization: 68 of 70 agreed defects overlap (share 0.9714), median anchor distance 0, 0 file mismatch(es)
- grouping: Jaccard 0.5247 (A 497 pair(s), B 398, both 308)
- items: 239; disagreements: 99; adjudicated: 99; adjudication share 0.4142
- defects: 45 (fix-commit 45); review-driven share 0.8667
- review-derived key (c131): 3 of 3 defect(s) lie within ±3 lines of a v2 defect

| defect | file | anchors | severity | label_source | agreement | review_driven | members |
|---|---|---|---|---|---|---|---|
| V01 | .claude/adapters/cheval.py | 356,1693,1694,1695,1696,2070 | medium | fix-commit | adjudicated | true | H04,H12,H14 |
| V02 | .claude/adapters/cheval.py | 783,1962,2255 | medium | fix-commit | agreed | true | H05,H13,H19 |
| V03 | .claude/adapters/cheval.py | 907,921,922,923,924 | low | fix-commit | agreed | true | H09 |
| V04 | .claude/adapters/cheval.py | 908 | low | fix-commit | agreed | true | H08 |
| V05 | .claude/adapters/cheval.py | 932,933,934,935,936,937,938,939,940 | medium | fix-commit | agreed | true | H10 |
| V06 | .claude/adapters/cheval.py | 1228,1229,2546,2547,2548,2549,2550,2551,2552 | low | fix-commit | adjudicated | true | H11,H20 |
| V07 | .claude/adapters/cheval.py | 2137,2138,2139,2140,2141 | medium | fix-commit | agreed | false | H15 |
| V08 | .claude/adapters/cheval.py | 2147,2156,2157,2158,2163 | low | fix-commit | agreed | true | H16,H17,H18 |
| V09 | .claude/adapters/cheval.py | 2834,2835,2836,2837,2838,2839,2840,2841,2842,2843 | medium | fix-commit | adjudicated | true | H21,H22 |
| V10 | .claude/adapters/loa_cheval/config/loader.py | 113,116,117,120,121,122,125,126 | high | fix-commit | adjudicated | true | H30 |
| V11 | .claude/adapters/loa_cheval/providers/agy_headless_adapter.py | 261,262 | low | fix-commit | agreed | true | H31 |
| V12 | .claude/adapters/loa_cheval/providers/claude_headless_adapter.py | 131,145,341,342 | medium | fix-commit | adjudicated | true | H33,H35,H39 |
| V13 | .claude/adapters/loa_cheval/providers/claude_headless_adapter.py | 543,544,545,546,547,548,549,550,551,552,553,575,576,577,578,579,580,581,582 | medium | fix-commit | adjudicated | true | H40,H41 |
| V14 | .claude/data/schemas/model-config-v3.schema.json | 282,283,287,290,291,292,295,296,299,300 | low | fix-commit | adjudicated | false | H91,H92,H93,H94 |
| V15 | .claude/data/schemas/model-config-v3.schema.json | 306,307 | medium | fix-commit | adjudicated | true | H95 |
| V16 | .claude/defaults/model-config.yaml | 503,506,509,513 | medium | fix-commit | adjudicated | true | H100,H101 |
| V17 | .claude/scripts/adversarial-review.sh | 2350,2351,2352,2353,2354,2355,2356,2357,2358,2359,2360 | medium | fix-commit | adjudicated | true | H104 |
| V18 | .claude/scripts/adversarial-review.sh | 4080,4081 | low | fix-commit | adjudicated | true | H105 |
| V19 | .claude/scripts/flatline-orchestrator.sh | 522,523,524,525,526,529,530,531,532,533,534,535,536 | medium | fix-commit | adjudicated | true | H107 |
| V20 | .claude/scripts/flatline-orchestrator.sh | 2456 | low | fix-commit | adjudicated | true | H108 |
| V21 | .claude/scripts/loa-status.sh | 798,799,800,801,802,803,804,805,806,811,812 | low | fix-commit | adjudicated | true | H110,H111 |
| V22 | .claude/scripts/loa-status.sh | 822,826,827,828,831,832,833,838,839,840,842 | medium | fix-commit | adjudicated | true | H112 |
| V23 | .claude/scripts/loa-status.sh | 860 | low | fix-commit | adjudicated | true | H113 |
| V24 | .claude/scripts/run-preflight.sh | 153,154,155,156,157,158,159,174,186,187,188,189,190,191,192 | medium | fix-commit | adjudicated | true | H117,H118,H120 |
| V25 | .claude/scripts/run-preflight.sh | 197,204 | low | fix-commit | agreed | false | H121,H122 |
| V26 | .claude/skills/bridgebuilder-review/resources/config.ts | 159,163,164,165,166,167,171,173,174,175,176,180,181,182 | high | fix-commit | adjudicated | true | H158 |
| V27 | .claude/skills/bridgebuilder-review/resources/config.ts | 190 | medium | fix-commit | adjudicated | true | H159 |
| V28 | .claude/skills/bridgebuilder-review/resources/config.ts | 200 | medium | fix-commit | adjudicated | true | H160 |
| V29 | .claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts | 172,173,174,212,421,422 | medium | fix-commit | adjudicated | true | H163,H164,H166 |
| V30 | .claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts | 347,348,349,350,351,352,353,652 | low | fix-commit | adjudicated | true | H165,H168 |
| V31 | .claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts | 34 | high | fix-commit | adjudicated | true | H170 |
| V32 | tools/ceiling-probe-live.py | 133,134,705,706,707,708,709,710,711,712,713,714,715,716,720,721,722,723,724,725,726,727 | medium | fix-commit | adjudicated | true | H200,H221 |
| V33 | tools/ceiling-probe-live.py | 144 | low | fix-commit | adjudicated | false | H201 |
| V34 | tools/ceiling-probe-live.py | 173,174,175,178,456,457,458,459,460,467,468,480 | medium | fix-commit | adjudicated | true | H202,H212 |
| V35 | tools/ceiling-probe-live.py | 215,216,217,218,219,220,221,222,223,224,225 | medium | fix-commit | agreed | true | H203 |
| V36 | tools/ceiling-probe-live.py | 230,231,232,238,239,240,751,752,753,754,755,756,757,758,759,760,761,762,830,831 | medium | fix-commit | adjudicated | true | H204,H205,H222,H226 |
| V37 | tools/ceiling-probe-live.py | 251,252,253,254,255,256,257,266,267 | high | fix-commit | adjudicated | true | H206,H207 |
| V38 | tools/ceiling-probe-live.py | 402,403,404,413,414,415,456,460 | medium | fix-commit | adjudicated | true | H209,H210 |
| V39 | tools/ceiling-probe-live.py | 512,513 | low | fix-commit | adjudicated | true | H214 |
| V40 | tools/ceiling-probe-live.py | 616,617,618,619,623,625,627,628 | medium | fix-commit | adjudicated | false | H215 |
| V41 | tools/ceiling-probe-live.py | 644,645,646,647,648,649,650,651,652,653 | medium | fix-commit | adjudicated | true | H218 |
| V42 | tools/ceiling-probe-live.py | 684,688,689,690,711,712,713,714,715,716,720,721,722,723,724,725,726,727 | medium | fix-commit | adjudicated | true | H216,H219 |
| V43 | tools/ceiling-probe-live.py | 771,772,773 | low | fix-commit | adjudicated | false | H223 |
| V44 | tools/ceiling-probe-live.py | 799,800,801,802 | low | fix-commit | adjudicated | true | H224 |
| V45 | tools/ceiling-probe-live.py | 811,812,813,814,815,816,817,818,819,820,821 | medium | fix-commit | adjudicated | true | H225 |
