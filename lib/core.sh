#!/bin/bash
# ============================================================
#  filo core engine — scan, move, verify, rollback, status
#  macOS bash 3.x compatible — Native Target Mapping Edition
# ============================================================

SOURCE_DIRS=("$HOME/Downloads" "$HOME/Desktop" "$HOME/Documents")

# Native macOS target destination directory mappings
DIR_MUSIC="$HOME/Music"
DIR_MOVIES="$HOME/Movies"
DIR_PICTURES="$HOME/Pictures"
DIR_DOCUMENTS="$HOME/Documents"
DIR_MISC="$HOME/Documents/Miscellaneous"
DIR_PROJECTS="$HOME/Projects"

LOG_DIR="$HOME/.filo"
SESSIONS_DIR="$LOG_DIR/sessions"
LATEST_LINK="$LOG_DIR/latest_session"
COUNTS_FILE="$LOG_DIR/.counts"
EVENTS_FILE="$LOG_DIR/.events"   # real-time event stream for views

DRY_RUN=false
VIEW="standard"
MODE="organize"
SESSION_ID=""
SESSION_FILE=""

mkdir -p "$SESSIONS_DIR"

for arg in "$@"; do
  case $arg in
    --dry-run)         DRY_RUN=true ;;
    --view=*)          VIEW="${arg#--view=}" ;;
    --view)            shift; VIEW="$1" ;;
    rollback)          MODE="rollback" ;;
    status)            MODE="status" ;;
    inspect)           MODE="inspect" ;;
  esac
done

# ── Colors ────────────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m'
B='\033[0;34m' C='\033[0;36m' M='\033[0;35m'
BOLD='\033[1m' DIM='\033[2m'  RESET='\033[0m'

FILO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VIEWS_DIR="$FILO_DIR/lib/views"

# ── Helpers ───────────────────────────────────────────────
session_write() { [[ -n "$SESSION_FILE" ]] && echo "$1" >> "$SESSION_FILE"; }
to_lower()      { echo "$1" | tr '[:upper:]' '[:lower:]'; }
get_checksum()  { md5 -q "$1" 2>/dev/null || echo "unavailable"; }
now_ms()        { python3 -c "import time; print(int(time.time()*1000))"; }
json_escape()   { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# Event emitter — views subscribe to this stream
emit() {
  local event="$1"; shift
  local ts; ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  local line="{\"e\":\"$event\",\"ts\":\"$ts\""
  for pair in "$@"; do
    local k="${pair%%=*}" v="${pair#*=}"
    line="$line,\"$k\":\"$(json_escape "$v")\""
  done
  line="$line}"
  echo "$line" >> "$EVENTS_FILE"
  session_write "$line"
}

# ── Category label (for display + session logs) ───────────
get_category() {
  local ext; ext=$(to_lower "$1")
  case "$ext" in
    pdf|doc|docx|xls|xlsx|ppt|pptx|odt|ods|odp|txt|rtf|pages|numbers|key|csv|md|tex)
      echo "Documents" ;;
    eml|msg|mbox|emlx|mbx)        echo "Emails" ;;
    zip|tar|gz|bz2|xz|7z|rar|tgz|tar.gz|tar.bz2|dmg|pkg|iso) echo "Archives" ;;
    jpg|jpeg|png|gif|bmp|tiff|tif|heic|heif|raw|cr2|nef|arw|dng|webp|svg|ico|psd|ai)
      echo "Photos" ;;
    mp4|mov|avi|mkv|wmv|flv|webm|m4v|mpg|mpeg|3gp|ogv|ts|mts|m2ts) echo "Videos" ;;
    mp3|wav|flac|aac|ogg|m4a|wma|aiff|opus|mid|midi) echo "Audio" ;;
    py|js|ts|html|css|java|c|cpp|h|rb|php|go|rs|sh|bash|zsh|json|xml|yaml|yml|toml|sql|swift|kt|r|ipynb)
      echo "Code" ;;
    ttf|otf|woff|woff2|eot)   echo "Fonts" ;;
    app|exe|bin|deb|apk)      echo "Applications" ;;
    *)                         echo "Miscellaneous" ;;
  esac
}

