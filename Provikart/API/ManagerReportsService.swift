//
//  ManagerReportsService.swift
//  Provikart
//
//  Načtení reportů týmu manažera (GET /api/manager_reports.php).
//

import Foundation

struct ManagerReportsResponse: Decodable {
    let success: Bool
    let reports: [UserReport]
    let count: Int
}

enum ManagerReportsError: LocalizedError {
    case invalidURL
    case notAuthenticated
    case serverError(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Neplatná adresa API"
        case .notAuthenticated: return "Nejste přihlášeni"
        case .serverError(let code, let message): return message ?? "Chyba serveru (\(code))"
        }
    }
}

final class ManagerReportsService {
    private let baseURL = "https://provikart.cz/api"

    func fetchManagerReports(token: String?) async throws -> [UserReport] {
        guard let token = token, !token.isEmpty else {
            throw ManagerReportsError.notAuthenticated
        }

        var comp = URLComponents(string: "\(baseURL)/manager_reports.php")
        comp?.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "_", value: "\(Int(Date().timeIntervalSince1970))")
        ]
        guard let url = comp?.url else {
            throw ManagerReportsError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ManagerReportsError.serverError(-1, "Neplatná odpověď")
        }

        switch http.statusCode {
        case 200:
            do {
                let decoded = try JSONDecoder().decode(ManagerReportsResponse.self, from: data)
                guard decoded.success else {
                    throw ManagerReportsError.serverError(200, "API vrátilo success: false")
                }
                return decoded.reports
            } catch {
                let body = String(data: data, encoding: .utf8)
                throw ManagerReportsError.serverError(200, body)
            }
        case 401:
            throw ManagerReportsError.notAuthenticated
        default:
            let body = String(data: data, encoding: .utf8)
            throw ManagerReportsError.serverError(http.statusCode, body)
        }
    }
}
