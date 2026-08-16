//
//  ThemeManager
//  Youtube X
//
// Created by fizzyg on 30/4/26.
//

import SwiftUI
import Combine

// MARK: - All Notification Names
extension Notification.Name {
    static let themeDidChange = Notification.Name("themeDidChange")
    static let navigateToHome = Notification.Name("navigateToHome")
    static let navigateToTrending = Notification.Name("navigateToTrending")
    static let navigateToSubscriptions = Notification.Name("navigateToSubscriptions")
    static let navigateToShorts = Notification.Name("navigateToShorts")
    static let toggleFullScreen = Notification.Name("toggleFullScreen")
    static let videoDetected = Notification.Name("videoDetected")
    static let toggleMiniPlayer = Notification.Name("toggleMiniPlayer")
    static let mediaKeyPlayPause = Notification.Name("mediaKeyPlayPause")
    static let mediaKeySkipForward = Notification.Name("mediaKeySkipForward")
    static let mediaKeySkipBackward = Notification.Name("mediaKeySkipBackward")
    static let autoPiP = Notification.Name("autoPiP")
}

// MARK: - Themes
enum AppTheme: String, CaseIterable {
    case system = "System"
    case dark = "YouTube Dark"
    case light = "Light"
    case midnight = "Midnight Blue"
    case forest = "Forest Green"
    case crimson = "Crimson Red"
    case amoled = "AMOLED Black"
    case sunset = "Sunset Orange"
    case ocean = "Ocean Teal"
    case lavender = "Lavender"

    var palette: ThemePalette {
        switch self {
        case .system:
            return AppTheme.dark.palette
        case .dark:
            return ThemePalette(
                name: rawValue,
                background: Color(hex: "000000"),
                surface: Color(hex: "0A0A0A"),
                toolbar: Color(hex: "000000"),
                textPrimary: .white,
                textSecondary: Color(hex: "B3B3B3"),
                accent: Color(hex: "EB0000"),
                divider: Color(hex: "1A1A1A"),
                searchBar: Color(hex: "1A1A1A"),
                buttonHover: Color(hex: "222222"),
                webBackground: "#000000",
                webSurface: "#0A0A0A",
                progressBar: Color(hex: "EB0000")
            )
        case .light:
            return ThemePalette(
                name: rawValue,
                background: Color(hex: "FFFFFF"),
                surface: Color(hex: "F5F5F5"),
                toolbar: Color(hex: "FAFAFA"),
                textPrimary: Color(hex: "0F0F0F"),
                textSecondary: Color(hex: "606060"),
                accent: Color(hex: "CC0000"),
                divider: Color(hex: "E0E0E0"),
                searchBar: Color(hex: "EEEEEE"),
                buttonHover: Color(hex: "E5E5E5"),
                webBackground: "#FFFFFF",
                webSurface: "#F5F5F5",
                progressBar: Color(hex: "CC0000")
            )
        case .midnight:
            return ThemePalette(
                name: rawValue,
                background: Color(hex: "0D1B2A"),
                surface: Color(hex: "1B2838"),
                toolbar: Color(hex: "162230"),
                textPrimary: .white,
                textSecondary: Color(hex: "7B8FA1"),
                accent: Color(hex: "3A86FF"),
                divider: Color(hex: "2C3E50"),
                searchBar: Color(hex: "1C2E40"),
                buttonHover: Color(hex: "243447"),
                webBackground: "#0D1B2A",
                webSurface: "#1B2838",
                progressBar: Color(hex: "3A86FF")
            )
        case .forest:
            return ThemePalette(
                name: rawValue,
                background: Color(hex: "1B2E1B"),
                surface: Color(hex: "243824"),
                toolbar: Color(hex: "1F331F"),
                textPrimary: .white,
                textSecondary: Color(hex: "8FA88F"),
                accent: Color(hex: "4CAF50"),
                divider: Color(hex: "2D442D"),
                searchBar: Color(hex: "1F331F"),
                buttonHover: Color(hex: "2B402B"),
                webBackground: "#1B2E1B",
                webSurface: "#243824",
                progressBar: Color(hex: "4CAF50")
            )
        case .crimson:
            return ThemePalette(
                name: rawValue,
                background: Color(hex: "1A1014"),
                surface: Color(hex: "2A1A20"),
                toolbar: Color(hex: "1F1419"),
                textPrimary: .white,
                textSecondary: Color(hex: "AF8F9A"),
                accent: Color(hex: "D32F2F"),
                divider: Color(hex: "3A2430"),
                searchBar: Color(hex: "24141C"),
                buttonHover: Color(hex: "2E1E25"),
                webBackground: "#1A1014",
                webSurface: "#2A1A20",
                progressBar: Color(hex: "D32F2F")
            )
        case .amoled:
            // True black - every surface pinned to #000000/#0A0A0A so nothing
            // reads as an off-theme white flash, even under bright ambient light.
            return ThemePalette(
                name: rawValue,
                background: Color(hex: "000000"),
                surface: Color(hex: "000000"),
                toolbar: Color(hex: "000000"),
                textPrimary: .white,
                textSecondary: Color(hex: "8A8A8A"),
                accent: Color(hex: "FF3B30"),
                divider: Color(hex: "141414"),
                searchBar: Color(hex: "0D0D0D"),
                buttonHover: Color(hex: "161616"),
                webBackground: "#000000",
                webSurface: "#000000",
                progressBar: Color(hex: "FF3B30")
            )
        case .sunset:
            return ThemePalette(
                name: rawValue,
                background: Color(hex: "1F1410"),
                surface: Color(hex: "2E1E16"),
                toolbar: Color(hex: "241811"),
                textPrimary: .white,
                textSecondary: Color(hex: "C9A38A"),
                accent: Color(hex: "FF7A33"),
                divider: Color(hex: "3D2A1E"),
                searchBar: Color(hex: "2A1B14"),
                buttonHover: Color(hex: "37241A"),
                webBackground: "#1F1410",
                webSurface: "#2E1E16",
                progressBar: Color(hex: "FF7A33")
            )
        case .ocean:
            return ThemePalette(
                name: rawValue,
                background: Color(hex: "081A1C"),
                surface: Color(hex: "0F2A2D"),
                toolbar: Color(hex: "0B2224"),
                textPrimary: .white,
                textSecondary: Color(hex: "7FB3B5"),
                accent: Color(hex: "17C3B2"),
                divider: Color(hex: "173B3E"),
                searchBar: Color(hex: "0D2528"),
                buttonHover: Color(hex: "133638"),
                webBackground: "#081A1C",
                webSurface: "#0F2A2D",
                progressBar: Color(hex: "17C3B2")
            )
        case .lavender:
            return ThemePalette(
                name: rawValue,
                background: Color(hex: "16121F"),
                surface: Color(hex: "241D33"),
                toolbar: Color(hex: "1B1628"),
                textPrimary: .white,
                textSecondary: Color(hex: "B3A5CC"),
                accent: Color(hex: "9B6BFF"),
                divider: Color(hex: "332843"),
                searchBar: Color(hex: "1F1A2C"),
                buttonHover: Color(hex: "2B233C"),
                webBackground: "#16121F",
                webSurface: "#241D33",
                progressBar: Color(hex: "9B6BFF")
            )
        }
    }
}

