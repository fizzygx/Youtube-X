//
//  NotesView.swift
//  Youtube X
//
//  Created by fizzyg on 8/7/26.
//
//Focus mode(to be continued once i get profiles up and running)
import Foundation
import SwiftUI

struct NotesView: View {
    @State private var note = ""
    var body: some View {
        VStack {
            TextEditor(text: $note)
                .font(.body)
            Button("Save Note") {}
        }
    }
}
