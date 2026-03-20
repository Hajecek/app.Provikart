//
//  ManagerTeamMembersService.swift
//  Provikart
//
//  Načtení členů týmu manažera (GET /api/manager_team_members.php).
//

import Foundation

struct ManagerTeamMember: Decodable, Identifiable {
    let id: Int
    let name: String?
    let firstname: String?
    let lastname: String?
    let username: String?
    let email: String?
    let personal_number: String?
    let profile_image: String?
    let role: String?
    let team_id: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, firstname, lastname, username, email, personal_number, profile_image, role, team_id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? c.decode(Int.self, forKey: .id) {
            id = intId
        } else if let stringId = try? c.decode(String.self, forKey: .id), let intId = Int(stringId) {
            id = intId
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "Invalid member id")
        }
        name = try c.decodeIfPresent(String.self, forKey: .name)
        firstname = try c.decodeIfPresent(String.self, forKey: .firstname)
        lastname = try c.decodeIfPresent(String.self, forKey: .lastname)
        username = try c.decodeIfPresent(String.self, forKey: .username)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        if let personalNumberString = try? c.decodeIfPresent(String.self, forKey: .personal_number) {
            personal_number = personalNumberString
        } else if let personalNumberInt = (try? c.decodeIfPresent(Int.self, forKey: .personal_number)) ?? nil {
            personal_number = String(personalNumberInt)
        } else if let personalNumberDouble = (try? c.decodeIfPresent(Double.self, forKey: .personal_number)) ?? nil {
            personal_number = String(Int(personalNumberDouble))
        } else {
            personal_number = nil
        }
        profile_image = try c.decodeIfPresent(String.self, forKey: .profile_image)
        role = try c.decodeIfPresent(String.self, forKey: .role)
        if let intTeamId = try? c.decodeIfPresent(Int.self, forKey: .team_id) {
            team_id = intTeamId
        } else if let stringTeamId = (try? c.decodeIfPresent(String.self, forKey: .team_id)) ?? nil,
                  let intTeamId = Int(stringTeamId) {
            team_id = intTeamId
        } else {
            team_id = nil
        }
    }
}

private struct ManagerTeamMembersResponse: Decodable {
    let success: Bool
    let members: [ManagerTeamMember]
    let count: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, members, count, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let boolSuccess = try? c.decode(Bool.self, forKey: .success) {
            success = boolSuccess
        } else if let intSuccess = try? c.decode(Int.self, forKey: .success) {
            success = (intSuccess == 1)
        } else if let stringSuccess = try? c.decode(String.self, forKey: .success) {
            success = ["1", "true", "yes"].contains(stringSuccess.lowercased())
        } else {
            success = false
        }
        members = (try? c.decode([ManagerTeamMember].self, forKey: .members)) ?? []
        if let intCount = try? c.decodeIfPresent(Int.self, forKey: .count) {
            count = intCount
        } else if let stringCount = (try? c.decodeIfPresent(String.self, forKey: .count)) ?? nil,
                  let intCount = Int(stringCount) {
            count = intCount
        } else {
            count = nil
        }
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }
}

enum ManagerTeamMembersError: LocalizedError {
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
            return message ?? "Nemáte oprávnění načíst členy týmu"
        case .serverError(let code, let message):
            return message ?? "Chyba serveru (\(code))"
        }
    }
}

final class ManagerTeamMembersService {
    private let baseURL = "https://provikart.cz/api"

    func fetchMembers(token: String?) async throws -> [ManagerTeamMember] {
        guard let token, !token.isEmpty else {
            throw ManagerTeamMembersError.notAuthenticated
        }

        var comp = URLComponents(string: "\(baseURL)/manager_team_members.php")
        comp?.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "_", value: "\(Int(Date().timeIntervalSince1970))")
        ]
        guard let url = comp?.url else {
            throw ManagerTeamMembersError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ManagerTeamMembersError.serverError(-1, "Neplatná odpověď")
        }

        let decoded = try? JSONDecoder().decode(ManagerTeamMembersResponse.self, from: data)
        let message = decoded?.error ?? String(data: data, encoding: .utf8)

        switch http.statusCode {
        case 200:
            guard let decoded, decoded.success else {
                throw ManagerTeamMembersError.serverError(200, message)
            }
            return decoded.members
        case 401:
            throw ManagerTeamMembersError.notAuthenticated
        case 403:
            throw ManagerTeamMembersError.forbidden(message)
        default:
            throw ManagerTeamMembersError.serverError(http.statusCode, message)
        }
    }
}
