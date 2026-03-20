//
//  WatchManagerReportsService.swift
//  ProvikartWatch Watch App
//
//  Načtení reportů týmu manažera na hodinkách.
//

import Foundation

enum WatchManagerReportsError: LocalizedError {
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

private struct WatchManagerReportItem: Codable {
    let status: String?
}

private struct WatchManagerReportsResponse: Codable {
    let success: Bool
    let reports: [WatchManagerReportItem]
}

final class WatchManagerReportsService {
    private let baseURL = "https://provikart.cz/api"

    /// Načte počet aktivních reportů (created + open) pro manažera.
    func fetchActiveReportsCount(token: String) async throws -> Int {
        guard !token.isEmpty else { throw WatchManagerReportsError.notAuthenticated }

        var comp = URLComponents(string: "\(baseURL)/manager_reports.php")
        comp?.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "_", value: "\(Int(Date().timeIntervalSince1970))")
        ]
        guard let url = comp?.url else { throw WatchManagerReportsError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WatchManagerReportsError.serverError(-1, "Neplatná odpověď")
        }

        switch http.statusCode {
        case 200:
            let decoded = try JSONDecoder().decode(WatchManagerReportsResponse.self, from: data)
            guard decoded.success else {
                throw WatchManagerReportsError.serverError(200, "API vrátilo success: false")
            }
            return decoded.reports.filter { report in
                let status = (report.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return status == "created" || status == "open"
            }.count
        case 401:
            throw WatchManagerReportsError.notAuthenticated
        default:
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw WatchManagerReportsError.serverError(http.statusCode, message)
        }
    }
}
