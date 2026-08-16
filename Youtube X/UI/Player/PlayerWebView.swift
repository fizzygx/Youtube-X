//
//  PlayerWebView.swift
//  Youtube X
//
//  Created by fizzyg on 8/7/26.
//

import Foundation
import SwiftUI
import WebKit

import SwiftUI
import WebKit

struct PlayerWebView: NSViewRepresentable {
    let videoId: String
    @Binding var isPlaying: Bool

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        webView.load(URLRequest(url: URL(string: "https://www.youtube.com/watch?v=\(videoId)")!))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(isPlaying: $isPlaying)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var isPlaying: Bool

        init(isPlaying: Binding<Bool>) {
            _isPlaying = isPlaying
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Hide YouTube UI, keep only player
            let js = """
            var s = document.createElement('style');
            s.textContent = '#masthead-container, #secondary, #below, #header, ytd-watch-metadata, ytd-comments, #panels, ytd-live-chat-frame { display:none!important; } #player-theater-container, #player-container, #movie_player { position:fixed!important; top:0; left:0; width:100%!important; height:100%!important; z-index:9999; }';
            document.head.appendChild(s);
            var v = document.querySelector('video');
            if (v) {
                v.addEventListener('play', function() { window.webkit.messageHandlers.playerState.postMessage('playing'); });
                v.addEventListener('pause', function() { window.webkit.messageHandlers.playerState.postMessage('paused'); });
            }
            """
            webView.evaluateJavaScript(js)
            webView.configuration.userContentController.add(self, name: "playerState")

            // CRITICAL: register this web view with the shared controls[hopefuly]
            PlayerControls.shared.playerWebView = webView
        }
    }
}

extension PlayerWebView.Coordinator: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "playerState", let state = message.body as? String {
            isPlaying = (state == "playing")
        }
    }
}