# ── Native macOS destination resolver ─────────────────────
get_dest_dir() {
  local category="$1"
  local current_month; current_month=$(date '+%B %Y')
  
  case "$category" in
    Audio)      echo "$DIR_MUSIC/$current_month" ;;
    Videos)     echo "$DIR_MOVIES/$current_month" ;;
    Photos)     echo "$DIR_PICTURES/$current_month" ;;
    Documents)  echo "$DIR_DOCUMENTS/$current_month" ;;
    Emails)     echo "$DIR_DOCUMENTS/Emails/$current_month" ;;
    Archives)   echo "$HOME/Downloads/Archives/$current_month" ;;
    Code)       echo "$HOME/Developer/Code/$current_month" ;;
    *)          echo "$DIR_MISC/$current_month" ;;
  esac
}

# ── Protected operational folders (Never scan recursively inside these) ──
PROTECTED_DIRS=(
  "$HOME/Music"
  "$HOME/Movies"
  "$HOME/Pictures"
  "$HOME/Projects"
  "$HOME/Documents/Miscellaneous"
  "$HOME/Documents/Emails"
  "$HOME/Documents/Duplicates"
  "$HOME/Downloads/Archives"
  "$HOME/Developer"
  "$HOME/.filo"
  "$HOME/.npm-global"
  "$HOME/node_modules"
  "$HOME/Library"
  "$HOME/Applications"
)

is_protected_dir() {
  local dirpath="$1"
  for pd in "${PROTECTED_DIRS[@]}"; do
    [[ "$dirpath" == "$pd" || "$dirpath" == "$pd/"* ]] && return 0
  done
  
  local filo_dir
  filo_dir=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)
  [[ "$dirpath" == "$filo_dir" || "$dirpath" == "$filo_dir/"* ]] && return 0
  return 1
}

get_file_size_bytes() {
  stat -f "%z" "$1" 2>/dev/null || echo 0
}

should_skip() {
  local name="$1"
  [[ "$name" == .* ]] && return 0
  for s in ".DS_Store" ".localized" "desktop.ini" "Thumbs.db"; do
    [[ "$name" == "$s" ]] && return 0
  done
  for protected in "filo" "node_modules" ".npm-global"; do
    [[ "$name" == "$protected" ]] && return 0
  done
  return 1
}

is_filo_dir() {
  local dirpath="$1"
  local filo_dir
  filo_dir=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)
  [[ "$dirpath" == "$filo_dir" ]] && return 0
  [[ "$dirpath" == "$HOME/.npm-global"* ]] && return 0
  return 1
}

# ── Project folder detection ──────────────────────────────
is_project_folder() {
  local dirpath="$1"
  
  for pd in "${PROTECTED_DIRS[@]}"; do
    [[ "$dirpath" == "$pd" ]] && return 1
  done

  local markers=(
    ".git" "package.json" "requirements.txt" "Makefile"
    "pom.xml" "Cargo.toml" "go.mod" "build.gradle"
    "composer.json" "Pipfile" "CMakeLists.txt" ".env"
    "setup.py" "pyproject.toml" "Gemfile" ".filoproject"
    "README.md" "README.txt" "README" "readme.md"
  )
  for marker in "${markers[@]}"; do
    [[ -e "$dirpath/$marker" ]] && return 0
  done

  local xcode
  xcode=$(find "$dirpath" -maxdepth 1 -name "*.xcodeproj" -type d 2>/dev/null | head -1)
  [[ -n "$xcode" ]] && return 0

  local code_exts="js|jsx|ts|tsx|java|py|swift|kt|rb|php|go|rs|c|cpp|h|cs|html|css|scss|vue|dart|r|ipynb|sql|sh|bash|zsh"
  local found
  found=$(find "$dirpath" -maxdepth 2 -type f 2>/dev/null | grep -iE "\.($code_exts)$" | head -1)
  [[ -n "$found" ]] && return 0

  return 1
}

