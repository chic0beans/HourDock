#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$HOME/.cargo/env" 2>/dev/null || true

ENT="$ROOT/SteamIdleMac/SteamIdleMac.entitlements"
# GitHub / Sparkle defaults for chic0beans (export SU_FEED_URL before running to override)
if [ -z "${SU_FEED_URL:-}" ] && [ -f "$ROOT/scripts/github-config.sh" ]; then
    # shellcheck source=/dev/null
    source "$ROOT/scripts/github-config.sh"
fi
SU_FEED_URL="${SU_FEED_URL:-https://github.com/chic0beans/HourDock/releases/latest/download/appcast.xml}"
SU_PUBLIC_ED_KEY="${SU_PUBLIC_ED_KEY:-}"

VERSION="${SIM_VERSION:-1.0.4}"
BUILD_NUMBER="${SIM_BUILD:-5}"

echo "==> Building idle-helper"
cd "$ROOT/idle-helper"
cargo build --release
DYLIB_OUT=$(find "$ROOT/idle-helper/target/release/build" -name "libsteam_api.dylib" | head -1)
mkdir -p "$ROOT/ThirdParty"
cp "$DYLIB_OUT" "$ROOT/ThirdParty/libsteam_api.dylib"

echo "==> Ensuring app icon exists"
if [ ! -f "$ROOT/SteamIdleMac/Resources/AppIcon.icns" ]; then
    bash "$ROOT/scripts/make-icon.sh"
fi

echo "==> Building Swift app"
cd "$ROOT"
swift build -c release

APP="$ROOT/build/HourDock.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
mkdir -p "$APP/Contents/Frameworks"

cp "$ROOT/.build/arm64-apple-macosx/release/SteamIdleMac" "$APP/Contents/MacOS/SteamIdleMac"
cp "$ROOT/idle-helper/target/release/idle-helper" "$APP/Contents/MacOS/idle-helper"
cp "$ROOT/ThirdParty/libsteam_api.dylib" "$APP/Contents/MacOS/libsteam_api.dylib"
cp "$ROOT/SteamIdleMac/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Sparkle framework + autoupdate XPCs/binaries
# Prefer the xcframework copy because it contains the full bundle layout including XPC services.
SPARKLE_BUILD_DIR=""
for cand in \
    "$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" \
    "$ROOT/.build/arm64-apple-macosx/release/Sparkle.framework"; do
    if [ -d "$cand" ]; then
        SPARKLE_BUILD_DIR="$cand"
        break
    fi
done

if [ -n "$SPARKLE_BUILD_DIR" ]; then
    echo "==> Embedding Sparkle.framework from $SPARKLE_BUILD_DIR"
    rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
    cp -R "$SPARKLE_BUILD_DIR" "$APP/Contents/Frameworks/Sparkle.framework"
else
    echo "warning: could not find Sparkle.framework — auto-update will be disabled"
fi

chmod +x "$APP/Contents/MacOS/SteamIdleMac" "$APP/Contents/MacOS/idle-helper"

# Ensure main binary can resolve embedded Sparkle.framework via @rpath
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/SteamIdleMac" 2>/dev/null || true
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ -n "$SU_PUBLIC_ED_KEY" ]; then
    SU_PUB_LINE="<key>SUPublicEDKey</key><string>${SU_PUBLIC_ED_KEY}</string>"
else
    SU_PUB_LINE=""
fi

cat > "$APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>SteamIdleMac</string>
	<key>CFBundleIdentifier</key><string>com.steamidlemac.app</string>
	<key>CFBundleName</key><string>HourDock</string>
	<key>CFBundleDisplayName</key><string>HourDock</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>${VERSION}</string>
	<key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>LSMinimumSystemVersion</key><string>13.0</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<key>SUFeedURL</key><string>${SU_FEED_URL}</string>
	${SU_PUB_LINE}
	<key>SUEnableInstallerLauncherService</key><true/>
	<key>SUEnableAutomaticChecks</key><true/>
</dict>
</plist>
PLIST

xattr -cr "$APP" 2>/dev/null || true

# Sign embedded Sparkle XPCs/helpers first (deep)
if [ -d "$APP/Contents/Frameworks/Sparkle.framework" ]; then
    SPARKLE_RES="$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Resources"
    # Sign Autoupdate first
    if [ -f "$SPARKLE_RES/Autoupdate" ]; then
        codesign --force --sign - --options runtime --timestamp=none "$SPARKLE_RES/Autoupdate" || true
    fi
    # Sign Updater.app
    if [ -d "$SPARKLE_RES/Updater.app" ]; then
        codesign --force --sign - --options runtime --timestamp=none --deep "$SPARKLE_RES/Updater.app" || true
    fi
    # Sign XPC services
    for xpc in "$SPARKLE_RES/"*.xpc; do
        if [ -d "$xpc" ]; then
            codesign --force --sign - --options runtime --timestamp=none --deep "$xpc" || true
        fi
    done
    # Sign the framework itself
    codesign --force --sign - --options runtime --timestamp=none "$APP/Contents/Frameworks/Sparkle.framework" || true
fi

codesign --force --sign - --options runtime --entitlements "$ENT" "$APP/Contents/MacOS/libsteam_api.dylib"
codesign --force --sign - --options runtime --entitlements "$ENT" "$APP/Contents/MacOS/idle-helper"
codesign --force --sign - --options runtime --entitlements "$ENT" "$APP/Contents/MacOS/SteamIdleMac"
codesign --force --sign - --options runtime --entitlements "$ENT" "$APP"

echo "Built and signed: $APP"
