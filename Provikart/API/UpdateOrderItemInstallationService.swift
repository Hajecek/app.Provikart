//
//  UpdateOrderItemInstallationService.swift
//  Provikart
//
//  Nastavení termínu instalace u položky objednávky. POST /api/update_order_item_installation.php
//

import Foundation

private struct UpdateInstallationResponse: Decodable {
    let success: Bool?
    let error: String?
}

enum UpdateOrderItemInstallationError: LocalizedError {
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

final class UpdateOrderItemInstallationService {
    private let baseURL = "https://provikart.cz/api"

    /// Nastaví termín instalace u položky objednávky.
    /// - Parameters:
    ///   - orderItemId: id položky z tabulky order_items
    ///   - installationDay: datum ve formátu YYYY-MM-DD
    ///   - installationTime: čas ve formátu HH:mm (volitelně, prázdný řetězec = bez času)
    ///   - token: API token
    func updateInstallation(orderItemId: Int, installationDay: String, installationTime: String, token: String?) async throws {
        guard let token = token, !token.isEmpty else {
            throw UpdateOrderItemInstallationError.notAuthenticated
        }
        guard let url = URL(string: "\(baseURL)/update_order_item_installation.php") else {
            throw UpdateOrderItemInstallationError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "order_item_id": orderItemId,
            "installation_day": installationDay,
            "installation_time": installationTime.isEmpty ? "" : installationTime,
            "token": token
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateOrderItemInstallationError.serverError(-1, "Neplatná odpověď")
        }

        let decoded = try? JSONDecoder().decode(UpdateInstallationResponse.self, from: data)
        let serverError = decoded?.error

        switch http.statusCode {
        case 200:
            // Úspěch jen když server vrátí platný JSON s success: true
            if decoded?.success == true {
                return
            }
            // Konkrétní zpráva ze serveru, nebo vysvětlení při neplatném JSON (PHP chyba = HTML místo JSON)
            if let msg = serverError, !msg.isEmpty {
                throw UpdateOrderItemInstallationError.serverError(200, msg)
            }
            if decoded == nil, let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                let preview = String(raw.prefix(120)).replacingOccurrences(of: "\n", with: " ")
                throw UpdateOrderItemInstallationError.serverError(200, "Server vrátil neplatnou odpověď (očekáván JSON). Odpověď: \(preview)...")
            }
            throw UpdateOrderItemInstallationError.serverError(200, "Server vrátil neplatnou odpověď. Zkontrolujte chyby na serveru (PHP logy).")
        case 401:
            throw UpdateOrderItemInstallationError.notAuthenticated
        case 404:
            throw UpdateOrderItemInstallationError.serverError(404, serverError ?? "Položka nebyla nalezena.")
        default:
            throw UpdateOrderItemInstallationError.serverError(http.statusCode, serverError)
        }
    }
}
