//
//  Youtube X
//
//  Created by fizzyg on 8/7/26.
//

import Foundation
import AppKit
import SwiftUI

// MARK: - SwiftUI wrapper for gesture-enabled view
struct TrackpadGestureView<Content: View>: NSViewRepresentable {
    let content: Content
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void
    let onPinch: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSHostingView<Content> {
        let hosting = NSHostingView(rootView: content)
        
        // Swipe recognizer
        let swipeRecognizer = SwipeGestureRecognizer()
        swipeRecognizer.onSwipeLeft = onSwipeLeft
        swipeRecognizer.onSwipeRight = onSwipeRight
        hosting.addGestureRecognizer(swipeRecognizer)
        
        // Pinch recognizer
        let pinchRecognizer = NSMagnificationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        hosting.addGestureRecognizer(pinchRecognizer)
        
        return hosting
    }

    func updateNSView(_ nsView: NSHostingView<Content>, context: Context) {
        nsView.rootView = content
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPinch: onPinch)
    }

    class Coordinator {
        let onPinch: (CGFloat) -> Void
        init(onPinch: @escaping (CGFloat) -> Void) {
            self.onPinch = onPinch
        }
        @objc func handlePinch(_ sender: NSMagnificationGestureRecognizer) {
            onPinch(sender.magnification)
        }
    }
}

// MARK: - Custom swipe gesture recognizer
private class SwipeGestureRecognizer: NSGestureRecognizer {
    var onSwipeLeft: (() -> Void)?
    var onSwipeRight: (() -> Void)?

    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {
        let dx = event.deltaX
        let dy = event.deltaY
        if abs(dx) > abs(dy) && abs(dx) > 40 {
            if dx > 0 {
                onSwipeRight?()
            } else {
                onSwipeLeft?()
            }
        }
    }
    override func mouseUp(with event: NSEvent) {}
}

// MARK: - Convenience modifier (optional)
extension View {
    func trackpadGestures(onSwipeLeft: @escaping () -> Void = {},
                          onSwipeRight: @escaping () -> Void = {},
                          onPinch: @escaping (CGFloat) -> Void = { _ in }) -> some View {
        TrackpadGestureView(content: self, onSwipeLeft: onSwipeLeft, onSwipeRight: onSwipeRight, onPinch: onPinch)
    }
}
