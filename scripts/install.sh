#!/usr/bin/env bash
# Builds VoiceFlow and installs it for this user. Setup-time only: nothing here runs when you dictate.
#   scripts/install.sh                   # build → ~/Applications/VoiceFlow.app → launch
#   scripts/install.sh --with-models     # also download + verify the default speech model and Neural Engine encoder
#   scripts/install.sh --with-languages  # also German/Hindi/Hinglish: large-v3 (transcription) + large-v3-turbo (detection)
#                                        # with Neural Engine encoders (~4.2 GB)
#   scripts/install.sh --applications    # install to /Applications instead (may ask for your password)
#   scripts/install.sh --no-launch
# Requires: Command Line Tools (swift), scripts/fetch-deps.sh run once (whisper.cpp framework).
set -euo pipefail
cd "$(dirname "$0")/.."

DEST_DIR="${VOICEFLOW_INSTALL_DIR:-$HOME/Applications}"; LAUNCH=1; MODELS=0; LANGUAGES=0
for arg in "$@"; do
  case "$arg" in
    --with-models) MODELS=1 ;;
    --with-languages) LANGUAGES=1 ;;
    --applications) DEST_DIR="/Applications" ;;
    --no-launch) LAUNCH=0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

command -v swift >/dev/null || { echo "✗ swift not found — install the Command Line Tools: xcode-select --install" >&2; exit 1; }
[[ -d Vendor/whisper.xcframework ]] || { echo "↓ whisper.cpp framework missing — running scripts/fetch-deps.sh"; scripts/fetch-deps.sh; }

if [[ $MODELS == 1 ]]; then
  scripts/fetch-models.sh whisper medium.en-q8_0
  scripts/fetch-models.sh whisper-coreml medium.en
fi
if [[ $LANGUAGES == 1 ]]; then
  scripts/fetch-models.sh whisper large-v3-q5_0 large-v3-turbo-q8_0
  scripts/fetch-models.sh whisper-coreml large-v3 large-v3-turbo
fi

scripts/build-app.sh
scripts/test.sh >/dev/null && echo "✓ tests passed"

if pgrep -x VoiceFlow >/dev/null; then
  osascript -e 'tell application id "local.voiceflow.VoiceFlow" to quit' >/dev/null 2>&1 || true
  for _ in $(seq 1 25); do pgrep -x VoiceFlow >/dev/null || break; sleep 0.2; done
  pkill -x VoiceFlow 2>/dev/null || true
fi

mkdir -p "$DEST_DIR"
DEST="$DEST_DIR/VoiceFlow.app"
SUDO=""; [[ -w "$DEST_DIR" ]] || SUDO="sudo"
$SUDO rm -rf "$DEST"
$SUDO ditto build/Products.noindex/VoiceFlow.app "$DEST"
echo "✓ installed $DEST ($(du -sh "$DEST" | cut -f1))"
# Keep Spotlight/Launch Services to the installed copy: forget development builds.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[[ -x "$LSREGISTER" ]] && "$LSREGISTER" -u "$PWD/build/Products.noindex/VoiceFlow.app" >/dev/null 2>&1 || true
mdimport "$DEST" >/dev/null 2>&1 || true

MODEL="$HOME/Library/Application Support/VoiceFlow/models/whisper/ggml-medium.en-q8_0.bin"
[[ -e "$MODEL" ]] || echo "! speech model not installed yet — run: scripts/install.sh --with-models (or scripts/fetch-models.sh whisper medium.en-q8_0)"

cat <<MSG

First run: macOS asks for
  • Microphone (when you first dictate)
  • Input Monitoring (for the ⌥ trigger) and Accessibility (to paste)
If VoiceFlow was allowed before from another location (build/VoiceFlow.app), macOS may list it twice or ask again:
remove the old entry in System Settings → Privacy & Security and allow the installed copy.
Menu bar → Open at Login starts VoiceFlow when you log in.
MSG

[[ $LAUNCH == 1 ]] && open "$DEST"
