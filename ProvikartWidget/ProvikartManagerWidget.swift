//
//  ProvikartManagerWidget.swift
//  ProvikartWidget
//
//  Widgety pro manažera – problémy týmu, docházka a přehled.
//

import WidgetKit
import SwiftUI

private let appGroupIdentifier = "group.com.hajecek.provikartApp"
private let timelineRefreshInterval: TimeInterval = 30 * 60
private let networkRequestTimeout: TimeInterval = 10
private let managerAccent = Color.indigo

private enum ManagerWidgetKeys {
    static let authToken = "widget_auth_token"
    static let userRole = "widget_user_role"
    static let managerOpenProblems = "widget_manager_open_problems"
    static let managerTeamSize = "widget_manager_team_size"
    static let managerPresentToday = "widget_manager_present_today"
    static let managerAbsentNames = "widget_manager_absent_names"
    static let managerProblemsPreview = "widget_manager_problems_preview"
}

// Changed this from fileprivate to internal (default)
struct ManagerProblemPreviewItem: Codable, Identifiable {
    let user_name: String?
    let order_number: String?
    let note: String?

    var id: String { "\(user_name ?? "")-\(order_number ?? "")" }

    var displayLine: String {
        var parts: [String] = []
        if let name = user_name, !name.isEmpty { parts.append(name) }
        if let order = order_number, !order.isEmpty { parts.append("obj. \(order)") }
        if parts.isEmpty, let note, !note.isEmpty {
            parts.append(String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(36)))
        }
        return parts.isEmpty ? "Otevřený problém" : parts.joined(separator: " · ")
    }
}

// MARK: - Shared cache helpers

private func loadAuthToken() -> String? {
    let suite = UserDefaults(suiteName: appGroupIdentifier)
    let token = suite?.string(forKey: ManagerWidgetKeys.authToken)
    let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines)
    return (trimmed?.isEmpty == false) ? trimmed : nil
}

private func isManagerRole() -> Bool {
    let suite = UserDefaults(suiteName: appGroupIdentifier)
    return suite?.string(forKey: ManagerWidgetKeys.userRole) == "manager"
}

// MARK: - Problems widget

struct ManagerProblemsEntry: TimelineEntry {
    let date: Date
    let openCount: Int?
    let preview: [ManagerProblemPreviewItem]
    let hasData: Bool
}

struct ProvikartManagerProblemsWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ManagerProblemsEntry {
        ManagerProblemsEntry(
            date: Date(),
            openCount: 4,
            preview: [
                ManagerProblemPreviewItem(user_name: "Jan Novák", order_number: "12345", note: nil),
                ManagerProblemPreviewItem(user_name: "Eva Svobodová", order_number: "12346", note: nil)
            ],
            hasData: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ManagerProblemsEntry) -> Void) {
        completion(loadCachedProblemsEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ManagerProblemsEntry>) -> Void) {
        let cached = loadCachedProblemsEntry()
        let nextReload = Date().addingTimeInterval(timelineRefreshInterval)

        guard isManagerRole(), let token = loadAuthToken() else {
            completion(Timeline(entries: [cached], policy: .after(Date().addingTimeInterval(60 * 60))))
            return
        }

        var didComplete = false
        let completeOnce: (Timeline<ManagerProblemsEntry>) -> Void = { timeline in
            guard !didComplete else { return }
            didComplete = true
            completion(timeline)
        }

        Task {
            let fresh = await fetchManagerProblems(token: token)
            completeOnce(Timeline(entries: [fresh ?? cached], policy: .after(nextReload)))
        }

        Task {
            try? await Task.sleep(nanoseconds: UInt64((networkRequestTimeout + 1) * 1_000_000_000))
            completeOnce(Timeline(entries: [cached], policy: .after(nextReload)))
        }
    }

    private func loadCachedProblemsEntry() -> ManagerProblemsEntry {
        let suite = UserDefaults(suiteName: appGroupIdentifier)
        let rawCount = suite?.object(forKey: ManagerWidgetKeys.managerOpenProblems)
        let count: Int? = (rawCount as? NSNumber)?.intValue ?? rawCount as? Int
        let preview: [ManagerProblemPreviewItem]
        if let data = suite?.data(forKey: ManagerWidgetKeys.managerProblemsPreview),
           let decoded = try? JSONDecoder().decode([ManagerProblemPreviewItem].self, from: data) {
            preview = decoded
        } else {
            preview = []
        }
        let hasData = suite?.object(forKey: ManagerWidgetKeys.managerOpenProblems) != nil
        return ManagerProblemsEntry(date: Date(), openCount: count, preview: preview, hasData: hasData)
    }

    private struct ReportsAPIResponse: Decodable {
        let success: Bool
        let reports: [Report]

        struct Report: Decodable {
            let status: String?
            let user_name: String?
            let order_number: String?
            let note: String?
        }
    }

    @MainActor
    private func saveProblemsToCache(openCount: Int, preview: [ManagerProblemPreviewItem]) {
        let suite = UserDefaults(suiteName: appGroupIdentifier)
        suite?.set(NSNumber(value: openCount), forKey: ManagerWidgetKeys.managerOpenProblems)
        if let data = try? JSONEncoder().encode(preview) {
            suite?.set(data, forKey: ManagerWidgetKeys.managerProblemsPreview)
        }
    }

    private func fetchManagerProblems(token: String) async -> ManagerProblemsEntry? {
        var comp = URLComponents(string: "https://provikart.cz/api/manager_reports.php")
        comp?.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "_", value: "\(Int(Date().timeIntervalSince1970))")
        ]
        guard let url = comp?.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = networkRequestTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(ReportsAPIResponse.self, from: data)
            guard decoded.success else { return nil }

            let open = decoded.reports.filter { ($0.status ?? "").lowercased() != "completed" }
            let preview = open.prefix(5).map {
                ManagerProblemPreviewItem(user_name: $0.user_name, order_number: $0.order_number, note: $0.note)
            }
            await MainActor.run { saveProblemsToCache(openCount: open.count, preview: Array(preview)) }
            return ManagerProblemsEntry(date: Date(), openCount: open.count, preview: Array(preview), hasData: true)
        } catch {
            return nil
        }
    }
}

