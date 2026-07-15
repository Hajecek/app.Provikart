//
//  TeamProfileService.swift
//  Provikart
//
//  Týmové profily (GET /api/team_profiles.php).
//

import Foundation

struct TeamProfile: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let firstname: String?
    let lastname: String?
    let username: String?
    let email: String?
    let personal_number: String?
    let profile_image: String?
    let profile_image_url: String?
    let role: String?
    let team_id: Int?
    let birth_date: String?
    let city: String?
    let interests: String?
    let motivation: String?
    let watch_for: String?

    enum CodingKeys: String, CodingKey {
        case id, name, firstname, lastname, username, email, personal_number
        case profile_image, profile_image_url, role, team_id
        case birth_date, city, interests, motivation, watch_for
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? c.decode(Int.self, forKey: .id) {
            id = intId
        } else if let stringId = try? c.decode(String.self, forKey: .id), let intId = Int(stringId) {
            id = intId
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "Invalid profile id")
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
        profile_image_url = try c.decodeIfPresent(String.self, forKey: .profile_image_url)
        role = try c.decodeIfPresent(String.self, forKey: .role)
        if let intTeamId = try? c.decodeIfPresent(Int.self, forKey: .team_id) {
            team_id = intTeamId
        } else if let stringTeamId = (try? c.decodeIfPresent(String.self, forKey: .team_id)) ?? nil,
                  let intTeamId = Int(stringTeamId) {
            team_id = intTeamId
        } else {
            team_id = nil
        }
        birth_date = try c.decodeIfPresent(String.self, forKey: .birth_date)
        city = try c.decodeIfPresent(String.self, forKey: .city)
        interests = try c.decodeIfPresent(String.self, forKey: .interests)
        motivation = try c.decodeIfPresent(String.self, forKey: .motivation)
        watch_for = try c.decodeIfPresent(String.self, forKey: .watch_for)
    }

    init(member: ManagerTeamMember) {
        id = member.id
        name = member.name
        firstname = member.firstname
        lastname = member.lastname
        username = member.username
        email = member.email
        personal_number = member.personal_number
        profile_image = member.profile_image
        profile_image_url = nil
        role = member.role
        team_id = member.team_id
        birth_date = nil
        city = nil
        interests = nil
        motivation = nil
        watch_for = nil
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TeamProfile, rhs: TeamProfile) -> Bool {
        lhs.id == rhs.id
    }
}

extension TeamProfile {
    var profileImageURL: URL? {
        if let direct = profile_image_url?.trimmingCharacters(in: .whitespacesAndNewlines),
           !direct.isEmpty,
           let url = URL(string: direct) {
            return url
        }
        guard let name = profile_image?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return nil
        }
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        return URL(string: "https://provikart.cz/auth/serve_image?file=\(encoded)")
    }

    var displayName: String {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        let first = firstname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let last = lastname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let full = "\(first) \(last)".trimmingCharacters(in: .whitespacesAndNewlines)
        if !full.isEmpty {
            return full
        }
        if let username = username, !username.isEmpty {
            return "@\(username)"
        }
        return "Uživatel #\(id)"
    }

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }.joined()
        if !letters.isEmpty {
            return letters.uppercased()
        }
        return String(displayName.prefix(1)).uppercased()
    }

    var roleLabel: String? {
        switch role?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "manager": return "Manažer"
        case "admin": return "Administrátor"
        case "user": return "Uživatel"
        default: return role?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private func decodeAPIBool<K: CodingKey>(_ c: KeyedDecodingContainer<K>, key: K) -> Bool {
    if let boolSuccess = try? c.decode(Bool.self, forKey: key) {
        return boolSuccess
    }
    if let intSuccess = try? c.decode(Int.self, forKey: key) {
        return intSuccess == 1
    }
    if let stringSuccess = try? c.decode(String.self, forKey: key) {
        return ["1", "true", "yes"].contains(stringSuccess.lowercased())
    }
    return false
}

private struct TeamProfilesListResponse: Decodable {
    let success: Bool
    let profiles: [TeamProfile]
    let count: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, profiles, count, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = decodeAPIBool(c, key: .success)
        profiles = (try? c.decode([TeamProfile].self, forKey: .profiles)) ?? []
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

private struct TeamProfileDetailResponse: Decodable {
    let success: Bool
    let profile: TeamProfile?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, profile, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = decodeAPIBool(c, key: .success)
        profile = try c.decodeIfPresent(TeamProfile.self, forKey: .profile)
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }
}

enum TeamProfileError: LocalizedError {
    case invalidURL
    case notAuthenticated
    case notFound(String?)
    case forbidden(String?)
    case endpointUnavailable
    case serverError(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Neplatná adresa API"
        case .notAuthenticated:
            return "Nejste přihlášeni"
        case .notFound(let message):
            return message ?? "Profil nebyl nalezen"
        case .forbidden(let message):
            return message ?? "Nemáte oprávnění zobrazit tento profil"
        case .endpointUnavailable:
            return "Endpoint týmových profilů na serveru zatím není dostupný."
        case .serverError(let code, let message):
            if let message, isLikelyHTML(message) {
                return "API týmových profilů není na serveru nasazené (team_profiles.php)."
            }
            return message ?? "Chyba serveru (\(code))"
        }
    }
}

