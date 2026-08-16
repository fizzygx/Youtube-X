//
//  DownloadManager.swift
//  Youtube X
//
//  Created by fizzyg on 8/7/26.
//

import Foundation
import Combine
import AppKit

// MARK: - yt‑dlp Updater (embedded)
class YtDlpUpdater: ObservableObject {
    static let shared = YtDlpUpdater()

    private let lastCheckKey = "YtDlpLastCheck"
    private let checkInterval: TimeInterval = 7 * 24 * 60 * 60
    private var updateInProgress = false

    func checkForUpdateIfNeeded(manual: Bool = false) {
        guard !updateInProgress else { return }

        if !manual {
            let last = UserDefaults.standard.double(forKey: lastCheckKey)
            let now = Date().timeIntervalSince1970
            guard now - last >= checkInterval else { return }
        }

        updateInProgress = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            defer { DispatchQueue.main.async { self?.updateInProgress = false } }

            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let ytxDir = appSupport.appendingPathComponent("YouTube X")
            try? FileManager.default.createDirectory(at: ytxDir, withIntermediateDirectories: true)
            let userYtdlp = ytxDir.appendingPathComponent("yt-dlp")

            guard let bundledPath = Bundle.main.path(forResource: "yt-dlp", ofType: nil) else { return }
            let bundledURL = URL(fileURLWithPath: bundledPath)

            let currentVersion: String
            if FileManager.default.fileExists(atPath: userYtdlp.path) {
                currentVersion = self?.runCommand(executable: userYtdlp, arguments: ["--version"]) ?? ""
            } else {
                currentVersion = self?.runCommand(executable: bundledURL, arguments: ["--version"]) ?? ""
            }
            guard !currentVersion.isEmpty else { return }

            let latestVersion: String
            let latestTag: String
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            task.arguments = ["-s", "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest"]
            let pipe = Pipe(); task.standardOutput = pipe
            do { try task.run(); task.waitUntilExit() } catch { return }
            guard let data = try? JSONSerialization.jsonObject(with: pipe.fileHandleForReading.readDataToEndOfFile()) as? [String: Any],
                  let tag = data["tag_name"] as? String else { return }
            latestTag = tag
            latestVersion = tag.replacingOccurrences(of: "-", with: ".")

            if currentVersion == latestVersion { return }

            let tempURL = ytxDir.appendingPathComponent("yt-dlp_download")
            let dlTask = Process()
            dlTask.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            dlTask.arguments = ["-L", "https://github.com/yt-dlp/yt-dlp/releases/download/\(latestTag)/yt-dlp_macos", "-o", tempURL.path]
            do { try dlTask.run(); dlTask.waitUntilExit() } catch { return }
            guard FileManager.default.fileExists(atPath: tempURL.path) else { return }

            if let attrs = try? FileManager.default.attributesOfItem(atPath: tempURL.path),
               let size = attrs[.size] as? Int64, size < 1_000_000 {
                try? FileManager.default.removeItem(at: tempURL)
                return
            }

            let newVersion = self?.runCommand(executable: tempURL, arguments: ["--version"]) ?? ""
            guard newVersion == latestVersion else { try? FileManager.default.removeItem(at: tempURL); return }

            do {
                var attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
                let permissions = (attrs[.posixPermissions] as? UInt16) ?? 0o644
                attrs[.posixPermissions] = permissions | 0o111
                try FileManager.default.setAttributes(attrs, ofItemAtPath: tempURL.path)
            } catch {}
            try? FileManager.default.removeItem(at: userYtdlp)
            try? FileManager.default.moveItem(at: tempURL, to: userYtdlp)

            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: self?.lastCheckKey ?? "")
            DispatchQueue.main.async {
                if manual {
                    let alert = NSAlert()
                    alert.messageText = "yt-dlp Updated"
                    alert.informativeText = "Version \(latestVersion) installed."
                    alert.runModal()
                }
            }
        }
    }

    private func runCommand(executable: URL, arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = executable
        task.arguments = arguments
        let pipe = Pipe(); task.standardOutput = pipe
        do { try task.run(); task.waitUntilExit() } catch { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var bestYtdlpPath: String? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let userYtdlp = appSupport.appendingPathComponent("YouTube X/yt-dlp").path
        if FileManager.default.fileExists(atPath: userYtdlp) { return userYtdlp }
        return Bundle.main.path(forResource: "yt-dlp", ofType: nil)
    }
}

