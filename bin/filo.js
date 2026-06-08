#!/usr/bin/env node

const { execFileSync } = require('child_process');
const path = require('path');
const os   = require('os');
const fs   = require('fs');

const CORE    = path.join(__dirname, '..', 'lib', 'core.sh');
const INSPECT = path.join(__dirname, '..', 'lib', 'inspect.sh');
const args    = process.argv.slice(2);

// ── Platform check ────────────────────────────────────────
if (os.platform() !== 'darwin') {
  console.error('\n  ✗ filo currently supports macOS only.\n    Windows and Linux support coming soon.\n');
  process.exit(1);
}

// ── Make scripts executable ───────────────────────────────
const scripts = [
  CORE,
  path.join(__dirname, '..', 'lib', 'inspect.sh'),
  path.join(__dirname, '..', 'lib', 'views', 'standard.sh'),
  path.join(__dirname, '..', 'lib', 'views', 'transfer.sh'),
  path.join(__dirname, '..', 'lib', 'views', 'debug.sh'),
  path.join(__dirname, '..', 'lib', 'views', 'compact.sh'),
];
scripts.forEach(s => { try { fs.chmodSync(s, '755'); } catch (_) {} });

// ── Help ──────────────────────────────────────────────────
if (args.includes('--help') || args.includes('-h') || args.length === 0 && process.stdout.isTTY) {
  // show help only if no args — but still run if piped
}

if (args.includes('--help') || args.includes('-h')) {
  console.log(`
  📁 filo — file + logic  v1.0

  Usage:
    filo                            Organize (standard view)
    filo --dry-run                  Preview without moving
    filo --view <view>              Choose output view
    filo rollback                   Undo the last run
    filo rollback --dry-run         Preview rollback
    filo status                     Session history
    filo inspect                    List past sessions
    filo inspect <id>               Inspect a session
    filo inspect <id> --view debug  Inspect with a specific view

  Views:
    standard   Clean summary  (default)
    transfer   Throughput + algorithm stats
    debug      Full diagnostic — every file, checksum, error
    compact    One line output

  Examples:
    filo --view transfer
    filo inspect a3f9c2d
    filo inspect a3f9c2d --view debug
`);
  process.exit(0);
}

// ── Route commands ────────────────────────────────────────
const cmd    = args[0];
const rest   = args.slice(1);

// Parse --view from anywhere in args
let view = 'standard';
const viewIdx = args.indexOf('--view');
if (viewIdx !== -1 && args[viewIdx + 1]) view = args[viewIdx + 1];
args.forEach(a => { if (a.startsWith('--view=')) view = a.split('=')[1]; });

try {
  if (cmd === 'inspect') {
    const sessionId = rest.find(a => !a.startsWith('-')) || '';
    execFileSync('/bin/bash', [INSPECT, sessionId, view,
      `${os.homedir()}/.filo/sessions`], { stdio: 'inherit' });
  } else {
    execFileSync('/bin/bash', [CORE, ...args], { stdio: 'inherit' });
  }
} catch (err) {
  process.exit(err.status || 1);
}
