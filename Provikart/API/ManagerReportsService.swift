//
//  ManagerReportsService.swift
//  Provikart
//
//  Načtení reportů týmu manažera (GET /api/manager_reports.php).
//

import Foundation

enum ManagerReportsFilter: String, CaseIterable, Identifiable {
    case regular
    case incompleteOrders
    case deferredSales
    case termSelection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .regular: return "Reporty"
        case .incompleteOrders: return "Nedokončené"
        case .deferredSales: return "Odložené"
        case .termSelection: return "Termíny"
        }
    }

    var subtitle: String {
        switch self {
        case .regular: return "Běžné problémy týmu"
        case .incompleteOrders: return "Nedokončené objednávky"
        case .deferredSales: return "Odložené prodeje"
        case .termSelection: return "Problémy s termínem"
        }
    }

    var icon: String {
        switch self {
        case .regular: return "exclamationmark.bubble.fill"
        case .incompleteOrders: return "cart.badge.minus"
        case .deferredSales: return "clock.arrow.circlepath"
        case .termSelection: return "calendar.badge.exclamationmark"
        }
    }

    var queryItems: [URLQueryItem] {
        switch self {
        case .regular:
            return []
        case .incompleteOrders:
            return [URLQueryItem(name: "incomplete_orders_only", value: "1")]
        case .deferredSales:
            return [URLQueryItem(name: "deferred_sales_only", value: "1")]
        case .termSelection:
            return [URLQueryItem(name: "term_selection_only", value: "1")]
        }
    }

    /// Plán API volání pro více současně vybraných kategorií.
    static func apiRequests(for filters: Set<ManagerReportsFilter>) -> [ManagerReportsFilter] {
        guard !filters.isEmpty else { return [] }

        var requests: [ManagerReportsFilter] = []

        if filters.contains(.regular) {
            requests.append(.regular)
        }

        let wantsDeferred = filters.contains(.deferredSales)
        let wantsIncomplete = filters.contains(.incompleteOrders)
        if wantsDeferred && wantsIncomplete {
            requests.append(.deferredSales)
            requests.append(.incompleteOrders)
        } else {
            if wantsDeferred { requests.append(.deferredSales) }
            if wantsIncomplete { requests.append(.incompleteOrders) }
        }

        if filters.contains(.termSelection) {
            requests.append(.termSelection)
        }

        return requests
    }
}

struct ManagerReportsFetchResult {
    let reports: [UserReport]
    let reportsByFilter: [ManagerReportsFilter: [UserReport]]
    let deferredSalesCount: Int
    let incompleteOrdersCount: Int
    let termSelectionCount: Int
}

struct ManagerReportsResponse: Decodable {
    let success: Bool
    let reports: [UserReport]
    let count: Int
    let deferred_sales_count: Int?
    let incomplete_orders_count: Int?
    let term_selection_count: Int?
}

enum ManagerReportsError: LocalizedError {
    case invalidURL
    case notAuthenticated
    case serverError(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Neplatná adresa API"
        case .notAuthenticated: return "Nejste přihlášeni"
        case .serverError(let code, let message): return message ?? "Chyba serveru (\(code))"
        }
    }
}

final class ManagerReportsService {
    private let baseURL = "https://provikart.cz/api"

    /// Načte reporty pro jednu nebo více kategorií paralelně a sloučí výsledky.
    func fetchManagerReports(
        token: String?,
        filters: Set<ManagerReportsFilter>
    ) async throws -> ManagerReportsFetchResult {
        let requests = ManagerReportsFilter.apiRequests(for: filters)
        guard !requests.isEmpty else {
            return ManagerReportsFetchResult(
                reports: [],
                reportsByFilter: [:],
                deferredSalesCount: 0,
                incompleteOrdersCount: 0,
                termSelectionCount: 0
            )
        }

        var reportsByFilter: [ManagerReportsFilter: [UserReport]] = [:]
        var deferredCount = 0
        var incompleteCount = 0
        var termCount = 0

        try await withThrowingTaskGroup(of: (ManagerReportsFilter, ManagerReportsFetchResult).self) { group in
            for filter in requests {
                group.addTask {
                    let result = try await self.fetchManagerReports(token: token, filter: filter)
                    return (filter, result)
                }
            }
            for try await (filter, result) in group {
                reportsByFilter[filter] = result.reports
                deferredCount = result.deferredSalesCount
                incompleteCount = result.incompleteOrdersCount
                termCount = result.termSelectionCount
            }
        }

        var seen = Set<Int>()
        var merged: [UserReport] = []
        for filter in requests {
            for report in reportsByFilter[filter] ?? [] where seen.insert(report.id).inserted {
                merged.append(report)
            }
        }
        let sorted = merged.sorted { lhs, rhs in
            let lDate = Self.parseReportDate(lhs.created_at)
            let rDate = Self.parseReportDate(rhs.created_at)
            switch (lDate, rDate) {
            case let (l?, r?): return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.id > rhs.id
            }
        }

        return ManagerReportsFetchResult(
            reports: sorted,
            reportsByFilter: reportsByFilter,
            deferredSalesCount: deferredCount,
            incompleteOrdersCount: incompleteCount,
            termSelectionCount: termCount
        )
    }

    func fetchManagerReports(
        token: String?,
        filter: ManagerReportsFilter = .regular
    ) async throws -> ManagerReportsFetchResult {
        guard let token = token, !token.isEmpty else {
            throw ManagerReportsError.notAuthenticated
        }

        var queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "_", value: "\(Int(Date().timeIntervalSince1970))")
        ]
        queryItems.append(contentsOf: filter.queryItems)

        var comp = URLComponents(string: "\(baseURL)/manager_reports.php")
        comp?.queryItems = queryItems
        guard let url = comp?.url else {
            throw ManagerReportsError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ManagerReportsError.serverError(-1, "Neplatná odpověď")
        }

        switch http.statusCode {
        case 200:
            do {
                let decoded = try JSONDecoder().decode(ManagerReportsResponse.self, from: data)
                guard decoded.success else {
                    throw ManagerReportsError.serverError(200, "API vrátilo success: false")
                }
                return ManagerReportsFetchResult(
                    reports: decoded.reports,
                    reportsByFilter: [filter: decoded.reports],
                    deferredSalesCount: decoded.deferred_sales_count ?? 0,
                    incompleteOrdersCount: decoded.incomplete_orders_count ?? 0,
                    termSelectionCount: decoded.term_selection_count ?? 0
                )
            } catch let error as ManagerReportsError {
                throw error
            } catch {
                let body = String(data: data, encoding: .utf8)
                throw ManagerReportsError.serverError(200, body)
            }
        case 401:
            throw ManagerReportsError.notAuthenticated
        default:
            let body = String(data: data, encoding: .utf8)
            throw ManagerReportsError.serverError(http.statusCode, body)
        }
    }

    /// Zpětná kompatibilita pro volání bez filtru.
    func fetchManagerReports(token: String?) async throws -> [UserReport] {
        try await fetchManagerReports(token: token, filters: [.regular]).reports
    }

    private static func parseReportDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }
}
