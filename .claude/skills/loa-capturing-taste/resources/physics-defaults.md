# Physics Defaults by Feel

When capturing physics for Gold components, suggest defaults based on @feel.

## Mapping Table

| Feel Pattern | Tension | Friction | Delay | Duration |
|--------------|---------|----------|-------|----------|
| heavy, deliberate, slow, weighty | 120 | 14 | 200 | 800 |
| snappy, instant, quick, fast | 400 | 30 | 0 | 0 |
| bouncy, playful, fun, springy | 80 | 10 | 100 | 400 |
| smooth, gentle, soft | 100 | 20 | 50 | 300 |
| (default fallback) | 170 | 26 | 0 | 0 |

## Usage

During graduation, after reading @feel:

```
Agent: "Based on @feel 'heavy, deliberate', I suggest:
        - Tension: 120
        - Friction: 14
        - Delay: 200ms
        - Duration: 800ms

        Accept defaults or provide custom values?"
```

## Validation Ranges

| Parameter | Valid Range |
|-----------|-------------|
| Tension | 1-500 |
| Friction | 1-50 |
| Delay | 0-2000 ms |
| Duration | 0-5000 ms |

If user provides out-of-range values, clamp and warn:

```
"Tension 600 is out of range (1-500). Using 500."
```
