#!/usr/bin/env bash
# Removes VoiceFlow.app. Your models, settings and dictionary stay unless you pass --purge.
#   scripts/uninstall.sh            # quit and remove the app (~/Applications and /Applications)
#   scripts/uninstall.sh --purge    # also delete ~/Library/Application Support/VoiceFlow (models ~1.4 GB+, settings, dictionary)
set -euo pipefail
PURGE=0; [[ "${1:-}" == "--purge" ]] && PURGE=1

if [[ -z "${VOICEFLOW_INSTALL_DIR:-}" ]] && pgrep -x VoiceFlow >/dev/null; then
  osascript -e 'tell application id "local.voiceflow.VoiceFlow" to quit' >/dev/null 2>&1 || true
  sleep 1; pkill -x VoiceFlow 2>/dev/null || true
fi
APPS=("$HOME/Applications/VoiceFlow.app" "/Applications/VoiceFlow.app")
[[ -n "${VOICEFLOW_INSTALL_DIR:-}" ]] && APPS=("$VOICEFLOW_INSTALL_DIR/VoiceFlow.app")
for app in "${APPS[@]}"; do
  if [[ -d "$app" ]]; then
    SUDO=""; [[ -w "$(dirname "$app")" ]] || SUDO="sudo"
    $SUDO rm -rf "$app" && echo "✓ removed $app"
  fi
done

DATA="$HOME/Library/Application Support/VoiceFlow"
if [[ $PURGE == 1 && -d "$DATA" ]]; then
  read -r -p "Delete $DATA ($(du -sh "$DATA" | cut -f1): models, settings, dictionary)? [y/N] " answer
  [[ "$answer" == [yY] ]] && rm -rf "$DATA" && echo "✓ removed $DATA"
fi
echo "Permissions granted to VoiceFlow can be removed in System Settings → Privacy & Security (Microphone, Accessibility, Input Monitoring)."
echo "If Open at Login was on, also remove VoiceFlow from System Settings → General → Login Items if it's still listed."
