//
//  NationalManagerService.swift
//  Provikart
//
//  API národního manažera (stejná data jako web /admin/dashboard, /admin/locations,
//  /admin/incomplete-orders):
//  GET /api/manager_sales_localities.php    – všechny prodejní lokality + KPI, filtr manažera
//  GET /api/manager_locations.php           – nahlášené lokality týmu vybraného manažera
//  GET /api/national_incomplete_orders.php  – kontrola nedokončených objednávek
//

import Foundation

// MARK: - Modely

struct NationalManagerOption: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let team: String?
    let profileImage: String?

    enum CodingKeys: String, CodingKey {
        case id, name, team
        case profileImage = "profile_image"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.nmInt(.id) ?? 0
        name = c.nmString(.name) ?? ""
        team = c.nmString(.team)
        profileImage = c.nmString(.profileImage)
    }
}

/// KPI jako horní karty na webu (HP / Fiber / Penetrace / Otevřeno).
struct NationalLocalityStats: Decodable, Equatable {
    var total = 0
    var hp = 0
    var hpClosed = 0
    var hpNotTradable = 0
    var hpCounted = 0
    var fiberKs = 0
    var opened = 0
    var penetrationPct = 0.0
    var openedPct = 0.0
    var done = 0
    var open = 0
    var assignedManager = 0
    var unassignedManager = 0

    enum CodingKeys: String, CodingKey {
        case total, hp, opened, done, open
        case hpClosed = "hp_closed"
        case hpNotTradable = "hp_not_tradable"
        case hpCounted = "hp_counted"
        case fiberKs = "fiber_ks"
        case penetrationPct = "penetration_pct"
        case openedPct = "opened_pct"
        case assignedManager = "assigned_manager"
        case unassignedManager = "unassigned_manager"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = c.nmInt(.total) ?? 0
        hp = c.nmInt(.hp) ?? 0
        hpClosed = c.nmInt(.hpClosed) ?? 0
        hpNotTradable = c.nmInt(.hpNotTradable) ?? 0
        hpCounted = c.nmInt(.hpCounted) ?? 0
        fiberKs = c.nmInt(.fiberKs) ?? 0
        opened = c.nmInt(.opened) ?? 0
        penetrationPct = c.nmDouble(.penetrationPct) ?? 0
        openedPct = c.nmDouble(.openedPct) ?? 0
        done = c.nmInt(.done) ?? 0
        open = c.nmInt(.open) ?? 0
        assignedManager = c.nmInt(.assignedManager) ?? 0
        unassignedManager = c.nmInt(.unassignedManager) ?? 0
    }
}

struct NationalLocalityFacets: Decodable, Equatable {
    var total = 0
    var done = 0
    var open = 0
    var deferred = 0
    var assignedManager = 0
    var unassignedManager = 0
    /// Počet zavřených lokalit – jen pokud ho API posílá.
    var closed: Int?

    enum CodingKeys: String, CodingKey {
        case total, done, open, deferred, closed
        case assignedManager = "assigned_manager"
        case unassignedManager = "unassigned_manager"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = c.nmInt(.total) ?? 0
        done = c.nmInt(.done) ?? 0
        open = c.nmInt(.open) ?? 0
        deferred = c.nmInt(.deferred) ?? 0
        closed = c.nmInt(.closed)
        assignedManager = c.nmInt(.assignedManager) ?? 0
        unassignedManager = c.nmInt(.unassignedManager) ?? 0
    }
}

struct NationalLocalitiesResult {
    let items: [SalesLocalityItem]
    let pagination: SalesLocalityPagination?
    let stats: NationalLocalityStats
    let facets: NationalLocalityFacets
    let managers: [NationalManagerOption]
}

private struct NationalLocalitiesResponse: Decodable {
    let success: Bool
    let items: [SalesLocalityItem]
    let pagination: SalesLocalityPagination?
    let stats: NationalLocalityStats?
    let facets: NationalLocalityFacets?
    let managers: [NationalManagerOption]
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, items, pagination, stats, facets, managers, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = c.nmBool(.success)
        items = (try? c.decode([SalesLocalityItem].self, forKey: .items)) ?? []
        pagination = try? c.decodeIfPresent(SalesLocalityPagination.self, forKey: .pagination)
        stats = try? c.decodeIfPresent(NationalLocalityStats.self, forKey: .stats)
        facets = try? c.decodeIfPresent(NationalLocalityFacets.self, forKey: .facets)
        managers = (try? c.decode([NationalManagerOption].self, forKey: .managers)) ?? []
        error = c.nmString(.error)
    }
}

/// Člen týmu a jeho nahlášená lokalita (národní manažer vidí jen „Nahlášeno“, ne název).
struct NationalLocationMember: Decodable, Identifiable, Hashable {
    let userId: Int
    let name: String
    let profileImage: String?
    let teamName: String

