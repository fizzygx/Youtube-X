//
//  OfflineStateView.swift
//  Youtube X
//
//  Created by fizzyg on 8/7/26.
//

import SwiftUI
struct OfflineBadgeView: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 12, weight: .semibold))
            Text("Offline")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(.white.opacity(0.85))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color.black.opacity(0.45))
        )
        .padding(14)
        .allowsHitTesting(false)
    }
}
struct OfflineStateView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    let onRetry: () -> Void
    let onGoToOfflineDownloads: () -> Void

    @State private var isRetrying = false

    var body: some View {
        VStack(spacing: 14) {
            illustration

            VStack(spacing: 8) {
                Text("You're Offline")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Color.ytTextPrimary)

                Text("YouTube X can't reach the internet right now.\nCheck your connection, or watch what you've already saved.")
                    .font(.system(size: 13.5))
                    .foregroundColor(Color.ytTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 400)
            }

            HStack(spacing: 10) {
                Button(action: retry) {
                    HStack(spacing: 6) {
                        if isRetrying {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Try Again")
                    }
                    .frame(minWidth: 100)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(action: onGoToOfflineDownloads) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Go to Offline Downloads")
                    }
                    .frame(minWidth: 190)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.ytRed)
                .controlSize(.large)
            }
            .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color.ytDarkBackground)
    }

    private func retry() {
        isRetrying = true
        onRetry()
        /// Brief cooldown so the spinner reads as an actual action rather than a state that's stuck if the network is still down.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            isRetrying = false
        }
    }
    @ViewBuilder
    private var illustration: some View {
        if NSImage(named: "OfflineIllustration") != nil {
            Image("OfflineIllustration")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 400, height: 400)
        } else {
            ZStack {
                Circle()
                    .fill(Color.ytRed.opacity(0.12))
                    .frame(width: 260, height: 260)
                Image(systemName: "wifi.slash")
                    .font(.system(size: 90, weight: .medium))
                    .foregroundColor(Color.ytRed)
            }
        }
    }
}
