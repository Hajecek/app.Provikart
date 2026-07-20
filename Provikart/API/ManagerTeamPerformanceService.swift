//
//  ManagerTeamPerformanceService.swift
//  Provikart
//
//  Výkon týmu manažera (GET /api/manager_performance.php)
//  a ruční zápis / smazání (PATCH /api/manager_performance_update.php).
//

import Foundation

struct ManagerPerformanceBreakdown: Decodable, Equatable {
    var internet: Int
    var postpaid: Int
    var oneplay: Int
    var family: Int
    var transfer: Int

    var total: Int {
        internet + postpaid + oneplay + family + transfer
    }

    enum CodingKeys: String, CodingKey {
        case internet, postpaid, oneplay, family, transfer
    }

    init(
        internet: Int = 0,
        postpaid: Int = 0,
        oneplay: Int = 0,
        family: Int = 0,
        transfer: Int = 0
    ) {
        self.internet = internet
        self.postpaid = postpaid
        self.oneplay = oneplay
        self.family = family
        self.transfer = transfer
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        internet = Self.decodeCount(c, key: .internet)
        postpaid = Self.decodeCount(c, key: .postpaid)
        oneplay = Self.decodeCount(c, key: .oneplay)
        family = Self.decodeCount(c, key: .family)
        transfer = Self.decodeCount(c, key: .transfer)
    }

    private static func decodeCount(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Int {
        if let intValue = try? c.decodeIfPresent(Int.self, forKey: key) {
            return max(0, intValue)
        }
        if let stringValue = try? c.decodeIfPresent(String.self, forKey: key),
           let intValue = Int(stringValue) {
            return max(0, intValue)
        }
        return 0
    }
}

struct ManagerPerformanceDayEntry: Decodable, Equatable {
    let attendanceStatus: String
    let attendanceIsDefault: Bool
    let servicesCount: Int?
    let updatedAt: String?
    let isManual: Bool
    let breakdown: ManagerPerformanceBreakdown?
    let autoBreakdown: ManagerPerformanceBreakdown?

    enum CodingKeys: String, CodingKey {
        case attendanceStatus = "attendance_status"
        case attendanceIsDefault = "attendance_is_default"
        case servicesCount = "services_count"
        case updatedAt = "updated_at"
        case isManual = "is_manual"
        case breakdown
        case autoBreakdown = "auto_breakdown"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        attendanceStatus = (try? c.decode(String.self, forKey: .attendanceStatus)) ?? "P"
        if let boolValue = try? c.decode(Bool.self, forKey: .attendanceIsDefault) {
            attendanceIsDefault = boolValue
        } else if let intValue = try? c.decode(Int.self, forKey: .attendanceIsDefault) {
            attendanceIsDefault = (intValue == 1)
        } else {
            attendanceIsDefault = false
        }
        if let intValue = try? c.decodeIfPresent(Int.self, forKey: .servicesCount) {
            servicesCount = intValue
        } else if let stringValue = try? c.decodeIfPresent(String.self, forKey: .servicesCount),
                  let intValue = Int(stringValue) {
            servicesCount = intValue
        } else {
            servicesCount = nil
        }
        updatedAt = try? c.decodeIfPresent(String.self, forKey: .updatedAt)
        if let boolValue = try? c.decode(Bool.self, forKey: .isManual) {
            isManual = boolValue
        } else if let intValue = try? c.decode(Int.self, forKey: .isManual) {
            isManual = (intValue == 1)
        } else {
            isManual = false
        }
        breakdown = try? c.decodeIfPresent(ManagerPerformanceBreakdown.self, forKey: .breakdown)
        autoBreakdown = try? c.decodeIfPresent(ManagerPerformanceBreakdown.self, forKey: .autoBreakdown)
    }

    init(
        attendanceStatus: String,
        attendanceIsDefault: Bool,
        servicesCount: Int?,
        updatedAt: String?,
        isManual: Bool,
        breakdown: ManagerPerformanceBreakdown?,
        autoBreakdown: ManagerPerformanceBreakdown?
    ) {
        self.attendanceStatus = attendanceStatus
        self.attendanceIsDefault = attendanceIsDefault
        self.servicesCount = servicesCount
        self.updatedAt = updatedAt
        self.isManual = isManual
        self.breakdown = breakdown
        self.autoBreakdown = autoBreakdown
    }
}

struct ManagerPerformanceUser: Decodable, Identifiable, Equatable {
    let userId: Int
    let name: String
    let firstname: String?
    let lastname: String?
    let username: String?
    let profileImage: String?
    let profileImageURL: String?
    let total: Int
    let performance: [String: ManagerPerformanceDayEntry]

