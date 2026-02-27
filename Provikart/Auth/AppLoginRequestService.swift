//
//  AppLoginRequestService.swift
//  Provikart
//
//  Služba pro schvalování přihlášení na web z aplikace – načtení čekajících požadavků
//  a volání API approve/reject.
//

import Foundation

private struct ErrorResponse: Codable {
    let error: String?
}

/// Jeden čekající požadavek na přihlášení z webu (odpověď app_login_pending.php).
struct AppLoginRequest: Codable, Identifiable {
    let id: Int
    let request_id: String
    let username: String
    let status: String
    let created_at: String?
}

/// Služba pro API přihlášení přes aplikaci (pending + approve/reject).
final class AppLoginRequestService {
    private let baseURL = "https://provikart.cz/api"

    /// Načte čekající požadavky na přihlášení pro daného uživatele.
    /// POST /api/auth/app_login_pending.php, body: { "username": "..." }, volitelně Header: Authorization: Bearer
    func fetchPendingRequests(username: String, token: String? = nil) async throws -> [AppLoginRequest] {
        guard !username.isEmpty,
              let url = URL(string: "\(baseURL)/auth/app_login_pending.php") else {
            return []
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(["username": username])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            return []
        }

        if http.statusCode != 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = json["error"] as? String {
                throw AppLoginError.serverError(err)
            }
            throw AppLoginError.serverError("HTTP \(http.statusCode)")
        }

        // API může vrátit pole nebo { "error": "..." }
        if let errObj = try? JSONDecoder().decode(ErrorResponse.self, from: data), let err = errObj.error {
            throw AppLoginError.serverError(err)
        }
        let list = (try? JSONDecoder().decode([AppLoginRequest].self, from: data)) ?? []
        return list.filter { $0.status == "pending" }
    }

    /// Schválí nebo odmítne požadavek na přihlášení.
    /// Token jen v hlavičce a v těle (ne v URL – znak + v query se na serveru může změnit na mezeru).
    func approveOrReject(requestId: String, action: ApproveAction, token: String) async throws {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty,
              let url = URL(string: "\(baseURL)/auth/app_approve_request.php") else {
            throw AppLoginError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(cleanToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode([
            "request_id": requestId,
            "action": action.rawValue,
            "token": cleanToken
        ])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AppLoginError.serverError("Neplatná odpověď")
        }

        switch http.statusCode {
        case 200:
            return
        case 400, 401, 404:
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = json["error"] as? String {
                throw AppLoginError.serverError(err)
            }
            throw AppLoginError.serverError("Kód \(http.statusCode)")
        default:
            throw AppLoginError.serverError("Chyba serveru (\(http.statusCode))")
        }
    }
}

enum ApproveAction: String, Codable {
    case approve
    case reject
}

enum AppLoginError: LocalizedError {
    case invalidURL
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Neplatná URL"
        case .serverError(let msg): return msg
        }
    }
}
