//
//  QueueManager.swift
//  Youtube X
//
//  Created by fizzyg on 8/7/26.
//

import Foundation
import SwiftUI

class QueueManager: ObservableObject {
    static let shared = QueueManager()
    @Published var queue: [QueueItem] = []
    
    func add(_ video: YouTubeVideo) { queue.append(QueueItem(video: video)) }
    func move(from source: IndexSet, to destination: Int) { queue.move(fromOffsets: source, toOffset: destination) }
    func remove(at offsets: IndexSet) { queue.remove(atOffsets: offsets) }
}
