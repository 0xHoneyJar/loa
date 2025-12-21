# DevRel Translator Bibliography

## Input Documents

### Loa Framework Documents
- **Product Requirements Document (PRD)**: `loa-grimoire/prd.md`
- **Software Design Document (SDD)**: `loa-grimoire/sdd.md`
- **Sprint Plan**: `loa-grimoire/sprint.md`
- **Sprint Reports**: `loa-grimoire/a2a/sprint-N/reviewer.md`
- **Security Audit Reports**: `SECURITY-AUDIT-REPORT.md`
- **Deployment Reports**: `loa-grimoire/a2a/deployment-report.md`

### Framework Documentation
- **Loa Framework Overview**: https://github.com/0xHoneyJar/loa/blob/main/CLAUDE.md
- **Workflow Process**: https://github.com/0xHoneyJar/loa/blob/main/PROCESS.md

## Technical Writing Resources

### Style Guides
- **Microsoft Writing Style Guide**: https://learn.microsoft.com/en-us/style-guide/welcome/
- **Google Developer Documentation Style Guide**: https://developers.google.com/style
- **Write the Docs - Beginner's Guide**: https://www.writethedocs.org/guide/writing/beginners-guide-to-docs/
- **Plain Language Guidelines**: https://www.plainlanguage.gov/guidelines/

### Communication Best Practices
- **Write the Docs - Writing for Non-Technical Audiences**: https://www.writethedocs.org/guide/writing/reducing-bias/
- **Handbook of Technical Writing**: https://www.oreilly.com/library/view/handbook-of-technical/9780471746492/

### Data Visualization
- **Google Charts Documentation**: https://developers.google.com/chart
- **Mermaid Diagram Syntax**: https://mermaid.js.org/syntax/flowchart.html

## Audience Persona References

### Technical Levels (from PRD Appendix B)
| Audience | Technical Level | Focus Areas |
|----------|-----------------|-------------|
| Product Managers | Medium | Features, user impact |
| Marketing | Low | Customer benefits, value propositions |
| Leadership/Executives | Very Low | Business impact, metrics |
| DevRel | High | Implementation details, best practices |
| Compliance/Legal | Low-Medium | Regulatory requirements, risk |
| Investors | Very Low | ROI, market positioning |
| Board | Very Low | Strategic alignment, governance |

## Organizational Meta Knowledge Base

**Repository**: https://github.com/0xHoneyJar/thj-meta-knowledge (Private)

### Essential Resources for Translation
- **Terminology Glossary**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/TERMINOLOGY.md
  - **MUST USE** for brand-specific terms
  - Ensures consistency across all communications

- **Product Documentation**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/products/
  - CubQuests, Mibera, Henlo, Set & Forgetti
  - fatBERA, apDAO, InterPoL, BeraFlip

- **Ecosystem Overview**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/ecosystem/OVERVIEW.md
  - Brand overview
  - System architecture (high-level)

- **Architecture Decision Records (ADRs)**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/decisions/INDEX.md
  - Decision context for explaining "why"
  - Background for leadership summaries

- **Knowledge Captures**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/knowledge/
  - Product insights for accurate summaries
  - Feature details by product

- **Links Registry**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/LINKS.md
  - All product URLs
  - For including in translated docs

- **AI Navigation Guide**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/.meta/RETRIEVAL_GUIDE.md

### When to Use Meta Knowledge
- **ALWAYS** check terminology glossary before translating technical terms
- Reference product documentation to understand context
- Use ecosystem overview for high-level explanations
- Include correct product URLs from links registry
- Reference ADRs to explain "why" decisions were made
- Verify product names, features, and descriptions

## Business Communication Resources

### Executive Communication
- **HBR Guide to Better Business Writing**: https://hbr.org/product/hbr-guide-to-better-business-writing/10024-PBK-ENG
- **Pyramid Principle (Barbara Minto)**: https://www.amazon.com/Pyramid-Principle-Logic-Writing-Thinking/dp/0273710516

### Risk Communication
- **NIST Risk Management Framework**: https://csrc.nist.gov/projects/risk-management
- **ISO 31000 Risk Management**: https://www.iso.org/iso-31000-risk-management.html

### Change Management
- **Prosci ADKAR Model**: https://www.prosci.com/methodology/adkar
- **Kotter's 8-Step Change Model**: https://www.kotterinc.com/8-step-process-for-leading-change/

## Compliance & Regulatory

### Data Protection
- **GDPR Official Text**: https://gdpr.eu/
- **CCPA Official Text**: https://oag.ca.gov/privacy/ccpa
- **SOC 2 Overview**: https://www.aicpa.org/soc2

### Blockchain/Crypto Regulation
- **SEC Crypto Guidance**: https://www.sec.gov/spotlight/cybersecurity
- **FATF Virtual Asset Guidance**: https://www.fatf-gafi.org/publications/fatfrecommendations/documents/guidance-rba-virtual-assets.html

## Output Standards

### All Translated Documents Must Include
- Clear audience specification
- Technical level appropriately matched to audience
- Links to source documents (absolute GitHub URLs)
- Visual suggestions with placement recommendations
- FAQ section addressing stakeholder concerns
- Risk callouts with mitigation strategies
- Next steps with actionable recommendations

### URL Format Standard
When referencing technical details, use absolute GitHub URLs:
```
https://github.com/{org}/{repo}/blob/{branch}/{path}
```

### Citation Format
```markdown
[Source Name](URL) - Section/Page
```

Example:
```markdown
[Security Audit Report](./SECURITY-AUDIT-REPORT.md) - Critical Findings section
```
