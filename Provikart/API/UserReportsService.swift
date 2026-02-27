//
//  UserReportsService.swift
//  Provikart
//
//  Načtení všech reportů přihlášeného uživatele (GET /api/user_reports.php).
//

import Foundation

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
    /// Pole výroků (JSON z DB) – může být pole řetězců nebo objektů.
    let statements: [String]?
    let status: String?
    let created_at: String?
    let updated_at: String?
    let statement_updated_at: String?
    let result: String?
    /// Pole URL obrázků (JSON z DB).
    let images: [String]?
    let is_term_selection_issue: Bool
    let created_by_manager: Bool?

    enum CodingKeys: String, CodingKey {
        case id, user_id, order_number, note, user_note, statement, statements
        case status, created_at, updated_at, statement_updated_at, result, images
        case is_term_selection_issue, created_by_manager
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        user_id = try c.decodeIfPresent(Int.self, forKey: .user_id)
        order_number = try c.decodeIfPresent(String.self, forKey: .order_number)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        user_note = try c.decodeIfPresent(String.self, forKey: .user_note)
        statement = try c.decodeIfPresent(String.self, forKey: .statement)
        statements = (try? c.decode([String].self, forKey: .statements)) ?? nil
        status = try c.decodeIfPresent(String.self, forKey: .status)
        created_at = try c.decodeIfPresent(String.self, forKey: .created_at)
        updated_at = try c.decodeIfPresent(String.self, forKey: .updated_at)
        statement_updated_at = try c.decodeIfPresent(String.self, forKey: .statement_updated_at)
        result = try c.decodeIfPresent(String.self, forKey: .result)
        images = (try? c.decode([String].self, forKey: .images)) ?? nil
        is_term_selection_issue = (try? c.decode(Bool.self, forKey: .is_term_selection_issue)) ?? false
        created_by_manager = try c.decodeIfPresent(Bool.self, forKey: .created_by_manager)
    }

    /// Report je dokončený při statusu "completed". Nedokončené jsou "created" a "open".
    var isCompleted: Bool {
        (status ?? "").lowercased() == "completed"
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
        comp?.queryItems = [URLQueryItem(name: "token", value: token)]
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
