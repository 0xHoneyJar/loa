# /gpt-review Command

Cross-model review using GPT 5.2 to catch issues Claude might miss.

## Usage

```bash
/gpt-review <type> [file]
```

**Types:**
- `code` - Review code changes (git diff or specified files)
- `prd` - Review Product Requirements Document
- `sdd` - Review Software Design Document
- `sprint` - Review Sprint Plan

**Examples:**
```bash
/gpt-review code                    # Review git diff
/gpt-review code src/auth.ts        # Review specific file
/gpt-review prd                     # Review grimoires/loa/prd.md
/gpt-review sdd grimoires/loa/sdd.md  # Review specific SDD
```

**To enable/disable:** Use `/toggle-gpt-review`

## How It Works

1. **Build context** from PRD/SDD (domain expertise + product context)
2. Run the script with context: `.claude/scripts/gpt-review-api.sh <type> <file> --augmentation <context>`
3. Script checks config - if disabled, returns `{"verdict": "SKIPPED", ...}`
4. If enabled, script calls GPT with full context
5. Handle the verdict

## Execution Steps

### Step 0: Build Context (MANDATORY)

**Before calling the API, you MUST build context for GPT.** This is not optional.

#### 0.1: Extract Domain Expertise

Read `grimoires/loa/prd.md` and identify the domain. Write a domain expertise statement:

```markdown
## Domain Expertise

You are an expert in [domain extracted from PRD]. You have deep knowledge of:
- [Key domain concept 1]
- [Key domain concept 2]
- [Relevant standards/protocols]
- [Common pitfalls in this domain]
```

**Examples by domain:**

| PRD Domain | Domain Expertise |
|------------|------------------|
| Crypto wallet | "Expert in cryptocurrency wallets, HD key derivation (BIP-32/39/44), secure key storage, transaction signing" |
| ML pipeline | "Expert in machine learning infrastructure, model training, data pipelines, GPU optimization, MLOps" |
| Healthcare app | "Expert in healthcare software, HIPAA compliance, HL7/FHIR standards, PHI protection" |
| Fintech | "Expert in financial software, PCI-DSS compliance, transaction processing, fraud detection" |
| E-commerce | "Expert in e-commerce platforms, payment processing, inventory management, order fulfillment" |

#### 0.2: Extract Product Context

From PRD, write a 2-3 sentence product summary:

```markdown
## Product Context

[Product name] is [what it does] for [target users].
Key requirements: [critical requirements from PRD].
Security/compliance: [any security or compliance requirements].
```

#### 0.3: Extract Feature Context (for code reviews)

For code reviews, describe what the code is supposed to do. This varies by context:

**During sprint execution (formal tasks):**
1. Check `grimoires/loa/NOTES.md` Current Focus for active task
2. Check `grimoires/loa/sprint.md` for task description and acceptance criteria

```markdown
## Feature Context

**Task**: [Task ID and title from sprint.md]
**Purpose**: [What this code is supposed to do]
**Acceptance Criteria**:
- [Criterion 1 from sprint.md]
- [Criterion 2]
- [Criterion 3]
```

**For ad-hoc work (quick fixes, feature upgrades, experiments):**
When there's no formal sprint task, describe what you're trying to accomplish:

```markdown
## Feature Context

**Goal**: [What you're trying to accomplish]
**Approach**: [How this code achieves that goal]
**Expected Behavior**:
- [What the code should do]
- [Edge cases it should handle]
- [Any constraints or requirements]
```

**Examples of ad-hoc context:**

| Scenario | Feature Context |
|----------|-----------------|
| Bug fix | "Goal: Fix race condition in auth refresh. Approach: Add mutex lock around token refresh. Expected: Only one refresh request at a time, others wait." |
| Quick feature | "Goal: Add copy-to-clipboard for wallet address. Approach: Use Clipboard API with fallback. Expected: Works on all browsers, shows feedback toast." |
| Refactor | "Goal: Extract validation logic into reusable module. Approach: Create validation utility with composable rules. Expected: Same behavior, better testability." |
| Experiment | "Goal: Test new caching strategy for API calls. Approach: LRU cache with 5-min TTL. Expected: Reduce API calls by ~50%, handle cache invalidation." |

#### 0.4: Extract Relevant SDD Design (for code reviews)

For code reviews, extract the relevant component design from SDD:

```markdown
## Relevant Architecture

From SDD [component name]:
- [Key design decisions]
- [Data flow]
- [Dependencies]
- [Security considerations for this component]
```

#### 0.5: Write Context File

Combine all sections into `/tmp/gpt-review-context.md`:

```markdown
## Domain Expertise

You are an expert in [domain]. You have deep knowledge of [specifics].

## Product Context

[Product summary from PRD]

## Feature Context

**Task**: [Task being implemented]
**Acceptance Criteria**: [From sprint.md]

## Relevant Architecture

[Relevant SDD excerpt]

## What to Verify

Given the above context, verify that:
1. The code/document correctly implements the requirements
2. Domain-specific best practices are followed
3. Security requirements are met
4. The implementation matches the architecture
```

