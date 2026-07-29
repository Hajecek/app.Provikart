//
//  UserSalesLocalitiesService.swift
//  Provikart
//
//  Přiřazené prodejní lokality obchodníka
//  GET  /api/user_sales_localities.php
//  PATCH/POST /api/user_sales_locality_update.php
//

import Foundation

// MARK: - Modely

struct SalesLocalityItem: Decodable, Identifiable, Equatable {
    let id: Int
    let ropId: String?
    let ruian: String?
    let ulice: String?
    let cisloPopisne: String?
    let cisloOrientacni: String?
    let obec: String?
    let okres: String?
    let castObce: String?
    let majitel: String?
    let puvodce: String?
    let email: String?
    let telefon: String?
    let note: String?
    let hp: Int
    let fiberKs: Int
    let openedCount: Int
    let d2d: Bool
    let isDone: Bool
    let openedPct: Double?
    let penetrationPct: Double?
    let salesUserId: Int?
    let managerUserId: Int?
    let managerName: String?
    let salesName: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ropId = "rop_id"
        case ruian
        case ulice, obec, okres
        case castObce = "cast_obce"
        case cisloPopisne = "cislo_popisne"
        case cisloDomovni = "cislo_domovni"
        case cisloOrientacni = "cislo_orientacni"
        case popisneCislo = "popisne_cislo"
        case orientacniCislo = "orientacni_cislo"
        case cisloP = "cislo_p"
        case cisloO = "cislo_o"
        case cp, co
        case cP = "c_p"
        case cO = "c_o"
        case cislo
        case houseNumber = "house_number"
        case majitel, puvodce, email, telefon, note
        case hp
        case fiberKs = "fiber_ks"
        case openedCount = "opened_count"
        case d2d
        case isDone = "is_done"
        case openedPct = "opened_pct"
        case penetrationPct = "penetration_pct"
        case salesUserId = "sales_user_id"
        case managerUserId = "manager_user_id"
        case managerName = "manager_name"
        case salesName = "sales_name"
        case managerFirstname = "manager_firstname"
        case managerLastname = "manager_lastname"
        case salesFirstname = "sales_firstname"
        case salesLastname = "sales_lastname"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeRequiredFlexibleInt(forKey: .id)
        ropId = c.decodeFlexibleString(forKey: .ropId)
        ruian = c.decodeFlexibleString(forKey: .ruian)
        ulice = c.decodeFlexibleString(forKey: .ulice)
        obec = c.decodeFlexibleString(forKey: .obec)
        okres = c.decodeFlexibleString(forKey: .okres)
        castObce = c.decodeFlexibleString(forKey: .castObce)
        majitel = c.decodeFlexibleString(forKey: .majitel)
        puvodce = c.decodeFlexibleString(forKey: .puvodce)
        email = c.decodeFlexibleString(forKey: .email)
        telefon = c.decodeFlexibleString(forKey: .telefon)
        note = c.decodeFlexibleString(forKey: .note)
        hp = c.decodeFlexibleInt(forKey: .hp) ?? 0
        fiberKs = c.decodeFlexibleInt(forKey: .fiberKs) ?? 0
        openedCount = c.decodeFlexibleInt(forKey: .openedCount) ?? 0
        d2d = c.decodeFlexibleBool(forKey: .d2d)
        isDone = c.decodeFlexibleBool(forKey: .isDone)
        openedPct = c.decodeFlexibleDouble(forKey: .openedPct)
        penetrationPct = c.decodeFlexibleDouble(forKey: .penetrationPct)
        salesUserId = c.decodeFlexibleInt(forKey: .salesUserId)
        managerUserId = c.decodeFlexibleInt(forKey: .managerUserId)
        updatedAt = c.decodeFlexibleString(forKey: .updatedAt)

        let rawPopisne = c.firstFlexibleString(forKeys: [
            .cisloPopisne, .cisloDomovni, .popisneCislo, .cisloP, .cp, .cP, .houseNumber
        ])
        let rawOrientacni = c.firstFlexibleString(forKeys: [
            .cisloOrientacni, .orientacniCislo, .cisloO, .co, .cO
        ])
        let combined = c.decodeFlexibleString(forKey: .cislo)
        let split = Self.splitHouseNumber(combined)

        cisloPopisne = rawPopisne ?? split.popisne
        cisloOrientacni = rawOrientacni ?? split.orientacni

