//
//  ManagerOverviewService.swift
//  Provikart
//
//  Manažerský přehled – GET /api/manager_overview.php
//

import Foundation

enum ManagerOverviewPeriod: String, CaseIterable, Identifiable {
    case today
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Dnes"
        case .week: return "Týden"
        case .month: return "Měsíc"
        }
    }
}

struct ManagerOverviewKPI: Decodable, Identifiable, Equatable {
    var id: String { key }
    let key: String
    let label: String
    let value: String
    let delta: String
    let up: Bool?
    let tone: String

    enum CodingKeys: String, CodingKey {
        case key, label, value, delta, up, tone
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = (try? c.decode(String.self, forKey: .key)) ?? UUID().uuidString
        label = (try? c.decode(String.self, forKey: .label)) ?? ""
        value = (try? c.decode(String.self, forKey: .value)) ?? "—"
        delta = (try? c.decode(String.self, forKey: .delta)) ?? "—"
        up = c.decodeFlexibleOptionalBool(forKey: .up)
        tone = (try? c.decode(String.self, forKey: .tone)) ?? "blue"
    }
}

struct ManagerOverviewActivity: Decodable, Identifiable, Equatable {
    var id: String { label }
    let label: String
    let value: String
    let delta: String
    let up: Bool?

    enum CodingKeys: String, CodingKey {
        case label, value, delta, up
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = (try? c.decode(String.self, forKey: .label)) ?? ""
        value = (try? c.decode(String.self, forKey: .value)) ?? "—"
        delta = (try? c.decode(String.self, forKey: .delta)) ?? "—"
        up = c.decodeFlexibleOptionalBool(forKey: .up)
    }
}

struct ManagerOverviewPerson: Decodable, Identifiable, Equatable {
    let id: Int
    let name: String
    let initials: String
    let avatar: String
    let commission: String
    let commissionRaw: Double
    let services: Int
    let planLabel: String
    let conversion: String

    enum CodingKeys: String, CodingKey {
        case id, name, initials, avatar, commission, services, conversion
        case commissionRaw = "commission_raw"
        case planLabel = "plan_label"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeFlexibleInt(forKey: .id) ?? 0
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        initials = (try? c.decode(String.self, forKey: .initials)) ?? "?"
        avatar = (try? c.decode(String.self, forKey: .avatar)) ?? ""
        commission = (try? c.decode(String.self, forKey: .commission)) ?? "0 Kč"
        commissionRaw = c.decodeFlexibleDouble(forKey: .commissionRaw) ?? 0
        services = c.decodeFlexibleInt(forKey: .services) ?? 0
        planLabel = (try? c.decode(String.self, forKey: .planLabel)) ?? "—"
        conversion = (try? c.decode(String.self, forKey: .conversion)) ?? "—"
    }

    var avatarURL: URL? {
        let raw = avatar.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
    }
}

struct ManagerOverviewLeader: Decodable, Identifiable, Equatable {
    let place: Int
    let id: Int
    let name: String
    let initials: String
    let avatar: String
    let amount: String
    let xp: Int

    enum CodingKeys: String, CodingKey {
        case place, id, name, initials, avatar, amount, xp
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        place = c.decodeFlexibleInt(forKey: .place) ?? 0
        id = c.decodeFlexibleInt(forKey: .id) ?? 0
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        initials = (try? c.decode(String.self, forKey: .initials)) ?? "?"
        avatar = (try? c.decode(String.self, forKey: .avatar)) ?? ""
        amount = (try? c.decode(String.self, forKey: .amount)) ?? "0 XP"
        xp = c.decodeFlexibleInt(forKey: .xp) ?? 0
    }

    var avatarURL: URL? {
        let raw = avatar.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
    }
}

struct ManagerOverviewServiceSlice: Decodable, Identifiable, Equatable {
    var id: String { key }
    let key: String
    let label: String
    let count: Int
    let pct: Int
    let color: String
    let delta: String
    let deltaUp: Bool?