    var id: Int { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name, username
        case profileImage = "profile_image"
        case teamName = "team_name"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = c.nmInt(.userId) ?? 0
        let n = c.nmString(.name) ?? ""
        name = n.isEmpty ? (c.nmString(.username) ?? "#\(userId)") : n
        profileImage = c.nmString(.profileImage)
        teamName = c.nmString(.teamName) ?? ""
    }
}

struct NationalLocationEntry: Decodable, Hashable {
    let userId: Int
    let workDate: String
    let locationName: String
    let arrivalTime: String?
    let note: String?
    let attendanceStatus: String?
    let isAbsent: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case workDate = "work_date"
        case locationName = "location_name"
        case arrivalTime = "arrival_time"
        case note
        case attendanceStatus = "attendance_status"
        case isAbsent = "is_absent"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = c.nmInt(.userId) ?? 0
        workDate = c.nmString(.workDate) ?? ""
        locationName = c.nmString(.locationName) ?? ""
        arrivalTime = c.nmString(.arrivalTime)
        note = c.nmString(.note)
        attendanceStatus = c.nmString(.attendanceStatus)
        isAbsent = c.nmBool(.isAbsent)
    }
}

struct NationalLocationsResult {
    let managers: [NationalManagerOption]
    let selectedManagerId: Int?
    let members: [NationalLocationMember]
    let entries: [NationalLocationEntry]
}

private struct NationalLocationsResponse: Decodable {
    let success: Bool
    let managers: [NationalManagerOption]
    let selectedManagerId: Int?
    let members: [NationalLocationMember]
    let items: [NationalLocationEntry]
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, managers, members, items, error
        case selectedManagerId = "selected_manager_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = c.nmBool(.success)
        managers = (try? c.decode([NationalManagerOption].self, forKey: .managers)) ?? []
        selectedManagerId = c.nmInt(.selectedManagerId)
        members = (try? c.decode([NationalLocationMember].self, forKey: .members)) ?? []
        items = (try? c.decode([NationalLocationEntry].self, forKey: .items)) ?? []
        error = c.nmString(.error)
    }
}

struct NationalOrderStatement: Decodable, Hashable {
    let text: String
    let createdAt: String
    let authorName: String
    let kind: String

    enum CodingKeys: String, CodingKey {
        case text, kind
        case createdAt = "created_at"
        case authorName = "author_name"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = c.nmString(.text) ?? ""
        createdAt = c.nmString(.createdAt) ?? ""
        authorName = c.nmString(.authorName) ?? ""
        kind = c.nmString(.kind) ?? "Vývoj"
    }
}

struct NationalIncompleteOrder: Decodable, Identifiable, Hashable {
    enum Status: String {
        case created, open, completed

        var label: String {
            switch self {
            case .created: return "Vytvořeno"
            case .open: return "Otevřeno"
            case .completed: return "Dokončeno"
            }
        }
    }

    let id: Int
    let orderNumber: String
    let note: String
    let statusRaw: String
    let createdAt: String
    let manager: String
    let sales: String
    let team: String
    let serviceKind: String
    let statements: [NationalOrderStatement]

    var status: Status { Status(rawValue: statusRaw) ?? .created }

    enum CodingKeys: String, CodingKey {
        case id, note, manager, sales, team, statements
        case orderNumber = "order_number"
        case statusRaw = "status"
        case createdAt = "created_at"
        case serviceKind = "service_kind"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.nmInt(.id) ?? 0
        orderNumber = c.nmString(.orderNumber) ?? ""
        note = c.nmString(.note) ?? ""
        statusRaw = c.nmString(.statusRaw) ?? "created"
        createdAt = c.nmString(.createdAt) ?? ""
        manager = c.nmString(.manager) ?? ""
        sales = c.nmString(.sales) ?? ""
        team = c.nmString(.team) ?? ""
        serviceKind = c.nmString(.serviceKind) ?? "other"
        statements = (try? c.decode([NationalOrderStatement].self, forKey: .statements)) ?? []
    }
}

private struct NationalIncompleteOrdersResponse: Decodable {
    let success: Bool
    let items: [NationalIncompleteOrder]
    let error: String?

    enum CodingKeys: String, CodingKey { case success, items, error }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = c.nmBool(.success)
        items = (try? c.decode([NationalIncompleteOrder].self, forKey: .items)) ?? []
        error = c.nmString(.error)
    }
}

enum NationalManagerError: LocalizedError {
    case notAuthenticated
    case forbidden(String?)
    case server(Int, String?)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Nejste přihlášeni"
        case .forbidden(let m): return m ?? "Nemáte oprávnění"
        case .server(let code, let m):
            if let m, !m.isEmpty, !m.lowercased().contains("<html") { return m }
            return "Chyba serveru (\(code))"
        }
    }
}

