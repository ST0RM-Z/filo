#!/bin/bash
# ── Debug View ────────────────────────────────────────────
# Full diagnostic — every file, checksum pairs, errors, warnings

SESSION_ID=$1  DRY_RUN=$2
SCAN=$3        MOVED=$4    DUPES=$5     ERRORS=$6
VERIFIED=$7    MISMATCHES=$8
BYTES_MOVED=$9 ELAPSED=${10} TOTAL_BYTES=${11}
SESSION_FILE=${12} DEST_BASE=${13}

G='\033[0;32m' R='\033[0;31m' Y='\033[1;33m'
B='\033[0;34m' C='\033[0;36m' M='\033[0;35m'
BOLD='\033[1m' DIM='\033[2m'  RESET='\033[0m'

shorten() { echo "${1/#$HOME/~}"; }

fmt_bytes() {
  local b=$1
  if   [[ $b -ge 1048576 ]]; then printf "%.1f MB" "$(echo "$b" | awk '{printf "%.1f", $1/1048576}')";
  elif [[ $b -ge 1024 ]];    then printf "%.1f KB" "$(echo "$b" | awk '{printf "%.1f", $1/1024}')";
  else printf "%d B" "$b"; fi
}

echo ""
echo -e "${BOLD}${M}  📁 filo${RESET}  ${DIM}debug view · session $SESSION_ID${RESET}"
[[ "$DRY_RUN" == "true" ]] && echo -e "${Y}  dry run — no files moved${RESET}"
echo ""

if [[ ! -f "$SESSION_FILE" ]]; then
  echo -e "${R}  Session file not found: $SESSION_FILE${RESET}"; exit 1
fi

# ── Event log ─────────────────────────────────────────────
echo -e "  ${BOLD}Event Log${RESET}"
echo -e "  ${DIM}──────────────────────────────────────────────────────────────${RESET}"

