//
//  UserOrdersService.swift
//  Provikart
//
//  Načtení všech objednávek a položek přihlášeného uživatele z API (GET user_orders.php).
//

import Foundation

/// Jedna položka objednávky (order_items z API).
struct UserOrderItem: Decodable, Identifiable {
    let id: Int
    let order_id: Int
    let item_name: String
    let item_type: String?
    let base_price: Double
    let discount: Double
    let commission: Double
    let has_oku_code: Bool?
    let oku_code: String?
    let installation_day: String?
    let installation_time: String?
    let status: String?
    let installation_notified_at: String?
    let commission_upfront: Int?

    enum CodingKeys: String, CodingKey {
        case id, order_id, item_name, item_type, base_price, discount, commission
        case has_oku_code, oku_code, installation_day, installation_time, status
        case installation_notified_at, commission_upfront
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try UserOrdersDecoding.decodeInt(c, forKey: .id)
        order_id = try UserOrdersDecoding.decodeInt(c, forKey: .order_id)
        item_name = (try? c.decodeIfPresent(String.self, forKey: .item_name)) ?? ""
        item_type = try? c.decodeIfPresent(String.self, forKey: .item_type)
        base_price = try UserOrdersDecoding.decodeDouble(c, forKey: .base_price)
        discount = try UserOrdersDecoding.decodeDouble(c, forKey: .discount)
        commission = try UserOrdersDecoding.decodeDouble(c, forKey: .commission)
        has_oku_code = try? UserOrdersDecoding.decodeBoolIfPresent(c, forKey: .has_oku_code)
        oku_code = try? c.decodeIfPresent(String.self, forKey: .oku_code)
        installation_day = try? c.decodeIfPresent(String.self, forKey: .installation_day)
        installation_time = try? c.decodeIfPresent(String.self, forKey: .installation_time)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        installation_notified_at = try? c.decodeIfPresent(String.self, forKey: .installation_notified_at)
        commission_upfront = try? UserOrdersDecoding.decodeIntIfPresent(c, forKey: .commission_upfront)
    }

    /// Datum instalace – installation_day nebo prázdný řetězec.
    var installationDateDisplay: String {
        installation_day?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    var statusDisplay: String {
        status?.trimmingCharacters(in: .whitespaces) ?? ""
    }
}

/// Jedna objednávka včetně položek (orders + items z API).
struct UserOrder: Decodable, Identifiable, Hashable {
    static func == (lhs: UserOrder, rhs: UserOrder) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    let id: Int
    let user_id: Int
    let order_number: String?
    let customer_name: String?
    let customer_phone: String?
    let customer_address: String?
    let order_date: String?
    let amount: Double?
    let status: String?
    let notes: String?
    let cancelled_note: String?
    let order_url: String?
    let created_at: String?
    let items: [UserOrderItem]

    enum CodingKeys: String, CodingKey {
        case id, user_id, order_number, customer_name, customer_phone, customer_address
        case order_date, amount, status, notes, cancelled_note, order_url, created_at, items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try UserOrdersDecoding.decodeInt(c, forKey: .id)
        user_id = try UserOrdersDecoding.decodeInt(c, forKey: .user_id)
        order_number = try? c.decodeIfPresent(String.self, forKey: .order_number)
        customer_name = try? c.decodeIfPresent(String.self, forKey: .customer_name)
        customer_phone = try? c.decodeIfPresent(String.self, forKey: .customer_phone)
        customer_address = try? c.decodeIfPresent(String.self, forKey: .customer_address)
        order_date = try? c.decodeIfPresent(String.self, forKey: .order_date)
        amount = try? UserOrdersDecoding.decodeDoubleIfPresent(c, forKey: .amount)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
        cancelled_note = try? c.decodeIfPresent(String.self, forKey: .cancelled_note)
        order_url = try? c.decodeIfPresent(String.self, forKey: .order_url)
        created_at = try? c.decodeIfPresent(String.self, forKey: .created_at)
        items = (try? c.decodeIfPresent([UserOrderItem].self, forKey: .items)) ?? []
    }

    var displayOrderNumber: String {
        let num = order_number?.trimmingCharacters(in: .whitespaces)
        if let n = num, !n.isEmpty { return n }
        return "\(id)"
    }

    var statusDisplay: String {
        status?.trimmingCharacters(in: .whitespaces) ?? ""
    }
}

/// Odpověď API user_orders.php
struct UserOrdersResponse: Decodable {
    let success: Bool
    let orders: [UserOrder]
    let count: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = (try? c.decode(Bool.self, forKey: .success)) ?? false
        orders = (try? c.decode([UserOrder].self, forKey: .orders)) ?? []
        if let i = try? c.decode(Int.self, forKey: .count) {
            count = i
        } else if let s = try? c.decode(String.self, forKey: .count), let i = Int(s) {
            count = i
        } else {
            count = orders.count
        }
    }

    enum CodingKeys: String, CodingKey {
        case success, orders, count
    }
}

