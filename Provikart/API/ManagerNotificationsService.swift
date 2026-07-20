//
//  ManagerNotificationsService.swift
//  Provikart
//
//  Notifikační inbox manažera:
//  GET /api/manager_notifications.php
//  POST /api/manager_notifications_read.php
//

import Foundation

struct ManagerNotificationItem: Decodable, Identifiable, Hashable {
    var id: String { key }

    let key: String
    let report_id: Int?
    let title: String
    let body: String?
    let type_label: String?
    let icon: String?
    let created_at: String?
    let user_name: String?
    let avatar_url: String?
    let is_read: Bool

    enum CodingKeys: String, CodingKey {
        case key, report_id, title, body, type_label, icon, created_at, user_name, avatar_url, is_read
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        if let intId = try? c.decodeIfPresent(Int.self, forKey: .report_id) {
            report_id = intId
        } else if let stringId = try? c.decodeIfPresent(String.self, forKey: .report_id),
                  let intId = Int(stringId) {
            report_id = intId
        } else {
            report_id = nil
        }
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        body = try c.decodeIfPresent(String.self, forKey: .body)
        type_label = try c.decodeIfPresent(String.self, forKey: .type_label)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        created_at = try c.decodeIfPresent(String.self, forKey: .created_at)
        user_name = try c.decodeIfPresent(String.self, forKey: .user_name)
        avatar_url = try c.decodeIfPresent(String.self, forKey: .avatar_url)
        if let boolRead = try? c.decode(Bool.self, forKey: .is_read) {
            is_read = boolRead
        } else if let intRead = try? c.decode(Int.self, forKey: .is_read) {
            is_read = intRead == 1
        } else if let stringRead = try? c.decode(String.self, forKey: .is_read) {
            is_read = ["1", "true", "yes"].contains(stringRead.lowercased())
        } else {
            is_read = false
        }
    }

    init(
        key: String,
        report_id: Int?,
        title: String,
        body: String?,
        type_label: String?,
        icon: String?,
        created_at: String?,
        user_name: String?,
        avatar_url: String?,
        is_read: Bool
    ) {
        self.key = key
        self.report_id = report_id
        self.title = title
        self.body = body
        self.type_label = type_label
        self.icon = icon
        self.created_at = created_at
        self.user_name = user_name
        self.avatar_url = avatar_url
        self.is_read = is_read
    }

    var avatarURL: URL? {
        guard let raw = avatar_url?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return URL(string: raw)
    }

    /// Font Awesome class → SF Symbol.
    var systemImageName: String {
        let raw = (icon ?? "").lowercased()
        if raw.contains("cake") || raw.contains("gift") || raw.contains("birthday") { return "birthday.cake.fill" }
        if raw.contains("triangle") || raw.contains("exclamation") { return "exclamationmark.triangle.fill" }
        if raw.contains("check") { return "checkmark.circle.fill" }
        if raw.contains("clock") || raw.contains("time") { return "clock.arrow.circlepath" }
        if raw.contains("user") || raw.contains("person") { return "person.crop.circle.fill" }
        if raw.contains("calendar") { return "calendar" }
        if raw.contains("cart") || raw.contains("shopping") { return "cart.badge.minus" }
        if raw.contains("bell") { return "bell.fill" }
        if raw.contains("flag") { return "flag.fill" }
        if raw.contains("info") { return "info.circle.fill" }
        return category.systemImage
    }

    var category: ManagerNotificationCategory {
        ManagerNotificationCategory.resolve(
            key: key,
            typeLabel: type_label,
            icon: icon,
            title: title,
            body: body
        )
    }

    func withReadState(_ isRead: Bool) -> ManagerNotificationItem {
        ManagerNotificationItem(
            key: key,
            report_id: report_id,
            title: title,
            body: body,
            type_label: type_label,
            icon: icon,
            created_at: created_at,
            user_name: user_name,
            avatar_url: avatar_url,
            is_read: isRead
        )
    }
}

/// Kategorie notifikačního inboxu – podle `key` / `type_label` / textu.
enum ManagerNotificationCategory: Hashable, Identifiable, Comparable {
    case birthdays
    case problemUpdates
    case deferredSales
    case incompleteOrders
    case other

    /// Filtry vždy dostupné v UI (bez „Ostatní“).
    static let filterCases: [ManagerNotificationCategory] = [
        .birthdays,
        .problemUpdates,
        .deferredSales,
        .incompleteOrders
    ]

    var id: String { sortKey }

