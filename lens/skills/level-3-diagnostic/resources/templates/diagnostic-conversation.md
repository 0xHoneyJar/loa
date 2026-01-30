# Diagnostic Conversation Template

## Flow

```
1. USER REPORTS ISSUE
   ↓
2. ASK LEVEL 3 QUESTION
   "What were you trying to do when you noticed?"
   ↓
3. TRACE THE SOURCE (if specific expectation mentioned)
   "Where does that expectation come from?"
   ↓
4. CHECK AGAINST EXISTING FEATURES
   "[Feature] does this — is it not working or something else?"
   ↓
5. UNDERSTAND THE WORKFLOW (if decision-maker)
   "What decision are you trying to make with this info?"
   ↓
6. INVESTIGATE / FIX with full context
   ↓
7. VALIDATE
   "You mentioned you were [goal]. Does this solve that?"
   ↓
8. LOG INSIGHT
```

---

## Question Bank

### Opening (Level 3)

- "What were you trying to do when you noticed this?"
- "Walk me through what happened"
- "What were you hoping to accomplish?"

### Tracing Expectations

- "Where does [specific expectation] come from? Did you see that somewhere?"
- "Is that how other protocols work for you?"
- "Did you read this in our docs, or is it an assumption?"

### Checking Existing Solutions

- "[Feature] shows this — is it not updating for you, or is it something else you need?"
- "Did you know about [feature]? Is it not visible, or not what you need?"
- "The sidebar/dashboard shows this — is that not working?"

### Understanding Workflow

- "What info do you need to make that decision?"
- "How do you decide when to [action]?"
- "What would you do differently if you had this information?"

### Trust/Frequency

- "What makes you check? Just habit or looking for something specific?"
- "What would make you confident it's working without checking?"
- "How often do you usually check this?"

### Validation

- "You mentioned you were trying to [goal]. Does this solve that for you?"
- "Is this what you needed, or is something still missing?"

---

## Response Interpretation

### When They Say... → They Mean...

| Surface Response | Underlying Need |
|------------------|-----------------|
| "Just curious" | Trust verification (need confidence signal) |
| "It should update faster" | Want to see progress (engagement need) |
| "The button doesn't work" | May be expectation gap, not bug |
| "Other protocols do X" | Benchmark expectation (competitive) |
| "I assumed" | Expectation gap (docs opportunity) |
| "I read it in docs" | Promise broken (fix or clarify) |

---

## Insight Capture Format

After conversation, log:

```markdown
## [Date] | [User/Channel]

### Level 3 Goal
[What were they actually trying to accomplish]

### User Type
[Decision-maker / Builder-minded / Trust-checker / Passive]

### Behavioral Evidence
- [What they actually did]
- [Workarounds they built]
- [Time/money invested]

### Expectation Gap
| Expected | Actual | Source |
|----------|--------|--------|
| [their expectation] | [system behavior] | [where it came from] |

### Workflow Dependency
[If they depend on product for decisions, what do they need?]

### Action Items
- [ ] [Specific action with context]
```
