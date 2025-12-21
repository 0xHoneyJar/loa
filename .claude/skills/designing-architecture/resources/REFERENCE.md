# Architecture Designer Reference

## Required SDD Sections Checklist

### 1. Project Architecture
- [ ] System Overview
- [ ] Architectural Pattern with justification
- [ ] Component Diagram (ASCII or textual)
- [ ] System Components breakdown
- [ ] Data Flow description
- [ ] External Integrations
- [ ] Deployment Architecture
- [ ] Scalability Strategy
- [ ] Security Architecture

### 2. Software Stack
- [ ] Frontend Technologies (framework, state management, build tools, testing)
- [ ] Backend Technologies (language, framework, API design, testing)
- [ ] Infrastructure & DevOps (cloud, containers, CI/CD, monitoring, IaC)
- [ ] Justification for each major choice

### 3. Database Design
- [ ] Database Technology choice with justification
- [ ] Schema Design with DDL examples
- [ ] Entity Relationships
- [ ] Data Modeling Approach
- [ ] Migration Strategy
- [ ] Data Access Patterns
- [ ] Caching Strategy
- [ ] Backup and Recovery

### 4. UI Design
- [ ] Design System
- [ ] Key User Flows
- [ ] Page/View Structure
- [ ] Component Architecture
- [ ] Responsive Design Strategy
- [ ] Accessibility Standards
- [ ] State Management

### 5. API Specifications
- [ ] API Design Principles
- [ ] Endpoint definitions
- [ ] Request/Response examples
- [ ] Error response format

### 6. Error Handling Strategy
- [ ] Error categories
- [ ] Response format
- [ ] Logging strategy

### 7. Testing Strategy
- [ ] Testing pyramid
- [ ] Coverage targets
- [ ] CI/CD integration

### 8. Development Phases
- [ ] Sprint breakdown
- [ ] Milestones

### 9. Known Risks and Mitigation
- [ ] Risk assessment
- [ ] Mitigation strategies

### 10. Open Questions
- [ ] Deferred decisions
- [ ] Pending product input

## Clarification Questions Checklist

### Technical Constraints
- [ ] Budget constraints?
- [ ] Timeline constraints?
- [ ] Team size and expertise?
- [ ] Existing systems to integrate with?

### Scale Requirements
- [ ] Expected user volume?
- [ ] Expected data volume?
- [ ] Growth projections?
- [ ] Peak load expectations?

### Security & Compliance
- [ ] Security requirements?
- [ ] Compliance requirements (GDPR, HIPAA, SOC2)?
- [ ] Data residency requirements?

### Performance
- [ ] Response time expectations?
- [ ] Availability requirements (SLA)?
- [ ] Throughput requirements?

## Technology Decision Matrix

When evaluating technology choices, consider:

| Factor | Weight | Option A | Option B | Option C |
|--------|--------|----------|----------|----------|
| Team Familiarity | High | | | |
| Community/Support | Medium | | | |
| Performance | Medium | | | |
| Cost | Medium | | | |
| Scalability | High | | | |
| Security | High | | | |
| Maintenance | Medium | | | |

## Common Architectural Patterns

### Monolithic
- **When:** Small team, simple requirements, rapid MVP
- **Pros:** Simple deployment, easy debugging, shared memory
- **Cons:** Scaling challenges, tight coupling, deployment risk

### Microservices
- **When:** Large team, complex domain, independent scaling needs
- **Pros:** Independent deployment, technology flexibility, fault isolation
- **Cons:** Operational complexity, network latency, data consistency

### Serverless
- **When:** Event-driven, variable load, cost optimization priority
- **Pros:** Auto-scaling, pay-per-use, reduced ops
- **Cons:** Cold starts, vendor lock-in, debugging complexity

### Event-Driven
- **When:** Decoupled services, async processing, audit trails
- **Pros:** Loose coupling, scalability, resilience
- **Cons:** Eventual consistency, debugging complexity, message ordering

## Database Selection Guide

| Database | Best For | Avoid When |
|----------|----------|------------|
| PostgreSQL | Relational data, ACID, complex queries | Simple key-value, massive scale |
| MongoDB | Document data, flexible schema, rapid development | Complex transactions, strong consistency |
| Redis | Caching, sessions, real-time | Persistent primary storage |
| DynamoDB | Serverless, AWS ecosystem, high scale | Complex queries, cost-sensitive |

## Security Checklist

### Authentication
- [ ] Strong password policies
- [ ] MFA support
- [ ] Secure session management
- [ ] Token expiration and refresh

### Authorization
- [ ] Role-based access control
- [ ] Principle of least privilege
- [ ] Resource-level permissions

### Data Protection
- [ ] Encryption at rest
- [ ] Encryption in transit (TLS)
- [ ] PII handling
- [ ] Data retention policies

### Infrastructure
- [ ] Firewall configuration
- [ ] VPC isolation
- [ ] Secrets management
- [ ] Audit logging
