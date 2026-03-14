//
//  UserGoalsService.swift
//  Provikart
//
//  Načtení cílů uživatele (provize, počet služeb) z API.
//  GET /api/user_goals – odpověď: { success, commission_goal, services_goal } (plochá struktura).
//

import Foundation

/// Odpověď API cílů – plochá struktura: { "success": true, "commission_goal": 50000, "services_goal": 20 }
struct UserGoalsResponse: Codable {
    let success: Bool
    let commission_goal: Double?
    let services_goal: Int?
}

enum UserGoalsError: LocalizedError {
    case invalidURL
    case notAuthenticated
    case serverError(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Neplatná adresa API"
        case .notAuthenticated: return "Nejste přihlášeni"
        case .serverError(let code, let msg): return msg ?? "Chyba serveru (\(code))"
        }
    }
}

final class UserGoalsService {
    private let baseURL = "https://provikart.cz/api"
    /// Endpoint cílů – URL bez .php (https://provikart.cz/api/user_goals)
    private let goalsPath = "user_goals"

    /// Načte cíle uživatele. Vyžaduje platný API token.
    /// commission_goal a services_goal mohou být null, pokud uživatel cíle nenastavil.
    func fetchGoals(token: String?) async throws -> (commissionGoal: Double?, servicesGoal: Int?) {
        guard let token = token, !token.isEmpty else {
            throw UserGoalsError.notAuthenticated
        }
        var comp = URLComponents(string: "\(baseURL)/\(goalsPath)")
        comp?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = comp?.url else {
            throw UserGoalsError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UserGoalsError.serverError(-1, "Neplatná odpověď")
        }

        switch http.statusCode {
        case 200:
            let decoded = try JSONDecoder().decode(UserGoalsResponse.self, from: data)
            guard decoded.success else {
                throw UserGoalsError.serverError(200, "Chyba při načtení cílů")
            }
            return (
                commissionGoal: decoded.commission_goal,
                servicesGoal: decoded.services_goal
            )
        case 401:
            throw UserGoalsError.notAuthenticated
        default:
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw UserGoalsError.serverError(http.statusCode, message)
        }
    }
}
