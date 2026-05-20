#!/usr/bin/env bash
# playlist-rw.sh — Portable playlist path rewriter
#
# Supports .pls, .xml, and .db (SQLite) playlist/library files.
#
# EXPORT: Strips a user's local music path and replaces it with a neutral
#         placeholder, making the file shareable with anyone.
#
# IMPORT: Takes a placeholder file and substitutes in the new user's
#         local music path so it works on their system.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#
#   Export (preparing a file to share):
#     ./playlist-rw.sh --export -i <input> -o <output>
#
#   Import (making a shared file work locally):
#     ./playlist-rw.sh --import -i <input> -o <output>
#
# ── Examples ─────────────────────────────────────────────────────────────────
#
#   ./playlist-rw.sh --export -i playlist.pls       -o playlist_portable.pls
#   ./playlist-rw.sh --export -i playlist.xml    -o playlist_portable.xml
#   ./playlist-rw.sh --export -i playlist.db  -o playlist_portable.db
#
#   ./playlist-rw.sh --import -i playlist_portable.pls      -o playlist_local.pls
#   ./playlist-rw.sh --import -i playlist_portable.xml   -o playlist_local.xml
#   ./playlist-rw.sh --import -i playlist_portable.db -o playlist_local.db
#
# ── Notes on .db files ───────────────────────────────────────────────────────
#
#   SQLite databases are binary files; sed cannot safely modify them.
#   This script uses sqlite3 for .db files and requires it to be installed.
#   The replacement is done via SQL REPLACE() across all text columns in all
#   tables, so no knowledge of the database schema is required.
#
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# The neutral placeholder used as the portable middle state
PLACEHOLDER="__MUSIC_PATH__"

# ── Helpers ───────────────────────────────────────────────────────────────────
usage() {
  echo ""
  echo "Usage:"
  echo "  $0 --export -i <input>  -o <output>"
  echo "  $0 --import -i <input>  -o <output>"
  echo ""
  echo "Modes:"
  echo "  --export   Replace your local music path with a portable placeholder"
  echo "  --import   Replace the placeholder with your local music path"
  echo ""
  echo "Options:"
  echo "  -i   Path to the source file (.pls, .xml, or .db)"
  echo "  -o   Path to write the rewritten file"
  echo ""
  echo "Supported file types:"
  echo "  .pls  — Plain-text playlist      (uses sed)"
  echo "  .xml  — XML library/playlist     (uses sed)"
  echo "  .db   — SQLite database          (uses sqlite3)"
  echo ""
  exit 1
}

ensure_output_dir() {
  local dir
  dir="$(dirname "$1")"
  if [[ -n "$dir" && "$dir" != "." ]]; then
    mkdir -p "$dir"
  fi
}

# ── Text file rewrite (sed) ───────────────────────────────────────────────────
rewrite_text() {
  local src="$1" dst="$2" old="$3" new="$4"
  sed "s|${old}|${new}|g" "$src" > "$dst"
}

