//
//  ManagerWidgetRefresh.swift
//  Provikart
//
//  Načtení a uložení dat pro manažerské widgety a Live Activity.
//

import Foundation

enum ManagerWidgetRefresh {
    private static let attendanceService = ManagerAttendanceService()
    private static let reportsService = ManagerReportsService()
    private static let performanceService = ManagerTeamPerformanceService()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM"
        return f
    }()

    @MainActor
    static func refreshAll(token: String) async {
        guard WidgetDataStore.isManager else { return }

        async let reportsTask = fetchReports(token: token)
        async let attendanceTask = fetchAttendance(token: token)
        async let servicesTask = fetchTodayServices(token: token)

        let reports = await reportsTask
        let attendance = await attendanceTask
        let todayServices = await servicesTask

        if let reports {
            let open = reports.filter { !$0.isCompleted }
            let preview = open.prefix(5).map {
                WidgetDataStore.ManagerProblemPreview(
                    user_name: $0.user_name,
                    order_number: $0.order_number,
                    note: $0.note
                )
            }
            WidgetDataStore.saveManagerProblems(openCount: open.count, preview: Array(preview))
        }

        if let attendance {
            WidgetDataStore.saveManagerAttendance(
                teamSize: attendance.teamSize,
                presentToday: attendance.presentToday,
                absentNames: attendance.absentNames
            )
        }

        if let performance = todayServices {
            WidgetDataStore.saveManagerTodayServices(performance.today)
            WidgetDataStore.saveManagerPerformance(performance.snapshot)
        }

        ManagerTeamLiveActivityManager.refreshRunning()
    }

    private struct AttendanceSummary {
        let teamSize: Int
        let presentToday: Int
        let absentNames: [String]
    }

    private struct PerformanceSummary {
        let today: Int
        let snapshot: WidgetDataStore.ManagerPerformanceSnapshot
    }

    /// Výkon týmu za měsíc: dnešek, součet měsíce, posledních 7 dní a nejlepší obchodník.
    private static func fetchTodayServices(token: String) async -> PerformanceSummary? {
        let month = monthFormatter.string(from: Date())
        guard let payload = try? await performanceService.fetchPerformance(token: token, month: month) else {
            return nil
        }
        return PerformanceSummary(today: payload.todayServicesCount, snapshot: performanceSnapshot(from: payload))
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.dateFormat = "EEEEEE"
        return f
    }()

    private static let monthNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.dateFormat = "LLLL"
        return f
    }()

    static func performanceSnapshot(from payload: ManagerTeamPerformancePayload) -> WidgetDataStore.ManagerPerformanceSnapshot {
        let todayKey = payload.todayDate.isEmpty ? dayFormatter.string(from: Date()) : payload.todayDate
        let pastDays = payload.days.filter { $0 <= todayKey }.sorted().suffix(7)

        var daily: [Int] = []
        var labels: [String] = []
        for day in pastDays {
            var total = payload.users.reduce(0) { $0 + ($1.performance[day]?.servicesCount ?? 0) }
            if day == todayKey { total = max(total, payload.todayServicesCount) }
            daily.append(total)
            if let date = dayFormatter.date(from: day) {
                labels.append(weekdayFormatter.string(from: date).capitalized)
            } else {
                labels.append(String(day.suffix(2)))
            }
        }

        let top = payload.users.max { $0.total < $1.total }
        let topName = top.flatMap { $0.total > 0 ? shortName($0) : nil }

        return WidgetDataStore.ManagerPerformanceSnapshot(
            monthServices: payload.users.reduce(0) { $0 + $1.total },
            dailyServices: daily,
            dailyLabels: labels,
            topPerformerName: topName,
            topPerformerServices: top?.total ?? 0,
            monthLabel: monthNameFormatter.string(from: Date()).capitalized
        )
    }

    /// „Jana Krátká“ → „Jana K.“ – krátké jméno se vejde do kapsle v Islandu.
    private static func shortName(_ user: ManagerPerformanceUser) -> String {
        let first = user.firstname?.trimmingCharacters(in: .whitespaces) ?? ""
        let last = user.lastname?.trimmingCharacters(in: .whitespaces) ?? ""
        if !first.isEmpty {
            return last.isEmpty ? first : "\(first) \(last.prefix(1))."
        }
        let parts = user.name.split(separator: " ")
        guard let head = parts.first else { return user.name }
        if parts.count > 1, let initial = parts[1].first {
            return "\(head) \(initial)."
        }
        return String(head)
    }

    private static func fetchReports(token: String) async -> [UserReport]? {
        try? await reportsService.fetchManagerReports(token: token)
    }

    private static func fetchAttendance(token: String) async -> AttendanceSummary? {
        let month = monthFormatter.string(from: Date())
        guard let payload = try? await attendanceService.fetchAttendance(token: token, month: month, includeSelf: false) else {
            return nil
        }

        let todayKey = dayFormatter.string(from: Date())
        let users = payload.users
        var present = 0
        var absentNames: [String] = []

        for user in users {
            let status = normalizedStatus(user.attendance[todayKey]?.status ?? "")
            if status == "P" {
                present += 1
            } else {
                absentNames.append(displayName(for: user))
            }
        }

        return AttendanceSummary(
            teamSize: users.count,
            presentToday: present,
            absentNames: Array(absentNames.prefix(6))
        )
    }

    private static func normalizedStatus(_ raw: String) -> String {
        let status = raw.uppercased()
        if status == "D" { return "V" }
        return status
    }

    private static func displayName(for user: ManagerAttendanceUser) -> String {
        if !user.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return user.name
        }
        if let username = user.username, !username.isEmpty {
            return "@\(username)"
        }
        return "Uživatel #\(user.userId)"
    }
}
