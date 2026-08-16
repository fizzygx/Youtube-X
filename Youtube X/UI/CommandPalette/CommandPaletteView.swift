//
//  CommandPaletteView.swift
//  Youtube X
//
//  Created by fizzyg on 8/7/26.
//

import SwiftUI

struct CommandPaletteView: View {
    @EnvironmentObject var webViewStore: WebViewStore
    @State private var query = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search YouTube…", text: $query)
                .textFieldStyle(.plain)
                .padding()
                .background(.ultraThinMaterial)
                .onSubmit {
                    if !query.isEmpty {
                        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        webViewStore.loadURL("https://www.youtube.com/results?search_query=\(encoded)")
                        dismiss()
                    }
                }
            Button("Search") {
                if !query.isEmpty {
                    let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    webViewStore.loadURL("https://www.youtube.com/results?search_query=\(encoded)")
                    dismiss()
                }
            }
            .padding()
        }
        .frame(width: 400, height: 100)
        .background(.regularMaterial)
    }
}
