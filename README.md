# YouTube X <img width="128" height="128" alt="ty" src="https://github.com/user-attachments/assets/29f2f682-8d37-4e68-8246-bf56ae59d08c" />

A beautiful, ad‑free YouTube experience for macOS Ventura and later. Built with SwiftUI + WKWebView, it feels like a native Apple app, not a website wrapper.

## ✨ Features

- **No ads** – advanced network blocking combined with automatic ad‑skipping (even video ads are skipped before you see them)
- **Download videos & Shorts** – offline downloads with built‑in `yt‑dlp` (see details below)
- **5 beautiful themes** – YouTube Dark, Light, Midnight Blue, Forest Green, Crimson Red
- **Picture‑in‑Picture** – pop any video out and keep it floating while you work
- **Media keys & Touch Bar** support – play/pause, skip, scrub
- **Mini Player** window – a compact floating player (⌘⇧M)
- **Watch history** – instantly revisit past videos
- **Keyboard shortcuts** overlay – see all shortcuts at a glance
- **Quality selector** – change video resolution on the fly
- **Context menu** – copy URL, open in browser, download

## 📥 Installation

1. Download the latest `YouTube X.app.zip` from the [Releases page](../../releases).
2. Unzip and drag `YouTube X.app` to your `/Applications` folder (or anywhere you like).
3. **First‑launch Gatekeeper workaround**:
   - **Right‑click** (or Control‑click) the app and choose **Open**.
   - In the dialog, click **Open** again.
   - If that doesn’t work, go to **System Settings → Privacy & Security** → scroll down to the bottom → click **Open Anyway**.
   - The app only needs this one‑time approval – after that it launches normally.

## 📦 Built‑in yt‑dlp (download engine)

This app includes the excellent [yt‑dlp](https://github.com/yt-dlp/yt-dlp) project to handle offline downloads. It is deeply integrated and works out of the box with no extra setup.

- **Automatic updates** – the app silently checks for new versions of yt‑dlp once a week and installs them in the background.
- **Manual update** – you can also trigger an update manually via the menu: **⋮ → Check for Updates**.
- **Credit** – all download functionality is powered by yt‑dlp. I am grateful to the yt‑dlp community for making this possible. Please consider supporting their work.

## 📝 Requirements

- macOS 13.0 (Ventura) or later (Intel and Apple Silicon)
- Internet connection for streaming and downloads

## ⚠️ Disclaimer

YouTube X is an independent project and is **not affiliated with or endorsed by YouTube LLC or Google Inc.** All trademarks belong to their respective owners. This app is intended for personal, non‑commercial use.

## 🔮 Source Code

The source code will be open‑sourced in the near future. Stay tuned!

---

**Thank you for trying YouTube X!**

☕ If you enjoy YouTube X, consider buying me a coffee to support future development!
[![BuyMeACoffee](https://raw.githubusercontent.com/pachadotdev/buymeacoffee-badges/main/bmc-yellow.svg)](https://www.buymeacoffee.com/youtubex)
