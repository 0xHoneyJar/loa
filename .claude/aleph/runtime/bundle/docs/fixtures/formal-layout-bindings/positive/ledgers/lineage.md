# Unit Lineage — RUN-typed-relations

- lineage_format: aleph-lineage/v1

| lineage_id | owner_stage | type | predecessors | successors | basis | established_by |
|------------|-------------|------|--------------|------------|-------|----------------|
| LIN-0001 | S3 | split | CC-0401 | CC-0410, CC-0411 | original normalization contained two independently stateable claims | fixture-simulated-normalizer |
| LIN-0002 | S3 | replace | CC-0402 | CC-0412 | corrected normalization establishes a new identity | fixture-simulated-normalizer |
| LIN-0003 | S3 | supersede | CC-0403 | CC-0413 | later normalized identity overtakes predecessor | fixture-simulated-normalizer |
| LIN-0004 | S4 | duplicate | CC-0404, CC-0405 | CC-0414 | same claim canonicalized with conserved provenance | fixture-simulated-merge-judge |
| LIN-0005 | S4 | merge | CC-0406, CC-0407 | CC-0415 | distinct inputs intentionally form one successor | fixture-simulated-merge-judge |
| LIN-0006 | S3 | reject | CC-0408 | none | structural claim candidate rejected with history retained | fixture-simulated-normalizer |
| LIN-0007 | S3 | exclude | CC-0409 | none | structural claim candidate excluded with history retained | fixture-simulated-normalizer |
| LIN-0008 | S3 | no-claim | PKT-0402 | none | packet yields no candidate claim | fixture-simulated-normalizer |
| LIN-0009 | S3 | split | CC-0410 | CC-0416, CC-0417 | later correction refines the intermediate identity | fixture-simulated-normalizer |
| LIN-0010 | S3 | supersede | CC-0411 | CC-0417 | sibling converges on the shared successor without compound N-to-M event | fixture-simulated-normalizer |
| LIN-0011 | S4 | merge | CC-0418, CC-0419 | CC-0420 | historical merge retained for later correction exercise | fixture-simulated-merge-judge |
| LIN-0012 | S3 | split | CC-0420 | CC-0421, CC-0422 | later unit correction preserves the prior merge as history | fixture-simulated-normalizer |
