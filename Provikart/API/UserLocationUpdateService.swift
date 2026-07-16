//
//  UserLocationUpdateService.swift
//  Provikart
//
//  Vlastní lokalita uživatele (GET/PATCH na user_location endpointy).
//

import Foundation

struct UserLocationRecord: Decodable, Equatable {
    let userId: Int?
    let workDate: String?
    let locationName: String?
    let arrivalTime: String?
    let note: String?
    let updatedAt: String?
    let updatedBy: Int?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case workDate = "work_date"
        case locationName = "location_name"
        case arrivalTime = "arrival_time"
        case note
        case updatedAt = "updated_at"
        case updatedBy = "updated_by"
    }

    var hasContent: Bool {
        !(locationName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    /// HH:mm pro DatePicker / zobrazení.
    var arrivalTimeDisplay: String? {
        guard let raw = arrivalTime?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw.count >= 5 {
            return String(raw.prefix(5))
        }
        return raw
    }
}

struct UserLocationFetchResult {
    let workDate: String
    let location: UserLocationRecord?
}

private struct UserLocationResponse: Decodable {
    let success: Bool
    let workDate: String?
    let location: UserLocationRecord?
    let message: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case workDate = "work_date"
        case location
        case message
        case error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let boolValue = try? c.decode(Bool.self, forKey: .success) {
            success = boolValue
        } else if let intValue = try? c.decode(Int.self, forKey: .success) {
            success = (intValue == 1)
        } else if let stringValue = try? c.decode(String.self, forKey: .success) {
            success = ["1", "true", "yes"].contains(stringValue.lowercased())
        } else {
            success = false
        }
        workDate = try? c.decodeIfPresent(String.self, forKey: .workDate)
        location = try? c.decodeIfPresent(UserLocationRecord.self, forKey: .location)
        message = try? c.decodeIfPresent(String.self, forKey: .message)
        error = try? c.decodeIfPresent(String.self, forKey: .error)
    }
}

enum UserLocationUpdateError: LocalizedError {
    case invalidURL
    case notAuthenticated
    case validation(String)
    case serverError(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Neplatná adresa API"
        case .notAuthenticated:
            return "Nejste přihlášeni"
        case .validation(let message):
            return message
        case .serverError(let code, let message):
            return message ?? "Chyba serveru (\(code))"
        }
    }
}

final class UserLocationUpdateService {
    private let baseURL = "https://provikart.cz/api"

    /// Načte lokalitu pro daný den (GET /api/user_location.php).
    func fetchLocation(token: String?, workDate: String) async throws -> UserLocationFetchResult {
        guard let token, !token.isEmpty else {
            throw UserLocationUpdateError.notAuthenticated
        }

        var comp = URLComponents(string: "\(baseURL)/user_location.php")
        comp?.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "work_date", value: workDate),
            URLQueryItem(name: "_", value: "\(Int(Date().timeIntervalSince1970))")
        ]
        guard let url = comp?.url else {
            throw UserLocationUpdateError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UserLocationUpdateError.serverError(-1, "Neplatná odpověď")
        }

        let decoded = try? JSONDecoder().decode(UserLocationResponse.self, from: data)
        let message = decoded?.error ?? decoded?.message ?? String(data: data, encoding: .utf8)

        switch http.statusCode {
        case 200:
            // Dokud na serveru není user_location.php, odpověď může být HTML 404 se statusem 200.
            guard let decoded else {
                return UserLocationFetchResult(workDate: workDate, location: nil)
            }
            guard decoded.success else {
                throw UserLocationUpdateError.serverError(200, message)
            }
            let location = decoded.location.flatMap { $0.hasContent ? $0 : nil }
            return UserLocationFetchResult(
                workDate: decoded.workDate ?? workDate,
                location: location
            )
        case 404:
            return UserLocationFetchResult(workDate: workDate, location: nil)
        case 401:
            throw UserLocationUpdateError.notAuthenticated
        default:
            throw UserLocationUpdateError.serverError(http.statusCode, message)
        }
    }

    func updateLocation(
        token: String?,
        workDate: String,
        locationName: String,
        arrivalTime: String,
        note: String?
    ) async throws -> UserLocationRecord? {
        guard let token, !token.isEmpty else {
            throw UserLocationUpdateError.notAuthenticated
        }
        guard let url = URL(string: "\(baseURL)/user_location_update.php") else {
            throw UserLocationUpdateError.invalidURL
        }

        let trimmedLocation = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedLocation.isEmpty {
            throw UserLocationUpdateError.validation("Zadejte lokalitu.")
        }

        var body: [String: Any] = [
            "token": token,
            "work_date": workDate,
            "location_name": trimmedLocation,
            "arrival_time": arrivalTime
        ]

        if let note {
            let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedNote.isEmpty {
                body["note"] = trimmedNote
            }
        }

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UserLocationUpdateError.serverError(-1, "Neplatná odpověď")
        }

        let decoded = try? JSONDecoder().decode(UserLocationResponse.self, from: data)
        let message = decoded?.error ?? decoded?.message ?? String(data: data, encoding: .utf8)

        switch http.statusCode {
        case 200:
            guard decoded?.success == true else {
                throw UserLocationUpdateError.serverError(200, message)
            }
            return decoded?.location
        case 400:
            throw UserLocationUpdateError.validation(message ?? "Neplatné vstupní údaje.")
        case 401:
            throw UserLocationUpdateError.notAuthenticated
        default:
            throw UserLocationUpdateError.serverError(http.statusCode, message)
        }
    }
}
