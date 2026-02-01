#!/usr/bin/env bats
# Integration tests for probe-ride workflow (context-manager + schema-validator)

setup() {
    export TEST_DIR="$BATS_TMPDIR/probe-ride-workflow-$$"
    mkdir -p "$TEST_DIR"

    export CONTEXT_SCRIPT="$BATS_TEST_DIRNAME/../../.claude/scripts/context-manager.sh"
    export SCHEMA_SCRIPT="$BATS_TEST_DIRNAME/../../.claude/scripts/schema-validator.sh"

    # Create a realistic project structure
    mkdir -p "$TEST_DIR/project/src"
    mkdir -p "$TEST_DIR/project/tests"
    mkdir -p "$TEST_DIR/project/docs"
    mkdir -p "$TEST_DIR/project/grimoires/loa"

    # Create source files
    cat > "$TEST_DIR/project/src/index.ts" << 'EOF'
/**
 * Main application entry point
 */
import { App } from './app';
import { Config } from './config';

export async function main(): Promise<void> {
    const config = new Config();
    const app = new App(config);
    await app.start();
}

main().catch(console.error);
EOF

    cat > "$TEST_DIR/project/src/app.ts" << 'EOF'
import { Config } from './config';

export class App {
    constructor(private config: Config) {}

    async start(): Promise<void> {
        console.log('Starting application...');
        // Application logic here
    }

    async stop(): Promise<void> {
        console.log('Stopping application...');
    }
}
EOF

    cat > "$TEST_DIR/project/src/config.ts" << 'EOF'
export class Config {
    readonly port: number;
    readonly host: string;

    constructor() {
        this.port = parseInt(process.env.PORT || '3000', 10);
        this.host = process.env.HOST || 'localhost';
    }
}
EOF

    # Create test files
    cat > "$TEST_DIR/project/tests/app.test.ts" << 'EOF'
import { App } from '../src/app';
import { Config } from '../src/config';

describe('App', () => {
    it('should start successfully', async () => {
        const config = new Config();
        const app = new App(config);
        await expect(app.start()).resolves.not.toThrow();
    });
});
EOF

    # Create documentation
    cat > "$TEST_DIR/project/docs/README.md" << 'EOF'
# Test Project

A sample project for testing the probe-ride workflow.

## Overview

This project demonstrates the integration between context-manager probe
and schema-validator assert functionality.

## Usage

```bash
npm start
```
EOF

    # Create valid PRD
    cat > "$TEST_DIR/project/grimoires/loa/prd.md" << 'EOF'
# Product Requirements Document

## Version
1.0.0

## Status
draft

## Stakeholders
- Product Owner
- Development Team
- QA Team

## Requirements

### Functional Requirements
1. The system shall provide user authentication
2. The system shall support role-based access control

### Non-Functional Requirements
1. Response time under 200ms
2. 99.9% uptime SLA
EOF

    # Create PRD JSON for schema validation
    cat > "$TEST_DIR/project/grimoires/loa/prd.json" << 'EOF'
{
    "version": "1.0.0",
    "title": "Test PRD",
    "status": "draft",
    "stakeholders": ["Product Owner", "Development Team"],
    "requirements": [
        {"id": "FR-1", "description": "User authentication"},
        {"id": "FR-2", "description": "Role-based access control"}
    ]
}
EOF

    # Create valid SDD
    cat > "$TEST_DIR/project/grimoires/loa/sdd.json" << 'EOF'
{
    "version": "1.0.0",
    "title": "Software Design Document",
    "components": [
        {"name": "api", "type": "service"},
        {"name": "auth", "type": "module"},
        {"name": "db", "type": "database"}
    ]
}
EOF

    # Create valid Sprint
    cat > "$TEST_DIR/project/grimoires/loa/sprint.json" << 'EOF'
{
    "version": "1.0.0",
    "status": "in_progress",
    "sprints": [
        {"id": 1, "name": "Sprint 1", "status": "completed"},
        {"id": 2, "name": "Sprint 2", "status": "in_progress"}
    ]
}
EOF

    # Create package.json
    cat > "$TEST_DIR/project/package.json" << 'EOF'
{
    "name": "test-project",
    "version": "1.0.0",
    "main": "src/index.ts",
    "scripts": {
        "start": "ts-node src/index.ts",
        "test": "jest"
    }
}
EOF
}

