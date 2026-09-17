#!/usr/bin/env bash
# Phase 14: synthetic 16 kHz clips for the multilingual corpus (shortlisting only; decisions use human recordings).
#   → benchmarks-output/audio/synthetic-de/<voice>/<id>.wav, benchmarks-output/audio/synthetic-hi/lekha/<id>.wav
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 scripts/bench/make-multilingual-corpora.py >/dev/null
speak() { # voice label corpus
  local out="benchmarks-output/audio/$3/$2"; mkdir -p "$out"
  python3 -c 'import json,sys
for e in json.load(open(sys.argv[1]))["entries"]: print(e["id"] + "\t" + e["spoken"])' "benchmarks-output/$4" |
  while IFS=$'\t' read -r id text; do
    [[ -f "$out/$id.wav" ]] || say -v "$1" -o "$out/$id.wav" --data-format=LEI16@16000 "$text"
  done
  echo "✓ $3/$2: $(ls "$out" | wc -l | tr -d ' ') clips"
}
speak "Anna" anna-de synthetic-de corpus-de.json
speak "Flo (German (Germany))" flo-de synthetic-de corpus-de.json
speak "Sandy (German (Germany))" sandy-de synthetic-de corpus-de.json
speak "Lekha" lekha-hi synthetic-hi corpus-hi-devanagari.json
