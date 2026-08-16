//
//  PlayerControls.swift
//  Youtube X
//
//  Created by fizzyg on 8/7/26.
//

import Foundation
import WebKit

class PlayerControls: ObservableObject {
    static let shared = PlayerControls()
    weak var playerWebView: WKWebView?

    func togglePlayPause() {
        playerWebView?.evaluateJavaScript("(function(){const v=document.querySelector('video');if(v)v.paused?v.play():v.pause()})();")
    }

    func skipForward() {
        playerWebView?.evaluateJavaScript("document.querySelector('video')?.currentTime+=10")
    }

    func skipBackward() {
        playerWebView?.evaluateJavaScript("document.querySelector('video')?.currentTime-=10")
    }

    func enterPiP() {
        playerWebView?.evaluateJavaScript("window.YoutubeX&&window.YoutubeX.togglePip()")
    }
}
