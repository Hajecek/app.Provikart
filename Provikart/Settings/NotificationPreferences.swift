//
//  NotificationPreferences.swift
//  Provikart
//
//  Přepínače push notifikací podle role (manažer / uživatel).
//  Lokálně persistované, synchronizované přes FCM témata a backend.
//

import Foundation
import SwiftUI
import FirebaseMessaging

/// Typ push oznámení, který jde v nastavení zapnout / vypnout.
enum NotificationChannel: String, CaseIterable, Identifiable {
    // Uživatel (obchodník)
    case userOrders
    case userProblems
    case userInstallations
    case userAttendance
    case userRewards
    case userGeneral

    // Manažer
    case managerBirthdays
    case managerProblemUpdates
    case managerDeferredSales
    case managerIncompleteOrders
    case managerAttendance
    case managerGeneral

    var id: String { rawValue }

    var role: UserRole {
        switch self {
        case .userOrders, .userProblems, .userInstallations, .userAttendance, .userRewards, .userGeneral:
            return .user
        case .managerBirthdays, .managerProblemUpdates, .managerDeferredSales,
             .managerIncompleteOrders, .managerAttendance, .managerGeneral:
            return .manager
        }
    }

    var title: String {
        switch self {
        case .userOrders: return "Objednávky"
        case .userProblems: return "Problémy"
        case .userInstallations: return "Instalace"
        case .userAttendance: return "Docházka"
        case .userRewards: return "Odměny a cíle"
        case .userGeneral: return "Obecná oznámení"
        case .managerBirthdays: return "Narozeniny"
        case .managerProblemUpdates: return "Vývoj problémů"
        case .managerDeferredSales: return "Odložené prodeje"
        case .managerIncompleteOrders: return "Nedokončené objednávky"
        case .managerAttendance: return "Docházka týmu"
        case .managerGeneral: return "Obecná oznámení"
        }
    }

    var subtitle: String {
        switch self {
        case .userOrders: return "Stav a změny vašich objednávek"
        case .userProblems: return "Aktualizace nahlášených problémů"
        case .userInstallations: return "Připomínky termínů instalací"
        case .userAttendance: return "Změny ve vaší docházce"
        case .userRewards: return "Lucky Box, Deal Wars a provize"
        case .userGeneral: return "Novinky a systémová oznámení"
        case .managerBirthdays: return "Narozeniny členů týmu"
        case .managerProblemUpdates: return "Nové záznamy a vývoj reportů"
        case .managerDeferredSales: return "Odložené prodeje v týmu"
        case .managerIncompleteOrders: return "Nedokončené objednávky týmu"
        case .managerAttendance: return "Docházka a absence týmu"
        case .managerGeneral: return "Novinky a systémová oznámení"
        }
    }

    var systemImage: String {
        switch self {
        case .userOrders: return "shippingbox.fill"
        case .userProblems: return "exclamationmark.bubble.fill"
        case .userInstallations: return "wrench.and.screwdriver.fill"
        case .userAttendance: return "person.badge.clock.fill"
        case .userRewards: return "gift.fill"
        case .userGeneral: return "bell.fill"
        case .managerBirthdays: return "birthday.cake.fill"
        case .managerProblemUpdates: return "text.bubble.fill"
        case .managerDeferredSales: return "clock.arrow.circlepath"
        case .managerIncompleteOrders: return "cart.badge.minus"
        case .managerAttendance: return "person.3.fill"
        case .managerGeneral: return "bell.fill"
        }
    }

    /// Klíč pro API / FCM payload.
    var apiKey: String {
        switch self {
        case .userOrders: return "user_orders"
        case .userProblems: return "user_problems"
        case .userInstallations: return "user_installations"
        case .userAttendance: return "user_attendance"
        case .userRewards: return "user_rewards"
        case .userGeneral: return "user_general"
        case .managerBirthdays: return "manager_birthdays"
        case .managerProblemUpdates: return "manager_problem_updates"
        case .managerDeferredSales: return "manager_deferred_sales"
        case .managerIncompleteOrders: return "manager_incomplete_orders"
        case .managerAttendance: return "manager_attendance"
        case .managerGeneral: return "manager_general"
        }
    }

