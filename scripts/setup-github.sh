#!/bin/bash
# First-time GitHub setup for chic0beans — run once.
set -euo pipefail

export PATH="$HOME/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

GITHUB_USER="chic0beans"
GITHUB_REPO="SteamIdleMac"
REMOTE="https://github.com/${GITHUB_USER}/${GITHUB_REPO}.git"

bash "$ROOT/scripts/install-tools.sh"

echo ""
echo "=== HourDock — GitHub setup ==="
echo "Account: $GITHUB_USER"
echo "Repo:    $GITHUB_REPO"
echo ""

if ! command -v gh >/dev/null 2>&1; then
    echo "Could not find gh. Run: bash scripts/install-tools.sh"
    exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
    echo "Log in to GitHub (browser will open)..."
    gh auth login
fi

echo "Logged in as: $(gh api user -q .login 2>/dev/null || echo unknown)"
echo ""

if [ ! -d .git ]; then
    git init
    git branch -M main
fi

git add -A

if ! git diff --cached --quiet 2>/dev/null; then
    git commit -m "HourDock"
elif ! git rev-parse HEAD >/dev/null 2>&1; then
    git commit --allow-empty -m "HourDock"
else
    echo "Nothing new to commit."
fi

if git remote get-url origin >/dev/null 2>&1; then
    git remote set-url origin "$REMOTE"
else
    git remote add origin "$REMOTE"
fi

if gh repo view "${GITHUB_USER}/${GITHUB_REPO}" >/dev/null 2>&1; then
    echo "Repo already on GitHub."
else
    echo "Creating repo on GitHub..."
    gh repo create "${GITHUB_REPO}" --public --source=. --remote=origin 2>/dev/null ||         gh repo create "${GITHUB_REPO}" --public
    git remote set-url origin "$REMOTE" 2>/dev/null || git remote add origin "$REMOTE"
fi

git push -u origin main || git push origin main

echo ""
echo "Done! https://github.com/${GITHUB_USER}/${GITHUB_REPO}"
echo ""
echo "Next: bash scripts/publish.sh"
echo ""
