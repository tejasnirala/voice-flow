#!/usr/bin/env bash
# Phase 14: multilingual STT shortlist and language-detection benchmark.
#   scripts/bench/stt-multilingual.sh [synthetic|human-hi] [run-filter-regex]
# Results: benchmarks-output/results/multilingual-<set>/*.jsonl (cached; FORCE=1 reruns).
set -euo pipefail
cd "$(dirname "$0")/../.."
SET="${1:-synthetic}"; FILTER="${2:-.}"
M="$HOME/Library/Application Support/VoiceFlow/models"
BIN=benchmarks-output/bin/stt_engines
OUT="benchmarks-output/results/multilingual-$SET"; mkdir -p "$OUT"
python3 scripts/bench/make-multilingual-corpora.py >/dev/null
P=benchmarks/prompts

run() { # name engine model language prompt corpus audio-dir voice
  local name="$1" file="$OUT/${1}__${8}.jsonl"
  [[ "$name" =~ $FILTER ]] || return 0
  [[ -s "$file" && -z "${FORCE:-}" ]] && return 0
  # Apple SpeechTranscriber needs a one-time system download per locale that can wait indefinitely for approval: opt in.
  [[ "$2" != apple || -n "${APPLE:-}" ]] || return 0
  [[ "$2" == apple || -e "$3" ]] || { echo "skip $name (no model)"; return 0; }
  local args=(--engine "$2" --model "$3" --language "$4" --run "$name" --corpus "$6" --audio-dir "$7" --voice "$8" --out "$file")
  [[ -n "$5" ]] && args+=(--prompt-file "$5")
  "$BIN" "${args[@]}" || { echo "✗ $name failed"; rm -f "$file"; }
}

W="$M/whisper"
if [[ "$SET" == synthetic ]]; then
  for voice in anna-de flo-de sandy-de; do
    A="benchmarks-output/audio/synthetic-de/$voice"; C=benchmarks-output/corpus-de.json
    run de-large-v3-turbo-q8_0 whisper "$W/ggml-large-v3-turbo-q8_0.bin" de "" $C $A $voice
    run de-large-v3-turbo-q8_0+prompt whisper "$W/ggml-large-v3-turbo-q8_0.bin" de $P/de.txt $C $A $voice
    run de-large-v3-turbo whisper "$W/ggml-large-v3-turbo.bin" de "" $C $A $voice
    run de-large-v3-q5_0 whisper "$W/ggml-large-v3-q5_0.bin" de "" $C $A $voice
    run de-large-v3-q5_0+prompt whisper "$W/ggml-large-v3-q5_0.bin" de $P/de.txt $C $A $voice
    run de-medium-q8_0 whisper "$W/ggml-medium-q8_0.bin" de "" $C $A $voice
    run de-medium-q8_0+prompt whisper "$W/ggml-medium-q8_0.bin" de $P/de.txt $C $A $voice
    run de-parakeet-tdt-0.6b-v3 parakeet "$M/parakeet/ggml-parakeet-tdt-0.6b-v3-q8_0.bin" de "" $C $A $voice
    run de-apple-speech apple de_DE de "" $C $A $voice
  done
fi
if [[ "$SET" == synthetic || "$SET" == human-hi ]]; then
  if [[ "$SET" == synthetic ]]; then A=benchmarks-output/audio/synthetic-hi/lekha-hi; V=lekha-hi; else V="${VOICE:-macbook-mic}"; A="benchmarks-output/audio/human-hi/$V"; fi
  C=benchmarks-output/corpus-hi-devanagari.json
  run hi-large-v3-turbo-q8_0 whisper "$W/ggml-large-v3-turbo-q8_0.bin" hi "" $C $A $V
  run hi-large-v3-turbo-q8_0+prompt-dev whisper "$W/ggml-large-v3-turbo-q8_0.bin" hi $P/hi-devanagari.txt $C $A $V
  run hi-large-v3-turbo-q8_0+prompt-hinglish whisper "$W/ggml-large-v3-turbo-q8_0.bin" hi $P/hinglish.txt $C $A $V
  run hi-large-v3-turbo-q8_0-as-en+prompt-hinglish whisper "$W/ggml-large-v3-turbo-q8_0.bin" en $P/hinglish.txt $C $A $V
  run hi-large-v3-turbo whisper "$W/ggml-large-v3-turbo.bin" hi $P/hi-devanagari.txt $C $A $V
  run hi-large-v3-q5_0 whisper "$W/ggml-large-v3-q5_0.bin" hi "" $C $A $V
  run hi-large-v3-q5_0+prompt-dev whisper "$W/ggml-large-v3-q5_0.bin" hi $P/hi-devanagari.txt $C $A $V
  run hi-large-v3-q5_0+prompt-hinglish whisper "$W/ggml-large-v3-q5_0.bin" hi $P/hinglish.txt $C $A $V
  run hi-medium-q8_0 whisper "$W/ggml-medium-q8_0.bin" hi "" $C $A $V
  run hi-medium-q8_0+prompt-dev whisper "$W/ggml-medium-q8_0.bin" hi $P/hi-devanagari.txt $C $A $V
  run hi-apple-speech apple hi_IN hi "" $C $A $V
fi
if [[ "$SET" == synthetic ]]; then
  # Language detection among en/de/hi (auto3) on the owner's English recordings, German and Hindi synthetic speech.
  for model in large-v3-turbo-q8_0 medium-q8_0 large-v3-q5_0; do
    run detect-$model whisper "$W/ggml-$model.bin" auto3 "" benchmarks/corpus/developer-speech.json benchmarks-output/audio/human/macbook-mic owner-en
    run detect-$model whisper "$W/ggml-$model.bin" auto3 "" benchmarks-output/corpus-de.json benchmarks-output/audio/synthetic-de/anna-de anna-de
    run detect-$model whisper "$W/ggml-$model.bin" auto3 "" benchmarks-output/corpus-hi-devanagari.json benchmarks-output/audio/synthetic-hi/lekha-hi lekha-hi
  done
fi
echo "done: $OUT"
