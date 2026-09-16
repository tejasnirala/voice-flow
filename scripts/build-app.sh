#!/usr/bin/env bash
# Builds VoiceFlow and assembles build/VoiceFlow.app (no Xcode required).
#   scripts/build-app.sh            # release build
#   scripts/build-app.sh debug      # debug build
# Signing: uses the "VoiceFlow Dev" identity from the login keychain when present
# (stable signature => macOS keeps Microphone/Accessibility grants across rebuilds),
# otherwise ad-hoc (grants may need re-approval after each rebuild).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/VoiceFlow.app"
IDENTITY="${VOICEFLOW_SIGN_IDENTITY:-VoiceFlow Dev}"

swift build -c "$CONFIG" --product VoiceFlow
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/VoiceFlow" "$APP/Contents/MacOS/VoiceFlow"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R prompts "$APP/Contents/Resources/prompts" 2>/dev/null || true

# Embed only the Vendor/ frameworks the executable actually links.
for fw in Vendor/*.xcframework; do
  [[ -e "$fw" ]] || continue
  name="$(basename "$fw" .xcframework)"
  otool -L "$APP/Contents/MacOS/VoiceFlow" | grep -q "@rpath/$name.framework" || continue
  slice="$(find "$fw" -maxdepth 1 -type d -name 'macos-*' | head -1)"
  cp -R "$slice/$name.framework" "$APP/Contents/Frameworks/"
done

if security find-identity -v -p codesigning | grep -q "\"$IDENTITY\""; then
  codesign --force --deep --options runtime --sign "$IDENTITY" "$APP"
  echo "Signed with: $IDENTITY"
else
  codesign --force --deep --sign - "$APP"
  echo "Signed ad-hoc (create a 'VoiceFlow Dev' identity to keep permission grants; see docs/development.md)"
fi

du -sh "$APP" "$APP/Contents/MacOS/VoiceFlow"
