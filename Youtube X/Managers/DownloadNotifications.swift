//
//  DownloadNotifications.swift
//  Youtube X
//
//  Created by fizzyg on 8/7/26.
//

import Foundation
import UserNotifications

class DownloadNotifications {
    static let shared = DownloadNotifications()

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification auth error: \(error.localizedDescription)")
            }
        }
    }

    func notifyDownloadComplete(title: String, fileURL: URL?) {
        let content = UNMutableNotificationContent()
        content.title = "Download Complete"
        content.body = title
        content.sound = .default

        if let fileURL = fileURL {
            content.userInfo = ["fileURL": fileURL.absoluteString]
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // immediate
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification error: \(error.localizedDescription)")
            }
        }
    }
}
