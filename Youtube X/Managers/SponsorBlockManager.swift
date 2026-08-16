//
//  SponsorBlockManager.swift
//  Youtube X
//
//  Created by fizzyg on 8/7/26.
//

import Foundation
import SwiftUI

struct SponsorSegment: Codable, Equatable {
    let category: String
    let segment: [Double] // [startSeconds, endSeconds]
}
//(N.B need to fix when it silently fails with videos TBD)
class SponsorBlockManager: ObservableObject {
    static let shared = SponsorBlockManager()

    @AppStorage("sponsorBlockEnabled") var isEnabled: Bool = false
    @AppStorage("sponsorBlockShowNotice") var showSkipNotice: Bool = true
    /// Comma-separated category IDs, since AppStorage can't directly store a Set.
    @AppStorage("sponsorBlockCategoriesRaw") private var categoriesRaw: String = "sponsor,selfpromo,interaction"

    var enabledCategories: Set<String> {
        get { Set(categoriesRaw.split(separator: ",").map(String.init)) }
        set { categoriesRaw = newValue.sorted().joined(separator: ",") }
    }

    static let allCategories: [(id: String, label: String)] = [
        ("sponsor", "Sponsor"),
        ("intro", "Intro"),
        ("outro", "Outro"),
        ("selfpromo", "Self-Promo"),
        ("interaction", "Interaction Reminder"),
    ]

    private var cache: [String: (segments: [SponsorSegment], fetchedAt: Date)] = [:]
    private let cacheExpiry: TimeInterval = 7 * 24 * 60 * 60
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        session = URLSession(configuration: config)
        loadCacheFromDisk()
    }

    /// Fetches segments for a video, using the cache when available and fresh. Always calls back on the main queue.
    /// Any failure (network error, timeout, rate limit, no segments found) should resolve to an empty array rather than throwing
    /// callers should treat that as "just play normally".
    func segments(for videoId: String, completion: @escaping ([SponsorSegment]) -> Void) {
        guard isEnabled, !videoId.isEmpty else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        if let cached = cache[videoId], Date().timeIntervalSince(cached.fetchedAt) < cacheExpiry {
            DispatchQueue.main.async { completion(cached.segments) }
            return
        }

        let categories = Array(enabledCategories)
        guard !categories.isEmpty,
              let categoriesJSON = try? JSONEncoder().encode(categories),
              let categoriesString = String(data: categoriesJSON, encoding: .utf8),
              let encodedCategories = categoriesString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://sponsor.ajay.app/api/skipSegments?videoID=\(videoId)&categories=\(encodedCategories)") else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        var request = URLRequest(url: url)
        request.setValue("YouTubeX-macOS/1.0 (+https://github.com/fizzygx/Youtube-X)", forHTTPHeaderField: "User-Agent")

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
        /// 404 from this API specifically means "no segments submitted for this video" a normal, expected outcome, not an error
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                DispatchQueue.main.async {
                    self.cache[videoId] = ([], Date())
                    completion([])
                }
                return
            }

            guard error == nil, let data = data,
                  let decoded = try? JSONDecoder().decode([SponsorSegment].self, from: data) else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            DispatchQueue.main.async {
                self.cache[videoId] = (decoded, Date())
                self.persistCacheToDisk()
                completion(decoded)
            }
        }
        task.resume()
    }

    // MARK: - Disk cache

    private struct CacheEntry: Codable {
        let videoId: String
        let segments: [SponsorSegment]
        let fetchedAt: Date
    }

    private var cacheFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("YouTube X")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sponsorblock_cache.json")
    }

    private func persistCacheToDisk() {
        let entries = cache.map { CacheEntry(videoId: $0.key, segments: $0.value.segments, fetchedAt: $0.value.fetchedAt) }
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: cacheFileURL)
        }
    }

    private func loadCacheFromDisk() {
        guard let data = try? Data(contentsOf: cacheFileURL),
              let entries = try? JSONDecoder().decode([CacheEntry].self, from: data) else { return }
        let now = Date()
        for entry in entries where now.timeIntervalSince(entry.fetchedAt) < cacheExpiry {
            cache[entry.videoId] = (entry.segments, entry.fetchedAt)
        }
    }
}
