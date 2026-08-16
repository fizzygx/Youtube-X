//
//  DownloadModels.swift
//  Youtube X
//
//  Created by fizzyg on 8/7/26.
//

import Foundation

struct DownloadItem: Identifiable, Codable {
    var id = UUID()
    let videoId: String
    let title: String
    let thumbnailURL: String
    var status: DownloadStatus = .queued
    var progress: Double = 0
    var fileURL: URL?
    let addedDate: Date
    var mediaType: MediaType = .videos
    var isAudio: Bool = false
    var playlistName: String? = nil
    var audioFormatRaw: String? = nil
}

enum DownloadStatus: String, Codable {
    case queued, downloading, completed, failed
}

/// Video quality choices to be intergrated in the next release
enum VideoQuality: String, CaseIterable, Identifiable {
    case auto = "Auto (Best)"
    case q2160 = "2160p (4K)"
    case q1440 = "1440p"
    case q1080 = "1080p"
    case q720 = "720p"
    case q480 = "480p"
    case q360 = "360p"

    var id: String { rawValue }

    var formatSelector: String {
        switch self {
        case .auto:
            return "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best"
        case .q2160: return "bestvideo[height<=2160][ext=mp4]+bestaudio[ext=m4a]/best[height<=2160]"
        case .q1440: return "bestvideo[height<=1440][ext=mp4]+bestaudio[ext=m4a]/best[height<=1440]"
        case .q1080: return "bestvideo[height<=1080][ext=mp4]+bestaudio[ext=m4a]/best[height<=1080]"
        case .q720:  return "bestvideo[height<=720][ext=mp4]+bestaudio[ext=m4a]/best[height<=720]"
        case .q480:  return "bestvideo[height<=480][ext=mp4]+bestaudio[ext=m4a]/best[height<=480]"
        case .q360:  return "bestvideo[height<=360][ext=mp4]+bestaudio[ext=m4a]/best[height<=360]"
        }
    }

    var sfSymbol: String {
        switch self {
        case .auto: return "sparkles"
        case .q2160: return "4k.tv"
        case .q1440, .q1080, .q720, .q480, .q360: return "tv"
        }
    }
}

/// Audio format choices yt-dlp + ffmpeg handle the actual transcode; `--embed-thumbnail --add-metadata` (applied in  DownloadManager) takes care of writing the video's title/uploader as track metadata and the thumbnail as embedded cover art
enum AudioFormat: String, CaseIterable, Identifiable {
    case m4a = "M4A"
    case mp3 = "MP3"
    case flac = "FLAC"
    case aac = "AAC"

    var id: String { rawValue }
    var ytdlpFormat: String { rawValue.lowercased() }
}
