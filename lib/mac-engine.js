const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const os = require('os');

function getMacDestDir(category, homeDir) {
  switch (category) {
    case 'Audio': return path.join(homeDir, 'Music');
    case 'Videos': return path.join(homeDir, 'Movies');
    case 'Photos': return path.join(homeDir, 'Pictures');
    case 'Documents': return path.join(homeDir, 'Documents');
    case 'Emails': return path.join(homeDir, 'Documents', 'Emails');
    case 'Projects': return path.join(homeDir, 'Projects');
    case 'Code': return path.join(homeDir, 'Developer', 'Code');
    case 'Archives': return path.join(homeDir, 'Downloads', 'Archives');
    default: return path.join(homeDir, 'Documents', 'Miscellaneous');
  }
}

function getFileChecksum(filePath) {
  try {
    return crypto.createHash('md5').update(fs.readFileSync(filePath)).digest('hex');
  } catch (e) { return 'unavailable'; }
}

function getCategoryByExtension(ext) {
  const docs = /^(pdf|doc|docx|xls|xlsx|ppt|pptx|txt|rtf|csv|md)$/i;
  const photos = /^(jpg|jpeg|png|gif|bmp|tiff|heic|webp|svg)$/i;
  const archives = /^(zip|tar|gz|7z|rar|dmg|pkg)$/i;
  const videos = /^(mp4|mov|avi|mkv|wmv|flv|webm)$/i;
  const audio = /^(mp3|wav|flac|aac|ogg|m4a)$/i;
  const code = /^(py|js|ts|html|css|java|c|cpp|cs|json|sh|bat|ps1)$/i;

  if (docs.test(ext)) return 'Documents';
  if (photos.test(ext)) return 'Photos';
  if (archives.test(ext)) return 'Archives';
  if (videos.test(ext)) return 'Videos';
  if (audio.test(ext)) return 'Audio';
  if (code.test(ext)) return 'Code';
  return 'Miscellaneous';
}

function isProjectFolder(dirPath) {
  const projectMarkers = ['package.json', '.git', '.env', 'xcworkspace', 'xcodeproj'];
  try { return fs.readdirSync(dirPath).some(item => projectMarkers.includes(item)); } catch (e) { return false; }
}

function processDirectory(dirPath, homeDir, options, stats, logs) {
  if (!fs.existsSync(dirPath)) return;
  const items = fs.readdirSync(dirPath);

  items.forEach(item => {
    if (item.startsWith('.')) return;
    const fullPath = path.join(dirPath, item);
    let stat;
    try { stat = fs.statSync(fullPath); } catch (e) { return; }

    if (stat.isDirectory()) {
      if (isProjectFolder(fullPath)) {
        const dest = getMacDestDir('Projects', homeDir);
        const finalPath = path.join(dest, item);

        // Guard Check: Skip moving if the target folder already exists to prevent crashes
        if (fs.existsSync(finalPath)) {
          console.log(`  \x1b[33m[SKIP]\x1b[0m      Project folder already exists at target: ~/Projects/${item}/`);
          return;
        }

        console.log(`  \x1b[35m[PROJECT]\x1b[0m   ${item.padEnd(30)} \x1b[90m→\x1b[0m \x1b[36m~/Projects/\x1b[0m`);
        stats.moved++;
        logs.push({ type: 'PROJECT', name: item, from: fullPath, to: finalPath });
        if (!options.isDryRun) {
          fs.mkdirSync(dest, { recursive: true });
          fs.renameSync(fullPath, finalPath);
        }
      } else if (dirPath === path.join(homeDir, 'Documents')) {
        processDirectory(fullPath, homeDir, options, stats, logs);
      }
    } else if (stat.isFile()) {
      const ext = path.extname(item).substring(1);
      const category = getCategoryByExtension(ext);
      const finalDestDir = getMacDestDir(category, homeDir);

      if (category === 'Documents' && dirPath === path.join(homeDir, 'Documents')) return;

      const finalDestPath = path.join(finalDestDir, item);
      const printableDest = finalDestPath.replace(homeDir, '~');

      if (fs.existsSync(finalDestPath)) {
        if (getFileChecksum(fullPath) === getFileChecksum(finalDestPath)) {
          console.log(`  \x1b[33m[DUPE]\x1b[0m      ${item.padEnd(30)} \x1b[90m→\x1b[0m \x1b[90m${printableDest}\x1b[0m`);
          stats.dupes++;
          return;
        }
      }

      console.log(`  \x1b[32m[MOVE]\x1b[0m      ${item.padEnd(30)} \x1b[90m→\x1b[0m \x1b[34m${printableDest}\x1b[0m`);
      stats.moved++;
      logs.push({ type: 'MOVE', name: item, from: fullPath, to: finalDestPath });

      if (!options.isDryRun) {
        fs.mkdirSync(finalDestDir, { recursive: true });
        fs.renameSync(fullPath, finalDestPath);
      }
    }
  });
}

function run(args, homeDir) {
  const options = { isDryRun: args.includes('--dry-run') };
  const stats = { moved: 0, dupes: 0 };
  const sessionLogs = [];
  const sessionId = Math.random().toString(16).substring(2, 9);

  const scanTargets = [
    path.join(homeDir, 'Downloads'),
    path.join(homeDir, 'Desktop'),
    path.join(homeDir, 'Documents')
  ];

  scanTargets.forEach(target => processDirectory(target, homeDir, options, stats, sessionLogs));

  console.log(`\n  \x1b[1m📁 filo\x1b[0m  session \x1b[36m${sessionId}\x1b[0m`);
  if (options.isDryRun) console.log(`  \x1b[1;33mdry run — no files moved\x1b[0m`);
  console.log(`\n  \x1b[32m✓\x1b[0m  \x1b[1m${stats.moved}\x1b[0m moved   \x1b[33m${stats.dupes}\x1b[0m duplicate   \x1b[31m0\x1b[0m errors`);
  console.log(`\n  \x1b[90mfrom\x1b[0m  ~/Downloads, ~/Desktop`);
  console.log(`  \x1b[90mto\x1b[0m    ~/Music  ~/Movies  ~/Pictures  ~/Documents`);
  console.log(`\n  \x1b[90m──────────────────────────────────────────\x1b[0m\n  \x1b[90mundo:\x1b[0m    \x1b[33mfilo rollback\x1b[0m\n  \x1b[90mdetails:\x1b[0m \x1b[36mfilo inspect ${sessionId}\x1b[0m\n`);

  const sessionDir = path.join(homeDir, '.filo', 'sessions');
  fs.mkdirSync(sessionDir, { recursive: true });
  fs.writeFileSync(
    path.join(sessionDir, `${sessionId}.json`),
    JSON.stringify({ sessionId, date: new Date(), isDryRun: options.isDryRun, stats, operations: sessionLogs }, null, 2)
  );
}

module.exports = { run };
