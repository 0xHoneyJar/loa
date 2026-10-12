# Retained Semantic-Review Challenge Cases

These fixture-simulated cases exercise the producer/reviewer contract outside
K2.16. They are not model judgments and do not establish semantic validation.

| case_id | challenge | structurally_legal | review_outcome | reason |
|---------|-----------|--------------------|----------------|--------|
| SR-1401 | missing required relation | yes | refuted | the bounded source basis requires an antecedent row omitted by the proposal |
| SR-1402 | over-broad relation | yes | refuted | the proposed target scope exceeds the exact qualifier |
| SR-1403 | wrong structurally legal subtype | yes | refuted | configuration was proposed where the source states a qualifier |
| SR-1404 | wrong existing/current target | yes | refuted | the target resolves and is current but is not the referenced unit |
| SR-1405 | context misused as support | yes | refuted | interpretive context cannot become independent evidence |
| SR-1406 | qualifier/antecedent loss | yes | refuted | normalization drops a bounded caveat required for faithful reading |
| SR-1407 | unjustified permitted cycle | yes | refuted | cycle permission is structural and the mutual context is not justified |
| SR-1408 | exact legal locus aimed at wrong semantic span | yes | refuted | bytes reopen and hash correctly but identify the wrong passage |
| SR-1409 | invented outside-corpus target disguised as in-corpus | yes | refuted | the proposed identity is not established by the frozen corpus |
| SR-1410 | explicit absence from incomplete context | yes | refuted | the bounded review did not receive enough frozen context to assert absence |
| SR-1411 | reviewer outcome not applicable | yes | not-applicable | the bounded family/subtype question does not apply and creates no canonical row |
