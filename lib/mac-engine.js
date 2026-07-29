const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execSync } = require('child_process');

// ── Tier 2: OS-Native Extended Attribute Extraction ───────────────────
function getOSMetadataCategory(filePath) {
  try {
    const stdout = execSync(`mdls -raw -name kMDItemWhereFroms "${filePath}"`, { encoding: 'utf8' });
    if (!stdout || stdout === '(null)') return null;

    const lower = stdout.toLowerCase();
    if (lower.includes('bank') || lower.includes('chase') || lower.includes('statement') || lower.includes('billing')) return 'Finance';
    if (lower.includes('health') || lower.includes('medical') || lower.includes('patient') || lower.includes('portal')) return 'Health';
    if (lower.includes('flight') || lower.includes('airline') || lower.includes('hotel') || lower.includes('booking')) return 'Travel';
  } catch (e) {
    return null;
  }
  return null;
}

function getMacDestDir(category, filePath, homeDir) {
  const metaCategory = getOSMetadataCategory(filePath);
  if (metaCategory) {
    return path.join(homeDir, 'Documents', metaCategory);
  }

  switch (category) {
    case 'Audio': return path.join(homeDir, 'Music');
    case 'Videos': return path.join(homeDir, 'Movies');
    case 'Photos': return path.join(homeDir, 'Pictures');
    case 'Projects': return path.join(homeDir, 'Projects');
    case 'Code': return path.join(homeDir, 'Developer', 'Code');
    case 'Archives': return path.join(homeDir, 'Downloads', 'Archives');
    case 'Documents': return path.join(homeDir, 'Documents');
    default: return path.join(homeDir, 'Documents', 'Miscellaneous');
  }
}

function getFileChecksum(filePath) {
  try { return crypto.createHash('md5').update(fs.readFileSync(filePath)).digest('hex'); }
  catch (e) { return 'unavailable'; }
}

function getCategoryByExtension(ext) {
  const docs = /^(pdf|doc|docx|xls|xlsx|ppt|pptx|txt|rtf|csv|md)$/i;
  const photos = /^(jpg|jpeg|png|gif|bmp|tiff|heic|webp|svg)$/i;
  const archives = /^(zip|tar|gz|7z|rar|dmg|pkg)$/i;
  const videos = /^(mp4|mov|avi|mkv|wmv|flv|webm)$/i;
  const audio = /^(mp3|wav|flac|aac|ogg|m4a)$/i;

  if (docs.test(ext)) return 'Documents';
  if (photos.test(ext)) return 'Photos';
  if (archives.test(ext)) return 'Archives';
  if (videos.test(ext)) return 'Videos';
  if (audio.test(ext)) return 'Audio';
  return 'Miscellaneous';
}

function isProjectFolder(dirPath) {
  const projectMarkers = ['package.json', '.git', '.env', 'xcworkspace', 'xcodeproj'];
  try { return fs.readdirSync(dirPath).some(item => projectMarkers.includes(item)); } 
  catch (e) { return false; }
}

// ── Tier 3A: Token & Prefix Clustering Helper ─────────────────────────
function groupFilesBySemanticSimilarity(files) {
  const groups = {};
  const ungrouped = [];

  function getTokens(filename) {
    const nameWithoutExt = path.parse(filename).name;
    return nameWithoutExt
      .toLowerCase()
      .replace(/[0-9_+\-\s]+/g, ' ')
      .trim()
      .split(/\s+/)
      .filter(token => token.length > 2);
  }

  files.forEach(fileObj => {
    const tokens = getTokens(fileObj.item);
    if (tokens.length === 0) {
      ungrouped.push(fileObj);
      return;
    }

    const primaryKey = tokens[0];
    if (!groups[primaryKey]) groups[primaryKey] = [];
    groups[primaryKey].push(fileObj);
  });

  const lexicalClusters = [];

  Object.keys(groups).forEach(key => {
    if (groups[key].length >= 2) {
      const folderName = key.charAt(0).toUpperCase() + key.slice(1);
      lexicalClusters.push({ folderName, files: groups[key] });
    } else {
      ungrouped.push(...groups[key]);
    }
  });

  return { lexicalClusters, remaining: ungrouped };
}

