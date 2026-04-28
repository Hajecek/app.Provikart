//
//  OrderItemsConnectedStatsService.swift
//  Provikart
//
//  Načtení zapojených služeb pro mobilní statistiky.
//

import Foundation

enum OrderItemsConnectedStatsError: LocalizedError {
    case invalidURL
    case notAuthenticated
    case serverError(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Neplatná adresa API"
        case .notAuthenticated: return "Nejste přihlášeni"
        case .serverError(let code, let message): return message ?? "Chyba serveru (\(code))"
        }
    }
}

final class OrderItemsConnectedStatsService {
    private let baseURL = "https://provikart.cz/api"

    /// Načte zapojené služby pro statistiky za konkrétní měsíc.
    /// Backend počítá období podle orders.order_date a filtruje jen completed položky.
    func fetchConnectedItems(token: String?, month: Int, year: Int) async throws -> [OrderItemByInstallationDate] {
        guard let token, !token.isEmpty else {
            throw OrderItemsConnectedStatsError.notAuthenticated
        }

        var comp = URLComponents(string: "\(baseURL)/order_items_connected_stats.php")
        comp?.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "month", value: "\(month)"),
            URLQueryItem(name: "year", value: "\(year)")
        ]
        guard let url = comp?.url else {
            throw OrderItemsConnectedStatsError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OrderItemsConnectedStatsError.serverError(-1, "Neplatná odpověď")
        }

        switch http.statusCode {
        case 200:
            do {
                let decoded = try JSONDecoder().decode(OrderItemsByInstallationDateResponse.self, from: data)
                guard decoded.success else {
                    throw OrderItemsConnectedStatsError.serverError(200, "API vrátilo success: false")
                }
                return decoded.items
            } catch {
                print("[OrderItemsConnectedStats] Error: \(error). Raw: \(String(data: data, encoding: .utf8)?.prefix(500) ?? "")")
                throw OrderItemsConnectedStatsError.serverError(200, "Chyba při zpracování odpovědi")
            }
        case 401:
            throw OrderItemsConnectedStatsError.notAuthenticated
        default:
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw OrderItemsConnectedStatsError.serverError(http.statusCode, message)
        }
    }
}