teardown() {
    rm -rf "$TEST_DIR"
}

# =============================================================================
# Probe-Then-Decide Workflow
# =============================================================================

@test "probe-then-decide: probe directory before loading" {
    # Step 1: Probe the source directory
    run "$CONTEXT_SCRIPT" probe "$TEST_DIR/project/src" --json
    [ "$status" -eq 0 ]

    local files tokens
    files=$(echo "$output" | jq '.total_files')
    tokens=$(echo "$output" | jq '.estimated_tokens')

    # Step 2: Make loading decision based on probe results
    [ "$files" -gt 0 ]
    [ "$tokens" -gt 0 ]

    # Step 3: If tokens low, safe to load individual files
    if [ "$tokens" -lt 5000 ]; then
        # should-load works on files, not directories
        run "$CONTEXT_SCRIPT" should-load "$TEST_DIR/project/src/index.ts" --json
        [ "$status" -eq 0 ]
        local decision
        decision=$(echo "$output" | jq -r '.decision')
        [ "$decision" = "load" ]
    fi
}

@test "probe-then-decide: skip large directories" {
    # Create a large directory
    mkdir -p "$TEST_DIR/large"
    for i in {1..100}; do
        for j in {1..10}; do
            echo "// Line $j of file $i - some padding content here" >> "$TEST_DIR/large/file_$i.ts"
        done
    done

    # Probe should still work
    run "$CONTEXT_SCRIPT" probe "$TEST_DIR/large" --json
    [ "$status" -eq 0 ]

    local tokens
    tokens=$(echo "$output" | jq '.estimated_tokens')
    [ "$tokens" -gt 100 ]
}

@test "probe-then-decide: compare files before and after changes" {
    # Initial probe
    run "$CONTEXT_SCRIPT" probe "$TEST_DIR/project/src/index.ts" --json
    [ "$status" -eq 0 ]
    local initial_tokens
    initial_tokens=$(echo "$output" | jq '.estimated_tokens')

    # Add content
    cat >> "$TEST_DIR/project/src/index.ts" << 'EOF'

// Additional functionality
export function helper(): string {
    return "helper function";
}
EOF

    # Probe again
    run "$CONTEXT_SCRIPT" probe "$TEST_DIR/project/src/index.ts" --json
    [ "$status" -eq 0 ]
    local new_tokens
    new_tokens=$(echo "$output" | jq '.estimated_tokens')

    # Tokens should have increased
    [ "$new_tokens" -gt "$initial_tokens" ]
}

# =============================================================================
# Schema Validation Workflow
# =============================================================================

@test "schema validation: validate PRD before processing" {
    run "$SCHEMA_SCRIPT" assert "$TEST_DIR/project/grimoires/loa/prd.json" --schema prd --json
    [ "$status" -eq 0 ]

    local status_val
    status_val=$(echo "$output" | jq -r '.status')
    [ "$status_val" = "passed" ]
}

@test "schema validation: validate SDD architecture" {
    run "$SCHEMA_SCRIPT" assert "$TEST_DIR/project/grimoires/loa/sdd.json" --schema sdd --json
    [ "$status" -eq 0 ]

    local status_val
    status_val=$(echo "$output" | jq -r '.status')
    [ "$status_val" = "passed" ]
}

@test "schema validation: validate Sprint planning" {
    run "$SCHEMA_SCRIPT" assert "$TEST_DIR/project/grimoires/loa/sprint.json" --schema sprint --json
    [ "$status" -eq 0 ]

    local status_val
    status_val=$(echo "$output" | jq -r '.status')
    [ "$status_val" = "passed" ]
}

@test "schema validation: reject invalid document" {
    # Create invalid PRD (missing required fields)
    cat > "$TEST_DIR/project/invalid-prd.json" << 'EOF'
{
    "title": "Missing Version and Stakeholders"
}
EOF

    run "$SCHEMA_SCRIPT" assert "$TEST_DIR/project/invalid-prd.json" --schema prd --json
    # Should fail or indicate failure
    [ "$status" -ne 0 ] || [[ $(echo "$output" | jq -r '.status') != "passed" ]]
}

