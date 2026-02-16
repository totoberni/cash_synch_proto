#!/bin/bash
#
# Development Environment Startup Script
#
# Starts stub server + ngrok in a single terminal session.
# Automatically extracts and displays the ngrok HTTPS URL.
#
# Prerequisites:
#   - node (for stub-server)
#   - ngrok (for public tunneling)
#   - curl (for ngrok API polling)
#   - jq (for JSON parsing)
#
# Usage:
#   ./scripts/dev-start.sh
#
# Press Ctrl+C to stop both processes.
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/.."
ENV_FILE="$PROJECT_ROOT/.env"

# Default values
STUB_SERVER_PORT=3456

# Source .env if it exists
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}┌────────────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│ GAS Change Tracker — Development Environment                   │${NC}"
echo -e "${BLUE}└────────────────────────────────────────────────────────────────┘${NC}"
echo ""

# Check prerequisites
for cmd in node ngrok curl jq; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}Error: $cmd is not installed${NC}"
        exit 1
    fi
done

# Check if port is already in use, kill if needed
if lsof -Pi :$STUB_SERVER_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo -e "${YELLOW}Port $STUB_SERVER_PORT is already in use. Killing existing process...${NC}"
    lsof -ti :$STUB_SERVER_PORT | xargs kill -9 2>/dev/null || true
    sleep 1
fi

# PID tracking
STUB_PID=""
NGROK_PID=""

# Cleanup function
cleanup() {
    echo ""
    echo -e "${YELLOW}Shutting down...${NC}"

    if [ -n "$STUB_PID" ]; then
        kill $STUB_PID 2>/dev/null || true
        echo "  - Stopped stub server (PID: $STUB_PID)"
    fi

    if [ -n "$NGROK_PID" ]; then
        kill $NGROK_PID 2>/dev/null || true
        echo "  - Stopped ngrok (PID: $NGROK_PID)"
    fi

    echo -e "${GREEN}✓ Cleanup complete${NC}"
    exit 0
}

# Register cleanup on exit
trap cleanup SIGINT SIGTERM

# Start stub server in background
echo -e "${BLUE}Starting stub server on port $STUB_SERVER_PORT...${NC}"
STUB_SERVER_PORT=$STUB_SERVER_PORT node "$PROJECT_ROOT/stub-server/server.js" &
STUB_PID=$!
sleep 2

# Verify stub server started
if ! kill -0 $STUB_PID 2>/dev/null; then
    echo -e "${RED}Error: Stub server failed to start${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Stub server started (PID: $STUB_PID)${NC}"
echo ""

# Start ngrok in background
echo -e "${BLUE}Starting ngrok tunnel...${NC}"
ngrok http $STUB_SERVER_PORT --log=stdout > /tmp/ngrok.log 2>&1 &
NGROK_PID=$!
sleep 2

# Verify ngrok started
if ! kill -0 $NGROK_PID 2>/dev/null; then
    echo -e "${RED}Error: ngrok failed to start${NC}"
    kill $STUB_PID 2>/dev/null || true
    exit 1
fi

# Poll ngrok API until ready (max 10 seconds)
echo -e "${BLUE}Waiting for ngrok to establish tunnel...${NC}"
NGROK_URL=""
for i in {1..10}; do
    if TUNNELS=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null); then
        NGROK_URL=$(echo "$TUNNELS" | jq -r '.tunnels[] | select(.proto=="https") | .public_url' 2>/dev/null || true)
        if [ -n "$NGROK_URL" ]; then
            break
        fi
    fi
    sleep 1
done

if [ -z "$NGROK_URL" ]; then
    echo -e "${RED}Error: Failed to retrieve ngrok URL${NC}"
    cleanup
    exit 1
fi

echo -e "${GREEN}✓ ngrok tunnel established (PID: $NGROK_PID)${NC}"
echo ""

# Display configuration
echo -e "${GREEN}┌────────────────────────────────────────────────────────────────┐${NC}"
echo -e "${GREEN}│ Development Environment Ready                                   │${NC}"
echo -e "${GREEN}├────────────────────────────────────────────────────────────────┤${NC}"
echo -e "${GREEN}│${NC} Local stub server:  http://localhost:$STUB_SERVER_PORT/changelog"
echo -e "${GREEN}│${NC} Public ngrok URL:   $NGROK_URL/changelog"
echo -e "${GREEN}├────────────────────────────────────────────────────────────────┤${NC}"
echo -e "${GREEN}│${NC} Next steps:                                                  ${GREEN}│${NC}"
echo -e "${GREEN}│${NC}   1. Open GAS Script Editor (clasp open)                     ${GREEN}│${NC}"
echo -e "${GREEN}│${NC}   2. Project Settings → Script Properties → Add:             ${GREEN}│${NC}"
echo -e "${GREEN}│${NC}      CHANGE_TRACKER_VPS_URL = $NGROK_URL/changelog"
echo -e "${GREEN}│${NC}      CHANGE_TRACKER_ENABLED = true                            ${GREEN}│${NC}"
echo -e "${GREEN}│${NC}   3. Test with: ./scripts/post-push-notify.sh                ${GREEN}│${NC}"
echo -e "${GREEN}└────────────────────────────────────────────────────────────────┘${NC}"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop both processes${NC}"
echo ""

# Wait indefinitely (until Ctrl+C)
wait
