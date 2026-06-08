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
    private static let teamService = ManagerTeamMembersService()

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
        async let teamTask = fetchTeamSize(token: token)

        let reports = await reportsTask
        let attendance = await attendanceTask
        let teamSize = await teamTask

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
            ManagerTeamLiveActivityManager.update(
                openProblems: open.count,
                teamSize: teamSize ?? attendance?.teamSize ?? 0,
                presentToday: attendance?.presentToday ?? 0,
                latestProblemLabel: preview.first?.displayLine
            )
        }

        if let attendance {
            WidgetDataStore.saveManagerAttendance(
                teamSize: attendance.teamSize,
                presentToday: attendance.presentToday,
                absentNames: attendance.absentNames
            )
            if reports == nil {
                let openCount = WidgetDataStore.managerOpenProblemsCount ?? 0
                ManagerTeamLiveActivityManager.update(
                    openProblems: openCount,
                    teamSize: attendance.teamSize,
                    presentToday: attendance.presentToday,
                    latestProblemLabel: nil
                )
            }
        }
    }

    private struct AttendanceSummary {
        let teamSize: Int
        let presentToday: Int
        let absentNames: [String]
    }

    private static func fetchReports(token: String) async -> [UserReport]? {
        try? await reportsService.fetchManagerReports(token: token)
    }

    private static func fetchTeamSize(token: String) async -> Int? {
        guard let members = try? await teamService.fetchMembers(token: token) else { return nil }
        return members.count
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
