//
//  OrderItemsCountService.swift
//  Provikart
//
//  Načtení celkového počtu položek objednávek (služeb) přihlášeného uživatele.
//  GET /api/order_items_count.php – položky s item_type = 'migrace' se nepočítají.
//

import Foundation

/// Odpověď API – počet položek (služeb).
struct OrderItemsCountResponse: Codable {
    let success: Bool
    let count: Int
}

enum OrderItemsCountError: LocalizedError {
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

final class OrderItemsCountService {
    private let baseURL = "https://provikart.cz/api"

    /// Načte celkový počet položek (služeb) uživatele. Vyžaduje platný API token.
    func fetchCount(token: String?) async throws -> Int {
        guard let token = token, !token.isEmpty else {
            throw OrderItemsCountError.notAuthenticated
        }
        var comp = URLComponents(string: "\(baseURL)/order_items_count.php")
        comp?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = comp?.url else {
            throw OrderItemsCountError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OrderItemsCountError.serverError(-1, "Neplatná odpověď")
        }

        switch http.statusCode {
        case 200:
            let decoded = try JSONDecoder().decode(OrderItemsCountResponse.self, from: data)
            return decoded.count
        case 401:
            throw OrderItemsCountError.notAuthenticated
        default:
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw OrderItemsCountError.serverError(http.statusCode, message)
        }
    }
}
