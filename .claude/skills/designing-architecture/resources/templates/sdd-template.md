# Software Design Document: {Project Name}

**Version:** 1.0
**Date:** {DATE}
**Author:** Architecture Designer Agent
**Status:** Draft | In Review | Approved
**PRD Reference:** grimoires/loa/prd.md

---

## Table of Contents

1. [Project Architecture](#1-project-architecture)
2. [Software Stack](#2-software-stack)
3. [Database Design](#3-database-design)
4. [UI Design](#4-ui-design)
5. [API Specifications](#5-api-specifications)
6. [Error Handling Strategy](#6-error-handling-strategy)
7. [Testing Strategy](#7-testing-strategy)
8. [Development Phases](#8-development-phases)
9. [Known Risks and Mitigation](#9-known-risks-and-mitigation)
10. [Open Questions](#10-open-questions)
11. [Appendix](#11-appendix)

---

## 1. Project Architecture

### 1.1 System Overview
{High-level description of the system and its purpose}

### 1.2 Architectural Pattern
**Pattern:** {Microservices | Monolithic | Serverless | Event-driven | Hybrid}

**Justification:**
{Why this pattern was chosen given the requirements}

### 1.3 Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                      {System Name}                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐     ┌──────────────┐    ┌──────────────┐ │
│  │   Frontend   │────▶│   API Layer  │───▶│   Database   │ │
│  └──────────────┘     └──────────────┘    └──────────────┘ │
│                              │                              │
│                              ▼                              │
│                       ┌──────────────┐                      │
│                       │   Services   │                      │
│                       └──────────────┘                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 1.4 System Components

#### {Component 1 Name}
- **Purpose:** {What this component does}
- **Responsibilities:** {List of responsibilities}
- **Interfaces:** {APIs exposed}
- **Dependencies:** {Other components it depends on}

#### {Component 2 Name}
...

### 1.5 Data Flow
{Description of how data moves through the system}

### 1.6 External Integrations

| Service | Purpose | API Type | Documentation |
|---------|---------|----------|---------------|
| {Service} | {Purpose} | {REST/GraphQL/etc} | {URL} |

### 1.7 Deployment Architecture
{How components are deployed - cloud, on-premise, hybrid}

### 1.8 Scalability Strategy
- **Horizontal Scaling:** {approach}
- **Vertical Scaling:** {approach}
- **Auto-scaling:** {triggers and thresholds}
- **Load Balancing:** {strategy}

### 1.9 Security Architecture
- **Authentication:** {method - JWT, OAuth, etc.}
- **Authorization:** {RBAC, ABAC, etc.}
- **Data Protection:** {encryption at rest/in transit}
- **Network Security:** {VPC, firewalls, etc.}

---

## 2. Software Stack

### 2.1 Frontend Technologies

| Category | Technology | Version | Justification |
|----------|------------|---------|---------------|
| Framework | {React/Vue/etc} | {X.Y.Z} | {Why} |
| State Management | {Redux/Zustand/etc} | {X.Y.Z} | {Why} |
| Build Tool | {Vite/Webpack/etc} | {X.Y.Z} | {Why} |
| Testing | {Jest/Vitest/etc} | {X.Y.Z} | {Why} |

**Key Libraries:**
- {library}: {purpose}
- {library}: {purpose}

### 2.2 Backend Technologies

| Category | Technology | Version | Justification |
|----------|------------|---------|---------------|
| Language | {Node.js/Python/etc} | {X.Y.Z} | {Why} |
| Framework | {Express/FastAPI/etc} | {X.Y.Z} | {Why} |
| API Design | {REST/GraphQL/gRPC} | - | {Why} |
| Testing | {Jest/Pytest/etc} | {X.Y.Z} | {Why} |

**Key Libraries:**
- {library}: {purpose}
- {library}: {purpose}

### 2.3 Infrastructure & DevOps

| Category | Technology | Purpose |
|----------|------------|---------|
| Cloud Provider | {AWS/GCP/Vercel/etc} | {Purpose} |
| Containerization | {Docker} | {Purpose} |
| Orchestration | {Kubernetes/ECS/etc} | {Purpose} |
| CI/CD | {GitHub Actions/etc} | {Purpose} |
| Monitoring | {Datadog/Grafana/etc} | {Purpose} |
| Logging | {ELK/CloudWatch/etc} | {Purpose} |
| IaC | {Terraform/Pulumi/etc} | {Purpose} |

---

## 3. Database Design

### 3.1 Database Technology
**Primary Database:** {PostgreSQL/MongoDB/etc}
**Version:** {X.Y}

**Justification:**
{Why this database was chosen}

### 3.2 Schema Design

#### Entity: {Entity Name}

```sql
CREATE TABLE {table_name} (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    {column_name} {TYPE} {CONSTRAINTS},
    {column_name} {TYPE} {CONSTRAINTS},
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_{table}_{column} ON {table_name}({column});
```

#### Entity Relationships

```
{Entity1} ──1:N──▶ {Entity2}
{Entity1} ◀──M:N──▶ {Entity3}
```

### 3.3 Data Modeling Approach
- **Normalization Level:** {3NF, etc.}
- **Denormalization Strategy:** {Where and why}

### 3.4 Migration Strategy
{How schema changes will be managed}

### 3.5 Data Access Patterns

| Query | Frequency | Optimization |
|-------|-----------|--------------|
| {Query description} | {High/Med/Low} | {Index/Cache/etc} |

### 3.6 Caching Strategy
- **Cache Provider:** {Redis/Memcached/etc}
- **Cached Data:** {What is cached}
- **Invalidation:** {Strategy}
- **TTL:** {Time to live}

### 3.7 Backup and Recovery
- **Backup Frequency:** {hourly/daily/etc}
- **Retention Period:** {X days}
- **Recovery Time Objective (RTO):** {X hours}
- **Recovery Point Objective (RPO):** {X hours}

---

## 4. UI Design

### 4.1 Design System
- **Component Library:** {MUI/Chakra/Tailwind/etc}
- **Design Tokens:** {colors, spacing, typography}
- **Theming:** {Light/Dark mode support}

### 4.2 Key User Flows

#### Flow 1: {Flow Name}
```
{Step 1} → {Step 2} → {Step 3} → {Outcome}
```

### 4.3 Page/View Structure

| Page | URL | Purpose | Key Components |
|------|-----|---------|----------------|
| {Page} | /{path} | {Purpose} | {Components} |

### 4.4 Component Architecture
```
App
├── Layout
│   ├── Header
│   ├── Sidebar
│   └── Footer
├── Pages
│   ├── {Page1}
│   └── {Page2}
└── Components
    ├── {Component1}
    └── {Component2}
```

### 4.5 Responsive Design Strategy
- **Breakpoints:** {mobile: 640px, tablet: 768px, desktop: 1024px}
- **Approach:** {Mobile-first}

### 4.6 Accessibility Standards
- **WCAG Level:** {AA/AAA}
- **Key Considerations:** {List}

### 4.7 State Management
{How UI state is managed and synchronized}

---

## 5. API Specifications

### 5.1 API Design Principles
- **Style:** {REST/GraphQL/gRPC}
- **Versioning:** {URL path/Header}
- **Authentication:** {Bearer token/API key}

### 5.2 Endpoints

#### {Resource} Endpoints

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | /api/v1/{resource} | List all | Yes |
| GET | /api/v1/{resource}/:id | Get one | Yes |
| POST | /api/v1/{resource} | Create | Yes |
| PUT | /api/v1/{resource}/:id | Update | Yes |
| DELETE | /api/v1/{resource}/:id | Delete | Yes |

#### Example: GET /api/v1/{resource}/:id

**Request:**
```http
GET /api/v1/{resource}/123
Authorization: Bearer {token}
```

**Response (200 OK):**
```json
{
  "id": "123",
  "field1": "value1",
  "createdAt": "2024-01-01T00:00:00Z"
}
```

**Error Response (404 Not Found):**
```json
{
  "error": {
    "code": "NOT_FOUND",
    "message": "Resource not found"
  }
}
```

---

## 6. Error Handling Strategy

### 6.1 Error Categories

| Category | HTTP Status | Example |
|----------|-------------|---------|
| Validation | 400 | Invalid input |
| Authentication | 401 | Invalid token |
| Authorization | 403 | Insufficient permissions |
| Not Found | 404 | Resource not found |
| Server Error | 500 | Unexpected error |

### 6.2 Error Response Format
```json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Human readable message",
    "details": {},
    "requestId": "uuid"
  }
}
```

### 6.3 Logging Strategy
- **Log Levels:** ERROR, WARN, INFO, DEBUG
- **Structured Logging:** JSON format
- **Correlation IDs:** Request tracing

---

## 7. Testing Strategy

### 7.1 Testing Pyramid

| Level | Coverage Target | Tools |
|-------|-----------------|-------|
| Unit | 80% | {Jest/Pytest/etc} |
| Integration | Key flows | {Supertest/etc} |
| E2E | Critical paths | {Playwright/Cypress} |

### 7.2 Testing Guidelines
- **Unit Tests:** {guidelines}
- **Integration Tests:** {guidelines}
- **E2E Tests:** {guidelines}

### 7.3 CI/CD Integration
- Tests run on every PR
- Required checks before merge
- Coverage reporting

---

## 8. Development Phases

### Phase 1: Foundation (Sprint 1-2)
- [ ] Project setup and CI/CD
- [ ] Database schema implementation
- [ ] Authentication system
- [ ] Core API endpoints

### Phase 2: Core Features (Sprint 3-4)
- [ ] {Feature 1}
- [ ] {Feature 2}
- [ ] {Feature 3}

### Phase 3: Polish & Launch (Sprint 5-6)
- [ ] UI/UX refinements
- [ ] Performance optimization
- [ ] Security hardening
- [ ] Documentation

---

## 9. Known Risks and Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| {Risk 1} | High/Med/Low | High/Med/Low | {Strategy} |
| {Risk 2} | High/Med/Low | High/Med/Low | {Strategy} |

---

## 10. Open Questions

| Question | Owner | Due Date | Status |
|----------|-------|----------|--------|
| {Question} | {Person} | {Date} | Open/Resolved |

---

## 11. Appendix

### A. Glossary
| Term | Definition |
|------|------------|
| {Term} | {Definition} |

### B. References
- {Reference 1}: {URL}
- {Reference 2}: {URL}

### C. Change Log
| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | {Date} | Initial version | Architecture Designer |

---

*Generated by Architecture Designer Agent*
