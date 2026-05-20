#!/bin/bash
# One-time Sparkle signing key setup for auto-updates.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SPARKLE_BIN=""
for cand in \
    "$ROOT/.build/artifacts/sparkle/Sparkle/bin" \
    "$ROOT/.build/checkouts/Sparkle/bin"; do
    if [ -x "$cand/generate_keys" ]; then
        SPARKLE_BIN="$cand"
        break
    fi
done

if [ -z "$SPARKLE_BIN" ]; then
    echo "Sparkle tools not found. Run first:"
    echo "  cd $ROOT && swift build -c release"
    exit 1
fi

mkdir -p "$HOME/.sparkle"

echo "=== Sparkle key setup ==="
echo "You may get a Keychain popup — click Allow."
echo ""

if [ ! -f "$HOME/.sparkle/eddsa_pub" ]; then
    "$SPARKLE_BIN/generate_keys"
    "$SPARKLE_BIN/generate_keys" -p > "$HOME/.sparkle/eddsa_pub"
    chmod 600 "$HOME/.sparkle/eddsa_pub"
    echo ""
    echo "Saved public key to ~/.sparkle/eddsa_pub"
else
    echo "Public key already exists at ~/.sparkle/eddsa_pub"
fi

if [ ! -f "$HOME/.sparkle/eddsa_priv" ]; then
    "$SPARKLE_BIN/generate_keys" -x "$HOME/.sparkle/eddsa_priv"
    chmod 600 "$HOME/.sparkle/eddsa_priv"
    echo "Saved private key to ~/.sparkle/eddsa_priv"
else
    echo "Private key already exists at ~/.sparkle/eddsa_priv"
fi

echo ""
echo "Public key for Info.plist:"
cat "$HOME/.sparkle/eddsa_pub"
echo ""
echo "Next — publish a new version with auto-update:"
echo "  bash scripts/publish.sh 1.0.5"
echo ""
