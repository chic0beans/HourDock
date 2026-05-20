# Put HourDock on GitHub (simple guide)

Your username: **chic0beans**

Download page: **https://github.com/chic0beans/SteamIdleMac/releases**

---

## You do NOT need Homebrew

If Terminal says `command not found: brew`, use these commands instead.

---

## Step 1 — Install GitHub CLI (no Homebrew)

```bash
cd ~/Documents/SteamIdleMac
bash scripts/install-tools.sh
```

Close Terminal and open a **new** Terminal window.

```bash
gh auth login
```

Pick **GitHub.com** → **HTTPS** → login with a **web browser**.

---

## Step 2 — Push project to GitHub (one-time)

```bash
cd ~/Documents/SteamIdleMac
bash scripts/setup-github.sh
```

Share this link: **https://github.com/chic0beans/SteamIdleMac/releases**

---

## What happens when you publish

1. Opens the link above
2. Downloads **SteamIdleMac.dmg**
3. Drags the app to Applications
4. First open: right-click → Open (Gatekeeper)

---

## Optional: Homebrew later

If you want `brew` for other tools: https://brew.sh

You do **not** need it for this project.

---

## Build options

### Without widget (Swift Package Manager only)

```bash
bash scripts/build-app.sh
```

### With WidgetKit extension (requires Xcode.app)

Install Xcode from the App Store, then:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
bash scripts/build-xcode.sh
```

Add the widget from Notification Center or Desktop widgets.

The app writes idle state to App Group `group.com.steamidlemac.shared`; timelines refresh when you start or stop idling.

---

## Publish a release

```bash
bash scripts/publish.sh 1.0.6
```
