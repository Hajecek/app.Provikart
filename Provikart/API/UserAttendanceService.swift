//
//  UserAttendanceService.swift
//  Provikart
//
//  Vlastní docházka uživatele (GET/POST/PATCH na user_attendance endpointy).
//

import Foundation

struct UserAttendanceEntry: Decodable {
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

struct UserAttendanceUser: Decodable {
    let userId: Int
    let name: String
    let firstname: String?
    let lastname: String?
    let username: String?
    let profileImage: String?
    let attendance: [String: UserAttendanceEntry]

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
        attendance = (try? c.decode([String: UserAttendanceEntry].self, forKey: .attendance)) ?? [:]
    }

    init(
        userId: Int,
        name: String,
        firstname: String?,
        lastname: String?,
        username: String?,
        profileImage: String?,
        attendance: [String: UserAttendanceEntry]
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

struct UserAttendancePayload {
    let weekStart: String?
    let month: String?
    let days: [String]
    let user: UserAttendanceUser
}

enum UserAttendanceError: LocalizedError {
    case invalidURL
    case notAuthenticated
    case serverError(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Neplatná adresa API"
        case .notAuthenticated:
            return "Nejste přihlášeni"
        case .serverError(let code, let message):
            return message ?? "Chyba serveru (\(code))"
        }
    }
}

private struct UserAttendanceResponse: Decodable {
    let success: Bool
    let weekStart: String?
    let month: String?
    let days: [String]
    let user: UserAttendanceUser?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case weekStart = "week_start"
        case month
        case days
        case user
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
        user = try? c.decodeIfPresent(UserAttendanceUser.self, forKey: .user)
        error = try? c.decodeIfPresent(String.self, forKey: .error)
    }
}

private struct UserAttendanceUpdateResponse: Decodable {
    struct Attendance: Decodable {
        let status: String?
        let note: String?
        let updatedAt: String?
        let updatedBy: Int?

        enum CodingKeys: String, CodingKey {
            case status
            case note
            case updatedAt = "updated_at"
            case updatedBy = "updated_by"
        }
    }

    let success: Bool?
    let message: String?
    let error: String?
    let attendance: Attendance?
}

final class UserAttendanceService {
    private let baseURL = "https://provikart.cz/api"

    func fetchAttendance(token: String?, month: String) async throws -> UserAttendancePayload {
        guard let token, !token.isEmpty else {
            throw UserAttendanceError.notAuthenticated
        }

        var comp = URLComponents(string: "\(baseURL)/user_attendance.php")
        comp?.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "month", value: month),
            URLQueryItem(name: "_", value: "\(Int(Date().timeIntervalSince1970))")
        ]
        guard let url = comp?.url else {
            throw UserAttendanceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UserAttendanceError.serverError(-1, "Neplatná odpověď")
        }

        let decoded = try? JSONDecoder().decode(UserAttendanceResponse.self, from: data)
        let message = decoded?.error ?? String(data: data, encoding: .utf8)

        switch http.statusCode {
        case 200:
            guard let decoded, decoded.success, let user = decoded.user else {
                throw UserAttendanceError.serverError(200, message)
            }
            return UserAttendancePayload(
                weekStart: decoded.weekStart,
                month: decoded.month,
                days: decoded.days,
                user: user
            )
        case 401:
            throw UserAttendanceError.notAuthenticated
        default:
            throw UserAttendanceError.serverError(http.statusCode, message)
        }
    }

    func updateAttendance(token: String?, day: String, status: String, note: String?) async throws -> UserAttendanceEntry {
        guard let token, !token.isEmpty else {
            throw UserAttendanceError.notAuthenticated
        }
        guard let url = URL(string: "\(baseURL)/user_attendance_update.php") else {
            throw UserAttendanceError.invalidURL
        }

        var body: [String: Any] = [
            "token": token,
            "work_date": day,
            "status": status
        ]
        if let note {
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
            throw UserAttendanceError.serverError(-1, "Neplatná odpověď")
        }

        let decoded = try? JSONDecoder().decode(UserAttendanceUpdateResponse.self, from: data)
        let message = decoded?.error ?? decoded?.message ?? String(data: data, encoding: .utf8)

        switch http.statusCode {
        case 200:
            guard decoded?.success == true else {
                throw UserAttendanceError.serverError(200, message)
            }
            let normalizedStatus = (decoded?.attendance?.status ?? status).uppercased()
            return UserAttendanceEntry(
                status: normalizedStatus,
                note: decoded?.attendance?.note ?? note,
                updatedAt: decoded?.attendance?.updatedAt,
                updatedBy: decoded?.attendance?.updatedBy,
                isDefault: false
            )
        case 401:
            throw UserAttendanceError.notAuthenticated
        default:
            throw UserAttendanceError.serverError(http.statusCode, message)
        }
    }
}
