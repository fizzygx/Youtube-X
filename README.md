# 🎬 YouTube X 
<img width="128" height="128" alt="ty" src="https://github.com/user-attachments/assets/29f2f682-8d37-4e68-8246-bf56ae59d08c" />

A beautiful, ad‑free YouTube experience for macOS Ventura and later. Built with SwiftUI + WKWebView, it feels like a native Apple app.

## ✨ Features

###  📁Offline Playback
- A dedicated Offline pane plays back everything you've downloaded — videos, Shorts, and audio — with no network required
- Shorts behave like real Shorts: they loop on end, and Up/Down arrow keys jump to the next/previous one like a continuous feed
- A separate floating Mini Player window supports shuffle, repeat, a reorderable queue, and saving/loading your own playlists
- Add files to the queue by browsing what's already downloaded right in the app — no digging through Finder required

### 🚫 Ad Blocking & SponsorBlock
- Strong network‑level ad blocking 
- Automatic video ad skipping
- Optional **SponsorBlock** integration toggle — automatically skips sponsor reads, intros, outros, self‑promo, and interaction‑reminder segments using community‑submitted data, with a brief on‑screen notice when a segment is skipped.  Toggle in Settings. 

###  ⬇️ Downloads
- Download videos, Shorts, and audio‑only tracks, powered by a bundled `yt‑dlp` + `ffmpeg`
- Videos are muxed to standard H.264/AAC MP4, so they play natively in QuickTime and any other Mac video app.
- Audio downloads support M4A, MP3, FLAC, and AAC, with embedded thumbnail artwork and metadata
- Whole playlists can be downloaded at once, each into its own named folder (with automatic numbering if a name's already taken)
- Everything is organized automatically — regular videos, Shorts, audio, and playlists each land in their own folder, so nothing gets mixed together
- A Safari‑style downloads popover lives in the toolbar with live per‑file progress rings; a full Downloads pane is also available for browsing everything, with status filters and retry/cancel/delete
- Share, Copy URL, and Show in Finder are available everywhere a download shows up

###  🎵 Smart Now Playing

- The sidebar and toolbar show what you’re watching – for YouTube and offline playback.
- Click it to jump back to the video without refreshing the page.
- Close it with a single ✕.

###  🌙 Appearance

- 10 built‑in themes — YouTube Dark, Light, Midnight Blue, Forest Green, Crimson Red, AMOLED Black, Sunset Orange, Ocean Teal, Lavender — plus a **System** option that automatically follows macOS's Light/Dark appearance
- Fullscreen hides the toolbar automatically for a cleaner, more immersive view

###  🛠️Additional Features
- Native macOS share sheet (Mail, Messages, AirDrop, and more)
- Picture‑in‑Picture and a dedicated Miniplayer toggle
- Command palette (⌘K) for quick navigation
- The app checks for its own updates against GitHub Releases and surfaces a badge in Options when a new version is available
- Full keyboard shortcut support for playback and navigation (see below)

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| Space / K | Play / Pause |
| J | Skip back 10s |
| L | Skip forward 10s |
| F | Toggle fullscreen |
| M | Mute |
| ↑ / ↓ | Next / previous Short (Offline & Downloads panes) |
| ⌘1 | Home |
| ⌘2 | Subscriptions |
| ⌘3 | Library |
| ⌘D | Downloads |
| ⌘K | Command palette |
| ⌘F | Find |
| ⌘, | Settings |

## 📥 Installation

1. Download the latest `YouTube X.app.zip` from the [Releases page](../../releases).
2. Unzip and drag `YouTube X.app` to your `/Applications` folder (or anywhere you like).
3. **First‑launch Gatekeeper workaround**:
   - **Right‑click** (or Control‑click) the app and choose **Open**.
   - In the dialog, click **Open** again.
   - If that doesn't work, go to **System Settings → Privacy & Security** → scroll down to the bottom → click **Open Anyway**.
   - The app only needs this one‑time approval — after that it launches normally.

**N.B. Sometimes ads are unskippable — just press the refresh button to make the ad go and it'll play without ads. Always works.**

## 📦 Built‑in yt‑dlp & ffmpeg (download engine)

This app includes [yt‑dlp](https://github.com/yt-dlp/yt-dlp) and [ffmpeg](https://ffmpeg.org) to handle offline downloads, merging, and audio extraction. Both are deeply integrated and work out of the box with no extra setup — for downloaded builds from the Releases page, that is. If you're compiling from source, see [Building from Source](#-building-from-source) below; these two tools are **not** checked into this repository and you'll need to add them yourself.

- **Automatic updates** — the app silently checks for new versions of yt‑dlp and ffmpeg once a week and installs them in the background, with no interruption.
- **Manual update** — trigger a check any time via **⋮ → Check for Updates**, or in **Settings → Downloads**.
- **Credit** — all download functionality is powered by yt‑dlp and ffmpeg. I'm grateful to both communities for making this possible — please consider supporting their work.

## 📝 Requirements

- macOS 13.0 (Ventura) or later (Intel and Apple Silicon)
- Internet connection for streaming and downloads (downloaded content still works fully offline)

## 🛠 Building from Source

**Requirements:** Xcode 14.3+ running on macOS 13 (Ventura) or later.

### 1. Clone the repo

```bash
git clone https://github.com/fizzygx/Youtube-X.git
cd Youtube-X
```

### 2. Get yt‑dlp and ffmpeg

These two command‑line tools are bundled *inside* the app but are **not included in this repository** (they're binaries, not source, and are excluded via `.gitignore`). You need to add them yourself before the download/offline features will work in a build you compile.

**yt‑dlp**
1. Download `yt-dlp_macos` from the [latest yt‑dlp release](https://github.com/yt-dlp/yt-dlp/releases/latest) — the standalone macOS binary, not the Python script and not the Windows/Linux builds.
2. Rename it to exactly `yt-dlp` (no file extension).
3. In Terminal: `chmod +x yt-dlp`

**ffmpeg**
1. Download the macOS build from the [yt‑dlp/FFmpeg‑Builds latest release](https://github.com/yt-dlp/FFmpeg-Builds/releases/latest) — grab whichever asset has `macos` in its filename (it'll be a `.zip` or `.tar.xz` archive, not a raw binary).
2. Extract it — the `ffmpeg` binary is inside, usually under a `bin/` folder.
3. Rename/move it so you have a plain file named exactly `ffmpeg` (no extension).
4. In Terminal: `chmod +x ffmpeg`

### 3. Add them to the Xcode project

1. Open `Youtube X.xcodeproj` in Xcode.
2. Drag both `yt-dlp` and `ffmpeg` into the **Youtube X** group in the Project Navigator (this replaces the placeholder files the `.gitignore` keeps out of the repo).
3. In the dialog that appears, check **Copy items if needed**, and make sure the **Youtube X** target checkbox is ticked before clicking **Add**.
4. Build (⌘B) and run (⌘R).

That's it — the app will use these bundled copies from first launch, and will silently keep both up to date in the background from then on (see [above](#-built-in-yt-dlp--ffmpeg-download-engine)).

> **Note:** the ad‑blocking rule list (`adblocker.json`) *is* checked into the repo and needs no extra setup.
🛠️ v2.0.0
---
### Screenshot s
<img width="789" height="516" alt="yx1" src="https://github.com/user-attachments/assets/4554ec97-b5cc-48c3-a3f5-2211f7002ef6" />

---
<img width="1366" height="768" alt="Screenshot 2026-08-11 at 21 13 41" src="https://github.com/user-attachments/assets/2b65c9e4-4de4-485a-a10c-da82b33a154c" />

---
### Thank you for trying YouTube X!
☕ If you enjoy YouTube X, consider buying me a coffee to support future development!
[![BuyMeACoffee](https://raw.githubusercontent.com/pachadotdev/buymeacoffee-badges/main/bmc-yellow.svg)](https://www.buymeacoffee.com/youtubex)
---
### ⚠️ Disclaimer

YouTube X is an independent project and is **not affiliated with or endorsed by YouTube LLC or Google Inc.** All trademarks belong to their respective owners. This app is intended for personal, non‑commercial use.
