//
//  WatchCommissionService.swift
//  ProvikartWatch Watch App
//
//  Lightweight API služba pro načtení provize na hodinkách.
//

import Foundation

struct WatchCommissionResponse: Codable {
    let success: Bool
    let month: String
    let month_label: String?
    let commission: Double
    let currency: String
}

enum WatchCommissionError: LocalizedError {
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

final class WatchCommissionService {
    private let baseURL = "https://provikart.cz/api"

    func fetchCommission(token: String) async throws -> WatchCommissionResponse {
        guard !token.isEmpty else { throw WatchCommissionError.notAuthenticated }

        var comp = URLComponents(string: "\(baseURL)/commission.php")
        comp?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = comp?.url else { throw WatchCommissionError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WatchCommissionError.serverError(-1, "Neplatná odpověď")
        }

        switch http.statusCode {
        case 200:
            return try JSONDecoder().decode(WatchCommissionResponse.self, from: data)
        case 401:
            throw WatchCommissionError.notAuthenticated
        default:
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw WatchCommissionError.serverError(http.statusCode, message)
        }
    }
}
