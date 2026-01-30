# System Architecture Flowchart Template

Use this template for high-level system architecture diagrams.

## Template

```mermaid
graph TD
    %% ===== CUSTOMIZATION POINTS =====
    %% 1. Replace subgraph names with your system layers
    %% 2. Replace node labels [in brackets]
    %% 3. Add/remove connections as needed
    %% 4. Adjust direction: TD (top-down), LR (left-right)

    subgraph "Client Layer"
        A[Web App]
        B[Mobile App]
        C[CLI Tool]
    end

    subgraph "API Layer"
        D[API Gateway]
        E[Load Balancer]
    end

    subgraph "Service Layer"
        F[Auth Service]
        G[Core Service]
        H[Worker Service]
    end

    subgraph "Data Layer"
        I[(Primary DB)]
        J[(Cache)]
        K[Message Queue]
    end

    %% Client to API
    A --> D
    B --> D
    C --> D

    %% API to Services
    D --> E
    E --> F
    E --> G
    E --> H

    %% Services to Data
    F --> I
    G --> I
    G --> J
    H --> K
    K --> G
```

## Preview URL Pattern

```
> **Preview**: [View diagram](https://agents.craft.do/mermaid?code={base64}&theme=github)
```

## Usage Notes

1. **Subgraphs**: Group related components by logical layer
2. **Connections**: Use `-->` for data flow, `-.->` for optional/async
3. **Database nodes**: Use `[( )]` shape for databases
4. **Labels**: Keep concise but descriptive

## Variations

### Microservices Pattern
```mermaid
graph LR
    GW[API Gateway] --> S1[Service A]
    GW --> S2[Service B]
    S1 --> DB1[(DB A)]
    S2 --> DB2[(DB B)]
    S1 <-.-> S2
```

### Monolith Pattern
```mermaid
graph TD
    C[Client] --> M[Monolith App]
    M --> DB[(Database)]
    M --> Cache[(Redis)]
```
