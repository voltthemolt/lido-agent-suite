#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Autonomous Agent Demo ==="
echo ""

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
  echo "[setup] Installing dependencies..."
  npm install --silent 2>&1
fi

# Compile TypeScript
echo "[build] Compiling TypeScript..."
npx tsc

# Run the agent
echo "[run]   Launching autonomous agent..."
echo ""
node dist/autonomous-agent.js
