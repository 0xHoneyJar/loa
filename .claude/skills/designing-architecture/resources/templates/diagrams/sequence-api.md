# API Interaction Sequence Template

Use this template for API request flows and service interactions.

## Template

```mermaid
sequenceDiagram
    %% ===== CUSTOMIZATION POINTS =====
    %% 1. Replace participant names
    %% 2. Update message labels
    %% 3. Add/remove participants as needed
    %% 4. Use alt/opt/loop blocks for conditionals

    participant C as Client
    participant G as API Gateway
    participant A as Auth Service
    participant S as Core Service
    participant D as Database

    C->>G: POST /api/resource
    G->>A: Validate token
    A-->>G: Token valid

    alt Token Invalid
        A-->>G: 401 Unauthorized
        G-->>C: 401 Unauthorized
    else Token Valid
        G->>S: Process request
        S->>D: Query data
        D-->>S: Data result
        S-->>G: Response payload
        G-->>C: 200 OK + data
    end
```

## Preview URL Pattern

```
> **Preview**: [View diagram](https://agents.craft.do/mermaid?code={base64}&theme=github)
```

## Usage Notes

1. **Participants**: Define all actors at the top
2. **Arrows**:
   - `->>` Synchronous request
   - `-->>` Response/return
   - `-)` Async message
3. **Blocks**:
   - `alt/else` for conditionals
   - `opt` for optional flows
   - `loop` for iterations
   - `par` for parallel execution

## Variations

### Authentication Flow
```mermaid
sequenceDiagram
    participant U as User
    participant A as Auth
    participant T as Token Store

    U->>A: Login(credentials)
    A->>T: Generate token
    T-->>A: JWT
    A-->>U: 200 + JWT
```

### Webhook Pattern
```mermaid
sequenceDiagram
    participant E as External Service
    participant W as Webhook Handler
    participant Q as Queue
    participant P as Processor

    E-)W: POST /webhook
    W->>Q: Enqueue event
    W-->>E: 202 Accepted
    Q-)P: Process event
```

### Error Handling
```mermaid
sequenceDiagram
    participant C as Client
    participant S as Service
    participant D as Database

    C->>S: Request
    S->>D: Query
    D--xS: Error
    Note over S: Log error
    S-->>C: 500 Internal Error
```
