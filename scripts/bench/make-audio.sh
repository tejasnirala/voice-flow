#!/usr/bin/env bash
# Generates synthetic 16 kHz mono clips for every synthesizable corpus entry with several macOS
# TTS voices → benchmarks-output/audio/synthetic/<voice>/<id>.wav
#
# Synthetic speech is NOT a substitute for real recordings: it is cleaner, perfectly paced, and its
# pronunciation of technical terms is often unnatural. Use it to validate the pipeline and to
# shortlist; decide on human recordings (scripts/bench/record.sh).
set -euo pipefail
cd "$(dirname "$0")/../.."
CORPUS=benchmarks/corpus/developer-speech.json
VOICES=("Rishi:rishi-en-IN" "Samantha:samantha-en-US" "Daniel:daniel-en-GB")

mkdir -p benchmarks-output
python3 -c '
import json, sys
for e in json.load(open(sys.argv[1]))["entries"]:
    if e["synthesizable"]: print(e["id"] + "\t" + e["spoken"])' "$CORPUS" > benchmarks-output/.spoken.tsv

for pair in "${VOICES[@]}"; do
  voice="${pair%%:*}" label="${pair#*:}"
  if ! say -v '?' | grep -q "^$voice "; then echo "skip voice $voice (not installed)"; continue; fi
  out="benchmarks-output/audio/synthetic/$label"; mkdir -p "$out"
  while IFS=$'\t' read -r id text; do
    [[ -f "$out/$id.wav" ]] || say -v "$voice" -o "$out/$id.wav" --data-format=LEI16@16000 "$text"
  done < benchmarks-output/.spoken.tsv
  echo "✓ $label: $(ls "$out" | wc -l | tr -d ' ') clips"
done
rm -f benchmarks-output/.spoken.tsv
