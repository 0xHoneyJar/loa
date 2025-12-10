/**
 * Google Service Account Setup Script
 *
 * Interactive script to guide proper setup of Google service account
 * with least privilege permissions.
 *
 * This implements CRITICAL-004 remediation (setup guidance).
 */

import * as readline from 'readline';
import { google } from 'googleapis';
import { configLoader } from '../src/utils/config-loader';
import { drivePermissionValidator } from '../src/services/drive-permission-validator';
import { logger } from '../src/utils/logger';
import path from 'path';
import fs from 'fs';

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

/**
 * Prompt user for input
 */
function prompt(question: string): Promise<string> {
  return new Promise(resolve => {
    rl.question(question, answer => {
      resolve(answer.trim());
    });
  });
}

/**
 * Main setup function
 */
async function setupServiceAccount(): Promise<void> {
  console.log('\n' + '='.repeat(80));
  console.log('Google Service Account Setup - Least Privilege Configuration');
  console.log('='.repeat(80) + '\n');

  console.log('This script will guide you through setting up a Google service account');
  console.log('with the minimum required permissions (least privilege principle).\n');

  // Step 1: API Scopes
  console.log('━'.repeat(80));
  console.log('STEP 1: Configure API Scopes (Read-Only)');
  console.log('━'.repeat(80) + '\n');

  console.log('✅ REQUIRED SCOPES (Read-Only):');
  console.log('  • https://www.googleapis.com/auth/drive.readonly');
  console.log('    → READ-ONLY access to Google Drive (no write, no delete)');
  console.log('  • https://www.googleapis.com/auth/documents.readonly');
  console.log('    → READ-ONLY access to Google Docs (no modify)\n');

  console.log('❌ DO NOT ENABLE:');
  console.log('  • https://www.googleapis.com/auth/drive (full access)');
  console.log('  • https://www.googleapis.com/auth/documents (write access)');
  console.log('  • Any scope ending in ".full" or without ".readonly"\n');

  console.log('⚠️  Why read-only?');
  console.log('  → Service account only needs to READ documents for summaries');
  console.log('  → Write access increases attack surface if credentials compromised');
  console.log('  → Follows principle of least privilege\n');

  const continueSetup = await prompt('Have you configured read-only scopes? (yes/no): ');
  if (continueSetup.toLowerCase() !== 'yes') {
    console.log('\n❌ Please configure API scopes before continuing.\n');
    rl.close();
    return;
  }

  // Step 2: Folder Sharing
  console.log('\n' + '━'.repeat(80));
  console.log('STEP 2: Folder Sharing Checklist');
  console.log('━'.repeat(80) + '\n');

  const config = configLoader.getConfig();
  const monitoredFolders = config.google_docs?.monitored_folders || [];

  if (monitoredFolders.length === 0) {
    console.log('⚠️  WARNING: No monitored folders configured in config.yaml\n');
    console.log('Add folders to config.yaml before proceeding:\n');
    console.log('google_docs:');
    console.log('  monitored_folders:');
    console.log('    - "Engineering/Sprint Updates"');
    console.log('    - "Product/Roadmaps"\n');
    rl.close();
    return;
  }

  console.log('✅ SHARE ONLY THESE FOLDERS with service account:');
  for (const folder of monitoredFolders) {
    console.log(`  ✓ ${folder}`);
    console.log(`    → Permission: Viewer (read-only)`);
  }
  console.log();

  console.log('❌ DO NOT SHARE THESE SENSITIVE FOLDERS:');
  const sensitiveFolders = [
    'Executive/Board Presentations',
    'HR/Personnel Files',
    'Legal/Contracts',
    'Finance/Accounting',
    'Finance/Payroll',
    'Security/Incident Reports',
    'Security/Penetration Tests',
    'Compliance/Audit Reports',
    'M&A/Due Diligence',
    'Customer/Confidential Data'
  ];

  for (const folder of sensitiveFolders) {
    console.log(`  ✗ ${folder}`);
  }
  console.log();

  console.log('⚠️  How to share folders:');
  console.log('  1. Open Google Drive in browser');
  console.log('  2. Right-click folder → Share');
  console.log('  3. Add service account email (ends with @*.iam.gserviceaccount.com)');
  console.log('  4. Set permission to "Viewer" (NOT Editor, NOT Commenter)');
  console.log('  5. Uncheck "Notify people" (no need to email service account)');
  console.log('  6. Click "Share"\n');

  const foldersShared = await prompt('Have you shared ONLY the required folders? (yes/no): ');
  if (foldersShared.toLowerCase() !== 'yes') {
    console.log('\n❌ Please share folders before continuing.\n');
    rl.close();
    return;
  }

  // Step 3: Validate Permissions
  console.log('\n' + '━'.repeat(80));
  console.log('STEP 3: Validate Permissions');
  console.log('━'.repeat(80) + '\n');

  console.log('Running permission validation to ensure setup is correct...\n');

  try {
    // Load service account credentials
    const credentialsPath = path.join(__dirname, '../config/google-service-account.json');

    if (!fs.existsSync(credentialsPath)) {
      console.log('❌ ERROR: Service account credentials not found');
      console.log(`   Expected location: ${credentialsPath}\n`);
      console.log('Please place your service account JSON key file at this location.\n');
      rl.close();
      return;
    }

    const auth = new google.auth.GoogleAuth({
      keyFile: credentialsPath,
      scopes: [
        'https://www.googleapis.com/auth/drive.readonly',
        'https://www.googleapis.com/auth/documents.readonly'
      ]
    });

    // Initialize validator
    await drivePermissionValidator.initialize(await auth.getClient());

    // Run validation
    console.log('🔍 Scanning accessible folders...\n');
    const validation = await drivePermissionValidator.validatePermissions();

    if (validation.valid) {
      console.log('✅ PERMISSION VALIDATION PASSED\n');
      console.log('Service account has correct folder access.\n');

      if (validation.warnings && validation.warnings.length > 0) {
        console.log('⚠️  Warnings:');
        for (const warning of validation.warnings) {
          console.log(`  • ${warning}`);
        }
        console.log();
      }

    } else {
      console.log('❌ PERMISSION VALIDATION FAILED\n');
      console.log('Issues detected:');
      for (const error of validation.errors) {
        console.log(`  ✗ ${error}`);
      }
      console.log();

      if (validation.unexpectedFolders && validation.unexpectedFolders.length > 0) {
        console.log('🚨 UNEXPECTED FOLDER ACCESS DETECTED:\n');
        for (const folder of validation.unexpectedFolders) {
          console.log(`  ⚠️  ${folder.path}`);
          console.log(`     → Link: ${folder.webViewLink}`);
          console.log(`     → Action: Revoke access immediately\n`);
        }
      }

      console.log('ACTION REQUIRED:');
      console.log('  1. Review unexpected folder access above');
      console.log('  2. Remove service account sharing from those folders');
      console.log('  3. Re-run this script to validate\n');

      rl.close();
      return;
    }

  } catch (error) {
    console.log(`❌ ERROR: ${error.message}\n`);
    rl.close();
    return;
  }

  // Step 4: Security Recommendations
  console.log('━'.repeat(80));
  console.log('STEP 4: Security Recommendations');
  console.log('━'.repeat(80) + '\n');

  console.log('✅ Setup complete! Follow these security best practices:\n');

  console.log('1. CREDENTIAL SECURITY:');
  console.log('   • Store service account key in secure location');
  console.log('   • NEVER commit credentials to git');
  console.log('   • Use environment variables or secret manager in production');
  console.log('   • Rotate credentials quarterly\n');

  console.log('2. PERIODIC AUDITS:');
  console.log('   • Run weekly permission audits (automatically scheduled)');
  console.log('   • Review audit logs monthly');
  console.log('   • Investigate any unexpected folder access immediately\n');

  console.log('3. ACCESS CONTROL:');
  console.log('   • Limit who can share folders with service account');
  console.log('   • Document all folder sharing changes');
  console.log('   • Review sharing permissions quarterly\n');

  console.log('4. MONITORING:');
  console.log('   • Monitor service account usage in Google Cloud Console');
  console.log('   • Set up alerts for unusual API usage');
  console.log('   • Review security logs weekly\n');

  console.log('━'.repeat(80));
  console.log('NEXT STEPS');
  console.log('━'.repeat(80) + '\n');

  console.log('1. Start the integration service:');
  console.log('   npm run start\n');

  console.log('2. Test document scanning:');
  console.log('   npm run test:scan\n');

  console.log('3. Monitor security logs:');
  console.log('   tail -f logs/security-events.log\n');

  console.log('━'.repeat(80) + '\n');

  rl.close();
}

/**
 * CLI entry point
 */
if (require.main === module) {
  setupServiceAccount()
    .then(() => {
      console.log('✅ Setup complete!\n');
      process.exit(0);
    })
    .catch(error => {
      console.error(`\n❌ Setup failed: ${error.message}\n`);
      console.error(error.stack);
      process.exit(1);
    });
}

export { setupServiceAccount };
