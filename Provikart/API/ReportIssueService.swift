//
//  ReportIssueService.swift
//  Provikart
//
//  Odeslání nahlášení problému. POST /api/report_issue.php – tělo odpovídá polím tabulky reports.
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

private struct ReportIssueResponse: Codable {
    let success: Bool
    let message: String?
    let report_id: Int?
    let error: String?
}

/// Data pro vytvoření reportu – mapuje pole tabulky reports, která může aplikace odeslat.
struct ReportIssuePayload {
    var order_number: String
    var note: String?
    var user_note: String?
    var is_term_selection_issue: Bool

    init(order_number: String, note: String? = nil, user_note: String? = nil, is_term_selection_issue: Bool = false) {
        self.order_number = order_number
        self.note = note
        self.user_note = user_note
        self.is_term_selection_issue = is_term_selection_issue
    }
}

final class ReportIssueService {
    private let baseURL = "https://provikart.cz/api"

    /// Odešle nahlášení na API. Tělo obsahuje order_number, note, user_note, is_term_selection_issue, token.
    func submitReport(payload: ReportIssuePayload, token: String?) async throws {
        guard let token = token, !token.isEmpty else {
            throw ReportIssueError.notAuthenticated
        }

        guard let url = URL(string: "\(baseURL)/report_issue.php") else {
            throw ReportIssueError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        // Prázdná pole posíláme jako null, aby backend mohl uložit NULL do sloupce user_note.
        struct Body: Encodable {
            let order_number: String
            let note: String?
            let user_note: String?
            let is_term_selection_issue: Bool
            let token: String
        }
        let body = Body(
            order_number: payload.order_number,
            note: payload.note,
            user_note: payload.user_note,
            is_term_selection_issue: payload.is_term_selection_issue,
            token: token
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ReportIssueError.serverError(-1, "Neplatná odpověď")
        }

        let decoded = try? JSONDecoder().decode(ReportIssueResponse.self, from: data)
        let serverMessage = decoded?.error ?? decoded?.message

        switch http.statusCode {
        case 200:
            if decoded?.success == true {
                return
            }
            throw ReportIssueError.serverError(200, serverMessage ?? "API vrátilo success: false")
        case 401:
            throw ReportIssueError.serverError(401, serverMessage ?? "Neplatný nebo vypršený token. Zkuste se znovu přihlásit.")
        case 400, 405, 500:
            throw ReportIssueError.serverError(http.statusCode, serverMessage)
        default:
            throw ReportIssueError.serverError(http.statusCode, serverMessage)
        }
    }
}
