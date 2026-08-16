//
//  QueuePanel.swift
//  Youtube X
//
//  Created by fizzyg on 8/7/26.
//

import Foundation
import SwiftUI

struct QueuePanel: View {
    @StateObject private var manager = QueueManager.shared
    
    var body: some View {
        List {
            Section("Now Playing") {
                Text("Current Video")
            }
            Section("Next") {
                ForEach(manager.queue) { item in
                    HStack {
                        AsyncImage(url: URL(string: item.video.thumbnailURL)) { img in
                            img.resizable().frame(width: 60, height: 34).cornerRadius(4)
                        } placeholder: {
                            Rectangle().fill(Color.gray).frame(width: 60, height: 34)
                        }
                        VStack(alignment: .leading) {
                            Text(item.video.title).font(.caption).lineLimit(2)
                            Text(item.video.channelName).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
                .onMove(perform: manager.move)
                .onDelete(perform: manager.remove)
            }
        }
        .listStyle(.plain)
        .background(.ultraThinMaterial)
    }
}
