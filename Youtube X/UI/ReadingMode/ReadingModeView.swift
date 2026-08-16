//
//  Youtube X
//
//  Created by fizzyg on 8/7/26.
//

//Focus mode (to be continued once i get profiles up and running)
import SwiftUI

struct ReadingModeView: View {
    let videoId: String
    @State private var selectedTab = 0
    @State private var transcriptLines: [TranscriptLine] = []

    var body: some View {
        HStack(spacing: 0) {
            // Video player (stripped WebView)
            PlayerWebView(videoId: videoId, isPlaying: .constant(false))
                .frame(minWidth: 640)

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
        .onAppear {
            loadTranscript()
        }
    }

    private func loadTranscript() {
        let fetcher = TranscriptFetcher()
        fetcher.fetchTranscript(for: videoId) { lines in
            self.transcriptLines = lines
        }
    }
}
