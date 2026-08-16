//
//  PlayerView.swift
//  Youtube X
//
//  Created by fizzyg on 8/7/26.
//

import Foundation
import SwiftUI

struct PlayerView: View {
    let videoId: String
    @State private var isPlaying = false
    @State private var showQueue = false
    @State private var showTranscript = false
    @State private var showNotes = false
    @State private var transcriptLines: [TranscriptLine] = []
    @State private var selectedTab = 0

    var body: some View {
        HStack(spacing: 0) {
            // Video player (stripped WebView)
            PlayerWebView(videoId: videoId, isPlaying: $isPlaying)
                .frame(minWidth: 640)

            if showQueue {
                QueuePanel()
                    .frame(width: 300)
            } else if showTranscript || showNotes {
                VStack(spacing: 0) {
                    Picker("", selection: $selectedTab) {
                        Text("Transcript").tag(0)
                        Text("Notes").tag(1)
                        Text("Bookmarks").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    if selectedTab == 0 {
                        TranscriptView(lines: transcriptLines)
                    } else if selectedTab == 1 {
                        NotesView()
                    } else {
                        BookmarksView()
                    }
                }
                .frame(width: 300)
                .background(.regularMaterial)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                PlayerControlsBar(isPlaying: $isPlaying)
                Button(action: { showQueue.toggle() }) {
                    Image(systemName: "list.bullet")
                }
                Button(action: {
                    showTranscript.toggle()
                    if showTranscript { loadTranscript() }
                    showQueue = false
                }) {
                    Image(systemName: "text.quote")
                }
                Button(action: {
                    showNotes.toggle()
                    showTranscript = false
                    showQueue = false
                }) {
                    Image(systemName: "note.text")
                }
                Button(action: downloadCurrentVideo) {
                    Image(systemName: "arrow.down.circle")
                }
            }
        }
        .onAppear {
            // Optionally load transcript on appear
        }
    }

    private func loadTranscript() {
        let fetcher = TranscriptFetcher()
        fetcher.fetchTranscript(for: videoId) { lines in
            self.transcriptLines = lines
        }
    }

    private func downloadCurrentVideo() {
        let dummy = YouTubeVideo(
            videoId: videoId,
            title: "Video \(videoId)",
            thumbnailURL: "",
            channelName: "",
            channelAvatarURL: nil,
            viewCount: "",
            publishedAt: "",
            duration: ""
        )
        DownloadManager.shared.addDownload(video: dummy)
    }
}

// Simple playback controls bar( Can be connect to PlayerControls.shared)
struct PlayerControlsBar: View {
    @Binding var isPlaying: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { PlayerControls.shared.togglePlayPause() }) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            }
            Button(action: { PlayerControls.shared.skipBackward() }) {
                Image(systemName: "gobackward.10")
            }
            Button(action: { PlayerControls.shared.skipForward() }) {
                Image(systemName: "goforward.10")
            }
            Button(action: { PlayerControls.shared.enterPiP() }) {
                Image(systemName: "pip")
            }
            Button(action: {
                if let window = NSApplication.shared.mainWindow {
                    window.toggleFullScreen(nil)
                }
            }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
        }
    }
}