# ── SQLite rewrite ────────────────────────────────────────────────────────────
# Iterates every table and every TEXT column, running REPLACE() on each one.
# No schema knowledge required — works with any media player database.
rewrite_sqlite() {
  local src="$1" dst="$2" old="$3" new="$4"

  if ! command -v sqlite3 &>/dev/null; then
    echo "Error: sqlite3 is not installed. Install it and try again."
    echo ""
    echo "  Ubuntu / Debian Based : sudo apt install sqlite3"
    echo "  Fedora                 : sudo dnf install sqlite"
    echo "  Arch / Manjaro         : sudo pacman -S sqlite"
    echo "  openSUSE               : sudo zypper install sqlite3"
    echo "  Alpine                 : sudo apk add sqlite"
    echo "  macOS (Homebrew)       : brew install sqlite3"
    exit 1
  fi

  # Work on a copy so the original is never touched
  cp "$src" "$dst"

  # Build and run REPLACE() statements for every TEXT column in every table
  local tables
  tables=$(sqlite3 "$dst" "SELECT name FROM sqlite_master WHERE type='table';")

  local updated_cols=0

  for table in $tables; do
    # Get column names and types for this table
    while IFS='|' read -r _cid col_name col_type _rest; do
      # Target only TEXT/VARCHAR columns (case-insensitive match)
      if echo "$col_type" | grep -qiE "TEXT|CHAR|CLOB"; then
        # Only update if the old value actually appears in this column
        local count
        count=$(sqlite3 "$dst" \
          "SELECT COUNT(*) FROM \"${table}\" WHERE \"${col_name}\" LIKE '%${old}%';")
        if [[ "$count" -gt 0 ]]; then
          sqlite3 "$dst" \
            "UPDATE \"${table}\" SET \"${col_name}\" = REPLACE(\"${col_name}\", '${old}', '${new}');"
          echo "  Updated $count row(s) in ${table}.${col_name}"
          (( updated_cols++ )) || true
        fi
      fi
    done < <(sqlite3 "$dst" "PRAGMA table_info(\"${table}\");")
  done

  if [[ "$updated_cols" -eq 0 ]]; then
    echo "  Warning: No columns were updated. Check that the path is correct."
  fi
}

# ── Parse mode ────────────────────────────────────────────────────────────────
MODE=""
if [[ "${1:-}" == "--export" ]]; then
  MODE="export"; shift
elif [[ "${1:-}" == "--import" ]]; then
  MODE="import"; shift
else
  echo "Error: First argument must be --export or --import."
  usage
fi

# ── Parse flags ───────────────────────────────────────────────────────────────
INPUT=""
OUTPUT=""

while getopts ":i:o:" opt; do
  case $opt in
    i) INPUT="$OPTARG" ;;
    o) OUTPUT="$OPTARG" ;;
    *) usage ;;
  esac
done

# ── Validate ──────────────────────────────────────────────────────────────────
[[ -z "$INPUT"  ]] && { echo "Error: No input file specified (-i).";  usage; }
[[ -z "$OUTPUT" ]] && { echo "Error: No output file specified (-o)."; usage; }
[[ -f "$INPUT"  ]] || { echo "Error: Input file not found: $INPUT";   exit 1; }

ensure_output_dir "$OUTPUT"

# Detect file type
EXT="${INPUT##*.}"
EXT=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')  # lowercase (bash 3.2 compatible)

case "$EXT" in
  pls|xml) FILE_TYPE="text" ;;
  db)      FILE_TYPE="sqlite" ;;
  *)
    echo "Error: Unsupported file type '.${EXT}'."
    echo "Supported types: .pls  .xml  .db"
    exit 1
    ;;
esac