    var title: String {
        switch self {
        case .birthdays: return "Narozeniny"
        case .problemUpdates: return "Vývoj"
        case .deferredSales: return "Odložené"
        case .incompleteOrders: return "Nedokončené"
        case .other: return "Ostatní"
        }
    }

    var subtitle: String {
        switch self {
        case .birthdays: return "Narozeniny týmu"
        case .problemUpdates: return "Vývoj problémů"
        case .deferredSales: return "Odložené prodeje"
        case .incompleteOrders: return "Nedokončené objednávky"
        case .other: return "Ostatní oznámení"
        }
    }

    var systemImage: String {
        switch self {
        case .birthdays: return "birthday.cake.fill"
        case .problemUpdates: return "text.bubble.fill"
        case .deferredSales: return "clock.arrow.circlepath"
        case .incompleteOrders: return "cart.badge.minus"
        case .other: return "bell.fill"
        }
    }

    private var sortKey: String {
        switch self {
        case .birthdays: return "0"
        case .problemUpdates: return "1"
        case .deferredSales: return "2"
        case .incompleteOrders: return "3"
        case .other: return "9"
        }
    }

    static func < (lhs: ManagerNotificationCategory, rhs: ManagerNotificationCategory) -> Bool {
        lhs.sortKey < rhs.sortKey
    }

    static func resolve(
        key: String,
        typeLabel: String?,
        icon: String?,
        title: String,
        body: String? = nil
    ) -> ManagerNotificationCategory {
        let haystack = [
            key,
            typeLabel ?? "",
            icon ?? "",
            title,
            body ?? ""
        ]
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
            .lowercased()

        let prefix = key
            .split(separator: ":", maxSplits: 1)
            .first
            .map(String.init)?
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
            .lowercased() ?? ""

        let label = (typeLabel ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
            .lowercased()

        // 1) Narozeniny
        if prefix.contains("birthday")
            || prefix.contains("narozen")
            || haystack.contains("birthday")
            || haystack.contains("narozenin")
            || haystack.contains("cake")
            || label == "narozeniny"
            || label == "birthday"
            || label == "birthdays" {
            return .birthdays
        }

        // 2) Odložené prodeje (před obecným „problém“)
        if prefix.contains("deferred")
            || prefix.contains("odloz")
            || haystack.contains("deferred_sale")
            || haystack.contains("deferred sale")
            || haystack.contains("odlozeny prodej")
            || haystack.contains("odlozene prodej")
            || haystack.contains("odlozen")
            || label == "odlozene"
            || label == "odlozeny prodej"
            || label == "odlozene prodeje"
            || label == "deferred"
            || label == "deferred sales" {
            return .deferredSales
        }

        // 3) Nedokončené objednávky
        if prefix.contains("incomplete")
            || prefix.contains("nedokonc")
            || haystack.contains("incomplete_order")
            || haystack.contains("incomplete order")
            || haystack.contains("nedokoncena objednav")
            || haystack.contains("nedokoncene objednav")
            || haystack.contains("nedokonc")
            || label == "nedokoncene"
            || label == "nedokoncene objednavky"
            || label == "incomplete"
            || label == "incomplete orders" {
            return .incompleteOrders
        }

        // 4) Vývoj problémů / reporty
        if prefix == "report"
            || prefix == "reports"
            || prefix.contains("problem")
            || prefix.contains("vyvoj")
            || prefix.contains("update")
            || prefix.contains("history")
            || haystack.contains("vyvoj problem")
            || haystack.contains("vyvoj report")
            || haystack.contains("problem update")
            || haystack.contains("report update")
            || haystack.contains("vyvoj")
            || haystack.contains("problem")
            || haystack.contains("report")
            || label == "report"
            || label == "reporty"
            || label == "problem"
            || label == "problemy"
            || label == "vyvoj"
            || label == "vyvoj problemu" {
            return .problemUpdates
        }

        return .other
    }
}

struct ManagerNotificationsPayload {
    let notifications: [ManagerNotificationItem]
    let unreadCount: Int
}

private struct ManagerNotificationsResponse: Decodable {
    let success: Bool
    let notifications: [ManagerNotificationItem]
    let unread_count: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, notifications, unread_count, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let boolSuccess = try? c.decode(Bool.self, forKey: .success) {
            success = boolSuccess
        } else if let intSuccess = try? c.decode(Int.self, forKey: .success) {
            success = intSuccess == 1
        } else {
            success = false
        }
        notifications = (try? c.decode([ManagerNotificationItem].self, forKey: .notifications)) ?? []
        if let intCount = try? c.decodeIfPresent(Int.self, forKey: .unread_count) {
            unread_count = intCount
        } else if let stringCount = try? c.decodeIfPresent(String.self, forKey: .unread_count),
                  let intCount = Int(stringCount) {
            unread_count = intCount
        } else {
            unread_count = nil
        }
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }
}

