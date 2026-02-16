#!/bin/bash
#
# Post-Push Notification Script — Bash
#
# Gathers git metadata and POSTs change notification to GAS web app.
#
# Prerequisites:
#   - git (for commit metadata)
#   - curl (for HTTP POST)
#   - jq (for JSON array construction)
#
# Usage:
#   export GAS_WEBAPP_URL="https://script.google.com/macros/s/YOUR_SCRIPT_ID/exec"
#   ./scripts/post-push-notify.sh
#

set -euo pipefail

# Source .env if it exists (project root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

# Configuration
GAS_WEBAPP_URL="${GAS_WEBAPP_URL:-https://YOUR_GAS_SCRIPT_URL_HERE/exec}"
APPS_SCRIPT_DIR="apps-script/src"

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}┌────────────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│ GAS Change Tracker — Post-Push Notification                    │${NC}"
echo -e "${BLUE}└────────────────────────────────────────────────────────────────┘${NC}"
echo ""

# Check if git is available
if ! command -v git &> /dev/null; then
    echo -e "${YELLOW}Warning: git not found. Using fallback values.${NC}"
    COMMIT_MESSAGE="Manual push (git not available)"
    COMMIT_HASH="unknown"
    AUTHOR="unknown"
    CHANGED_FILES="[]"
else
    # Gather git metadata
    COMMIT_MESSAGE=$(git log -1 --pretty=format:"%s" 2>/dev/null || echo "Manual push")
    COMMIT_HASH=$(git log -1 --pretty=format:"%h" 2>/dev/null || echo "unknown")
    AUTHOR=$(git log -1 --pretty=format:"%an" 2>/dev/null || echo "unknown")

    # Get changed files in apps-script/src/ from the last commit
    # Use jq to construct a proper JSON array
    if command -v jq &> /dev/null; then
        CHANGED_FILES=$(git diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null | \
                       { grep "^${APPS_SCRIPT_DIR}/" || true; } | \
                       sed "s|^${APPS_SCRIPT_DIR}/||" | \
                       jq -R -s -c 'split("\n") | map(select(length > 0))')

        # Fallback if no files found
        if [ "$CHANGED_FILES" = "[]" ] || [ -z "$CHANGED_FILES" ]; then
            CHANGED_FILES='["(no apps-script changes in last commit)"]'
        fi
    else
        echo -e "${YELLOW}Warning: jq not found. Using placeholder for files array.${NC}"
        CHANGED_FILES='["(jq not available)"]'
    fi
fi

# Build JSON payload
PAYLOAD=$(cat <<EOF
{
  "action": "reportChange",
  "author": "$AUTHOR",
  "changelog": "$COMMIT_MESSAGE",
  "commitHash": "$COMMIT_HASH",
  "files": $CHANGED_FILES
}
EOF
)

# Display what we're sending
echo -e "${GREEN}Metadata gathered:${NC}"
echo "  Author:      $AUTHOR"
echo "  Commit:      $COMMIT_HASH"
echo "  Message:     $COMMIT_MESSAGE"
echo "  Files:       $CHANGED_FILES"
echo ""

# Check if URL is configured
if [[ "$GAS_WEBAPP_URL" == *"YOUR_GAS_SCRIPT_URL_HERE"* ]]; then
    echo -e "${YELLOW}Warning: GAS_WEBAPP_URL not configured. Using placeholder.${NC}"
    echo "  Set it with: export GAS_WEBAPP_URL=\"https://script.google.com/...\""
    echo ""
fi

echo -e "${BLUE}Sending notification to: $GAS_WEBAPP_URL${NC}"
echo ""

# POST to GAS web app
# IMPORTANT: Use -d (not -X POST) to handle GAS 302 redirects correctly
# See gotchas.md line 19
RESPONSE=$(curl -sL \
  -d "$PAYLOAD" \
  -H "Content-Type: application/json" \
  "$GAS_WEBAPP_URL")

echo -e "${GREEN}Response:${NC}"
echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
echo ""

# Check for success
if echo "$RESPONSE" | jq -e '.success == true' &> /dev/null; then
    echo -e "${GREEN}✓ Change notification sent successfully${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠ Warning: Response may indicate an error${NC}"
    exit 1
fi