    var id: Int { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case firstname
        case lastname
        case username
        case profileImage = "profile_image"
        case profileImageURL = "profile_image_url"
        case total
        case performance
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
        profileImageURL = try? c.decodeIfPresent(String.self, forKey: .profileImageURL)
        if let intValue = try? c.decode(Int.self, forKey: .total) {
            total = intValue
        } else if let stringValue = try? c.decode(String.self, forKey: .total),
                  let intValue = Int(stringValue) {
            total = intValue
        } else {
            total = 0
        }
        performance = (try? c.decode([String: ManagerPerformanceDayEntry].self, forKey: .performance)) ?? [:]
    }

    init(
        userId: Int,
        name: String,
        firstname: String?,
        lastname: String?,
        username: String?,
        profileImage: String?,
        profileImageURL: String?,
        total: Int,
        performance: [String: ManagerPerformanceDayEntry]
    ) {
        self.userId = userId
        self.name = name
        self.firstname = firstname
        self.lastname = lastname
        self.username = username
        self.profileImage = profileImage
        self.profileImageURL = profileImageURL
        self.total = total
        self.performance = performance
    }
}

struct ManagerTeamPerformancePayload {
    let month: String
    let days: [String]
    let users: [ManagerPerformanceUser]
    let todayDate: String
    let todayServicesCount: Int
}

struct ManagerPerformanceUpdateResult {
    let userId: Int
    let workDate: String
    let servicesCount: Int?
    let isManual: Bool
    let breakdown: ManagerPerformanceBreakdown?
    let autoBreakdown: ManagerPerformanceBreakdown?
    let message: String?
}

enum ManagerTeamPerformanceError: LocalizedError {
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
            return message ?? "Nemáte oprávnění k výkonu týmu"
        case .serverError(let code, let message):
            return message ?? "Chyba serveru (\(code))"
        }
    }
}

private struct ManagerTeamPerformanceResponse: Decodable {
    let success: Bool
    let month: String?
    let days: [String]
    let users: [ManagerPerformanceUser]
    let todayDate: String?
    let todayServicesCount: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case month
        case days
        case users
        case todayDate = "today_date"
        case todayServicesCount = "today_services_count"
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
        month = try? c.decodeIfPresent(String.self, forKey: .month)
        days = (try? c.decode([String].self, forKey: .days)) ?? []
        users = (try? c.decode([ManagerPerformanceUser].self, forKey: .users)) ?? []
        todayDate = try? c.decodeIfPresent(String.self, forKey: .todayDate)
        if let intValue = try? c.decodeIfPresent(Int.self, forKey: .todayServicesCount) {
            todayServicesCount = intValue
        } else if let stringValue = try? c.decodeIfPresent(String.self, forKey: .todayServicesCount),
                  let intValue = Int(stringValue) {
            todayServicesCount = intValue
        } else {
            todayServicesCount = nil
        }
        error = try? c.decodeIfPresent(String.self, forKey: .error)
    }
}

private struct ManagerPerformanceUpdateResponse: Decodable {
    let success: Bool?
    let message: String?
    let error: String?
    let userId: Int?
    let workDate: String?
    let servicesCount: Int?
    let isManual: Bool?
    let breakdown: ManagerPerformanceBreakdown?
    let autoBreakdown: ManagerPerformanceBreakdown?

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case error
        case userId = "user_id"
        case workDate = "work_date"
        case servicesCount = "services_count"
        case isManual = "is_manual"
        case breakdown
        case autoBreakdown = "auto_breakdown"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let boolValue = try? c.decodeIfPresent(Bool.self, forKey: .success) {
            success = boolValue
        } else if let intValue = try? c.decodeIfPresent(Int.self, forKey: .success) {
            success = (intValue == 1)
        } else {
            success = nil
        }
        message = try? c.decodeIfPresent(String.self, forKey: .message)
        error = try? c.decodeIfPresent(String.self, forKey: .error)
        if let intValue = try? c.decodeIfPresent(Int.self, forKey: .userId) {
            userId = intValue
        } else if let stringValue = try? c.decodeIfPresent(String.self, forKey: .userId),
                  let intValue = Int(stringValue) {
            userId = intValue
        } else {
            userId = nil
        }
        workDate = try? c.decodeIfPresent(String.self, forKey: .workDate)
        if let intValue = try? c.decodeIfPresent(Int.self, forKey: .servicesCount) {
            servicesCount = intValue
        } else if let stringValue = try? c.decodeIfPresent(String.self, forKey: .servicesCount),
                  let intValue = Int(stringValue) {
            servicesCount = intValue
        } else {
            servicesCount = nil
        }
        if let boolValue = try? c.decodeIfPresent(Bool.self, forKey: .isManual) {
            isManual = boolValue
        } else if let intValue = try? c.decodeIfPresent(Int.self, forKey: .isManual) {
            isManual = (intValue == 1)
        } else {
            isManual = nil
        }
        breakdown = try? c.decodeIfPresent(ManagerPerformanceBreakdown.self, forKey: .breakdown)
        autoBreakdown = try? c.decodeIfPresent(ManagerPerformanceBreakdown.self, forKey: .autoBreakdown)
    }
}

