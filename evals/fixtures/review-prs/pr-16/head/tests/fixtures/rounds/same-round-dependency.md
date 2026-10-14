# Negative fixture: a round that holds a question and its prerequisite

Fixture for tools/check-round-independence.sh. Q3 depends on Q2, and both are
asked in round 1, so the operator would be answering Q3 before Q2 is settled.

Round 1 (Problem & Vision)

❓ Q1: Audience
Is the reading list for your team only?
➡ Recommended: yes

❓ Q2: Write access
Should every team member be able to add entries?
➡ Recommended: yes

❓ Q3: Moderation
Given open write access (Q2), should entries need a lead's approval?
➡ Recommended: no

<!-- round: 1; questions: [{"id":"Q1","depends_on":[]},{"id":"Q2","depends_on":[]},{"id":"Q3","depends_on":["Q2"]}] -->

Round 2 (Functional Requirements)

❓ Q4: Sign-in
Should sign-in use the company SSO?
➡ Recommended: yes

❓ Q5: Digest
Should the service send a weekly digest?
➡ Recommended: yes

<!-- round: 2; questions: [{"id":"Q4","depends_on":["Q1"]},{"id":"Q5","depends_on":[]}] -->
