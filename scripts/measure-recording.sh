#!/usr/bin/env bash
# Records N seconds through the real app pipeline (without the hotkey) and prints the recording metrics:
# engine start time, press → first audio buffer, leading digital silence, levels, speech detection,
# CPU time and memory footprint during the recording.
#   scripts/build-app.sh && scripts/measure-recording.sh [seconds=3] [runs=1] [extra app flags…]
# Extra flags: --fresh-engine (rebuild AVAudioEngine per recording), --stay (keep running afterwards).
# All runs happen in one app process (the first run is cold). Speak or stay silent as the test requires.
set -euo pipefail
cd "$(dirname "$0")/.."
SECONDS_TO_RECORD="${1:-3}"
RUNS="${2:-1}"
shift $(( $# < 2 ? $# : 2 ))
EXTRA=("$@")
APP=build/VoiceFlow.app
[[ -d "$APP" ]] || { echo "missing $APP — run scripts/build-app.sh" >&2; exit 1; }
if pgrep -x VoiceFlow >/dev/null; then
  osascript -e 'tell application id "local.voiceflow.VoiceFlow" to quit' >/dev/null 2>&1 || pkill -x VoiceFlow
  sleep 1
fi

start="$(date '+%Y-%m-%d %H:%M:%S')"
echo "recording ${RUNS} × ${SECONDS_TO_RECORD}s ${EXTRA[*]:-}…"
open "$APP" --args --measure-recording "$SECONDS_TO_RECORD" --runs "$RUNS" ${EXTRA[@]+"${EXTRA[@]}"}
if [[ " ${EXTRA[*]:-} " == *" --stay "* ]]; then
  sleep $(( RUNS * (${SECONDS_TO_RECORD%.*} + 2) + 3 ))
else
  sleep 1
  while pgrep -x VoiceFlow >/dev/null; do sleep 0.2; done
  sleep 1
fi
/usr/bin/log show --start "$start" --style compact \
  --predicate 'subsystem == "local.voiceflow.VoiceFlow" AND category IN {"audio", "lifecycle"}' \
  | grep -v '^Timestamp' | sed -E 's/^[0-9-]+ ([0-9:.]+) [^]]*\] /  \1 /'
