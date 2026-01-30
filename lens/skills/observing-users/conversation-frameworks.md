# Conversation Frameworks

Reference material for generating follow-up conversation starters and recognizing weak signals.

---

## Framework Structure

When generating conversation frameworks for a canvas, follow this pattern:

### Template: Topic-Based Framework

```markdown
**If they mention [{extracted topic}]:**
- Opener: "You mentioned [their exact words]. How did that go?"
- Dig deeper: "Walk me through what happened."
- Past behavior: "When was the last time you [related action]?"
```

### Template: Action-Based Framework

```markdown
**If they complete [{anticipated action}]:**
- Opener: "How did [action] feel?"
- Dig deeper: "Anything unexpected?"
- Comparison: "How does that compare to before?"
```

### Template: Return Visit Framework

```markdown
**When this user returns:**
- Anchor: Reference their exact words from last quote
- Check: Did they follow through on any promises?
- Expand: Ask about related behaviors, not just the stated topic
```

---

## Red Flags Reference

Listen for these patterns that indicate **weak signal**:

| Red Flag | What it means | Better follow-up |
|----------|---------------|------------------|
| "I would probably..." | Hypothetical, not real | "When did you last actually do X?" |
| "That sounds useful" | Politeness | "What would you use it for specifically?" |
| "Everyone wants..." | Projection | "Tell me about YOUR experience" |
| "I might try..." | Future promise | Add to Promise table, validate later |
| "It seems like..." | Opinion, not behavior | "Walk me through what you actually did" |
| "I think I would..." | Hypothetical self | "What did you do last time this came up?" |

---

## Green Flags Reference

These patterns indicate **strong signal**:

| Green Flag | What it means | How to expand |
|------------|---------------|---------------|
| "Last week I..." | Specific past behavior | "What happened next?" |
| "I've been doing X workaround" | Real pain, evidence of need | "How long have you been doing that?" |
| "Let me show you my spreadsheet" | Commitment through action | "Walk me through how you use it" |
| "I check every morning before..." | Workflow integration | "What do you do with that information?" |
| "The last time I did X, Y happened" | Concrete incident | "How did you handle that?" |

---

## Mom Test Principles (Quick Reference)

### The Five Rules

1. **Talk about their life, not your idea**
2. **Ask about specifics in the past, not generics about the future**
3. **Talk less, listen more**
4. **Seek disconfirming evidence**
5. **Push for commitment or advancement**

### Question Transforms

| Bad (Opinion) | Good (Behavior) |
|---------------|-----------------|
| "Would you use X?" | "How do you handle X today?" |
| "Is this useful?" | "When did you last need this?" |
| "Do you want Y?" | "Tell me about a time Y would have helped" |
| "How often would you..." | "How often did you..." |
| "What do you think of..." | "What did you do when..." |

---

## Promise Detection

### Signal Words to Flag

When any of these appear in a quote, add to the Future Promises table:

| Category | Words/Phrases |
|----------|---------------|
| Future intent | will, would, might, going to, plan to |
| Temporal | later, tomorrow, soon, eventually, next week |
| Conditional | if I..., when I..., once I... |
| Hedged | probably, maybe, I think I'll |

### Promise Table Entry Format

```markdown
| Promise | Date | Follow-up Trigger |
|---------|------|-------------------|
| "{exact quoted promise}" | {today's date} | {condition for follow-up} |
```

### Example Triggers

| Promise Type | Follow-up Trigger |
|--------------|-------------------|
| "I'll migrate later" | If returns within 7 days / if doesn't migrate by {date} |
| "I might try burning tomorrow" | Next conversation / check if action completed |
| "I'm going to set up a threshold" | Ask about threshold in next session |

---

## Generating Frameworks from Quotes

### Process

1. **Extract topics**: What specific things did they mention?
2. **Identify actions**: What did they say they might do?
3. **Note promises**: What did they commit to (even weakly)?
4. **Create openers**: Use their exact words as anchors
5. **Add red flag listeners**: What weak signals should we watch for?

### Example Transformation

**Input Quote**: "ser im planning some henlo burns, will check the sidebar later"

**Generated Frameworks**:

```markdown
**If they mention burn planning:**
- Opener: "You mentioned planning some burns. How's that going?"
- Dig deeper: "Walk me through how you decide when to burn."
- Past behavior: "When was your last burn? What triggered that decision?"

**If they return:**
- Opener: "Last time you mentioned checking the sidebar - did you get a chance?"
- Dig deeper: "What were you looking for specifically?"

**Red flags to listen for:**
- "I would probably burn when..." (hypothetical)
- "That burn feature sounds useful" (politeness)
- "I'll definitely try it" (another promise without action)
```

---

## Anti-Patterns

### What NOT to Generate

1. **Generic template questions**: "Would you find X useful?"
2. **Leading questions**: "Don't you think the sidebar is helpful?"
3. **Multiple choice**: "Do you prefer A, B, or C?"
4. **Closed questions**: "Did you like the feature?" (yes/no)
5. **Opinion requests**: "What do you think we should build?"

### Instead, Always

1. **Anchor to their words**: Use exact phrases from their quotes
2. **Ask about past behavior**: "When did you last..."
3. **Request specifics**: "Walk me through..."
4. **Stay curious**: "Tell me more about..."
5. **Seek disconfirmation**: "What doesn't work about this?"
