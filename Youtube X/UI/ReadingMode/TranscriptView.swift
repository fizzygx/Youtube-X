//
//  TranscriptView.swift
//  Youtube X
//
//  Created by fizzyg on 8/7/26.
//
//Focus mode(to be continued once i get profiles up and running)
import Foundation
import SwiftUI

struct TranscriptView: View {
    let lines: [TranscriptLine]
    @State private var searchText = ""
    
    var filteredLines: [TranscriptLine] {
        if searchText.isEmpty { return lines }
        return lines.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack {
            TextField("Search transcript", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding()
            ScrollViewReader { proxy in
                List(filteredLines) { line in
                    HStack(alignment: .top) {
                        Text(timeString(line.time))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .leading)
                        Text(line.text)
                            .font(.body)
                    }
                    .padding(.vertical, 4)
                    .id(line.id)
                }
            }
        }
    }
    
    func timeString(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
