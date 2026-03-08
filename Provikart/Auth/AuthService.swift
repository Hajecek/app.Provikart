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

    /// Sloučí data z API s existujícím uživatelem – hodnoty z API mají přednost, u nil se zachová existing (např. profilový obrázek).
    init(merging api: UserInfo, existing: UserInfo?) {
        id = api.id ?? existing?.id
        email = api.email ?? existing?.email
        name = api.name ?? existing?.name
        username = api.username ?? existing?.username
        personal_number = api.personal_number ?? existing?.personal_number
        firstname = api.firstname ?? existing?.firstname
        lastname = api.lastname ?? existing?.lastname
        profile_image = api.profile_image ?? existing?.profile_image
        role = api.role ?? existing?.role
        plan = api.plan ?? existing?.plan
    }

    /// Sjednocený výpis profilu do konzole (tag [Profil]) – používá se při přihlášení i při obnovení uživatele napříč aplikací.
    func logToConsole() {
        print("[Profil] Uživatel:")
        print("  id: \(id ?? 0)")
        print("  email: \(email ?? "—")")
        print("  name: \(name ?? "—")")
        print("  username: \(username ?? "—")")
        print("  personal_number: \(personal_number ?? "—")")
        print("  firstname: \(firstname ?? "—")")
        print("  lastname: \(lastname ?? "—")")
        print("  profile_image: \(profile_image ?? "—")")
        if let url = profileImageURL {
            print("  profile_image_url: \(url.absoluteString)")
        } else {
            print("  profile_image_url: —")
        }
        print("  role: \(role ?? "—")")
        print("  plan: \(plan ?? "—")")
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
    /// POST s tělem token=xxx – tělo se na serveru neodstraňuje (na rozdíl od query u GET).
    /// Odpověď: stejný tvar jako u přihlášení (např. { "user": { ... } }).
    func fetchCurrentUser(token: String?) async throws -> UserInfo? {
        guard let token = token, !token.isEmpty else { return nil }
        guard let url = URL(string: "https://www.provikart.cz/api/auth/me") else { throw AuthError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = "token=\(token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")".data(using: .utf8)

        print("[AuthService] /auth/me – POST token=***")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.serverError("Neplatná odpověď serveru")
        }

        let bodyPreview = String(data: data.prefix(500), encoding: .utf8) ?? "(nelze přečíst)"

        switch httpResponse.statusCode {
        case 200...299:
            // Podpora odpovědi { "user": { ... } } i přímo { ... }
            if let decoded = try? JSONDecoder().decode(LoginResponse.self, from: data), let user = decoded.user {
                return user
            }
            if let user = try? JSONDecoder().decode(UserInfo.self, from: data) {
                return user
            }
            print("[AuthService] /auth/me – HTTP 200, ale dekódování selhalo. Tělo: \(bodyPreview)")
            do {
                _ = try JSONDecoder().decode(LoginResponse.self, from: data)
            } catch {
                print("[AuthService] /auth/me – chyba dekódování: \(error)")
            }
            return nil
        case 401:
            print("[AuthService] /auth/me – HTTP 401 (neplatný/vypršený token). Tělo: \(bodyPreview)")
            return nil
        default:
            print("[AuthService] /auth/me – HTTP \(httpResponse.statusCode). Tělo: \(bodyPreview)")
            return nil
        }
    }
}
