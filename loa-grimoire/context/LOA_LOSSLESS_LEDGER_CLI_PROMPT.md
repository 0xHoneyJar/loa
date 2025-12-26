# Loa: Lossless Ledger Protocol (CLI Prompt)

<role>Principal Engineer refactoring Loa to "Clear, Don't Compact" architecture</role>

<version>v2 (Production-Hardened - 10 Principal Engineer Reviews)</version>

<objective>
Implement stateless inference backed by external ledgers (NOTES.md, Beads).
Context window = disposable workspace. State Zone = lossless permanent records.
Token efficiency: 99.6% reduction through lightweight identifiers.
</objective>

<paradigm_shift>
BEFORE (Lossy Compaction - "Smudged Paper Ledger"):
Context grows → Compact/summarize → Information lost → Hallucinations
Like: Smudging a chalkboard until it's a grey blur of ghosts

AFTER (Lossless Ledger - "Digital Blockchain"):
Context grows → Synthesize to ledgers → /clear → Resume from ledgers
Like: Immutable vault + clear desk + JIT file retrieval

Result: Every turn has full attention, zero information loss
Token Efficiency: 99.6% reduction via lightweight identifiers
</paradigm_shift>

<truth_hierarchy>
1. CODE (src/)           ← Absolute truth
2. BEADS (.beads/)       ← Lossless task graph, decisions
3. NOTES.md              ← Decision log, session continuity
4. TRAJECTORY            ← Audit trail, handoff records
5. PRD/SDD               ← Design intent
6. CONTEXT WINDOW        ← TRANSIENT, never authoritative

CRITICAL: Nothing in transient context overrides external ledger.
</truth_hierarchy>

<integrity_protocol>
Before any operation (Production-Hardened):

1. SYSTEM ZONE INTEGRITY:
   - Verify .claude/ checksums against .claude/checksums.json
   - If integrity_enforcement=strict and drift detected → HALT

2. VERSION PINNING (Schema Drift Prevention):
   - Check ck version matches .loa-version.json requirement
   - Verify binary hash if fingerprint available
   - Prevents embedding index incompatibility

3. SELF-HEALING STATE ZONE (Priority Order):
   a) Git-backed recovery FIRST (highest fidelity):
      - git show HEAD:loa-grimoire/NOTES.md → recover NOTES.md
      - git checkout HEAD -- .beads/ → recover tracked beads
   b) Template reconstruction SECOND (fallback):
      - Create from template if git recovery fails
      - Preserves framework contract but loses historical data
   c) Delta reindex for .ck/ (background):
      - Try delta update before full reindex
   
   Recovery Priority: Git > Template > Fresh
   Key: Ledger is source of truth - recover from git when possible

4. SYNTHESIS PROTECTION:
   - Ledger format customizations go in .claude/overrides/
   - Framework updates will NOT clobber override files
   - Never modify schema files directly
</integrity_protocol>

<session_recovery>
AFTER /clear OR SESSION START (mandatory steps):

Step 1 - Restore Task Context:
  bd ready                    # List active tasks
  bd show <active_bead_id>    # Load current task with decisions[]

Step 2 - TIERED LEDGER RECOVERY (Attention-Aware):
  DO NOT read entire NOTES.md - use tiered retrieval:
  
  Level 1 (Default, ~100 tokens):
    - Load ONLY "Session Continuity → Active Context" section
    - Load last 3 Decision Log entries
    - Command: head -50 "${PROJECT_ROOT}/loa-grimoire/NOTES.md" | grep -A 20 "## Session Continuity"
  
  Level 2 (When needed, ~200-500 tokens):
    - Use ck --hybrid to retrieve specific historical decisions
    - Trigger: Current task needs context from older decisions
    - Command: ck --hybrid "relevant query" "${PROJECT_ROOT}/loa-grimoire/" --top-k 3 --jsonl
  
  Level 3 (Rare, user-requested):
    - Full ledger scan - significant attention budget cost
    - Only for major architectural review or audit

Step 3 - FAILURE-AWARE LEDGER PARSING:
  - If malformed line encountered → DROP and continue (never crash)
  - Log parse errors to trajectory for audit
  - Self-heal: reconstruct from template if file corrupted

Step 4 - Verify Lightweight Identifiers:
  - Confirm referenced files exist
  - DO NOT load content - use JIT retrieval when needed
  - ALL paths must use ${PROJECT_ROOT} prefix (absolute)

