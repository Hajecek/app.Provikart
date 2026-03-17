//
//  EntryCardsCountService.swift
//  Provikart
//
//  Načtení počtu záznamů z Karty vchodu pro přihlášeného uživatele.
//  GET /api/entry_cards_count.php
//

import Foundation

/// Odpověď API – počet záznamů z Karty vchodu za aktuální měsíc.
struct EntryCardsCountResponse: Codable {
    let success: Bool
    let month: String
    /// Součet hodnot `entries_count` za daný měsíc.
    let entries_count: Int
    /// Počet řádků v tabulce `entry_cards` za daný měsíc.
    let rows_count: Int
}

enum EntryCardsCountError: LocalizedError {
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

final class EntryCardsCountService {
    private let baseURL = "https://provikart.cz/api"

    /// Načte statistiku Karty vchodu za aktuální měsíc. Vyžaduje platný API token.
    func fetchCount(token: String?) async throws -> EntryCardsCountResponse {
        guard let token = token, !token.isEmpty else {
            throw EntryCardsCountError.notAuthenticated
        }
        var comp = URLComponents(string: "\(baseURL)/entry_cards_count.php")
        comp?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = comp?.url else {
            throw EntryCardsCountError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw EntryCardsCountError.serverError(-1, "Neplatná odpověď")
        }

        switch http.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(EntryCardsCountResponse.self, from: data)
            } catch {
                throw EntryCardsCountError.serverError(200, "Chyba při zpracování odpovědi")
            }
        case 401:
            throw EntryCardsCountError.notAuthenticated
        default:
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw EntryCardsCountError.serverError(http.statusCode, message)
        }
    }
}

