//
//  UserReportsService.swift
//  Provikart
//
//  Načtení všech reportů přihlášeného uživatele (GET /api/user_reports.php).
//

import Foundation

/// Jeden výrok v reportu (objekt z API: text, created_at, is_result).
struct ReportStatement: Codable {
    let text: String
    let created_at: String?
    let is_result: Bool?
}

/// Jeden report z API user_reports.
struct UserReport: Codable, Identifiable, Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: UserReport, rhs: UserReport) -> Bool { lhs.id == rhs.id }
    let id: Int
    let user_id: Int?
    let order_number: String?
    let note: String?
    let user_note: String?
    let statement: String?
    /// Pole výroků – API vrací objekty { "text": "...", "created_at": "...", "is_result": bool }.
    let statements: [ReportStatement]?
    let status: String?
    let created_at: String?
    let updated_at: String?
    let statement_updated_at: String?
    let result: String?
    let images: [String]?
    let is_term_selection_issue: Bool
    let created_by_manager: Bool?
    /// Manager endpoint: jméno člena týmu, který report vytvořil.
    let user_name: String?
    /// Manager endpoint: username autora reportu.
    let username: String?
    /// Manager endpoint: název souboru profilové fotky uživatele.
    let profile_image: String?
    /// Manager endpoint: volitelná přímá URL profilové fotky.
    let profile_image_url: String?

    enum CodingKeys: String, CodingKey {
        case id, user_id, order_number, note, user_note, statement, statements
        case status, created_at, updated_at, statement_updated_at, result, images
        case is_term_selection_issue, created_by_manager, user_name, username, profile_image, profile_image_url
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        user_id = try c.decodeIfPresent(Int.self, forKey: .user_id)
        order_number = Self.decodeOrderNumber(c)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        user_note = try c.decodeIfPresent(String.self, forKey: .user_note)
        statement = try c.decodeIfPresent(String.self, forKey: .statement)
        statements = try? c.decode([ReportStatement].self, forKey: .statements)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        created_at = try c.decodeIfPresent(String.self, forKey: .created_at)
        updated_at = try c.decodeIfPresent(String.self, forKey: .updated_at)
        statement_updated_at = try c.decodeIfPresent(String.self, forKey: .statement_updated_at)
        result = try c.decodeIfPresent(String.self, forKey: .result)
        images = (try? c.decode([String].self, forKey: .images)) ?? nil
        is_term_selection_issue = (try? c.decode(Bool.self, forKey: .is_term_selection_issue)) ?? false
        created_by_manager = try c.decodeIfPresent(Bool.self, forKey: .created_by_manager)
        user_name = try c.decodeIfPresent(String.self, forKey: .user_name)
        username = try c.decodeIfPresent(String.self, forKey: .username)
        profile_image = try c.decodeIfPresent(String.self, forKey: .profile_image)
        profile_image_url = try c.decodeIfPresent(String.self, forKey: .profile_image_url)
    }

    /// URL profilové fotky autora reportu (pokud je k dispozici).
    var reportProfileImageURL: URL? {
        if let raw = profile_image_url?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let direct = URL(string: raw) {
            return direct
        }
        guard let name = profile_image?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        return URL(string: "https://provikart.cz/auth/serve_image?file=\(encoded)")
    }

    /// order_number může přijít jako String nebo jako číslo – vždy vrátíme řetězec.
    private static func decodeOrderNumber(_ c: KeyedDecodingContainer<CodingKeys>) -> String? {
        if let s = try? c.decode(String.self, forKey: .order_number), !s.isEmpty { return s }
        if let i = try? c.decode(Int.self, forKey: .order_number) { return String(i) }
        return nil
    }

    /// Report je dokončený při statusu "completed". Nedokončené jsou "created" a "open".
    var isCompleted: Bool {
        (status ?? "").lowercased() == "completed"
    }

    /// České zobrazení stavu z API (`created` / `open` / `completed`).
    var statusDisplayCzech: String {
        let t = (status ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "—" }
        switch t.lowercased() {
        case "created": return "Vytvořeno"
        case "open": return "Otevřeno"
        case "completed": return "Dokončeno"
        default: return t
        }
    }
}

/// Odpověď API user_reports.php
struct UserReportsResponse: Codable {
    let success: Bool
    let reports: [UserReport]
    let count: Int
}

enum UserReportsError: LocalizedError {
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

final class UserReportsService {
    private let baseURL = "https://provikart.cz/api"

    /// Načte všechny reporty přihlášeného uživatele. Vyžaduje platný API token.
    func fetchUserReports(token: String?) async throws -> [UserReport] {
        guard let token = token, !token.isEmpty else {
            throw UserReportsError.notAuthenticated
        }
        var comp = URLComponents(string: "\(baseURL)/user_reports.php")
        comp?.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "_", value: "\(Int(Date().timeIntervalSince1970))") // cache bust
        ]
        guard let url = comp?.url else {
            throw UserReportsError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UserReportsError.serverError(-1, "Neplatná odpověď")
        }

        switch http.statusCode {
        case 200:
            do {
                let decoded = try JSONDecoder().decode(UserReportsResponse.self, from: data)
                guard decoded.success else {
                    throw UserReportsError.serverError(200, "API vrátilo success: false")
                }
                return decoded.reports
            } catch {
                throw UserReportsError.serverError(200, "Chyba při zpracování odpovědi")
            }
        case 401:
            throw UserReportsError.notAuthenticated
        default:
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw UserReportsError.serverError(http.statusCode, message)
        }
    }
}
