//
//  ManagerAttendanceService.swift
//  Provikart
//
//  Načtení docházky týmu manažera (GET /api/manager_attendance.php).
//

import Foundation

struct ManagerAttendanceEntry: Decodable {
    let status: String
    let note: String?
    let updatedAt: String?
    let updatedBy: Int?
    let isDefault: Bool

    enum CodingKeys: String, CodingKey {
        case status
        case note
        case updatedAt = "updated_at"
        case updatedBy = "updated_by"
        case isDefault = "is_default"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = (try? c.decode(String.self, forKey: .status)) ?? "P"
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        updatedAt = try? c.decodeIfPresent(String.self, forKey: .updatedAt)
        if let intValue = try? c.decodeIfPresent(Int.self, forKey: .updatedBy) {
            updatedBy = intValue
        } else if let stringValue = (try? c.decodeIfPresent(String.self, forKey: .updatedBy)) ?? nil,
                  let intValue = Int(stringValue) {
            updatedBy = intValue
        } else {
            updatedBy = nil
        }
        if let boolValue = try? c.decode(Bool.self, forKey: .isDefault) {
            isDefault = boolValue
        } else if let intValue = try? c.decode(Int.self, forKey: .isDefault) {
            isDefault = (intValue == 1)
        } else if let stringValue = try? c.decode(String.self, forKey: .isDefault) {
            isDefault = ["1", "true", "yes"].contains(stringValue.lowercased())
        } else {
            isDefault = false
        }
    }

    init(status: String, note: String?, updatedAt: String?, updatedBy: Int?, isDefault: Bool) {
        self.status = status
        self.note = note
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
        self.isDefault = isDefault
    }
}

struct ManagerAttendanceUser: Decodable, Identifiable {
    let userId: Int
    let name: String
    let firstname: String?
    let lastname: String?
    let username: String?
    let profileImage: String?
    let attendance: [String: ManagerAttendanceEntry]

    var id: Int { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case firstname
        case lastname
        case username
        case profileImage = "profile_image"
        case attendance
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
        attendance = (try? c.decode([String: ManagerAttendanceEntry].self, forKey: .attendance)) ?? [:]
    }

    init(
        userId: Int,
        name: String,
        firstname: String?,
        lastname: String?,
        username: String?,
        profileImage: String?,
        attendance: [String: ManagerAttendanceEntry]
    ) {
        self.userId = userId
        self.name = name
        self.firstname = firstname
        self.lastname = lastname
        self.username = username
        self.profileImage = profileImage
        self.attendance = attendance
    }
}

private struct ManagerAttendanceResponse: Decodable {
    let success: Bool
    let weekStart: String?
    let month: String?
    let days: [String]
    let users: [ManagerAttendanceUser]
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case weekStart = "week_start"
        case month
        case days
        case users
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
        weekStart = try? c.decodeIfPresent(String.self, forKey: .weekStart)
        month = try? c.decodeIfPresent(String.self, forKey: .month)
        days = (try? c.decode([String].self, forKey: .days)) ?? []
        users = (try? c.decode([ManagerAttendanceUser].self, forKey: .users)) ?? []
        error = try? c.decodeIfPresent(String.self, forKey: .error)
    }
}

struct ManagerAttendancePayload {
    let weekStart: String?
    let month: String?
    let days: [String]
    let users: [ManagerAttendanceUser]
}

enum ManagerAttendanceError: LocalizedError {
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
            return message ?? "Nemáte oprávnění načíst docházku"
        case .serverError(let code, let message):
            return message ?? "Chyba serveru (\(code))"
        }
    }
}

private struct ManagerAttendanceUpdateResponse: Decodable {
    let success: Bool?
    let message: String?
    let error: String?
}

final class ManagerAttendanceService {
    private let baseURL = "https://provikart.cz/api"

    func fetchAttendance(token: String?, month: String, includeSelf: Bool = true) async throws -> ManagerAttendancePayload {
        guard let token, !token.isEmpty else {
            throw ManagerAttendanceError.notAuthenticated
        }

        var comp = URLComponents(string: "\(baseURL)/manager_attendance.php")
        comp?.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "month", value: month),
            URLQueryItem(name: "include_self", value: includeSelf ? "1" : "0"),
            URLQueryItem(name: "_", value: "\(Int(Date().timeIntervalSince1970))")
        ]
        guard let url = comp?.url else {
            throw ManagerAttendanceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ManagerAttendanceError.serverError(-1, "Neplatná odpověď")
        }

        let decoded = try? JSONDecoder().decode(ManagerAttendanceResponse.self, from: data)
        let message = decoded?.error ?? String(data: data, encoding: .utf8)

        switch http.statusCode {
        case 200:
            guard let decoded, decoded.success else {
                throw ManagerAttendanceError.serverError(200, message)
            }
            return ManagerAttendancePayload(
                weekStart: decoded.weekStart,
                month: decoded.month,
                days: decoded.days,
                users: decoded.users
            )
        case 401:
            throw ManagerAttendanceError.notAuthenticated
        case 403:
            throw ManagerAttendanceError.forbidden(message)
        default:
            throw ManagerAttendanceError.serverError(http.statusCode, message)
        }
    }

    /// Uloží změnu docházky manažerem.
    /// PATCH /api/manager_attendance_update.php
    func updateAttendance(token: String?, userId: Int, day: String, status: String, note: String? = nil) async throws {
        guard let token, !token.isEmpty else {
            throw ManagerAttendanceError.notAuthenticated
        }
        guard let url = URL(string: "\(baseURL)/manager_attendance_update.php") else {
            throw ManagerAttendanceError.invalidURL
        }

        var body: [String: Any] = [
            "token": token,
            "user_id": userId,
            "work_date": day,
            "status": status
        ]
        if let note, !note.isEmpty {
            body["note"] = note
        }

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ManagerAttendanceError.serverError(-1, "Neplatná odpověď")
        }

        let decoded = try? JSONDecoder().decode(ManagerAttendanceUpdateResponse.self, from: data)
        let message = decoded?.error ?? decoded?.message ?? String(data: data, encoding: .utf8)

        switch http.statusCode {
        case 200:
            if decoded?.success == true {
                return
            }
            throw ManagerAttendanceError.serverError(200, message)
        case 401:
            throw ManagerAttendanceError.notAuthenticated
        case 403:
            throw ManagerAttendanceError.forbidden(message)
        default:
            throw ManagerAttendanceError.serverError(http.statusCode, message)
        }
    }
}
