//
//  Youtube_XAPP.swift
//  Youtube X
//
//  Created by fizzyg on 30/4/26.
//

import SwiftUI
import AppKit

@main
struct YouTube_XApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var webViewStore = WebViewStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(themeManager)
                .environmentObject(webViewStore)
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(themeManager.colorScheme)
                .background(WindowConfigurator())
        }
        .windowStyle(.titleBar)
        .windowResizability(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Navigation") {
                Button("Home") { NotificationCenter.default.post(name: .navigateToHome, object: nil) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Subscriptions") { NotificationCenter.default.post(name: .navigateToSubscriptions, object: nil) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Library") { NotificationCenter.default.post(name: .navigateToLibrary, object: nil) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Downloads") { NotificationCenter.default.post(name: .navigateToDownloads, object: nil) }
                    .keyboardShortcut("4", modifiers: .command)
                Divider()
                Button("Command Palette...") { NotificationCenter.default.post(name: .toggleCommandPalette, object: nil) }
                    .keyboardShortcut("k", modifiers: .command)
            }
            CommandMenu("Playback") {
                Button("Play/Pause") { NotificationCenter.default.post(name: .mediaKeyPlayPause, object: nil) }
                Button("Skip Forward") { NotificationCenter.default.post(name: .mediaKeySkipForward, object: nil) }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Skip Backward") { NotificationCenter.default.post(name: .mediaKeySkipBackward, object: nil) }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(themeManager)
                .environmentObject(webViewStore)
                .preferredColorScheme(themeManager.colorScheme)
        }

        Window("Youtube X Player", id: "miniplayer") {
            MiniPlayerView()
                .onAppear {
                    // Ensure the window has a consistent identifier for sidebar lookups
                    if let window = NSApp.windows.first(where: { $0.title == "Youtube X Player" }) {
                        window.identifier = NSUserInterfaceItemIdentifier("miniplayer")
                    }
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 480, height: 270)
    }
}

// MARK: - Window Configurator
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.styleMask.formUnion([.resizable, .miniaturizable, .closable, .titled])
            window.collectionBehavior.insert(.fullScreenPrimary)
            window.isRestorable = true
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var mediaKeyTap: MediaKeyHandler?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let ytdlpPath = Bundle.main.path(forResource: "yt-dlp", ofType: nil) {
            let task = Process()
            task.launchPath = "/usr/bin/xattr"
            task.arguments = ["-d", "com.apple.quarantine", ytdlpPath]
            task.launch()
            task.waitUntilExit()
        }
        KeyboardShortcuts.setup()
        mediaKeyTap = MediaKeyHandler()
        mediaKeyTap?.startListening()
        DownloadNotifications.shared.requestAuthorization()
    }

    func applicationWillResignActive(_ notification: Notification) {
        if ThemeManager.shared.autoPiP {
            NotificationCenter.default.post(name: .autoPiP, object: nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        mediaKeyTap?.stopListening()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

// MARK: - Media Key Handler
class MediaKeyHandler {
    private var eventMonitor: Any?

    func startListening() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            self?.handle(event: event)
        }
    }

    func stopListening() {
        if let monitor = eventMonitor { NSEvent.removeMonitor(monitor) }
    }

    private func handle(event: NSEvent) {
        guard event.type == .systemDefined, event.subtype.rawValue == 8 else { return }
        let keyCode = (event.data1 & 0xFFFF0000) >> 16
        let flags = event.data1 & 0xFFFF
        let state = (flags & 0xFF00) >> 8
        if state == 0xA || (flags & 0x1) == 1 {
            switch keyCode {
            case 16: NotificationCenter.default.post(name: .mediaKeyPlayPause, object: nil)
            case 18: NotificationCenter.default.post(name: .mediaKeySkipForward, object: nil)
            case 19: NotificationCenter.default.post(name: .mediaKeySkipBackward, object: nil)
            default: break
            }
        }
    }
}
