# Cultural Context (Berachain/Crypto)

Reference material for interpreting user signals in crypto community contexts.

---

## Low-Signal Patterns (Cultural Noise)

These patterns are common in crypto communities and should **NOT** be used for user classification:

| Pattern | Meaning | NOT an indicator of |
|---------|---------|---------------------|
| "ser" / "fren" | Respect/community marker | Formality or personality |
| "gm" / "henlo" | Standard greeting | Engagement level |
| Ironic usernames | Self-deprecation common | Actual profession/status |
| Number suffixes | Often random/meme | Technical sophistication |
| "wagmi" / "ngmi" | Community sentiment | Actual conviction |
| Animal/food PFPs | Community identity | Seriousness level |

### Username Examples

| Username | Wrong Interpretation | Correct Stance |
|----------|---------------------|----------------|
| `3figscapital` | "Fund manager" | Likely ironic (self-deprecating about portfolio size) |
| `degentrader420` | "Reckless gambler" | Unknown - could be careful investor with meme name |
| `papabear_eth` | "Experienced whale" | Unknown - username tells us nothing |
| `ngmi_larry` | "Pessimist" | Unknown - likely humorous |

**Default**: Treat all usernames as **opaque identifiers** with no signal value.

---

## Higher-Signal Patterns

These patterns tend to carry genuine meaning:

| Pattern | Usually indicates |
|---------|-------------------|
| Specific questions | Clear intent to act |
| Unprompted detail | Genuine investment in topic |
| Time-specific actions | Real behavior ("I checked this morning") |
| Workarounds described | Actual pain point |
| Numbers mentioned | Concrete stakes ("my 50k HENLO") |
| Comparison to alternatives | Active decision-making |
| Frustration with timing | Time-sensitive goals |

### Strong Signal Examples

| Quote | Signal | Why it's meaningful |
|-------|--------|---------------------|
| "I check every morning before work" | Habitual behavior | Specific, past tense, integrated into routine |
| "I've been using a spreadsheet to track" | Workaround | Evidence of real need (effort spent) |
| "Last time I burned, I miscalculated" | Past behavior + pain | Specific incident, emotional weight |
| "My 50k threshold isn't working" | Concrete goal | Specific number, shows planning |

---

## Default Stance

When analyzing quotes from Berachain/crypto users:

1. **Each user's context is unique** - Resist pattern-matching to "types"
2. **Usernames are noise** - Never infer profession, wealth, or personality
3. **Cultural phrases are greetings** - "ser", "gm", "henlo" are politeness markers
4. **When uncertain, note uncertainty explicitly** - Use "Unknown" field
5. **Prefer "Unknown" over speculation** - Empty Unknown field is a red flag

---

## Confidence Calibration

| Evidence Level | Confidence | Example |
|----------------|------------|---------|
| Single greeting | None | "gm ser" |
| Single short quote | Low | "rewards not updating" |
| Quote with specific detail | Low-Medium | "I check my 50k threshold daily" |
| Multiple quotes, same topic | Medium | 3 quotes about burn timing |
| Observed behavior over time | Medium-High | Returned, completed action discussed |

**Never assign High confidence** from user research canvases alone. High confidence requires:
- Observed behavior matching stated intent
- Multiple independent data points
- Validation through follow-up conversation