    enum CodingKeys: String, CodingKey {
        case key, label, count, pct, color, delta
        case deltaUp = "delta_up"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = (try? c.decode(String.self, forKey: .key)) ?? UUID().uuidString
        label = (try? c.decode(String.self, forKey: .label)) ?? ""
        count = c.decodeFlexibleInt(forKey: .count) ?? 0
        pct = c.decodeFlexibleInt(forKey: .pct) ?? 0
        color = (try? c.decode(String.self, forKey: .color)) ?? "#007AFF"
        delta = (try? c.decode(String.self, forKey: .delta)) ?? "—"
        deltaUp = c.decodeFlexibleOptionalBool(forKey: .deltaUp)
    }
}

struct ManagerOverviewRiskPerson: Decodable, Identifiable, Equatable {
    let id: Int
    let name: String
    let initials: String
    let avatar: String
    let reason: String
    let detail: String
    let metric: String
    let level: String

    enum CodingKeys: String, CodingKey {
        case id, name, initials, avatar, reason, detail, metric, level
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeFlexibleInt(forKey: .id) ?? 0
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        initials = (try? c.decode(String.self, forKey: .initials)) ?? "?"
        avatar = (try? c.decode(String.self, forKey: .avatar)) ?? ""
        reason = (try? c.decode(String.self, forKey: .reason)) ?? ""
        detail = (try? c.decode(String.self, forKey: .detail)) ?? ""
        metric = (try? c.decode(String.self, forKey: .metric)) ?? ""
        level = (try? c.decode(String.self, forKey: .level)) ?? "warn"
    }

    var avatarURL: URL? {
        let raw = avatar.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
    }
}

struct ManagerOverviewAlert: Decodable, Identifiable, Equatable {
    let id: String
    let tone: String
    let title: String
    let text: String
    let action: String
    let actionLabel: String

    enum CodingKeys: String, CodingKey {
        case id, tone, title, text, action
        case actionLabel = "action_label"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        tone = (try? c.decode(String.self, forKey: .tone)) ?? "warn"
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        action = (try? c.decode(String.self, forKey: .action)) ?? "home"
        actionLabel = (try? c.decode(String.self, forKey: .actionLabel)) ?? "Otevřít"
    }
}

struct ManagerOverviewLocalities: Decodable, Equatable {
    let available: Bool
    let total: Int
    let assigned: Int
    let unassigned: Int
    let done: Int
    let open: Int
    let receivedToday: Int
    let assignPct: Int

    enum CodingKeys: String, CodingKey {
        case available, total, assigned, unassigned, done, open
        case receivedToday = "received_today"
        case assignPct = "assign_pct"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        available = c.decodeFlexibleOptionalBool(forKey: .available) ?? false
        total = c.decodeFlexibleInt(forKey: .total) ?? 0
        assigned = c.decodeFlexibleInt(forKey: .assigned) ?? 0
        unassigned = c.decodeFlexibleInt(forKey: .unassigned) ?? 0
        done = c.decodeFlexibleInt(forKey: .done) ?? 0
        open = c.decodeFlexibleInt(forKey: .open) ?? 0
        receivedToday = c.decodeFlexibleInt(forKey: .receivedToday) ?? 0
        assignPct = c.decodeFlexibleInt(forKey: .assignPct) ?? 0
    }

    static let empty = ManagerOverviewLocalities(
        available: false, total: 0, assigned: 0, unassigned: 0,
        done: 0, open: 0, receivedToday: 0, assignPct: 0
    )

    init(available: Bool, total: Int, assigned: Int, unassigned: Int, done: Int, open: Int, receivedToday: Int, assignPct: Int) {
        self.available = available
        self.total = total
        self.assigned = assigned
        self.unassigned = unassigned
        self.done = done
        self.open = open
        self.receivedToday = receivedToday
        self.assignPct = assignPct
    }
}

