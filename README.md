# HourDock for Mac

HourDock is a native macOS app for idling your Steam library and tracking hours without launching full games.

## Features

- Run 32 games at once
- Polished UI & Functional Menu Bar
- Start/stop sessions from both the app and menu bar
- Use floating idle banners in banner or icon style
- Keep lightweight idle-time tracking and widget snapshots
- Get in-app update checks on release builds

## Download and Install

1. Open the releases page: [HourDock Releases](https://github.com/chic0beans/HourDock/releases)
2. Download `HourDock.dmg`
3. Drag `HourDock.app` to `Applications`
4. Launch the app

## Quick Start

1. Open setup and paste your Steam Web API key 
2. Test the key and load your library
3. Choose your idle banner style
4. Click a game to start idling

## Updates

- In-app: use `Check for Updates...` from the app/menu bar
- Manual: install the latest DMG from Releases

If update checking is disabled, you're likely running a non-release build. Install from an official GitHub release DMG.

## Privacy

- No HourDock account required
- No analytics, ads, or third-party tracking SDKs
- Steam Web API key is stored in macOS Keychain (`com.steamidlemac.apikey` / `steam_web_api`)
- App preferences, cache, and idle metadata stay on your Mac
- Network calls are only for Steam library/profile data and release update checks (GitHub/Sparkle)
