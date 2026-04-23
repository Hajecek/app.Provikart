//
//  DealwarsSeasonService.swift
//  Provikart
//
//  Načtení žebříčku Deal Wars sezóny z API game_season.php.
//

import Foundation

struct DealwarsPlayer: Decodable, Identifiable {
    let userId: Int?
    let rank: Int
    let name: String
    let points: Double
    let xpBase: Int
    let dailyBonus: Int
    let mixBonus: Int
    let locationBonus: Int
    let locationDays2XP: Int
    let locationDays1XP: Int
    let locationDaysMinus1XP: Int
    let tarif: Int
    let tv: Int
    let internet: Int
    let bossKill: Int
    let winnerEligible: Bool
    let mixEligible: Bool
    let profileImageName: String?
    let profileImageURLString: String?

    var id: String {
        if let userId {
            return "user-\(userId)"
        }
        return "\(rank)-\(name)"
    }

    var resolvedProfileURL: URL? {
        if let profileImageURLString, !profileImageURLString.isEmpty {
            return Self.normalizedURL(from: profileImageURLString)
        }
        if let profileImageName, !profileImageName.isEmpty {
            let encoded = profileImageName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? profileImageName
            return URL(string: "https://provikart.cz/auth/serve_image?file=\(encoded)")
        }
        return nil
    }

    static func normalizedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            if let direct = URL(string: trimmed) { return direct }
            let escaped = trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
            return escaped.flatMap(URL.init(string:))
        }

        let relative = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relative.isEmpty else { return nil }

        if relative.contains("?") {
            let parts = relative.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            let path = String(parts[0])
            let query = parts.count > 1 ? String(parts[1]) : ""
            var components = URLComponents()
            components.scheme = "https"
            components.host = "provikart.cz"
            components.percentEncodedPath = "/" + (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)
            components.percentEncodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            return components.url
        }

        let encodedPath = relative.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relative
        return URL(string: "https://provikart.cz/\(encodedPath)")
    }

    enum CodingKeys: String, CodingKey {
        case user_id, id, seller_id
        case rank, position
        case points, score, total_points, xp_total
        case xp_base, daily_bonus, mix_bonus, location_bonus
        case location_days_2xp, location_days_1xp, location_days_minus1xp
        case tarif, tv, internet, boss_kill
        case winner_eligible, mix_eligible
        case seller, name, full_name, username, firstname, lastname
        case seller_avatar_url, profile_image, profileImage, profile_image_url, avatar_url, image_url
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = c.decodeIntIfPresent(forKeys: [.seller_id, .user_id, .id])
        rank = c.decodeIntIfPresent(forKeys: [.rank, .position]) ?? 0
        points = c.decodeDoubleIfPresent(forKeys: [.xp_total, .points, .score, .total_points]) ?? 0
        xpBase = c.decodeIntIfPresent(forKeys: [.xp_base]) ?? 0
        dailyBonus = c.decodeIntIfPresent(forKeys: [.daily_bonus]) ?? 0
        mixBonus = c.decodeIntIfPresent(forKeys: [.mix_bonus]) ?? 0
        locationBonus = c.decodeIntIfPresent(forKeys: [.location_bonus]) ?? 0
        locationDays2XP = c.decodeIntIfPresent(forKeys: [.location_days_2xp]) ?? 0
        locationDays1XP = c.decodeIntIfPresent(forKeys: [.location_days_1xp]) ?? 0
        locationDaysMinus1XP = c.decodeIntIfPresent(forKeys: [.location_days_minus1xp]) ?? 0
        tarif = c.decodeIntIfPresent(forKeys: [.tarif]) ?? 0
        tv = c.decodeIntIfPresent(forKeys: [.tv]) ?? 0
        internet = c.decodeIntIfPresent(forKeys: [.internet]) ?? 0
        bossKill = c.decodeIntIfPresent(forKeys: [.boss_kill]) ?? 0
        winnerEligible = c.decodeBoolIfPresent(forKeys: [.winner_eligible]) ?? false
        mixEligible = c.decodeBoolIfPresent(forKeys: [.mix_eligible]) ?? false

        let baseName = c.decodeStringIfPresent(forKeys: [.seller, .name, .full_name, .username])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = c.decodeStringIfPresent(forKeys: [.firstname])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = c.decodeStringIfPresent(forKeys: [.lastname])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let joined = [first, last].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " ")
        if let baseName, !baseName.isEmpty {
            name = baseName
        } else if !joined.isEmpty {
            name = joined
        } else {
            name = "Hráč"
        }

        profileImageName = c.decodeStringIfPresent(forKeys: [.profile_image, .profileImage])
        profileImageURLString = c.decodeStringIfPresent(forKeys: [.seller_avatar_url, .profile_image_url, .avatar_url, .image_url])
    }
}

struct DealwarsTeamPlayer: Decodable, Identifiable {
    let sellerId: Int
    let seller: String
    let sellerAvatarURL: String?

    var id: Int { sellerId }

    enum CodingKeys: String, CodingKey {
        case seller_id, seller, seller_avatar_url
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sellerId = c.decodeIntIfPresent(forKeys: [.seller_id]) ?? 0
        seller = c.decodeStringIfPresent(forKeys: [.seller]) ?? "Hráč"
        sellerAvatarURL = c.decodeStringIfPresent(forKeys: [.seller_avatar_url])
    }
}

struct DealwarsSeasonData: Decodable {
    let season: String
    let scope: String
    let leaderboard: [DealwarsPlayer]
    let playersCount: Int
    let teamPlayers: [DealwarsTeamPlayer]