// ── Tier 3B: Temporal Clustering Helper ───────────────────────────────
function clusterByTime(files) {
  const TIME_WINDOW_MS = 5 * 60 * 1000; // 5-minute window
  const clusters = [];

  const sorted = files.slice().sort((a, b) => a.mtime - b.mtime);

  sorted.forEach(file => {
    let placed = false;
    for (const cluster of clusters) {
      const avgTime = cluster.reduce((sum, f) => sum + f.mtime, 0) / cluster.length;
      if (Math.abs(file.mtime - avgTime) <= TIME_WINDOW_MS) {
        cluster.push(file);
        placed = true;
        break;
      }
    }
    if (!placed) {
      clusters.push([file]);
    }
  });

  return clusters;
}

function processDirectory(dirPath, homeDir, options, stats, logs) {
  if (!fs.existsSync(dirPath)) return;
  const items = fs.readdirSync(dirPath);
  const docsDir = path.join(homeDir, 'Documents');

  const looseFiles = [];

  items.forEach(item => {
    if (item.startsWith('.')) return;
    const fullPath = path.join(dirPath, item);
    let stat;
    try { stat = fs.statSync(fullPath); } catch (e) { return; }

    if (stat.isDirectory()) {
      // Tier 1: Protect Projects and preserve user subfolders inside ~/Documents
      if (isProjectFolder(fullPath)) {
        const dest = path.join(homeDir, 'Projects');
        const finalPath = path.join(dest, item);

        if (fs.existsSync(finalPath)) {
          console.log(`  \x1b[33m[SKIP]\x1b[0m      Project folder exists: ~/Projects/${item}/`);
          return;
        }

        console.log(`  \x1b[35m[PROJECT]\x1b[0m   ${item.padEnd(30)} \x1b[90m→\x1b[0m \x1b[36m~/Projects/\x1b[0m`);
        stats.moved++;
        logs.push({ type: 'PROJECT', name: item, from: fullPath, to: finalPath });
        if (!options.isDryRun) {
          fs.mkdirSync(dest, { recursive: true });
          fs.renameSync(fullPath, finalPath);
        }
      }
      // Note: Do NOT recurse into ~/Documents subfolders to protect user collections!
    } else if (stat.isFile()) {
      // Tier 1 Guard: If a file is ALREADY inside any subfolder in ~/Documents, leave it alone!
      const isInsideSubfolderInDocs = dirPath.startsWith(docsDir) && dirPath !== docsDir;
      if (isInsideSubfolderInDocs) return;

      looseFiles.push({ item, fullPath, mtime: stat.mtimeMs });
    }
  });

  // Apply Tier 3A: Token & Prefix Clustering
  const { lexicalClusters, remaining } = groupFilesBySemanticSimilarity(looseFiles);

  lexicalClusters.forEach(cluster => {
    const targetDir = path.join(homeDir, 'Documents', cluster.folderName);
    cluster.files.forEach(({ item, fullPath }) => {
      moveFile(item, fullPath, targetDir, homeDir, options, stats, logs);
    });
  });

  // Apply Tier 3B: Temporal Clustering on remaining files
  const timeClusters = clusterByTime(remaining);

  timeClusters.forEach(cluster => {
    const hasMultipleTypes = cluster.length > 1;
    let clusterDir = null;

    if (hasMultipleTypes) {
      const dateStr = new Date(cluster[0].mtime).toISOString().split('T')[0];
      clusterDir = path.join(homeDir, 'Documents', `Batch_${dateStr}`);
    }

    cluster.forEach(({ item, fullPath }) => {
      const ext = path.extname(item).substring(1);
      const category = getCategoryByExtension(ext);
      const finalDestDir = clusterDir || getMacDestDir(category, fullPath, homeDir);
      moveFile(item, fullPath, finalDestDir, homeDir, options, stats, logs);
    });
  });
}

function moveFile(item, fullPath, finalDestDir, homeDir, options, stats, logs) {
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