private enum UserOrdersDecoding {
    static func decodeInt(_ c: KeyedDecodingContainer<UserOrderItem.CodingKeys>, forKey key: UserOrderItem.CodingKeys) throws -> Int {
        if let i = try? c.decode(Int.self, forKey: key) { return i }
        if let s = try? c.decode(String.self, forKey: key), let i = Int(s) { return i }
        throw DecodingError.typeMismatch(Int.self, .init(codingPath: c.codingPath + [key], debugDescription: "Očekáváno Int nebo String"))
    }

    static func decodeInt(_ c: KeyedDecodingContainer<UserOrder.CodingKeys>, forKey key: UserOrder.CodingKeys) throws -> Int {
        if let i = try? c.decode(Int.self, forKey: key) { return i }
        if let s = try? c.decode(String.self, forKey: key), let i = Int(s) { return i }
        throw DecodingError.typeMismatch(Int.self, .init(codingPath: c.codingPath + [key], debugDescription: "Očekáváno Int nebo String"))
    }

    static func decodeDouble(_ c: KeyedDecodingContainer<UserOrderItem.CodingKeys>, forKey key: UserOrderItem.CodingKeys) throws -> Double {
        if let d = try? c.decode(Double.self, forKey: key) { return d }
        if let i = try? c.decode(Int.self, forKey: key) { return Double(i) }
        if let s = try? c.decode(String.self, forKey: key) {
            return Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0
        }
        return 0
    }

    static func decodeDoubleIfPresent(_ c: KeyedDecodingContainer<UserOrder.CodingKeys>, forKey key: UserOrder.CodingKeys) throws -> Double? {
        guard c.contains(key) else { return nil }
        if let d = try? c.decode(Double.self, forKey: key) { return d }
        if let i = try? c.decode(Int.self, forKey: key) { return Double(i) }
        if let s = try? c.decode(String.self, forKey: key) {
            return Double(s.replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }

    static func decodeIntIfPresent(_ c: KeyedDecodingContainer<UserOrderItem.CodingKeys>, forKey key: UserOrderItem.CodingKeys) throws -> Int? {
        guard c.contains(key) else { return nil }
        if let i = try? c.decode(Int.self, forKey: key) { return i }
        if let s = try? c.decode(String.self, forKey: key) { return Int(s) }
        if let b = try? c.decode(Bool.self, forKey: key) { return b ? 1 : 0 }
        return nil
    }

    static func decodeBoolIfPresent(_ c: KeyedDecodingContainer<UserOrderItem.CodingKeys>, forKey key: UserOrderItem.CodingKeys) throws -> Bool? {
        guard c.contains(key) else { return nil }
        if let b = try? c.decode(Bool.self, forKey: key) { return b }
        if let i = try? c.decode(Int.self, forKey: key) { return i != 0 }
        if let s = try? c.decode(String.self, forKey: key) { return (Int(s) ?? 0) != 0 }
        return nil
    }
}

enum UserOrdersError: LocalizedError {
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

final class UserOrdersService {
    private let baseURL = "https://provikart.cz/api"

    /// Načte všechny objednávky a položky přihlášeného uživatele.
    func fetchOrders(token: String?) async throws -> [UserOrder] {
        guard let token = token, !token.isEmpty else {
            throw UserOrdersError.notAuthenticated
        }
        var comp = URLComponents(string: "\(baseURL)/user_orders.php")
        comp?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = comp?.url else {
            throw UserOrdersError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UserOrdersError.serverError(-1, "Neplatná odpověď")
        }

        switch http.statusCode {
        case 200:
            let startsLikeHtml = String(data: data.prefix(50), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .hasPrefix("<") == true
            if startsLikeHtml {
                print("[UserOrders] Server vrátil HTML místo JSON (404?). Raw: \(String(data: data.prefix(200), encoding: .utf8) ?? "")")
                throw UserOrdersError.serverError(200, "Server vrátil stránku místo dat. Nahrajte na server soubor user_orders.php do složky api (např. api/user_orders.php).")
            }
            do {
                let decoded = try JSONDecoder().decode(UserOrdersResponse.self, from: data)
                guard decoded.success else {
                    throw UserOrdersError.serverError(200, "API vrátilo success: false")
                }
                return decoded.orders
            } catch let decodingError as DecodingError {
                let detail = (decodingError as NSError).localizedDescription
                print("[UserOrders] Decoding error: \(detail). Raw: \(String(data: data, encoding: .utf8)?.prefix(500) ?? "")")
                throw UserOrdersError.serverError(200, "Chyba při zpracování odpovědi: \(detail)")
            } catch {
                print("[UserOrders] Error: \(error)")
                throw UserOrdersError.serverError(200, "Chyba při zpracování odpovědi")
            }
        case 401:
            throw UserOrdersError.notAuthenticated
        case 404:
            throw UserOrdersError.serverError(404, "Endpoint nebyl nalezen (404). Nahrajte na server soubor user_orders.php do složky api.")
        default:
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw UserOrdersError.serverError(http.statusCode, message)
        }
    }
}
