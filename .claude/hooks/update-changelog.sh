#!/bin/bash
# update-changelog.sh — PostToolUse hook for per-module changelog updates
# Fires on: Edit | MultiEdit | Write
# Appends a timestamped entry to the relevant module's changelog.md
set -euo pipefail

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')

# Skip if no file path
[ -z "$FILE_PATH" ] && exit 0

# Prevent infinite recursion — skip meta files
BASENAME=$(basename "$FILE_PATH")
case "$BASENAME" in
  changelog.md|changelog-archive.md|CHANGELOG.md) exit 0 ;;
  gotchas.md|CLAUDE.md|CLAUDE.local.md) exit 0 ;;
  settings.json|settings.local.json) exit 0 ;;
  plan.md|README.md|test-report.md) exit 0 ;;
  *.example|.gitignore|.clasp.json) exit 0 ;;
esac

# Resolve project dir
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
REL_PATH="${FILE_PATH#$PROJECT_DIR/}"

# Determine which module this file belongs to
case "$REL_PATH" in
  apps-script/src/api/*)         CHANGELOG="$PROJECT_DIR/apps-script/src/api/changelog.md" ;;
  apps-script/src/tracking/*)    CHANGELOG="$PROJECT_DIR/apps-script/src/tracking/changelog.md" ;;
  apps-script/src/correlation/*) exit 0 ;;  # READ-ONLY — enterprise copy, should never fire
  apps-script/src/logging/*)     exit 0 ;;  # READ-ONLY — enterprise copy, should never fire
  stub-server/*)                 CHANGELOG="$PROJECT_DIR/apps-script/src/tracking/changelog.md" ;;
  scripts/*)                     CHANGELOG="$PROJECT_DIR/apps-script/src/tracking/changelog.md" ;;
  *)                             exit 0 ;;  # Untracked file
esac

TIMESTAMP=$(date -u '+%H:%MZ')
DATE=$(date -u '+%Y-%m-%d')

# Build description from tool type
DESC=""
if [ "$TOOL_NAME" = "Write" ]; then
  DESC="File created/written: \`$REL_PATH\`"
elif [ "$TOOL_NAME" = "Edit" ]; then
  OLD=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty' 2>/dev/null | head -c 60 | tr '\n' ' ')
  NEW=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null | head -c 60 | tr '\n' ' ')
  if [ -n "$OLD" ] && [ -n "$NEW" ]; then
    DESC="Edited \`$REL_PATH\`: '${OLD}' → '${NEW}'"
  else
    DESC="Edited \`$REL_PATH\`"
  fi
elif [ "$TOOL_NAME" = "MultiEdit" ]; then
  DESC="Multiple edits to \`$REL_PATH\`"
fi

[ -z "$DESC" ] && exit 0

# Create changelog if it doesn't exist
if [ ! -f "$CHANGELOG" ]; then
  MODULE_DIR=$(dirname "$CHANGELOG")
  MODULE_NAME=$(basename "$MODULE_DIR")
  cat > "$CHANGELOG" << EOF
# Changelog — $MODULE_NAME

<!-- AUTO-MANAGED: Entries appended by PostToolUse hook -->

## $DATE

EOF
fi

# Add date header if today's date isn't present
if ! grep -q "## $DATE" "$CHANGELOG"; then
  echo "" >> "$CHANGELOG"
  echo "## $DATE" >> "$CHANGELOG"
  echo "" >> "$CHANGELOG"
fi

# Append entry
echo "- **${TIMESTAMP}** | ${DESC} | session:\`${SESSION_ID:0:8}\`" >> "$CHANGELOG"

# Truncation: keep only last 25 entries
ENTRY_COUNT=$(grep -c '^\- \*\*' "$CHANGELOG" 2>/dev/null || echo 0)
if [ "$ENTRY_COUNT" -gt 25 ]; then
  ARCHIVE="${CHANGELOG%.md}-archive.md"
  # Preserve header (first 3 lines)
  head -n 3 "$CHANGELOG" > "$CHANGELOG.tmp"
  echo "" >> "$CHANGELOG.tmp"
  # Keep last 25 entry lines plus their date headers
  tail -n 30 "$CHANGELOG" >> "$CHANGELOG.tmp"
  # Archive overflow
  echo "" >> "$ARCHIVE" 2>/dev/null || true
  echo "## Archived $(date -u '+%Y-%m-%d %H:%MZ')" >> "$ARCHIVE"
  grep '^\- \*\*' "$CHANGELOG" | head -n -25 >> "$ARCHIVE"
  mv "$CHANGELOG.tmp" "$CHANGELOG"
fi

exit 0