# State Machine / Lifecycle Diagram Template

Use this template for state machines, status flows, and lifecycle diagrams.

## Template

```mermaid
stateDiagram-v2
    %% ===== CUSTOMIZATION POINTS =====
    %% 1. Replace state names
    %% 2. Update transitions and labels
    %% 3. Add guards [condition]
    %% 4. Add composite states if needed

    [*] --> Draft : create

    Draft --> Pending : submit
    Draft --> Cancelled : cancel

    Pending --> Approved : approve
    Pending --> Rejected : reject
    Pending --> Draft : request_changes

    Approved --> Active : activate
    Approved --> Cancelled : cancel

    Active --> Completed : complete
    Active --> Paused : pause
    Active --> Cancelled : cancel

    Paused --> Active : resume
    Paused --> Cancelled : cancel

    Rejected --> Draft : revise
    Rejected --> [*] : archive

    Completed --> [*]
    Cancelled --> [*]

    note right of Pending
        Awaiting review
        by approver
    end note
```

## Preview URL Pattern

```
> **Preview**: [View diagram](https://agents.craft.do/mermaid?code={base64}&theme=github)
```

## Usage Notes

1. **Special States**:
   - `[*]` Start/End state
   - Use arrows from `[*]` for initial state
   - Use arrows to `[*]` for terminal states

2. **Transitions**: `StateA --> StateB : event`

3. **Notes**: `note right of State` / `note left of State`

4. **Direction**: Default is top-down, use `direction LR` for left-right

## Variations

### Order Lifecycle
```mermaid
stateDiagram-v2
    [*] --> Cart
    Cart --> Checkout : proceed
    Checkout --> Processing : pay
    Processing --> Shipped : ship
    Shipped --> Delivered : deliver
    Delivered --> [*]

    Processing --> Cancelled : cancel
    Cancelled --> [*]

    Shipped --> Returned : return
    Returned --> Refunded : process
    Refunded --> [*]
```

### User Account States
```mermaid
stateDiagram-v2
    [*] --> Pending : register
    Pending --> Active : verify_email
    Pending --> [*] : expire

    Active --> Suspended : suspend
    Suspended --> Active : reinstate
    Suspended --> Deleted : delete

    Active --> Deleted : delete
    Deleted --> [*]
```

### Composite States
```mermaid
stateDiagram-v2
    [*] --> Ready

    state Processing {
        [*] --> Validating
        Validating --> Executing
        Executing --> [*]
    }

    Ready --> Processing : start
    Processing --> Complete : success
    Processing --> Failed : error

    Complete --> [*]
    Failed --> Ready : retry
```

### Concurrent States
```mermaid
stateDiagram-v2
    [*] --> Active

    state Active {
        state "Payment" as P {
            [*] --> Unpaid
            Unpaid --> Paid
        }
        --
        state "Fulfillment" as F {
            [*] --> Unfulfilled
            Unfulfilled --> Fulfilled
        }
    }

    Active --> Complete : both_done
```
