#!/bin/bash
# ── Compact View ──────────────────────────────────────────
# One line. Everything you need.

SESSION_ID=$1  DRY_RUN=$2
SCAN=$3        MOVED=$4    DUPES=$5     ERRORS=$6
VERIFIED=$7    MISMATCHES=$8
BYTES_MOVED=$9 ELAPSED=${10} TOTAL_BYTES=${11}
SESSION_FILE=${12} DEST_BASE=${13}

G='\033[0;32m' R='\033[0;31m' Y='\033[1;33m'
C='\033[0;36m' BOLD='\033[1m' DIM='\033[2m' RESET='\033[0m'

fmt_bytes() {
  local b=$1
  if   [[ $b -ge 1073741824 ]]; then printf "%.1fGB" "$(echo "$b" | awk '{printf "%.1f", $1/1073741824}')";
  elif [[ $b -ge 1048576 ]];    then printf "%.1fMB" "$(echo "$b" | awk '{printf "%.1f", $1/1048576}')";
  elif [[ $b -ge 1024 ]];       then printf "%.1fKB" "$(echo "$b" | awk '{printf "%.1f", $1/1024}')";
  else printf "%dB" "$b"; fi
}

echo ""
if [[ $ERRORS -eq 0 && $MISMATCHES -eq 0 ]]; then
  STATUS="${G}✓${RESET}"
else
  STATUS="${R}✗${RESET}"
fi

SIZE_STR=""
[[ $BYTES_MOVED -gt 0 ]] && SIZE_STR=" · $(fmt_bytes "$BYTES_MOVED")"

[[ "$DRY_RUN" == "true" ]] && DRY="  ${Y}dry-run${RESET}" || DRY=""

printf "  $STATUS  ${BOLD}%d${RESET} moved  ${Y}%d${RESET} dupes  ${R}%d${RESET} errors%s  ${DIM}[%s]${RESET}%s\n" \
  "$MOVED" "$DUPES" "$ERRORS" "$SIZE_STR" "$SESSION_ID" "$DRY"

[[ $ERRORS -gt 0 || $MISMATCHES -gt 0 ]] && \
  printf "     ${DIM}→ filo inspect %s --view debug${RESET}\n" "$SESSION_ID"

echo ""
