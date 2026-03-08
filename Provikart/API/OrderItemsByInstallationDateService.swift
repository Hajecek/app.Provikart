//
//  OrderItemsByInstallationDateService.swift
//  Provikart
//
//  Načtení položek objednávek s datumem instalace z API (GET order_items_by_installation_date.php).
//

import Foundation

/// Jedna položka objednávky s datumem instalace (odpověď API).
/// Dekódování je tolerantní k null a k číslům vráceným jako řetězce (PHP/MySQL).
/// Podporuje jak staré pole installation_date, tak nové installation_day + installation_time z tabulky order_items.
struct OrderItemByInstallationDate: Decodable, Identifiable {
    let id: Int
    let order_id: Int
    /// Skutečné číslo objednávky pro zákazníka (z tabulky orders). Pokud API nevrátí, zobrazí se order_id.
    let order_number: String?
    let item_name: String
    /// Typ produktu z tabulky order_items (sloupec item_type). Např. postpaid → zobrazení „Postpaid“. Používá se pro kategorizaci ve statistikách.
    let item_type: String?
    /// Datum instalace – buď z installation_date (API), nebo z installation_day (nová DB). Formát YYYY-MM-DD nebo dd.MM.yyyy.
    let installation_date: String
    /// Čas instalace HH:MM (volitelné, z sloupce installation_time).
    let installation_time: String?
    let base_price: Double
    let discount: Double
    let commission: Double
    /// Část provize vyplacená hned (při podpisu); zbytek při dokončení.
    let commission_upfront: Double?
    /// Skutečně zapojená provize: u completed celá commission, jinak commission_upfront.
    let commission_earned: Double?
    /// Čekající provize („při zapojení“).
    let commission_pending: Double?
    let status: String

    enum CodingKeys: String, CodingKey {
        case id, order_id, order_number, item_name, item_type, installation_date, installation_time, base_price, discount, commission, status
        case installation_day
        case commission_upfront, commission_earned, commission_pending
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIntOrString(forKey: .id)
        order_id = try c.decodeIntOrString(forKey: .order_id)
        order_number = try? c.decodeIfPresent(String.self, forKey: .order_number)
        item_name = (try c.decodeIfPresent(String.self, forKey: .item_name)) ?? ""
        item_type = try? c.decodeIfPresent(String.self, forKey: .item_type)
        // API může vracet installation_date (staré) nebo installation_day (nové po úpravě tabulky)
        let fromDate = try? c.decodeIfPresent(String.self, forKey: .installation_date)
        let fromDay = try? c.decodeIfPresent(String.self, forKey: .installation_day)
        installation_date = fromDate?.trimmingCharacters(in: .whitespaces).isEmpty == false
            ? (fromDate ?? "")
            : (fromDay?.trimmingCharacters(in: .whitespaces) ?? "")
        installation_time = try? c.decodeIfPresent(String.self, forKey: .installation_time)
        base_price = try c.decodeDoubleOrString(forKey: .base_price)
        discount = try c.decodeDoubleOrString(forKey: .discount)
        commission = try c.decodeDoubleOrString(forKey: .commission)
        commission_upfront = try? c.decodeDoubleOrStringIfPresent(forKey: .commission_upfront)
        commission_earned = try? c.decodeDoubleOrStringIfPresent(forKey: .commission_earned)
        commission_pending = try? c.decodeDoubleOrStringIfPresent(forKey: .commission_pending)
        status = (try c.decodeIfPresent(String.self, forKey: .status)) ?? ""
    }

    /// Pro statistiky „Tržba“: zapojená provize (commission_earned), nebo base_price pokud API neposílá commission_earned.
    var revenueForStats: Double {
        if let earned = commission_earned { return earned }
        return base_price
    }

    /// Zobrazované číslo objednávky: order_number z API, jinak order_id.
    var displayOrderNumber: String {
        if let num = order_number, !num.trimmingCharacters(in: .whitespaces).isEmpty {
            return num.trimmingCharacters(in: .whitespaces)
        }
        return "\(order_id)"
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