    enum CodingKeys: String, CodingKey {
        case season, scope, leaderboard, ranking, players, items, players_count, team_players
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        season = c.decodeStringIfPresent(forKeys: [.season]) ?? ""
        scope = c.decodeStringIfPresent(forKeys: [.scope]) ?? "team"
        leaderboard =
            c.decodeArrayIfPresent([DealwarsPlayer].self, forKeys: [.leaderboard]) ??
            c.decodeArrayIfPresent([DealwarsPlayer].self, forKeys: [.ranking]) ??
            c.decodeArrayIfPresent([DealwarsPlayer].self, forKeys: [.players]) ??
            c.decodeArrayIfPresent([DealwarsPlayer].self, forKeys: [.items]) ??
            []
        playersCount = c.decodeIntIfPresent(forKeys: [.players_count]) ?? leaderboard.count
        teamPlayers = c.decodeArrayIfPresent([DealwarsTeamPlayer].self, forKeys: [.team_players]) ?? []
    }
}

private struct DealwarsSeasonResponse: Decodable {
    let success: Bool
    let data: DealwarsSeasonData?
    let error: String?
}

enum DealwarsSeasonError: LocalizedError {
    case invalidURL
    case notAuthenticated
    case invalidResponse
    case serverError(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Neplatná adresa API"
        case .notAuthenticated:
            return "Nejste přihlášeni"
        case .invalidResponse:
            return "Odpověď serveru se nepodařilo zpracovat"
        case .serverError(let code, let message):
            return message ?? "Chyba serveru (\(code))"
        }
    }
}

final class DealwarsSeasonService {
    private let baseURL = "https://provikart.cz/api"

    func fetchSeason(token: String?, season: String? = nil, scope: String = "team") async throws -> DealwarsSeasonData {
        guard let token, !token.isEmpty else {
            throw DealwarsSeasonError.notAuthenticated
        }

        var comp = URLComponents(string: "\(baseURL)/game_season.php")
        var queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "scope", value: scope)
        ]
        if let season, !season.isEmpty {
            queryItems.append(URLQueryItem(name: "season", value: season))
        }
        comp?.queryItems = queryItems
        guard let url = comp?.url else {
            throw DealwarsSeasonError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DealwarsSeasonError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            let decoded = try JSONDecoder().decode(DealwarsSeasonResponse.self, from: data)
            guard decoded.success else {
                throw DealwarsSeasonError.serverError(200, decoded.error ?? "API vrátilo success: false")
            }
            guard let payload = decoded.data else {
                throw DealwarsSeasonError.invalidResponse
            }
            return payload
        case 401:
            throw DealwarsSeasonError.notAuthenticated
        default:
            let decoded = try? JSONDecoder().decode(DealwarsSeasonResponse.self, from: data)
            throw DealwarsSeasonError.serverError(http.statusCode, decoded?.error)
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeStringIfPresent(forKeys keys: [Key]) -> String? {
        for key in keys {
            do {
                if let value = try decodeIfPresent(String.self, forKey: key), !value.isEmpty {
                    return value
                }
            } catch {
                continue
            }
        }
        return nil
    }

    func decodeIntIfPresent(forKeys keys: [Key]) -> Int? {
        for key in keys {
            do {
                if let intValue = try decodeIfPresent(Int.self, forKey: key) {
                    return intValue
                }
            } catch {
                // Ignorujeme a zkusíme další variantu.
            }
            do {
                if let stringValue = try decodeIfPresent(String.self, forKey: key), let intValue = Int(stringValue) {
                    return intValue
                }
            } catch {
                continue
            }
        }
        return nil
    }

    func decodeDoubleIfPresent(forKeys keys: [Key]) -> Double? {
        for key in keys {
            do {
                if let doubleValue = try decodeIfPresent(Double.self, forKey: key) {
                    return doubleValue
                }
            } catch {
                // Ignorujeme a zkusíme další variantu.
            }
            do {
                if let intValue = try decodeIfPresent(Int.self, forKey: key) {
                    return Double(intValue)
                }
            } catch {
                // Ignorujeme a zkusíme další variantu.
            }
            do {
                if let stringValue = try decodeIfPresent(String.self, forKey: key) {
                    let normalized = stringValue.replacingOccurrences(of: ",", with: ".")
                    if let doubleValue = Double(normalized) {
                        return doubleValue
                    }
                }
            } catch {
                continue
            }
        }
        return nil
    }

    func decodeArrayIfPresent<T: Decodable>(_ type: T.Type, forKeys keys: [Key]) -> T? {
        for key in keys {
            do {
                if let decoded = try decodeIfPresent(type, forKey: key) {
                    return decoded
                }
            } catch {
                continue
            }
        }
        return nil
    }

    func decodeBoolIfPresent(forKeys keys: [Key]) -> Bool? {
        for key in keys {
            do {
                if let boolValue = try decodeIfPresent(Bool.self, forKey: key) {
                    return boolValue
                }
            } catch {
                // Ignorujeme a zkusíme další variantu.
            }
            do {
                if let intValue = try decodeIfPresent(Int.self, forKey: key) {
                    return intValue != 0
                }
            } catch {
                // Ignorujeme a zkusíme další variantu.
            }
            do {
                if let stringValue = try decodeIfPresent(String.self, forKey: key) {
                    let normalized = stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if ["1", "true", "yes", "ano"].contains(normalized) { return true }
                    if ["0", "false", "no", "ne"].contains(normalized) { return false }
                }
            } catch {
                continue
            }
        }
        return nil
    }
}
