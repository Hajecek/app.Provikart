//
//  ReportIssueService.swift
//  Provikart
//
//  Odeslání nahlášení problému k objednávce. API endpoint se doplní při napojení na backend.
//

import Foundation

enum ReportIssueError: LocalizedError {
    case notAuthenticated
    case invalidURL
    case serverError(Int, String?)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Nejste přihlášeni"
        case .invalidURL: return "Neplatná adresa API"
        case .serverError(let code, let msg): return msg ?? "Chyba serveru (\(code))"
        }
    }
}

final class ReportIssueService {
    private let baseURL = "https://provikart.cz/api"

    /// Odešle nahlášení problému. Po napojení na API doplnit volání na např. POST /api/report_issue.php (nebo dle backendu).
    func submitReport(orderNumber: String, note: String?, token: String?) async throws {
        guard let token = token, !token.isEmpty else {
            throw ReportIssueError.notAuthenticated
        }

        // TODO: Napojit na reálné API (např. POST report_issue.php s parametry order_number, user_note, token).
        // Příklad struktury:
        // var request = URLRequest(url: url)
        // request.httpMethod = "POST"
        // request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // let body = ["order_number": orderNumber, "user_note": note ?? ""]
        // request.httpBody = try JSONEncoder().encode(body)
        // let (_, response) = try await URLSession.shared.data(for: request)
        // ... zpracování odpovědi

        _ = (orderNumber, note, token, baseURL) // použito jen pro potlačení varování do doby implementace API
        try await Task.sleep(nanoseconds: 400_000_000) // krátké zpoždění jako simulace sítě
    }
}
