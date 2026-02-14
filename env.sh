#!/bin/bash
# scripts/load-env.sh
# ===================
# Loads environment variables from .env file (in project root) for Claude Code orchestration
# 
# Usage:
#   source scripts/load-env.sh           # Load variables into current shell
#   ./scripts/load-env.sh                # Display variables without loading (for verification)

# Get the project root directory (parent of scripts/)
SCRIPT_DIR="."
PROJECT_ROOT="."
ENV_FILE=".env"

# Check if .env file exists
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: .env file not found at $ENV_FILE"
    echo "Please create one based on .env.example"
    echo ""
    echo "Quick setup:"
    echo "  cp .env.example .env"
    echo "  nano .env"
    return 1 2>/dev/null || exit 1
fi

# Function to export variables if sourced, or just display if executed
load_env() {
    local line_num=0
    while IFS= read -r line || [ -n "$line" ]; do
        line_num=$((line_num + 1))
        
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Parse KEY=VALUE format
        if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            
            # Remove surrounding quotes if present
            value=$(echo "$value" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
            
            # Export if sourced, otherwise just display
            if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
                export "$key=$value"
                echo "✓ Loaded: $key=$value"
            else
                echo "$key=$value"
            fi
        fi
    done < "$ENV_FILE"
}

# Main execution
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    echo "Loading environment variables from $ENV_FILE..."
    load_env
    echo ""
    echo "✓ Environment variables loaded successfully!"
    echo "To verify, run: env | grep CLAUDE_CODE"
else
    echo "Current .env configuration:"
    echo "================================"
    load_env
    echo ""
    echo "To load these variables, run: source scripts/load-env.sh"
fi