// MARK: - FFmpeg Updater (yt-dlp/FFmpeg-Builds – rolling snapshots)
class FfmpegUpdater: ObservableObject {
    static let shared = FfmpegUpdater()
    
    private let lastCheckKey = "FfmpegLastCheck"
    private let checkInterval: TimeInterval = 7 * 24 * 60 * 60
    private var updateInProgress = false
    
    /// Best available ffmpeg path – updated copy in Application Support first, then the bundled one, then Homebrew.
    var bestFfmpegPath: String? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let userFfmpeg = appSupport.appendingPathComponent("YouTube X/ffmpeg").path
        if FileManager.default.fileExists(atPath: userFfmpeg) { return userFfmpeg }
        if let bundled = Bundle.main.path(forResource: "ffmpeg", ofType: nil) { return bundled }
        // Homebrew fallbacks
        for path in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"] {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }
    
    func checkForUpdateIfNeeded(manual: Bool = false) {
        guard !updateInProgress else { return }
        if !manual {
            let last = UserDefaults.standard.double(forKey: lastCheckKey)
            let now = Date().timeIntervalSince1970
            guard now - last >= checkInterval else { return }
        }
        
        updateInProgress = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            defer { DispatchQueue.main.async { self?.updateInProgress = false } }
            
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let ytxDir = appSupport.appendingPathComponent("YouTube X")
            try? FileManager.default.createDirectory(at: ytxDir, withIntermediateDirectories: true)
            let userFfmpeg = ytxDir.appendingPathComponent("ffmpeg")
            
            // Get current version from the best available binary
            let currentPath = self?.bestFfmpegPath ?? ""
            let currentVersion: String
            if !currentPath.isEmpty {
                // ffmpeg version output: "ffmpeg version n7.1 …"
                let raw = self?.runCommand(executable: URL(fileURLWithPath: currentPath), arguments: ["-version"]) ?? ""
                currentVersion = raw.components(separatedBy: " ").dropFirst().first ?? raw
            } else {
                currentVersion = ""
            }
            guard !currentVersion.isEmpty else { return }
            
            /// yt-dlp/FFmpeg-Builds releases are continuous snapshots
           /// Each release tag is something like "n7.1-39-g…" fetch the latest release and find the macOS asset.
            guard let releaseInfo = self?.fetchLatestReleaseInfo(from: "https://api.github.com/repos/yt-dlp/FFmpeg-Builds/releases/latest"),
                  let downloadURL = releaseInfo.url,
                  let latestTag = releaseInfo.tag,
                  let assetName = releaseInfo.assetName else { return }
            
            let latestVersion = latestTag   // e.g., "n7.1-39-g123456"
            if currentVersion.trimmingCharacters(in: .whitespacesAndNewlines) == latestVersion.trimmingCharacters(in: .whitespacesAndNewlines) { return }
            
/// Download the archive (this is a compressed .zip or .tar.xz, not a raw binary which needs to be extracted before they are usable at all).
            let archiveURL = ytxDir.appendingPathComponent(assetName)
            let dlTask = Process()
            dlTask.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            dlTask.arguments = ["-L", downloadURL, "-o", archiveURL.path]
            do { try dlTask.run(); dlTask.waitUntilExit() } catch { return }
            
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: archiveURL.path),
                  let size = attrs[.size] as? Int64, size > 1_000_000 else {
                try? FileManager.default.removeItem(at: archiveURL)
                return
            }
            
