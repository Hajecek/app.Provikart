//
//  WatchOrderItemsCountService.swift
//  ProvikartWatch Watch App
//
//  Načtení počtu služeb (order items) na hodinkách – stejné API jako iOS.
//

import Foundation

enum WatchOrderItemsCountError: LocalizedError {
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

private struct OrderItemsCountResponse: Codable {
    let success: Bool
    let count: Int
}

final class WatchOrderItemsCountService {
    private let baseURL = "https://provikart.cz/api"

    /// Načte celkový počet služeb uživatele.
    func fetchCount(token: String) async throws -> Int {
        guard !token.isEmpty else { throw WatchOrderItemsCountError.notAuthenticated }

        var comp = URLComponents(string: "\(baseURL)/order_items_count.php")
        comp?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = comp?.url else { throw WatchOrderItemsCountError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WatchOrderItemsCountError.serverError(-1, "Neplatná odpověď")
        }

        switch http.statusCode {
        case 200:
            let decoded = try JSONDecoder().decode(OrderItemsCountResponse.self, from: data)
            return decoded.count
        case 401:
            throw WatchOrderItemsCountError.notAuthenticated
        default:
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw WatchOrderItemsCountError.serverError(http.statusCode, message)
        }
    }
}
