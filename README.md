# 📁 filo — file + logic

> Intelligent file organizer for macOS and windows. One command. Four views. Full rollback.

```bash
npx filo
```

---

## Commands

```bash
filo                          # organize (standard view)
filo --dry-run                # preview without moving anything
filo --view transfer          # throughput + algorithm stats
filo --view debug             # full diagnostic
filo --view compact           # one line output
filo rollback                 # undo last run
filo status                   # session history
filo inspect                  # list past sessions
filo inspect <session-id>     # inspect a specific session
filo inspect <id> --view debug
```

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

---

## Output structure

```
~/Folder Manager/
├── Photos/        May 2026/
├── Documents/     March 2026/
├── Videos/
├── Audio/
├── Archives/
├── Emails/
├── Code/
├── Fonts/
├── Applications/
└── Miscellaneous/
                   Duplicates/
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

- macOS 10.15+
- Node.js 14+

---

## License

MIT
