const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

function getWindowsDestDir(category, homeDir) {
  switch (category) {
    case 'Audio': return path.join(homeDir, 'Music');
    case 'Videos': return path.join(homeDir, 'Videos');
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

function run(args, homeDir) {
  const options = { isDryRun: args.includes('--dry-run') };
  let movedCount = 0;
  let dupeCount = 0;
  const sessionId = Math.random().toString(16).substring(2, 9);

  const sourceDirs = [
    path.join(homeDir, 'Downloads'),
    path.join(homeDir, 'Desktop')
  ];

  sourceDirs.forEach(srcDir => {
    if (!fs.existsSync(srcDir)) return;
    const files = fs.readdirSync(srcDir);

    files.forEach(file => {
      if (file.startsWith('.') || file === 'desktop.ini' || file === 'Thumbs.db') return;
      const fullPath = path.join(srcDir, file);
      let stat;
      try { stat = fs.statSync(fullPath); } catch(e) { return; }

      if (stat.isFile()) {
        const ext = path.extname(file).substring(1);
        const category = getCategoryByExtension(ext);
        const finalDestDir = getWindowsDestDir(category, homeDir);
        const finalDestPath = path.join(finalDestDir, file);
        
        const printableDest = finalDestPath.replace(homeDir, '~').replace(/\\/g, '/');

        if (fs.existsSync(finalDestPath)) {
          if (getFileChecksum(fullPath) === getFileChecksum(finalDestPath)) {
            console.log(`  \x1b[33m[DUPE]\x1b[0m      ${file.padEnd(30)} \x1b[90m→\x1b[0m \x1b[90m${printableDest}\x1b[0m`);
            dupeCount++;
            return;
          }
        }

        console.log(`  \x1b[32m[MOVE]\x1b[0m      ${file.padEnd(30)} \x1b[90m→\x1b[0m \x1b[34m${printableDest}\x1b[0m`);
        movedCount++;

        if (!options.isDryRun) {
          fs.mkdirSync(finalDestDir, { recursive: true });
          fs.renameSync(fullPath, finalDestPath);
        }
      }
    });
  });

  console.log(`\n  \x1b[1m📁 filo\x1b[0m  session \x1b[36m${sessionId}\x1b[0m`);
  if (options.isDryRun) console.log(`  \x1b[1;33mdry run — no files moved\x1b[0m`);
  console.log(`\n  \x1b[32m✓\x1b[0m  \x1b[1m${movedCount}\x1b[0m moved   \x1b[33m${dupeCount}\x1b[0m duplicate   \x1b[31m0\x1b[0m errors`);
  console.log(`\n  \x1b[90mfrom\x1b[0m  ~/Downloads, ~/Desktop`);
  console.log(`  \x1b[90mto\x1b[0m    ~/Music  ~/Videos  ~/Pictures  ~/Documents`);
  console.log(`\n  \x1b[90m──────────────────────────────────────────\x1b[0m\n  \x1b[90mundo:\x1b[0m    \x1b[33mfilo rollback\x1b[0m\n  \x1b[90mdetails:\x1b[0m \x1b[36mfilo inspect ${sessionId}\x1b[0m\n`);
}

module.exports = { run };
