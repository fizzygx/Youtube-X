//
//  MiniPlayerView.swift
//  Youtube X
//
//  Created by fizzyg on 8/7/26.
//

import SwiftUI
import AVKit

// Local player view to avoid ambiguity
private struct MiniPlayerVideoView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        return view
    }
    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}

struct MiniPlayerView: View {
    @ObservedObject private var playerManager = PlayerManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var showQueue = false
    @State private var showAddSheet = false
    @State private var playlistName = "My Playlist"
    @State private var showSaveAlert = false

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                MiniPlayerVideoView(player: playerManager.player)
                    .frame(minWidth: 320, minHeight: 180)

                HStack(spacing: 8) {
                    Button(action: { playerManager.playPrevious() }) {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(6)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(playerManager.currentIndex <= 0)
                    .help("Previous")

                    Button(action: { playerManager.togglePlayPause() }) {
                        Image(systemName: playerManager.player.timeControlStatus == .playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(6)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Play/Pause (Space)")

                    Button(action: { playerManager.playNext() }) {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(6)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(playerManager.currentIndex >= playerManager.playlist.count - 1)
                    .help("Next")

                    Button(action: { showQueue.toggle() }) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(6)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
            }

            if showQueue {
                VStack(spacing: 0) {
                    HStack {
                        Text("Queue")
                            .font(.headline)
                            .foregroundColor(Color.ytTextPrimary)
                        Spacer()
                        Button(action: { showAddSheet = true }) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(Color.ytRed)
                        .help("Add from offline downloads")
                        Button(action: { playerManager.toggleShuffle() }) {
                            Image(systemName: playerManager.isShuffled ? "shuffle.circle.fill" : "shuffle")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(playerManager.isShuffled ? Color.ytRed : Color.ytTextSecondary)
                        .help("Shuffle")
                        Button(action: { playerManager.toggleRepeat() }) {
                            Image(systemName: playerManager.isRepeating ? "repeat.circle.fill" : "repeat")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(playerManager.isRepeating ? Color.ytRed : Color.ytTextSecondary)
                        .help("Repeat")
                        Text("\(playerManager.playlist.isEmpty ? 0 : playerManager.currentIndex + 1)/\(playerManager.playlist.count)")
                            .font(.caption)
                            .foregroundColor(Color.ytTextSecondary)
                    }
                    .padding(.horizontal).padding(.top, 8)

                    Divider()

                    if playerManager.playlist.isEmpty {
                        VStack(spacing: 8) {
                            Spacer()
                            Image(systemName: "music.note.list").font(.title2).foregroundColor(Color.ytTextSecondary)
                            Text("Queue is empty").font(.caption).foregroundColor(Color.ytTextSecondary)
                            Button("Add from Offline Downloads") { showAddSheet = true }
                                .buttonStyle(.plain)
                                .font(.caption.weight(.medium))
                                .foregroundColor(Color.ytRed)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        List {
                            ForEach(Array(playerManager.playlist.enumerated()), id: \.element) { index, url in
                                HStack {
                                    Text(url.deletingPathExtension().lastPathComponent)
                                        .lineLimit(1)
                                        .font(.caption)
                                        .foregroundColor(Color.ytTextPrimary)
                                    Spacer()
                                    if index == playerManager.currentIndex {
                                        Image(systemName: "play.circle.fill").foregroundColor(Color.ytRed)
                                    }
                                }
                                .listRowSeparator(.visible)
                                .listRowBackground(Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    playerManager.play(url: url, playlist: playerManager.playlist)
                                }
                            }
                            .onMove { source, destination in
                                playerManager.movePlaylist(from: source, to: destination)
                            }
                            .onDelete { offsets in
                                playerManager.removeFromPlaylist(at: offsets)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }

                    Divider()

                    HStack {
                        TextField("Playlist name", text: $playlistName)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") {
                            playerManager.savePlaylist(name: playlistName)
                            showSaveAlert = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(playerManager.playlist.isEmpty)
                    }
                    .padding(.horizontal, 8).padding(.bottom, 8)
                }
                .frame(width: 250)
                .background(Color.ytSurfaceGray)
            }
        }
        .background(Color.ytDarkBackground)
        .onAppear {
            if let url = playerManager.currentVideoURL {
                playerManager.offlineNowPlayingTitle = url.deletingPathExtension().lastPathComponent
                playerManager.isOfflinePlaying = true
            }
        }
        .onDisappear {
            playerManager.stopOfflinePlayback()
        }
        .onChange(of: playerManager.currentVideoURL) { newURL in
            if let url = newURL {
                playerManager.offlineNowPlayingTitle = url.deletingPathExtension().lastPathComponent
                playerManager.isOfflinePlaying = true
            }
        }
        .alert("Playlist Saved", isPresented: $showSaveAlert) {
            Button("OK") {}
        } message: {
            Text("Playlist '\(playlistName)' saved to Offline Downloads > Playlists.")
        }
        .sheet(isPresented: $showAddSheet) {
            AddToQueueSheet(isPresented: $showAddSheet)
        }
    }
}

/// Adding downloaded files to the current queue by browsing what's already in the app, instead of having to go through them in Finder.
private struct AddToQueueSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject private var playerManager = PlayerManager.shared
    @State private var availableFiles: [URL] = []
    @State private var selected: Set<URL> = []

    private let mediaExtensions: Set<String> = ["mp4", "mkv", "mov", "m4a", "mp3", "flac", "aac"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add to Queue").font(.headline).foregroundColor(Color.ytTextPrimary)
                Spacer()
                Button("Cancel") { isPresented = false }.buttonStyle(.plain).foregroundColor(Color.ytTextSecondary)
            }
            .padding()

            Divider()

            if availableFiles.isEmpty {
                VStack {
                    Spacer()
                    Text("No offline downloads found").foregroundColor(Color.ytTextSecondary)
                    Spacer()
                }
            } else {
                List(availableFiles, id: \.self) { url in
                    HStack {
                        Image(systemName: selected.contains(url) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selected.contains(url) ? Color.ytRed : Color.ytTextSecondary)
                        Text(url.deletingPathExtension().lastPathComponent)
                            .lineLimit(1)
                            .foregroundColor(Color.ytTextPrimary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selected.contains(url) { selected.remove(url) } else { selected.insert(url) }
                    }
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

            Divider()

            HStack {
                Spacer()
                Button("Add \(selected.isEmpty ? "" : "(\(selected.count))")") {
                    playerManager.addToPlaylist(Array(selected))
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty)
            }
            .padding()
        }
        .frame(width: 340, height: 400)
        .background(Color.ytSurfaceGray)
        .onAppear { loadAvailableFiles() }
    }

    private func loadAvailableFiles() {
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let root = downloadsDir.appendingPathComponent("YouTube X Downloads")
        var found: [URL] = []
        func scan(_ dir: URL) {
            guard let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
            for url in contents where mediaExtensions.contains(url.pathExtension.lowercased()) {
                found.append(url)
            }
        }
        scan(root)
        scan(root.appendingPathComponent("Shorts"))
        // Already-queued files don't need to be offered again.
        let existing = Set(playerManager.playlist)
        availableFiles = found.filter { !existing.contains($0) }
    }
}
