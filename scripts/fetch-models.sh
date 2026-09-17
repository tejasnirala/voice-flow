#!/usr/bin/env bash
# Downloads model files into ~/Library/Application Support/VoiceFlow/models/ and verifies
# each file's SHA-256 against the Hugging Face LFS metadata.
# Setup-time only — VoiceFlow never touches the network at runtime. Re-run to resume.
#
#   scripts/fetch-models.sh whisper small.en medium.en-q8_0 large-v3-turbo large-v3-turbo-q8_0
#   scripts/fetch-models.sh whisper distil-large-v3
#   scripts/fetch-models.sh parakeet tdt-0.6b-v3-q8_0
#   scripts/fetch-models.sh whisper-coreml medium.en     # Core ML encoder (Neural Engine) for the default model
#   scripts/fetch-models.sh llm qwen2.5-1.5b-instruct-q4_k_m
set -euo pipefail

ROOT="$HOME/Library/Application Support/VoiceFlow/models"
KIND="${1:?usage: fetch-models.sh whisper|parakeet|llm <name>...}"; shift

expected_sha() { # repo file
  curl -fsSL "https://huggingface.co/api/models/$1/tree/main" | python3 -c '
import json, sys
name = sys.argv[1]
for f in json.load(sys.stdin):
    if f["path"] == name and "lfs" in f:
        print(f["lfs"]["oid"]); break' "$2"
}

fetch() { # repo file destdir
  local repo="$1" file="$2" dir="$3" dest="$3/$2"
  mkdir -p "$dir"
  local sha; sha="$(expected_sha "$repo" "$file")"
  [[ -n "$sha" ]] || { echo "✗ $file not found in $repo" >&2; return 1; }
  if [[ -f "$dest" ]]; then
    if echo "$sha  $dest" | shasum -a 256 -c - >/dev/null 2>&1; then echo "✓ $file (present, verified)"; return; fi
    echo "! $file checksum mismatch — re-downloading"; rm -f "$dest"
  fi
  echo "↓ $file"
  curl -fL --retry 5 --retry-delay 2 --speed-limit 10000 --speed-time 30 -sS \
       -C - -o "$dest.part" "https://huggingface.co/$repo/resolve/main/$file"
  echo "$sha  $dest.part" | shasum -a 256 -c - >/dev/null || { echo "✗ $file checksum mismatch" >&2; rm -f "$dest.part"; return 1; }
  mv "$dest.part" "$dest"
  echo "✓ $file $(du -h "$dest" | cut -f1) (verified)"
}

for m in "$@"; do
  case "$KIND:$m" in
    whisper:distil-*)   fetch "distil-whisper/$m-ggml" "ggml-$m.bin" "$ROOT/whisper" ;;
    whisper:*)          fetch "ggerganov/whisper.cpp" "ggml-$m.bin" "$ROOT/whisper" ;;
    parakeet:*)         fetch "ggml-org/parakeet-GGUF" "ggml-parakeet-$m.bin" "$ROOT/parakeet" ;;
    whisper-coreml:*)
      # Core ML encoder (runs Whisper's encoder on the Neural Engine; ~25% faster, same accuracy: ACCURACY.md §5.10).
      # Installed next to the models: whisper.cpp uses it automatically. The first load compiles it (~7 s, once).
      dir="$ROOT/whisper/ggml-$m-encoder.mlmodelc"
      if [[ -d "$dir" ]]; then echo "✓ ggml-$m-encoder.mlmodelc (present)"; continue; fi
      fetch "ggerganov/whisper.cpp" "ggml-$m-encoder.mlmodelc.zip" "$ROOT/whisper"
      unzip -q "$ROOT/whisper/ggml-$m-encoder.mlmodelc.zip" -d "$ROOT/whisper"
      rm -f "$ROOT/whisper/ggml-$m-encoder.mlmodelc.zip"
      echo "✓ installed ggml-$m-encoder.mlmodelc" ;;
    llm:qwen2.5-0.5b-instruct-q4_k_m) fetch "Qwen/Qwen2.5-0.5B-Instruct-GGUF" "$m.gguf" "$ROOT/llm" ;;
    llm:qwen2.5-1.5b-instruct-q4_k_m) fetch "Qwen/Qwen2.5-1.5B-Instruct-GGUF" "$m.gguf" "$ROOT/llm" ;;
    llm:qwen2.5-3b-instruct-q4_k_m)   fetch "Qwen/Qwen2.5-3B-Instruct-GGUF" "$m.gguf" "$ROOT/llm" ;;
    llm:gemma-3-1b-it-Q4_K_M)         fetch "unsloth/gemma-3-1b-it-GGUF" "$m.gguf" "$ROOT/llm" ;;
    llm:Llama-3.2-1B-Instruct-Q4_K_M) fetch "bartowski/Llama-3.2-1B-Instruct-GGUF" "$m.gguf" "$ROOT/llm" ;;
    *) echo "unknown model: $KIND $m" >&2; exit 1 ;;
  esac
done
