//
//  NotificationPreferencesService.swift
//  Provikart
//
//  POST /api/notification_preferences.php
//  Uloží výběr notifikací na backend. 404 / chyba se ignoruje – lokální stav platí vždy.
//

import Foundation

final class NotificationPreferencesService {
    private let baseURL = "https://provikart.cz/api"

    func save(token: String?, payload: [String: Any]) async {
        guard let token, !token.isEmpty else { return }
        guard let url = URL(string: "\(baseURL)/notification_preferences.php") else { return }

        var body = payload
        body["token"] = token
        body["token_api"] = token

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, _) = try await URLSession.shared.authAwareData(for: request)
        } catch {
            // Endpoint zatím nemusí existovat – volba zůstane lokálně.
        }
    }
}