final class ManagerTeamPerformanceService {
    private let baseURL = "https://provikart.cz/api"

    func fetchPerformance(token: String?, month: String) async throws -> ManagerTeamPerformancePayload {
        guard let token, !token.isEmpty else {
            throw ManagerTeamPerformanceError.notAuthenticated
        }

        var comp = URLComponents(string: "\(baseURL)/manager_performance.php")
        comp?.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "month", value: month),
            URLQueryItem(name: "_", value: "\(Int(Date().timeIntervalSince1970))")
        ]
        guard let url = comp?.url else {
            throw ManagerTeamPerformanceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ManagerTeamPerformanceError.serverError(-1, "Neplatná odpověď")
        }

        let decoded = try? JSONDecoder().decode(ManagerTeamPerformanceResponse.self, from: data)
        let message = decoded?.error ?? String(data: data, encoding: .utf8)

        switch http.statusCode {
        case 200:
            guard let decoded, decoded.success else {
                throw ManagerTeamPerformanceError.serverError(200, message)
            }
            return ManagerTeamPerformancePayload(
                month: decoded.month ?? month,
                days: decoded.days,
                users: decoded.users,
                todayDate: decoded.todayDate ?? "",
                todayServicesCount: decoded.todayServicesCount ?? 0
            )
        case 401:
            throw ManagerTeamPerformanceError.notAuthenticated
        case 403:
            throw ManagerTeamPerformanceError.forbidden(message)
        default:
            throw ManagerTeamPerformanceError.serverError(http.statusCode, message)
        }
    }

    /// Uloží ruční výkon (breakdown) nebo smaže přepis (`clear: true`).
    func updatePerformance(
        token: String?,
        userId: Int,
        workDate: String,
        breakdown: ManagerPerformanceBreakdown?,
        clear: Bool
    ) async throws -> ManagerPerformanceUpdateResult {
        guard let token, !token.isEmpty else {
            throw ManagerTeamPerformanceError.notAuthenticated
        }
        guard let url = URL(string: "\(baseURL)/manager_performance_update.php") else {
            throw ManagerTeamPerformanceError.invalidURL
        }

        var body: [String: Any] = [
            "token": token,
            "user_id": userId,
            "work_date": workDate
        ]

        if clear {
            body["clear"] = true
        } else if let breakdown {
            body["cnt_internet"] = breakdown.internet
            body["cnt_postpaid"] = breakdown.postpaid
            body["cnt_oneplay"] = breakdown.oneplay
            body["cnt_family"] = breakdown.family
            body["cnt_transfer"] = breakdown.transfer
        } else {
            throw ManagerTeamPerformanceError.serverError(400, "Chybí breakdown nebo clear.")
        }

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ManagerTeamPerformanceError.serverError(-1, "Neplatná odpověď")
        }

        let decoded = try? JSONDecoder().decode(ManagerPerformanceUpdateResponse.self, from: data)
        let message = decoded?.error ?? decoded?.message ?? String(data: data, encoding: .utf8)

        switch http.statusCode {
        case 200:
            guard decoded?.success == true else {
                throw ManagerTeamPerformanceError.serverError(200, message)
            }
            return ManagerPerformanceUpdateResult(
                userId: decoded?.userId ?? userId,
                workDate: decoded?.workDate ?? workDate,
                servicesCount: decoded?.servicesCount,
                isManual: decoded?.isManual ?? !clear,
                breakdown: decoded?.breakdown,
                autoBreakdown: decoded?.autoBreakdown,
                message: decoded?.message
            )
        case 401:
            throw ManagerTeamPerformanceError.notAuthenticated
        case 403:
            throw ManagerTeamPerformanceError.forbidden(message)
        default:
            throw ManagerTeamPerformanceError.serverError(http.statusCode, message)
        }
    }
}