        if let name = c.decodeFlexibleString(forKey: .managerName), !name.isEmpty {
            managerName = name
        } else {
            managerName = Self.joinedName(
                c.decodeFlexibleString(forKey: .managerFirstname),
                c.decodeFlexibleString(forKey: .managerLastname)
            )
        }

        if let name = c.decodeFlexibleString(forKey: .salesName), !name.isEmpty {
            salesName = name
        } else {
            salesName = Self.joinedName(
                c.decodeFlexibleString(forKey: .salesFirstname),
                c.decodeFlexibleString(forKey: .salesLastname)
            )
        }
    }

    /// Č.p. / č.o. ve formátu `12` nebo `12/3`.
    var houseNumberLabel: String? {
        let popisne = cisloPopisne?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let orientacni = cisloOrientacni?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !popisne.isEmpty && !orientacni.isEmpty { return "\(popisne)/\(orientacni)" }
        if !popisne.isEmpty { return popisne }
        if !orientacni.isEmpty { return orientacni }
        return nil
    }

    /// Ulice + čísla + obec pro seznam.
    var addressTitle: String {
        let street = ulice?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let city = obec?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let number = houseNumberLabel ?? ""

        let streetWithNumber: String = {
            if !street.isEmpty && !number.isEmpty { return "\(street) \(number)" }
            if !street.isEmpty { return street }
            if !number.isEmpty { return "č. \(number)" }
            return ""
        }()

        if !streetWithNumber.isEmpty && !city.isEmpty { return "\(streetWithNumber), \(city)" }
        if !streetWithNumber.isEmpty { return streetWithNumber }
        if !city.isEmpty { return city }
        if let cast = castObce?.trimmingCharacters(in: .whitespacesAndNewlines), !cast.isEmpty {
            return cast
        }
        return "Lokalita #\(id)"
    }

    var addressSubtitle: String? {
        var parts: [String] = []
        if let popisne = cisloPopisne?.trimmingCharacters(in: .whitespacesAndNewlines), !popisne.isEmpty {
            parts.append("č.p. \(popisne)")
        }
        if let orientacni = cisloOrientacni?.trimmingCharacters(in: .whitespacesAndNewlines), !orientacni.isEmpty {
            parts.append("č.o. \(orientacni)")
        }
        if let cast = castObce?.trimmingCharacters(in: .whitespacesAndNewlines), !cast.isEmpty,
           cast.caseInsensitiveCompare(obec ?? "") != .orderedSame {
            parts.append(cast)
        }
        if let okres = okres?.trimmingCharacters(in: .whitespacesAndNewlines), !okres.isEmpty {
            parts.append(okres)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Otevřené dveře / HP (0…1).
    var openedProgress: Double {
        guard hp > 0 else { return 0 }
        return min(1, max(0, Double(openedCount) / Double(hp)))
    }

    /// Fiber / HP (0…1).
    var fiberProgress: Double {
        guard hp > 0 else { return 0 }
        return min(1, max(0, Double(fiberKs) / Double(hp)))
    }

    var computedOpenedPct: Double {
        if let openedPct { return openedPct }
        guard hp > 0 else { return 0 }
        return round(Double(openedCount) / Double(hp) * 1000) / 10
    }

    var computedPenetrationPct: Double {
        if let penetrationPct { return penetrationPct }
        guard hp > 0 else { return 0 }
        return round(Double(min(fiberKs, openedCount)) / Double(hp) * 1000) / 10
    }

    private static func joinedName(_ first: String?, _ last: String?) -> String? {
        let parts = [first, last]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private static func splitHouseNumber(_ raw: String?) -> (popisne: String?, orientacni: String?) {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return (nil, nil)
        }
        let separators = CharacterSet(charactersIn: "/\\")
        let parts = raw.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.count >= 2 {
            return (parts[0], parts[1])
        }
        return (parts.first, nil)
    }
}

struct SalesLocalityStats: Decodable, Equatable {
    let total: Int
    let hp: Int
    let fiberKs: Int
    let opened: Int
    let penetrationPct: Double
    let openedPct: Double
    let done: Int
    let open: Int
    let assignedSales: Int
    let unassignedSales: Int

    enum CodingKeys: String, CodingKey {
        case total, hp, opened, done, open
        case fiberKs = "fiber_ks"
        case penetrationPct = "penetration_pct"
        case openedPct = "opened_pct"
        case assignedSales = "assigned_sales"
        case unassignedSales = "unassigned_sales"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = c.decodeFlexibleInt(forKey: .total) ?? 0
        hp = c.decodeFlexibleInt(forKey: .hp) ?? 0
        fiberKs = c.decodeFlexibleInt(forKey: .fiberKs) ?? 0
        opened = c.decodeFlexibleInt(forKey: .opened) ?? 0
        done = c.decodeFlexibleInt(forKey: .done) ?? 0
        open = c.decodeFlexibleInt(forKey: .open) ?? 0
        penetrationPct = c.decodeFlexibleDouble(forKey: .penetrationPct) ?? 0
        openedPct = c.decodeFlexibleDouble(forKey: .openedPct) ?? 0
        assignedSales = c.decodeFlexibleInt(forKey: .assignedSales) ?? 0
        unassignedSales = c.decodeFlexibleInt(forKey: .unassignedSales) ?? 0
    }

    static let empty = SalesLocalityStats(
        total: 0, hp: 0, fiberKs: 0, opened: 0,
        penetrationPct: 0, openedPct: 0, done: 0, open: 0,
        assignedSales: 0, unassignedSales: 0
    )

    init(
        total: Int,
        hp: Int,
        fiberKs: Int,
        opened: Int,
        penetrationPct: Double,
        openedPct: Double,
        done: Int,
        open: Int,
        assignedSales: Int = 0,
        unassignedSales: Int = 0
    ) {
        self.total = total
        self.hp = hp
        self.fiberKs = fiberKs
        self.opened = opened
        self.penetrationPct = penetrationPct
        self.openedPct = openedPct
        self.done = done
        self.open = open
        self.assignedSales = assignedSales
        self.unassignedSales = unassignedSales
    }
}

struct SalesLocalityPagination: Decodable, Equatable {
    let page: Int
    let pageSize: Int
    let total: Int
    let totalPages: Int

    enum CodingKeys: String, CodingKey {
        case page, total
        case pageSize = "page_size"
        case totalPages = "total_pages"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        page = c.decodeFlexibleInt(forKey: .page) ?? 1
        pageSize = c.decodeFlexibleInt(forKey: .pageSize) ?? 50
        total = c.decodeFlexibleInt(forKey: .total) ?? 0
        totalPages = c.decodeFlexibleInt(forKey: .totalPages) ?? 1
    }

    init(page: Int, pageSize: Int, total: Int, totalPages: Int) {
        self.page = page
        self.pageSize = pageSize
        self.total = total
        self.totalPages = totalPages
    }
}

struct SalesLocalityListResult {
    let items: [SalesLocalityItem]
    let count: Int
    let pagination: SalesLocalityPagination
    let stats: SalesLocalityStats
    let editableFields: [String]
}

struct SalesLocalityUpdateFields {
    var fiberKs: Int?
    var openedCount: Int?
    var isDone: Bool?
    var note: String?
    var majitel: String?
    var email: String?
    var telefon: String?
    var d2d: Bool?
    var hp: Int?
    /// `nil` = neposílat; `0` = odebrat obchodníka; `>0` = přiřadit.
    var salesUserId: Int?

    var asDictionary: [String: Any] {
        var body: [String: Any] = [:]
        if let fiberKs { body["fiber_ks"] = fiberKs }
        if let openedCount { body["opened_count"] = openedCount }
        if let isDone { body["is_done"] = isDone ? 1 : 0 }
        if let note { body["note"] = note }
        if let majitel { body["majitel"] = majitel }
        if let email { body["email"] = email }
        if let telefon { body["telefon"] = telefon }
        if let d2d { body["d2d"] = d2d ? 1 : 0 }
        if let hp { body["hp"] = hp }
        if let salesUserId {
            body["sales_user_id"] = salesUserId > 0 ? salesUserId : NSNull()
        }
        return body
    }

    var hasChanges: Bool { !asDictionary.isEmpty }
}

// MARK: - Odpovědi

private struct SalesLocalityListResponse: Decodable {
    let success: Bool
    let items: [SalesLocalityItem]
    let count: Int?
    let pagination: SalesLocalityPagination?
    let stats: SalesLocalityStats?
    let editableFields: [String]
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, items, count, pagination, stats, error
        case editableFields = "editable_fields"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = c.decodeFlexibleBool(forKey: .success)
        items = (try? c.decode([SalesLocalityItem].self, forKey: .items)) ?? []
        count = c.decodeFlexibleInt(forKey: .count)
        pagination = try? c.decodeIfPresent(SalesLocalityPagination.self, forKey: .pagination)
        stats = try? c.decodeIfPresent(SalesLocalityStats.self, forKey: .stats)
        editableFields = (try? c.decode([String].self, forKey: .editableFields)) ?? []
        error = try? c.decodeIfPresent(String.self, forKey: .error)
    }
}