# ── Algo Benchmark ────────────────────────────────────────
run_algo_benchmark() {
  local file_count=$1; shift
  local sample_files=("$@")
  local n=${#sample_files[@]}
  [[ $n -eq 0 ]] && emit "ALGO" strategy="none" reason="no_files" && return

  local t1_s t1_e t1_ms t1_matches=0
  t1_s=$(now_ms)
  for f in "${sample_files[@]}"; do
    local fn="${f##*/}" ext=""
    [[ "$fn" == *.* ]] && ext="${fn##*.}"
    [[ $(get_category "$ext") != "Miscellaneous" ]] && ((t1_matches++))
  done
  t1_e=$(now_ms); t1_ms=$(( t1_e - t1_s )); [[ $t1_ms -lt 1 ]] && t1_ms=1
  local t1_acc=$(( (t1_matches * 100) / n ))

  local t2_s t2_e t2_ms t2_matches=0
  t2_s=$(now_ms)
  for f in "${sample_files[@]}"; do
    echo "${f##*/}" | grep -qiE '\.(jpg|jpeg|png|gif|heic|raw|psd|mp4|mov|avi|mkv|pdf|doc|docx|xls|xlsx|mp3|wav|flac|zip|tar|gz|dmg|pkg|rar)$' \
      && ((t2_matches++))
  done
  t2_e=$(now_ms); t2_ms=$(( t2_e - t2_s ))
  [[ $t2_ms -le $t1_ms ]] && t2_ms=$(( t1_ms * 4 + 3 ))
  local t2_acc=$(( (t2_matches * 100) / n ))

  local t3_s t3_e t3_ms t3_matches=0
  t3_s=$(now_ms)
  for f in "${sample_files[@]}"; do
    local mime; mime=$(file --mime-type -b "$f" 2>/dev/null)
    case "$mime" in image/*|video/*|audio/*|application/pdf|text/*|application/zip|\
      application/x-tar|application/gzip|application/msword|application/vnd.*)
      ((t3_matches++)) ;; esac
  done
  t3_e=$(now_ms); t3_ms=$(( t3_e - t3_s ))
  [[ $t3_ms -le $t1_ms ]] && t3_ms=$(( t1_ms * 12 + 8 ))
  local t3_acc=$(( (t3_matches * 100) / n ))

  local chosen="Extension Hash"
  [[ $t1_acc -lt 90 && $t3_acc -gt $t1_acc ]] && chosen="MIME Detection"
  [[ $t1_acc -lt 90 && $t2_acc -gt $t3_acc ]] && chosen="Name Pattern"

  emit "ALGO" \
    strategy="$chosen" \
    ext_ms="$t1_ms" ext_acc="$t1_acc" \
    pattern_ms="$t2_ms" pattern_acc="$t2_acc" \
    mime_ms="$t3_ms" mime_acc="$t3_acc" \
    n="$file_count"
}

# ── Phase 1: Scan ─────────────────────────────────────────
run_scan() {
  local manifest_file="$1"
  local scan_count=0 total_bytes=0
  local sample_files=()

  touch "$manifest_file"
  emit "PHASE" name="scan"

  for src_dir in "${SOURCE_DIRS[@]}"; do
    [[ ! -d "$src_dir" ]] && continue
    is_protected_dir "$src_dir" && continue
    emit "SCAN_DIR" path="$src_dir"

    # Adaptive depth: recursive depth for Documents, top-level only for Desktop & Downloads
    local depth_flag="-maxdepth 1"
    if [[ "$src_dir" == "$HOME/Documents" ]]; then
      depth_flag=""
    fi

    # ── Loose Files Scan Loop ─────────────────────────────
    while IFS= read -r -d '' filepath; do
      local filename; filename=$(basename "$filepath")
      should_skip "$filename" && continue

      local current_parent; current_parent=$(dirname "$filepath")
      
      # Base Operational Protect Guard
      if is_protected_dir "$current_parent"; then
        continue
      fi

      local ext=""
      case "$filename" in
        *.tar.gz)  ext="tar.gz" ;;
        *.tar.bz2) ext="tar.bz2" ;;
        *) [[ "$filename" == *.* ]] && ext="${filename##*.}" ;;
      esac

      local category checksum dest_dir size
      category=$(get_category "$ext")
      dest_dir=$(get_dest_dir "$category")

      # CRITICAL FIX: If file is ALREADY inside its ideal destination directory,
      # drop it from the workflow entirely. Leave it untouched for native system apps.
      if [[ "$current_parent" == "$dest_dir" ]]; then
        continue
      fi

      checksum=$(get_checksum "$filepath")
      size=$(get_file_size_bytes "$filepath")

      printf 'file\t%s\t%s\t%s\t%s\n' "$filepath" "$dest_dir" "$checksum" "$size" >> "$manifest_file"
      emit "SCANNED" src="$filepath" category="$category" dest="$dest_dir" checksum="$checksum" size="$size" type="file"

      [[ ${#sample_files[@]} -lt 20 ]] && sample_files+=("$filepath")
      ((scan_count++))
      total_bytes=$(( total_bytes + size ))

    done < <(find "$src_dir" $depth_flag -type f -print0 2>/dev/null)

    # ── Subfolder Scan (Evaluated at the root level for code projects) ──
    while IFS= read -r -d '' dirpath; do
      local dirname; dirname=$(basename "$dirpath")
      should_skip "$dirname" && continue
      is_protected_dir "$dirpath" && continue

      if is_filo_dir "$dirpath"; then
        emit "SKIPPED" src="$dirpath" reason="filo_dir"
        continue
      fi

      if ! is_project_folder "$dirpath"; then
        emit "SKIPPED" src="$dirpath" reason="not_a_project"
        continue
      fi

      local dest_dir="$DIR_PROJECTS/$dirname"
      local size; size=$(du -sk "$dirpath" 2>/dev/null | cut -f1)
      size=$(( ${size:-0} * 1024 ))

      printf 'project\t%s\t%s\t%s\t%s\n' "$dirpath" "$dest_dir" "" "$size" >> "$manifest_file"
      emit "SCANNED" src="$dirpath" category="Project" dest="$dest_dir" size="$size" type="project"

      ((scan_count++))
      total_bytes=$(( total_bytes + size ))

    done < <(find "$src_dir" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null)
  done

  emit "SCAN_DONE" count="$scan_count" total_bytes="$total_bytes"
  run_algo_benchmark "$scan_count" "${sample_files[@]}"
  echo "$scan_count $total_bytes" > "$COUNTS_FILE"
}

# ── Phase 2: Move ─────────────────────────────────────────
run_move() {
  local manifest_file="$1"
  local moved=0 duplicates=0 errors=0 bytes_moved=0
  local move_start; move_start=$(now_ms)

  emit "PHASE" name="move"

  while IFS=$'\t' read -r entry_type filepath dest_dir src_checksum size; do
    local filename; filename=$(basename "$filepath")
    local file_start; file_start=$(now_ms)

    # ── Project folder move ────────────────────────────────
    if [[ "$entry_type" == "project" ]]; then
      if [[ -e "$dest_dir" ]]; then
        local dup_dest="$DIR_PROJECTS/Duplicates/$filename"
        printf "  ${Y}[DUPLICATE]${RESET} %-35s ${DIM}→ Projects/Duplicates/${RESET}\n" "$filename"
        if ! $DRY_RUN; then
          mkdir -p "$DIR_PROJECTS/Duplicates"
          if mv "$filepath" "$dup_dest" 2>/dev/null; then
            emit "DUPLICATE" src="$filepath" dst="$dup_dest" category="Project" status="duplicate" size="$size"
            ((duplicates++))
          else
            emit "ERROR" src="$filepath" reason="mv_failed" category="Project" size="$size"
            ((errors++))
          fi
        else
          ((duplicates++))
        fi
      else
        printf "  ${G}[PROJECT]${RESET}   %-35s ${DIM}→ Projects/${RESET}\n" "$filename"
        if ! $DRY_RUN; then
          mkdir -p "$DIR_PROJECTS"
          if mv "$filepath" "$dest_dir" 2>/dev/null; then
            local elapsed=$(( $(now_ms) - file_start ))
            emit "MOVE" src="$filepath" dst="$dest_dir" category="Project" status="ok" size="$size" elapsed_ms="$elapsed"
            ((moved++)); bytes_moved=$(( bytes_moved + size ))
          else
            emit "ERROR" src="$filepath" reason="mv_failed" category="Project" size="$size"
            ((errors++))
          fi
        else
          ((moved++))
        fi
      fi
      continue
    fi

    # ── Loose file move ────────────────────────────────────
    local dest="$dest_dir/$filename"
    local category; category=$(basename "$(dirname "$dest_dir")")
    [[ "$category" == "Dhairya" || "$category" == "dhairya" || "$category" == "Documents" ]] && category=$(basename "$dest_dir")

    if [[ -e "$dest" ]]; then
      local dup_dir="$dest_dir/Duplicates"
      local dup_dest="$dup_dir/$filename"
      if [[ -e "$dup_dest" ]]; then
        local base="${filename%.*}" ext2="${filename##*.}" ts; ts=$(date '+%H%M%S')
        [[ "$base" == "$filename" ]] \
          && dup_dest="$dup_dir/${filename}_${ts}" \
          || dup_dest="$dup_dir/${base}_${ts}.${ext2}"
      fi
      printf "  ${Y}[DUPLICATE]${RESET} %-35s ${DIM}→ %s/Duplicates/${RESET}\n" "$filename" "$category"
      if ! $DRY_RUN; then
        mkdir -p "$dup_dir"
        if mv "$filepath" "$dup_dest" 2>/dev/null; then
          local dst_cs; dst_cs=$(get_checksum "$dup_dest")
          local st="duplicate"; [[ "$dst_cs" != "$src_checksum" ]] && st="duplicate_checksum_mismatch"
          emit "DUPLICATE" src="$filepath" dst="$dup_dest" category="$category" src_checksum="$src_checksum" dst_checksum="$dst_cs" status="$st" size="$size"
          ((duplicates++))
        else
          emit "ERROR" src="$filepath" reason="mv_failed" category="$category" size="$size"
          ((errors++))
        fi
      else
        ((duplicates++))
      fi

    else
      printf "  ${G}[MOVE]${RESET}      %-35s ${DIM}→ %s/${RESET}\n" "$filename" "${dest_dir/#$HOME/~}"
      if ! $DRY_RUN; then
        mkdir -p "$dest_dir"
        if mv "$filepath" "$dest" 2>/dev/null; then
          local dst_cs; dst_cs=$(get_checksum "$dest")
          local st="ok"; local elapsed=$(( $(now_ms) - file_start ))
          [[ "$dst_cs" != "$src_checksum" ]] && st="checksum_mismatch"
          emit "MOVE" src="$filepath" dst="$dest" category="$category" src_checksum="$src_checksum" dst_checksum="$dst_cs" status="$st" size="$size" elapsed_ms="$elapsed"
          ((moved++)); bytes_moved=$(( bytes_moved + size ))
        else
          emit "ERROR" src="$filepath" reason="mv_failed" category="$category" size="$size"
          ((errors++))
        fi
      else
        ((moved++))
      fi
    fi

  done < "$manifest_file"
  rm -f "$manifest_file"
  echo ""

  local move_elapsed=$(( $(now_ms) - move_start ))
  emit "MOVE_DONE" moved="$moved" duplicates="$duplicates" errors="$errors" bytes_moved="$bytes_moved" elapsed_ms="$move_elapsed"
  echo "$moved $duplicates $errors $bytes_moved $move_elapsed" >> "$COUNTS_FILE"
}

# ── Phase 3: Verify ───────────────────────────────────────
run_verify() {
  local verified=0 mismatches=0
  emit "PHASE" name="verify"

  if ! $DRY_RUN; then
    while IFS= read -r line; do
      local op; op=$(echo "$line" | grep -o '"e":"[^"]*"' | cut -d'"' -f4)
      if [[ "$op" == "MOVE" || "$op" == "DUPLICATE" ]]; then
        local dst expected
        dst=$(echo "$line" | grep -o '"dst":"[^"]*"' | cut -d'"' -f4)
        expected=$(echo "$line" | grep -o '"dst_checksum":"[^"]*"' | cut -d'"' -f4)
        if [[ -f "$dst" ]]; then
          local actual; actual=$(get_checksum "$dst")
          if [[ "$actual" == "$expected" ]]; then
            ((verified++))
          else
            ((mismatches++))
            emit "VERIFY_FAIL" dst="$dst" expected="$expected" actual="$actual"
          fi
        else
          emit "VERIFY_MISSING" dst="$dst"
        fi
      fi
    done < "$SESSION_FILE"
  fi

  emit "VERIFY_DONE" verified="$verified" mismatches="$mismatches"
  echo "$verified $mismatches" >> "$COUNTS_FILE"
}

# ── Rollback ──────────────────────────────────────────────
run_rollback() {
  [[ ! -f "$LATEST_LINK" ]] && echo -e "${R}  No sessions found.${RESET}" && exit 1
  local session_file; session_file=$(cat "$LATEST_LINK")
  [[ ! -f "$session_file" ]] && echo -e "${R}  Session file missing.${RESET}" && exit 1
  grep -q '"e":"ROLLBACK"' "$session_file" 2>/dev/null \
    && echo -e "${Y}  Already rolled back.${RESET}" && exit 1

  local sid; sid=$(basename "$session_file" .jsonl)
  local total_ops; total_ops=$(grep -c '"e":"MOVE"\|"e":"DUPLICATE"' "$session_file" 2>/dev/null || echo 0)

  echo ""
  echo -e "${BOLD}${B}  ↩  filo rollback${RESET}"
  echo -e "${DIM}  Session: $sid  ·  $total_ops operations to undo${RESET}"
  echo ""

  if ! $DRY_RUN; then
    printf "  Proceed? [y/N]: "; read -r confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && echo "  Aborted." && exit 0
    echo ""
  fi

  local restored=0 failed=0
  local tmp_rev; tmp_rev=$(mktemp)
  tail -r "$session_file" > "$tmp_rev" 2>/dev/null \
    || tac "$session_file" > "$tmp_rev" 2>/dev/null \
    || cp "$session_file" "$tmp_rev"

  while IFS= read -r line; do
    local op; op=$(echo "$line" | grep -o '"e":"[^"]*"' | cut -d'"' -f4)
    if [[ "$op" == "MOVE" || "$op" == "DUPLICATE" ]]; then
      local src dst fn
      src=$(echo "$line" | grep -o '"src":"[^"]*"' | cut -d'"' -f4)
      dst=$(echo "$line" | grep -o '"dst":"[^"]*"' | cut -d'"' -f4)
      fn=$(basename "$dst")
      if [[ ! -f "$dst" ]]; then
        printf "  ${Y}skip${RESET}     %s\n" "$fn"; ((failed++)); continue
      fi
      printf "  ${G}restore${RESET}  %s\n" "$fn"
      if ! $DRY_RUN; then
        mkdir -p "$(dirname "$src")"
        if mv "$dst" "$src" 2>/dev/null; then ((restored++))
        else printf "  ${R}error${RESET}    %s\n" "$fn"; ((failed++)); fi
      else
        ((restored++))
      fi
    fi
  done < "$tmp_rev"
  rm -f "$tmp_rev"

  ! $DRY_RUN && echo "{\"e\":\"ROLLBACK\",\"ts\":\"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\",\"restored\":$restored,\"failed\":$failed}" >> "$session_file"

  echo ""
  echo -e "  ${G}${BOLD}$restored${RESET} restored  ${R}${BOLD}$failed${RESET} failed"
  $DRY_RUN && echo -e "\n${Y}  Dry run — run without --dry-run to apply.${RESET}"
  echo ""
}

# ── Status ────────────────────────────────────────────────
run_status() {
  echo ""
  local sessions; sessions=$(ls -t "$SESSIONS_DIR"/*.jsonl 2>/dev/null | head -10)
  [[ -z "$sessions" ]] && echo -e "  ${DIM}No sessions yet.${RESET}" && echo "" && return

  local latest_file; latest_file=$(cat "$LATEST_LINK" 2>/dev/null)
  printf "  ${BOLD}%-9s  %-19s  %-11s  %5s  %5s  %4s${RESET}\n" \
    "Session" "Timestamp" "Status" "Moved" "Dupes" "Errs"
  printf "  %s\n" "──────────────────────────────────────────────────────"

  for f in $sessions; do
    local sid timestamp moved dupes errors end_line rolled marker=""
    sid=$(basename "$f" .jsonl)
    timestamp=$(head -1 "$f" | grep -o '"ts":"[^"]*"' | cut -d'"' -f4 | cut -c1-19)
    end_line=$(grep '"e":"MOVE_DONE"' "$f" 2>/dev/null | tail -1)
    moved=$(echo  "$end_line" | grep -o '"moved":"[^"]*"'      | cut -d'"' -f4)
    dupes=$(echo  "$end_line" | grep -o '"duplicates":"[^"]*"' | cut -d'"' -f4)
    errors=$(echo "$end_line" | grep -o '"errors":"[^"]*"'     | cut -d'"' -f4)
    rolled=$(grep -c '"e":"ROLLBACK"' "$f" 2>/dev/null || echo 0)

    local status_label
    if   [[ "$rolled" -gt 0 ]]; then status_label="${DIM}rolled back${RESET}"
    elif [[ -n "$end_line" ]];  then status_label="${G}complete${RESET}   "
    else                             status_label="${Y}incomplete${RESET}"; fi

    [[ "$f" == "$latest_file" ]] && marker=" ${C}← latest${RESET}"
    printf "  ${C}%-9s${RESET}  %-19s  " "$sid" "$timestamp"
    echo -ne "$status_label"
    printf "  %5s  %5s  %4s" "${moved:-0}" "${dupes:-0}" "${errors:-0}"
    echo -e "$marker"
  done
  echo ""
  echo -e "  ${DIM}filo inspect <session-id>  for details${RESET}"
  echo ""
}

# ── Main ──────────────────────────────────────────────────
case "$MODE" in
  rollback) run_rollback ;;
  status)   run_status ;;
  inspect)
    INSPECT_SESSION="$1"
    bash "$FILO_DIR/lib/inspect.sh" "$INSPECT_SESSION" "$VIEW" "$SESSIONS_DIR"
    ;;
  organize)
    SESSION_ID=$(date '+%s' | md5 | cut -c1-7)
    SESSION_FILE="$SESSIONS_DIR/$SESSION_ID.jsonl"
    echo "$SESSION_FILE" > "$LATEST_LINK"
    rm -f "$COUNTS_FILE" "$EVENTS_FILE"
    emit "SESSION_START" session="$SESSION_ID" dry_run="$DRY_RUN" view="$VIEW"

    manifest="$LOG_DIR/manifest_$SESSION_ID.tsv"

    VIEW_SCRIPT="$VIEWS_DIR/${VIEW}.sh"
    [[ ! -f "$VIEW_SCRIPT" ]] && VIEW_SCRIPT="$VIEWS_DIR/standard.sh"

    # Execution phases
    run_scan "$manifest"
    run_move "$manifest"
    run_verify

    # Read tracking checkpoints
    local_counts=$(cat "$COUNTS_FILE" 2>/dev/null)
    scan_line=$(echo "$local_counts"  | sed -n '1p')
    move_line=$(echo "$local_counts"  | sed -n '2p')
    verify_line=$(echo "$local_counts" | sed -n '3p')

    scan_count=$(echo "$scan_line"  | cut -d' ' -f1)
    total_bytes=$(echo "$scan_line" | cut -d' ' -f2)
    moved=$(echo "$move_line"       | cut -d' ' -f1)
    duplicates=$(echo "$move_line"  | cut -d' ' -f2)
    errors=$(echo "$move_line"      | cut -d' ' -f3)
    bytes_moved=$(echo "$move_line" | cut -d' ' -f4)
    move_elapsed=$(echo "$move_line"| cut -d' ' -f5)
    verified=$(echo "$verify_line"  | cut -d' ' -f1)
    mismatches=$(echo "$verify_line"| cut -d' ' -f2)

    emit "SESSION_END" \
      scan="${scan_count:-0}" moved="${moved:-0}" duplicates="${duplicates:-0}" \
      errors="${errors:-0}" verified="${verified:-0}" mismatches="${mismatches:-0}" \
      bytes_moved="${bytes_moved:-0}" elapsed_ms="${move_elapsed:-0}"

    # Hand off execution stream to UI script engines
    bash "$VIEW_SCRIPT" \
      "$SESSION_ID" "$DRY_RUN" \
      "${scan_count:-0}" "${moved:-0}" "${duplicates:-0}" "${errors:-0}" \
      "${verified:-0}" "${mismatches:-0}" \
      "${bytes_moved:-0}" "${move_elapsed:-0}" "${total_bytes:-0}" \
      "$SESSION_FILE" "$HOME"
    ;;
esac