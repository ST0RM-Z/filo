# 📁 filo — file + logic

> Intelligent file organizer for macOS. One command. Four views. Full rollback.

```bash
npx filo
```

---

## Commands

```bash
filo                          # organize (standard view)
filo --dry-run                # preview without moving anything
filo inspect                  # list past session logs
filo inspect <session-id>     # inspect a specific session
filo rollback                 # undo last run (optional)
filo --help                   # view usage guide and flags


---

## Views

| View | What it shows |
|---|---|
| `standard` | Files moved, duplicates, errors, source → destination |
| `transfer` | Per-category breakdown, throughput, algorithm benchmark |
| `debug` | Every file event, checksum pairs, error reasons, verify failures |
| `compact` | Single line — `✓  47 moved  3 dupes  0 errors` |

---

## How it works

**Three independent phases:**

1. **Scan** — catalogs every file, computes MD5 checksum, builds manifest
2. **Move** — executes from manifest; duplicates go to `Duplicates/` subfolder
3. **Verify** — re-checks every checksum at destination independently

**Algorithm benchmark** — before moving, filo benchmarks three classification strategies on your actual files:

```
  Strategy          Complexity    Time    Accuracy
  Extension Hash    O(1)          8ms      98%    ← selected
  Name Pattern      O(n log n)    42ms     96%
  MIME Detection    O(n)          180ms    99%
```

**Git-style rollback** — every run is saved as a `.jsonl` session log. `filo rollback` reverses every operation in reverse order. A session can only be rolled back once.

```
filo runs 100% locally and offline without reading sensitive file bodies or pulling in risky third-party parsers.

Tier 1 — User Subfolder Protection: Leaves existing subfolders inside ~/Documents/ (e.g., ~/Documents/Medical/) untouched to preserve custom collections and file context.

Tier 2 — OS-Native Metadata Inspection: Uses OS extended attributes (mdls on macOS, Zone.Identifier on Windows) to route downloads based on origin URLs (e.g., banking portals → Finance/).

Tier 3 — Token & Temporal Clustering: Automatically groups loose files sharing lexical stems (e.g., Tax_2024.pdf, Tax_2025.pdf → ~/Documents/Tax/) or created within the same 5-minute session window into clean batch folders.
```
---

## Output structure

```

~ (User Home Directory)
├── Documents/
│   ├── Medical/            ← Protected user folder (kept intact)
│   ├── Tax/                ← Grouped via Token Clustering (Tax_2024, Tax_2025)
│   └── Health/             ← Grouped via OS Metadata (medical portal downloads)
├── Pictures/               ← All loose image formats (.png, .jpg, .heic)
├── Movies/                 ← All loose video formats (.mp4, .mov, .mkv)
├── Music/                  ← All loose audio formats (.mp3, .wav, .flac)
└── Projects/               ← Recognized project codebases (.git, package.json)
```

---

## Debug & diagnostics

```bash
filo --view debug              # see everything during a run
filo inspect <id> --view debug # diagnose a past session
```

Debug view shows:
- Every file move with source → destination
- Checksum before and after (first 8 chars)
- Error reason (permission denied, mv failed, etc.)
- Verification failures with expected vs actual checksum
- Algorithm selection with timing

---

## Requirements

- macOS 10.15+ or Windows 10+
- Node.js 14+

---

## License

MIT