# ─────────────────────────────────────────────────────────────────────────────
# EXPORT MODE
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$MODE" == "export" ]]; then

  echo ""
  echo "=== EXPORT MODE (.$EXT) ==="
  echo "Your local music path will be replaced with: $PLACEHOLDER"
  echo ""

  # Show a sample path line to help the user identify their path
  if [[ "$FILE_TYPE" == "text" ]]; then
    SAMPLE=$(grep -m1 "file:///" "$INPUT" || true)
    if [[ -n "$SAMPLE" ]]; then
      echo "Sample entry from your file:"
      echo "  $SAMPLE"
      echo ""
    fi
  elif [[ "$FILE_TYPE" == "sqlite" ]]; then
    echo "Note: All text columns across all tables will be scanned."
    echo ""
  fi

  read -rp "Enter your current music path to replace (e.g. /home/user/Music): " OLD_PATH
  OLD_PATH="${OLD_PATH%/}"  # strip trailing slash

  if [[ -z "$OLD_PATH" ]]; then
    echo "Error: No path entered. Aborting."
    exit 1
  fi

  # Warn if the path isn't found
  PATH_FOUND=false
  if [[ "$FILE_TYPE" == "text" ]] && grep -q "$OLD_PATH" "$INPUT"; then
    PATH_FOUND=true
  elif [[ "$FILE_TYPE" == "sqlite" ]] && \
       sqlite3 "$INPUT" "SELECT COUNT(*) FROM (SELECT name FROM sqlite_master WHERE type='table') t;" &>/dev/null; then
    # Quick check — just attempt the rewrite and let the per-column logic warn if nothing matched
    PATH_FOUND=true
  fi

  if [[ "$PATH_FOUND" == false ]]; then
    echo "Warning: '$OLD_PATH' was not found in $INPUT."
    read -rp "Continue anyway? [y/N]: " CONFIRM
    [[ "$(echo "$CONFIRM" | tr '[:upper:]' '[:lower:]')" == "y" ]] || { echo "Aborted."; exit 1; }
  fi

  echo ""
  if [[ "$FILE_TYPE" == "text" ]]; then
    rewrite_text "$INPUT" "$OUTPUT" "$OLD_PATH" "$PLACEHOLDER"
  else
    rewrite_sqlite "$INPUT" "$OUTPUT" "$OLD_PATH" "$PLACEHOLDER"
  fi

  echo ""
  echo "Done — portable file written."
  echo "  Input   : $INPUT"
  echo "  Replaced: $OLD_PATH"
  echo "  With    : $PLACEHOLDER"
  echo "  Output  : $OUTPUT"
  echo ""
  echo "Share '$OUTPUT' and the recipient runs --import to set their own path."

# ─────────────────────────────────────────────────────────────────────────────
# IMPORT MODE
# ─────────────────────────────────────────────────────────────────────────────
elif [[ "$MODE" == "import" ]]; then

  echo ""
  echo "=== IMPORT MODE (.$EXT) ==="
  echo "The placeholder '$PLACEHOLDER' will be replaced with your local music path."
  echo ""

  # Validate placeholder exists
  PLACEHOLDER_FOUND=false
  if [[ "$FILE_TYPE" == "text" ]] && grep -q "$PLACEHOLDER" "$INPUT"; then
    PLACEHOLDER_FOUND=true
  elif [[ "$FILE_TYPE" == "sqlite" ]]; then
    # Search all TEXT columns for the placeholder
    while IFS= read -r table; do
      while IFS='|' read -r _cid col_name col_type _rest; do
        if echo "$col_type" | grep -qiE "TEXT|CHAR|CLOB"; then
          count=$(sqlite3 "$INPUT" \
            "SELECT COUNT(*) FROM \"${table}\" WHERE \"${col_name}\" LIKE '%${PLACEHOLDER}%';" 2>/dev/null || echo 0)
          if [[ "$count" -gt 0 ]]; then
            PLACEHOLDER_FOUND=true
            break 2
          fi
        fi
      done < <(sqlite3 "$INPUT" "PRAGMA table_info(\"${table}\");")
    done < <(sqlite3 "$INPUT" "SELECT name FROM sqlite_master WHERE type='table';")
  fi

  if [[ "$PLACEHOLDER_FOUND" == false ]]; then
    echo "Error: Placeholder '$PLACEHOLDER' not found in $INPUT."
    echo "Make sure you are using a file that was prepared with --export."
    exit 1
  fi

  read -rp "Enter your local music path (e.g. /home/yourname/Music): " NEW_PATH
  NEW_PATH="${NEW_PATH%/}"  # strip trailing slash

  if [[ -z "$NEW_PATH" ]]; then
    echo "Error: No path entered. Aborting."
    exit 1
  fi

  echo ""
  if [[ "$FILE_TYPE" == "text" ]]; then
    rewrite_text "$INPUT" "$OUTPUT" "$PLACEHOLDER" "$NEW_PATH"
  else
    rewrite_sqlite "$INPUT" "$OUTPUT" "$PLACEHOLDER" "$NEW_PATH"
  fi

  echo ""
  echo "Done — local file written."
  echo "  Input   : $INPUT"
  echo "  Replaced: $PLACEHOLDER"
  echo "  With    : $NEW_PATH"
  echo "  Output  : $OUTPUT"

fi
