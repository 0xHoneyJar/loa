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

### Step 5: Construct Network Tools (optional)

Constructs are an optional ecosystem of installable packs (skills, commands, schemas) on top of Loa. If the operator does not work with constructs, this step is pure no-op — answer "Skip" and the wizard continues unchanged.

If the project has `.claude/scripts/constructs-install.sh` available, offer to install a construct pack. Present via AskUserQuestion:

```yaml
question: "Install a construct pack?"
header: "Constructs (optional)"
options:
  - label: "Install the default bundle (construct-network-tools)"
    description: "Tries `constructs install construct-network-tools` from the registry. If the pack is not yet published, the install is a non-fatal no-op and the wizard continues."
  - label: "Choose a different pack"
    description: "Prompts for a slug (e.g. gtm-collective, artisan, observer)"
  - label: "Skip"
    description: "I'll run /constructs install manually later, or never"
multiSelect: false
```

**Notes for the wizard implementation:**

- The `construct-network-tools` slug is the *intended* default bundle for the construct onramp. As of cycle-005 it may not yet exist in the registry; if `constructs-install.sh` returns exit code 3 (not found) the wizard MUST surface a single-line hint ("default bundle not yet published — try `/constructs` to browse what's available") and continue. Mount remains valid either way.
- For "Choose a different pack": prompt for a slug via a second AskUserQuestion. Validate against `[a-z0-9-]+` before invoking the installer; reject empty input.
- All install errors are non-fatal — a failed pack install does NOT invalidate the wizard run.
- If the installer is missing (older Loa versions without `constructs-install.sh` bundled), skip this step silently.

### Step 6: Summary

Display a summary with next steps. The third line about constructs SHOULD only appear when constructs were installed in Step 5 OR when `.run/construct-index.yaml` exists (i.e., when constructs are part of this project's reality):

```
Setup complete! Next steps:
  1. Start planning: /plan
  2. Or check status: /loa
  3. Browse packs: /constructs        # only when constructs are in use
```

## Security

- **NFR-8**: Never display API key values. Only show boolean presence ("is set" / "not set").
- **Never write secrets to disk.** Only modify feature toggles in `.loa.config.yaml`.
- **Require user consent** before modifying any configuration file.