struct ManagerOverviewSummary: Decodable, Equatable {
    let totalCommission: String
    let commissionDelta: String
    let commissionDeltaUp: Bool?
    let monthPrediction: String
    let monthEarnedLabel: String
    let bestName: String
    let bestAvatar: String
    let planPct: Int?
    let salespersonCount: Int
    let monthName: String
    let teamGoalLabel: String
    let hasGoal: Bool

    enum CodingKeys: String, CodingKey {
        case totalCommission = "total_commission"
        case commissionDelta = "commission_delta"
        case commissionDeltaUp = "commission_delta_up"
        case monthPrediction = "month_prediction"
        case monthEarnedLabel = "month_earned_label"
        case bestName = "best_name"
        case bestAvatar = "best_avatar"
        case planPct = "plan_pct"
        case salespersonCount = "salesperson_count"
        case monthName = "month_name"
        case teamGoalLabel = "team_goal_label"
        case hasGoal = "has_goal"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalCommission = (try? c.decode(String.self, forKey: .totalCommission)) ?? "0 Kč"
        commissionDelta = (try? c.decode(String.self, forKey: .commissionDelta)) ?? "—"
        commissionDeltaUp = c.decodeFlexibleOptionalBool(forKey: .commissionDeltaUp)
        monthPrediction = (try? c.decode(String.self, forKey: .monthPrediction)) ?? "—"
        monthEarnedLabel = (try? c.decode(String.self, forKey: .monthEarnedLabel)) ?? "0 Kč"
        bestName = (try? c.decode(String.self, forKey: .bestName)) ?? "—"
        bestAvatar = (try? c.decode(String.self, forKey: .bestAvatar)) ?? ""
        planPct = c.decodeFlexibleInt(forKey: .planPct)
        salespersonCount = c.decodeFlexibleInt(forKey: .salespersonCount) ?? 0
        monthName = (try? c.decode(String.self, forKey: .monthName)) ?? ""
        teamGoalLabel = (try? c.decode(String.self, forKey: .teamGoalLabel)) ?? "Nenastaven"
        hasGoal = c.decodeFlexibleOptionalBool(forKey: .hasGoal) ?? false
    }
}

struct ManagerOverviewServicesMeta: Decodable, Equatable {
    let total: Int
    let delta: String
    let deltaUp: Bool?
    let monthTotal: Int
    let monthName: String

    enum CodingKeys: String, CodingKey {
        case total, delta
        case deltaUp = "delta_up"
        case monthTotal = "month_total"
        case monthName = "month_name"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = c.decodeFlexibleInt(forKey: .total) ?? 0
        delta = (try? c.decode(String.self, forKey: .delta)) ?? "—"
        deltaUp = c.decodeFlexibleOptionalBool(forKey: .deltaUp)
        monthTotal = c.decodeFlexibleInt(forKey: .monthTotal) ?? 0
        monthName = (try? c.decode(String.self, forKey: .monthName)) ?? ""
    }
}

struct ManagerOverviewPayload: Decodable {
    let memberCount: Int
    let kpis: [ManagerOverviewKPI]
    let activities: [ManagerOverviewActivity]
    let salespeople: [ManagerOverviewPerson]
    let leaderboard: [ManagerOverviewLeader]
    let riskPeople: [ManagerOverviewRiskPerson]
    let localities: ManagerOverviewLocalities
    let summary: ManagerOverviewSummary?
    let servicesBreakdown: [ManagerOverviewServiceSlice]
    let servicesMeta: ManagerOverviewServicesMeta?
    let alerts: [ManagerOverviewAlert]
    let tasksDueTodayCount: Int

