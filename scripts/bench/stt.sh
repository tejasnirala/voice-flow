#!/usr/bin/env bash
# STT benchmark: whisper.cpp (tiny/base/small, Metal and CPU) + Apple SpeechTranscriber.
#   scripts/fetch-deps.sh && scripts/fetch-models.sh whisper tiny.en base.en small.en
#   scripts/bench/make-audio.sh && scripts/bench/stt.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
FW="$(pwd)/Vendor/whisper.xcframework/macos-arm64_x86_64"
BIN=benchmarks-output/bin; mkdir -p "$BIN"
A=benchmarks-output/audio; CLIPS=("$A/short.wav" "$A/medium.wav" "$A/developer.wav" "$A/long.wav")
M="$HOME/Library/Application Support/VoiceFlow/models/whisper"

swiftc -O -F "$FW" -framework whisper scripts/bench/whisper_bench.swift -o "$BIN/whisper_bench" -Xlinker -rpath -Xlinker "$FW"
swiftc -O scripts/bench/apple_speech_bench.swift -o "$BIN/apple_speech_bench"

for model in tiny.en base.en small.en; do
  [[ -f "$M/ggml-$model.bin" ]] || { echo "skip $model (not downloaded)"; continue; }
  for backend in gpu cpu; do "$BIN/whisper_bench" "$M/ggml-$model.bin" "$backend" "${CLIPS[@]}"; done
done
"$BIN/apple_speech_bench" en-US "${CLIPS[@]}"
