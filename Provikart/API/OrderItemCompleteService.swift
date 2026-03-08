//
//  OrderItemCompleteService.swift
//  Provikart
//
//  Označení položky objednávky jako dokončené. POST /api/order_item_complete.php
//

import Foundation

/// Odpověď API po dokončení položky.
private struct OrderItemCompleteResponse: Codable {
    let success: Bool?
    let error: String?
}

enum OrderItemCompleteError: LocalizedError {
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

final class OrderItemCompleteService {
    private let baseURL = "https://provikart.cz/api"

    /// Označí položku objednávky (order_item) jako dokončenou. Vyžaduje platný API token.
    /// - Parameters:
    ///   - orderItemId: id položky z tabulky order_items
    ///   - token: API token
    func completeOrderItem(orderItemId: Int, token: String?) async throws {
        guard let token = token, !token.isEmpty else {
            throw OrderItemCompleteError.notAuthenticated
        }
        guard let url = URL(string: "\(baseURL)/order_item_complete.php") else {
            throw OrderItemCompleteError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // PHP přijímá order_item_id i orderItemId
        let body: [String: Any] = [
            "order_item_id": orderItemId,
            "orderItemId": orderItemId,
            "token": token
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OrderItemCompleteError.serverError(-1, "Neplatná odpověď")
        }
        if let raw = String(data: data, encoding: .utf8) {
            print("[OrderItemComplete] HTTP \(http.statusCode) → \(raw.prefix(200))")
        }
        let decoded = try? JSONDecoder().decode(OrderItemCompleteResponse.self, from: data)
        let serverError = decoded?.error ?? extractErrorFromJSON(data)

        switch http.statusCode {
        case 200:
            if decoded?.success == false {
                throw OrderItemCompleteError.serverError(200, serverError ?? "Položku se nepodařilo dokončit.")
            }
        case 401:
            throw OrderItemCompleteError.notAuthenticated
        default:
            throw OrderItemCompleteError.serverError(http.statusCode, serverError)
        }
    }
}

private func extractErrorFromJSON(_ data: Data) -> String? {
    (try? JSONDecoder().decode(OrderItemCompleteResponse.self, from: data))?.error
}
