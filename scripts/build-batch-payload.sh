#!/bin/bash
#
# Build Batch Payload — Constructs JSON for the Documentation Batch workflow
#
# Gathers commit metadata and changed files between two SHAs,
# outputs a JSON payload suitable for POSTing to the GAS batch endpoint.
#
# Prerequisites:
#   - git (for commit/diff queries)
#   - jq (for safe JSON construction)
#
# Usage:
#   bash scripts/build-batch-payload.sh FROM_SHA TO_SHA PATH_FILTER TRIGGER TRIGGERED_BY REPOSITORY
#
# Arguments:
#   FROM_SHA      - Start of commit range (exclusive)
#   TO_SHA        - End of commit range (inclusive)
#   PATH_FILTER   - Directory filter for changed files (e.g. "apps-script/src/")
#   TRIGGER       - How this was triggered: "manual" or "scheduled"
#   TRIGGERED_BY  - Who/what triggered: GitHub actor or "cron"
#   REPOSITORY    - Repository identifier (e.g. "owner/repo")
#
# Output:
#   JSON payload to stdout (pipe to file or curl -d @-)
#
# Example (local test):
#   FROM=$(git log --reverse --pretty=format:"%H" | head -1)
#   TO=$(git rev-parse HEAD)
#   bash scripts/build-batch-payload.sh "$FROM" "$TO" "apps-script/src/" "manual" "test-user" "owner/repo" | jq .
#

set -euo pipefail

# ────────────────────────────────────────────────────────────────
# Prerequisite check
# ────────────────────────────────────────────────────────────────

if ! command -v jq &> /dev/null; then
    echo "ERROR: jq is required but not installed." >&2
    echo "Install it with: sudo apt install jq (Linux) or brew install jq (macOS)" >&2
    exit 1
fi

if ! command -v git &> /dev/null; then
    echo "ERROR: git is required but not installed." >&2
    exit 1
fi

# ────────────────────────────────────────────────────────────────
# Parse arguments
# ────────────────────────────────────────────────────────────────

if [ $# -lt 6 ]; then
    echo "Usage: bash scripts/build-batch-payload.sh FROM_SHA TO_SHA PATH_FILTER TRIGGER TRIGGERED_BY REPOSITORY" >&2
    echo "" >&2
    echo "Arguments:" >&2
    echo "  FROM_SHA      Start of commit range (exclusive)" >&2
    echo "  TO_SHA        End of commit range (inclusive)" >&2
    echo "  PATH_FILTER   Directory filter (e.g. 'apps-script/src/')" >&2
    echo "  TRIGGER       'manual' or 'scheduled'" >&2
    echo "  TRIGGERED_BY  GitHub actor or 'cron'" >&2
    echo "  REPOSITORY    Repository identifier (e.g. 'owner/repo')" >&2
    exit 1
fi

FROM_SHA="$1"
TO_SHA="$2"
PATH_FILTER="$3"
TRIGGER="$4"
TRIGGERED_BY="$5"
REPOSITORY="$6"

# ────────────────────────────────────────────────────────────────
# Gather data
# ────────────────────────────────────────────────────────────────

# Commit count
COMMIT_COUNT=$(git rev-list --count "$FROM_SHA".."$TO_SHA")

# Build commits array using NUL-delimited format for safe handling
# of special characters in commit messages
COMMITS_JSON=$(
    git log "$FROM_SHA".."$TO_SHA" --pretty=format:"%H%x00%h%x00%an%x00%s%x00%aI%x00" |
    jq -R -s '
        split("\u0000\n") |
        map(select(length > 0)) |
        map(
            split("\u0000") |
            select(length >= 5) |
            {
                sha: .[0],
                shortSha: .[1],
                author: .[2],
                message: .[3],
                timestamp: .[4]
            }
        )
    '
)

# Build files changed array, filtering by PATH_FILTER and stripping prefix
FILES_JSON=$(
    git diff --name-only "$FROM_SHA" "$TO_SHA" -- "$PATH_FILTER" 2>/dev/null |
    sed "s|^${PATH_FILTER}||" |
    jq -R -s 'split("\n") | map(select(length > 0))'
)

# ────────────────────────────────────────────────────────────────
# Construct final payload
# ────────────────────────────────────────────────────────────────

jq -n \
    --arg action "reportBatch" \
    --arg trigger "$TRIGGER" \
    --arg triggeredBy "$TRIGGERED_BY" \
    --arg repository "$REPOSITORY" \
    --arg from "$FROM_SHA" \
    --arg to "$TO_SHA" \
    --argjson commitCount "$COMMIT_COUNT" \
    --argjson commits "$COMMITS_JSON" \
    --argjson filesChanged "$FILES_JSON" \
    --arg pathFilter "$PATH_FILTER" \
    '{
        action: $action,
        trigger: $trigger,
        triggeredBy: $triggeredBy,
        repository: $repository,
        range: {
            from: $from,
            to: $to,
            commitCount: $commitCount
        },
        commits: $commits,
        filesChanged: $filesChanged,
        pathFilter: $pathFilter
    }'
