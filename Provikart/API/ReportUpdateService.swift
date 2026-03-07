//
//  ReportUpdateService.swift
//  Provikart
//
//  Úprava a smazání reportu. PATCH /api/report_update.php, DELETE /api/report_delete.php.
//

import Foundation

enum ReportUpdateError: LocalizedError {
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

private struct ReportUpdateResponse: Codable {
    let success: Bool?
    let message: String?
    let report_id: Int?
    let error: String?
}

/// Payload pro úpravu reportu – mapuje body PATCH report_update.php.
struct ReportUpdatePayload {
    let id: Int
    var order_number: String?
    var note: String?
    var user_note: String?
    var is_term_selection_issue: Bool?
    var deleted_images: [String]?
    var images: [String]?  // data:image/jpeg;base64,… max 5 celkem, každý max 5 MB
}

final class ReportUpdateService {
    private let baseURL = "https://provikart.cz/api"

    /// Upraví report na serveru. PATCH report_update.php, Authorization: Bearer token.
    func updateReport(payload: ReportUpdatePayload, token: String?) async throws {
        guard let token = token, !token.isEmpty else {
            throw ReportUpdateError.notAuthenticated
        }
        guard let url = URL(string: "\(baseURL)/report_update.php") else {
            throw ReportUpdateError.invalidURL
        }

        var body: [String: Any] = ["id": payload.id, "token": token]
        if let v = payload.order_number { body["order_number"] = v }
        if let v = payload.note { body["note"] = v }
        if let v = payload.user_note { body["user_note"] = v }
        if let v = payload.is_term_selection_issue { body["is_term_selection_issue"] = v }
        if let v = payload.deleted_images, !v.isEmpty { body["deleted_images"] = v }
        if let v = payload.images, !v.isEmpty { body["images"] = v }

        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 90

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ReportUpdateError.serverError(-1, "Neplatná odpověď")
        }

        let jsonData = sanitizeJsonResponse(data)
        let decoded = try? JSONDecoder().decode(ReportUpdateResponse.self, from: jsonData)
        let serverMessage = decoded?.error ?? decoded?.message

        switch http.statusCode {
        case 200:
            if decoded?.success == true {
                return
            }
            throw ReportUpdateError.serverError(200, serverMessage ?? "Neplatná odpověď serveru.")
        case 401:
            throw ReportUpdateError.serverError(401, serverMessage ?? "Neplatný nebo vypršený token.")
        case 400, 404, 405, 500:
            throw ReportUpdateError.serverError(http.statusCode, serverMessage)
        default:
            throw ReportUpdateError.serverError(http.statusCode, serverMessage)
        }
    }

    /// Smaže report na serveru. DELETE report_delete.php?id=… nebo JSON body { "id": … }.
    func deleteReport(id: Int, token: String?) async throws {
        guard let token = token, !token.isEmpty else {
            throw ReportUpdateError.notAuthenticated
        }
        var comp = URLComponents(string: "\(baseURL)/report_delete.php")
        comp?.queryItems = [
            URLQueryItem(name: "id", value: "\(id)"),
            URLQueryItem(name: "token", value: token)
        ]
        guard let url = comp?.url else {
            throw ReportUpdateError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ReportUpdateError.serverError(-1, "Neplatná odpověď")
        }

        let jsonData = sanitizeJsonResponse(data)
        let decoded = try? JSONDecoder().decode(ReportUpdateResponse.self, from: jsonData)
        let serverMessage = decoded?.error ?? decoded?.message

        switch http.statusCode {
        case 200:
            if decoded?.success == true {
                return
            }
            throw ReportUpdateError.serverError(200, serverMessage ?? "Neplatná odpověď serveru.")
        case 401:
            throw ReportUpdateError.serverError(401, serverMessage ?? "Neplatný nebo vypršený token.")
        case 404, 405, 500:
            throw ReportUpdateError.serverError(http.statusCode, serverMessage)
        default:
            throw ReportUpdateError.serverError(http.statusCode, serverMessage)
        }
    }

    private func sanitizeJsonResponse(_ data: Data) -> Data {
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return data }
        let trimmed = text.drop(while: { $0 == "\u{FEFF}" })
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start < end else { return data }
        return Data(trimmed[start ... end].utf8)
    }
}
