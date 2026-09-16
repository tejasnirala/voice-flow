#!/usr/bin/env bash
# Downloads model files into ~/Library/Application Support/VoiceFlow/models/.
# Setup-time only — VoiceFlow never touches the network at runtime.
# Resumable (re-run to continue an interrupted download).
#   scripts/fetch-models.sh whisper tiny.en base.en small.en
#   scripts/fetch-models.sh llm qwen2.5-1.5b-instruct-q4_k_m
set -euo pipefail

ROOT="$HOME/Library/Application Support/VoiceFlow/models"
KIND="${1:?usage: fetch-models.sh whisper|llm <name>...}"; shift

fetch() { # url dest
  local url="$1" dest="$2"
  if [[ -f "$dest" ]]; then echo "✓ $(basename "$dest") (present)"; return; fi
  echo "↓ $(basename "$dest")"
  curl -fL --retry 5 --retry-delay 2 --speed-limit 10000 --speed-time 30 \
       -C - -o "$dest.part" "$url"
  mv "$dest.part" "$dest"
  echo "✓ $(basename "$dest") $(du -h "$dest" | cut -f1)"
}

case "$KIND" in
  whisper)
    mkdir -p "$ROOT/whisper"
    for m in "$@"; do
      fetch "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$m.bin" "$ROOT/whisper/ggml-$m.bin"
    done ;;
  llm)
    mkdir -p "$ROOT/llm"
    for m in "$@"; do
      case "$m" in
        qwen2.5-0.5b-instruct-q4_k_m) repo="Qwen/Qwen2.5-0.5B-Instruct-GGUF" ;;
        qwen2.5-1.5b-instruct-q4_k_m) repo="Qwen/Qwen2.5-1.5B-Instruct-GGUF" ;;
        *) echo "unknown llm model: $m" >&2; exit 1 ;;
      esac
      fetch "https://huggingface.co/$repo/resolve/main/$m.gguf" "$ROOT/llm/$m.gguf"
    done ;;
  *) echo "unknown kind: $KIND" >&2; exit 1 ;;
esac
