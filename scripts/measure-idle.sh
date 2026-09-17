#!/usr/bin/env bash
# Measures startup time and idle resource use of build/VoiceFlow.app, then quits it.
#   scripts/build-app.sh && scripts/measure-idle.sh [idle-seconds=60]
#
# Startup: the app logs its own launch time, from kernel process creation to
# applicationDidFinishLaunching. Also reported: wall time from `open` until that log line.
# Idle: after a 5 s settle, over the sample window:
#   CPU   = process CPU-time delta ÷ window (ps)
#   Wakeups = idle wakeups over the window (top) — non-zero rates reveal timers/polling
#   GPU   = per-process Metal GPU time delta (ioreg AGXDeviceUserClient; 0 if no GPU client exists)
#   Memory = phys_footprint (footprint), RSS (ps)
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/VoiceFlow.app
WINDOW="${1:-60}"
[[ -d "$APP" ]] || { echo "missing $APP — run scripts/build-app.sh" >&2; exit 1; }
if pgrep -x VoiceFlow >/dev/null; then echo "VoiceFlow is already running; quit it first" >&2; exit 1; fi

now_ms() { python3 -c 'import time; print(int(time.time()*1000))'; }
cpu_seconds() { ps -o time= -p "$1" | awk -F'[:.]' '{ if (NF==3) print $1*60+$2+$3/100; else print $1*3600+$2*60+$3+$4/100 }'; }
gpu_ns() {
  ioreg -r -c AGXDeviceUserClient -a | python3 -c '
import plistlib, sys
pid = sys.argv[1]
try: clients = plistlib.loads(sys.stdin.buffer.read())
except Exception: clients = []
total = 0
for c in clients:
    if str(c.get("IOUserClientCreator", "")).startswith(f"pid {pid},"):
        total += sum(u.get("accumulatedGPUTime", 0) for u in c.get("AppUsage", []))
print(total)' "$1"
}

t_open=$(now_ms)
open "$APP"
pid=""
for _ in $(seq 1 100); do pid=$(pgrep -x VoiceFlow || true); [[ -n "$pid" ]] && break; sleep 0.05; done
[[ -n "$pid" ]] || { echo "VoiceFlow did not start" >&2; exit 1; }

launch_line=""
for _ in $(seq 1 40); do
  launch_line=$(log show --last 1m --style compact \
    --predicate "subsystem == \"local.voiceflow.VoiceFlow\" AND category == \"lifecycle\" AND processIdentifier == $pid" 2>/dev/null \
    | grep -o 'launched in [0-9.]* ms' | tail -1 || true)
  [[ -n "$launch_line" ]] && break
  sleep 0.25
done
t_logged=$(now_ms)

sleep 5
cpu0=$(cpu_seconds "$pid"); gpu0=$(gpu_ns "$pid")
top_out=$(top -l 2 -s "$WINDOW" -pid "$pid" -stats pid,idlew,power | tail -1)
cpu1=$(cpu_seconds "$pid"); gpu1=$(gpu_ns "$pid")
footprint_mb=$(footprint "$pid" 2>/dev/null | awk '/phys_footprint:/ {print $2, $3; exit}')
rss_mb=$(ps -o rss= -p "$pid" | awk '{printf "%.1f MB", $1/1024}')

t_quit=$(now_ms)
osascript -e 'tell application id "local.voiceflow.VoiceFlow" to quit' >/dev/null 2>&1 || kill "$pid"
for _ in $(seq 1 100); do kill -0 "$pid" 2>/dev/null || break; sleep 0.05; done
if kill -0 "$pid" 2>/dev/null; then quit_result="did NOT exit within 5 s"; else quit_result="exited in $(( $(now_ms) - t_quit )) ms"; fi

idle_wakeups=$(echo "$top_out" | awk '{print $2}')
echo "VoiceFlow idle measurement — $(date '+%Y-%m-%d %H:%M'), $(sw_vers -productVersion), pid $pid"
echo "  Launch (kernel start → didFinishLaunching): ${launch_line#launched in } (app log)"
echo "  open → launch log line visible:             $(( t_logged - t_open )) ms (includes log query latency)"
echo "  Idle window:                                ${WINDOW} s (after 5 s settle)"
echo "  CPU:                                        $(python3 -c "print(f'{($cpu1-$cpu0):.2f} s CPU time = {($cpu1-$cpu0)/$WINDOW*100:.3f} %')")"
echo "  Idle wakeups (top, window):                 ${idle_wakeups}"
echo "  GPU time:                                   $(python3 -c "print(f'{($gpu1-$gpu0)/1e6:.3f} ms')")"
echo "  Physical footprint:                         ${footprint_mb}"
echo "  RSS:                                        ${rss_mb}"
echo "  Quit:                                       ${quit_result}"