    var fcmTopic: String { "pk_\(apiKey)" }

    static func channels(for role: UserRole) -> [NotificationChannel] {
        switch role {
        case .manager:
            return [
                .managerBirthdays,
                .managerProblemUpdates,
                .managerDeferredSales,
                .managerIncompleteOrders,
                .managerAttendance,
                .managerGeneral
            ]
        case .user, .unknown:
            return [
                .userOrders,
                .userProblems,
                .userInstallations,
                .userAttendance,
                .userRewards,
                .userGeneral
            ]
        }
    }

    static func resolve(userInfo: [AnyHashable: Any], role: UserRole) -> NotificationChannel {
        let key = payloadString(userInfo, keys: ["key", "notification_key", "type", "notification_type", "category", "kind"])
        let typeLabel = payloadString(userInfo, keys: ["type_label", "typeLabel", "label"])
        let title = alertTitle(from: userInfo)
        let body = alertBody(from: userInfo)

        if role == .manager {
            let category = ManagerNotificationCategory.resolve(
                key: key,
                typeLabel: typeLabel,
                icon: payloadString(userInfo, keys: ["icon"]),
                title: title,
                body: body
            )
            switch category {
            case .birthdays: return .managerBirthdays
            case .problemUpdates: return .managerProblemUpdates
            case .deferredSales: return .managerDeferredSales
            case .incompleteOrders: return .managerIncompleteOrders
            case .other:
                if matchesAttendance(key: key, typeLabel: typeLabel, title: title, body: body) {
                    return .managerAttendance
                }
                return .managerGeneral
            }
        }

        let haystack = [key, typeLabel, title, body]
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
            .lowercased()

        if haystack.contains("order") || haystack.contains("objednav") || haystack.contains("shipping") {
            return .userOrders
        }
        if haystack.contains("problem") || haystack.contains("report") || haystack.contains("vyvoj") {
            return .userProblems
        }
        if haystack.contains("install") || haystack.contains("instalac") || haystack.contains("calendar") {
            return .userInstallations
        }
        if matchesAttendance(key: key, typeLabel: typeLabel, title: title, body: body) {
            return .userAttendance
        }
        if haystack.contains("lucky") || haystack.contains("reward") || haystack.contains("odmen")
            || haystack.contains("dealwar") || haystack.contains("proviz") || haystack.contains("chest")
            || haystack.contains("goal") || haystack.contains("cil") {
            return .userRewards
        }
        return .userGeneral
    }

    private static func matchesAttendance(key: String, typeLabel: String, title: String, body: String) -> Bool {
        let haystack = [key, typeLabel, title, body]
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
            .lowercased()
        return haystack.contains("attendance") || haystack.contains("dochazk") || haystack.contains("absence")
    }

    private static func payloadString(_ userInfo: [AnyHashable: Any], keys: [String]) -> String {
        for key in keys {
            if let value = userInfo[key] as? String, !value.isEmpty { return value }
            if let value = userInfo[key] as? NSNumber { return value.stringValue }
        }
        return ""
    }

    private static func alertTitle(from userInfo: [AnyHashable: Any]) -> String {
        let title = payloadString(userInfo, keys: ["title", "notification_title"])
        if !title.isEmpty { return title }
        guard let aps = userInfo["aps"] as? [AnyHashable: Any] else { return "" }
        if let alert = aps["alert"] as? [AnyHashable: Any] {
            return (alert["title"] as? String) ?? ""
        }
        return ""
    }

    private static func alertBody(from userInfo: [AnyHashable: Any]) -> String {
        let body = payloadString(userInfo, keys: ["body", "message", "notification_body"])
        if !body.isEmpty { return body }
        guard let aps = userInfo["aps"] as? [AnyHashable: Any] else { return "" }
        if let alert = aps["alert"] as? String { return alert }
        if let alert = aps["alert"] as? [AnyHashable: Any] {
            return (alert["body"] as? String) ?? ""
        }
        return ""
    }
}

