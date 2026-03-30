#!/usr/bin/env bash
set -euo pipefail

# Generate all test cases for ekdy

EKDY_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export EKDY_DIR

mkdir -p "$EKDY_DIR/test-resource/html5lib-expectations"

find "$EKDY_DIR/test-resource/html5lib-tests/tree-construction" \
  -maxdepth 1 -type f -name '*.dat' -print0 |
parallel -0 -j8 --env EKDY_DIR '
  f="{}"
  base=$(basename "$f")
  out="$EKDY_DIR/test-resource/html5lib-expectations/${base%.dat}.ekdytest"
  port=$((9000 + {%} - 1))

  echo "[slot {%}] processing $base -> $(basename "$out") on port $port" >&2

  "$EKDY_DIR/scripts/gen_html5lib_tests.py" -p ${port} < "$f" > "$out"
'