private struct SalesLocalityUpdateResponse: Decodable {
    let success: Bool
    let message: String?
    let item: SalesLocalityItem?
    let editableFields: [String]
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, message, item, error
        case editableFields = "editable_fields"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = c.decodeFlexibleBool(forKey: .success)
        message = try? c.decodeIfPresent(String.self, forKey: .message)
        item = try? c.decodeIfPresent(SalesLocalityItem.self, forKey: .item)
        editableFields = (try? c.decode([String].self, forKey: .editableFields)) ?? []
        error = try? c.decodeIfPresent(String.self, forKey: .error)
    }
}

// MARK: - Chyby

enum UserSalesLocalitiesError: LocalizedError {
    case invalidURL
    case notAuthenticated
    case forbidden(String?)
    case validation(String)
    case notFound(String?)
    case serverError(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Neplatná adresa API"
        case .notAuthenticated:
            return "Nejste přihlášeni"
        case .forbidden(let message):
            let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty,
               !["forbidden", "403", "access denied"].contains(trimmed.lowercased()) {
                return trimmed
            }
            return "Nemáte oprávnění upravit tuto lokalitu."
        case .validation(let message):
            return message
        case .notFound(let message):
            return message ?? "Lokalita nenalezena"
        case .serverError(let code, let message):
            return message ?? "Chyba serveru (\(code))"
        }
    }
}

