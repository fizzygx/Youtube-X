//
//  ProfileManager.swift
//  Youtube X
//
//  Created by fizzyg on 8/7/26.
//
// Focus mode(to be continued once i get profiles up and running)
import Foundation
import WebKit
import Combine

struct YouTubeProfile: Identifiable, Codable {
    let id: UUID
    let name: String
    let dataStoreIdentifier: UUID
}

class ProfileManager: ObservableObject {
    static let shared = ProfileManager()
    @Published var profiles: [YouTubeProfile] = []
    @Published var activeProfile: YouTubeProfile

    private let defaultsKey = "profiles"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([YouTubeProfile].self, from: data),
           !saved.isEmpty {
            profiles = saved
            activeProfile = saved.first!
        } else {
            let defaultProfile = YouTubeProfile(id: UUID(), name: "Default", dataStoreIdentifier: UUID())
            profiles = [defaultProfile]
            activeProfile = defaultProfile
            save()
        }
    }

    func addProfile(name: String) {
        let profile = YouTubeProfile(id: UUID(), name: name, dataStoreIdentifier: UUID())
        profiles.append(profile)
        save()
    }

    func switchTo(_ profile: YouTubeProfile) {
        activeProfile = profile
        // The DataWebView/PlayerWebView should use the data store associated with this profile
        // Probably need to post notification so that the engine can recreate its WebViews with the new data store.
        NotificationCenter.default.post(name: .profileDidChange, object: profile)
    }

    func removeProfile(_ profile: YouTubeProfile) {
        profiles.removeAll { $0.id == profile.id }
        if activeProfile.id == profile.id {
            activeProfile = profiles.first ?? YouTubeProfile(id: UUID(), name: "Default", dataStoreIdentifier: UUID())
        }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

extension Notification.Name {
    static let profileDidChange = Notification.Name("profileDidChange")
}
