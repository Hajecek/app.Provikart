//
//  CommissionService.swift
//  Provikart
//
//  Načtení měsíční provize z API (GET /api/commission.php).
//

import Foundation

/// Odpověď API provize za aktuální měsíc.
struct CommissionResponse: Codable {
    let success: Bool
    let month: String
    let month_label: String?
    let commission: Double
    let currency: String
}

enum CommissionError: LocalizedError {
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

final class CommissionService {
    private let baseURL = "https://provikart.cz/api"

    /// Načte provizi za aktuální měsíc. Vyžaduje platný API token.
    /// Token se posílá v hlavičce Authorization i v GET parametru (některé servery hlavičku odstraňují).
    func fetchCommission(token: String?) async throws -> CommissionResponse {
        guard let token = token, !token.isEmpty else {
            throw CommissionError.notAuthenticated
        }
        var comp = URLComponents(string: "\(baseURL)/commission.php")
        comp?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = comp?.url else {
            throw CommissionError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CommissionError.serverError(-1, "Neplatná odpověď")
        }

        switch http.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(CommissionResponse.self, from: data)
            } catch {
                throw CommissionError.serverError(200, "Chyba při zpracování odpovědi")
            }
        case 401:
            throw CommissionError.notAuthenticated
        default:
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw CommissionError.serverError(http.statusCode, message)
        }
    }
}