// MARK: - Service

final class UserSalesLocalitiesService {
    private let baseURL = "https://provikart.cz/api"

    struct ListQuery {
        var q: String? = nil
        var okres: String? = nil
        var obec: String? = nil
        var done: Bool? = nil
        var page: Int = 1
        var limit: Int = 50
    }

    func fetchLocalities(token: String?, query: ListQuery = ListQuery()) async throws -> SalesLocalityListResult {
        guard let token, !token.isEmpty else {
            throw UserSalesLocalitiesError.notAuthenticated
        }

        var items: [URLQueryItem] = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "page", value: "\(max(1, query.page))"),
            URLQueryItem(name: "limit", value: "\(min(100, max(1, query.limit)))"),
            URLQueryItem(name: "_", value: "\(Int(Date().timeIntervalSince1970))")
        ]

        if let q = query.q?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
            items.append(URLQueryItem(name: "q", value: q))
        }
        if let okres = query.okres?.trimmingCharacters(in: .whitespacesAndNewlines), !okres.isEmpty {
            items.append(URLQueryItem(name: "okres", value: okres))
        }
        if let obec = query.obec?.trimmingCharacters(in: .whitespacesAndNewlines), !obec.isEmpty {
            items.append(URLQueryItem(name: "obec", value: obec))
        }
        if let done = query.done {
            items.append(URLQueryItem(name: "done", value: done ? "1" : "0"))
        }

        var comp = URLComponents(string: "\(baseURL)/user_sales_localities.php")
        comp?.queryItems = items
        guard let url = comp?.url else {
            throw UserSalesLocalitiesError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.authAwareData(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UserSalesLocalitiesError.serverError(-1, "Neplatná odpověď")
        }

        let decoded = try? JSONDecoder().decode(SalesLocalityListResponse.self, from: data)
        let message = decoded?.error ?? String(data: data, encoding: .utf8)

        switch http.statusCode {
        case 200:
            guard let decoded, decoded.success else {
                throw UserSalesLocalitiesError.serverError(200, message)
            }
            let pagination = decoded.pagination
                ?? SalesLocalityPagination(
                    page: query.page,
                    pageSize: query.limit,
                    total: decoded.count ?? decoded.items.count,
                    totalPages: 1
                )
            return SalesLocalityListResult(
                items: decoded.items,
                count: decoded.count ?? decoded.items.count,
                pagination: pagination,
                stats: decoded.stats ?? .empty,
                editableFields: decoded.editableFields
            )
        case 401:
            throw UserSalesLocalitiesError.notAuthenticated
        case 403:
            throw UserSalesLocalitiesError.forbidden(message)
        default:
            throw UserSalesLocalitiesError.serverError(http.statusCode, message)
        }
    }

    func updateLocality(
        token: String?,
        id: Int,
        fields: SalesLocalityUpdateFields
    ) async throws -> (item: SalesLocalityItem, editableFields: [String]) {
        guard let token, !token.isEmpty else {
            throw UserSalesLocalitiesError.notAuthenticated
        }
        guard fields.hasChanges else {
            throw UserSalesLocalitiesError.validation("Žádné změny k uložení.")
        }

        // Stejně jako u GET: token i v query – Authorization header Apache často nepropustí do PHP.
        var comp = URLComponents(string: "\(baseURL)/user_sales_locality_update.php")
        comp?.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "id", value: "\(id)")
        ]
        guard let url = comp?.url else {
            throw UserSalesLocalitiesError.invalidURL
        }

        var body = fields.asDictionary
        body["id"] = id
        body["token"] = token

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: url)
        // POST je v API povolený a spolehlivější než PATCH u některých proxy/WAF.
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(token, forHTTPHeaderField: "X-Auth-Token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.authAwareData(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UserSalesLocalitiesError.serverError(-1, "Neplatná odpověď")
        }

        let decoded = try? JSONDecoder().decode(SalesLocalityUpdateResponse.self, from: data)
        let rawBody = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let message = decoded?.error ?? decoded?.message ?? rawBody

        switch http.statusCode {
        case 200:
            guard let decoded, decoded.success, let item = decoded.item else {
                throw UserSalesLocalitiesError.serverError(200, message)
            }
            return (item, decoded.editableFields)
        case 400:
            throw UserSalesLocalitiesError.validation(message ?? "Neplatné vstupní údaje.")
        case 401:
            throw UserSalesLocalitiesError.notAuthenticated
        case 403:
            throw UserSalesLocalitiesError.forbidden(message)
        case 404:
            throw UserSalesLocalitiesError.notFound(message)
        default:
            throw UserSalesLocalitiesError.serverError(http.statusCode, message)
        }
    }
}

