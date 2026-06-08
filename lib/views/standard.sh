#!/bin/bash
# ── Standard View ─────────────────────────────────────────
# Clean, minimal. Just what happened and where.

SESSION_ID=$1  DRY_RUN=$2
SCAN=$3        MOVED=$4    DUPES=$5     ERRORS=$6
VERIFIED=$7    MISMATCHES=$8
BYTES_MOVED=$9 ELAPSED=${10} TOTAL_BYTES=${11}
SESSION_FILE=${12} DEST_BASE=${13}

G='\033[0;32m' R='\033[0;31m' Y='\033[1;33m'
B='\033[0;34m' C='\033[0;36m' M='\033[0;35m'
BOLD='\033[1m' DIM='\033[2m'  RESET='\033[0m'

fmt_bytes() {
  local b=$1
  if   [[ $b -ge 1073741824 ]]; then printf "%.1f GB" "$(echo "$b" | awk '{printf "%.1f", $1/1073741824}')";
  elif [[ $b -ge 1048576 ]];    then printf "%.1f MB" "$(echo "$b" | awk '{printf "%.1f", $1/1048576}')";
  elif [[ $b -ge 1024 ]];       then printf "%.1f KB" "$(echo "$b" | awk '{printf "%.1f", $1/1024}')";
  else printf "%d B" "$b"; fi
}

echo ""
echo -e "${BOLD}${M}  📁 filo${RESET}  ${DIM}session $SESSION_ID${RESET}"
[[ "$DRY_RUN" == "true" ]] && echo -e "${Y}  dry run — no files moved${RESET}"
echo ""

# Result line
if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${G}${BOLD}✓${RESET}  ${BOLD}$MOVED${RESET} moved   ${Y}${BOLD}$DUPES${RESET} duplicate   ${G}${BOLD}$ERRORS${RESET} errors"
else
  echo -e "  ${R}${BOLD}✗${RESET}  ${BOLD}$MOVED${RESET} moved   ${Y}${BOLD}$DUPES${RESET} duplicate   ${R}${BOLD}$ERRORS${RESET} errors"
fi

echo ""

# Source → destination
echo -e "  ${DIM}from${RESET}  ~/Downloads, ~/Desktop"
echo -e "  ${DIM}to${RESET}    ~/Music  ~/Movies  ~/Pictures  ~/Documents"

# Size
if [[ $BYTES_MOVED -gt 0 ]]; then
  echo -e "  ${DIM}size${RESET}  $(fmt_bytes "$BYTES_MOVED")"
fi

echo ""

# Warnings
if [[ $MISMATCHES -gt 0 ]]; then
  echo -e "  ${R}⚠  $MISMATCHES checksum mismatch(es) — run: filo inspect $SESSION_ID --view debug${RESET}"
fi
if [[ $ERRORS -gt 0 ]]; then
  echo -e "  ${R}⚠  $ERRORS error(s) — run: filo inspect $SESSION_ID --view debug${RESET}"
fi

# Footer
echo -e "  ${DIM}──────────────────────────────────────────${RESET}"
echo -e "  ${DIM}undo:    ${RESET}${C}filo rollback${RESET}"
echo -e "  ${DIM}details: ${RESET}${C}filo inspect $SESSION_ID${RESET}"
echo ""
