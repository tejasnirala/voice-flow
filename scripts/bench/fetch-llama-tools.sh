#!/usr/bin/env bash
# Fetches official llama.cpp macOS arm64 release binaries (llama-server, llama-bench, …) for the Smart Mode
# benchmark into benchmarks-output/tools/ (gitignored). Benchmark tooling only: VoiceFlow never runs a server.
set -euo pipefail
cd "$(dirname "$0")/../.."
TAG="b11005"
SHA256="c968cb395a4149bf9edfc066ca13d43127fef6304aed8440fdd3546b4610c78c"
DEST="benchmarks-output/tools/llama-$TAG"
if [[ -x "$DEST/llama-server" ]]; then echo "✓ $DEST"; exit 0; fi
mkdir -p benchmarks-output/tools
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
curl -fL --retry 5 -sS -o "$tmp/llama.tgz" "https://github.com/ggml-org/llama.cpp/releases/download/$TAG/llama-$TAG-bin-macos-arm64.tar.gz"
echo "$SHA256  $tmp/llama.tgz" | shasum -a 256 -c - >/dev/null
tar xzf "$tmp/llama.tgz" -C benchmarks-output/tools
echo "✓ $DEST (SHA-256 verified)"