// MARK: - Flexibilní dekódování

private extension KeyedDecodingContainer {
    func hasNonNilValue(forKey key: Key) -> Bool {
        guard contains(key) else { return false }
        return (try? decodeNil(forKey: key)) != true
    }

    func decodeRequiredFlexibleInt(forKey key: Key) throws -> Int {
        if let i = try? decode(Int.self, forKey: key) { return i }
        if let d = try? decode(Double.self, forKey: key) { return Int(d) }
        if let s = try? decode(String.self, forKey: key) {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if let i = Int(trimmed) { return i }
            if let d = Double(trimmed.replacingOccurrences(of: ",", with: ".")) { return Int(d) }
        }
        throw DecodingError.typeMismatch(
            Int.self,
            .init(codingPath: codingPath + [key], debugDescription: "Očekáváno Int")
        )
    }

    func decodeFlexibleInt(forKey key: Key) -> Int? {
        guard hasNonNilValue(forKey: key) else { return nil }
        return try? decodeRequiredFlexibleInt(forKey: key)
    }

    func decodeFlexibleDouble(forKey key: Key) -> Double? {
        guard hasNonNilValue(forKey: key) else { return nil }
        if let d = try? decode(Double.self, forKey: key) { return d }
        if let i = try? decode(Int.self, forKey: key) { return Double(i) }
        if let s = try? decode(String.self, forKey: key) {
            return Double(s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }

    func decodeFlexibleString(forKey key: Key) -> String? {
        guard hasNonNilValue(forKey: key) else { return nil }
        if let s = try? decode(String.self, forKey: key) {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let i = try? decode(Int.self, forKey: key) { return String(i) }
        if let d = try? decode(Double.self, forKey: key) {
            return d.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(d)) : String(d)
        }
        return nil
    }

    func firstFlexibleString(forKeys keys: [Key]) -> String? {
        for key in keys {
            if let value = decodeFlexibleString(forKey: key) {
                return value
            }
        }
        return nil
    }

    func decodeFlexibleBool(forKey key: Key) -> Bool {
        guard hasNonNilValue(forKey: key) else { return false }
        if let b = try? decode(Bool.self, forKey: key) { return b }
        if let i = try? decode(Int.self, forKey: key) { return i != 0 }
        if let s = try? decode(String.self, forKey: key) {
            let v = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ["1", "true", "yes", "ano", "y"].contains(v)
        }
        return false
    }
}
