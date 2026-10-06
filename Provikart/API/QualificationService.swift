//
//  QualificationService.swift
//  Provikart
//

import Foundation

struct QualificationBar: Decodable, Identifiable, Equatable {
    var id: String { key }
    let key: String
    let label: String
    let current: Int
    let target: Int
    let met: Bool
    let hint: String
    let percent: Int

    enum CodingKeys: String, CodingKey {
        case key, label, current, target, met, hint, percent
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = (try? c.decode(String.self, forKey: .key)) ?? UUID().uuidString
        label = (try? c.decode(String.self, forKey: .label)) ?? ""
        current = c.decodeFlexibleInt(forKey: .current)
        target = c.decodeFlexibleInt(forKey: .target)
        met = c.decodeFlexibleBool(forKey: .met)
        hint = (try? c.decode(String.self, forKey: .hint)) ?? ""
        percent = c.decodeFlexibleInt(forKey: .percent)
    }
}

struct QualificationGap: Decodable, Equatable, Identifiable {
    var id: String { address }
    let address: String
}

struct QualificationProgress: Decodable, Equatable {
    let status: String
    let qualified: Bool
    let startedOn: String
    let startedLabel: String
    let percent: Int
    let message: String
    let bars: [QualificationBar]
    let visible: Bool
    let modelaceMet: Bool
    let modelaceNote: String
    let localityUnfilled: Int
    let localityGaps: [QualificationGap]

    enum CodingKeys: String, CodingKey {
        case status, qualified, percent, message, bars, visible
        case startedOn = "started_on"
        case startedLabel = "started_label"
        case modelaceMet = "modelace_met"
        case modelaceNote = "modelace_note"
        case localityUnfilled = "locality_unfilled"
        case localityGaps = "locality_gaps"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = (try? c.decode(String.self, forKey: .status)) ?? "active"
        startedOn = (try? c.decode(String.self, forKey: .startedOn)) ?? ""
        startedLabel = (try? c.decode(String.self, forKey: .startedLabel)) ?? ""
        message = (try? c.decode(String.self, forKey: .message)) ?? ""
        let decodedBars = (try? c.decode([QualificationBar].self, forKey: .bars)) ?? []
        bars = decodedBars.filter { $0.key != "performance" }
        let summary = Self.summary(for: bars)
        percent = summary.percent
        qualified = summary.qualified
        visible = c.contains(.visible) ? c.decodeFlexibleBool(forKey: .visible) : true
        modelaceMet = c.contains(.modelaceMet) ? c.decodeFlexibleBool(forKey: .modelaceMet) : false
        modelaceNote = (try? c.decode(String.self, forKey: .modelaceNote)) ?? ""
        localityUnfilled = c.contains(.localityUnfilled) ? c.decodeFlexibleInt(forKey: .localityUnfilled) : 0
        localityGaps = (try? c.decode([QualificationGap].self, forKey: .localityGaps)) ?? []
    }

    private static func summary(for bars: [QualificationBar]) -> (percent: Int, qualified: Bool) {
        guard !bars.isEmpty else { return (0, false) }
        let allMet = bars.allSatisfy(\.met)
        if allMet { return (100, true) }
        let average = Int((Double(bars.reduce(0) { $0 + $1.percent }) / Double(bars.count)).rounded())
        return (min(99, average), false)
    }
}

enum QualificationError: Error {
    case invalidURL
    case notAuthenticated
    case serverError(Int, String?)
}

final class QualificationService {
    private let baseURL = "https://provikart.cz/api"

    func fetchProgress(token: String?) async throws -> QualificationProgress {
        guard let token, !token.isEmpty else { throw QualificationError.notAuthenticated }

        var comp = URLComponents(string: "\(baseURL)/user_qualification.php")
        comp?.queryItems = [
            URLQueryItem(name: "_", value: "\(Int(Date().timeIntervalSince1970))")
        ]
        guard let url = comp?.url else { throw QualificationError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.authAwareData(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw QualificationError.serverError(-1, "Neplatná odpověď")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw QualificationError.notAuthenticated
        }
        guard http.statusCode == 200 else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw QualificationError.serverError(http.statusCode, message)
        }

        let payload = try JSONDecoder().decode(QualificationEnvelope.self, from: data)
        guard payload.success else {
            throw QualificationError.serverError(200, "Kvalifikaci se nepodařilo načíst")
        }
        return payload.progress
    }
}

private struct QualificationEnvelope: Decodable {
    let success: Bool
    let progress: QualificationProgress

    enum CodingKeys: String, CodingKey {
        case success, status, qualified, percent, message, bars
        case startedOn = "started_on"
        case startedLabel = "started_label"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = c.decodeFlexibleBool(forKey: .success)
        progress = try QualificationProgress(from: decoder)
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleInt(forKey key: Key) -> Int {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(Double.self, forKey: key) { return Int(value) }
        if let value = try? decode(String.self, forKey: key) { return Int(value) ?? 0 }
        return 0
    }

    func decodeFlexibleBool(forKey key: Key) -> Bool {
        if let value = try? decode(Bool.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return value != 0 }
        if let value = try? decode(String.self, forKey: key) {
            return value == "1" || value.lowercased() == "true"
        }
        return false
    }
}
