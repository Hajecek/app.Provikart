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

        if let todayServices {
            WidgetDataStore.saveManagerTodayServices(todayServices)
        }

        ManagerTeamLiveActivityManager.refreshRunning()
    }

    private struct AttendanceSummary {
        let teamSize: Int
        let presentToday: Int
        let absentNames: [String]
    }

    private static func fetchTodayServices(token: String) async -> Int? {
        let month = monthFormatter.string(from: Date())
        guard let payload = try? await performanceService.fetchPerformance(token: token, month: month) else {
            return nil
        }
        return payload.todayServicesCount
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
