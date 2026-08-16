//
//  Models.swift
//  Youtube X
//
//  Created by fizzyg on 8/7/26.
//

import Foundation

// MARK: - MediaType for YouTubeVideo and DownloadItem
enum MediaType: String, Codable, CaseIterable {
    case videos = "Videos"
    case shorts = "Shorts"
    case audio = "Audio"
    case playlists = "Playlists"
}

struct YouTubeVideo: Identifiable, Codable {
    var id = UUID()
    let videoId: String
    let title: String
    let thumbnailURL: String
    let channelName: String
    let channelAvatarURL: String?
    let viewCount: String
    let publishedAt: String
    let duration: String
    var mediaType: MediaType = .videos

    enum CodingKeys: String, CodingKey {
        case videoId, title, thumbnailURL, channelName, channelAvatarURL, viewCount, publishedAt, duration
    }

    static func fromJSON(_ dict: [String: Any]) -> YouTubeVideo? {
        guard let videoId = dict["videoId"] as? String else { return nil }
        return YouTubeVideo(
            videoId: videoId,
            title: dict["title"] as? String ?? "",
            thumbnailURL: dict["thumbnailURL"] as? String ?? "",
            channelName: dict["channelName"] as? String ?? "",
            channelAvatarURL: dict["channelAvatarURL"] as? String,
            viewCount: dict["viewCount"] as? String ?? "",
            publishedAt: dict["publishedAt"] as? String ?? "",
            duration: dict["duration"] as? String ?? ""
        )
    }
}

struct YouTubeChannel: Identifiable, Codable {
    var id = UUID()
    let channelId: String
    let name: String
    let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case channelId, name, avatarURL
    }
}

struct HomeSection: Identifiable {
    var id = UUID()
    let title: String
    let videos: [YouTubeVideo]

    static func fromJSON(_ dict: [String: Any]) -> HomeSection? {
        guard let title = dict["title"] as? String,
              let items = dict["items"] as? [[String: Any]] else { return nil }
        let videos = items.compactMap { YouTubeVideo.fromJSON($0) }
        return HomeSection(title: title, videos: videos)
    }
}

struct Bookmark: Identifiable, Codable {
    var id = UUID()
    let videoId: String
    let timestamp: Double
    let title: String
    let note: String
    let colorLabel: String
}

struct QueueItem: Identifiable, Codable {
    var id = UUID()
    let video: YouTubeVideo
}

struct TranscriptLine: Identifiable {
    var id = UUID()
    let time: Double
    let text: String
}
