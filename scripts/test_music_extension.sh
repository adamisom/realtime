#!/bin/bash

# Music Extension Automated Test Script
# Wrapper script that sets up environment and runs Elixir test script

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Change to project root
cd "$PROJECT_ROOT"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Music Extension Automated Test Runner                     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}📋 Checking prerequisites...${NC}"

# Check if mix is available
if ! command -v mix &> /dev/null; then
    echo -e "${RED}❌ Error: 'mix' command not found. Please install Elixir.${NC}"
    exit 1
fi

# Check if database is accessible
if ! mix ecto.migrate --quiet 2>/dev/null; then
    echo -e "${YELLOW}⚠️  Warning: Database migration check failed. Continuing anyway...${NC}"
fi

# Check if server dependencies are available
if [ ! -d "deps" ]; then
    echo -e "${YELLOW}📦 Installing dependencies...${NC}"
    mix deps.get
fi

# Check if application is compiled
if [ ! -d "_build" ]; then
    echo -e "${YELLOW}🔨 Compiling application...${NC}"
    mix compile
fi

# Check if server is running (optional - tests can run without it for some features)
if ! curl -s http://localhost:4000/health &>/dev/null && ! curl -s http://localhost:4000 &>/dev/null; then
    echo -e "${YELLOW}⚠️  Warning: Server doesn't appear to be running on port 4000.${NC}"
    echo -e "${YELLOW}   Some tests may fail. Start server with: mix phx.server${NC}"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo -e "${GREEN}✅ Prerequisites check complete${NC}"
echo ""

# Run the Elixir test script
echo -e "${BLUE}🚀 Running test suite...${NC}"
echo ""

# Use mix run to execute the script with the application context loaded
if mix run "$SCRIPT_DIR/test_music_extension.exs"; then
    echo ""
    echo -e "${GREEN}✅ Test suite completed successfully${NC}"
    exit 0
else
    EXIT_CODE=$?
    echo ""
    echo -e "${RED}❌ Test suite completed with failures (exit code: $EXIT_CODE)${NC}"
    exit $EXIT_CODE
fi

