#!/usr/bin/env bash
# Fetches prebuilt native runtimes into Vendor/ (gitignored), verifying SHA-256.
# Build-time only. Pinned versions and the rationale are recorded in docs/ARCHITECTURE.md §6.
set -euo pipefail
cd "$(dirname "$0")/.."

WHISPER_TAG="b5130"
WHISPER_SHA256="033a43b0174e8cf9b366f72e4a428cdcf126f93ad1c87d3fa119a96bed6f231a"

mkdir -p Vendor
if [[ ! -d Vendor/whisper.xcframework ]]; then
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  curl -fL --retry 5 -o "$tmp/whisper.zip" \
    "https://github.com/ggml-org/whisper.cpp/releases/download/$WHISPER_TAG/whisper-$WHISPER_TAG-xcframework.zip"
  echo "$WHISPER_SHA256  $tmp/whisper.zip" | shasum -a 256 -c -
  unzip -q "$tmp/whisper.zip" -d "$tmp"
  mv "$tmp/build-apple/whisper.xcframework" Vendor/
fi
echo "✓ Vendor/whisper.xcframework ($WHISPER_TAG)"