            let extractDir = ytxDir.appendingPathComponent("ffmpeg_extract_tmp")
            try? FileManager.default.removeItem(at: extractDir)
            try? FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
            
            let extractTask = Process()
            if assetName.lowercased().hasSuffix(".zip") {
                extractTask.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                extractTask.arguments = ["-q", archiveURL.path, "-d", extractDir.path]
            } else {
                // .tar.xz / .tar.gz - plain `tar -xf` auto-detects the compression.
                extractTask.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                extractTask.arguments = ["-xf", archiveURL.path, "-C", extractDir.path]
            }
            do { try extractTask.run(); extractTask.waitUntilExit() } catch {
                try? FileManager.default.removeItem(at: archiveURL)
                try? FileManager.default.removeItem(at: extractDir)
                return
            }
            try? FileManager.default.removeItem(at: archiveURL)
            
          /// The archive contains a folder structure (typically bin/ffmpeg somewhere inside) -
         /// Search for the actual binary rather than assuming a fixed path, since that structure isn't guaranteed stable across builds.
            guard let enumerator = FileManager.default.enumerator(at: extractDir, includingPropertiesForKeys: nil) else {
                try? FileManager.default.removeItem(at: extractDir)
                return
            }
            var extractedBinary: URL?
            for case let fileURL as URL in enumerator where fileURL.lastPathComponent == "ffmpeg" {
                extractedBinary = fileURL
                break
            }
            guard let binary = extractedBinary else {
                try? FileManager.default.removeItem(at: extractDir)
                return
            }
            
            // Verify the extracted binary's version before installing it.
            let newVersion = self?.runCommand(executable: binary, arguments: ["-version"]) ?? ""
            guard newVersion.contains(latestTag) else {
                try? FileManager.default.removeItem(at: extractDir)
                return
            }
            
            // Make executable
            do {
                var fileAttrs = try FileManager.default.attributesOfItem(atPath: binary.path)
                let permissions = (fileAttrs[.posixPermissions] as? UInt16) ?? 0o644
                fileAttrs[.posixPermissions] = permissions | 0o111
                try FileManager.default.setAttributes(fileAttrs, ofItemAtPath: binary.path)
            } catch {}
            
            try? FileManager.default.removeItem(at: userFfmpeg)
            try? FileManager.default.copyItem(at: binary, to: userFfmpeg)
            try? FileManager.default.removeItem(at: extractDir)
            
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: self?.lastCheckKey ?? "")
        }
    }
    
    // Fetch the latest release and return the macOS asset download URL and tag.
    private func fetchLatestReleaseInfo(from apiURL: String) -> (url: String?, tag: String?, assetName: String?)? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        task.arguments = ["-s", apiURL]
        let pipe = Pipe(); task.standardOutput = pipe
        do { try task.run(); task.waitUntilExit() } catch { return nil }
        guard let data = try? JSONSerialization.jsonObject(with: pipe.fileHandleForReading.readDataToEndOfFile()) as? [String: Any],
              let assets = data["assets"] as? [[String: Any]],
              let tag = data["tag_name"] as? String else { return nil }
        
    /// Find an asset that contains "macos" which is a compressed archive (.zip or .tar.xz), not a raw binary.
    /// The caller needs the name to know how to extract it.
        for asset in assets {
            if let name = asset["name"] as? String,
               name.lowercased().contains("macos"),
               let url = asset["browser_download_url"] as? String {
                return (url, tag, name)
            }
        }
        return (nil, tag, nil)
    }
    
    private func runCommand(executable: URL, arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = executable
        task.arguments = arguments
        let pipe = Pipe(); task.standardOutput = pipe
        do { try task.run(); task.waitUntilExit() } catch { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - App Update Checker
class AppUpdateChecker: ObservableObject {
    static let shared = AppUpdateChecker()
    @Published var updateAvailable = false
    @Published var latestVersion: String?
    let releasesURL = URL(string: "https://github.com/fizzygx/Youtube-X/releases/")!
    private let apiURL = URL(string: "https://api.github.com/repos/fizzygx/Youtube-X/releases/latest")!
    private let lastCheckKey = "AppUpdateLastCheck"
    private let checkInterval: TimeInterval = 24 * 60 * 60

    func checkIfNeeded() {
        let last = UserDefaults.standard.double(forKey: lastCheckKey)
        let now = Date().timeIntervalSince1970
        guard now - last >= checkInterval else { return }
        check()
    }

    func check() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return }
            let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let current = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
            DispatchQueue.main.async {
                self.latestVersion = latest
                self.updateAvailable = Self.isNewer(latest, than: current)
            }
        }.resume()
    }

    private static func isNewer(_ latest: String, than current: String) -> Bool {
        let l = latest.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }
        if l.isEmpty || c.isEmpty { return latest != current }
        for i in 0..<max(l.count, c.count) {
            let lv = i < l.count ? l[i] : 0
            let cv = i < c.count ? c[i] : 0
            if lv != cv { return lv > cv }
        }
        return false
    }
}

