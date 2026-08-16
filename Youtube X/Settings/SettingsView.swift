//
//  SettingsView.swift
//  Youtube X
//
//  Created by fizzyg on 8/7/26.
//

import SwiftUI
import WebKit

struct SettingsView: View {
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            DownloadSettingsView()
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 460)
    }
}

// MARK: - General
struct GeneralSettingsView: View {
    @AppStorage("autoPiP") private var autoPiP = true
    @AppStorage("incognitoMode") private var incognitoMode = false
    @AppStorage("showNowPlaying") private var showNowPlaying = true
    @ObservedObject private var sponsorBlock = SponsorBlockManager.shared
    @EnvironmentObject var webViewStore: WebViewStore

    var body: some View {
        Form {
            Group {
                Toggle("Auto Picture-in-Picture", isOn: $autoPiP)
                Toggle("Incognito Mode (no history)", isOn: $incognitoMode)
                Toggle("Show \u{201C}Now Playing\u{201D} in sidebar", isOn: $showNowPlaying)
            }

            Divider()

            Text("SponsorBlock").font(.headline)
            Toggle("Auto-skip sponsored segments", isOn: $sponsorBlock.isEnabled)
                .onChange(of: sponsorBlock.isEnabled) { _ in webViewStore.refreshSponsorBlockForCurrentVideo() }
            Text("Uses community-submitted data from sponsor.ajay.app to automatically skip sponsor reads, intros, outros, and similar segments. Off by default.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            if sponsorBlock.isEnabled {
                Toggle("Show a brief notice when a segment is skipped", isOn: $sponsorBlock.showSkipNotice)
                Text("Skip Categories").font(.system(size: 12, weight: .semibold)).padding(.top, 4)
                ForEach(SponsorBlockManager.allCategories, id: \.id) { category in
                    Toggle(category.label, isOn: Binding(
                        get: { sponsorBlock.enabledCategories.contains(category.id) },
                        set: { isOn in
                            var current = sponsorBlock.enabledCategories
                            if isOn { current.insert(category.id) } else { current.remove(category.id) }
                            sponsorBlock.enabledCategories = current
                            webViewStore.refreshSponsorBlockForCurrentVideo()
                        }
                    ))
                }
            }

            Divider()
            Text("Keyboard Shortcuts").font(.headline)
            Group {
                Text("⌘1 – Home   ⌘2 – Subscriptions   ⌘3 – Library")
                Text("Space – Play/Pause   ⌘→/⌘← – Skip")
                Text("K – Command Palette   I – Miniplayer")
                Text("J/L – Back/Forward 10s")
            }
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        }
        .padding()
    }
}

// MARK: - Downloads
struct DownloadSettingsView: View {
    @AppStorage("defaultVideoQuality") private var defaultVideoQuality = "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]"
    @AppStorage("defaultAudioFormat") private var defaultAudioFormat = "M4A"
    @State private var storageLocation = defaultDownloadPath()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Video Quality
            VStack(alignment: .leading, spacing: 4) {
                Text("Video Quality")
                    .font(.system(size: 12, weight: .semibold))
                Picker("", selection: $defaultVideoQuality) {
                    Text("Best (up to 4K)").tag("bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]")
                    Text("1080p").tag("bestvideo[height<=1080][ext=mp4]+bestaudio[ext=m4a]/best[height<=1080]")
                    Text("720p").tag("bestvideo[height<=720][ext=mp4]+bestaudio[ext=m4a]/best[height<=720]")
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
            }

            // Audio Format
            VStack(alignment: .leading, spacing: 4) {
                Text("Audio Format")
                    .font(.system(size: 12, weight: .semibold))
                Picker("", selection: $defaultAudioFormat) {
                    ForEach(AudioFormat.allCases) { format in
                        Text(format.rawValue).tag(format.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 140)
            }

            // Download Location
            HStack {
                Text("Location:")
                    .font(.system(size: 12, weight: .semibold))
                Text(storageLocation)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(action: {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.begin { response in
                        if response == .OK, let url = panel.url {
                            storageLocation = url.path
                        }
                    }
                }) {
                    Text("Change…")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
            }

            Divider()

            // YouTube X Tools
            HStack {
                Text("YouTube X Tools")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(action: {
                    YtDlpUpdater.shared.checkForUpdateIfNeeded(manual: true)
                    FfmpegUpdater.shared.checkForUpdateIfNeeded(manual: true)
                }) {
                    Text("Check for Updates")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Text("Big thanks to the teams behind yt-dlp and ffmpeg which make projects & experiences like this possible 🤘")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func defaultDownloadPath() -> String {
        let paths = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("YouTube X Downloads").path
    }
}

// MARK: - Appearance
struct AppearanceSettingsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    var body: some View {
        Form {
            Picker("Theme", selection: $themeManager.currentTheme) {
                ForEach(AppTheme.allCases, id: \.self) { theme in
                    Text(theme.rawValue).tag(theme)
                }
            }
        }
        .padding()
    }
}

// MARK: - About (with attribution)
struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)

            Text("YouTube X").font(.largeTitle)
            Text("Built for macOS 13+")
            Text("A native YouTube experience")

            Divider()

            Group {
                HStack {
                    Button("Check for App Updates") {
                        AppUpdateChecker.shared.check()
                    }
                    Button("Open Downloads Folder") {
                        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                            NSWorkspace.shared.open(downloads.appendingPathComponent("YouTube X Downloads"))
                        }
                    }
                }

                HStack {
                    Button("Clear Cache") {
                        WKWebsiteDataStore.default().removeData(
                            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                            modifiedSince: Date(timeIntervalSince1970: 0)
                        ) {}
                    }
                    Button("Clear History") {
                        WatchHistoryManager.shared.clear()
                    }
                }
            }

            Divider()

            VStack(spacing: 4) {
                Text("Powered by")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    Link("yt‑dlp (MIT)", destination: URL(string: "https://github.com/yt-dlp/yt-dlp/blob/master/LICENSE")!)
                    Text("·")
                        .foregroundColor(.secondary)
                    Link("FFmpeg (LGPL)", destination: URL(string: "https://github.com/FFmpeg/FFmpeg/blob/master/LICENSE.md")!)
                    Text("·")
                        .foregroundColor(.secondary)
                    Link("SponsorBlock", destination: URL(string: "https://sponsor.ajay.app")!)
                }
                .font(.system(size: 10))
            }

            Divider()

            Link("View on GitHub", destination: URL(string: "https://github.com/fizzygx/Youtube-X")!)
        }
        .padding()
    }
}
