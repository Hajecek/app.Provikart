//
//  PerformanceDayReportService.swift
//  Provikart
//
//  Denní report výkonu. required = po 19:00 a bez jediné služby.
//

import Foundation

struct PerformanceDayReportPrompt: Decodable {
    let required: Bool
    let title: String
    let message: String
    let reportDate: String
    let minCommentWords: Int
    let submitted: Bool
    let serviceCount: Int

    enum CodingKeys: String, CodingKey {
        case required
        case title
        case message
        case reportDate = "report_date"
        case minCommentWords = "min_comment_words"
        case submitted
        case serviceCount = "service_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? c.decode(Bool.self, forKey: .required) {
            required = value
        } else {
            required = ((try? c.decode(Int.self, forKey: .required)) ?? 0) == 1
        }
        title = (try? c.decode(String.self, forKey: .title)) ?? "Report výkonu"
        message = (try? c.decode(String.self, forKey: .message)) ?? ""
        reportDate = (try? c.decode(String.self, forKey: .reportDate)) ?? ""
        minCommentWords = (try? c.decode(Int.self, forKey: .minCommentWords)) ?? 50
        if let value = try? c.decode(Bool.self, forKey: .submitted) {
            submitted = value
        } else {
            submitted = ((try? c.decode(Int.self, forKey: .submitted)) ?? 0) == 1
        }
        serviceCount = (try? c.decode(Int.self, forKey: .serviceCount)) ?? 0
    }
}

private struct PerformanceDayReportEnvelope: Decodable {
    let success: Bool
    let error: String?
    let performanceDayReport: PerformanceDayReportPrompt?

    enum CodingKeys: String, CodingKey {
        case success
        case error
        case performanceDayReport = "performance_day_report"
    }
}

enum PerformanceDayReportError: LocalizedError {
    case invalidURL
    case notAuthenticated
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Neplatná adresa API"
        case .notAuthenticated:
            return "Nejste přihlášeni"
        case .server(let message):
            return message
        }
    }
}

final class PerformanceDayReportService {
    private let baseURL = "https://provikart.cz/api"

    func fetch(token: String?) async throws -> PerformanceDayReportPrompt {
        guard let token, !token.isEmpty else {
            throw PerformanceDayReportError.notAuthenticated
        }
        var comp = URLComponents(string: "\(baseURL)/performance_day_report.php")
        comp?.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "_", value: "\(Int(Date().timeIntervalSince1970))")
        ]
        guard let url = comp?.url else {
            throw PerformanceDayReportError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    func save(token: String?, knocked: Int, opened: Int, comment: String) async throws -> PerformanceDayReportPrompt {
        guard let token, !token.isEmpty else {
            throw PerformanceDayReportError.notAuthenticated
        }
        guard let url = URL(string: "\(baseURL)/performance_day_report.php") else {
            throw PerformanceDayReportError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "token": token,
            "knocked_count": knocked,
            "opened_count": opened,
            "comment": comment
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> PerformanceDayReportPrompt {
        let (data, response) = try await URLSession.shared.authAwareData(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PerformanceDayReportError.server("Neplatná odpověď")
        }
        let decoded = try? JSONDecoder().decode(PerformanceDayReportEnvelope.self, from: data)
        if http.statusCode == 200, let prompt = decoded?.performanceDayReport, decoded?.success == true {
            return prompt
        }
        let message = decoded?.error ?? String(data: data, encoding: .utf8) ?? "Report se nepodařilo načíst."
        throw PerformanceDayReportError.server(message)
    }
}

