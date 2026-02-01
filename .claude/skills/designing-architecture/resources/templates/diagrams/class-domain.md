# Domain Model Class Diagram Template

Use this template for object models and type relationships.

## Template

```mermaid
classDiagram
    %% ===== CUSTOMIZATION POINTS =====
    %% 1. Replace class names
    %% 2. Update attributes and methods
    %% 3. Adjust relationships
    %% 4. Add visibility: + public, - private, # protected

    class User {
        +String id
        +String email
        +String name
        -String passwordHash
        +DateTime createdAt
        +login(credentials) bool
        +updateProfile(data) User
    }

    class Organization {
        +String id
        +String name
        +String plan
        +addMember(user) void
        +removeMember(user) void
    }

    class Project {
        +String id
        +String name
        +String status
        +DateTime createdAt
        +archive() void
        +restore() void
    }

    class Task {
        +String id
        +String title
        +String description
        +TaskStatus status
        +complete() void
        +assign(user) void
    }

    %% Relationships
    User "1" --> "*" Organization : belongs to
    Organization "1" --> "*" Project : owns
    Project "1" --> "*" Task : contains
    User "1" --> "*" Task : assigned to
```

## Preview URL Pattern

```
> **Preview**: [View diagram](https://agents.craft.do/mermaid?code={base64}&theme=github)
```

## Usage Notes

1. **Visibility**:
   - `+` Public
   - `-` Private
   - `#` Protected
   - `~` Package/Internal

2. **Relationships**:
   - `-->` Association
   - `--o` Aggregation
   - `--*` Composition
   - `--|>` Inheritance
   - `..|>` Implementation

3. **Cardinality**: `"1"`, `"*"`, `"0..1"`, `"1..*"`

## Variations

### Interface Implementation
```mermaid
classDiagram
    class IRepository {
        <<interface>>
        +find(id) Entity
        +save(entity) void
        +delete(id) void
    }

    class UserRepository {
        +find(id) User
        +save(user) void
        +delete(id) void
    }

    IRepository <|.. UserRepository
```

### Inheritance Hierarchy
```mermaid
classDiagram
    class BaseEntity {
        <<abstract>>
        +String id
        +DateTime createdAt
        +DateTime updatedAt
    }

    class User {
        +String email
    }

    class Admin {
        +String[] permissions
    }

    BaseEntity <|-- User
    User <|-- Admin
```

### Enum Types
```mermaid
classDiagram
    class TaskStatus {
        <<enumeration>>
        PENDING
        IN_PROGRESS
        COMPLETED
        CANCELLED
    }

    class Task {
        +TaskStatus status
    }

    Task --> TaskStatus
```
