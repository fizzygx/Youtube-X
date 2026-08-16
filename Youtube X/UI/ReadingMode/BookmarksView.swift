//
//  BookmarksView.swift
//  Youtube X
//
//  Created by fizzyg on 8/7/26.
//
//Focus mode(to be continued once i get profiles up and running)
import Foundation
import SwiftUI

struct BookmarksView: View {
    @State private var bookmarks: [Bookmark] = []
    var body: some View {
        List(bookmarks) { bm in
            Label(bm.title, systemImage: "bookmark.fill")
        }
    }
}
