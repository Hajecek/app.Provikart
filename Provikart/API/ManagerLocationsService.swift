//
//  ManagerLocationsService.swift
//  Provikart
//
//  Načtení lokalit členů týmu manažera (GET /api/manager_locations.php).
//

import Foundation

struct ManagerLocationItem: Decodable, Identifiable {
    let userId: Int
    let name: String
    let firstname: String?
    let lastname: String?
    let username: String?
    let profileImage: String?
    let workDate: String
    let locationName: String
    let arrivalTime: String?
    let note: String?
    let updatedAt: String?

    var id: String { "\(userId)-\(workDate)-\(locationName)" }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case firstname
        case lastname
        case username
        case profileImage = "profile_image"
        case workDate = "work_date"
        case locationName = "location_name"
        case arrivalTime = "arrival_time"
        case note
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let intValue = try? c.decode(Int.self, forKey: .userId) {
            userId = intValue
        } else if let stringValue = try? c.decode(String.self, forKey: .userId),
                  let intValue = Int(stringValue) {
            userId = intValue
        } else {
            throw DecodingError.dataCorruptedError(forKey: .userId, in: c, debugDescription: "Invalid user_id")
        }
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        firstname = try? c.decodeIfPresent(String.self, forKey: .firstname)
        lastname = try? c.decodeIfPresent(String.self, forKey: .lastname)
        username = try? c.decodeIfPresent(String.self, forKey: .username)
        profileImage = try? c.decodeIfPresent(String.self, forKey: .profileImage)
        workDate = (try? c.decode(String.self, forKey: .workDate)) ?? ""
        locationName = (try? c.decode(String.self, forKey: .locationName)) ?? ""
        arrivalTime = try? c.decodeIfPresent(String.self, forKey: .arrivalTime)
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        updatedAt = try? c.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

private struct ManagerLocationsResponse: Decodable {
    let success: Bool
    let workDate: String?
    let count: Int?
    let items: [ManagerLocationItem]
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case workDate = "work_date"
        case count
        case items
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
        if let intCount = try? c.decodeIfPresent(Int.self, forKey: .count) {
            count = intCount
        } else if let stringCount = (try? c.decodeIfPresent(String.self, forKey: .count)) ?? nil,
                  let intCount = Int(stringCount) {
            count = intCount
        } else {
            count = nil
        }
        items = (try? c.decode([ManagerLocationItem].self, forKey: .items)) ?? []
        error = try? c.decodeIfPresent(String.self, forKey: .error)
    }
}

enum ManagerLocationsError: LocalizedError {
    case invalidURL
    case notAuthenticated
    case forbidden(String?)
    case serverError(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Neplatná adresa API"
        case .notAuthenticated:
            return "Nejste přihlášeni"
        case .forbidden(let message):
            return message ?? "Nemáte oprávnění načíst lokality týmu"
        case .serverError(let code, let message):
            return message ?? "Chyba serveru (\(code))"
        }
    }
}

final class ManagerLocationsService {
    private let baseURL = "https://provikart.cz/api"

    func fetchLocations(token: String?, workDate: String) async throws -> [ManagerLocationItem] {
        guard let token, !token.isEmpty else {
            throw ManagerLocationsError.notAuthenticated
        }

        var comp = URLComponents(string: "\(baseURL)/manager_locations.php")
        comp?.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "work_date", value: workDate),
            URLQueryItem(name: "_", value: "\(Int(Date().timeIntervalSince1970))")
        ]
        guard let url = comp?.url else {
            throw ManagerLocationsError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ManagerLocationsError.serverError(-1, "Neplatná odpověď")
        }

        let decoded = try? JSONDecoder().decode(ManagerLocationsResponse.self, from: data)
        let message = decoded?.error ?? String(data: data, encoding: .utf8)

        switch http.statusCode {
        case 200:
            guard let decoded, decoded.success else {
                throw ManagerLocationsError.serverError(200, message)
            }
            return decoded.items
        case 401:
            throw ManagerLocationsError.notAuthenticated
        case 403:
            throw ManagerLocationsError.forbidden(message)
        default:
            throw ManagerLocationsError.serverError(http.statusCode, message)
        }
    }
}