    enum CodingKeys: String, CodingKey {
        case memberCount = "member_count"
        case kpis, activities, salespeople, leaderboard, localities, summary, alerts
        case riskPeople = "risk_people"
        case servicesBreakdown = "services_breakdown"
        case servicesMeta = "services_meta"
        case tasksDueTodayCount = "tasks_due_today_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        memberCount = c.decodeFlexibleInt(forKey: .memberCount) ?? 0
        kpis = (try? c.decode([ManagerOverviewKPI].self, forKey: .kpis)) ?? []
        activities = (try? c.decode([ManagerOverviewActivity].self, forKey: .activities)) ?? []
        salespeople = (try? c.decode([ManagerOverviewPerson].self, forKey: .salespeople)) ?? []
        leaderboard = (try? c.decode([ManagerOverviewLeader].self, forKey: .leaderboard)) ?? []
        riskPeople = (try? c.decode([ManagerOverviewRiskPerson].self, forKey: .riskPeople)) ?? []
        localities = (try? c.decode(ManagerOverviewLocalities.self, forKey: .localities)) ?? .empty
        summary = try? c.decodeIfPresent(ManagerOverviewSummary.self, forKey: .summary)
        servicesBreakdown = (try? c.decode([ManagerOverviewServiceSlice].self, forKey: .servicesBreakdown)) ?? []
        servicesMeta = try? c.decodeIfPresent(ManagerOverviewServicesMeta.self, forKey: .servicesMeta)
        alerts = (try? c.decode([ManagerOverviewAlert].self, forKey: .alerts)) ?? []
        tasksDueTodayCount = c.decodeFlexibleInt(forKey: .tasksDueTodayCount) ?? 0
    }
}

struct ManagerOverviewPeriodInfo: Decodable {
    let key: String
    let label: String
}

struct ManagerOverviewResponse: Decodable {
    let success: Bool
    let period: ManagerOverviewPeriodInfo?
    let data: ManagerOverviewPayload?
}

enum ManagerOverviewError: LocalizedError {
    case invalidURL
    case notAuthenticated
    case serverError(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Neplatná URL"
        case .notAuthenticated: return "Nejste přihlášeni."
        case .serverError(_, let body): return body ?? "Nepodařilo se načíst přehled."
        }
    }
}

final class ManagerOverviewService {
    private let baseURL = "https://provikart.cz/api"

    func fetchOverview(token: String?, period: ManagerOverviewPeriod) async throws -> (ManagerOverviewPayload, String) {
        guard let token, !token.isEmpty else { throw ManagerOverviewError.notAuthenticated }

        var comp = URLComponents(string: "\(baseURL)/manager_overview.php")
        comp?.queryItems = [
            URLQueryItem(name: "period", value: period.rawValue),
            URLQueryItem(name: "_", value: "\(Int(Date().timeIntervalSince1970))")
        ]
        guard let url = comp?.url else { throw ManagerOverviewError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(token, forHTTPHeaderField: "X-Auth-Token")

        let (data, response) = try await URLSession.shared.authAwareData(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ManagerOverviewError.serverError(-1, "Neplatná odpověď")
        }

        switch http.statusCode {
        case 200:
            let decoded = try JSONDecoder().decode(ManagerOverviewResponse.self, from: data)
            guard decoded.success, let payload = decoded.data else {
                throw ManagerOverviewError.serverError(200, "Přehled se nepodařilo načíst.")
            }
            return (payload, decoded.period?.label ?? period.title)
        case 401, 403:
            throw ManagerOverviewError.notAuthenticated
        default:
            let body = String(data: data, encoding: .utf8)
            throw ManagerOverviewError.serverError(http.statusCode, body)
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleInt(forKey key: Key) -> Int? {
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Double.self, forKey: key) { return Int(v) }
        if let s = try? decodeIfPresent(String.self, forKey: key), let v = Int(s) { return v }
        return nil
    }

    func decodeFlexibleDouble(forKey key: Key) -> Double? {
        if let v = try? decodeIfPresent(Double.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return Double(v) }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            let normalized = s.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")
            if let v = Double(normalized) { return v }
        }
        return nil
    }

    func decodeFlexibleOptionalBool(forKey key: Key) -> Bool? {
        if let v = try? decodeIfPresent(Bool.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return v != 0 }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            let l = s.lowercased()
            if ["1", "true", "yes"].contains(l) { return true }
            if ["0", "false", "no"].contains(l) { return false }
        }
        return nil
    }
}
