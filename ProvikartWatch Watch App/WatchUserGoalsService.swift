//
//  WatchUserGoalsService.swift
//  ProvikartWatch Watch App
//
//  Načtení cílů uživatele (provize, počet služeb) z API.
//

import Foundation

/// Odpověď API – plochá struktura: { "success": true, "commission_goal": 50000, "services_goal": 20 }
struct WatchUserGoalsResponse: Codable {
    let success: Bool
    let commission_goal: Double?
    let services_goal: Int?
}

final class WatchUserGoalsService {
    private let baseURL = "https://provikart.cz/api"

    func fetchGoals(token: String) async throws -> (commissionGoal: Double?, servicesGoal: Int?) {
        guard !token.isEmpty else { return (nil, nil) }

        var comp = URLComponents(string: "\(baseURL)/user_goals")
        comp?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = comp?.url else { return (nil, nil) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return (nil, nil)
        }

        let decoded = try? JSONDecoder().decode(WatchUserGoalsResponse.self, from: data)
        guard decoded?.success == true else { return (nil, nil) }
        return (decoded?.commission_goal, decoded?.services_goal)
    }
}
