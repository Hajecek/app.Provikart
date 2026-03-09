//
//  DeleteAccountService.swift
//  Provikart
//
//  Smazání uživatelského účtu (DELETE /api/auth/delete_account.php).
//

import Foundation

struct DeleteAccountResponse: Codable {
    let success: Bool
    let message: String?
    let error: String?
}

enum DeleteAccountError: LocalizedError {
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

final class DeleteAccountService {
    private let baseURL = "https://provikart.cz/api"

    func deleteAccount(token: String?) async throws -> DeleteAccountResponse {
        guard let token = token, !token.isEmpty else {
            throw DeleteAccountError.notAuthenticated
        }

        guard let url = URL(string: "\(baseURL)/auth/delete_account.php") else {
            throw DeleteAccountError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body: [String: String] = ["token_api": token]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DeleteAccountError.serverError(-1, "Neplatná odpověď")
        }

        switch http.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(DeleteAccountResponse.self, from: data)
            } catch {
                throw DeleteAccountError.serverError(200, "Chyba při zpracování odpovědi")
            }
        case 401:
            throw DeleteAccountError.notAuthenticated
        default:
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw DeleteAccountError.serverError(http.statusCode, message)
        }
    }
}
