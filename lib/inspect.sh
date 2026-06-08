#!/bin/bash
# ── filo inspect <session-id> [--view <view>] ─────────────
# Reads a past session log and renders it in any view

SESSION_ARG=$1
VIEW=${2:-standard}
SESSIONS_DIR=$3

G='\033[0;32m' R='\033[0;31m' Y='\033[1;33m'
B='\033[0;34m' C='\033[0;36m' M='\033[0;35m'
BOLD='\033[1m' DIM='\033[2m'  RESET='\033[0m'

FILO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VIEWS_DIR="$FILO_DIR/lib/views"

# Find session file
if [[ -z "$SESSION_ARG" ]]; then
  # No session given — show picker
  echo ""
  echo -e "  ${BOLD}filo inspect${RESET} — available sessions:"
  echo ""
  sessions=$(ls -t "$SESSIONS_DIR"/*.jsonl 2>/dev/null | head -10)
  if [[ -z "$sessions" ]]; then
    echo -e "  ${DIM}No sessions found.${RESET}"; echo ""; exit 0
  fi
  i=1
  for f in $sessions; do
    sid=$(basename "$f" .jsonl)
    ts=$(head -1 "$f" | grep -o '"ts":"[^"]*"' | cut -d'"' -f4 | cut -c1-19)
    moved=$(grep '"e":"MOVE_DONE"' "$f" 2>/dev/null | grep -o '"moved":"[^"]*"' | cut -d'"' -f4)
    errors=$(grep '"e":"MOVE_DONE"' "$f" 2>/dev/null | grep -o '"errors":"[^"]*"' | cut -d'"' -f4)
    rolled=$(grep -c '"e":"ROLLBACK"' "$f" 2>/dev/null); rolled=${rolled:-0}
    status="${G}ok${RESET}"
    [[ "${errors:-0}" -gt 0 ]] && status="${R}errors${RESET}"
    [[ $rolled -gt 0 ]]        && status="${DIM}rolled back${RESET}"
    echo -e "  ${C}${sid}${RESET}  $(printf '%-19s' "$ts")  ${moved:-0} moved  $status"
    ((i++))
  done
  echo ""
  echo -e "  Usage: ${C}filo inspect <session-id> [--view debug|transfer|compact]${RESET}"
  echo ""
  exit 0
fi

# Find the file
SESSION_FILE=$(ls "$SESSIONS_DIR/${SESSION_ARG}"*.jsonl 2>/dev/null | head -1)
if [[ ! -f "$SESSION_FILE" ]]; then
  echo -e "\n  ${R}Session not found: $SESSION_ARG${RESET}"
  echo -e "  ${DIM}Run 'filo inspect' to list available sessions.${RESET}\n"
  exit 1
fi

SESSION_ID=$(basename "$SESSION_FILE" .jsonl)

# Read summary from session
end_line=$(grep '"e":"MOVE_DONE"' "$SESSION_FILE" 2>/dev/null | tail -1)
verify_line=$(grep '"e":"VERIFY_DONE"' "$SESSION_FILE" 2>/dev/null | tail -1)
scan_line=$(grep '"e":"SCAN_DONE"' "$SESSION_FILE" 2>/dev/null | tail -1)

scan_count=$(echo "$scan_line"  | grep -o '"count":"[^"]*"'      | cut -d'"' -f4)
total_bytes=$(echo "$scan_line" | grep -o '"total_bytes":"[^"]*"' | cut -d'"' -f4)
moved=$(echo "$end_line"        | grep -o '"moved":"[^"]*"'       | cut -d'"' -f4)
duplicates=$(echo "$end_line"   | grep -o '"duplicates":"[^"]*"'  | cut -d'"' -f4)
errors=$(echo "$end_line"       | grep -o '"errors":"[^"]*"'      | cut -d'"' -f4)
bytes_moved=$(echo "$end_line"  | grep -o '"bytes_moved":"[^"]*"' | cut -d'"' -f4)
elapsed=$(echo "$end_line"      | grep -o '"elapsed_ms":"[^"]*"'  | cut -d'"' -f4)
verified=$(echo "$verify_line"  | grep -o '"verified":"[^"]*"'    | cut -d'"' -f4)
mismatches=$(echo "$verify_line"| grep -o '"mismatches":"[^"]*"'  | cut -d'"' -f4)
dry_run=$(head -1 "$SESSION_FILE" | grep -o '"dry_run":"[^"]*"'   | cut -d'"' -f4)
dest_base="$HOME/Folder Manager"

# Check rollback status
rolled=$(grep -c '"e":"ROLLBACK"' "$SESSION_FILE" 2>/dev/null || echo 0)
[[ "$rolled" -gt 0 ]] && echo -e "\n  ${Y}⚠  This session was rolled back.${RESET}"

# Render view
VIEW_SCRIPT="$VIEWS_DIR/${VIEW}.sh"
[[ ! -f "$VIEW_SCRIPT" ]] && VIEW_SCRIPT="$VIEWS_DIR/standard.sh"

bash "$VIEW_SCRIPT" \
  "$SESSION_ID" "$dry_run" \
  "${scan_count:-0}" "${moved:-0}" "${duplicates:-0}" "${errors:-0}" \
  "${verified:-0}" "${mismatches:-0}" \
  "${bytes_moved:-0}" "${elapsed:-0}" "${total_bytes:-0}" \
  "$SESSION_FILE" "$dest_base"
