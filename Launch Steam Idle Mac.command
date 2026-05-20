#!/bin/bash
APP="$(cd "$(dirname "$0")" && pwd)/build/SteamIdleMac.app"
if [[ ! -d "$APP" ]]; then
  osascript -e 'display alert "HourDock" message "App not found. Build it first with: bash scripts/build-app.sh"'
  exit 1
fi
xattr -cr "$APP" 2>/dev/null || true
pkill -x SteamIdleMac 2>/dev/null || true
open -n "$APP"
