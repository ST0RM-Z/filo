#!/usr/bin/env node

const os = require('os');
const fs = require('fs');
const path = require('path');
const args = process.argv.slice(2);

const isMac = os.platform() === 'darwin';
const isWindows = os.platform() === 'win32';

if (!isMac && !isWindows) {
  console.error(`\n  ✗ filo currently does not support platform: ${os.platform()}.\n`);
  process.exit(1);
}

const cmd = args[0];
const sessionDir = path.join(os.homedir(), '.filo', 'sessions');

// ── Handle Inspect Action ─────────────────────────────────
if (cmd === 'inspect') {
  const sessionId = args[1];

  if (!sessionId) {
    if (!fs.existsSync(sessionDir)) {
      console.log('\n  No active history sessions found.\n');
      process.exit(0);
    }

    console.log('\n  \x1b[1m📁 filo inspect — available sessions:\x1b[0m\n');
    
    const files = fs.readdirSync(sessionDir)
      .filter(f => f.endsWith('.json'))
      .map(f => {
        try {
          return JSON.parse(fs.readFileSync(path.join(sessionDir, f), 'utf8'));
        } catch(e) { return null; }
      })
      .filter(Boolean)
      .sort((a, b) => new Date(b.date) - new Date(a.date));

    files.forEach(data => {
      const timeStr = new Date(data.date).toISOString().replace('Z', '').replace('T', ' ').substring(0, 19);
      const modeIndicator = data.isDryRun ? '\x1b[33mdry\x1b[0m' : '\x1b[32mok\x1b[0m';
      console.log(`  \x1b[36m${data.sessionId.padEnd(8)}\x1b[0m  \x1b[90m${timeStr}\x1b[0m  ${String(data.stats.moved).padStart(4)} moved  ${modeIndicator}`);
    });

    console.log(`\n  \x1b[90mUsage: filo inspect <session-id> [--view debug|transfer|compact]\x1b[0m\n`);
    process.exit(0);
  }

  const sessionFile = path.join(sessionDir, `${sessionId}.json`);
  if (!fs.existsSync(sessionFile)) {
    console.error(`\n  \x1b[31m✗\x1b[0m Session not found: ${sessionId}`);
    console.log(`  Run 'filo inspect' to list available sessions.\n`);
    process.exit(1);
  }

  const data = JSON.parse(fs.readFileSync(sessionFile, 'utf8'));
  console.log(`\n  \x1b[1m📁 filo session logs [${data.sessionId}]\x1b[0m`);
  if (data.isDryRun) console.log(`  \x1b[1;33mdry run — no files moved\x1b[0m`);
  console.log(`  \x1b[90mExecuted on: ${new Date(data.date).toLocaleString()}\x1b[0m\n`);
  
  if (data.operations && data.operations.length > 0) {
    data.operations.forEach(op => {
      const printableDest = op.to.replace(os.homedir(), '~');
      console.log(`  \x1b[32m[${op.type}]\x1b[0m  ${op.name.padEnd(30)} \x1b[90m→\x1b[0m \x1b[34m${printableDest}\x1b[0m`);
    });
  } else {
    console.log('  \x1b[90mNo file operations logged for this run.\x1b[0m');
  }
  console.log(`\n  ✓ Captured Summary: ${data.stats.moved} operations logged.\n`);
  process.exit(0);
}

// ── Help Menu ─────────────────────────────────────────────
if (args.includes('--help') || args.includes('-h')) {
  console.log(`
  📁 filo — file + logic  v1.0.7

  Usage:
    filo                            Organize (standard view)
    filo --dry-run                  Preview without moving
    filo inspect                    List all past logs
    filo inspect <id>               Inspect a historical session

  Examples:
    filo --dry-run
    filo inspect
  `);
  process.exit(0);
}

// ── Main Pipeline Router ──────────────────────────────────
try {
  if (isMac) {
    require('../lib/mac-engine').run(args, os.homedir());
  } else if (isWindows) {
    require('../lib/windows-engine').run(args, os.homedir());
  }
} catch (err) {
  console.error('❌ Error executing file engine operations:', err.message);
  process.exit(1);
}
