#!/bin/bash

# Deploy ZOS to ~/Zomboid/mods (local testing)
# Prerequisites: none. Run from project root or scripts/

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

TARGET_DIR="$HOME/Zomboid/mods/ZOS"
SRC="$PROJECT_ROOT/Contents/mods/ZOS"

echo -e "${GREEN}=== ZOS Local Deployment ===${NC}"

if [ -d "$TARGET_DIR" ]; then
    echo -e "${YELLOW}Removing existing mod directory...${NC}"
    rm -rf "$TARGET_DIR"
fi

echo -e "${YELLOW}Copying mod to Zomboid/mods...${NC}"
cp -rf "$SRC" "$(dirname "$TARGET_DIR")/"

echo -e "${GREEN}Mod copied to $TARGET_DIR${NC}"