struct ProvikartManagerProblemsWidgetEntryView: View {
    var entry: ManagerProblemsEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall: problemsSmallView
            case .systemMedium: problemsMediumView
            case .accessoryCircular: problemsCircularView
            case .accessoryRectangular: problemsRectangularView
            case .accessoryInline: problemsInlineView
            default: problemsMediumView
            }
        }
        .containerBackground(for: .widget) {
            Color(uiColor: .secondarySystemGroupedBackground)
        }
        .widgetURL(URL(string: "provikart://manager/problems"))
    }

    private var problemsCircularView: some View {
        ZStack {
            if entry.hasData, let count = entry.openCount {
                Text("\(count)")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(managerAccent)
            } else {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(managerAccent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var problemsRectangularView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Tým – problémy", systemImage: "person.3.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            if entry.hasData, let count = entry.openCount {
                Text(count == 0 ? "Žádné otevřené problémy" : (count == 1 ? "1 otevřený problém" : "\(count) otevřených problémů"))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            } else {
                Text("Přihlaste se jako manažer")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var problemsInlineView: some View {
        if entry.hasData, let count = entry.openCount {
            Text(count == 0 ? "Tým bez otevřených problémů" : "Tým: \(count) otevřených problémů")
                .font(.system(size: 14, weight: .medium))
        } else {
            Text("Provikart Manažer – přihlaste se")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var problemsSmallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(managerAccent)
                Text("TÝM")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            Spacer(minLength: 8)
            if entry.hasData, let count = entry.openCount {
                Text("\(count)")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(managerAccent)
                Text(count == 1 ? "otevřený problém" : "otevřených problémů")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Text("Přihlaste se")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(16)
    }

    private var problemsMediumView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(managerAccent)
                Text("Problémy týmu")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if entry.hasData, let count = entry.openCount {
                    Text("\(count)")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(managerAccent)
                }
            }
            if !entry.hasData {
                Text("Přihlaste se jako manažer")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if entry.preview.isEmpty {
                Text("Žádné otevřené problémy")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entry.preview.prefix(3)) { item in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(managerAccent.opacity(0.2))
                            .frame(width: 6, height: 6)
                        Text(item.displayLine)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
    }
}

struct ProvikartManagerProblemsWidget: Widget {
    let kind: String = "ProvikartManagerProblemsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProvikartManagerProblemsWidgetProvider()) { entry in
            ProvikartManagerProblemsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Tým – problémy")
        .description("Otevřené problémy členů vašeho týmu.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline
        ])
    }
}

// MARK: - Attendance widget

struct ManagerAttendanceEntry: TimelineEntry {
    let date: Date
    let teamSize: Int?
    let presentToday: Int?
    let absentNames: [String]
    let hasData: Bool
}

struct ProvikartManagerAttendanceWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ManagerAttendanceEntry {
        ManagerAttendanceEntry(date: Date(), teamSize: 8, presentToday: 6, absentNames: ["Jan N.", "Eva S."], hasData: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (ManagerAttendanceEntry) -> Void) {
        completion(loadCachedAttendanceEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ManagerAttendanceEntry>) -> Void) {
        let cached = loadCachedAttendanceEntry()
        let nextReload = Date().addingTimeInterval(timelineRefreshInterval)

        guard isManagerRole(), let token = loadAuthToken() else {
            completion(Timeline(entries: [cached], policy: .after(Date().addingTimeInterval(60 * 60))))
            return
        }

        var didComplete = false
        let completeOnce: (Timeline<ManagerAttendanceEntry>) -> Void = { timeline in
            guard !didComplete else { return }
            didComplete = true
            completion(timeline)
        }

        Task {
            let fresh = await fetchManagerAttendance(token: token)
            completeOnce(Timeline(entries: [fresh ?? cached], policy: .after(nextReload)))
        }

        Task {
            try? await Task.sleep(nanoseconds: UInt64((networkRequestTimeout + 1) * 1_000_000_000))
            completeOnce(Timeline(entries: [cached], policy: .after(nextReload)))
        }
    }

    private func loadCachedAttendanceEntry() -> ManagerAttendanceEntry {
        let suite = UserDefaults(suiteName: appGroupIdentifier)
        let teamSize = (suite?.object(forKey: ManagerWidgetKeys.managerTeamSize) as? NSNumber)?.intValue
        let present = (suite?.object(forKey: ManagerWidgetKeys.managerPresentToday) as? NSNumber)?.intValue
        let absentNames: [String]
        if let data = suite?.data(forKey: ManagerWidgetKeys.managerAbsentNames),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            absentNames = decoded
        } else {
            absentNames = []
        }
        let hasData = suite?.object(forKey: ManagerWidgetKeys.managerTeamSize) != nil
        return ManagerAttendanceEntry(
            date: Date(),
            teamSize: teamSize,
            presentToday: present,
            absentNames: absentNames,
            hasData: hasData
        )
    }

    private struct AttendanceAPIResponse: Decodable {
        let success: Bool
        let days: [String]?
        let users: [AttendanceUser]?

        struct AttendanceUser: Decodable {
            let name: String?
            let username: String?
            let user_id: Int?
            let attendance: [String: AttendanceEntry]?
        }

        struct AttendanceEntry: Decodable {
            let status: String?
        }
    }

    @MainActor
    private func saveAttendanceToCache(teamSize: Int, presentToday: Int, absentNames: [String]) {
        let suite = UserDefaults(suiteName: appGroupIdentifier)
        suite?.set(NSNumber(value: teamSize), forKey: ManagerWidgetKeys.managerTeamSize)
        suite?.set(NSNumber(value: presentToday), forKey: ManagerWidgetKeys.managerPresentToday)
        if let data = try? JSONEncoder().encode(absentNames) {
            suite?.set(data, forKey: ManagerWidgetKeys.managerAbsentNames)
        }
    }

    private func fetchManagerAttendance(token: String) async -> ManagerAttendanceEntry? {
        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "en_US_POSIX")
        monthFormatter.timeZone = .current
        monthFormatter.dateFormat = "yyyy-MM"
        let month = monthFormatter.string(from: Date())

        var comp = URLComponents(string: "https://provikart.cz/api/manager_attendance.php")
        comp?.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "month", value: month),
            URLQueryItem(name: "include_self", value: "0"),
            URLQueryItem(name: "_", value: "\(Int(Date().timeIntervalSince1970))")
        ]
        guard let url = comp?.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = networkRequestTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(AttendanceAPIResponse.self, from: data)
            guard decoded.success, let users = decoded.users else { return nil }

            let dayFormatter = DateFormatter()
            dayFormatter.locale = Locale(identifier: "en_US_POSIX")
            dayFormatter.timeZone = .current
            dayFormatter.dateFormat = "yyyy-MM-dd"
            let todayKey = dayFormatter.string(from: Date())

            var present = 0
            var absentNames: [String] = []
            for user in users {
                let status = (user.attendance?[todayKey]?.status ?? "").uppercased()
                if status == "P" {
                    present += 1
                } else {
                    absentNames.append(displayName(user))
                }
            }

            await MainActor.run {
                saveAttendanceToCache(teamSize: users.count, presentToday: present, absentNames: Array(absentNames.prefix(6)))
            }
            return ManagerAttendanceEntry(
                date: Date(),
                teamSize: users.count,
                presentToday: present,
                absentNames: Array(absentNames.prefix(6)),
                hasData: true
            )
        } catch {
            return nil
        }
    }

    private func displayName(_ user: AttendanceAPIResponse.AttendanceUser) -> String {
        if let name = user.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        if let username = user.username, !username.isEmpty {
            return "@\(username)"
        }
        return "Uživatel #\(user.user_id ?? 0)"
    }
}