Step 5 - Resume from "Reasoning State" checkpoint
</session_recovery>

<synthesis_checkpoint>
BEFORE /clear (MANDATORY - never wipe without synthesis):

Step 1 - GROUNDING VERIFICATION (BLOCKING):
  REQUIREMENT: grounding_ratio >= 0.95
  - Every decision must have word-for-word code quote
  - Every citation must use ${PROJECT_ROOT} absolute path
  
  IF FAILS → BLOCK /clear command
  Message: "Cannot clear: X decisions lack grounded citations.
           Add evidence or mark as [ASSUMPTION] before clearing.
           Current grounding ratio: 0.XX (required: 0.95)"

Step 2 - NEGATIVE GROUNDING VERIFICATION:
  For each Ghost Feature flagged this session:
  - Must have executed 2 diverse semantic queries
  - Both must return 0 results below 0.4 threshold
  - If not verified → Flag as [UNVERIFIED GHOST], not confirmed
  
  Purpose: Prevent "Phantom Liabilities" in permanent ledger

Step 3 - Update Decision Log:
  Write all High-Signal Findings to NOTES.md
  Use AST-AWARE SNIPPETS: ck --full-section for complete functions/classes
  Format: Decision, Rationale, Evidence (${PROJECT_ROOT} paths), Test Scenarios

Step 4 - Update Bead:
  bd update <id> --notes "progress, next steps, blockers"
  Append to decisions[] array with word-for-word evidence

Step 5 - Log Trajectory Handoff:
  {"phase":"session_handoff","session_id":"...","bead_id":"...","notes_refs":["NOTES.md:45-67"],"edd_verified":true,"grounding_ratio":0.97}
  
  If any search returned >50 results:
  - Verify Trajectory Pivot was logged
  - Pivot must explain hypothesis failure before refinement

Step 6 - Decay Raw Output:
  Full code blocks → lightweight identifiers (${PROJECT_ROOT}/path:line only)
  Raw tool output → single-line summaries
  Verbose explanations → key points

Step 7 - Verify EDD:
  Confirm 3 test scenarios documented for current task
  If missing: DO NOT /clear until documented

BLOCKING CHECKLIST before /clear permitted:
- [ ] Grounding ratio >= 0.95
- [ ] All Ghost Features have Negative Grounding verification
- [ ] Decision Log updated with AST-aware evidence
- [ ] Active Bead updated with rationale and next steps
- [ ] Trajectory handoff logged with line references
- [ ] 3 test scenarios documented
- [ ] All citations use ${PROJECT_ROOT} absolute paths
</synthesis_checkpoint>

<notes_md_structure>
## Session Continuity
<!-- Load FIRST after /clear -->

### Active Context
- **Current Bead**: bd-x7y8 (task description)
- **Last Checkpoint**: 2024-01-15T14:30:00Z
- **Reasoning State**: Where we left off

### Lightweight Identifiers
| Identifier | Purpose | Last Verified |
|------------|---------|---------------|
| /abs/path/src/auth/jwt.ts:45-67 | Token validation | 14:25:00Z |

### Decision Log
#### 2024-01-15T14:30:00Z - Decision Title
**Decision**: What we decided
**Rationale**: Why
**Evidence**: `code quote` [/abs/path/file.ts:line]
**Test Scenarios**: 1) happy 2) edge 3) error
</notes_md_structure>

<bead_authority>
BEADS-FIRST RECOVERY:
After /clear, Beads is FIRST source of truth (before NOTES.md)

PREVENTING FORKS:
1. After /clear: ALWAYS `bd show <id>` before reasoning
2. Before decisions: CHECK Bead decisions[] for prior rulings
3. After decisions: IMMEDIATELY append to Bead decisions[]
4. Never reason about task without loading its Bead first

FORK DETECTION:
If context reasoning conflicts with Bead state:
1. HALT reasoning
2. Load full Bead
3. Determine: Bead outdated OR agent wrong
4. Document resolution in Bead decisions[]
</bead_authority>

<jit_retrieval>
LIGHTWEIGHT IDENTIFIERS vs EAGER LOADING:

Eager (AVOID):
- Load all files "just in case"
- Context fills → attention degrades → compaction → loss

