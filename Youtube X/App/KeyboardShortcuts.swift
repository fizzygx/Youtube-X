//
//  KeyboardShortcuts.swift
//  Youtube X
//
//  Created by fizzyg on 8/7/26.
//

import Foundation
import SwiftUI
import Combine
import Cocoa
import WebKit

class KeyboardShortcuts {

    // Check if a native text field is focused
    private static func isTextFieldFocused() -> Bool {
        guard let firstResponder = NSApp.keyWindow?.firstResponder else { return false }
        return firstResponder is NSTextView || firstResponder is NSTextField
    }

    // Check if the first responder is inside any WKWebView
    private static func isWebViewFocused() -> Bool {
        guard let firstResponder = NSApp.keyWindow?.firstResponder as? NSView else { return false }
        var view: NSView? = firstResponder
        while let v = view {
            if v is WKWebView { return true }
            view = v.superview
        }
        return false
    }

    static func setup() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let characters = event.charactersIgnoringModifiers else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let cmd = modifiers.contains(.command)
            let shift = modifiers.contains(.shift)

            // Single-key shortcuts: only if NOT in a text field AND NOT inside a WebView
            if !cmd {
                if isTextFieldFocused() || isWebViewFocused() {
                    return event   
                }

                // Shorts Up/Down navigation - handler
                if PlayerManager.shared.isBrowsingShorts {
                    if event.keyCode == 126 { // Up arrow
                        NotificationCenter.default.post(name: .shortsNavigateUp, object: nil)
                        return nil
                    }
                    if event.keyCode == 125 { // Down arrow
                        NotificationCenter.default.post(name: .shortsNavigateDown, object: nil)
                        return nil
                    }
                }

                if !shift {
                    switch characters {
                    case "j": NotificationCenter.default.post(name: .mediaKeySkipBackward, object: nil); return nil
                    case "k": NotificationCenter.default.post(name: .mediaKeyPlayPause, object: nil); return nil
                    case "l": NotificationCenter.default.post(name: .mediaKeySkipForward, object: nil); return nil
                    case "f": NotificationCenter.default.post(name: .toggleFullScreen, object: nil); return nil
                    case "m": NotificationCenter.default.post(name: .toggleMute, object: nil); return nil
                    default: break
                    }
                }

                // Space for play/pause
                if characters == " " && event.keyCode == 49 {
                    NotificationCenter.default.post(name: .mediaKeyPlayPause, object: nil)
                    return nil
                }
            }

            // Command shortcuts (always active)
            if cmd {
                switch characters {
                case "1": NotificationCenter.default.post(name: .navigateToHome, object: nil); return nil
                case "2": NotificationCenter.default.post(name: .navigateToSubscriptions, object: nil); return nil
                case "3": NotificationCenter.default.post(name: .navigateToLibrary, object: nil); return nil
                case "f": NotificationCenter.default.post(name: .toggleFind, object: nil); return nil
                case "d": NotificationCenter.default.post(name: .navigateToDownloads, object: nil); return nil
                case "k": NotificationCenter.default.post(name: .toggleCommandPalette, object: nil); return nil
                case ",":
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    return nil
                default: break
                }
            }
            return event
        }
    }
}

extension Notification.Name {
    static let toggleMute = Notification.Name("toggleMute")
    static let toggleFind = Notification.Name("toggleFind")
    static let navigateToLibrary = Notification.Name("navigateToLibrary")
    static let navigateToDownloads = Notification.Name("navigateToDownloads")
    static let toggleCommandPalette = Notification.Name("toggleCommandPalette")
    static let shortsNavigateUp = Notification.Name("shortsNavigateUp")
    static let shortsNavigateDown = Notification.Name("shortsNavigateDown")
}
