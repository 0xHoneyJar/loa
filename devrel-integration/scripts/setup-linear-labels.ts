#!/usr/bin/env ts-node
/**
 * Linear Label Setup Script
 *
 * This script initializes all base labels needed for the Linear audit trail system.
 * It should be run once during framework setup to create the label taxonomy.
 *
 * Usage:
 *   npx ts-node scripts/setup-linear-labels.ts [--team-id TEAM_ID]
 *
 * Labels Created:
 * - Agent labels (who did the work)
 * - Type labels (what kind of work)
 * - Source labels (where work originated)
 * - Priority labels (human-assigned urgency)
 */

import { LinearClient } from '@linear/sdk';
import * as dotenv from 'dotenv';

dotenv.config();

interface LabelDefinition {
  name: string;
  description: string;
  color: string;
}

// Base label definitions
const BASE_LABELS: LabelDefinition[] = [
  // Agent labels - who did the work
  {
    name: 'agent:implementer',
    description: 'Work by sprint-task-implementer agent',
    color: '#FFEB3B', // Yellow
  },
  {
    name: 'agent:devops',
    description: 'Work by devops-crypto-architect agent',
    color: '#00BCD4', // Cyan
  },
  {
    name: 'agent:auditor',
    description: 'Work by paranoid-auditor agent',
    color: '#F44336', // Red
  },

  // Type labels - what kind of work
  {
    name: 'type:feature',
    description: 'New feature implementation',
    color: '#4CAF50', // Green
  },
  {
    name: 'type:bugfix',
    description: 'Bug fix',
    color: '#FF9800', // Orange
  },
  {
    name: 'type:infrastructure',
    description: 'Infrastructure and deployment work',
    color: '#9C27B0', // Purple
  },
  {
    name: 'type:security',
    description: 'Security-related work',
    color: '#F44336', // Red
  },
  {
    name: 'type:audit-finding',
    description: 'Security audit finding',
    color: '#D32F2F', // Dark red
  },
  {
    name: 'type:refactor',
    description: 'Code refactoring',
    color: '#2196F3', // Blue
  },
  {
    name: 'type:docs',
    description: 'Documentation work',
    color: '#607D8B', // Blue grey
  },

  // Source labels - where work originated
  {
    name: 'source:discord',
    description: 'Originated from Discord feedback',
    color: '#5865F2', // Discord brand color
  },
  {
    name: 'source:github',
    description: 'Originated from GitHub',
    color: '#24292F', // GitHub brand color
  },
  {
    name: 'source:internal',
    description: 'Agent-created work',
    color: '#9E9E9E', // Grey
  },

  // Priority labels - human-assigned urgency
  {
    name: 'priority:critical',
    description: 'Drop everything - critical priority',
    color: '#B71C1C', // Dark red
  },
  {
    name: 'priority:high',
    description: 'Important, address ASAP',
    color: '#E65100', // Dark orange
  },
  {
    name: 'priority:normal',
    description: 'Standard priority',
    color: '#1976D2', // Blue
  },
  {
    name: 'priority:low',
    description: 'Nice to have - low priority',
    color: '#388E3C', // Dark green
  },
];

async function setupLinearLabels(teamId?: string): Promise<void> {
  const apiKey = process.env.LINEAR_API_KEY;

  if (!apiKey) {
    throw new Error('LINEAR_API_KEY environment variable is required');
  }

  const linearClient = new LinearClient({ apiKey });

  console.log('🔧 Linear Label Setup Script');
  console.log('================================\n');

  // Get team
  let team;
  if (teamId) {
    team = await linearClient.team(teamId);
    console.log(`📋 Using team: ${team.name} (${team.id})\n`);
  } else {
    const teams = await linearClient.teams();
    if (teams.nodes.length === 0) {
      throw new Error('No teams found in Linear workspace');
    }
    team = teams.nodes[0];
    console.log(`📋 Using default team: ${team.name} (${team.id})\n`);
  }

  // Fetch existing labels
  console.log('📥 Fetching existing labels...');
  const existingLabelsResponse = await linearClient.issueLabels({
    filter: { team: { id: { eq: team.id } } },
  });
  const existingLabels = existingLabelsResponse.nodes;
  const existingLabelNames = new Set(existingLabels.map(label => label.name));
  console.log(`   Found ${existingLabels.length} existing labels\n`);

  // Create labels
  console.log('🏷️  Creating labels...\n');

  let created = 0;
  let skipped = 0;
  const errors: Array<{ label: string; error: string }> = [];

  for (const labelDef of BASE_LABELS) {
    try {
      if (existingLabelNames.has(labelDef.name)) {
        console.log(`   ⏭️  Skipped: ${labelDef.name} (already exists)`);
        skipped++;
        continue;
      }

      const result = await linearClient.createIssueLabel({
        name: labelDef.name,
        description: labelDef.description,
        color: labelDef.color,
        teamId: team.id,
      });

      if (result.success) {
        console.log(`   ✅ Created: ${labelDef.name}`);
        created++;
      } else {
        console.log(`   ❌ Failed: ${labelDef.name}`);
        errors.push({ label: labelDef.name, error: 'Create operation failed' });
      }
    } catch (error) {
      console.log(`   ❌ Error: ${labelDef.name} - ${error.message}`);
      errors.push({ label: labelDef.name, error: error.message });
    }
  }

  // Summary
  console.log('\n================================');
  console.log('📊 Summary:');
  console.log(`   ✅ Created: ${created}`);
  console.log(`   ⏭️  Skipped: ${skipped}`);
  console.log(`   ❌ Errors: ${errors.length}`);

  if (errors.length > 0) {
    console.log('\n❌ Errors encountered:');
    errors.forEach(({ label, error }) => {
      console.log(`   - ${label}: ${error}`);
    });
  }

  console.log('\n✨ Label setup complete!\n');

  // Print usage examples
  console.log('📖 Usage Examples:');
  console.log('   Query issues by agent:');
  console.log('     mcp__linear__list_issues({ filter: { labels: { some: { name: { eq: "agent:implementer" } } } } })');
  console.log('\n   Query security findings:');
  console.log('     mcp__linear__list_issues({ filter: { labels: { some: { name: { eq: "type:audit-finding" } } } } })');
  console.log('\n   Query critical priority issues:');
  console.log('     mcp__linear__list_issues({ filter: { labels: { some: { name: { eq: "priority:critical" } } } } })');
  console.log('');
}

// Parse command line arguments
const args = process.argv.slice(2);
let teamId: string | undefined;

for (let i = 0; i < args.length; i++) {
  if (args[i] === '--team-id' && i + 1 < args.length) {
    teamId = args[i + 1];
    i++;
  } else if (args[i] === '--help' || args[i] === '-h') {
    console.log('Usage: npx ts-node scripts/setup-linear-labels.ts [--team-id TEAM_ID]');
    console.log('\nOptions:');
    console.log('  --team-id TEAM_ID    Linear team ID to create labels for (optional)');
    console.log('  --help, -h           Show this help message');
    process.exit(0);
  }
}

// Run the script
setupLinearLabels(teamId)
  .then(() => {
    process.exit(0);
  })
  .catch((error) => {
    console.error('\n❌ Fatal error:', error.message);
    process.exit(1);
  });