JIT (REQUIRED):
- Store paths only (~15 tokens vs ~500 for code block)
- Retrieve ONLY when reasoning requires
- 97% token reduction per reference

RETRIEVAL:
ck --hybrid "query" "${PROJECT_ROOT}/src/" --top-k 3 --jsonl
# OR
sed -n '45,67p' "/abs/path/file.ts"
</jit_retrieval>

<attention_budget>
| Threshold | Tokens | Action |
|-----------|--------|--------|
| Green | 0-5k | Normal operation |
| Yellow | 5-10k | **DELTA-SYNTHESIS** (partial persist) |
| Orange | 10-15k | Recommend /clear to user |
| Red | 15k+ | MANDATORY synthesis, halt new work |

AT YELLOW THRESHOLD (Delta-Synthesis Protocol):
Critical: Persist work NOW to survive potential crashes
1. Immediately append recent findings to NOTES.md Decision Log
2. Update active Bead with progress-to-date (mark delta_synced: true)
3. Log: {"phase":"delta_sync","tokens":5000,"decisions_persisted":N}
4. DO NOT clear context yet - just persist to ledger
Rationale: If agent crashes before /clear, work is already saved

AT ORANGE THRESHOLD:
1. Execute full synthesis checkpoint
2. Inform user: "Context is filling. Consider /clear when ready."

AT RED THRESHOLD:
1. HALT new tool calls
2. Execute mandatory synthesis checkpoint
3. Refuse new work until /clear
4. Message: "Attention budget exhausted. Please /clear."

AST-AWARE EVIDENCE CAPTURE:
When persisting to ledgers, use complete logical blocks:
- WRONG: sed -n '45,50p' (arbitrary lines, loses context)
- RIGHT: ck --full-section "functionName" (complete function/class)
</attention_budget>

<trajectory_handoff>
SESSION HANDOFF LOG:
{"ts":"...","phase":"session_handoff","session_id":"sess-002","root_span_id":"span-def","bead_id":"bd-x7y8","notes_refs":["NOTES.md:68-92"],"edd_verified":true,"grounding_ratio":0.97,"next_session_ready":true}

TRAJECTORY PIVOT PROTOCOL:
If any search returned >50 results during session:
- Must log Trajectory Pivot BEFORE refining query
- Pivot explains WHY initial hypothesis failed
- Format: {"phase":"pivot","reason":"query too broad","result_count":127,"hypothesis_failure":"...","refined_hypothesis":"..."}
- Do NOT just narrow query - document the learning

HANDOFF READY WHEN:
- Grounding ratio >= 0.95
- All Ghost Features have Negative Grounding verification
- All decisions logged to NOTES.md with AST-aware evidence
- Bead decisions[] updated
- 3 test scenarios documented
- All citations use ${PROJECT_ROOT} absolute paths
- Trajectory includes notes_refs
- Any >50 result searches have Trajectory Pivot logged

IF CHECKLIST FAILS: BLOCK /clear
</trajectory_handoff>

<ride_integration>
/ride SESSION-AWARE:

After /clear:
1. bd ready → bd show <id>
2. Load NOTES.md Session Continuity
3. Verify integrity
4. DO NOT load files - use JIT

