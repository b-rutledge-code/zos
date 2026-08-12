#!/bin/bash

# Bake historicalsource COMPILED/zorkN.z3 (MIT, Z-machine v3) into a generated
# Lua module of 1024-byte numeric chunk tables. Kahlua's string.byte is not
# safe on NUL-filled data, so chunks are number tables, not strings.
#
# Run from anywhere:  ./tools/bake_zork.sh 1|2|3
# ./tools/bake_zork1.sh still works and calls this with 1.

set -euo pipefail

TITLE="${1:-}"
if [ "$TITLE" != "1" ] && [ "$TITLE" != "2" ] && [ "$TITLE" != "3" ]; then
    echo "Usage: $0 1|2|3" >&2
    exit 1
fi

BYTES_PER_CHUNK=1024

case "$TITLE" in
    1)
        REPO="zork1"
        FILE="zork1.z3"
        MODULE="ZosStoryZork1"
        LABEL="Zork I"
        EXPECT_SHA1="c4f162274869b5433e4b9dfa7ee770fc3b789525"
        EXPECT_BYTES=86838
        RELEASE=119
        SERIAL="880429"
        ;;
    2)
        REPO="zork2"
        FILE="zork2.z3"
        MODULE="ZosStoryZork2"
        LABEL="Zork II"
        EXPECT_SHA1="6e5415ace76ad235a307a5d4a2e88a8980b9f193"
        EXPECT_BYTES=92524
        RELEASE=63
        SERIAL="860811"
        ;;
    3)
        REPO="zork3"
        FILE="zork3.z3"
        MODULE="ZosStoryZork3"
        LABEL="Zork III"
        EXPECT_SHA1="0340b09fe05cf3ba0f01c04a7699236e15ab2aed"
        EXPECT_BYTES=87984
        RELEASE=25
        SERIAL="860811"
        ;;
esac

URL="https://raw.githubusercontent.com/historicalsource/${REPO}/master/COMPILED/${FILE}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUT="$PROJECT_ROOT/Contents/mods/ZOS/42.20/media/lua/shared/Zos/${MODULE}.lua"

TMP="$(mktemp -t "${FILE}.XXXXXX")"
trap 'rm -f "$TMP"' EXIT

echo "Downloading $URL"
curl -fsSL "$URL" -o "$TMP"

ACTUAL_BYTES=$(wc -c < "$TMP" | tr -d ' ')
if [ "$ACTUAL_BYTES" != "$EXPECT_BYTES" ]; then
    echo "ERROR: expected $EXPECT_BYTES bytes, got $ACTUAL_BYTES" >&2
    exit 1
fi

ACTUAL_SHA1=$(shasum -a 1 "$TMP" | awk '{print $1}')
if [ "$ACTUAL_SHA1" != "$EXPECT_SHA1" ]; then
    echo "ERROR: sha1 mismatch" >&2
    echo "  expected $EXPECT_SHA1" >&2
    echo "  got      $ACTUAL_SHA1" >&2
    exit 1
fi

read_byte() {
    od -An -v -tu1 -N1 -j"$1" "$TMP" | tr -d ' \n'
}

ACTUAL_VERSION=$(read_byte 0)
ACTUAL_RELEASE=$(( $(read_byte 2) * 256 + $(read_byte 3) ))
ACTUAL_SERIAL=$(dd if="$TMP" bs=1 skip=18 count=6 2>/dev/null)

if [ "$ACTUAL_VERSION" != "3" ]; then
    echo "ERROR: expected Z-machine version 3, got $ACTUAL_VERSION" >&2
    exit 1
fi
if [ "$ACTUAL_RELEASE" != "$RELEASE" ]; then
    echo "ERROR: expected release $RELEASE, got $ACTUAL_RELEASE" >&2
    exit 1
fi
if [ "$ACTUAL_SERIAL" != "$SERIAL" ]; then
    echo "ERROR: expected serial $SERIAL, got $ACTUAL_SERIAL" >&2
    exit 1
fi

echo "Verified $ACTUAL_BYTES bytes, sha1 $ACTUAL_SHA1"
echo "Verified Z-machine v$ACTUAL_VERSION, release $ACTUAL_RELEASE, serial $ACTUAL_SERIAL"
mkdir -p "$(dirname "$OUT")"

{
    echo "-- GENERATED FILE -- do not edit by hand."
    echo "-- $LABEL release $RELEASE / serial $SERIAL (Z-machine v3), numeric chunks."
    echo "-- Source: $URL"
    echo "-- $EXPECT_BYTES bytes, sha1 $EXPECT_SHA1"
    echo "-- Regenerate with tools/bake_zork.sh $TITLE"
    echo "-- Licensed MIT by its copyright holder; see third_party/${REPO}/LICENSE.txt"
    echo ""
    echo "${MODULE} = {}"
    echo "${MODULE}.release = $RELEASE"
    echo "${MODULE}.serial = \"$SERIAL\""
    echo "${MODULE}.length = $EXPECT_BYTES"
    echo "${MODULE}.sha1 = \"$EXPECT_SHA1\""
    echo ""
    echo "local chunks = {}"

    od -An -v -tu1 "$TMP" \
        | tr -s '[:space:]' '\n' \
        | sed '/^$/d' \
        | awk -v per="$BYTES_PER_CHUNK" '
            {
                if (esc != "") esc = esc ","
                esc = esc $1
                n++
                if (n % per == 0) {
                    c++
                    printf "chunks[%d] = {%s}\n", c, esc
                    esc = ""
                }
            }
            END {
                if (esc != "") {
                    c++
                    printf "chunks[%d] = {%s}\n", c, esc
                }
            }
        '

    echo ""
    echo "${MODULE}.chunks = chunks"
} > "$OUT"

echo "Wrote $OUT ($(wc -l < "$OUT" | tr -d ' ') lines)"
