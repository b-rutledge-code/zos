#!/bin/bash
# Wrapper: ./tools/bake_zork.sh 1
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bake_zork.sh" 1 "$@"