During /ride:
- Continuously synthesize (don't wait for end)
- High-signal finding → immediately to NOTES.md
- Decision → immediately to Bead decisions[]
- At 75% attention budget → recommend /clear

Before completion:
- Full synthesis checkpoint
- Update Beads
- Log trajectory
- Verify EDD
</ride_integration>

<anti_patterns>
NEVER:
- "I'll remember this" → Write to NOTES.md NOW
- Trust compacted context → Trust only ledgers
- Relative paths → ALWAYS ${PROJECT_ROOT} absolute paths
- Defer synthesis → Synthesize continuously
- Reason without Bead → ALWAYS bd show first
- Eager load files → Store identifiers, JIT retrieve
- /clear without checkpoint → Execute protocol first
- /clear with grounding_ratio < 0.95 → BLOCKED until fixed
- Ghost Features without Negative Grounding → Flag as [UNVERIFIED]
- >50 result search without Trajectory Pivot → Document hypothesis failure
- Arbitrary line ranges → Use ck --full-section for AST-aware snippets
- Skip Delta-Synthesis at Yellow → Persist work to survive crashes
- Halt on missing State Zone → Self-heal (reconstruct from template)
</anti_patterns>

<citation_format>
REQUIRED (survives session wipes):
`export function validateToken()` [${PROJECT_ROOT}/src/auth/jwt.ts:45]

INSUFFICIENT (loses context):
validateToken [src/auth/jwt.ts:45]

RULE: ${PROJECT_ROOT} prefix + absolute path + line number + word-for-word quote
AST-AWARE: Use ck --full-section for complete logical blocks
</citation_format>

<analogy>
Compacting = smudging chalkboard → grey blur of ghosts

Lossless Ledger = 
- Digital Ledger (Beads) for tasks
- Project Binder (NOTES.md) for decisions  
- Filing Cabinet (trajectory/) for audit

When desk (context) is messy → wipe clean (/clear)
Permanent records safe in State Zone
Every turn: clear mind, full attention, lossless history
</analogy>

<execution_tasks>
1. Create .claude/protocols/session-continuity.md
2. Create .claude/protocols/synthesis-checkpoint.md
3. Update .claude/commands/ride.md with session-aware init
4. Add Session Continuity section to NOTES.md template
5. Extend Bead schema: decisions[], handoffs[]
6. Add session_handoff phase to trajectory format
7. Implement attention budget thresholds with Delta-Synthesis
8. Verify all citations use ${PROJECT_ROOT} absolute paths
9. Implement grounding ratio enforcement (block /clear if < 0.95)
10. Add Negative Grounding verification for Ghost Features
11. Add Trajectory Pivot protocol for >50 result searches
12. Implement AST-aware snippet capture via ck --full-section
</execution_tasks>

<traceability_verification>
PRODUCTION-HARDENED REQUIREMENTS (v2.2 - 3 PE Reviews):

AWS Projen (Infrastructure):
✅ Self-healing State Zone (reconstruct, don't halt)
✅ Git-backed recovery (highest fidelity source)
✅ Recovery priority: Git > Template > Fresh
✅ Version pinning for ck binary
✅ Binary hash verification (SHA-256)
✅ Synthesis protection via .claude/overrides/
✅ Delta-first reindexing for .ck/

Anthropic ACI (Context Engineering):
✅ Tiered Ledger Recovery (3 levels, attention-aware)
✅ Level 1: Metadata only (~100 tokens)
✅ Level 2: bd show <id> for active task
✅ Level 3: ck --hybrid for JIT historical search
✅ Failure-Aware Ledger Parsing (drop malformed, continue)
✅ ${PROJECT_ROOT} absolute paths (mandatory)
✅ JIT retrieval vs eager loading
✅ Delta-Synthesis at Yellow threshold (5k tokens)
✅ AST-aware snippets via ck --full-section

Google ADK (Trajectory):
✅ Grounding ratio enforcement (>= 0.95, BLOCKS /clear)
✅ Negative Grounding verification for Ghost Features
✅ Trajectory Pivot protocol for >50 results
✅ root_span_id in session_handoff for lineage tracing
✅ EDD verification (3 test scenarios)
✅ Session handoff with notes_refs
✅ Word-for-word citations required

Loa Standard (Truth Hierarchy):
✅ CODE > BEADS > NOTES.md > TRAJECTORY > CONTEXT
✅ Context window = transient, never authoritative
✅ Beads-first recovery after /clear
✅ Fork detection and resolution
✅ Ledger as append-only permanent record

BLOCKING BEHAVIORS:
- grounding_ratio < 0.95 → BLOCK /clear
- Ghost without Negative Grounding → BLOCK /clear
- Missing 3 test scenarios → BLOCK /clear
- Relative paths in citations → BLOCK /clear
- Missing word-for-word quote → BLOCK /clear
</traceability_verification>

<blockchain_analogy>
Digital Blockchain vs Smudged Paper Ledger:

| Smudged Ledger (Compaction) | Digital Blockchain (Lossless) |
|-----------------------------|-------------------------------|
| Fading, overwritten memory | Immutable, append-only ledger |
| Cluttered desk | Clear desk after every audit |
| Summarized evidence | Word-for-word, verifiable |
| "I think I remember..." | Timestamped trajectory |

The Auditor starts every turn with a clear desk (/clear),
pulling specific files (JIT) from the vault (State Zone)
only when evidence is required.
</blockchain_analogy>

<protocol_version>v2.2 (Production-Hardened, 3 PE Reviews)</protocol_version>
