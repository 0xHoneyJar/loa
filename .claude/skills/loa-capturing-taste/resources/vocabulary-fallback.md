# Vocabulary Fallback

When no vocabulary is loaded, @intent is freeform. This document provides guidance for common patterns.

## Behavior Without Vocabulary

1. Show warning: "No vocabulary loaded. @intent is freeform."
2. Capture user's description as-is
3. Do not validate against any labels
4. Continue normally (not blocking)

## Common Freeform Patterns

When users describe @feel, common themes emerge:

| User Says | Likely Intent |
|-----------|---------------|
| "anxious", "worried", "uncertain" | Reduce anxiety |
| "confused", "lost", "overwhelmed" | Help understand |
| "excited", "celebrating", "achieved" | Create delight |
| "trust", "secure", "safe" | Build confidence |
| "quick", "efficient", "expert" | Enable mastery |

## Example Freeform @intent

Without vocabulary:
```
@intent Heavy, deliberate - users should feel the system is working hard
```

With vocabulary (HivemindOS):
```
@intent [J] Reduce My Anxiety
```

## Upgrade Path

When HivemindOS is connected:
1. Freeform @intent can be migrated to validated labels
2. Agent can suggest: "Your freeform intent maps to [J] Reduce My Anxiety"
3. User confirms, proto-bead updated

## Why Freeform is Okay

Freeform @intent is valuable:
- Captures tacit knowledge immediately
- Doesn't block on vocabulary setup
- Provides upgrade hook to HivemindOS
- User's exact words preserved

The "upgrade hook" is that freeform intent can become validated intent when vocabulary is available.