// MARK: - Download Manager
class DownloadManager: ObservableObject {
    static let shared = DownloadManager()
    @Published var items: [DownloadItem] = []
    @Published var usedStorage: Int64 = 0
    @Published var unseenCount: Int = 0

    let downloadsDirectory: URL

    private let defaultsKey = "downloadItems"
    private var runningTasks: [UUID: Process] = [:]
    private let minimumValidFileSize: Int64 = 32 * 1024

    init() {
        let paths = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
        downloadsDirectory = paths[0].appendingPathComponent("YouTube X Downloads")
        try? FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        loadItems()
        calculateStorage()
    }

    func clearUnseenBadge() { unseenCount = 0 }

    // MARK: - FFmpeg detection
    private func detectFFmpegPath() -> String? {
        // 1. Updater’s best copy (Application Support or bundled)
        if let path = FfmpegUpdater.shared.bestFfmpegPath, FileManager.default.fileExists(atPath: path) {
            return path
        }
        // 2. Homebrew fallbacks (last resort)
        for path in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"] {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    private func ffmpegArgs() -> [String] {
        guard let path = detectFFmpegPath() else { return [] }
        return ["--ffmpeg-location", path]
    }

    private func showMissingFFmpegAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "ffmpeg Not Found"
            alert.informativeText = "Downloads need ffmpeg to merge video/audio and extract audio correctly. Install it with Homebrew (\"brew install ffmpeg\") and try again."
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    // MARK: - Directory helpers
    private func destinationDirectory(mediaType: MediaType, playlistName: String?) -> URL {
        var dir = downloadsDirectory
        switch mediaType {
        case .videos:
            return dir
        case .audio:
            dir = dir.appendingPathComponent("Audio")
        case .shorts:
            dir = dir.appendingPathComponent("Shorts")
        case .playlists:
            dir = dir.appendingPathComponent("Playlists")
            if let name = playlistName, !name.isEmpty {
                dir = dir.appendingPathComponent(sanitizedFilename(name))
            }
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func sanitizedFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return name.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func uniquePlaylistFolderName(baseName: String) -> String {
        let playlistsDir = downloadsDirectory.appendingPathComponent("Playlists")
        var name = baseName
        var counter = 1
        while FileManager.default.fileExists(atPath: playlistsDir.appendingPathComponent(name).path) {
            counter += 1
            name = "\(baseName) \(counter)"
        }
        return name
    }

    // MARK: - Public API
    func addDownload(video: YouTubeVideo, quality: VideoQuality = .auto) {
        let item = DownloadItem(videoId: video.videoId, title: video.title, thumbnailURL: video.thumbnailURL, addedDate: Date(), mediaType: video.mediaType)
        items.append(item)
        saveItems()
        startDownload(item, quality: quality)
    }

    func startDownload(_ item: DownloadItem, quality: VideoQuality = .auto) {
        if !items.contains(where: { $0.id == item.id }) { items.append(item) }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

        if detectFFmpegPath() == nil {
            items[index].status = .failed
            saveItems()
            showMissingFFmpegAlert()
            return
        }

        items[index].status = .downloading
        saveItems()
        unseenCount += 1

        let ytdlpPath = YtDlpUpdater.shared.bestYtdlpPath ?? "/usr/local/bin/yt-dlp"
        let capturedItem = items[index]
        let destDir = destinationDirectory(mediaType: capturedItem.mediaType, playlistName: capturedItem.playlistName)

        var arguments: [String]

        if capturedItem.isAudio {
            let format = AudioFormat(rawValue: capturedItem.audioFormatRaw ?? "M4A") ?? .m4a
            let outputTemplate = destDir.appendingPathComponent("%(title)s.%(ext)s").path
            arguments = [
                "-f", "bestaudio/best",
                "--extract-audio",
                "--audio-format", format.ytdlpFormat,
                "--audio-quality", "0",
                "--embed-thumbnail",
                "--add-metadata",
            ] + ffmpegArgs() + [
                "-o", outputTemplate,
                "https://www.youtube.com/watch?v=\(capturedItem.videoId)"
            ]
        } else {
            // H.264 video + AAC audio, merged into MP4 – QuickTime compatible
            let outputTemplate = destDir.appendingPathComponent("%(title)s.mp4").path
            arguments = [
                "-f", "bestvideo[ext=mp4][vcodec^=avc1]+bestaudio[ext=m4a]/best[ext=mp4]",
                "--merge-output-format", "mp4",
            ] + ffmpegArgs() + [
                "-o", outputTemplate,
                "https://www.youtube.com/watch?v=\(capturedItem.videoId)"
            ]
        }

        runYtdlp(ytdlpPath: ytdlpPath, arguments: arguments, itemId: capturedItem.id, destDir: destDir)
    }

    func startPlaylistDownload(playlistURL: String, title: String, isAudio: Bool, quality: VideoQuality = .auto, audioFormat: AudioFormat = .m4a) {
        if detectFFmpegPath() == nil {
            showMissingFFmpegAlert()
            return
        }

        var item = DownloadItem(videoId: "", title: title, thumbnailURL: "", addedDate: Date())
        item.mediaType = .playlists
        item.isAudio = isAudio
        item.playlistName = title
        item.audioFormatRaw = audioFormat.rawValue
        items.append(item)
        saveItems()
        unseenCount += 1

        let ytdlpPath = YtDlpUpdater.shared.bestYtdlpPath ?? "/usr/local/bin/yt-dlp"
        let folderName = uniquePlaylistFolderName(baseName: title.isEmpty ? "Playlist" : title)
        let destDir = destinationDirectory(mediaType: .playlists, playlistName: folderName)

        var arguments: [String]
        if isAudio {
            let format = audioFormat
            let outputTemplate = destDir.appendingPathComponent("%(playlist_index)s - %(title)s.%(ext)s").path
            arguments = [
                "--yes-playlist",
                "-f", "bestaudio/best",
                "--extract-audio",
                "--audio-format", format.ytdlpFormat,
                "--audio-quality", "0",
                "--embed-thumbnail",
                "--add-metadata",
            ] + ffmpegArgs() + [
                "-o", outputTemplate,
                playlistURL
            ]
        } else {
            let outputTemplate = destDir.appendingPathComponent("%(playlist_index)s - %(title)s.mp4").path
            arguments = [
                "--yes-playlist",
                "-f", "bestvideo[ext=mp4][vcodec^=avc1]+bestaudio[ext=m4a]/best[ext=mp4]",
                "--merge-output-format", "mp4",
            ] + ffmpegArgs() + [
                "-o", outputTemplate,
                playlistURL
            ]
        }

        runYtdlp(ytdlpPath: ytdlpPath, arguments: arguments, itemId: item.id, destDir: destDir, isPlaylist: true)
    }

    // MARK: - yt-dlp execution
    private func runYtdlp(ytdlpPath: String, arguments: [String], itemId: UUID, destDir: URL, isPlaylist: Bool = false) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            for attempt in 1...3 {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: ytdlpPath)
                task.arguments = arguments

                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = pipe

                var lastDestinationPath: String?
                var playlistTotal = 1
                var playlistCurrent = 1
                var isAudioDownload = false
                if let idx = self.items.firstIndex(where: { $0.id == itemId }) {
                    isAudioDownload = self.items[idx].isAudio
                }

                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }

                    if isPlaylist, let itemRange = output.range(of: #"Downloading item (\d+) of (\d+)"#, options: .regularExpression) {
                        let matched = String(output[itemRange])
                        let nums = matched.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
                        if nums.count >= 2 { playlistCurrent = nums[0]; playlistTotal = max(nums[1], 1) }
                    }

                    if let destRange = output.range(of: #"Destination: (.+)"#, options: .regularExpression) {
                        lastDestinationPath = String(output[destRange]).replacingOccurrences(of: "Destination: ", with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }

                    if output.contains("%"), let percentRange = output.range(of: #"\d+\.\d+%"#, options: .regularExpression) {
                        let p = String(output[percentRange]).dropLast()
                        if let fileProgress = Double(p) {
                            let overall: Double
                            if isPlaylist {
                                let completedFraction = Double(playlistCurrent - 1) / Double(playlistTotal)
                                overall = completedFraction + (fileProgress / 100.0) / Double(playlistTotal)
                            } else {
                                overall = fileProgress / 100.0
                            }
                            DispatchQueue.main.async { [weak self] in
                                if let idx = self?.items.firstIndex(where: { $0.id == itemId }) {
                                    self?.items[idx].progress = min(max(overall, 0), 1)
                                }
                            }
                        }
                    }
                }

                var launchFailed = false
                do {
                    try task.run()
                    DispatchQueue.main.async { self.runningTasks[itemId] = task }
                    task.waitUntilExit()
                } catch {
                    launchFailed = true
                }
                pipe.fileHandleForReading.readabilityHandler = nil

                let exitedCleanly = !launchFailed && task.terminationStatus == 0
                var resolvedURL: URL?
                var verifiedSuccess = false

                if isPlaylist {
                    let contents = (try? FileManager.default.contentsOfDirectory(at: destDir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
                    let validFiles = contents.filter { url in
                        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 else { return false }
                        return size >= self.minimumValidFileSize
                    }
                    verifiedSuccess = exitedCleanly && !validFiles.isEmpty
                    resolvedURL = destDir
                } else {
                    if let destPath = lastDestinationPath, FileManager.default.fileExists(atPath: destPath) {
                        let fileURL = URL(fileURLWithPath: destPath)
                        let size = (try? FileManager.default.attributesOfItem(atPath: destPath)[.size] as? Int64) ?? 0
                        if size >= self.minimumValidFileSize {
                            verifiedSuccess = true
                            resolvedURL = fileURL
                        } else {
                            try? FileManager.default.removeItem(at: fileURL)
                        }
                    } else if exitedCleanly {
                        var expectedExtensions: [String] = []
                        if isAudioDownload {
                            if let idx = self.items.firstIndex(where: { $0.id == itemId }),
                               let formatRaw = self.items[idx].audioFormatRaw {
                                expectedExtensions = [AudioFormat(rawValue: formatRaw)?.ytdlpFormat ?? "m4a"]
                            } else {
                                expectedExtensions = ["m4a", "mp3", "flac", "aac"]
                            }
                        } else {
                            expectedExtensions = ["mp4"]
                        }
                        if let foundURL = self.newestFile(in: destDir, extensions: expectedExtensions, minSize: self.minimumValidFileSize) {
                            verifiedSuccess = true
                            resolvedURL = foundURL
                        }
                    }

                    if verifiedSuccess, isAudioDownload, let url = resolvedURL {
                        let base = url.deletingPathExtension()
                        let thumbnailExtensions = ["webp", "jpg", "jpeg", "png"]
                        for ext in thumbnailExtensions {
                            let thumbURL = base.appendingPathExtension(ext)
                            if FileManager.default.fileExists(atPath: thumbURL.path) {
                                try? FileManager.default.removeItem(at: thumbURL)
                            }
                        }
                    }
                }

                if verifiedSuccess {
                    DispatchQueue.main.async {
                        self.runningTasks[itemId] = nil
                        guard let idx = self.items.firstIndex(where: { $0.id == itemId }) else { return }
                        self.items[idx].status = .completed
                        self.items[idx].progress = 1.0
                        self.items[idx].fileURL = resolvedURL
                        if !isPlaylist {
                            SpotlightIndexer.shared.addDownloadedVideo(self.items[idx])
                        }
                        DownloadNotifications.shared.notifyDownloadComplete(title: self.items[idx].title, fileURL: resolvedURL)
                        self.saveItems()
                        self.calculateStorage()
                    }
                    return
                } else if attempt == 3 {
                    DispatchQueue.main.async {
                        self.runningTasks[itemId] = nil
                        guard let idx = self.items.firstIndex(where: { $0.id == itemId }) else { return }
                        self.items[idx].status = .failed
                        self.saveItems()
                    }
                } else {
                    Thread.sleep(forTimeInterval: 2)
                }
            }
        }
    }

