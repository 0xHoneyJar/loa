# /loa setup — Environment Setup Wizard

Run the Loa environment setup wizard. Validates dependencies, checks configuration, and optionally configures feature toggles.

## Arguments

- `--check`: Non-interactive mode. Run validation only and display results. Do not prompt.

## Workflow

### Step 1: Run Validation Engine

Execute `.claude/scripts/loa-setup-check.sh` and capture the JSONL output. Each line is a JSON object with `step`, `name`, `status`, and `detail` fields.

### Step 2: Display Results

Present the validation results in a formatted table:

```
Setup Check Results
═══════════════════

Step 1 — API Key
  ✓ ANTHROPIC_API_KEY is set

Step 2 — Required Dependencies
  ✓ jq v1.7
  ✓ yq v4.40
  ✓ git v2.43

Step 3 — Optional Tools
  ⚠ beads not installed (cargo install beads_rust)
  ⚠ ck not installed

Step 4 — Configuration
  Features: flatline=true, memory=true, enhancement=true
```

Use ✓ for `pass`, ⚠ for `warn`, ✗ for `fail`.

### Step 2.5: Offer to Fix Missing Dependencies

If any required dependency has status `fail`:

1. Collect all failed dependencies into a list
2. Present via AskUserQuestion:

```yaml
question: "Fix missing dependencies?"
header: "Auto-fix"
options:
  - label: "Yes, install now (Recommended)"
    description: "Install {list of missing deps} automatically"
  - label: "Skip"
    description: "I'll install manually later"
multiSelect: false
```

3. If user selects "Yes, install now":
   - Detect OS: macOS (brew), Linux-apt (apt), Linux-yum (yum)
   - For each missing dep, run the appropriate install command via Bash tool:
     - jq: `brew install jq` (macOS) or `sudo apt install jq` (Linux)
     - yq: `brew install yq` (macOS) or download mikefarah binary (Linux)
     - beads: Run `.claude/scripts/beads/install-br.sh`
   - Show progress for each: "Installing jq... ✓" or "Installing jq... ✗ (manual: brew install jq)"
   - Re-run `.claude/scripts/loa-setup-check.sh` after to verify fixes
   - Display updated results table

4. If user selects "Skip", continue to Step 3.

5. If all deps already pass, skip this step entirely (no prompt shown).

### Step 3: Interactive Configuration (skip if --check)

If NOT in `--check` mode, present feature toggle configuration via AskUserQuestion:

```yaml
question: "Which features would you like to enable?"
header: "Features"
options:
  - label: "Flatline Protocol"
    description: "Multi-model adversarial review (Opus + GPT-5.2)"
  - label: "Persistent Memory"
    description: "Cross-session observation storage"
  - label: "Prompt Enhancement"
    description: "Invisible prompt improvement before skill execution"
  - label: "Keep current settings"
    description: "Don't change .loa.config.yaml"
multiSelect: true
```

### Step 4: Apply Configuration

If user selected features (and did NOT select "Keep current settings"):

1. For each selected feature, update `.loa.config.yaml` using `yq`:
   - "Flatline Protocol" → `yq -i '.flatline_protocol.enabled = true' .loa.config.yaml`
   - "Persistent Memory" → `yq -i '.memory.enabled = true' .loa.config.yaml`
   - "Prompt Enhancement" → `yq -i '.prompt_enhancement.invisible_mode.enabled = true' .loa.config.yaml`
2. Display confirmation of changes made.

If user selected "Keep current settings", skip configuration changes.

### Step 5: Summary

Display a summary with next steps:

```
Setup complete! Next steps:
  1. Start planning: /plan
  2. Or check status: /loa
```

## Security

- **NFR-8**: Never display API key values. Only show boolean presence ("is set" / "not set").
- **Never write secrets to disk.** Only modify feature toggles in `.loa.config.yaml`.
- **Require user consent** before modifying any configuration file.
