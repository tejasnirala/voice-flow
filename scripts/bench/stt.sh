#!/usr/bin/env bash
# STT accuracy + performance benchmark over the developer-speech corpus.
#
#   scripts/bench/stt.sh [synthetic|human|cpu-sample] [run-name-filter-regex]
#
# CPU-backend runs ("-cpu") are slow for large models (a large-v3-turbo clip takes tens of seconds), so
# they only run on the `cpu-sample` set: 5 representative Rishi clips. The Metal runs cover the same clips,
# so the two can be compared per clip.
#
# Prereqs: scripts/fetch-deps.sh; models via scripts/fetch-models.sh; audio via
# scripts/bench/make-audio.sh (synthetic) or scripts/bench/record.sh (human).
# Output: benchmarks-output/results/<set>/*.jsonl and a markdown report on stdout
# (also saved as benchmarks-output/results/<set>/report.md). Missing models are skipped.
# Completed runs are reused (resume after interruption); FORCE=1 reruns everything.
set -euo pipefail
cd "$(dirname "$0")/../.."

SET="${1:-synthetic}"
FILTER="${2:-.}"
M="$HOME/Library/Application Support/VoiceFlow/models"
FW="$(pwd)/Vendor/whisper.xcframework/macos-arm64_x86_64"
BIN=benchmarks-output/bin/stt_engines
CORPUS=benchmarks/corpus/developer-speech.json
VOCAB=benchmarks/vocabulary.txt
OUT="benchmarks-output/results/$SET"
mkdir -p "$(dirname "$BIN")" "$OUT"

[[ -d "$FW" ]] || { echo "missing Vendor/whisper.xcframework — run scripts/fetch-deps.sh" >&2; exit 1; }
if [[ ! -x "$BIN" || scripts/bench/stt_engines.swift -nt "$BIN" ]]; then
  swiftc -O -F "$FW" -framework whisper scripts/bench/stt_engines.swift -o "$BIN" -Xlinker -rpath -Xlinker "$FW" 2>&1 | grep -v "ld: warning" || true
fi

# run name | engine | model (path or locale) | backend | prompt/vocabulary file
CONFIGS=(
  "whisper-small.en|whisper|$M/whisper/ggml-small.en.bin|metal|"
  "whisper-medium.en-q8_0|whisper|$M/whisper/ggml-medium.en-q8_0.bin|metal|"
  "whisper-large-v3-turbo|whisper|$M/whisper/ggml-large-v3-turbo.bin|metal|"
  "whisper-large-v3-turbo-q8_0|whisper|$M/whisper/ggml-large-v3-turbo-q8_0.bin|metal|"
  "whisper-large-v3-turbo-q8_0+vocab|whisper|$M/whisper/ggml-large-v3-turbo-q8_0.bin|metal|$VOCAB"
  "whisper-large-v3-turbo-q8_0-cpu|whisper|$M/whisper/ggml-large-v3-turbo-q8_0.bin|cpu|"
  "whisper-distil-large-v3|whisper|$M/whisper/ggml-distil-large-v3.bin|metal|"
  "parakeet-tdt-0.6b-v3-q8_0|parakeet|$M/parakeet/ggml-parakeet-tdt-0.6b-v3-q8_0.bin|metal|"
  "parakeet-tdt-0.6b-v3-q8_0-cpu|parakeet|$M/parakeet/ggml-parakeet-tdt-0.6b-v3-q8_0.bin|cpu|"
  "apple-speech-en-US|apple|en-US|os|"
  "apple-speech-en-IN|apple|en-IN|os|"
  "apple-speech-en-US+vocab|apple|en-US|os|$VOCAB"
)

case "$SET" in
  synthetic)  AUDIO_DIRS=(benchmarks-output/audio/synthetic/*/) ;;
  human)      AUDIO_DIRS=(benchmarks-output/audio/human/*/) ;;
  cpu-sample)
    SAMPLE=benchmarks-output/audio/cpu-sample/rishi-en-IN; mkdir -p "$SAMPLE"
    for id in normal-01 technical-03 identifiers-01 commands-01 natural-01; do
      ln -sf "$(pwd)/benchmarks-output/audio/synthetic/rishi-en-IN/$id.wav" "$SAMPLE/$id.wav"
    done
    AUDIO_DIRS=("$SAMPLE/") ;;
  *) echo "unknown set: $SET" >&2; exit 1 ;;
esac

for cfg in "${CONFIGS[@]}"; do
  IFS='|' read -r run engine model backend vocab <<< "$cfg"
  [[ "$run" =~ $FILTER ]] || continue
  case "$SET:$backend" in cpu-sample:cpu) ;; cpu-sample:*) continue ;; *:cpu) continue ;; esac
  if [[ "$engine" != apple && ! -f "$model" ]]; then echo "skip $run (model not downloaded)"; continue; fi
  for dir in "${AUDIO_DIRS[@]}"; do
    [[ -d "$dir" ]] || continue
    voice="$(basename "$dir")"
    result="$OUT/${run}__${voice}.jsonl"
    # Resume: a result file ending in its run summary line is complete.
    if [[ -z "${FORCE:-}" && -f "$result" ]] && grep -q '"type":"run"' "$result"; then
      echo "done $run [$voice] (cached; FORCE=1 to rerun)"; continue
    fi
    args=(--engine "$engine" --model "$model" --backend "$backend" --corpus "$CORPUS"
          --audio-dir "$dir" --voice "$voice" --run "$run" --out "$result")
    [[ -n "$vocab" ]] && args+=(--prompt-file "$vocab")
    "$BIN" "${args[@]}"
  done
done

swift build -c release --product vf-bench 2>&1 | grep -E "error" || true
"$(swift build -c release --show-bin-path)/vf-bench" score "$CORPUS" "$OUT"/*.jsonl --errors > "$OUT/report.md"
awk '/^## Errors/{exit} {print}' "$OUT/report.md"
echo "Full report with per-clip errors: $OUT/report.md"
