#!/bin/bash
# Stage ZOS for the in-game Workshop uploader.
# PZwiki: ~/Zomboid/Workshop/<name>/Contents/mods/<ModId>/... + workshop.txt + preview.png
#
# Usage:
#   ./scripts/deploy_workshop.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SRC="$PROJECT_ROOT/Contents/mods/ZOS"
TARGET_DIR="$HOME/Zomboid/Workshop"
WORKSHOP_MOD="$TARGET_DIR/ZOS"
CONTENTS_MOD="$WORKSHOP_MOD/Contents/mods/ZOS"

if [ ! -d "$SRC/42.20" ]; then
    echo "Mod source not found: $SRC/42.20"
    exit 1
fi

if [ ! -f "$PROJECT_ROOT/workshop.txt" ]; then
    echo "Missing workshop.txt at mod root"
    exit 1
fi

if [ -d "$WORKSHOP_MOD" ]; then
    echo "Removing existing Workshop mod directory..."
    rm -rf "$WORKSHOP_MOD"
fi

echo "Creating Workshop structure..."
mkdir -p "$CONTENTS_MOD"

if [ -d "$SRC/common" ]; then
    cp -r "$SRC/common" "$CONTENTS_MOD/"
else
    mkdir -p "$CONTENTS_MOD/common"
fi

echo "Copying 42.20..."
cp -r "$SRC/42.20" "$CONTENTS_MOD/"

cp "$PROJECT_ROOT/workshop.txt" "$WORKSHOP_MOD/"
if [ -f "$PROJECT_ROOT/preview.png" ]; then
    cp "$PROJECT_ROOT/preview.png" "$WORKSHOP_MOD/"
else
    echo "No preview.png at mod root — add one for the Workshop thumb"
fi

echo "Cleaning up..."
find "$WORKSHOP_MOD" -name ".DS_Store" -delete

echo "Deployed to $WORKSHOP_MOD"
echo "  Structure: Contents/mods/ZOS/{common,42.20}"
echo "  Next: Run game → Workshop → Create and update items"
