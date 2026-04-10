//
//  UserLocationUpdateService.swift
//  Provikart
//
//  Uložení vlastní lokality uživatele (PATCH /api/user_location_update.php).
//

import Foundation

struct UserLocationUpdateResult: Decodable {
    struct Location: Decodable {
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
    }

    let success: Bool?
    let message: String?
    let error: String?
    let location: Location?
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

    func updateLocation(
        token: String?,
        workDate: String,
        locationName: String,
        arrivalTime: String,
        note: String?
    ) async throws -> UserLocationUpdateResult.Location? {
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

        let decoded = try? JSONDecoder().decode(UserLocationUpdateResult.self, from: data)
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
