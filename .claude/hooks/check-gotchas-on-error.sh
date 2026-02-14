#!/bin/bash
# check-gotchas-on-error.sh — PostToolUse hook for Bash tool
# Fires on: Bash
# When a bash command produces error-like output, injects additionalContext
# telling the agent to check gotchas.md for known solutions and to update it
# if they solve a new problem.
set -euo pipefail

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"')

# Only process Bash tool results
[ "$TOOL_NAME" != "Bash" ] && exit 0

# Extract the command output (stdout/stderr combined)
# PostToolUse receives tool_output with the command result
TOOL_OUTPUT=$(echo "$INPUT" | jq -r '.tool_output // empty' 2>/dev/null)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Skip if no output to analyze
[ -z "$TOOL_OUTPUT" ] && exit 0

# Check for error patterns in the output (case-insensitive)
ERROR_DETECTED=false
ERROR_PATTERNS="error|Error|ERROR|fatal|FATAL|Failed|FAILED|failed|denied|DENIED|refused|Exception|exception|EXCEPTION|Traceback|traceback|not found|NOT FOUND|Permission denied|command not found|No such file|Cannot find|unable to|Unable to"

if echo "$TOOL_OUTPUT" | grep -qiE "$ERROR_PATTERNS"; then
  ERROR_DETECTED=true
fi

# Also check for non-zero exit codes if available
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_output_metadata.exit_code // empty' 2>/dev/null)
if [ -n "$EXIT_CODE" ] && [ "$EXIT_CODE" != "0" ]; then
  ERROR_DETECTED=true
fi

# Skip common false positives
if echo "$COMMAND" | grep -qE '(grep|find|test |diff |git diff|git log)'; then
  # These commands often contain "error" in their output without being errors
  # Only flag if exit code was explicitly non-zero
  if [ -z "$EXIT_CODE" ] || [ "$EXIT_CODE" = "0" ]; then
    ERROR_DETECTED=false
  fi
fi

# If no error detected, exit silently
[ "$ERROR_DETECTED" != "true" ] && exit 0

# Inject context telling the agent to check gotchas.md
# The additionalContext field is appended to what the agent sees
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
GOTCHAS_FILE="$PROJECT_DIR/gotchas.md"

if [ -f "$GOTCHAS_FILE" ]; then
  cat << 'JSONEOF'
{
  "additionalContext": "⚠️ ERROR DETECTED in command output. Before debugging from scratch:\n1. READ gotchas.md at project root — it contains known errors and their solutions for this project.\n2. If the error matches a known gotcha, apply the documented fix.\n3. If you solve a NEW error not in gotchas.md, APPEND it with this format:\n\n| Symptom | Cause | Fix |\n|---------|-------|-----|\n| <error message> | <root cause> | <what fixed it> |\n\nThis helps future agent sessions avoid the same mistake."
}
JSONEOF
else
  cat << 'JSONEOF'
{
  "additionalContext": "⚠️ ERROR DETECTED in command output. If you resolve this error, create gotchas.md at project root and document the problem and solution so future agent sessions can reference it."
}
JSONEOF
fi

exit 0