    private func newestFile(in directory: URL, extensions: [String], minSize: Int64) -> URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return nil
        }
        return contents
            .filter { url in
                let ext = url.pathExtension.lowercased()
                guard extensions.contains(ext) else { return false }
                guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, Int64(size) >= minSize else { return false }
                return true
            }
            .sorted {
                let date0 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let date1 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return date0 > date1
            }
            .first
    }

    // MARK: - Additional download management
    func cancelDownload(id: UUID) {
        runningTasks[id]?.terminate()
        runningTasks[id] = nil
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].status = .failed
            saveItems()
        }
    }

    func addAudioDownload(videoId: String, title: String, mediaType: MediaType = .audio, format: AudioFormat = .m4a) {
        var item = DownloadItem(videoId: videoId, title: title, thumbnailURL: "", addedDate: Date())
        item.isAudio = true
        item.mediaType = mediaType
        item.audioFormatRaw = format.rawValue
        startDownload(item)
    }

    func removeDownload(id: UUID) {
        cancelDownload(id: id)
        if let item = items.first(where: { $0.id == id }), item.mediaType != .playlists {
            if let fileURL = item.fileURL {
                try? FileManager.default.removeItem(at: fileURL)
            }
            SpotlightIndexer.shared.removeDownloadedVideo(id: item.id)
        }
        items.removeAll { $0.id == id }
        saveItems()
        calculateStorage()
    }

    func removeCompletedTasks() {
        items.removeAll { $0.status == .completed }
        saveItems()
        calculateStorage()
    }

    func retry(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        if item.mediaType == .playlists { return }
        let video = YouTubeVideo(
            videoId: item.videoId,
            title: item.title,
            thumbnailURL: item.thumbnailURL,
            channelName: "",
            channelAvatarURL: nil,
            viewCount: "",
            publishedAt: "",
            duration: "",
            mediaType: item.mediaType
        )
        removeDownload(id: id)
        if item.isAudio {
            addAudioDownload(videoId: item.videoId, title: item.title, mediaType: item.mediaType, format: AudioFormat(rawValue: item.audioFormatRaw ?? "M4A") ?? .m4a)
        } else {
            addDownload(video: video)
        }
    }

    private func calculateStorage() {
        var total: Int64 = 0
        for item in items where item.status == .completed {
            if let fileURL = item.fileURL,
               let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path) {
                total += (attrs[.size] as? Int64) ?? 0
            }
        }
        usedStorage = total
    }

    private func loadItems() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return }
        items = (try? JSONDecoder().decode([DownloadItem].self, from: data)) ?? []
    }

    func saveItems() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
