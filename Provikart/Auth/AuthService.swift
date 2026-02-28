//
//  AuthService.swift
//  Provikart
//
//  Služba pro přihlášení přes API.
//

import Foundation

/// Odpověď API po úspěšném přihlášení (uprav podle skutečného API).
struct LoginResponse: Codable {
    let token: String?
    let user: UserInfo?
}

struct UserInfo: Codable {
    let id: Int?
    let email: String?
    let name: String?
    let username: String?
    let personal_number: String?
    let firstname: String?
    let lastname: String?
    let profile_image: String?
    let role: String?
    /// free / paid – pro zobrazení AI objednávky jen pro placený plán
    let plan: String?

    /// URL profilového obrázku – přes serve_image.php (složka images/ je zakázaná pro přímý přístup).
    var profileImageURL: URL? {
        guard let name = profile_image, !name.isEmpty else { return nil }
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        return URL(string: "https://provikart.cz/auth/serve_image?file=\(encoded)")
    }
}

enum AuthError: LocalizedError {
    case invalidURL
    case invalidCredentials
    case serverError(String)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Neplatná URL adresa"
        case .invalidCredentials: return "Nesprávný e-mail nebo heslo"
        case .serverError(let message): return message
        case .decodingError: return "Chyba při zpracování odpovědi"
        }
    }
}

final class AuthService {
    /// Základní URL API – nastav na adresu svého backendu.
    private let baseURL = "https://provikart.cz/api"

    func login(email: String, password: String) async throws -> LoginResponse {
        guard let url = URL(string: "\(baseURL)/auth/login") else {
            throw AuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: String] = [
            "email": email,
            "password": password
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.serverError("Neplatná odpověď serveru")
        }

        switch httpResponse.statusCode {
        case 200...299:
            do {
                return try JSONDecoder().decode(LoginResponse.self, from: data)
            } catch {
                throw AuthError.decodingError
            }
        case 401:
            throw AuthError.invalidCredentials
        default:
            let rawBody = String(data: data, encoding: .utf8) ?? ""
            // Pro debugging: celá odpověď do konzole
            print("[AuthService] HTTP \(httpResponse.statusCode), tělo: \(rawBody.prefix(500))\(rawBody.count > 500 ? "…" : "")")
            // Uživateli neukazujeme HTML – jen srozumitelnou zprávu
            let userMessage: String
            if rawBody.lowercased().contains("<!doctype") || rawBody.lowercased().contains("<html") {
                userMessage = "Chyba serveru (\(httpResponse.statusCode)). Zkuste to později nebo kontaktujte podporu."
            } else if !rawBody.isEmpty, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let msg = json["message"] as? String {
                userMessage = msg
            } else {
                userMessage = "Chyba serveru (\(httpResponse.statusCode)). Zkuste to později."
            }
            throw AuthError.serverError(userMessage)
        }
    }

    /// Načte aktuálního uživatele podle tokenu (pro kontrolu plánu bez odhlášení).
    /// Backend musí mít endpoint GET /api/auth/me s hlavičkou Authorization: Bearer <token>,
    /// odpověď stejná struktura jako u přihlášení (např. { "user": { ... } }).
    func fetchCurrentUser(token: String?) async throws -> UserInfo? {
        guard let token = token, !token.isEmpty else { return nil }
        guard let url = URL(string: "\(baseURL)/auth/me") else { throw AuthError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.serverError("Neplatná odpověď serveru")
        }

        switch httpResponse.statusCode {
        case 200...299:
            // Podpora odpovědi { "user": { ... } } i přímo { ... }
            if let decoded = try? JSONDecoder().decode(LoginResponse.self, from: data), let user = decoded.user {
                return user
            }
            if let user = try? JSONDecoder().decode(UserInfo.self, from: data) {
                return user
            }
            return nil
        case 401:
            return nil
        default:
            return nil
        }
    }
}
