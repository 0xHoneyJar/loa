# PR Description Template — cycle-098-agent-network

> Use this template when opening the cycle-098 PR. The fingerprint section is the **first of three** publication channels for the maintainer root pubkey (per SDD §1.9.3.1 + Sprint 1 SKP-001 ACs).

---

## Title

`feat(cycle-098): agent-network operation primitives (L1-L7)`

## Body

### Summary

Cycle-098 ships seven framework-level primitives that extend Loa from per-repo, per-session, per-operator operation to **operator-absent network operation** — multiple repos, multiple operators, multiple agents, with explicit primitives for adjudication, budget enforcement, trust state, identity expression, and structured handoffs.

The seven primitives:

| Layer | Name | One-line surface |
|-------|------|------------------|
| L1 | hitl-jury-panel | N-panelist random-selection adjudicator for `AskUserQuestion`-class decisions |
| L2 | cost-budget-enforcer | Daily token cap with fail-closed semantics |
| L3 | scheduled-cycle-template | Generic skill template composing `/schedule` + autonomous primitives |
| L4 | graduated-trust | Per-(scope, capability) trust ledger with operator-defined transitions |
| L5 | cross-repo-status-reader | Read structured cross-repo state via `gh` API |
| L6 | structured-handoff | Markdown+frontmatter handoff documents (same-machine only; FU-6 for multi-host) |
| L7 | soul-identity-doc | Schema + SessionStart hook for descriptive `SOUL.md` |

Sprint 1 lands shared cross-cutting infrastructure: audit-log envelope schema (versioned, hash-chained, Ed25519-signed), JCS canonicalization adapters, tier validator, prompt isolation extension, OPERATORS.md schema, root-of-trust release-signed pubkey, fd-based secret loading.

### Cycle metadata

- **PRD**: `grimoires/loa/prd.md` (v1.3, 2 PRD-level Flatline passes + SKP-002 back-propagation)
- **SDD**: `grimoires/loa/sdd.md` (v1.5, 4 SDD-level Flatline passes integrated)
- **Sprint plan**: `grimoires/loa/sprint.md` (TBD)
- **Source issues**: #653 (L1), #654 (L2), #655 (L3), #656 (L4), #657 (L5), #658 (L6), #659 (L7)
- **Discovered bug**: #675 (cheval HTTP/2 disconnect — to be triaged separately)

### Maintainer root pubkey fingerprint (publication channel 1 of 3)

> Sprint 1 lands this pubkey at `.claude/data/maintainer-root-pubkey.txt` (System Zone) and as a release-signed git tag `cycle-098-root-key-v1`. Operators verify the fingerprint matches across all three channels before accepting the trust anchor (per SDD §1.9.3.1).

**SHA-256 of public key SPKI DER (hex)**:
```
e76eec460b34eb610f6db1272d7ef364b994d51e49f13ad0886fa8b9e854c4d1
```

**Colon-separated** (for visual cross-check):
```
e7:6e:ec:46:0b:34:eb:61:0f:6d:b1:27:2d:7e:f3:64:b9:94:d5:1e:49:f1:3a:d0:88:6f:a8:b9:e8:54:c4:d1
```

**Algorithm**: Ed25519 (RFC 8032)
**Generated**: 2026-05-03 by maintainer (deep-name / jani@0xhoneyjar.xyz)
**Encryption**: passphrase-protected on maintainer's offline backup
**Verification**: `git tag -v cycle-098-root-key-v1` validates against maintainer's GitHub-registered GPG key

**Cross-verify** with the other two channels before accepting:
1. This PR description (you are here)
2. `grimoires/loa/NOTES.md` cycle-098 section
3. `grimoires/loa/cycles/cycle-098-agent-network/release-notes-sprint1.md`

If any of the three fingerprints diverge, **DO NOT ACCEPT the trust anchor**. Open an issue and contact the maintainer out-of-band (Slack/email/signed announcement).

### Test plan

- [ ] All 63 acceptance criteria from PRD (9 per primitive average) PASS
- [ ] All 11 cross-cutting FRs (CC-1..CC-11) satisfied
- [ ] Cross-primitive integration tests PASS for all 5 supported configuration tiers
- [ ] macOS CI passes (flock + realpath portability per cycle-098 bug batch shims)
- [ ] JCS multi-language conformance CI gate green (bash + Python + Node byte-identical)
- [ ] Adversarial jailbreak corpus (Sprint 7) passes
- [ ] No regressions in existing skills

### Sprint progress

> Filled in iteratively by sprint PRs. Each sprint produces `cycles/cycle-098-agent-network/sprint-N-progress.md`.

- [ ] Sprint 1 (L1 + CC infra)
- [ ] Sprint 2 (L2 + reconciliation cron)
- [ ] Sprint 3 (L3)
- [ ] Sprint 4 (L4)
- [ ] Sprint 4.5 buffer week
- [ ] Sprint 5 (L5)
- [ ] Sprint 6 (L6)
- [ ] Sprint 7 (L7 + adversarial corpus)

### De-scope triggers active

- [ ] R11 weekly Friday schedule-check ritual active from Sprint 1 kickoff (per SDD Sprint 1 ACs §6 SOLO_OPUS recommendation)
- [ ] Sprint 1 >2 weeks late → re-baseline as phased (cycle-098a / cycle-098b)
- [ ] Audit-log envelope schema breaks 2x → schema design dedicated mini-cycle

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
