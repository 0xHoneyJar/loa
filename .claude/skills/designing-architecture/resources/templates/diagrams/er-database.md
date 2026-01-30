# Database Schema ER Diagram Template

Use this template for database schemas and entity relationships.

## Template

```mermaid
erDiagram
    %% ===== CUSTOMIZATION POINTS =====
    %% 1. Replace entity names (PascalCase)
    %% 2. Update attributes with types
    %% 3. Adjust relationships and cardinality
    %% 4. Add PK/FK markers

    USERS {
        uuid id PK
        string email UK
        string name
        string password_hash
        timestamp created_at
        timestamp updated_at
    }

    ORGANIZATIONS {
        uuid id PK
        string name
        string plan
        timestamp created_at
    }

    MEMBERSHIPS {
        uuid id PK
        uuid user_id FK
        uuid org_id FK
        string role
        timestamp joined_at
    }

    PROJECTS {
        uuid id PK
        uuid org_id FK
        string name
        string status
        timestamp created_at
    }

    TASKS {
        uuid id PK
        uuid project_id FK
        uuid assignee_id FK
        string title
        text description
        string status
        timestamp due_date
    }

    %% Relationships
    USERS ||--o{ MEMBERSHIPS : "has"
    ORGANIZATIONS ||--o{ MEMBERSHIPS : "has"
    ORGANIZATIONS ||--o{ PROJECTS : "owns"
    PROJECTS ||--o{ TASKS : "contains"
    USERS ||--o{ TASKS : "assigned"
```

## Preview URL Pattern

```
> **Preview**: [View diagram](https://agents.craft.do/mermaid?code={base64}&theme=github)
```

## Usage Notes

1. **Attribute Markers**:
   - `PK` Primary Key
   - `FK` Foreign Key
   - `UK` Unique Key

2. **Common Types**:
   - `uuid`, `int`, `bigint`
   - `string`, `text`
   - `boolean`
   - `timestamp`, `date`
   - `jsonb`, `array`

3. **Relationships**:
   - `||--||` One to one
   - `||--o{` One to many
   - `o{--o{` Many to many

## Variations

### Junction Table (Many-to-Many)
```mermaid
erDiagram
    USERS ||--o{ USER_ROLES : "has"
    ROLES ||--o{ USER_ROLES : "assigned to"

    USER_ROLES {
        uuid user_id FK
        uuid role_id FK
        timestamp granted_at
    }
```

### Self-Referencing
```mermaid
erDiagram
    EMPLOYEES {
        uuid id PK
        uuid manager_id FK
        string name
    }

    EMPLOYEES ||--o{ EMPLOYEES : "manages"
```

### Polymorphic Association
```mermaid
erDiagram
    COMMENTS {
        uuid id PK
        string commentable_type
        uuid commentable_id
        text body
    }

    POSTS ||--o{ COMMENTS : "has"
    TASKS ||--o{ COMMENTS : "has"
```

### Audit Trail
```mermaid
erDiagram
    AUDIT_LOGS {
        uuid id PK
        string entity_type
        uuid entity_id
        string action
        jsonb changes
        uuid actor_id FK
        timestamp created_at
    }
```
