#!/usr/bin/env bash
# Record your own voice for the STT accuracy benchmark.
#   scripts/bench/record.sh <mic-label> [--category technical] [--include-hinglish]
# e.g. scripts/bench/record.sh macbook-mic      → benchmarks-output/audio/human/macbook-mic/
# Then: scripts/bench/stt.sh human
set -euo pipefail
cd "$(dirname "$0")/../.."
LABEL="${1:?usage: record.sh <mic-label> [--category name] [--include-hinglish]}"; shift
BIN=benchmarks-output/bin/record
mkdir -p "$(dirname "$BIN")"
if [[ ! -x "$BIN" || scripts/bench/record.swift -nt "$BIN" ]]; then
  swiftc -O scripts/bench/record.swift -o "$BIN" 2>&1 | grep -v "ld: warning" || true
fi
"$BIN" --corpus benchmarks/corpus/developer-speech.json --out "benchmarks-output/audio/human/$LABEL" "$@"