### Step 1: Prepare Content

**For code reviews:**
```bash
# Get git diff or file content
if [[ -n "$file" ]]; then
  content_file="$file"
else
  git diff HEAD > /tmp/gpt-review-content.txt
  content_file="/tmp/gpt-review-content.txt"
fi
```

**For document reviews:**
```bash
# Default paths
case "$type" in
  prd) content_file="${file:-grimoires/loa/prd.md}" ;;
  sdd) content_file="${file:-grimoires/loa/sdd.md}" ;;
  sprint) content_file="${file:-grimoires/loa/sprint.md}" ;;
esac
```

### Step 2: Run Review Script (First Iteration)

**ALWAYS include --augmentation with the context file:**

```bash
# First review with context
context_file="/tmp/gpt-review-context.md"
response=$(.claude/scripts/gpt-review-api.sh "$type" "$content_file" \
  --augmentation "$context_file")
verdict=$(echo "$response" | jq -r '.verdict')

# IMPORTANT: Save findings for potential re-review
echo "$response" > /tmp/gpt-review-findings-1.json
iteration=1
```

### Step 3: Handle Verdict

```bash
case "$verdict" in
  SKIPPED)
    echo "GPT review disabled - continuing"
    # Done, no action needed
    ;;

  APPROVED)
    echo "GPT review passed"
    # Done, continue with next step
    ;;

  CHANGES_REQUIRED)
    # Fix the issues, then go to Step 4 (Re-Review Loop)
    ;;

  DECISION_NEEDED)
    # Extract question and ask user
    question=$(echo "$response" | jq -r '.question')
    # Use AskUserQuestion tool to get user input
    # Continue with user's answer
    ;;
esac
```

### Step 4: Re-Review Loop (CRITICAL for CHANGES_REQUIRED)

When GPT returns `CHANGES_REQUIRED`, you MUST:

1. Fix the issues GPT identified
2. Run a re-review with **iteration number**, **previous findings**, and **context**

```bash
# After fixing issues from iteration N, run iteration N+1:
iteration=$((iteration + 1))
previous_findings="/tmp/gpt-review-findings-$((iteration - 1)).json"
context_file="/tmp/gpt-review-context.md"

response=$(.claude/scripts/gpt-review-api.sh "$type" "$content_file" \
  --augmentation "$context_file" \
  --iteration "$iteration" \
  --previous "$previous_findings")

verdict=$(echo "$response" | jq -r '.verdict')

# Save this iteration's findings for potential next iteration
echo "$response" > "/tmp/gpt-review-findings-${iteration}.json"

# Loop until APPROVED or max iterations reached
```

## Context Building by Review Type

### PRD Reviews

For PRD reviews, the context is lighter since the PRD itself describes the product:

```markdown
## Domain Expertise

You are an expert in [domain from PRD problem statement].
You specialize in [relevant domain knowledge].

## Review Focus

This is a Product Requirements Document for [product type].
Pay special attention to:
- [Domain-specific requirements that are often missed]
- [Compliance requirements for this domain]
- [Common pitfalls in this product category]
```

### SDD Reviews

For SDD reviews, include PRD context:

```markdown
## Domain Expertise

You are an expert in [domain] software architecture.

## Product Context

From PRD: [Key requirements that the SDD must satisfy]

## Review Focus

Verify the architecture addresses:
- [Key PRD requirements]
- [Domain-specific architectural concerns]
- [Security/compliance from PRD]
```

### Sprint Reviews

For sprint reviews, include both PRD and SDD context:

```markdown
## Domain Expertise

You are an expert in [domain] and agile sprint planning.

## Product Context

[Product summary from PRD]

## Architecture Context

[Key architectural constraints from SDD]

## Review Focus

Verify the sprint plan:
- Maps to PRD requirements (traceability)
- Respects SDD architecture
- Has measurable acceptance criteria
- Correctly estimates complexity for this domain
```

### Code Reviews

For code reviews, provide the fullest context:

```markdown
## Domain Expertise

You are an expert in [domain]. You have deep knowledge of:
- [Domain-specific technologies]
- [Security requirements for this domain]
- [Common vulnerabilities in this type of code]

## Product Context

[Product summary] for [target users].
Critical requirements: [from PRD]

## Feature Context

**Task**: [Task ID] - [Title]
**Purpose**: [What this code implements]
**Acceptance Criteria**:
- [Criterion 1]
- [Criterion 2]

## Relevant Architecture

From SDD [component]:
- Design: [Key decisions]
- Data flow: [How data moves]
- Security: [Security requirements for this component]

## What to Verify

1. Code correctly implements the task
2. Acceptance criteria can be met
3. Follows the SDD architecture
4. No domain-specific security issues
5. No fabrication (hardcoded values that should be calculated)
```

## Complete Example (Sprint Task)

