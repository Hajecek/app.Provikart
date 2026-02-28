//
//  AIOrderService.swift
//  Provikart
//
//  Parsování textu objednávky pomocí AI a vytvoření objednávky v databázi.
//  Backend: add-ai.php (parse_order, create_order_direct).
//  Pro přístup z aplikace musí backend akceptovat API token (např. Authorization: Bearer nebo token_api v těle).
//

import Foundation

// MARK: - Parsed item (odpověď parse_order)

struct AIParsedItem: Codable, Identifiable {
    var id: String { "\(item_name)-\(base_price)-\(discount)-\(commission)" }
    let item_name: String
    let item_type: String
    let base_price: Double
    let discount: Double
    let commission: Double
    let base_commission: Double?
    let has_oku_code: Int?
    let has_family_viewing: Int?

    enum CodingKeys: String, CodingKey {
        case item_name, item_type, base_price, discount, commission
        case base_commission, has_oku_code, has_family_viewing
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        item_name = (try? c.decode(String.self, forKey: .item_name)) ?? ""
        item_type = (try? c.decode(String.self, forKey: .item_type)) ?? "jine"
        base_price = try c.decodeNumber(forKey: .base_price)
        discount = try c.decodeNumber(forKey: .discount)
        commission = try c.decodeNumber(forKey: .commission)
        base_commission = try? c.decodeNumber(forKey: .base_commission)
        has_oku_code = try? c.decode(Int.self, forKey: .has_oku_code)
        has_family_viewing = try? c.decode(Int.self, forKey: .has_family_viewing)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(item_name, forKey: .item_name)
        try c.encode(item_type, forKey: .item_type)
        try c.encode(base_price, forKey: .base_price)
        try c.encode(discount, forKey: .discount)
        try c.encode(commission, forKey: .commission)
        try c.encodeIfPresent(base_commission, forKey: .base_commission)
        try c.encodeIfPresent(has_oku_code, forKey: .has_oku_code)
        try c.encodeIfPresent(has_family_viewing, forKey: .has_family_viewing)
    }
}

// Čísla mohou přijít jako Double, Int nebo String (např. "3500") – server někdy vrací stringy
private extension KeyedDecodingContainer where Key == AIParsedItem.CodingKeys {
    func decodeNumber(forKey key: Key) throws -> Double {
        if let d = try? decode(Double.self, forKey: key) { return d }
        if let i = try? decode(Int.self, forKey: key) { return Double(i) }
        if let s = try? decode(String.self, forKey: key), let v = Double(s) { return v }
        throw DecodingError.typeMismatch(Double.self, .init(codingPath: codingPath + [key], debugDescription: "Expected number or numeric string"))
    }
}

struct AIParseOrderResponse: Codable {
    let success: Bool?
    let order_number: String?
    let items: [AIParsedItem]?
    let error: String?
}

// MARK: - Create order direct response

struct AICreateOrderResponse: Codable {
    let success: Bool?
    let message: String?
    let order_id: Int?
    let order_number: String?
    let error: String?
}

enum AIOrderError: LocalizedError {
    case invalidURL
    case notAuthenticated
    case serverError(Int, String?)
    case parsingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Neplatná adresa API"
        case .notAuthenticated: return "Nejste přihlášeni"
        case .serverError(let code, let msg): return msg ?? "Chyba serveru (\(code))"
        case .parsingFailed(let msg): return msg
        }
    }
}

final class AIOrderService {
    /// Backend: JSON API pro AI objednávku (soubor backend-api/add_order_ai.php na serveru např. api/add_order_ai.php)
    private let addAIURLString = "https://www.provikart.cz/api/add_order_ai.php"

    private var addAIURL: URL? {
        URL(string: addAIURLString)
    }

    /// Pošle text objednávky na backend; AI ho zpracuje a vrátí číslo objednávky a položky včetně provizí.
    func parseOrder(text: String, token: String?) async throws -> AIParseOrderResponse {
        guard let url = addAIURL else { throw AIOrderError.invalidURL }
        guard let token = token, !token.isEmpty else { throw AIOrderError.notAuthenticated }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        var body = "action=parse_order&text=\(text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        body += "&token_api=\(token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIOrderError.serverError(-1, "Neplatná odpověď")
        }

        switch http.statusCode {
        case 200:
            let cleanData = dataWithoutBOMOrWhitespace(data)
            if let nonJsonMessage = responseNotJsonMessage(data: cleanData) {
                print("[ProviKart AI] parse_order – server nevrátil JSON: \(nonJsonMessage)")
                throw AIOrderError.parsingFailed(nonJsonMessage)
            }
            do {
                let decoded = try JSONDecoder().decode(AIParseOrderResponse.self, from: cleanData)
                if decoded.success == false, let err = decoded.error {
                    print("[ProviKart AI] parse_order – chyba z API: \(err)")
                    throw AIOrderError.parsingFailed(err)
                }
                return decoded
            } catch let err as AIOrderError {
                throw err
            } catch {
                let msg = friendlyDecodingError(data: cleanData, underlying: error)
                print("[ProviKart AI] parse_order – neplatný formát: \(msg)")
                if let raw = String(data: cleanData.prefix(500), encoding: .utf8) {
                    print("[ProviKart AI] Odpověď serveru (prvních 500 znaků): \(raw)")
                }
                throw AIOrderError.parsingFailed(msg)
            }
        case 401:
            throw AIOrderError.notAuthenticated
        default:
            let cleanData = dataWithoutBOMOrWhitespace(data)
            let message = (try? JSONDecoder().decode([String: String].self, from: cleanData))?["error"]
            print("[ProviKart AI] parse_order – HTTP \(http.statusCode): \(message ?? "bez zprávy")")
            throw AIOrderError.serverError(http.statusCode, message)
        }
    }