final class NotificationPreferencesStore: ObservableObject {
    static let shared = NotificationPreferencesStore()

    private enum Keys {
        static let master = "settings.notifications.master"
        static func channel(_ id: String) -> String { "settings.notifications.channel.\(id)" }
    }

    private let defaults = UserDefaults.standard

    @Published var masterEnabled: Bool {
        didSet {
            defaults.set(masterEnabled, forKey: Keys.master)
            defaults.set(masterEnabled, forKey: "Provikart.notificationsEnabled")
        }
    }

    private var channelEnabled: [NotificationChannel: Bool]

    private init() {
        let storedMaster = defaults.object(forKey: Keys.master) as? Bool
        let legacyEnabled = defaults.object(forKey: "Provikart.notificationsEnabled") as? Bool
        masterEnabled = storedMaster ?? legacyEnabled ?? true

        let legacyGeneral = defaults.object(forKey: "settings.notifications.general") as? Bool
        let legacyOrders = defaults.object(forKey: "settings.notifications.orders") as? Bool

        var map: [NotificationChannel: Bool] = [:]
        for channel in NotificationChannel.allCases {
            if let stored = defaults.object(forKey: Keys.channel(channel.rawValue)) as? Bool {
                map[channel] = stored
            } else {
                switch channel {
                case .userOrders:
                    map[channel] = legacyOrders ?? true
                case .userGeneral, .managerGeneral:
                    map[channel] = legacyGeneral ?? true
                default:
                    map[channel] = true
                }
            }
        }
        channelEnabled = map
    }

    func isEnabled(_ channel: NotificationChannel) -> Bool {
        channelEnabled[channel] ?? true
    }

    func setEnabled(_ channel: NotificationChannel, _ enabled: Bool) {
        objectWillChange.send()
        channelEnabled[channel] = enabled
        defaults.set(enabled, forKey: Keys.channel(channel.rawValue))
    }

    func binding(for channel: NotificationChannel) -> Binding<Bool> {
        Binding(
            get: { self.isEnabled(channel) },
            set: { self.setEnabled(channel, $0) }
        )
    }

    func enabledCount(for role: UserRole) -> Int {
        NotificationChannel.channels(for: role).filter { isEnabled($0) }.count
    }

    /// Má se push v popředí vůbec ukázat. Čte přímo UserDefaults, aby šlo volat i mimo main thread.
    func shouldPresent(userInfo: [AnyHashable: Any], role: UserRole) -> Bool {
        let master = defaults.object(forKey: Keys.master) as? Bool
            ?? defaults.object(forKey: "Provikart.notificationsEnabled") as? Bool
            ?? true
        guard master else { return false }
        let channel = NotificationChannel.resolve(userInfo: userInfo, role: role)
        return defaults.object(forKey: Keys.channel(channel.rawValue)) as? Bool ?? true
    }

    func apiPayload(role: UserRole) -> [String: Any] {
        var channels: [String: Bool] = [:]
        for channel in NotificationChannel.channels(for: role) {
            channels[channel.apiKey] = isEnabled(channel)
        }
        return [
            "role": role.rawValue,
            "enabled": masterEnabled,
            "channels": channels
        ]
    }

    func applyTopicSubscriptions(role: UserRole) {
        for channel in NotificationChannel.allCases {
            let want = masterEnabled && channel.role == role && isEnabled(channel)
            if want {
                Messaging.messaging().subscribe(toTopic: channel.fcmTopic) { _ in }
            } else {
                Messaging.messaging().unsubscribe(fromTopic: channel.fcmTopic) { _ in }
            }
        }

        let wantBroadcast = masterEnabled && isEnabled(role == .manager ? .managerGeneral : .userGeneral)
        if wantBroadcast {
            Messaging.messaging().subscribe(toTopic: "all_users") { _ in }
        } else {
            Messaging.messaging().unsubscribe(fromTopic: "all_users") { _ in }
        }
    }
}