struct ThemePalette {
    let name: String
    let background: Color
    let surface: Color
    let toolbar: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let divider: Color
    let searchBar: Color
    let buttonHover: Color
    let webBackground: String
    let webSurface: String
    let progressBar: Color
}

// MARK: - Theme Manager
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var currentTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: "selectedTheme")
            applyWindowAppearance()
            NotificationCenter.default.post(name: .themeDidChange, object: nil)
        }
    }

/// Tracks the live macOS appearance so `.system` can resolve to the correct light/dark palette and update automatically when you
/// flip System Settings > Appearance, without needing to relaunch.
    @Published private var systemIsDark: Bool = ThemeManager.detectSystemIsDark()

    @AppStorage("incognitoMode") var incognitoMode = false
    @AppStorage("autoPiP") var autoPiP = true

    init() {
        let saved = UserDefaults.standard.string(forKey: "selectedTheme") ?? AppTheme.dark.rawValue
        currentTheme = AppTheme(rawValue: saved) ?? .dark
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemAppearanceChanged),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
        applyWindowAppearance()
    }

    @objc private func systemAppearanceChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.systemIsDark = Self.detectSystemIsDark()
            self.applyWindowAppearance()
            NotificationCenter.default.post(name: .themeDidChange, object: nil)
        }
    }

    private static func detectSystemIsDark() -> Bool {
        let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") ?? "Light"
        return style.lowercased().contains("dark")
    }

    /// `.system` resolved to whichever concrete theme is actually in effect while the other case resolves to itself.
    var resolvedTheme: AppTheme {
        currentTheme == .system ? (systemIsDark ? .dark : .light) : currentTheme
    }

    var palette: ThemePalette {
        resolvedTheme.palette
    }

/// Feed straight into `.preferredColorScheme()` at the app root so SwiftUI's own materials, controls, and text follow the chosen theme instead of quietly falling back to the OS default (which was the main source of stray white showing through on a dark custom theme).
    var colorScheme: ColorScheme? {
        switch currentTheme {
        case .system: return nil
        case .light: return .light
        default: return .dark
        }
    }
/// Beyond SwiftUI's own materials, macOS's native chrome - the titlebar, the sidebar's vibrancy, scrollbars, menus - follows `NSApp.appearance`independently.
/// Setting it here is what actually eliminates the leftover white edges/sidebar background that `.preferredColorScheme` alone doesn't reach.
    private func applyWindowAppearance() {
        DispatchQueue.main.async {
            switch self.currentTheme {
            case .system:
                NSApp.appearance = nil
            case .light:
                NSApp.appearance = NSAppearance(named: .aqua)
            default:
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }
}

// MARK: - Watch History
struct WatchHistoryItem: Codable, Identifiable {
    var id = UUID()
    let url: String
    let title: String
    let timestamp: Date
}

class WatchHistoryManager: ObservableObject {
    static let shared = WatchHistoryManager()
    @Published var history: [WatchHistoryItem] = []

    private let key = "watchHistory"
    private let max = 50

    init() { load() }

    func add(url: String, title: String) {
        let item = WatchHistoryItem(url: url, title: title, timestamp: Date())
        history.insert(item, at: 0)
        if history.count > max { history = Array(history.prefix(max)) }
        save()
    }

    func clear() {
        history.removeAll()
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([WatchHistoryItem].self, from: data) else { return }
        history = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Color Extensions
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}

extension Color {
    static var ytRed: Color { ThemeManager.shared.palette.accent }
    static var ytDarkBackground: Color { ThemeManager.shared.palette.background }
    static var ytSurfaceGray: Color { ThemeManager.shared.palette.surface }
    static var ytToolbarBackground: Color { ThemeManager.shared.palette.toolbar }
    static var ytTextPrimary: Color { ThemeManager.shared.palette.textPrimary }
    static var ytTextSecondary: Color { ThemeManager.shared.palette.textSecondary }
    static var ytSearchBar: Color { ThemeManager.shared.palette.searchBar }
    static var ytDivider: Color { ThemeManager.shared.palette.divider }
    static var ytProgressBar: Color { ThemeManager.shared.palette.progressBar }
    static var ytButtonHover: Color { ThemeManager.shared.palette.buttonHover }
}
