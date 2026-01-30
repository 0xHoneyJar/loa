---
name: nats-jetstream-consumer-durable
description: |
  Fix for NATS JetStream consumer losing position after restart. Use when
  consumer stops receiving messages after process restart. Implements durable
  consumer name for persistent subscription state.
loa-agent: implementing-tasks
extracted-from: sprint-7-task-3
extraction-date: 2026-01-18
version: 1.0.0
tags:
  - nats
  - jetstream
  - messaging
  - durability
  - consumers
---

# NATS JetStream Consumer Position Lost After Restart

## Problem

Consumer stops receiving messages after process restart. All messages published
during downtime are lost because consumer doesn't remember its position.

---

## Trigger Conditions

### Symptoms

- Consumer works initially, fails after restart
- No error messages - just silent message loss
- Works fine when consuming from beginning
- Messages published during downtime never received

### Error Messages

No explicit error - the failure is silent. Consumer simply doesn't receive
messages that were published while it was down.

### Context

| Context | Value |
|---------|-------|
| Technology Stack | NATS JetStream |
| Environment | Any with process restarts |
| Timing | After consumer process restart |
| Prerequisites | NATS Server with JetStream enabled |

---

## Root Cause

Ephemeral consumers don't persist their position. On restart, a new ephemeral
consumer is created with no memory of previous position. The consumer starts
fresh, missing all messages from the downtime period.

JetStream maintains message position per consumer name. Without a durable name,
each connection creates a new anonymous consumer that starts at the stream's
current position.

---

## Solution

### Step 1: Add Durable Name

Add the `durable` option to your consumer subscription. This tells JetStream
to persist the consumer state under that name.

```typescript
const sub = await js.subscribe('orders.>', {
  durable: 'my-service-orders', // Add this line - persistent consumer name
  deliverTo: createInbox(),
});
```

### Step 2: Verify Consumer Persistence

Confirm the consumer is now durable by checking JetStream.

```bash
nats consumer info ORDERS my-service-orders
```

### Complete Example

```typescript
import { connect, JetStreamClient, StringCodec } from 'nats';

async function setupDurableConsumer() {
  const nc = await connect({ servers: 'nats://localhost:4222' });
  const js = nc.jetstream();
  const sc = StringCodec();

  // Create durable consumer - survives restarts
  const sub = await js.subscribe('orders.>', {
    durable: 'my-service-orders',  // KEY: Makes consumer persistent
    ackPolicy: AckPolicy.Explicit,
    deliverPolicy: DeliverPolicy.All,
  });

  console.log('Durable consumer connected');

  for await (const m of sub) {
    console.log(`Received: ${sc.decode(m.data)}`);
    m.ack();  // Explicit ack moves the cursor
  }
}
```

---

## Verification

### Command

```bash
nats consumer info ORDERS my-service-orders
```

### Expected Output

```
Information for Consumer ORDERS > my-service-orders

Configuration:
     Durable Name: my-service-orders
        ...
        Ack Policy: explicit
        Ack Wait: 30s
        ...

State:
   Last Delivered Message: Consumer sequence: 42 Stream sequence: 42
     Acknowledgement floor: Consumer sequence: 42 Stream sequence: 42
         Outstanding Acks: 0 out of maximum 1,000
```

### Checklist

- [ ] Consumer shows "Durable Name" in info output
- [ ] "Last Delivered Message" shows non-zero sequence after restart
- [ ] Messages published during downtime are received after restart
- [ ] No silent message loss observed

---

## Anti-Patterns

### Don't: Use ephemeral consumers for persistent processing

```typescript
// BAD - position lost on restart
const sub = await js.subscribe('orders.>');
```

Without `durable`, every restart creates a new consumer starting fresh.

### Don't: Use generic durable names across services

```typescript
// BAD - conflicts between services
const sub = await js.subscribe('orders.>', {
  durable: 'orders-consumer',  // Too generic!
});
```

Use service-specific names like `billing-service-orders` to avoid conflicts.

### Don't: Forget explicit acks with durable consumers

```typescript
// BAD - auto-ack doesn't advance cursor predictably
const sub = await js.subscribe('orders.>', {
  durable: 'my-service-orders',
  // Missing: ackPolicy: AckPolicy.Explicit
});
```

Always use explicit acks with durable consumers for reliable cursor advancement.

---

## Related Resources

- [NATS JetStream Documentation](https://docs.nats.io/nats-concepts/jetstream)
- [NATS Consumer Types](https://docs.nats.io/nats-concepts/jetstream/consumers)
- [NATS TypeScript Client](https://github.com/nats-io/nats.js)

---

## Related Memory

### NOTES.md References

- `## Learnings`: "JetStream consumers need durable names for restart persistence"
- `## Technical Debt`: None - this is a configuration fix

### Related Skills

- `nats-jetstream-replay-policy`: How to configure message replay on consumer creation
- `nats-connection-retry`: Handling NATS connection drops gracefully

---

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-01-18 | Initial extraction from sprint-7 debugging session |

---

## Metadata (Auto-Generated)

```yaml
quality_gates:
  discovery_depth: true    # Required debugging, not obvious from error
  reusability: true        # Common NATS pattern, applies broadly
  trigger_clarity: true    # Clear symptoms and context
  verification: true       # Verified with nats CLI
extraction_source:
  agent: implementing-tasks
  phase: /implement
  sprint: sprint-7
  task: task-3
```
