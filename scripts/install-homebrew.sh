#!/bin/bash
# One-time Homebrew install (needs your Mac password).
set -euo pipefail

if [ -x /opt/homebrew/bin/brew ] || [ -x /usr/local/bin/brew ]; then
    echo "Homebrew is already installed."
    if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    brew --version
    exit 0
fi

echo "This will install Homebrew. You will be asked for your Mac login password."
echo ""
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

echo ""
echo "Adding Homebrew to your shell..."
if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    grep -q 'homebrew/bin/brew shellenv' "$HOME/.zprofile" 2>/dev/null || \
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

echo ""
echo "Installing create-dmg..."
brew install create-dmg

echo ""
echo "Done! Open a NEW Terminal window, then run:"
echo "  cd ~/Documents/SteamIdleMac"
echo "  bash scripts/publish.sh"