    /// Vytvoří objednávku přímo v databázi (order_number + položky). Položky musí být ve formátu vráceném z parse_order.
    func createOrderDirect(orderNumber: String, items: [AIParsedItem], token: String?) async throws -> AICreateOrderResponse {
        guard let url = addAIURL else { throw AIOrderError.invalidURL }
        guard let token = token, !token.isEmpty else { throw AIOrderError.notAuthenticated }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let itemsData = try JSONEncoder().encode(items)
        let itemsJson = String(data: itemsData, encoding: .utf8) ?? "[]"
        var body = "action=create_order_direct"
        body += "&order_number=\(orderNumber.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        body += "&items=\(itemsJson.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        body += "&token_api=\(token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIOrderError.serverError(-1, "Neplatná odpověď")
        }

        switch http.statusCode {
        case 200:
            let cleanData = dataWithoutBOMOrWhitespace(data)
            if let nonJsonMessage = responseNotJsonMessage(data: cleanData) {
                print("[ProviKart AI] create_order_direct – server nevrátil JSON: \(nonJsonMessage)")
                throw AIOrderError.parsingFailed(nonJsonMessage)
            }
            do {
                let decoded = try JSONDecoder().decode(AICreateOrderResponse.self, from: cleanData)
                return decoded
            } catch {
                let msg = friendlyDecodingError(data: cleanData, underlying: error)
                print("[ProviKart AI] create_order_direct – neplatný formát: \(msg)")
                if let raw = String(data: cleanData.prefix(500), encoding: .utf8) {
                    print("[ProviKart AI] Odpověď serveru (prvních 500 znaků): \(raw)")
                }
                throw AIOrderError.parsingFailed(msg)
            }
        case 401:
            throw AIOrderError.notAuthenticated
        default:
            let cleanData = dataWithoutBOMOrWhitespace(data)
            let message = (try? JSONDecoder().decode([String: String].self, from: cleanData))?["error"]
            print("[ProviKart AI] create_order_direct – HTTP \(http.statusCode): \(message ?? "bez zprávy")")
            throw AIOrderError.serverError(http.statusCode, message)
        }
    }

    /// Odstraní BOM (UTF-8) a úvodní/koncové bílé znaky z odpovědi – server nebo proxy je někdy přidají.
    private func dataWithoutBOMOrWhitespace(_ data: Data) -> Data {
        var d = data
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        if d.count >= 3 && d[0] == bom[0] && d[1] == bom[1] && d[2] == bom[2] {
            d = d.dropFirst(3)
        }
        guard let s = String(data: d, encoding: .utf8) else { return d }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return Data(trimmed.utf8)
    }

    /// Pokud server vrátí HTML (např. přihlašovací stránku), vrátí srozumitelnou zprávu.
    private func responseNotJsonMessage(data: Data) -> String? {
        guard data.count > 10 else { return nil }
        let prefix = String(data: data.prefix(200), encoding: .utf8) ?? ""
        let lower = prefix.lowercased()
        if lower.contains("<!DOCTYPE") || lower.hasPrefix("<html") || lower.contains("<html ") {
            return "Server vrátil webovou stránku místo dat. Zkontrolujte přihlášení nebo že adresa API je správná."
        }
        if lower.contains("přihlás") || lower.contains("login") || lower.contains("vítejte zpět") {
            return "Vyžaduje se přihlášení. Jste přihlášeni v aplikaci?"
        }
        return nil
    }

    private func friendlyDecodingError(data: Data, underlying: Error) -> String {
        if let msg = responseNotJsonMessage(data: data) { return msg }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let serverError = json["error"] as? String, !serverError.isEmpty {
                return serverError
            }
            // Náhled odpovědi pro diagnostiku (bez citlivých dat)
            let preview = String(data: data.prefix(400), encoding: .utf8) ?? ""
            if !preview.isEmpty {
                return "API vrátilo neplatný formát dat. Odpověď začíná: \(preview.prefix(150))…"
            }
        }
        let preview = String(data: data.prefix(200), encoding: .utf8) ?? ""
        if preview.isEmpty { return "Server vrátil prázdnou odpověď." }
        return "API vrátilo neplatný formát. Začátek odpovědi: \(preview.prefix(100))…"
    }
}
