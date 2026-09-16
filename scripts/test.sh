#!/usr/bin/env bash
# Runs unit tests. With only the Command Line Tools installed, SwiftPM does not
# search the subdirectory holding the Swift Testing macro plugin, so pass it in.
set -euo pipefail
cd "$(dirname "$0")/.."
PLUGIN_DIR="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
if [[ -d "$PLUGIN_DIR" ]]; then
  exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGIN_DIR" "$@"
fi
exec swift test "$@"
