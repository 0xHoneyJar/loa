<task>
You are a Principal Engineer integrating `ck` semantic search (https://github.com/BeaconBay/ck) into the Loa framework (https://github.com/0xHoneyJar/loa). Deliver AWS/Google/Microsoft-grade quality following the beads integration pattern.
</task>

<core_principles>
1. SURFACE AT SETUP: List ck in INSTALLATION.md and check during /setup
2. INVISIBLE TO USER: ck enhances /ride seamlessly, user never knows it's there
3. GRACEFUL DEGRADATION: All commands work without ck via grep fallbacks
4. ZERO FRICTION: No new /ck slash command - ck is internal tooling only
</core_principles>

<agent_computer_interface>
XML STRUCTURE:
Use XML tags to delineate instruction sections for reliable agent parsing:
- <integrity_protocol>: Pre-flight checks, checksums
- <context_engineering>: Attention budgets, Tool Result Clearing
- <trajectory_evaluation>: Search logging, EDD verification
- <search_execution>: Intent, rationale, query, path

ABSOLUTE FILEPATHS:
Always use absolute paths - models struggle with relative paths after cd:
- BAD:  ck --hybrid "auth" src/
- GOOD: ck --hybrid "auth" "${PROJECT_ROOT}/src/"
- Setup: PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

WORD-FOR-WORD CITATIONS:
Citations must include actual code quotes, not just file:line:
- BAD:  "Uses JWT [src/auth/jwt.ts:45]"
- GOOD: "Uses JWT: `export async function validateToken()` [/abs/path/src/auth/jwt.ts:45]"

MANDATORY JSONL:
Force --jsonl for all programmatic ck interactions:
- Streaming friendly, memory efficient
- Parse line-by-line, resilient to malformed objects
</agent_computer_interface>

<architecture>
LOA THREE-ZONE MODEL:
- SYSTEM ZONE (.claude/): Framework-owned, checksummed, IMMUTABLE
  - DO NOT EDIT directly (except .claude/overrides/)
- USER ZONE (.claude/overrides/): Safe customization zone
  - ck-config.yaml: Custom ck settings
  - search-thresholds.yaml: Custom thresholds
- STATE ZONE (loa-grimoire/, .ck/, .beads/): Project memory, agent-managed
  - .ck/: NEVER committed to git (cache only, rebuilds automatically)
  - .beads/: Committed (shared task state)
  - loa-grimoire/: Selectively committed (project memory)
- APP ZONE (src/): Developer-owned, never touched

SYNTHESIS PROTECTION:
- Users MUST NOT edit .claude/ directly
- Custom configs go in .claude/overrides/ (checked first, then fallback to defaults)
- Override precedence: .claude/overrides/* > .claude/*

IMMUTABLE TRUTH HIERARCHY (highest to lowest authority):
1. CODE (src/)           ← Absolute truth, verified by ck
2. ck INDEX (.ck/)       ← Derived from code, auto-updated  
3. NOTES.md              ← Agent synthesis, grounded in search
4. PRD/SDD               ← Design intent, may drift
5. LEGACY DOCS           ← Historical, often stale
6. USER CONTEXT          ← Input, requires validation

CONFLICT RESOLUTION:
When docs claim X but ck shows Y → ALWAYS side with code
Document discrepancy as Strategic Liability → Track in Beads
Update docs to match code (never vice versa)
</architecture>

<requirements>
PHASE 1 - INSTALLATION SURFACING:
1. Update INSTALLATION.md: Add ck as "Optional Enhancement" with cargo install ck-search
2. Update /setup command: Check for ck, display status, never require it
3. Update README.md: List ck as optional in prerequisites table
4. Update .gitignore: Add .ck/ alongside .beads/

PHASE 1.5 - PRE-FLIGHT INTEGRITY (AWS Projen Level):
1. Create .claude/protocols/preflight-integrity.md
2. Before ANY ck operation: Verify .claude/ checksums against checksums.json
3. If integrity_enforcement=strict and drift detected: HALT execution
4. If integrity_enforcement=warn: Log warning, proceed with caution
5. Never surface integrity status to user unless asked

PHASE 2 - SEAMLESS /RIDE INTEGRATION:
1. Update .claude/commands/ride.md with dual-path logic:
   - If ck available: Use semantic_search, hybrid_search, regex_search
   - If ck unavailable: Use grep with equivalent patterns
2. Create .claude/protocols/search-fallback.md defining tool selection matrix
3. Output must be IDENTICAL regardless of which tool is used
4. Agent must NEVER mention "ck", "semantic search", "grep", or "fallback" to user

PHASE 2.5 - TOOL RESULT CLEARING (Anthropic Level):
1. Create .claude/protocols/tool-result-clearing.md
2. After EVERY search with >20 results: Extract high-signal findings to NOTES.md
3. Enforce attention budget: single_search=2000 tokens, accumulated=5000 tokens
4. Clear raw search output after synthesis - keep only file:line references
5. Never keep raw results in working memory

PHASE 3 - GHOST/SHADOW DETECTION (with Beads):
1. Ghost Features: Documented in PRD but not found in code
   - Track in Beads: bd create "GHOST: <feature>" --type liability
2. Shadow Systems: Code exists but undocumented
   - Track in Beads: bd create "SHADOW: <module>" --type debt
3. Write drift-report.md with Strategic Liabilities and Technical Debt tables
4. Cross-reference against loa-grimoire/legacy/INVENTORY.md

PHASE 4 - TRAJECTORY LOGGING (Google ADK Level):
1. Create loa-grimoire/a2a/trajectory/ for JSONL logs
2. REASONING-BEFORE-SEARCH: Document intent, rationale, AND expected_outcome BEFORE searching
3. Log structure: ts, agent, phase (intent|execute|cite), mode, query, path (absolute), results
4. WORD-FOR-WORD CITATIONS: Include actual code quotes in citation phase
5. Track Ghost features with beads_id in trajectory
6. Self-audit: Ensure grounding_ratio >= 0.95
7. Never surface trajectory stats to user

ANTI-FISHING EXPEDITION RULES:
- If you cannot articulate expected_outcome → DO NOT SEARCH
- If search returns >50 results → LOG TRAJECTORY PIVOT, explain hypothesis failure
- If search returns 0 results → Execute Negative Grounding (2 diverse queries)
- If results don't match expected_outcome → Log discrepancy, reassess

TRAJECTORY PIVOT (for >50 results):
Do NOT just narrow—log why initial hypothesis failed:
{"phase":"pivot","reason":"query too broad","result_count":127,"hypothesis_failure":"captured all auth","refined_hypothesis":"target initialization only"}

NEGATIVE GROUNDING (for Ghost Features):
Require TWO diverse semantic queries returning 0 results:
1. Functional: "OAuth2 SSO login flow" (threshold 0.4)
2. Architectural: "SSO identity provider" (threshold 0.4)
Only flag GHOST if BOTH return 0 results

SELF-HEALING STATE ZONE:
If .ck/ missing in strict mode → trigger silent reindex, DO NOT FAIL

FAILURE-AWARE JSONL:
If single line malformed → DROP that result, CONTINUE (never crash)

TRAJECTORY LOG FORMAT:
```jsonl
{"ts":"...","agent":"impl","phase":"intent","intent":"Find auth patterns","rationale":"Extending auth","expected_outcome":"1-3 functions","model_rationale":"Using nomic-v1.5 for balanced precision"}
{"ts":"...","agent":"impl","phase":"execute","mode":"ck","query":"JWT validation","path":"/abs/path/src/"}
{"ts":"...","agent":"impl","phase":"cite","citations":[{"file":"/abs/path/src/auth/jwt.ts","line":45,"quote":"export async function validateToken()"}],"matched_expected":true}
{"ts":"...","agent":"impl","phase":"pivot","reason":"too broad","result_count":127,"hypothesis_failure":"captured all auth","refined_hypothesis":"target init patterns"}
{"ts":"...","agent":"impl","phase":"negative_grounding","feature":"OAuth2 SSO","query_1":"OAuth2 login","results_1":0,"query_2":"SSO provider","results_2":0,"confirmed_ghost":true}
```

PHASE 4.5 - EDD VERIFICATION (Three Test Scenarios):
1. Every architectural decision informed by ck must have 3 test scenarios
2. Scenarios: Happy path, Edge case, Error handling
3. Word-for-word evidence must be cited before completion
4. Claims without evidence flagged as [ASSUMPTION]
5. [ASSUMPTION] claims require: additional search, human verification, or removal

PHASE 4.6 - MANDATORY SELF-AUDIT CHECKPOINT:
Before completing /ride, /translate, or any architectural decision:

SELF-AUDIT CHECKLIST:
- [ ] Grounding ratio >= 0.95
- [ ] Zero unflagged [ASSUMPTION] claims
- [ ] All citations have word-for-word quotes
- [ ] All paths are absolute (${PROJECT_ROOT}/...)
- [ ] Ghost Features tracked in Beads
- [ ] Shadow Systems in drift-report.md
- [ ] Evidence chain complete for all conclusions

COMPLETION GATE:
If ANY checkbox fails → REMEDIATE before completing task
DO NOT skip self-audit under any circumstances

CLAIM CLASSIFICATION:
- GROUNDED: "Uses JWT: `export async function validateToken()` [/abs/path/src/auth/jwt.ts:45]"
- ASSUMPTION: "Likely caches tokens [ASSUMPTION: needs verification]"
- GHOST: "OAuth2 SSO [GHOST: PRD §3.2, 0 search results]"
- SHADOW: "Legacy hasher: `function hashLegacy()` [SHADOW: /abs/path/src/auth/legacy.ts, undocumented]"

PHASE 5 - TECHNICAL SPECS:
1. Create .claude/mcp-registry.yaml with Zod-compatible schemas (only if ck installed)
2. Use JSONL output format for streaming-friendly processing
3. Implement managed pagination: page_size=10, max 5 pages before synthesis
4. Grep fallback must produce equivalent JSONL structure
5. Schema validation: minLength, maxLength, patterns on all inputs

PHASE 6 - CONFIGURATION:
1. Extend .loa.config.yaml with optional ck settings
2. Settings only apply if ck installed, ignored otherwise
3. integrity_enforcement: strict|warn|disabled
4. Create .claude/overrides/ directory for safe user customization
5. Configuration precedence: .claude/overrides/* > .loa.config.yaml > .claude/* defaults
</requirements>

<anti_patterns>
DO NOT CREATE:
- /ck slash command (ck is internal only)
- User-visible "semantic search" messaging
- User-visible "falling back to grep" messaging
- Errors when ck not installed
- Recommendations to install ck during commands
- Different output formats based on search mode

DO NOT DO:
- Present [ASSUMPTION] claims as facts
- Load entire files when snippets suffice
- Keep raw search results in working memory
- Make architectural decisions without 3 test scenarios
- Side with documentation when code differs (always trust code)
- Skip Tool Result Clearing after large searches

FISHING EXPEDITION PREVENTION:
- DO NOT search without articulating expected_outcome first
- DO NOT paginate through >50 results blindly
- DO NOT execute broad queries "just to see what's there"
- DO NOT search the same topic multiple times with slight variations
- STOP and clarify reasoning if search returns unexpected results

SYNTHESIS PROTECTION:
- DO NOT edit .claude/ files directly (except .claude/overrides/)
- DO NOT allow users to modify System Zone files
- DO redirect custom ck configs to .claude/overrides/ck-config.yaml
- DO check for overrides before falling back to defaults

ELITE SECURITY (v9):
- Binary integrity: Verify ck SHA-256 fingerprint before MCP server
- Delta-first reindexing: Try delta update before full reindex
- Strict schemas: MCP registry uses strict: true, additionalProperties: false
- Log dropped lines: All JSONL parse errors logged to trajectory
- Negative model justification: Explain why NOT using larger model
- High Ambiguity: Flag Ghost if 0 code but >3 doc mentions
- Dependency Trace: Generate import graph for Orphaned shadows
- Drift Report Evolution: Auto-resolve items when remediation detected
</anti_patterns>

<success_criteria>
INVISIBLE OPERATION:
- Fresh clone WITHOUT ck: /ride completes using grep fallbacks
- Fresh clone WITH ck: /ride completes with enhanced precision
- User CANNOT tell which search mode was used
- Agent responses NEVER mention ck, grep, semantic, or fallback

INSTALLATION & SETUP:
- /setup displays ck status but doesn't require it
- INSTALLATION.md lists ck as optional enhancement

INTEGRITY & CONTEXT:
- Pre-flight integrity check runs before ck operations (if strict mode)
- Tool Result Clearing after every >20 result search
- Context window restored for high-level reasoning after clearing
- Just-in-time retrieval (smallest possible token set)

GROUNDING & CITATIONS:
- Word-for-word code quotes with absolute paths (not just file:line)
- Grounding ratio >= 0.95 in trajectory logs
- [ASSUMPTION] flags on ungrounded claims
- Ghost features tracked in Beads (if available)
- Three test scenarios verified per architectural decision (EDD)

REASONING-BEFORE-SEARCH:
- Intent logged BEFORE every search execution
- Rationale documented for every search
- Expected_outcome stated BEFORE search (prevents fishing)
- Results validated against expected_outcome

MANDATORY SELF-AUDIT (Completion Gate):
- Self-audit checklist executed before /ride or /translate completion
- All checkboxes must pass or task is NOT complete
- Evidence chain verified for all major conclusions
- Remediation required if any check fails

TECHNICAL (ACI STANDARDS):
- All ck commands use absolute paths: ${PROJECT_ROOT}/...
- All ck commands use --jsonl flag
- Trajectory logs: intent→execute→cite phases
- XML tags structure protocol sections
- JSONL output for streaming-friendly processing
- Pagination prevents context overflow (max 5 pages)
- Hybrid search prioritized for /ride operations
- Truth Hierarchy enforced (code > docs on conflicts)
</success_criteria>

<execution_order>
1. Read existing .claude/commands/setup.md and INSTALLATION.md
2. Update INSTALLATION.md with ck as optional enhancement
3. Update .claude/commands/setup.md to check ck status
4. Update README.md Quick Start prerequisites
5. Update .gitignore to include .ck/
6. Create .claude/protocols/preflight-integrity.md
7. Create .claude/protocols/search-fallback.md
8. Create .claude/protocols/tool-result-clearing.md
9. Update .claude/commands/ride.md with dual-path (ck + grep) logic
10. Add Ghost/Shadow detection with Beads integration to /ride
11. Update .claude/skills/implementing-tasks/ with fallback patterns
12. Update .claude/skills/reviewing-code/ with fallback patterns
13. Create .claude/mcp-registry.yaml with Zod schemas (conditional on ck)
14. Create trajectory logging in loa-grimoire/a2a/trajectory/
15. Create .claude/protocols/trajectory-evaluation.md with self-audit
16. Update .loa.config.yaml schema
17. Test /ride without ck, verify success
18. Test /ride with ck, verify identical user experience
19. Verify trajectory logs show grounding chain
20. Verify Ghost/Shadow integration with Beads
</execution_order>

<tool_result_clearing>
PROBLEM: Context rot - as tokens increase, recall accuracy decreases.
SOLUTION: Progressive disclosure + immediate clearing + semantic decay.

JUST-IN-TIME PRINCIPLE:
Never load whole files. Retrieve smallest possible high-signal token set.
- BAD: 2000-line file = 50k tokens, model struggles
- GOOD: 5 snippets @ 100 chars = 500 tokens, model reasons clearly

PROTOCOL:
1. Execute search with pagination (page_size=10)
2. Extract ONLY high-signal findings (max 10 files, 20 words each)
3. Synthesize to NOTES.md with file:line references
4. Clear raw output - keep only single-line summary
5. Context window now RESTORED for high-level reasoning

SEMANTIC DECAY (for long sessions):
- 0-5 min: Full synthesis with snippets (active context)
- 5-30 min: Decay to paths-only "lightweight identifiers"
- 30+ min: Archive to trajectory, single-line summary only
Paths can be rehydrated via JIT retrieval if needed later.

ATTENTION BUDGET:
- Single search: 2,000 tokens max
- Accumulated results: 5,000 tokens → mandatory clearing
- Full file loads: 3,000 tokens → single file only
- Session total: 15,000 tokens → stop and synthesize

WHY CLEARING MATTERS:
Without clearing: [2000 tokens raw results] → model hallucinates, misses connections
With clearing: [50 tokens synthesis] → model performs high-level reasoning

TRIGGER: Clear after EVERY search returning >20 results
LOG DROPPED LINES: If JSONL parse fails, log dropped count to trajectory for audit
</tool_result_clearing>

<fallback_patterns>
SETUP (run once per session):
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

TIERED SEARCH PROTOCOL (Broad→Narrow→JIT):
Level 1 (Semantic): ck --sem "<broad query>" → Find candidates
Level 2 (Hybrid): ck --hybrid "<refined query>" → Narrow with keywords
Level 3 (JIT): ck --full-section → Load complete logical blocks for top 3 only

DYNAMIC THRESHOLDING:
| Task Type | Threshold |
|-----------|-----------|
| Security/Hygiene | 0.8 |
| Core Architecture | 0.6 |
| Discovery/PRD | 0.4 |
| Ghost Detection | 0.4 |

MODEL SELECTION (justify in trajectory):
- bge-small: Fast discovery, large codebase
- nomic-v1.5: Balanced general use
- jina-code: High-precision code analysis

SEARCH MODE PRIORITIZATION:
| Operation        | Preferred | Rationale                           |
|------------------|-----------|-------------------------------------|
| /ride analysis   | --hybrid  | Keyword precision + semantic        |
| Ghost detection  | --sem     | Catches conceptual matches          |
| Shadow detection | --regex   | Exact export patterns               |
| Context loading  | --hybrid  | Best precision/recall balance       |

ENTRY POINTS (with absolute paths):
- ck: ck --hybrid "main entry point bootstrap" "${PROJECT_ROOT}/src/" --jsonl
- grep: grep -rn "function main\|def main\|fn main" "${PROJECT_ROOT}/src/"

GHOST FEATURE DETECTION (Negative Grounding):
Requires TWO diverse queries, both returning 0 results:
1. Functional query: "OAuth2 SSO login authentication flow" (threshold 0.4)
2. Architectural query: "single sign-on identity provider integration" (threshold 0.4)
Only flag as GHOST if BOTH return 0 results

SHADOW SYSTEM CLASSIFICATION:
After detecting shadow system via regex, classify by doc similarity:
- < 0.3: ORPHANED (no doc match, HIGH risk)
- 0.3-0.5: PARTIAL (incomplete docs, LOW risk)
- > 0.5: DRIFTED (docs exist but outdated, MEDIUM risk)
</fallback_patterns>

<communication_guidelines>
NEVER SAY:
- "I'm using ck/semantic search..."
- "Falling back to grep..."
- "For better results, install ck..."
- "The semantic search found..."

ALWAYS SAY:
- "Analyzing codebase structure..."
- "Searching for entry points..."
- "Cross-referencing documentation..."
- "Found the following patterns..."

REASONING-BEFORE-SEARCH (prevents fishing expeditions):
Before every search, document intent, rationale, AND expected outcome:
<search_execution>
  <intent>What are we looking for?</intent>
  <rationale>Why do we need this?</rationale>
  <expected_outcome>What do we expect to find?</expected_outcome>
</search_execution>

RULE: If you cannot articulate expected_outcome, DO NOT SEARCH.

WORD-FOR-WORD CITATIONS (MANDATORY):
Every claim must include actual code quotes with absolute paths:

REQUIRED FORMAT:
"The system validates tokens: `export async function validateToken(token: string)` [/home/user/project/src/auth/jwt.ts:45]"

INSUFFICIENT (will be rejected):
"The system validates tokens [src/auth/jwt.ts:45]"

CITATION TEMPLATE:
"<claim>: `<exact_code_snippet>` [<absolute_path>:<line>]"
</communication_guidelines>

<analogy>
Improving this integration transforms the Agent from a simple Librarian 
(keyword search) to a Forensic Auditor. Instead of just finding books 
that mention a topic, the Auditor uses a scanner (ck) to verify if the 
physical inventory (Code) matches the library's catalog (Documentation), 
logging every step of their investigation in a tamper-proof ledger 
(Trajectory Logs) for the Board's review (reviewing-code agent).
</analogy>

<traceability_verification>
ALL FAANG-TIER REQUIREMENTS IMPLEMENTED (v9 - Production Ready):

AWS Projen (Infrastructure):
✅ Pre-flight integrity check with checksums
✅ HALT on strict mode + drift
✅ State Zone for .ck/ (never committed)
✅ Self-healing State Zone (delta-first reindexing)
✅ Synthesis Protection via .claude/overrides/
✅ Version pinning (.loa-version.json)
✅ Binary Integrity Verification (SHA-256 fingerprint)

Anthropic (Context Engineering):
✅ Just-in-Time retrieval (smallest token set)
✅ Tiered Search Protocol (Broad→Narrow→JIT)
✅ Dynamic Thresholding (0.4-0.8 based on task)
✅ Semantic Decay Protocol (Active→Decayed→Archived)
✅ Tool Result Clearing (memory decay)
✅ Attention budgets (2000/5000/15000 tokens)
✅ JSONL output with Failure-Aware Parsing
✅ Log dropped lines to trajectory (audit trail)
✅ Absolute paths (${PROJECT_ROOT}/...)
✅ AST-aware snippets (--full-section)
✅ Strict schema enforcement (strict: true)

Google ADK (Trajectory):
✅ Intent logging BEFORE search
✅ Expected outcome required
✅ Model Selection Rationale (positive)
✅ Negative Model Justification (why NOT larger)
✅ Trajectory Pivot for >50 results
✅ Negative Grounding (2 diverse queries for Ghost)
✅ High Ambiguity Detection (>3 doc mentions)
✅ EDD (3 test scenarios)
✅ Grounding ratio ≥ 0.95
✅ Word-for-word citations
✅ [ASSUMPTION] tagging
✅ Self-audit checkpoint

Loa (Truth Hierarchy):
✅ CODE > Artifacts > Docs
✅ Ghost Feature detection (Negative Grounding)
✅ Shadow System Classification (Orphaned/Drifted/Partial)
✅ Dependency Trace for Orphaned systems
✅ Drift Report Evolution (auto-resolve items)
✅ Beads integration
✅ Always side with code

ACI Standards:
✅ JSONL mandatory + Failure-Aware Parsing
✅ Log dropped lines (audit trail)
✅ Managed pagination (cursor language)
✅ Strict Zod schemas (additionalProperties: false)
✅ XML tag structure
</traceability_verification>