```bash
# === STEP 0: BUILD CONTEXT ===
# Read PRD for domain and product context
# Read sprint.md for task and acceptance criteria
# Read SDD for relevant component design
# Write to /tmp/gpt-review-context.md

cat > /tmp/gpt-review-context.md << 'EOF'
## Domain Expertise

You are an expert in cryptocurrency wallet development. You have deep knowledge of:
- HD wallet key derivation (BIP-32, BIP-39, BIP-44)
- Secure cryptographic implementations
- Private key protection and memory safety
- Common wallet vulnerabilities (key leakage, weak entropy)

## Product Context

CryptoVault is a non-custodial multi-chain wallet for retail crypto users.
Critical requirements: Secure key derivation, support for ETH/BTC/SOL, offline signing capability.
Security: Keys must never leave the device, all crypto ops must be constant-time.

## Feature Context

**Task**: Sprint-1 Task 2.3 - Implement HD key derivation from seed phrase
**Purpose**: Derive child keys from BIP-39 mnemonic for multi-chain support
**Acceptance Criteria**:
- Correctly derives master key from 12/24 word mnemonic
- Supports BIP-44 derivation paths for ETH, BTC, SOL
- Passes BIP-32 test vectors
- Keys are zeroed from memory after use

## Relevant Architecture

From SDD Wallet Core Component:
- Design: Modular crypto layer with chain-specific derivation
- Data flow: Mnemonic → Master Key → Chain Keys → Addresses
- Security: All key material in secure memory, constant-time operations

## What to Verify

1. Key derivation matches BIP-32/39/44 specifications
2. Memory is properly zeroed after key operations
3. No key material logged or exposed
4. Entropy source is cryptographically secure
5. No hardcoded test keys or mnemonics
EOF

# === STEP 1: PREPARE CONTENT ===
content_file="src/wallet/keyDerivation.ts"

# === STEP 2: RUN REVIEW ===
response=$(.claude/scripts/gpt-review-api.sh code "$content_file" \
  --augmentation /tmp/gpt-review-context.md)
echo "$response" > /tmp/gpt-review-findings-1.json
verdict=$(echo "$response" | jq -r '.verdict')
iteration=1

# === STEP 3: HANDLE VERDICT ===
# ... handle as described above ...
```

## Complete Example (Ad-hoc Quick Fix)

For work outside of formal sprints (bug fixes, quick features, experiments):

```bash
# === STEP 0: BUILD CONTEXT ===
# Even for quick fixes, provide domain expertise and explain what you're doing

cat > /tmp/gpt-review-context.md << 'EOF'
## Domain Expertise

You are an expert in React and browser APIs. You have deep knowledge of:
- Clipboard API and browser compatibility
- React state management and hooks
- User feedback patterns and accessibility
- Cross-browser testing considerations

## Product Context

CryptoVault wallet app - users need to copy wallet addresses frequently.
This is a UX improvement, not security-critical.

## Feature Context

**Goal**: Add copy-to-clipboard functionality for wallet addresses
**Approach**:
- Use navigator.clipboard API with execCommand fallback for older browsers
- Show toast notification on success/failure
- Add visual feedback on the copy button

**Expected Behavior**:
- Clicking copy button copies address to clipboard
- Toast appears confirming success or explaining failure
- Works on Chrome, Firefox, Safari (desktop and mobile)
- Accessible via keyboard (Enter/Space on focused button)

## What to Verify

1. Clipboard API used correctly with proper error handling
2. Fallback works for browsers without clipboard API
3. User feedback is clear and accessible
4. No security issues with clipboard access
5. Component handles edge cases (empty address, very long address)
EOF

# === STEP 1: PREPARE CONTENT ===
content_file="src/components/AddressCopyButton.tsx"

# === STEP 2: RUN REVIEW ===
response=$(.claude/scripts/gpt-review-api.sh code "$content_file" \
  --augmentation /tmp/gpt-review-context.md)
# ... continue as normal ...
```

## Configuration

The script checks `.loa.config.yaml`:

```yaml
gpt_review:
  enabled: true              # Master toggle
  timeout_seconds: 300       # API timeout
  max_iterations: 3          # Auto-approve after this many
  models:
    documents: "gpt-5.2"     # For PRD, SDD, Sprint
    code: "gpt-5.2-codex"    # For code reviews
  phases:
    prd: true                # Enable/disable per type
    sdd: true
    sprint: true
    implementation: true
```

## Environment

- `OPENAI_API_KEY` - Required (can also be in `.env` file)

## Verdicts

| Verdict | Code Review | Document Review |
|---------|-------------|-----------------|
| SKIPPED | Review disabled | Review disabled |
| APPROVED | No bugs found | No blocking issues |
| CHANGES_REQUIRED | Has bugs to fix | Has issues that would cause failure |
| DECISION_NEEDED | N/A (not used) | Design choice for user to decide |

## Error Handling

| Exit Code | Meaning | Action |
|-----------|---------|--------|
| 0 | Success (includes SKIPPED) | Continue |
| 1 | API error | Retry or skip |
| 2 | Invalid input | Check arguments |
| 3 | Timeout | Retry with longer timeout |
| 4 | Missing API key | Set OPENAI_API_KEY |
| 5 | Invalid response | Retry |
