//
//  ManagerSalesLocalitiesService.swift
//  Provikart
//
//  Prodejní lokality manažera
//  GET    /api/manager_sales_localities.php
//  POST   /api/manager_sales_locality_update.php
//  POST   /api/manager_sales_locality_assign.php
//

import Foundation

// MARK: - Facety / oprávnění

struct ManagerSalesLocalityFacets: Decodable, Equatable {
    let total: Int
    let unassignedSales: Int
    let assignedSales: Int
    let done: Int
    let open: Int

    enum CodingKeys: String, CodingKey {
        case total, done, open
        case unassignedSales = "unassigned_sales"
        case assignedSales = "assigned_sales"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = c.decodeFlexibleInt(forKey: .total) ?? 0
        unassignedSales = c.decodeFlexibleInt(forKey: .unassignedSales) ?? 0
        assignedSales = c.decodeFlexibleInt(forKey: .assignedSales) ?? 0
        done = c.decodeFlexibleInt(forKey: .done) ?? 0
        open = c.decodeFlexibleInt(forKey: .open) ?? 0
    }

    static let empty = ManagerSalesLocalityFacets(
        total: 0, unassignedSales: 0, assignedSales: 0, done: 0, open: 0
    )

    init(total: Int, unassignedSales: Int, assignedSales: Int, done: Int, open: Int) {
        self.total = total
        self.unassignedSales = unassignedSales
        self.assignedSales = assignedSales
        self.done = done
        self.open = open
    }
}

struct ManagerSalesLocalityPermissions: Decodable, Equatable {
    let canAssignSales: Bool
    let canDelete: Bool

    enum CodingKeys: String, CodingKey {
        case canAssignSales = "can_assign_sales"
        case canDelete = "can_delete"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        canAssignSales = c.decodeFlexibleBool(forKey: .canAssignSales)
        canDelete = c.decodeFlexibleBool(forKey: .canDelete)
    }

    static let `default` = ManagerSalesLocalityPermissions(canAssignSales: true, canDelete: false)

    init(canAssignSales: Bool, canDelete: Bool) {
        self.canAssignSales = canAssignSales
        self.canDelete = canDelete
    }
}

struct ManagerSalesLocalityListResult {
    let items: [SalesLocalityItem]
    let count: Int
    let pagination: SalesLocalityPagination
    let stats: SalesLocalityStats
    let facets: ManagerSalesLocalityFacets
    let editableFields: [String]
    let permissions: ManagerSalesLocalityPermissions
}

struct ManagerSalesLocalityAssignResult {
    let updated: Int
    let errors: [String]
    let message: String?
    let salesUserId: Int?
}

// MARK: - Odpovědi

private struct ManagerSalesLocalityListResponse: Decodable {
    let success: Bool
    let items: [SalesLocalityItem]
    let count: Int?
    let pagination: SalesLocalityPagination?
    let stats: SalesLocalityStats?
    let facets: ManagerSalesLocalityFacets?
    let editableFields: [String]
    let permissions: ManagerSalesLocalityPermissions?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, items, count, pagination, stats, facets, error, permissions
        case editableFields = "editable_fields"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = c.decodeFlexibleBool(forKey: .success)
        items = (try? c.decode([SalesLocalityItem].self, forKey: .items)) ?? []
        count = c.decodeFlexibleInt(forKey: .count)
        pagination = try? c.decodeIfPresent(SalesLocalityPagination.self, forKey: .pagination)
        stats = try? c.decodeIfPresent(SalesLocalityStats.self, forKey: .stats)
        facets = try? c.decodeIfPresent(ManagerSalesLocalityFacets.self, forKey: .facets)
        editableFields = (try? c.decode([String].self, forKey: .editableFields)) ?? []
        permissions = try? c.decodeIfPresent(ManagerSalesLocalityPermissions.self, forKey: .permissions)
        error = try? c.decodeIfPresent(String.self, forKey: .error)
    }
}

private struct ManagerSalesLocalityUpdateResponse: Decodable {
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

private struct ManagerSalesLocalityAssignResponse: Decodable {
    let success: Bool
    let updated: Int?
    let errors: [String]
    let message: String?
    let salesUserId: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, updated, errors, message, error
        case salesUserId = "sales_user_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = c.decodeFlexibleBool(forKey: .success)
        updated = c.decodeFlexibleInt(forKey: .updated)
        errors = (try? c.decode([String].self, forKey: .errors)) ?? []
        message = try? c.decodeIfPresent(String.self, forKey: .message)
        salesUserId = c.decodeFlexibleInt(forKey: .salesUserId)
        error = try? c.decodeIfPresent(String.self, forKey: .error)
    }
}

// MARK: - Chyby

enum ManagerSalesLocalitiesError: LocalizedError {
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
            return "Nemáte oprávnění k této akci."
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

final class ManagerSalesLocalitiesService {
    private let baseURL = "https://provikart.cz/api"

    enum AssignmentFilter: Equatable {
        case all
        case unassigned
        case assigned
    }

    struct ListQuery {
        var q: String? = nil
        var okres: String? = nil
        var obec: String? = nil
        var done: Bool? = nil
        var assignment: AssignmentFilter = .all
        var salesId: Int? = nil
        var page: Int = 1
        var limit: Int = 50
    }

