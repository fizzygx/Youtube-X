//
//  SpotlightIndexer.swift
//  Youtube X
//
//  Created by fizzyg on 8/7/26.
//

import Foundation
import CoreSpotlight
import CoreServices

class SpotlightIndexer {
    static let shared = SpotlightIndexer()
    private let index = CSSearchableIndex.default()

    func addDownloadedVideo(_ item: DownloadItem) {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .movie)
        attributeSet.title = item.title
        attributeSet.contentDescription = "Downloaded video"
        attributeSet.thumbnailURL = item.fileURL
        attributeSet.addedDate = item.addedDate

        let searchableItem = CSSearchableItem(
            uniqueIdentifier: "download-\(item.id.uuidString)",
            domainIdentifier: "com.youtubex.downloads",
            attributeSet: attributeSet
        )
        index.indexSearchableItems([searchableItem]) { error in
            if let error = error {
                print("Spotlight indexing error: \(error.localizedDescription)")
            }
        }
    }

    func removeDownloadedVideo(id: UUID) {
        index.deleteSearchableItems(withIdentifiers: ["download-\(id.uuidString)"]) { error in
            if let error = error {
                print("Spotlight removal error: \(error.localizedDescription)")
            }
        }
    }
}