while IFS= read -r line; do
  ev=$(echo "$line" | grep -o '"e":"[^"]*"' | cut -d'"' -f4)
  ts=$(echo "$line" | grep -o '"ts":"[^"]*"' | cut -d'"' -f4 | cut -c12-19)

  case "$ev" in
    PHASE)
      name=$(echo "$line" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | tr '[:lower:]' '[:upper:]')
      echo -e "\n  ${BOLD}${B}── $name ──────────────────────────────────────${RESET}"
      ;;

    MOVE)
      src=$(echo "$line"  | grep -o '"src":"[^"]*"'         | cut -d'"' -f4)
      dst=$(echo "$line"  | grep -o '"dst":"[^"]*"'         | cut -d'"' -f4)
      sc=$(echo "$line"   | grep -o '"src_checksum":"[^"]*"'| cut -d'"' -f4 | cut -c1-8)
      dc=$(echo "$line"   | grep -o '"dst_checksum":"[^"]*"'| cut -d'"' -f4 | cut -c1-8)
      st=$(echo "$line"   | grep -o '"status":"[^"]*"'      | cut -d'"' -f4)
      sz=$(echo "$line"   | grep -o '"size":"[^"]*"'        | cut -d'"' -f4)
      el=$(echo "$line"   | grep -o '"elapsed_ms":"[^"]*"'  | cut -d'"' -f4)
      fn=$(basename "$src")

      if [[ "$st" == "ok" || "$st" == "dry_run" ]]; then
        printf "  ${G}[MOVE]${RESET}    ${BOLD}%-35s${RESET}\n" "$fn"
      else
        printf "  ${Y}[MOVE]${RESET}    ${BOLD}%-35s${RESET}  ${R}⚠ $st${RESET}\n" "$fn"
      fi
      printf "  ${DIM}          src: %-45s  cs: %s${RESET}\n" "$(shorten "$src")" "$sc"
      printf "  ${DIM}          dst: %-45s  cs: %s${RESET}\n" "$(shorten "$dst")" "$dc"
      [[ -n "$sz" && -n "$el" ]] && printf "  ${DIM}          size: %-10s  time: %sms${RESET}\n" "$(fmt_bytes "$sz")" "$el"
      if [[ "$sc" != "$dc" && -n "$sc" && -n "$dc" ]]; then
        echo -e "  ${R}          ✗ checksum mismatch  src=$sc  dst=$dc${RESET}"
      fi
      ;;

    DUPLICATE)
      src=$(echo "$line"  | grep -o '"src":"[^"]*"'         | cut -d'"' -f4)
      dst=$(echo "$line"  | grep -o '"dst":"[^"]*"'         | cut -d'"' -f4)
      sc=$(echo "$line"   | grep -o '"src_checksum":"[^"]*"'| cut -d'"' -f4 | cut -c1-8)
      dc=$(echo "$line"   | grep -o '"dst_checksum":"[^"]*"'| cut -d'"' -f4 | cut -c1-8)
      fn=$(basename "$src")
      printf "  ${Y}[DUPE]${RESET}    ${BOLD}%-35s${RESET}  → Duplicates/\n" "$fn"
      printf "  ${DIM}          src: $(shorten "$src")${RESET}\n"
      printf "  ${DIM}          dst: $(shorten "$dst")${RESET}\n"
      [[ "$sc" != "$dc" && -n "$sc" && -n "$dc" ]] \
        && echo -e "  ${R}          ✗ checksum mismatch  src=$sc  dst=$dc${RESET}"
      ;;

    ERROR)
      src=$(echo "$line"    | grep -o '"src":"[^"]*"'    | cut -d'"' -f4)
      reason=$(echo "$line" | grep -o '"reason":"[^"]*"' | cut -d'"' -f4)
      fn=$(basename "$src")
      printf "  ${R}[ERROR]${RESET}   ${BOLD}%-35s${RESET}\n" "$fn"
      printf "  ${DIM}          src:    $(shorten "$src")${RESET}\n"
      printf "  ${R}          reason: $reason${RESET}\n"
      ;;

    VERIFY_FAIL)
      dst=$(echo "$line"  | grep -o '"dst":"[^"]*"'      | cut -d'"' -f4)
      exp=$(echo "$line"  | grep -o '"expected":"[^"]*"' | cut -d'"' -f4 | cut -c1-8)
      act=$(echo "$line"  | grep -o '"actual":"[^"]*"'   | cut -d'"' -f4 | cut -c1-8)
      fn=$(basename "$dst")
      printf "  ${R}[VERIFY]${RESET}  ${BOLD}%-35s${RESET}  ${R}✗ checksum mismatch${RESET}\n" "$fn"
      printf "  ${DIM}          expected: %s  actual: %s${RESET}\n" "$exp" "$act"
      printf "  ${DIM}          dst: $(shorten "$dst")${RESET}\n"
      ;;

    VERIFY_MISSING)
      dst=$(echo "$line" | grep -o '"dst":"[^"]*"' | cut -d'"' -f4)
      fn=$(basename "$dst")
      printf "  ${R}[MISSING]${RESET} ${BOLD}%-35s${RESET}  ${R}✗ not found at destination${RESET}\n" "$fn"
      ;;

    ALGO)
      strategy=$(echo "$line" | grep -o '"strategy":"[^"]*"' | cut -d'"' -f4)
      ext_ms=$(echo "$line"   | grep -o '"ext_ms":"[^"]*"'   | cut -d'"' -f4)
      pat_ms=$(echo "$line"   | grep -o '"pattern_ms":"[^"]*"'| cut -d'"' -f4)
      mime_ms=$(echo "$line"  | grep -o '"mime_ms":"[^"]*"'  | cut -d'"' -f4)
      echo -e "\n  ${BOLD}${B}── ALGORITHM ──────────────────────────────────${RESET}"
      printf "  ${DIM}  Extension Hash: %sms  Name Pattern: %sms  MIME: %sms${RESET}\n" \
        "$ext_ms" "$pat_ms" "$mime_ms"
      echo -e "  ${G}  Selected: $strategy${RESET}"
      ;;

    SESSION_END)
      echo ""
      echo -e "  ${BOLD}${B}── SUMMARY ──────────────────────────────────────${RESET}"
      sc2=$(echo "$line"  | grep -o '"scan":"[^"]*"'       | cut -d'"' -f4)
      mv2=$(echo "$line"  | grep -o '"moved":"[^"]*"'      | cut -d'"' -f4)
      du2=$(echo "$line"  | grep -o '"duplicates":"[^"]*"' | cut -d'"' -f4)
      er2=$(echo "$line"  | grep -o '"errors":"[^"]*"'     | cut -d'"' -f4)
      vr2=$(echo "$line"  | grep -o '"verified":"[^"]*"'   | cut -d'"' -f4)
      mm2=$(echo "$line"  | grep -o '"mismatches":"[^"]*"' | cut -d'"' -f4)
      total=$(( ${mv2:-0} + ${du2:-0} + ${er2:-0} ))
      printf "  %-24s  %s / %s\n" "Accounted for:" "$total" "${sc2:-0}"
      printf "  ${G}%-24s  %s${RESET}\n"  "Moved:"     "${mv2:-0}"
      printf "  ${Y}%-24s  %s${RESET}\n"  "Duplicates:" "${du2:-0}"
      printf "  ${R}%-24s  %s${RESET}\n"  "Errors:"     "${er2:-0}"
      printf "  ${B}%-24s  %s${RESET}\n"  "Verified:"   "${vr2:-0}"
      [[ "${mm2:-0}" -gt 0 ]] && printf "  ${R}%-24s  %s${RESET}\n" "Checksum mismatches:" "${mm2:-0}"
      ;;
  esac
done < "$SESSION_FILE"

echo ""
echo -e "  ${DIM}session log: ~/.filo/sessions/${SESSION_ID}.jsonl${RESET}"
echo ""
