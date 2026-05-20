#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

APP="$ROOT/build/SteamIdleMac.app"
if [ ! -d "$APP" ]; then
    echo "Building app first..."
    bash "$ROOT/scripts/build-app.sh"
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
OUT_DIR="$ROOT/build"
DMG_PATH="$OUT_DIR/SteamIdleMac-${VERSION}.dmg"
mkdir -p "$OUT_DIR"
rm -f "$DMG_PATH"

make_dmg_hdiutil() {
    echo "==> Creating DMG with hdiutil..."
    STAGE=$(mktemp -d)
    cp -R "$APP" "$STAGE/SteamIdleMac.app"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "HourDock ${VERSION}" -srcfolder "$STAGE" -ov -format UDZO "$DMG_PATH" >/dev/null
    rm -rf "$STAGE"
}

if ! command -v create-dmg >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
        echo "==> Installing create-dmg..."
        brew install create-dmg
    else
        make_dmg_hdiutil
        echo "Built: $DMG_PATH"
        exit 0
    fi
fi

BG_PNG="$ROOT/scripts/dmg-background.png"
if [ ! -f "$BG_PNG" ]; then
    swift "$ROOT/scripts/generate-dmg-background.swift" "$BG_PNG" 2>/dev/null || true
fi

echo "==> Creating DMG with create-dmg..."
DMG_ARGS=(
    --volname "HourDock ${VERSION}"
    --window-pos 200 120
    --window-size 640 400
    --icon-size 128
    --icon "SteamIdleMac.app" 160 200
    --app-drop-link 480 200
    --hide-extension "SteamIdleMac.app"
)
if [ -f "$BG_PNG" ]; then
    DMG_ARGS+=(--background "$BG_PNG")
fi
DMG_ARGS+=("$DMG_PATH" "$APP")

create-dmg "${DMG_ARGS[@]}"

echo "Built: $DMG_PATH"