private func isLikelyJSON(_ data: Data) -> Bool {
    let whitespace: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]
    for byte in data {
        if whitespace.contains(byte) { continue }
        return byte == UInt8(ascii: "{") || byte == UInt8(ascii: "[")
    }
    return false
}

private func isLikelyHTML(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return trimmed.hasPrefix("<!doctype") || trimmed.hasPrefix("<html")
}

final class TeamProfileService {
    private let baseURL = "https://provikart.cz/api"
    private let membersService = ManagerTeamMembersService()

    func fetchProfiles(token: String?, includeSelf: Bool = true) async throws -> [TeamProfile] {
        guard let token, !token.isEmpty else {
            throw TeamProfileError.notAuthenticated
        }

        do {
            return try await fetchProfilesFromTeamProfilesAPI(token: token, includeSelf: includeSelf)
        } catch let error as TeamProfileError where shouldFallbackToMembers(error) {
            return try await fetchProfilesFromMembersFallback(token: token)
        }
    }

    func fetchProfile(id: Int, token: String?) async throws -> TeamProfile {
        guard let token, !token.isEmpty else {
            throw TeamProfileError.notAuthenticated
        }
        guard id > 0 else {
            throw TeamProfileError.notFound(nil)
        }

        do {
            return try await fetchProfileFromTeamProfilesAPI(id: id, token: token)
        } catch let error as TeamProfileError where shouldFallbackToMembers(error) {
            return try await fetchProfileFromMembersFallback(id: id, token: token)
        }
    }

    private func shouldFallbackToMembers(_ error: TeamProfileError) -> Bool {
        switch error {
        case .endpointUnavailable:
            return true
        case .serverError(let code, let message):
            return code == 404 || (message.map(isLikelyHTML) ?? false)
        default:
            return false
        }
    }

    private func fetchProfilesFromTeamProfilesAPI(token: String, includeSelf: Bool) async throws -> [TeamProfile] {
        var comp = URLComponents(string: "\(baseURL)/team_profiles.php")
        var queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "_", value: "\(Int(Date().timeIntervalSince1970))")
        ]
        if !includeSelf {
            queryItems.append(URLQueryItem(name: "include_self", value: "0"))
        }
        comp?.queryItems = queryItems
        guard let url = comp?.url else {
            throw TeamProfileError.invalidURL
        }

        let (data, http) = try await performGETWithStatus(url: url, token: token)
        guard isLikelyJSON(data) else {
            throw TeamProfileError.endpointUnavailable
        }

        let decoded = try? JSONDecoder().decode(TeamProfilesListResponse.self, from: data)
        let message = decoded?.error ?? String(data: data, encoding: .utf8)

        switch http.statusCode {
        case 200:
            guard let decoded, decoded.success else {
                throw TeamProfileError.serverError(200, message)
            }
            return decoded.profiles
        case 401:
            throw TeamProfileError.notAuthenticated
        case 403:
            throw TeamProfileError.forbidden(message)
        case 404:
            throw TeamProfileError.endpointUnavailable
        default:
            throw TeamProfileError.serverError(http.statusCode, message)
        }
    }

    private func fetchProfileFromTeamProfilesAPI(id: Int, token: String) async throws -> TeamProfile {
        var comp = URLComponents(string: "\(baseURL)/team_profiles.php")
        comp?.queryItems = [
            URLQueryItem(name: "id", value: "\(id)"),
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "_", value: "\(Int(Date().timeIntervalSince1970))")
        ]
        guard let url = comp?.url else {
            throw TeamProfileError.invalidURL
        }

        let (data, http) = try await performGETWithStatus(url: url, token: token)
        guard isLikelyJSON(data) else {
            throw TeamProfileError.endpointUnavailable
        }

        let decoded = try? JSONDecoder().decode(TeamProfileDetailResponse.self, from: data)
        let message = decoded?.error ?? String(data: data, encoding: .utf8)

        switch http.statusCode {
        case 200:
            guard let decoded, decoded.success, let profile = decoded.profile else {
                throw TeamProfileError.serverError(200, message)
            }
            return profile
        case 401:
            throw TeamProfileError.notAuthenticated
        case 403:
            throw TeamProfileError.forbidden(message)
        case 404:
            throw TeamProfileError.endpointUnavailable
        default:
            throw TeamProfileError.serverError(http.statusCode, message)
        }
    }

    private func fetchProfilesFromMembersFallback(token: String) async throws -> [TeamProfile] {
        let members = try await membersService.fetchMembers(token: token)
        return members.map(TeamProfile.init(member:))
    }

    private func fetchProfileFromMembersFallback(id: Int, token: String) async throws -> TeamProfile {
        let members = try await membersService.fetchMembers(token: token)
        guard let member = members.first(where: { $0.id == id }) else {
            throw TeamProfileError.notFound("Profil nebyl nalezen v seznamu členů týmu.")
        }
        return TeamProfile(member: member)
    }

    private func performGETWithStatus(url: URL, token: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TeamProfileError.serverError(-1, "Neplatná odpověď")
        }
        return (data, http)
    }
}