private struct ManagerNotificationsReadResponse: Decodable {
    let success: Bool
    let unread_count: Int?
    let marked_count: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, unread_count, marked_count, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let boolSuccess = try? c.decode(Bool.self, forKey: .success) {
            success = boolSuccess
        } else if let intSuccess = try? c.decode(Int.self, forKey: .success) {
            success = intSuccess == 1
        } else {
            success = false
        }
        if let intCount = try? c.decodeIfPresent(Int.self, forKey: .unread_count) {
            unread_count = intCount
        } else if let stringCount = try? c.decodeIfPresent(String.self, forKey: .unread_count),
                  let intCount = Int(stringCount) {
            unread_count = intCount
        } else {
            unread_count = nil
        }
        if let intMarked = try? c.decodeIfPresent(Int.self, forKey: .marked_count) {
            marked_count = intMarked
        } else if let stringMarked = try? c.decodeIfPresent(String.self, forKey: .marked_count),
                  let intMarked = Int(stringMarked) {
            marked_count = intMarked
        } else {
            marked_count = nil
        }
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }
}

enum ManagerNotificationsError: LocalizedError {
    case invalidURL
    case notAuthenticated
    case forbidden(String?)
    case serverError(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Neplatná adresa API"
        case .notAuthenticated:
            return "Nejste přihlášeni"
        case .forbidden(let message):
            return message ?? "Nemáte oprávnění k oznámením"
        case .serverError(let code, let message):
            return message ?? "Chyba serveru (\(code))"
        }
    }
}

final class ManagerNotificationsService {
    private let baseURL = "https://provikart.cz/api"

    func fetchNotifications(token: String?, limit: Int = 80) async throws -> ManagerNotificationsPayload {
        guard let token, !token.isEmpty else {
            throw ManagerNotificationsError.notAuthenticated
        }

        var comp = URLComponents(string: "\(baseURL)/manager_notifications.php")
        comp?.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "limit", value: "\(max(1, min(200, limit)))"),
            URLQueryItem(name: "_", value: "\(Int(Date().timeIntervalSince1970))")
        ]
        guard let url = comp?.url else {
            throw ManagerNotificationsError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ManagerNotificationsError.serverError(-1, "Neplatná odpověď")
        }

        let decoded = try? JSONDecoder().decode(ManagerNotificationsResponse.self, from: data)
        let message = decoded?.error ?? String(data: data, encoding: .utf8)

        switch http.statusCode {
        case 200:
            guard let decoded, decoded.success else {
                throw ManagerNotificationsError.serverError(200, message)
            }
            let unread = decoded.unread_count ?? decoded.notifications.filter { !$0.is_read }.count
            return ManagerNotificationsPayload(notifications: decoded.notifications, unreadCount: unread)
        case 401:
            throw ManagerNotificationsError.notAuthenticated
        case 403:
            throw ManagerNotificationsError.forbidden(message)
        default:
            throw ManagerNotificationsError.serverError(http.statusCode, message)
        }
    }

    @discardableResult
    func setRead(token: String?, key: String, isRead: Bool) async throws -> Int {
        try await postRead(
            token: token,
            body: [
                "notification_key": key,
                "read_state": isRead ? 1 : 0
            ]
        )
    }

    @discardableResult
    func markAllRead(token: String?) async throws -> Int {
        try await postRead(
            token: token,
            body: ["read_all": true]
        )
    }

    private func postRead(token: String?, body: [String: Any]) async throws -> Int {
        guard let token, !token.isEmpty else {
            throw ManagerNotificationsError.notAuthenticated
        }
        guard let url = URL(string: "\(baseURL)/manager_notifications_read.php") else {
            throw ManagerNotificationsError.invalidURL
        }

        var payload = body
        payload["token"] = token

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ManagerNotificationsError.serverError(-1, "Neplatná odpověď")
        }

        let decoded = try? JSONDecoder().decode(ManagerNotificationsReadResponse.self, from: data)
        let message = decoded?.error ?? String(data: data, encoding: .utf8)

        switch http.statusCode {
        case 200:
            guard let decoded, decoded.success else {
                throw ManagerNotificationsError.serverError(200, message)
            }
            return decoded.unread_count ?? 0
        case 401:
            throw ManagerNotificationsError.notAuthenticated
        case 403:
            throw ManagerNotificationsError.forbidden(message)
        default:
            throw ManagerNotificationsError.serverError(http.statusCode, message)
        }
    }
}
