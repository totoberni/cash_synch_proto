#!/bin/bash
# .claude/hooks/update-changelog.sh
# PostToolUse hook: auto-appends changelog entries when files are written/edited.
# Adapted for GAS Change Tracker Sandbox module structure.

# Read tool info from stdin
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')

# Skip if no file path
[ -z "$FILE_PATH" ] && exit 0

# Prevent infinite recursion — skip changelog files and orchestrator state
BASENAME=$(basename "$FILE_PATH")
case "$BASENAME" in
  changelog.md|changelog-archive.md|CHANGELOG.md|CLAUDE.md) exit 0 ;;
  state.md|task-queue.md|active-tasks.md|decisions.md) exit 0 ;;
  gotchas.md) exit 0 ;;
esac

# Only track files in our source modules
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
REL_PATH="${FILE_PATH#$PROJECT_DIR/}"

# Determine which module this file belongs to
case "$REL_PATH" in
  apps-script/src/api/*)         CHANGELOG="$PROJECT_DIR/apps-script/src/api/changelog.md" ;;
  apps-script/src/correlation/*) CHANGELOG="$PROJECT_DIR/apps-script/src/correlation/changelog.md" ;;
  apps-script/src/logging/*)     CHANGELOG="$PROJECT_DIR/apps-script/src/logging/changelog.md" ;;
  apps-script/src/tracking/*)    CHANGELOG="$PROJECT_DIR/apps-script/src/tracking/changelog.md" ;;
  stub-server/*)                 CHANGELOG="$PROJECT_DIR/stub-server/changelog.md" ;;
  scripts/*)                     CHANGELOG="$PROJECT_DIR/scripts/changelog.md" ;;
  *)                             exit 0 ;;  # Not a tracked module
esac

TIMESTAMP=$(date -u '+%H:%MZ')
DATE=$(date -u '+%Y-%m-%d')

# Build description from tool type
if [ "$TOOL_NAME" = "Write" ]; then
  DESC="File written/created"
elif [ "$TOOL_NAME" = "Edit" ]; then
  OLD=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty' | head -c 60 | tr '\n' ' ')
  NEW=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' | head -c 60 | tr '\n' ' ')
  DESC="Edited: '${OLD}' → '${NEW}'"
elif [ "$TOOL_NAME" = "MultiEdit" ]; then
  DESC="Multiple edits applied"
fi

# Create changelog if it doesn't exist
if [ ! -f "$CHANGELOG" ]; then
  MODULE_DIR=$(dirname "$CHANGELOG")
  MODULE=$(basename "$MODULE_DIR")
  cat > "$CHANGELOG" << EOF
# Changelog — $MODULE

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
echo "- **${TIMESTAMP}** | \`${REL_PATH}\` | ${DESC} | session:\`${SESSION_ID:0:8}\`" >> "$CHANGELOG"

# Truncation: keep only last 25 entries
ENTRY_COUNT=$(grep -c '^\- \*\*' "$CHANGELOG" 2>/dev/null || echo 0)
if [ "$ENTRY_COUNT" -gt 25 ]; then
  ARCHIVE="${CHANGELOG%.md}-archive.md"
  HEADER_END=$(grep -n '^\- \*\*' "$CHANGELOG" | head -1 | cut -d: -f1)
  HEADER_END=$((HEADER_END - 1))
  head -n "$HEADER_END" "$CHANGELOG" > "$CHANGELOG.tmp"
  tail -n 30 "$CHANGELOG" >> "$CHANGELOG.tmp"
  head -n -30 "$CHANGELOG" | tail -n +"$((HEADER_END + 1))" >> "$ARCHIVE"
  mv "$CHANGELOG.tmp" "$CHANGELOG"
fi

exit 0
