#!/bin/bash
# .claude/hooks/check-gotchas-on-error.sh
# PostToolUse hook for Bash commands: when a command fails, search gotchas.md
# for relevant advice and inject it as additional context.

INPUT=$(cat)

# Extract exit code and command from hook input
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_result.exit_code // 0')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
STDERR=$(echo "$INPUT" | jq -r '.tool_result.stderr // empty')
STDOUT=$(echo "$INPUT" | jq -r '.tool_result.stdout // empty')

# Only act on failures
[ "$EXIT_CODE" = "0" ] && exit 0
[ -z "$COMMAND" ] && exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
GOTCHAS="$PROJECT_DIR/gotchas.md"

# If gotchas.md doesn't exist, nothing to check
[ ! -f "$GOTCHAS" ] && exit 0

# Combine stderr and stdout for keyword matching
ERROR_TEXT="$STDERR $STDOUT $COMMAND"

# Build a list of keywords to search for based on the failed command and output
KEYWORDS=""

# Extract tool-specific keywords
case "$COMMAND" in
  *clasp*)     KEYWORDS="clasp deploy push pull authorization" ;;
  *curl*)      KEYWORDS="curl response caching ContentService" ;;
  *node*)      KEYWORDS="node server localhost" ;;
  *git*)       KEYWORDS="git" ;;
  *UrlFetch*)  KEYWORDS="UrlFetchApp localhost ngrok" ;;
esac

# Also extract keywords from error text (common GAS/clasp terms)
for term in "authorization" "deployment" "cached" "timeout" "6-minute" \
            "import" "export" "scope" "UrlFetchApp" "localhost" \
            "ContentService" "HtmlService" "clasp" "push" "deploy"; do
  if echo "$ERROR_TEXT" | grep -qi "$term"; then
    KEYWORDS="$KEYWORDS $term"
  fi
done

# If we found relevant keywords, search gotchas.md
if [ -n "$KEYWORDS" ]; then
  MATCHES=""
  for kw in $KEYWORDS; do
    RESULT=$(grep -i "$kw" "$GOTCHAS" 2>/dev/null | head -3)
    if [ -n "$RESULT" ]; then
      MATCHES="$MATCHES\n$RESULT"
    fi
  done

  if [ -n "$MATCHES" ]; then
    # Output additional context for Claude to see
    echo ""
    echo "⚠️  GOTCHA MATCH — The failed command may relate to a known issue."
    echo "Relevant entries from gotchas.md:"
    echo -e "$MATCHES" | sort -u | head -10
    echo ""
    echo "→ Read gotchas.md for full context and workarounds."
  fi
fi

exit 0
