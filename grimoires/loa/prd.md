# PRD: Flatline Red Team — Generative Adversarial Security Design

> Source: [#312](https://github.com/0xHoneyJar/loa/issues/312) — Flatline red team
> Cross-reference: [loa-finn #66](https://github.com/0xHoneyJar/loa-finn/issues/66) — Launch readiness gap analysis
> Author: PRD discovery + context synthesis
> Cycle: cycle-012

## 1. Problem Statement

The Flatline Protocol is a multi-model adversarial review system (Claude Opus 4.6 + GPT-5.2) that currently operates as a **quality gate** — it reviews planning documents (PRD, SDD, Sprint) and classifies consensus improvements. But it's used defensively: "Is this document good enough?"

Issue #312 proposes a paradigm shift: use Flatline as a **generative red-teaming tool** — where the adversarial models actively *create* attack scenarios, *design* failure modes, and *generate* security test cases. The attackers become co-designers.

> *"Adversarial red-teaming as a creative act... Imagine using it as a generative tool: 'Here's the agent identity spec. Now break it. What are the 10 most creative attack vectors?' The attackers become co-designers. This is how Google's Project Zero works."* — Issue #312

### Current State

| Capability | Status |
|-----------|--------|
| Multi-model review (Opus + GPT) | Shipping |
| Consensus scoring (0-1000) | Shipping |
| Skeptic mode (find concerns) | Shipping — but reactive, not generative |
| Cross-model dissent (adversarial-review.sh) | Shipping — but anchored to existing code, not speculative |
| Security audit (auditing-security skill) | Shipping — OWASP/CWE checklist, rubric-scored |
| Red-teaming (generative attack scenarios) | **Not implemented** |
| Attack tree generation | **Not implemented** |
| Creative exploit design | **Not implemented** |
| Security-as-design (attackers improve architecture) | **Not implemented** |

### Why Now

The loa-finn launch readiness RFC ([#66](https://github.com/0xHoneyJar/loa-finn/issues/66)) reveals a Product Experience score of 25% with critical gaps in agent identity, chat persistence, transfer handling, and billing. These are exactly the surfaces where adversarial red-teaming would improve the *design* — not just find bugs after the fact.

The Bridgebuilder deep dive comment on #66 identifies specific attack surfaces: confused deputy prevention, token-gated access, per-NFT personality isolation, soul vs inbox transfer semantics. A generative red team could systematically explore these before implementation begins.

> Sources: Issue #312 body, loa-finn #66 RFC body and Bridgebuilder comment

## 2. Core Concept: Red Team as Co-Designer

Google's Project Zero doesn't just find bugs — the security team improves the architecture by imagining how adversaries think. This PRD proposes the same pattern for Loa:

### Quality Gate (Current Flatline)

```
Document → Review → Score → Consensus → Accept/Reject
```

The models *evaluate*. They grade what exists.

### Red Team (Proposed Extension)

```
Spec/Design → "Break this" → Attack Scenarios → Counter-Designs → Hardened Spec
```

The models *create*. They generate novel attack vectors, then design defenses.

### Key Distinction

| Dimension | Quality Gate | Red Team |
|-----------|-------------|----------|
| **Input** | Complete document | Spec fragment, API surface, identity definition |
| **Prompt** | "Find improvements" | "Break this. What are the 10 most creative attacks?" |
| **Output** | Scored improvements | Attack trees, exploit scenarios, counter-designs |
| **Value** | Polish existing work | Discover unknown unknowns before implementation |
| **Timing** | After artifact creation | During or before design |
| **Stance** | Evaluator | Adversary-as-designer |

## 3. Functional Requirements

### 3.1 Red Team Skill (`/red-team`)

A new Loa skill that invokes Flatline in **generative adversarial mode**.

**Invocation**:
```bash
/red-team grimoires/loa/sdd.md                    # Red-team a document
/red-team grimoires/loa/sdd.md --focus "auth"      # Focus on auth surface
/red-team --spec "Agent identity is stored in BEAUVOIR.md per NFT"  # Ad-hoc spec
/red-team grimoires/loa/sdd.md --section "Data Architecture"  # Target specific section
```

**Input types**:
1. **Document**: PRD, SDD, Sprint plan — existing Flatline inputs
2. **Spec fragment**: A sentence or paragraph describing a design decision
3. **Architecture decision**: A specific technical choice to stress-test

> **Design decision (SKP-003)**: Code surface / glob pattern input is explicitly out of scope for v1. Red-teaming operates on design documents and spec fragments only — not source code. Code-aware security review remains the domain of the existing `auditing-security` skill. This prevents scope confusion between "red-team the design" and "audit the code."

**Output**: Structured red team report with attack scenarios, severity, and counter-designs.

### 3.2 Red Team Templates

Two new Flatline templates extending the existing template system:

#### 3.2.1 Attack Generator Template (`flatline-red-team.md.template`)

Prompt that instructs models to think like adversaries:

```
You are a security researcher performing a creative red-team exercise.
Your goal is NOT to find bugs in code — it's to imagine creative attacks
against a DESIGN before it's implemented.

Think like: Google Project Zero, Trail of Bits, a motivated nation-state actor,
a clever teenager with too much time, an insider with legitimate access.

For each attack:
1. Attack vector (how the attacker gets in)
2. Exploit scenario (step-by-step what happens)
3. Impact (what's the worst case)
4. Likelihood (how realistic is this)
5. Counter-design (how would you redesign to prevent this)
```

Output format: JSON array of attack scenarios with structured fields.

#### 3.2.2 Counter-Design Template (`flatline-counter-design.md.template`)

After attack generation, a second pass where models design defenses:

```
Given these attack scenarios, propose architectural changes that would
make each attack impossible or impractical. Don't just add checks —
redesign the system so the attack category doesn't exist.
```

### 3.3 Red Team Phases (Extension of Flatline Pipeline)

The red team extends the existing Flatline 4-phase pipeline:

| Phase | Current Flatline | Red Team Extension |
|-------|-----------------|-------------------|
| Phase 0 | Knowledge retrieval | Same + load threat models, OWASP, past red team results |
| Phase 1 | 4 parallel reviews | 4 parallel attack generations (GPT attacker, Opus attacker, GPT defender, Opus defender) |
| Phase 2 | Cross-scoring | Cross-validation: GPT validates Opus attacks, Opus validates GPT attacks |
| Phase 3 | Consensus | Attack severity consensus + counter-design synthesis |
| **Phase 4** (NEW) | — | Counter-design generation: merge best defenses from both models |

### 3.4 Attack Scenario Schema

Each attack scenario has structured output:

```json
{
  "id": "ATK-001",
  "name": "Persona Injection via Transfer",
  "attacker_profile": "insider",
  "vector": "NFT transfer with poisoned BEAUVOIR.md personality file",
  "scenario": [
    "Attacker creates NFT with normal personality",
    "Embeds hidden instruction in personality 'context' field",
    "Transfers NFT to target user",
    "Target's agent now executes hidden instructions"
  ],
  "impact": "Agent identity hijacking, unauthorized actions",
  "likelihood": "HIGH",
  "severity_score": 850,
  "target_surface": "agent-identity",
  "trust_boundary": "NFT ownership verification → personality ingest",
  "asset_at_risk": "Agent autonomy, user trust",
  "assumption_challenged": "Personality files are always benign",
  "reproducibility": "Create BEAUVOIR.md with hidden system prompt in 'context' field, transfer NFT, observe agent behavior change",
  "counter_design": {
    "description": "Sanitize personality files on transfer, validate against schema",
    "architectural_change": "Personality files pass through content policy filter on ingest",
    "prevents": "Injection of hidden instructions in personality context"
  },
  "faang_parallel": "Similar to OAuth token injection in federated auth flows"
}
```

> **Validation requirements (SKP-002)**: Each CONFIRMED_ATTACK must include: `trust_boundary` (which boundary is crossed), `asset_at_risk` (what's at stake), `assumption_challenged` (what design assumption is violated), and `reproducibility` (concrete steps that would confirm/deny the scenario). This prevents model hallucination from becoming security theater — two models agreeing on a non-reproducible attack is consensus on fiction.

### 3.5 Attack Surface Registry

A YAML registry of known attack surfaces that the red team can target:

```yaml
# .claude/data/attack-surfaces.yaml
surfaces:
  agent-identity:
    description: "Per-NFT personality and identity system"
    entry_points:
      - "BEAUVOIR.md personality files"
      - "Soul memory storage"
      - "Identity API endpoints"
    trust_boundary: "NFT ownership verification"

  token-gated-access:
    description: "NFT-based access control"
    entry_points:
      - "Wallet signature verification"
      - "Token balance checks"
      - "Tier-gated feature access"
    trust_boundary: "On-chain verification"
```

### 3.6 Consensus and Severity Model

Red team findings use an extended consensus model:

| Category | Criteria | Action |
|----------|----------|--------|
| **CONFIRMED_ATTACK** | Both models agree attack is viable, score >700 | Must address in design |
| **THEORETICAL** | One model scores >700, other <400 | Document as known risk |
| **CREATIVE_ONLY** | Both models <400 but novel | Log for future consideration |
| **DEFENDED** | Counter-design scores >700 from both | Architecture already handles this |

### 3.7 Integration Points

#### 3.7.1 Simstim Integration

New optional phase between SDD and Sprint Plan:

```
Phase 3: ARCHITECTURE (SDD)
Phase 4: FLATLINE SDD
Phase 4.5: RED TEAM SDD (NEW — optional)
Phase 5: PLANNING (Sprint Plan)
```

When enabled, the red team reviews the SDD's security-critical sections before sprint planning. Confirmed attacks generate additional sprint tasks.

#### 3.7.2 Run Bridge Integration

Red team can run as a bridge iteration variant:

```bash
/run-bridge --red-team            # Replace Bridgebuilder with red team
/run-bridge --red-team --depth 3  # 3 red team iterations
```

Each iteration targets a different attack surface from the registry.

#### 3.7.3 Ad-Hoc Invocation

```bash
# Red-team a specific design decision
/red-team --spec "Users authenticate via wallet signature, cached for 24h"

# Red-team the agent identity spec from loa-finn
/red-team grimoires/loa/sdd.md --section "Agent Identity" --depth 2

# Focus on specific attack categories
/red-team grimoires/loa/sdd.md --focus "injection,authz"
```

### 3.8 Report Format

The red team produces a structured report:

```markdown
# Red Team Report: [Target]
> Generated: 2026-02-13T18:00:00Z
> Models: Claude Opus 4.6, GPT-5.2
> Target: Agent Identity Specification
> Attack surfaces: agent-identity, token-gated-access

## Executive Summary
- **Confirmed attacks**: 3 (must address)
- **Theoretical risks**: 4 (document)
- **Creative scenarios**: 2 (future consideration)
- **Already defended**: 1

## Confirmed Attacks

### ATK-001: Persona Injection via Transfer
...

## Counter-Design Recommendations

### CDR-001: Personality Sanitization Layer
**Addresses**: ATK-001, ATK-003
**Architectural change**: ...
**Implementation cost**: LOW
**Security improvement**: HIGH

## Attack Tree
[Visual attack tree showing relationships between vectors]
```

### 3.9 Safety Policy — Dual-Use Controls (SKP-001)

Red team reports are sensitive dual-use artifacts. File permissions alone are insufficient.

#### 3.9.1 Report Classification

| Level | Criteria | Controls |
|-------|----------|----------|
| **PUBLIC** | Counter-design recommendations only, no attack details | Shareable, no redaction |
| **INTERNAL** | Full attack scenarios with counter-designs | 0600 permissions, audit logged |
| **RESTRICTED** | Step-by-step exploit chains, credential attack vectors | Encrypted at rest, access-controlled, retention-limited |

#### 3.9.2 Prohibited Content Taxonomy

The attack generator template MUST include a prohibited content policy. Models are instructed to NEVER generate:

- Working exploit code (PoC stubs are acceptable, functional exploits are not)
- Real credential patterns (use `EXAMPLE_KEY_xxx` placeholders)
- Instructions targeting specific individuals or real systems
- Content that could enable physical harm
- Social engineering scripts targeting real services

#### 3.9.3 Mandatory Redaction

The existing Bridgebuilder redaction pipeline (gitleaks-inspired patterns) applies to all red team output. Additional patterns for red team:

- Attack scenarios referencing real-world CVEs must cite by ID only (no reproduction steps)
- Internal infrastructure details (IP addresses, endpoints) are auto-redacted
- Model-generated "example" credentials are validated against the prohibited patterns

#### 3.9.4 Retention and Access

- Reports stored in `.run/red-team/` with 0600 permissions
- Retention: configurable, default 30 days for RESTRICTED, 90 days for INTERNAL
- Audit log: every report generation and access logged to `.run/audit.jsonl`
- CI/CD: red team reports NEVER included in build artifacts or PR bodies (summary only)

### 3.10 Cost Controls and Execution Modes (SKP-004)

The 4-model pipeline with attack generation + cross-validation + counter-design is token-intensive.

#### 3.10.1 Execution Modes

| Mode | Models | Phases | Use Case |
|------|--------|--------|----------|
| **Quick** | 2 (primary only) | Phase 1 + Phase 3 | PR-level, pre-commit |
| **Standard** | 4 (both pairs) | Full pipeline | Milestone review, SDD gate |
| **Deep** | 4 + iteration | Full + multi-depth | Major architecture decisions |

#### 3.10.2 Budget Enforcement

```yaml
red_team:
  budgets:
    quick_max_tokens: 50000        # ~$0.50
    standard_max_tokens: 200000    # ~$2.00
    deep_max_tokens: 500000        # ~$5.00
    max_attacks_total: 20          # Hard cap across all models
  early_stopping:
    saturation_threshold: 0.8      # Stop if 80% of attacks overlap
    min_novel_per_iteration: 2     # Stop if <2 novel attacks per depth
```

#### 3.10.3 Incremental Runs

Red team caches results by input hash. When a document changes incrementally:
- Unchanged sections: reuse previous attack scenarios
- Changed sections: generate new attacks for delta only
- New sections: full attack generation

### 3.11 Input Sanitization — Prompt Injection Defense (SKP-007)

The red team ingests untrusted text (spec fragments, design decisions) that could contain prompt injection.

#### 3.11.1 Input Pipeline

```
User Input → Injection Detection → Content Sanitization → Context Isolation → Model Call
```

1. **Injection detection**: Reuse existing `guardrails.input.injection_detection` (threshold 0.7)
2. **Content sanitization**: Strip/escape control characters, normalize whitespace, validate UTF-8
3. **Context isolation**: User-provided specs are wrapped in explicit `<untrusted-input>` delimiters in the prompt
4. **Secret filtering**: Inputs scanned for credential patterns before submission to models

#### 3.11.2 Model Isolation

- Red team model calls NEVER include: environment variables, repo secrets, auth tokens, internal URLs
- System prompt explicitly forbids: data exfiltration, accessing external services, generating content outside the red team schema
- All model responses are validated against the attack scenario JSON schema before processing

### 3.12 Human Validation Gate (SKP-002)

CONFIRMED_ATTACK findings with severity_score > 800 require human acknowledgment before being used to generate sprint tasks or counter-design recommendations.

- **Interactive mode**: Presented inline with [Accept/Reject/Investigate] options
- **Autonomous mode**: Logged to `.run/red-team/pending-review.json`, execution continues but findings are marked `awaiting_human_validation`
- **Simstim mode**: Presented as BLOCKER-equivalent, user decides

## 4. Configuration

```yaml
# .loa.config.yaml
red_team:
  enabled: true
  mode: standard                   # quick | standard | deep
  models:
    attacker_primary: opus
    attacker_secondary: gpt-5.2
    defender_primary: opus
    defender_secondary: gpt-5.2
  defaults:
    attacks_per_model: 10
    depth: 2                       # Iterations of attack → counter-design
    focus: null                    # null = all surfaces
  thresholds:
    confirmed_attack: 700          # Both models agree
    theoretical: 400               # One model flags
    human_review_gate: 800         # Require human validation above this
  budgets:
    quick_max_tokens: 50000
    standard_max_tokens: 200000
    deep_max_tokens: 500000
    max_attacks_total: 20
  early_stopping:
    saturation_threshold: 0.8
    min_novel_per_iteration: 2
  safety:
    prohibited_content: true       # Enforce prohibited content taxonomy
    mandatory_redaction: true      # Apply redaction pipeline
    retention_days_restricted: 30
    retention_days_internal: 90
    ci_artifact_scrubbing: true    # Never include reports in CI artifacts
  input_sanitization:
    injection_detection: true
    context_isolation: true
    secret_filtering: true
  surfaces_registry: .claude/data/attack-surfaces.yaml
  simstim:
    auto_trigger: false            # Opt-in for simstim integration
    phase: "post_sdd"
  bridge:
    enabled: false                 # Opt-in for bridge integration
```

## 5. Out of Scope

| Item | Reason |
|------|--------|
| **Automated exploit generation** | Ethical boundary — red team generates scenarios, not working exploits |
| **Penetration testing execution** | Red team is design-phase, not runtime |
| **Third-party model integration beyond Opus+GPT** | Can be added later; 2-model consensus is proven |
| **Real-time monitoring/alerting** | Runtime security is a different concern |
| **Automated fix generation** | Counter-designs are recommendations, not PRs |

## 6. Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| `/red-team` command functional | 1 new skill shipping | Skill invocable with document or spec input |
| Attack generator template | 1 new template | Produces structured JSON attack scenarios |
| Counter-design template | 1 new template | Produces architectural recommendations |
| Attack surface registry | 1 YAML registry | Valid, parseable, at least 3 surfaces defined |
| Red team report format | 1 markdown report | Includes confirmed/theoretical/creative classification |
| Consensus model extended | 4 new categories | CONFIRMED_ATTACK, THEORETICAL, CREATIVE_ONLY, DEFENDED |
| Safety policy enforced | Prohibited content taxonomy active | Template includes policy, redaction pipeline active |
| Input sanitization | Injection detection + context isolation | Untrusted inputs wrapped and scanned |
| Cost controls | Quick/standard/deep modes | Budget enforcement with early stopping |
| Human validation gate | Severity >800 requires ack | Gate fires in interactive and simstim modes |
| Integration tests | Phase 4 pipeline working | End-to-end: spec → attacks → counter-designs |

## 7. Risks

| Risk | Mitigation |
|------|------------|
| Models generate unrealistic attacks | Cross-validation + reproducibility field + human gate for severity >800 (Section 3.12) |
| Token cost of 4-model pipeline | Quick/standard/deep modes with hard budgets and early stopping (Section 3.10) |
| Red team findings overwhelm sprint planning | CONFIRMED_ATTACK threshold + max_attacks_total cap |
| Dual-use concern (attack scenarios could aid real attackers) | Classification levels, prohibited content taxonomy, mandatory redaction, retention limits, CI scrubbing (Section 3.9) |
| Scope creep into runtime security | Explicitly out of scope; red team is design-phase only |
| Prompt injection via untrusted spec inputs | Injection detection, content sanitization, context isolation, secret filtering (Section 3.11) |
| Model consensus without ground truth | Trust boundary mapping, reproducibility field, human validation gate (Sections 3.4, 3.12) |

## 8. References

- [Issue #312](https://github.com/0xHoneyJar/loa/issues/312) — Feature request: Flatline red team
- [loa-finn #66](https://github.com/0xHoneyJar/loa-finn/issues/66) — Launch readiness RFC
- [Google Project Zero](https://googleprojectzero.blogspot.com/) — Security research improving architecture
- [OWASP Threat Modeling](https://owasp.org/www-community/Threat_Modeling) — Structured threat analysis
- [STRIDE](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats) — Threat classification framework
- [Trail of Bits claude-code-config](https://github.com/trailofbits/claude-code-config) — Agent safety patterns (cycle-011 reference)
- Flatline Protocol: `.claude/protocols/flatline-protocol.md`
- Flatline Orchestrator: `.claude/scripts/flatline-orchestrator.sh`
- Adversarial Review: `.claude/scripts/adversarial-review.sh`
- Security Audit Skill: `.claude/skills/auditing-security/SKILL.md`
