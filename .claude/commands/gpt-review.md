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

GPT receives two prompts with full context:

1. **SYSTEM PROMPT** = Domain Expertise (WHO GPT is) + Review Instructions (HOW to review)
2. **USER PROMPT** = Product Context + Feature Context (WHAT we're reviewing) + Content (the actual code/doc)

You MUST build both before calling the API.

## Execution Steps

### Step 0: Build Domain Expertise (MANDATORY - SYSTEM PROMPT)

**YOU MUST READ `grimoires/loa/prd.md` AND EXTRACT THE ACTUAL DOMAIN.** Do not use placeholders.

Write expertise to `/tmp/gpt-review-expertise.md`:

```markdown
You are an expert in [ACTUAL DOMAIN FROM PRD]. You have deep knowledge of:
- [ACTUAL KEY CONCEPT 1 from PRD]
- [ACTUAL KEY CONCEPT 2 from PRD]
- [ACTUAL STANDARDS/PROTOCOLS for this domain]
- [ACTUAL COMMON PITFALLS in this domain]
```

**CRITICAL**: Replace ALL bracketed placeholders with REAL values from the PRD. Examples:

| If PRD is about... | Domain Expertise should say... |
|-------------------|-------------------------------|
| Crypto wallet | "You are an expert in cryptocurrency wallets. You have deep knowledge of: HD key derivation (BIP-32/39/44), secure key storage, transaction signing, common wallet vulnerabilities (key leakage, weak entropy)" |
| ML pipeline | "You are an expert in machine learning infrastructure. You have deep knowledge of: model training pipelines, data preprocessing, GPU optimization, MLOps practices, common ML bugs (data leakage, distribution shift)" |
| Healthcare app | "You are an expert in healthcare software. You have deep knowledge of: HIPAA compliance, HL7/FHIR standards, PHI protection, audit logging requirements, healthcare-specific security concerns" |
| E-commerce | "You are an expert in e-commerce platforms. You have deep knowledge of: payment processing (PCI-DSS), inventory management, order fulfillment, cart abandonment patterns, checkout optimization" |
| CLI tool | "You are an expert in command-line tool development. You have deep knowledge of: argument parsing, UNIX conventions, shell scripting integration, error handling patterns, cross-platform compatibility" |

### Step 1: Build Product & Feature Context (MANDATORY - USER PROMPT)

**YOU MUST READ THE ACTUAL PROJECT FILES AND FILL IN REAL VALUES.**

Write context to `/tmp/gpt-review-context.md`:

#### For Code Reviews

Read these files and extract ACTUAL content:
- `grimoires/loa/prd.md` - Product summary
- `grimoires/loa/NOTES.md` - Current task (if sprint work)
- `grimoires/loa/sprint.md` - Acceptance criteria (if sprint work)
- `grimoires/loa/sdd.md` - Relevant architecture

```markdown
## Product Context

[ACTUAL PRODUCT NAME] is [ACTUAL DESCRIPTION FROM PRD] for [ACTUAL TARGET USERS].
Critical requirements: [ACTUAL KEY REQUIREMENTS FROM PRD].
Security/compliance: [ACTUAL SECURITY REQUIREMENTS, or "None specified"].

## Feature Context

**Task**: [ACTUAL TASK ID AND TITLE, or describe what you're doing for ad-hoc work]
**Purpose**: [ACTUAL PURPOSE - what this code is supposed to do]
**Acceptance Criteria**:
- [ACTUAL CRITERION 1 from sprint.md or your goal]
- [ACTUAL CRITERION 2]
- [ACTUAL CRITERION 3]

## Relevant Architecture

From SDD [ACTUAL COMPONENT NAME]:
- Design: [ACTUAL DESIGN DECISIONS from SDD]
- Data flow: [ACTUAL DATA FLOW from SDD]
- Security: [ACTUAL SECURITY REQUIREMENTS for this component]

## What to Verify

Given the above context, verify:
1. Code correctly implements the task
2. Acceptance criteria can be met
3. Follows the SDD architecture
4. No domain-specific security issues
5. No fabrication (hardcoded values that should be calculated)
```

#### For Document Reviews (PRD/SDD/Sprint)

```markdown
## Product Context

This is a [PRD/SDD/Sprint Plan] for [ACTUAL PRODUCT NAME].
Domain: [ACTUAL DOMAIN from PRD].
Target users: [ACTUAL TARGET USERS from PRD].

## Review Focus

Pay special attention to:
- [ACTUAL DOMAIN-SPECIFIC CONCERNS]
- [ACTUAL COMPLIANCE/SECURITY REQUIREMENTS]
- [ACTUAL PITFALLS common in this domain]
```

### Step 2: Prepare Content File

**For code reviews:**
```bash
# Specific file
content_file="src/auth.ts"

# Or git diff
git diff HEAD > /tmp/gpt-review-content.txt
content_file="/tmp/gpt-review-content.txt"
```

**For document reviews:**
```bash
case "$type" in
  prd) content_file="${file:-grimoires/loa/prd.md}" ;;
  sdd) content_file="${file:-grimoires/loa/sdd.md}" ;;
  sprint) content_file="${file:-grimoires/loa/sprint.md}" ;;
esac
```

### Step 3: Run Review Script

**ALWAYS include both --expertise and --context.**

**Output path**: Use `--output` to persist findings to `grimoires/loa/a2a/gpt-review/`.
The directory is created automatically. Files are named by type and iteration for easy lookup.

```bash
expertise_file="/tmp/gpt-review-expertise.md"
context_file="/tmp/gpt-review-context.md"
output_dir="grimoires/loa/a2a/gpt-review"
output_file="${output_dir}/${type}-findings-1.json"

response=$(.claude/scripts/gpt-review-api.sh "$type" "$content_file" \
  --expertise "$expertise_file" \
  --context "$context_file" \
  --output "$output_file")

verdict=$(echo "$response" | jq -r '.verdict')
iteration=1
```

### Step 4: Handle Verdict

```bash
case "$verdict" in
  SKIPPED)
    echo "GPT review disabled - continuing"
    ;;
  APPROVED)
    echo "GPT review passed"
    ;;
  CHANGES_REQUIRED)
    # Fix the issues, then re-review (Step 5)
    ;;
  DECISION_NEEDED)
    question=$(echo "$response" | jq -r '.question')
    # Use AskUserQuestion tool, then continue
    ;;
esac
```

### Step 5: Re-Review Loop (for CHANGES_REQUIRED)

After fixing issues, run another review with iteration number and previous findings:

```bash
iteration=$((iteration + 1))
previous_findings="${output_dir}/${type}-findings-$((iteration - 1)).json"
output_file="${output_dir}/${type}-findings-${iteration}.json"

response=$(.claude/scripts/gpt-review-api.sh "$type" "$content_file" \
  --expertise "$expertise_file" \
  --context "$context_file" \
  --iteration "$iteration" \
  --previous "$previous_findings" \
  --output "$output_file")

verdict=$(echo "$response" | jq -r '.verdict')
```

## Complete Example: Sprint Task Code Review

```bash
# === STEP 0: BUILD DOMAIN EXPERTISE ===
# Read PRD to understand the domain
# This goes in the SYSTEM PROMPT

cat > /tmp/gpt-review-expertise.md << 'EOF'
You are an expert in cryptocurrency wallet development. You have deep knowledge of:
- HD wallet key derivation (BIP-32, BIP-39, BIP-44)
- Secure cryptographic implementations
- Private key protection and memory safety
- Common wallet vulnerabilities (key leakage, weak entropy)
- Constant-time cryptographic operations
EOF

# === STEP 1: BUILD CONTEXT ===
# Read PRD, sprint.md, SDD to understand what we're reviewing
# This goes in the USER PROMPT

cat > /tmp/gpt-review-context.md << 'EOF'
## Product Context

CryptoVault is a non-custodial multi-chain wallet for retail crypto users.
Critical requirements: Secure key derivation, support for ETH/BTC/SOL, offline signing.
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
- Data flow: Mnemonic -> Master Key -> Chain Keys -> Addresses
- Security: All key material in secure memory, constant-time operations

## What to Verify

1. Key derivation matches BIP-32/39/44 specifications
2. Memory is properly zeroed after key operations
3. No key material logged or exposed
4. Entropy source is cryptographically secure
5. No hardcoded test keys or mnemonics
EOF

# === STEP 2: PREPARE CONTENT ===
content_file="src/wallet/keyDerivation.ts"

# === STEP 3: RUN REVIEW ===
output_dir="grimoires/loa/a2a/gpt-review"
response=$(.claude/scripts/gpt-review-api.sh code "$content_file" \
  --expertise /tmp/gpt-review-expertise.md \
  --context /tmp/gpt-review-context.md \
  --output "${output_dir}/code-findings-1.json")
verdict=$(echo "$response" | jq -r '.verdict')
iteration=1

# === STEP 4: HANDLE VERDICT ===
# Continue based on verdict...
```

## Complete Example: Ad-hoc Quick Fix

For work outside formal sprints:

```bash
# === STEP 0: BUILD DOMAIN EXPERTISE ===
cat > /tmp/gpt-review-expertise.md << 'EOF'
You are an expert in React and browser APIs. You have deep knowledge of:
- Clipboard API and browser compatibility
- React state management and hooks
- User feedback patterns and accessibility
- Cross-browser testing considerations
EOF

# === STEP 1: BUILD CONTEXT ===
cat > /tmp/gpt-review-context.md << 'EOF'
## Product Context

CryptoVault wallet app - users need to copy wallet addresses frequently.
This is a UX improvement, not security-critical.

## Feature Context

**Goal**: Add copy-to-clipboard functionality for wallet addresses
**Approach**:
- Use navigator.clipboard API with execCommand fallback
- Show toast notification on success/failure
- Add visual feedback on the copy button

**Expected Behavior**:
- Clicking copy copies address to clipboard
- Toast confirms success or explains failure
- Works on Chrome, Firefox, Safari (desktop/mobile)
- Accessible via keyboard (Enter/Space)

## What to Verify

1. Clipboard API used correctly with proper error handling
2. Fallback works for browsers without clipboard API
3. User feedback is clear and accessible
4. No security issues with clipboard access
5. Handles edge cases (empty address, very long address)
EOF

# === STEP 2-4: Same as above ===
```

## Configuration

```yaml
# .loa.config.yaml
gpt_review:
  enabled: true              # Master toggle
  timeout_seconds: 300       # API timeout
  max_iterations: 3          # Auto-approve after this many
  models:
    documents: "gpt-5.2"     # For PRD, SDD, Sprint
    code: "gpt-5.2-codex"    # For code reviews (gpt-5.3-codex when API available)
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