// MARK: - Service

final class NationalManagerService {
    private let baseURL = "https://provikart.cz/api"

    enum ManagerAssignment: Equatable {
        case all
        case unassigned
        case assigned
    }

    struct LocalitiesQuery: Equatable {
        var q: String = ""
        var managerId: Int? = nil
        var assignment: ManagerAssignment = .all
        var done: Bool? = nil
        var kind: String? = nil
        var page: Int = 1
        var limit: Int = 50
    }

    func fetchLocalities(token: String?, query: LocalitiesQuery) async throws -> NationalLocalitiesResult {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "\(max(1, query.page))"),
            URLQueryItem(name: "limit", value: "\(min(100, max(1, query.limit)))"),
        ]
        let q = query.q.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { items.append(URLQueryItem(name: "q", value: q)) }
        if let managerId = query.managerId, managerId > 0 {
            items.append(URLQueryItem(name: "manager_id", value: "\(managerId)"))
        } else {
            switch query.assignment {
            case .all: break
            case .unassigned: items.append(URLQueryItem(name: "unassigned", value: "manager"))
            case .assigned: items.append(URLQueryItem(name: "unassigned", value: "assigned_manager"))
            }
        }
        if let done = query.done { items.append(URLQueryItem(name: "done", value: done ? "1" : "0")) }
        if let kind = query.kind, !kind.isEmpty { items.append(URLQueryItem(name: "kind", value: kind)) }

        let data = try await get("manager_sales_localities.php", token: token, query: items)
        let decoded = try JSONDecoder().decode(NationalLocalitiesResponse.self, from: data)
        guard decoded.success else { throw NationalManagerError.server(200, decoded.error) }
        return NationalLocalitiesResult(
            items: decoded.items,
            pagination: decoded.pagination,
            stats: decoded.stats ?? NationalLocalityStats(),
            facets: decoded.facets ?? NationalLocalityFacets(),
            managers: decoded.managers
        )
    }

    func fetchLocations(token: String?, managerId: Int?, workDate: String) async throws -> NationalLocationsResult {
        var items = [URLQueryItem(name: "work_date", value: workDate)]
        if let managerId, managerId > 0 {
            items.append(URLQueryItem(name: "manager_id", value: "\(managerId)"))
        }
        let data = try await get("manager_locations.php", token: token, query: items)
        let decoded = try JSONDecoder().decode(NationalLocationsResponse.self, from: data)
        guard decoded.success else { throw NationalManagerError.server(200, decoded.error) }
        return NationalLocationsResult(
            managers: decoded.managers,
            selectedManagerId: decoded.selectedManagerId,
            members: decoded.members,
            entries: decoded.items
        )
    }

    func fetchIncompleteOrders(token: String?) async throws -> [NationalIncompleteOrder] {
        let data = try await get("national_incomplete_orders.php", token: token, query: [])
        let decoded = try JSONDecoder().decode(NationalIncompleteOrdersResponse.self, from: data)
        guard decoded.success else { throw NationalManagerError.server(200, decoded.error) }
        return decoded.items
    }

    private func get(_ path: String, token: String?, query: [URLQueryItem]) async throws -> Data {
        guard let token, !token.isEmpty else { throw NationalManagerError.notAuthenticated }
        var comp = URLComponents(string: "\(baseURL)/\(path)")
        comp?.queryItems = query + [URLQueryItem(name: "_", value: "\(Int(Date().timeIntervalSince1970))")]
        guard let url = comp?.url else { throw NationalManagerError.server(-1, "Neplatná adresa API") }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.authAwareData(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        switch status {
        case 200:
            return data
        case 401:
            throw NationalManagerError.notAuthenticated
        case 403:
            throw NationalManagerError.forbidden(Self.errorMessage(data))
        default:
            throw NationalManagerError.server(status, Self.errorMessage(data))
        }
    }

    private static func errorMessage(_ data: Data) -> String? {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = obj["error"] as? String {
            return message
        }
        return nil
    }
}

// MARK: - Tolerantní dekódování (lokální pro tento soubor)

private extension KeyedDecodingContainer {
    func nmInt(_ key: Key) -> Int? {
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Double.self, forKey: key) { return Int(v) }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    func nmDouble(_ key: Key) -> Double? {
        if let v = try? decodeIfPresent(Double.self, forKey: key) { return v }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            return Double(s.replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }

    func nmString(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return String(v) }
        return nil
    }

    func nmBool(_ key: Key) -> Bool {
        if let v = try? decodeIfPresent(Bool.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return v != 0 }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            return ["1", "true", "yes"].contains(s.lowercased())
        }
        return false
    }
}
