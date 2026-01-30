---
type: cultural-context-base
name: crypto-base
version: 1.0.0
description: Universal crypto community patterns for user research
---

# Cultural Context (Crypto Base)

Reference material for interpreting user signals in crypto community contexts.

---

## Low-Signal Patterns (Cultural Noise)

<!-- @table:low-signal-patterns [merge-mode:append] -->

These patterns are common in crypto communities and should **NOT** be used for user classification:

| Pattern | Meaning | NOT an indicator of |
|---------|---------|---------------------|
| "ser" / "fren" | Respect/community marker | Formality or personality |
| "gm" | Standard greeting | Engagement level |
| Ironic usernames | Self-deprecation common | Actual profession/status |
| Number suffixes | Often random/meme | Technical sophistication |
| "wagmi" / "ngmi" | Community sentiment | Actual conviction |
| Animal/food PFPs | Community identity | Seriousness level |

<!-- @table:low-signal-patterns:end -->

### Username Examples

| Username | Wrong Interpretation | Correct Stance |
|----------|---------------------|----------------|
| `degentrader420` | "Reckless gambler" | Unknown - could be careful investor with meme name |
| `ngmi_larry` | "Pessimist" | Unknown - likely humorous |

**Default**: Treat all usernames as **opaque identifiers** with no signal value.

---

## Higher-Signal Patterns

<!-- @table:high-signal-patterns [merge-mode:append] -->

These patterns tend to carry genuine meaning:

| Pattern | Usually indicates |
|---------|-------------------|
| Specific questions | Clear intent to act |
| Unprompted detail | Genuine investment in topic |
| Time-specific actions | Real behavior ("I checked this morning") |
| Workarounds described | Actual pain point |
| Numbers mentioned | Concrete stakes |
| Comparison to alternatives | Active decision-making |
| Frustration with timing | Time-sensitive goals |

<!-- @table:high-signal-patterns:end -->

### Strong Signal Examples

| Quote | Signal | Why it's meaningful |
|-------|--------|---------------------|
| "I check every morning before work" | Habitual behavior | Specific, past tense, integrated into routine |
| "I've been using a spreadsheet to track" | Workaround | Evidence of real need (effort spent) |

---

## Default Stance

When analyzing quotes from crypto users:

1. **Each user's context is unique** - Resist pattern-matching to "types"
2. **Usernames are noise** - Never infer profession, wealth, or personality
3. **Cultural phrases are greetings** - Standard community politeness markers
4. **When uncertain, note uncertainty explicitly** - Use "Unknown" field
5. **Prefer "Unknown" over speculation** - Empty Unknown field is a red flag

---

## Confidence Calibration

| Evidence Level | Confidence | Example |
|----------------|------------|---------|
| Single greeting | None | "gm" |
| Single short quote | Low | "rewards not updating" |
| Quote with specific detail | Low-Medium | "I check my threshold daily" |
| Multiple quotes, same topic | Medium | 3 quotes about same topic |
| Observed behavior over time | Medium-High | Returned, completed action discussed |

**Never assign High confidence** from user research canvases alone. High confidence requires:
- Observed behavior matching stated intent
- Multiple independent data points
- Validation through follow-up conversation
