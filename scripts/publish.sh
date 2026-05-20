#!/bin/bash
# Build and upload a release to GitHub.
# Usage: bash scripts/publish.sh
#        bash scripts/publish.sh 1.0.5
set -euo pipefail

export PATH="$HOME/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

GITHUB_USER="chic0beans"
GITHUB_REPO="HourDock"
GITHUB_RELEASES_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}/releases"
GITHUB_LATEST_DMG_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}/releases/latest/download/HourDock.dmg"
SU_FEED_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}/releases/latest/download/appcast.xml"

VERSION="${1:-1.0.4}"

if ! command -v gh >/dev/null 2>&1; then
    echo "Run first: bash scripts/install-tools.sh"
    echo "Then:      gh auth login"
    exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
    echo "Not logged in. Run: gh auth login"
    exit 1
fi

if [ -f "$HOME/.sparkle/eddsa_pub" ]; then
    export SU_PUBLIC_ED_KEY="$(cat "$HOME/.sparkle/eddsa_pub")"
fi
if [ -f "$HOME/.sparkle/eddsa_priv" ]; then
    export SPARKLE_PRIVATE_KEY="$(cat "$HOME/.sparkle/eddsa_priv")"
fi

export SU_FEED_URL
export SIM_VERSION="$VERSION"
export SIM_BUILD="$(date +%s)"

echo ""
echo "=== Publishing HourDock v${VERSION} ==="
echo ""

bash "$ROOT/scripts/build-app.sh"
bash "$ROOT/scripts/make-dmg.sh"

DMG_VERSIONED="$ROOT/build/HourDock-${VERSION}.dmg"
DMG_LATEST="$ROOT/build/HourDock.dmg"

if [ ! -f "$DMG_VERSIONED" ]; then
    echo "Error: DMG not found at $DMG_VERSIONED"
    exit 1
fi

cp "$DMG_VERSIONED" "$DMG_LATEST"

sparkle_bin_dir() {
    for cand in         "$ROOT/.build/artifacts/sparkle/Sparkle/bin"         "$ROOT/.build/checkouts/Sparkle/bin"; do
        if [ -x "$cand/generate_appcast" ]; then
            echo "$cand"
            return 0
        fi
    done
    find "$ROOT/.build" -type f -name generate_appcast 2>/dev/null | head -1 | xargs dirname 2>/dev/null || true
}

APPCAST=""
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
    UPDATES_DIR="$ROOT/build/updates"
    mkdir -p "$UPDATES_DIR"
    rm -f "$UPDATES_DIR/"*.dmg "$UPDATES_DIR/appcast.xml"
    cp "$DMG_VERSIONED" "$UPDATES_DIR/"
    SPARKLE_DIR=$(sparkle_bin_dir || true)
    GEN_TOOL=""
    [ -n "$SPARKLE_DIR" ] && GEN_TOOL="$SPARKLE_DIR/generate_appcast"
    if [ -n "$GEN_TOOL" ] && [ -x "$GEN_TOOL" ]; then
        printf "%s" "$SPARKLE_PRIVATE_KEY" | "$GEN_TOOL" --ed-key-file - "$UPDATES_DIR"
        if [ -f "$UPDATES_DIR/appcast.xml" ]; then
            APPCAST="$UPDATES_DIR/appcast.xml"
        else
            echo "Error: appcast generation failed."
            exit 1
        fi
    fi
fi

TAG="v${VERSION}"
if gh release view "$TAG" >/dev/null 2>&1; then
    echo "Release $TAG exists — updating files..."
    gh release upload "$TAG" "$DMG_VERSIONED" "$DMG_LATEST" --clobber
    [ -n "$APPCAST" ] && gh release upload "$TAG" "$APPCAST" --clobber
else
    FILES=("$DMG_VERSIONED" "$DMG_LATEST")
    [ -n "$APPCAST" ] && FILES+=("$APPCAST")
    gh release create "$TAG" \
        --title "HourDock ${VERSION}" \
        --notes "Download HourDock.dmg, open it, drag the app to Applications. First launch: right-click -> Open." \
        "${FILES[@]}"
fi

echo ""
echo "Published!"
echo "  Share:    ${GITHUB_RELEASES_URL}"
echo "  Download: ${GITHUB_LATEST_DMG_URL}"
echo ""