    func fetchLocalities(token: String?, query: ListQuery = ListQuery()) async throws -> ManagerSalesLocalityListResult {
        guard let token, !token.isEmpty else {
            throw ManagerSalesLocalitiesError.notAuthenticated
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
        if let salesId = query.salesId, salesId > 0 {
            items.append(URLQueryItem(name: "sales_id", value: "\(salesId)"))
        } else {
            switch query.assignment {
            case .all:
                break
            case .unassigned:
                items.append(URLQueryItem(name: "unassigned", value: "sales"))
            case .assigned:
                items.append(URLQueryItem(name: "unassigned", value: "assigned_sales"))
            }
        }

        var comp = URLComponents(string: "\(baseURL)/manager_sales_localities.php")
        comp?.queryItems = items
        guard let url = comp?.url else {
            throw ManagerSalesLocalitiesError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.authAwareData(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ManagerSalesLocalitiesError.serverError(-1, "Neplatná odpověď")
        }

        let decoded = try? JSONDecoder().decode(ManagerSalesLocalityListResponse.self, from: data)
        let message = decoded?.error ?? String(data: data, encoding: .utf8)

        switch http.statusCode {
        case 200:
            guard let decoded, decoded.success else {
                throw ManagerSalesLocalitiesError.serverError(200, message)
            }
            let pagination = decoded.pagination
                ?? SalesLocalityPagination(
                    page: query.page,
                    pageSize: query.limit,
                    total: decoded.count ?? decoded.items.count,
                    totalPages: 1
                )
            return ManagerSalesLocalityListResult(
                items: decoded.items,
                count: decoded.count ?? decoded.items.count,
                pagination: pagination,
                stats: decoded.stats ?? .empty,
                facets: decoded.facets ?? .empty,
                editableFields: decoded.editableFields,
                permissions: decoded.permissions ?? .default
            )
        case 401:
            throw ManagerSalesLocalitiesError.notAuthenticated
        case 403:
            throw ManagerSalesLocalitiesError.forbidden(message)
        default:
            throw ManagerSalesLocalitiesError.serverError(http.statusCode, message)
        }
    }

    func updateLocality(
        token: String?,
        id: Int,
        fields: SalesLocalityUpdateFields
    ) async throws -> (item: SalesLocalityItem, editableFields: [String]) {
        guard let token, !token.isEmpty else {
            throw ManagerSalesLocalitiesError.notAuthenticated
        }
        guard fields.hasChanges else {
            throw ManagerSalesLocalitiesError.validation("Žádné změny k uložení.")
        }

        var comp = URLComponents(string: "\(baseURL)/manager_sales_locality_update.php")
        comp?.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "id", value: "\(id)")
        ]
        guard let url = comp?.url else {
            throw ManagerSalesLocalitiesError.invalidURL
        }

        var body = fields.asDictionary
        body["id"] = id
        body["token"] = token

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(token, forHTTPHeaderField: "X-Auth-Token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.authAwareData(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ManagerSalesLocalitiesError.serverError(-1, "Neplatná odpověď")
        }

        let decoded = try? JSONDecoder().decode(ManagerSalesLocalityUpdateResponse.self, from: data)
        let rawBody = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let message = decoded?.error ?? decoded?.message ?? rawBody

        switch http.statusCode {
        case 200:
            guard let decoded, decoded.success, let item = decoded.item else {
                throw ManagerSalesLocalitiesError.serverError(200, message)
            }
            return (item, decoded.editableFields)
        case 400:
            throw ManagerSalesLocalitiesError.validation(message ?? "Neplatné vstupní údaje.")
        case 401:
            throw ManagerSalesLocalitiesError.notAuthenticated
        case 403:
            throw ManagerSalesLocalitiesError.forbidden(message)
        case 404:
            throw ManagerSalesLocalitiesError.notFound(message)
        default:
            throw ManagerSalesLocalitiesError.serverError(http.statusCode, message)
        }
    }

    func assignSales(
        token: String?,
        localityIds: [Int],
        salesUserId: Int?
    ) async throws -> ManagerSalesLocalityAssignResult {
        guard let token, !token.isEmpty else {
            throw ManagerSalesLocalitiesError.notAuthenticated
        }
        let ids = Array(Set(localityIds.filter { $0 > 0 }))
        guard !ids.isEmpty else {
            throw ManagerSalesLocalitiesError.validation("Chybí locality_ids.")
        }

        var comp = URLComponents(string: "\(baseURL)/manager_sales_locality_assign.php")
        comp?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = comp?.url else {
            throw ManagerSalesLocalitiesError.invalidURL
        }

        let targetId = max(0, salesUserId ?? 0)
        let body: [String: Any] = [
            "token": token,
            "locality_ids": ids,
            "sales_user_id": targetId > 0 ? targetId : NSNull()
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(token, forHTTPHeaderField: "X-Auth-Token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.authAwareData(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ManagerSalesLocalitiesError.serverError(-1, "Neplatná odpověď")
        }

        let decoded = try? JSONDecoder().decode(ManagerSalesLocalityAssignResponse.self, from: data)
        let rawBody = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let message = decoded?.error ?? decoded?.message ?? rawBody

        switch http.statusCode {
        case 200:
            guard let decoded, decoded.success else {
                throw ManagerSalesLocalitiesError.serverError(200, message)
            }
            return ManagerSalesLocalityAssignResult(
                updated: decoded.updated ?? 0,
                errors: decoded.errors,
                message: decoded.message ?? message,
                salesUserId: decoded.salesUserId
            )
        case 400:
            throw ManagerSalesLocalitiesError.validation(message ?? "Neplatné vstupní údaje.")
        case 401:
            throw ManagerSalesLocalitiesError.notAuthenticated
        case 403:
            throw ManagerSalesLocalitiesError.forbidden(message)
        default:
            throw ManagerSalesLocalitiesError.serverError(http.statusCode, message)
        }
    }
}

// MARK: - Flexibilní dekódování (lokální kopie pro tento soubor)

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
