//
//  OrderItemsByInstallationDateService.swift
//  Provikart
//
//  Načtení položek objednávek s datumem instalace z API (GET order_items_by_installation_date.php).
//

import Foundation

/// Jedna položka objednávky s datumem instalace (odpověď API).
/// Dekódování je tolerantní k null a k číslům vráceným jako řetězce (PHP/MySQL).
struct OrderItemByInstallationDate: Decodable, Identifiable {
    let id: Int
    let order_id: Int
    let item_name: String
    let installation_date: String
    let base_price: Double
    let discount: Double
    let commission: Double
    let status: String

    enum CodingKeys: String, CodingKey {
        case id, order_id, item_name, installation_date, base_price, discount, commission, status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIntOrString(forKey: .id)
        order_id = try c.decodeIntOrString(forKey: .order_id)
        item_name = (try c.decodeIfPresent(String.self, forKey: .item_name)) ?? ""
        installation_date = (try c.decodeIfPresent(String.self, forKey: .installation_date)) ?? ""
        base_price = try c.decodeDoubleOrString(forKey: .base_price)
        discount = try c.decodeDoubleOrString(forKey: .discount)
        commission = try c.decodeDoubleOrString(forKey: .commission)
        status = (try c.decodeIfPresent(String.self, forKey: .status)) ?? ""
    }
}

/// Odpověď API order_items_by_installation_date.php
struct OrderItemsByInstallationDateResponse: Decodable {
    let success: Bool
    let items: [OrderItemByInstallationDate]
    let count: Int
    let installation_date: String?

    enum CodingKeys: String, CodingKey {
        case success, items, count, installation_date
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = (try? c.decode(Bool.self, forKey: .success)) ?? false
        items = (try? c.decode([OrderItemByInstallationDate].self, forKey: .items)) ?? []
        if let i = try? c.decode(Int.self, forKey: .count) {
            count = i
        } else if let s = try? c.decode(String.self, forKey: .count), let i = Int(s) {
            count = i
        } else {
            count = items.count
        }
        installation_date = try? c.decodeIfPresent(String.self, forKey: .installation_date)
    }
}

private extension DecodingError {
    var friendlyDescription: String {
        switch self {
        case .keyNotFound(let key, _): return "Chybí klíč: \(key.stringValue)"
        case .typeMismatch(let type, let ctx): return "Špatný typ u \(ctx.codingPath.map(\.stringValue).joined(separator: ".")): očekáváno \(type)"
        case .valueNotFound(_, let ctx): return "Chybí hodnota u \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
        case .dataCorrupted(let ctx): return "Poškozená data: \(ctx.debugDescription)"
        @unknown default: return "Neznámá chyba dekódování"
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
}

enum OrderItemsByInstallationDateError: LocalizedError {
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

final class OrderItemsByInstallationDateService {
    private let baseURL = "https://provikart.cz/api"

    /// Načte položky s datumem instalace. Volitelně jen pro dané datum (YYYY-MM-DD).
    /// Token se posílá v hlavičce Authorization i v GET parametru.
    func fetchOrderItems(token: String?, installationDate: String? = nil) async throws -> [OrderItemByInstallationDate] {
        guard let token = token, !token.isEmpty else {
            throw OrderItemsByInstallationDateError.notAuthenticated
        }
        var comp = URLComponents(string: "\(baseURL)/order_items_by_installation_date.php")
        var queryItems = [URLQueryItem(name: "token", value: token)]
        if let date = installationDate, !date.isEmpty {
            queryItems.append(URLQueryItem(name: "installation_date", value: date))
        }
        comp?.queryItems = queryItems
        guard let url = comp?.url else {
            throw OrderItemsByInstallationDateError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OrderItemsByInstallationDateError.serverError(-1, "Neplatná odpověď")
        }

        switch http.statusCode {
        case 200:
            do {
                let decoded = try JSONDecoder().decode(OrderItemsByInstallationDateResponse.self, from: data)
                guard decoded.success else {
                    throw OrderItemsByInstallationDateError.serverError(200, "API vrátilo success: false")
                }
                return decoded.items
            } catch let decodingError as DecodingError {
                let detail = decodingError.friendlyDescription
                print("[OrderItemsByInstallationDate] Decoding error: \(detail). Raw: \(String(data: data, encoding: .utf8)?.prefix(500) ?? "")")
                throw OrderItemsByInstallationDateError.serverError(200, "Chyba při zpracování odpovědi: \(detail)")
            } catch {
                print("[OrderItemsByInstallationDate] Error: \(error). Raw: \(String(data: data, encoding: .utf8)?.prefix(500) ?? "")")
                throw OrderItemsByInstallationDateError.serverError(200, "Chyba při zpracování odpovědi")
            }
        case 401:
            throw OrderItemsByInstallationDateError.notAuthenticated
        default:
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw OrderItemsByInstallationDateError.serverError(http.statusCode, message)
        }
    }
}
