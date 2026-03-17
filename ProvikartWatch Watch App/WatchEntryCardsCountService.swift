//
//  WatchEntryCardsCountService.swift
//  ProvikartWatch Watch App
//
//  Načtení počtu záznamů z Karty vchodu (entry_cards_count.php) na hodinkách.
//

import Foundation

enum WatchEntryCardsCountError: LocalizedError {
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

private struct WatchEntryCardsCountResponse: Codable {
    let success: Bool
    let month: String
    let entries_count: Int
    let rows_count: Int
}

final class WatchEntryCardsCountService {
    private let baseURL = "https://provikart.cz/api"

    /// Načte statistiku Karty vchodu (součet entries_count) pro aktuální měsíc.
    func fetchEntriesCount(token: String) async throws -> Int {
        guard !token.isEmpty else { throw WatchEntryCardsCountError.notAuthenticated }

        var comp = URLComponents(string: "\(baseURL)/entry_cards_count.php")
        comp?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = comp?.url else { throw WatchEntryCardsCountError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WatchEntryCardsCountError.serverError(-1, "Neplatná odpověď")
        }

        switch http.statusCode {
        case 200:
            let decoded = try JSONDecoder().decode(WatchEntryCardsCountResponse.self, from: data)
            return decoded.entries_count
        case 401:
            throw WatchEntryCardsCountError.notAuthenticated
        default:
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw WatchEntryCardsCountError.serverError(http.statusCode, message)
        }
    }
}