struct ProvikartManagerAttendanceWidgetEntryView: View {
    var entry: ManagerAttendanceEntry
    @Environment(\.widgetFamily) var family

    private var presentLabel: String {
        guard let present = entry.presentToday, let total = entry.teamSize else { return "–" }
        return "\(present)/\(total)"
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall: attendanceSmallView
            case .systemMedium: attendanceMediumView
            case .accessoryCircular: attendanceCircularView
            case .accessoryRectangular: attendanceRectangularView
            case .accessoryInline: attendanceInlineView
            default: attendanceMediumView
            }
        }
        .containerBackground(for: .widget) {
            Color(uiColor: .secondarySystemGroupedBackground)
        }
        .widgetURL(URL(string: "provikart://manager/attendance"))
    }

    private var attendanceCircularView: some View {
        ZStack {
            if entry.hasData {
                Text(presentLabel)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            } else {
                Image(systemName: "person.badge.clock.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(managerAccent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var attendanceRectangularView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Docházka týmu", systemImage: "person.badge.clock.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            if entry.hasData {
                Text("Dnes v práci \(presentLabel)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            } else {
                Text("Přihlaste se jako manažer")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var attendanceInlineView: some View {
        if entry.hasData {
            Text("Tým v práci dnes \(presentLabel)")
                .font(.system(size: 14, weight: .medium))
        } else {
            Text("Provikart Manažer – přihlaste se")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var attendanceSmallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "person.badge.clock.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(managerAccent)
                Text("DOCHÁZKA")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            Spacer(minLength: 8)
            if entry.hasData {
                Text(presentLabel)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(managerAccent)
                Text("v práci dnes")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Text("Přihlaste se")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(16)
    }

    private var attendanceMediumView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "person.badge.clock.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(managerAccent)
                Text("Docházka dnes")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if entry.hasData {
                    Text(presentLabel)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(managerAccent)
                }
            }
            if !entry.hasData {
                Text("Přihlaste se jako manažer")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if entry.absentNames.isEmpty {
                Text("Celý tým je v práci")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Text("Nepřítomní:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                ForEach(entry.absentNames.prefix(4), id: \.self) { name in
                    Text(name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
    }
}

struct ProvikartManagerAttendanceWidget: Widget {
    let kind: String = "ProvikartManagerAttendanceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProvikartManagerAttendanceWidgetProvider()) { entry in
            ProvikartManagerAttendanceWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Tým – docházka")
        .description("Kolik členů týmu je dnes v práci.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline
        ])
    }
}

// MARK: - Team overview widget

struct ManagerTeamEntry: TimelineEntry {
    let date: Date
    let openProblems: Int?
    let teamSize: Int?
    let presentToday: Int?
    let hasData: Bool
}

struct ProvikartManagerTeamWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ManagerTeamEntry {
        ManagerTeamEntry(date: Date(), openProblems: 3, teamSize: 8, presentToday: 6, hasData: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (ManagerTeamEntry) -> Void) {
        completion(loadCachedTeamEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ManagerTeamEntry>) -> Void) {
        let cached = loadCachedTeamEntry()
        let nextReload = Date().addingTimeInterval(timelineRefreshInterval)
        completion(Timeline(entries: [cached], policy: .after(nextReload)))
    }

    private func loadCachedTeamEntry() -> ManagerTeamEntry {
        let suite = UserDefaults(suiteName: appGroupIdentifier)
        let open = (suite?.object(forKey: ManagerWidgetKeys.managerOpenProblems) as? NSNumber)?.intValue
        let team = (suite?.object(forKey: ManagerWidgetKeys.managerTeamSize) as? NSNumber)?.intValue
        let present = (suite?.object(forKey: ManagerWidgetKeys.managerPresentToday) as? NSNumber)?.intValue
        let hasData = suite?.object(forKey: ManagerWidgetKeys.managerTeamSize) != nil
            || suite?.object(forKey: ManagerWidgetKeys.managerOpenProblems) != nil
        return ManagerTeamEntry(date: Date(), openProblems: open, teamSize: team, presentToday: present, hasData: hasData)
    }
}

struct ProvikartManagerTeamWidgetEntryView: View {
    var entry: ManagerTeamEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall: teamSmallView
            case .systemMedium: teamMediumView
            case .accessoryCircular: teamCircularView
            case .accessoryRectangular: teamRectangularView
            case .accessoryInline: teamInlineView
            default: teamMediumView
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color.indigo.opacity(0.15), Color(uiColor: .secondarySystemGroupedBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .widgetURL(URL(string: "provikart://"))
    }

    private var teamCircularView: some View {
        ZStack {
            if entry.hasData, let open = entry.openProblems {
                VStack(spacing: 0) {
                    Text("\(open)")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text("prob.")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(managerAccent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var teamRectangularView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Manažerský přehled", systemImage: "person.3.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            if entry.hasData {
                Text(teamSummaryLine)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(2)
            } else {
                Text("Přihlaste se jako manažer")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var teamInlineView: some View {
        if entry.hasData {
            Text(teamSummaryLine)
                .font(.system(size: 14, weight: .medium))
        } else {
            Text("Provikart Manažer – přihlaste se")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var teamSummaryLine: String {
        let open = entry.openProblems ?? 0
        let present = entry.presentToday ?? 0
        let total = entry.teamSize ?? present
        return "\(open) problémů · \(present)/\(total) v práci"
    }

    private var teamSmallView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(managerAccent)
                Text("MANAŽER")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            if entry.hasData {
                HStack(spacing: 16) {
                    miniStat(value: "\(entry.openProblems ?? 0)", label: "problémů")
                    miniStat(
                        value: "\(entry.presentToday ?? 0)/\(entry.teamSize ?? 0)",
                        label: "v práci"
                    )
                }
            } else {
                Text("Přihlaste se")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(16)
    }

    private var teamMediumView: some View {
        HStack(spacing: 0) {
            teamStatColumn(
                icon: "exclamationmark.bubble.fill",
                value: "\(entry.openProblems ?? 0)",
                title: "Otevřené problémy",
                subtitle: "k vyřešení"
            )
            Divider().padding(.vertical, 8)
            teamStatColumn(
                icon: "person.badge.clock.fill",
                value: "\(entry.presentToday ?? 0)/\(entry.teamSize ?? 0)",
                title: "Docházka dnes",
                subtitle: "v práci"
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
        .opacity(entry.hasData ? 1 : 0.6)
        .overlay {
            if !entry.hasData {
                Text("Přihlaste se jako manažer")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func miniStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(managerAccent)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func teamStatColumn(icon: String, value: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(managerAccent)
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(managerAccent)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProvikartManagerTeamWidget: Widget {
    let kind: String = "ProvikartManagerTeamWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProvikartManagerTeamWidgetProvider()) { entry in
            ProvikartManagerTeamWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Manažerský přehled")
        .description("Problémy týmu a docházka na jednom místě.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline
        ])
    }
}

