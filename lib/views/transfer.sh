#!/bin/bash
# ── Transfer View ─────────────────────────────────────────
# File operation stats, throughput, algo analysis

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

bar() {
  local val=$1 max=$2 width=${3:-20}
  [[ $max -eq 0 ]] && max=1
  local filled=$(( (val * width) / max ))
  local empty=$(( width - filled ))
  printf "${G}"
  printf '%0.s█' $(seq 1 $filled 2>/dev/null) 2>/dev/null
  printf "${DIM}"
  printf '%0.s░' $(seq 1 $empty 2>/dev/null) 2>/dev/null
  printf "${RESET}"
}

echo ""
echo -e "${BOLD}${M}  📁 filo${RESET}  ${DIM}transfer view · session $SESSION_ID${RESET}"
[[ "$DRY_RUN" == "true" ]] && echo -e "${Y}  dry run${RESET}"
echo ""

# ── Transfer stats ────────────────────────────────────────
echo -e "  ${BOLD}Transfer${RESET}"
echo -e "  ${DIM}──────────────────────────────────────────${RESET}"

total=$((MOVED + DUPES + ERRORS))
[[ $total -eq 0 ]] && total=1

# Per-category breakdown from session file
if [[ -f "$SESSION_FILE" ]]; then
  declare -A cat_counts cat_bytes
  while IFS= read -r line; do
    local_e=$(echo "$line" | grep -o '"e":"[^"]*"' | cut -d'"' -f4)
    if [[ "$local_e" == "MOVE" || "$local_e" == "DUPLICATE" ]]; then
      cat=$(echo "$line" | grep -o '"category":"[^"]*"' | cut -d'"' -f4)
      sz=$(echo "$line"  | grep -o '"size":"[^"]*"'     | cut -d'"' -f4)
      [[ -z "$cat" ]] && cat="Miscellaneous"
      [[ -z "$sz"  ]] && sz=0
      cat_counts[$cat]=$(( ${cat_counts[$cat]:-0} + 1 ))
      cat_bytes[$cat]=$(( ${cat_bytes[$cat]:-0} + sz ))
    fi
  done < "$SESSION_FILE"

  for cat in "${!cat_counts[@]}"; do
    local cnt=${cat_counts[$cat]}
    local bytes=${cat_bytes[$cat]}
    printf "  ${C}%-16s${RESET}  " "$cat"
    bar "$cnt" "$total" 16
    printf "  %3d files  %s\n" "$cnt" "$(fmt_bytes "$bytes")"
  done
fi

echo ""

# ── Throughput ────────────────────────────────────────────
echo -e "  ${BOLD}Throughput${RESET}"
echo -e "  ${DIM}──────────────────────────────────────────${RESET}"

elapsed_s=0
[[ $ELAPSED -gt 0 ]] && elapsed_s=$(echo "$ELAPSED" | awk '{printf "%.1f", $1/1000}')

rate_bps=0
if [[ $ELAPSED -gt 0 && $BYTES_MOVED -gt 0 ]]; then
  rate_bps=$(echo "$BYTES_MOVED $ELAPSED" | awk '{printf "%d", ($1 / $2) * 1000}')
fi

printf "  %-22s  %s\n"  "Total data moved:"    "$(fmt_bytes "$BYTES_MOVED")"
printf "  %-22s  %ss\n" "Elapsed:"              "$elapsed_s"
printf "  %-22s  %s/s\n" "Avg throughput:"      "$(fmt_bytes "$rate_bps")"
printf "  %-22s  %d / %d\n" "Files (moved/scan):" "$MOVED" "$SCAN"
printf "  %-22s  %d\n"  "Verified:"             "$VERIFIED"
[[ $MISMATCHES -gt 0 ]] && printf "  ${R}%-22s  %d${RESET}\n" "Checksum mismatches:" "$MISMATCHES"

echo ""

# ── Algo benchmark ────────────────────────────────────────
echo -e "  ${BOLD}Classification Algorithm${RESET}"
echo -e "  ${DIM}──────────────────────────────────────────${RESET}"

algo_line=$(grep '"e":"ALGO"' "$SESSION_FILE" 2>/dev/null | tail -1)
if [[ -n "$algo_line" ]]; then
  strategy=$(echo "$algo_line" | grep -o '"strategy":"[^"]*"' | cut -d'"' -f4)
  ext_ms=$(echo "$algo_line"   | grep -o '"ext_ms":"[^"]*"'   | cut -d'"' -f4)
  ext_acc=$(echo "$algo_line"  | grep -o '"ext_acc":"[^"]*"'  | cut -d'"' -f4)
  pat_ms=$(echo "$algo_line"   | grep -o '"pattern_ms":"[^"]*"' | cut -d'"' -f4)
  pat_acc=$(echo "$algo_line"  | grep -o '"pattern_acc":"[^"]*"' | cut -d'"' -f4)
  mime_ms=$(echo "$algo_line"  | grep -o '"mime_ms":"[^"]*"'  | cut -d'"' -f4)
  mime_acc=$(echo "$algo_line" | grep -o '"mime_acc":"[^"]*"' | cut -d'"' -f4)
  n=$(echo "$algo_line"        | grep -o '"n":"[^"]*"'        | cut -d'"' -f4)

  printf "  ${BOLD}%-24s  %-14s  %-6s  %s${RESET}\n" "Strategy" "Complexity" "Time" "Accuracy"
  printf "  ${DIM}%s${RESET}\n" "──────────────────────────────────────────"

  selected_marker() { [[ "$strategy" == "$1" ]] && echo -e " ${G}← selected${RESET}" || echo ""; }

  printf "  ${G}%-24s${RESET}  %-14s  %4sms  %3s%%  %s\n" \
    "Extension Hash" "O(1)" "$ext_ms" "$ext_acc" "$(selected_marker "Extension Hash")"
  printf "  ${C}%-24s${RESET}  %-14s  %4sms  %3s%%  %s\n" \
    "Name Pattern" "O(n log n)" "$pat_ms" "$pat_acc" "$(selected_marker "Name Pattern")"
  printf "  ${Y}%-24s${RESET}  %-14s  %4sms  %3s%%  %s\n" \
    "MIME Detection" "O(n)" "$mime_ms" "$mime_acc" "$(selected_marker "MIME Detection")"

  echo -e "  ${DIM}sample: $n files${RESET}"
fi

echo ""
echo -e "  ${DIM}undo: filo rollback  ·  details: filo inspect $SESSION_ID --view debug${RESET}"
echo ""
