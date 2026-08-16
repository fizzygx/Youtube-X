//
//  NetworkMonitor.swift
//  Youtube X
//
//  Created by fizzyg on 8/7/26.
//

import Foundation
import Network
import Combine

class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isConnected = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.youtubex.networkmonitor")
    private let session: URLSession
    private var verificationTask: URLSessionDataTask?
    private var verificationTimer: Timer?

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 4
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            if path.status != .satisfied {
    /// No link-layer route at all - unambiguous, no need to verify further, and no point polling while it's down.
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.stopPeriodicVerification()
                }
            } else {
    /// Link looks up: Confirm it's actually real before trusting it, then keep re-checking periodically in case it degrades (captive portal expires, router drops WAN, etc.) without the link layer itself ever changing state.
                self.verifyRealConnectivity()
                self.startPeriodicVerification()
            }
        }
        monitor.start(queue: queue)
    }

    private func startPeriodicVerification() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.verificationTimer == nil else { return }
            self.verificationTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                self?.verifyRealConnectivity()
            }
        }
    }

    private func stopPeriodicVerification() {
        DispatchQueue.main.async { [weak self] in
            self?.verificationTimer?.invalidate()
            self?.verificationTimer = nil
        }
    }

    private func verifyRealConnectivity() {
        verificationTask?.cancel()
        guard let url = URL(string: "https://www.youtube.com/generate_204") else { return }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let task = session.dataTask(with: request) { [weak self] _, response, _ in
            let reachable = (response as? HTTPURLResponse).map { (200...399).contains($0.statusCode) } ?? false
            DispatchQueue.main.async {
                self?.isConnected = reachable
            }
        }
        verificationTask = task
        task.resume()
    }
}
/// NetworkMonitor.swift
/// Watches system-level network reachability so the UI can react when there is genuine no connection (as opposed to YouTube itself being
/// slow/down, which the WebView's own load states already handle).
/// NWPathMonitor alone only confirms a link-layer route exists  by reporting "satisfied" for a Wi-Fi connection with no real internet behind it
/// (captive portals, a router with a dead WAN link, etc.) and says nothing about whether YouTube specifically is reachable.
/// So on top of the fast link-layer signal, this verifies real reachability with a lightweight request against YouTube's own connectivity-check
/// endpoint derived from the same pattern Google's own apps use, and specifically what matters for this app rather than internet
/// reachability in general.
