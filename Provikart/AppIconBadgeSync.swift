//
//  AppIconBadgeSync.swift
//  Provikart
//
//  Badge na ikoně aplikace při příchodu push notifikace (klasické chování).
//

import Foundation
import UIKit
import UserNotifications

enum AppIconBadgeSync {
    /// Nastaví badge z APNs payloadu, případně z API (manažer), jinak +1.
    static func apply(
        from userInfo: [AnyHashable: Any],
        authToken: String?,
        userRole: String?,
        completion: ((UIBackgroundFetchResult) -> Void)? = nil
    ) {
        if let badge = badgeValue(from: userInfo) {
            setBadge(badge)
            completion?(.newData)
            return
        }

        let role = (userRole ?? "").lowercased()
        let isManager = role == "manager" || role == "admin"
        let token = authToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard isManager, !token.isEmpty else {
            // Fallback bez API: zvýš aktuální badge o 1 (klasika „přišla nová notifikace“).
            incrementBadge(by: 1)
            completion?(.noData)
            return
        }

        Task {
            do {
                let payload = try await ManagerNotificationsService().fetchNotifications(token: token, limit: 1)
                await setBadgeAsync(payload.unreadCount)
                NotificationCenter.default.post(
                    name: .managerNotificationsUnreadDidUpdate,
                    object: nil,
                    userInfo: ["unread_count": payload.unreadCount]
                )
                completion?(.newData)
            } catch {
                await MainActor.run {
                    incrementBadge(by: 1)
                }
                completion?(.failed)
            }
        }
    }

    static func setBadge(_ count: Int) {
        let value = max(0, count)
        Task { @MainActor in
            try? await UNUserNotificationCenter.current().setBadgeCount(value)
        }
    }

    static func setBadgeAsync(_ count: Int) async {
        let value = max(0, count)
        try? await UNUserNotificationCenter.current().setBadgeCount(value)
    }

    private static func incrementBadge(by delta: Int) {
        Task { @MainActor in
            let current = UIApplication.shared.applicationIconBadgeNumber
            try? await UNUserNotificationCenter.current().setBadgeCount(max(0, current + delta))
        }
    }

    /// `aps.badge` nebo vlastní `unread_count` z FCM data.
    static func badgeValue(from userInfo: [AnyHashable: Any]) -> Int? {
        if let aps = userInfo["aps"] as? [String: Any] {
            if let intBadge = aps["badge"] as? Int {
                return max(0, intBadge)
            }
            if let number = aps["badge"] as? NSNumber {
                return max(0, number.intValue)
            }
            if let string = aps["badge"] as? String, let intBadge = Int(string) {
                return max(0, intBadge)
            }
        }

        for key in ["unread_count", "unreadCount", "badge"] {
            if let intValue = userInfo[key] as? Int {
                return max(0, intValue)
            }
            if let number = userInfo[key] as? NSNumber {
                return max(0, number.intValue)
            }
            if let string = userInfo[key] as? String, let intValue = Int(string) {
                return max(0, intValue)
            }
        }
        return nil
    }
}

extension Notification.Name {
    static let managerNotificationsUnreadDidUpdate = Notification.Name("managerNotificationsUnreadDidUpdate")
}
