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
    let success: Bool?
    let message: String?
    let report_id: Int?
    let error: String?

    var isSuccess: Bool { success ?? false }

    enum CodingKeys: String, CodingKey {
        case success, message, report_id, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        if let intVal = try? c.decode(Int.self, forKey: .report_id) {
            report_id = intVal
        } else if let strVal = try? c.decode(String.self, forKey: .report_id), let intVal = Int(strVal) {
            report_id = intVal
        } else {
            report_id = nil
        }
    }
}

/// Data pro vytvoření reportu – mapuje pole tabulky reports, která může aplikace odeslat.
/// Pole `images`: pole řetězců ve formátu "data:image/jpeg;base64,…" (max 5, každý max 5 MB na serveru).
struct ReportIssuePayload {
    var order_number: String
    var note: String?
    var user_note: String?
    var is_term_selection_issue: Bool
    var images: [String]?

    init(order_number: String, note: String? = nil, user_note: String? = nil, is_term_selection_issue: Bool = false, images: [String]? = nil) {
        self.order_number = order_number
        self.note = note
        self.user_note = user_note
        self.is_term_selection_issue = is_term_selection_issue
        self.images = images
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

        // Prázdná pole posíláme jako null. Obrázky jako pole "data:image/jpeg;base64,…" (max 5).
        struct Body: Encodable {
            let order_number: String
            let note: String?
            let user_note: String?
            let is_term_selection_issue: Bool
            let images: [String]?
            let token: String
        }
        let body = Body(
            order_number: payload.order_number,
            note: payload.note,
            user_note: payload.user_note,
            is_term_selection_issue: payload.is_term_selection_issue,
            images: payload.images?.isEmpty == true ? nil : payload.images,
            token: token
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ReportIssueError.serverError(-1, "Neplatná odpověď")
        }

        let jsonData = sanitizeJsonResponse(data)
        let decoded = try? JSONDecoder().decode(ReportIssueResponse.self, from: jsonData)
        let serverMessage = decoded?.error ?? decoded?.message ?? messageFromRawResponse(jsonData)

        switch http.statusCode {
        case 200:
            if decoded?.isSuccess == true {
                return
            }
            throw ReportIssueError.serverError(200, serverMessage ?? "Odpověď serveru není platné JSON. Zkuste to znovu nebo bez příloh.")
        case 401:
            throw ReportIssueError.serverError(401, serverMessage ?? "Neplatný nebo vypršený token. Zkuste se znovu přihlásit.")
        case 400, 405, 500:
            throw ReportIssueError.serverError(http.statusCode, serverMessage)
        default:
            throw ReportIssueError.serverError(http.statusCode, serverMessage)
        }
    }

    /// Odstraní BOM, mezery a případný text před/za JSON (některé servery nebo PHP přidají výstup před json_encode).
    private func sanitizeJsonResponse(_ data: Data) -> Data {
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return data }
        let trimmed = text.drop(while: { $0 == "\u{FEFF}" }) // BOM
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start < end else { return data }
        let slice = trimmed[start ... end]
        return Data(slice.utf8)
    }

    /// Zkusí z odpovědi (JSON nebo text) vyčíst chybovou zprávu, když standardní dekódování selže.
    private func messageFromRawResponse(_ data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = json["error"] as? String, !err.isEmpty { return err }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let msg = json["message"] as? String, !msg.isEmpty { return msg }
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let t = text, t.prefix(1) == "{", t.contains("error") {
            return "Chyba serveru – zkontrolujte připojení."
        }
        if let t = text, !t.isEmpty, t.count < 500 {
            return t.hasPrefix("<") ? "Server vrátil chybu (neplatná odpověď)." : nil
        }
        return nil
    }
}
