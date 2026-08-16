//
//  TabManager.swift
//  Youtube X v1.1
//
//  Created by fizzyg on 5/2/26.
//

import Foundation
import SwiftUI
import WebKit

// MARK: - Tab Item
struct TabItem: Identifiable {
    let id = UUID()
    var url: URL?
    var title: String = "New Tab"
    let webViewStore: WebViewStore
}

// MARK: - Tab Manager
class TabManager: ObservableObject {
    static let shared = TabManager()

    @Published var tabs: [TabItem] = []
    @Published var selectedTabIndex: Int = 0

    init() {
        addTab(url: URL(string: "https://www.youtube.com")!)
    }

    func addTab(url: URL? = nil) {
        let store = WebViewStore(initialURL: url)
        let tab = TabItem(url: url, title: "New Tab", webViewStore: store)
        tabs.append(tab)
        selectedTabIndex = tabs.count - 1
    }

    func closeTab(index: Int) {
        guard tabs.count > 1 else { return }
        tabs.remove(at: index)
        if selectedTabIndex >= tabs.count {
            selectedTabIndex = tabs.count - 1
        }
    }

    func closeCurrentTab() {
        closeTab(index: selectedTabIndex)
    }

    func switchTab(index: Int) {
        guard index >= 0, index < tabs.count else { return }
        selectedTabIndex = index
    }

    var selectedTab: TabItem? {
        guard tabs.indices.contains(selectedTabIndex) else { return nil }
        return tabs[selectedTabIndex]
    }
}

// MARK: - Open New Tab Handler
class OpenNewTabHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "openNewTab",
              let urlString = message.body as? String,
              let url = URL(string: urlString) else { return }
        DispatchQueue.main.async {
            TabManager.shared.addTab(url: url)
        }
    }
}
