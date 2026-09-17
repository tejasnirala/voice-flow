#!/usr/bin/env bash
# Record your own voice for the STT accuracy benchmark.
#   scripts/bench/record.sh <mic-label> [--category technical] [--include-hinglish]
#   scripts/bench/record.sh <mic-label> --hindi   # Phase 14: Hindi sentences (scored as Devanagari and Hinglish)
# e.g. scripts/bench/record.sh macbook-mic      → benchmarks-output/audio/human/macbook-mic/
#      scripts/bench/record.sh macbook-mic --hindi → benchmarks-output/audio/human-hi/macbook-mic/
# Then: scripts/bench/stt.sh human
set -euo pipefail
cd "$(dirname "$0")/../.."
LABEL="${1:?usage: record.sh <mic-label> [--category name] [--include-hinglish]}"; shift
BIN=benchmarks-output/bin/record
mkdir -p "$(dirname "$BIN")"
if [[ ! -x "$BIN" || scripts/bench/record.swift -nt "$BIN" ]]; then
  swiftc -O scripts/bench/record.swift -o "$BIN" 2>&1 | grep -v "ld: warning" || true
fi
if [[ "${1:-}" == "--hindi" ]]; then
  shift
  python3 scripts/bench/make-multilingual-corpora.py >/dev/null
  echo "Hindi set: read each sentence the way you normally speak (English words as English). The Hinglish line is the same sentence."
  "$BIN" --corpus benchmarks-output/corpus-hi-record.json --out "benchmarks-output/audio/human-hi/$LABEL" "$@"
else
  "$BIN" --corpus benchmarks/corpus/developer-speech.json --out "benchmarks-output/audio/human/$LABEL" "$@"
fi
