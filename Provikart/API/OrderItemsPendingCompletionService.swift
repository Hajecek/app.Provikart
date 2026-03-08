//
//  OrderItemsPendingCompletionService.swift
//  Provikart
//
//  Načtení počtu položek objednávek čekajících na dokončení (po datu instalace, ne completed).
//  GET /api/order_items_pending_completion.php
//

import Foundation

/// Odpověď API – položky čekající na dokončení.
struct PendingCompletionResponse: Codable {
    let success: Bool
    let items: [PendingCompletionItem]
    let count: Int
}

/// Jedna položka čekající na dokončení (odpověď API).
struct PendingCompletionItem: Codable, Identifiable {
    let id: Int
    let order_id: Int
    let order_number: String?
    let customer_name: String?
    let customer_phone: String?
    let customer_address: String?
    let order_url: String?
    let item_name: String?
    let item_type: String?
    let base_price: Double
    let discount: Double
    let commission: Double
    let commission_upfront: Double?
    let has_oku_code: Bool
    let oku_code: String?
    let installation_day: String?
    let installation_time: String?
    let status: String?
    let installation_notified_at: String?

    enum CodingKeys: String, CodingKey {
        case id, order_id, order_number, customer_name, customer_phone, customer_address, order_url
        case item_name, item_type, base_price, discount, commission, commission_upfront
        case has_oku_code, oku_code, installation_day, installation_time, status, installation_notified_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIntOrString(forKey: .id)
        order_id = try c.decodeIntOrString(forKey: .order_id)
        order_number = try? c.decodeIfPresent(String.self, forKey: .order_number)
        customer_name = try? c.decodeIfPresent(String.self, forKey: .customer_name)
        customer_phone = try? c.decodeIfPresent(String.self, forKey: .customer_phone)
        customer_address = try? c.decodeIfPresent(String.self, forKey: .customer_address)
        order_url = try? c.decodeIfPresent(String.self, forKey: .order_url)
        item_name = try? c.decodeIfPresent(String.self, forKey: .item_name)
        item_type = try? c.decodeIfPresent(String.self, forKey: .item_type)
        base_price = try c.decodeDoubleOrString(forKey: .base_price)
        discount = try c.decodeDoubleOrString(forKey: .discount)
        commission = try c.decodeDoubleOrString(forKey: .commission)
        commission_upfront = try? c.decodeDoubleOrStringIfPresent(forKey: .commission_upfront)
        has_oku_code = (try? c.decode(Int.self, forKey: .has_oku_code)) == 1 || (try? c.decode(Bool.self, forKey: .has_oku_code)) == true
        oku_code = try? c.decodeIfPresent(String.self, forKey: .oku_code)
        installation_day = try? c.decodeIfPresent(String.self, forKey: .installation_day)
        installation_time = try? c.decodeIfPresent(String.self, forKey: .installation_time)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        installation_notified_at = try? c.decodeIfPresent(String.self, forKey: .installation_notified_at)
    }

    /// Zobrazované číslo objednávky.
    var displayOrderNumber: String {
        (order_number?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 } ?? "\(order_id)"
    }
}

final class OrderItemsPendingCompletionService {
    private let baseURL = "https://provikart.cz/api"

    /// Načte počet položek čekajících na dokončení. Vyžaduje platný API token.
    func fetchPendingCount(token: String?) async throws -> Int {
        guard let token = token, !token.isEmpty else {
            throw PendingCompletionError.notAuthenticated
        }
        var comp = URLComponents(string: "\(baseURL)/order_items_pending_completion.php")
        comp?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = comp?.url else {
            throw PendingCompletionError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PendingCompletionError.serverError(-1, "Neplatná odpověď")
        }

        switch http.statusCode {
        case 200:
            let decoded = try JSONDecoder().decode(PendingCompletionResponse.self, from: data)
            return decoded.count
        case 401:
            throw PendingCompletionError.notAuthenticated
        default:
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw PendingCompletionError.serverError(http.statusCode, message)
        }
    }

    /// Načte celý seznam položek čekajících na dokončení.
    func fetchPendingItems(token: String?) async throws -> [PendingCompletionItem] {
        guard let token = token, !token.isEmpty else {
            throw PendingCompletionError.notAuthenticated
        }
        var comp = URLComponents(string: "\(baseURL)/order_items_pending_completion.php")
        comp?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = comp?.url else {
            throw PendingCompletionError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PendingCompletionError.serverError(-1, "Neplatná odpověď")
        }
        switch http.statusCode {
        case 200:
            let decoded = try JSONDecoder().decode(PendingCompletionResponse.self, from: data)
            return decoded.items
        case 401:
            throw PendingCompletionError.notAuthenticated
        default:
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw PendingCompletionError.serverError(http.statusCode, message)
        }
    }
}

enum PendingCompletionError: LocalizedError {
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

private extension KeyedDecodingContainer {
    func decodeIntOrString(forKey key: Key) throws -> Int {
        if let i = try? decode(Int.self, forKey: key) { return i }
        if let s = try? decode(String.self, forKey: key), let i = Int(s) { return i }
        throw DecodingError.typeMismatch(Int.self, .init(codingPath: codingPath + [key], debugDescription: "Očekáváno Int nebo String s číslem"))
    }
    func decodeDoubleOrString(forKey key: Key) throws -> Double {
        if let d = try? decode(Double.self, forKey: key) { return d }
        if let i = try? decode(Int.self, forKey: key) { return Double(i) }
        if let s = try? decode(String.self, forKey: key) {
            let normalized = s.replacingOccurrences(of: ",", with: ".")
            return Double(normalized) ?? 0
        }
        return 0
    }
    func decodeDoubleOrStringIfPresent(forKey key: Key) -> Double? {
        guard contains(key) else { return nil }
        if let d = try? decode(Double.self, forKey: key) { return d }
        if let i = try? decode(Int.self, forKey: key) { return Double(i) }
        if let s = try? decode(String.self, forKey: key) {
            let normalized = s.replacingOccurrences(of: ",", with: ".")
            return Double(normalized)
        }
        return nil
    }
}