# =============================================================================
# Combined Probe + Validate Workflow
# =============================================================================

@test "full workflow: probe project, validate docs, assess readiness" {
    # Step 1: Probe project structure
    run "$CONTEXT_SCRIPT" probe "$TEST_DIR/project" --json
    [ "$status" -eq 0 ]
    local project_tokens
    project_tokens=$(echo "$output" | jq '.estimated_tokens')
    [ "$project_tokens" -gt 0 ]

    # Step 2: Validate PRD
    run "$SCHEMA_SCRIPT" assert "$TEST_DIR/project/grimoires/loa/prd.json" --schema prd --json
    [ "$status" -eq 0 ]

    # Step 3: Validate SDD
    run "$SCHEMA_SCRIPT" assert "$TEST_DIR/project/grimoires/loa/sdd.json" --schema sdd --json
    [ "$status" -eq 0 ]

    # Step 4: Validate Sprint
    run "$SCHEMA_SCRIPT" assert "$TEST_DIR/project/grimoires/loa/sprint.json" --schema sprint --json
    [ "$status" -eq 0 ]

    # All validations passed - project is ready for implementation
}

@test "selective loading: probe identifies high-value targets" {
    # Probe each directory
    run "$CONTEXT_SCRIPT" probe "$TEST_DIR/project/src" --json
    [ "$status" -eq 0 ]
    local src_tokens
    src_tokens=$(echo "$output" | jq '.estimated_tokens')

    run "$CONTEXT_SCRIPT" probe "$TEST_DIR/project/tests" --json
    [ "$status" -eq 0 ]
    local test_tokens
    test_tokens=$(echo "$output" | jq '.estimated_tokens')

    run "$CONTEXT_SCRIPT" probe "$TEST_DIR/project/docs" --json
    [ "$status" -eq 0 ]
    local docs_tokens
    docs_tokens=$(echo "$output" | jq '.estimated_tokens')

    # Source should have more content than docs
    [ "$src_tokens" -gt "$docs_tokens" ]
}

@test "incremental validation: validate each phase output" {
    # Phase 1: PRD validation
    run "$SCHEMA_SCRIPT" assert "$TEST_DIR/project/grimoires/loa/prd.json" --schema prd --json
    [ "$status" -eq 0 ]
    [[ $(echo "$output" | jq -r '.status') == "passed" ]]

    # Phase 2: SDD validation (depends on PRD)
    run "$SCHEMA_SCRIPT" assert "$TEST_DIR/project/grimoires/loa/sdd.json" --schema sdd --json
    [ "$status" -eq 0 ]
    [[ $(echo "$output" | jq -r '.status') == "passed" ]]

    # Phase 3: Sprint validation (depends on SDD)
    run "$SCHEMA_SCRIPT" assert "$TEST_DIR/project/grimoires/loa/sprint.json" --schema sprint --json
    [ "$status" -eq 0 ]
    [[ $(echo "$output" | jq -r '.status') == "passed" ]]
}

# =============================================================================
# Error Handling
# =============================================================================

@test "graceful handling: missing grimoires directory" {
    rm -rf "$TEST_DIR/project/grimoires"

    # Probe should still work on project
    run "$CONTEXT_SCRIPT" probe "$TEST_DIR/project" --json
    [ "$status" -eq 0 ]

    # Validation should fail gracefully for missing file
    run "$SCHEMA_SCRIPT" assert "$TEST_DIR/project/grimoires/loa/prd.json" --schema prd --json
    [ "$status" -ne 0 ] || [[ "$output" == *"error"* ]]
}

@test "graceful handling: empty project" {
    mkdir -p "$TEST_DIR/empty_project"

    run "$CONTEXT_SCRIPT" probe "$TEST_DIR/empty_project" --json
    [ "$status" -eq 0 ]

    local files
    files=$(echo "$output" | jq '.total_files')
    [ "$files" -eq 0 ]
}

@test "graceful handling: special characters in paths" {
    mkdir -p "$TEST_DIR/project/src/special dir"
    echo "content" > "$TEST_DIR/project/src/special dir/file.ts"

    run "$CONTEXT_SCRIPT" probe "$TEST_DIR/project/src/special dir" --json
    [ "$status" -eq 0 ]
}
