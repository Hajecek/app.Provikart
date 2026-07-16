//
//  ManagerAttendanceView.swift
//  Provikart
//
//  Manažerský přehled docházky týmu.
//

import SwiftUI

private enum ManagerAttendanceFilter: String, CaseIterable, Identifiable {
    case all = "Všichni"
    case presentToday = "Dnes v práci"
    case absentToday = "Dnes nepřítomni"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .all: return "person.3.fill"
        case .presentToday: return "checkmark.circle.fill"
        case .absentToday: return "calendar.circle.fill"
        }
    }
}

private extension ManagerAttendanceUser {
    var profileImageURL: URL? {
        guard let name = profileImage?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return nil
        }
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        return URL(string: "https://provikart.cz/auth/serve_image?file=\(encoded)")
    }
}

@MainActor
final class ManagerAttendanceViewModel: ObservableObject {
    @Published var users: [ManagerAttendanceUser] = []
    @Published var days: [String] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedMonthDate: Date = Date()
    @Published var savingKey: String?

    private let service = ManagerAttendanceService()

    var monthTitle: String {
        Self.monthTitleFormatter.string(from: selectedMonthDate).capitalized
    }

    var todayKey: String {
        Self.dayKeyFormatter.string(from: Date())
    }

    var isCurrentMonth: Bool {
        Calendar.current.isDate(selectedMonthDate, equalTo: Date(), toGranularity: .month)
    }

    var presentTodayCount: Int {
        users.filter { normalizedAttendanceStatus(attendanceStatus(for: $0, day: todayKey)) == "P" }.count
    }

    var absentTodayCount: Int {
        max(users.count - presentTodayCount, 0)
    }

    var presentTodayRate: Double {
        guard !users.isEmpty else { return 0 }
        return Double(presentTodayCount) / Double(users.count)
    }

    func loadAttendance(token: String?) async {
        guard let token, !token.isEmpty else {
            users = []
            days = []
            errorMessage = "Nejste přihlášeni."
            return
        }

        isLoading = true
        errorMessage = nil
        do {
            let month = Self.monthAPIFormatter.string(from: selectedMonthDate)
            let payload = try await service.fetchAttendance(token: token, month: month, includeSelf: true)
            users = payload.users
            days = payload.days
            saveAttendanceWidgetData(users: payload.users)
            isLoading = false
        } catch {
            isLoading = false
            guard !Self.isCancellation(error) else { return }
            // Při chybě nemažeme stávající data (např. cancel z pull-to-refresh).
            if users.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        return false
    }

    func moveMonth(by offset: Int) {
        guard let updated = Calendar.current.date(byAdding: .month, value: offset, to: selectedMonthDate) else { return }
        selectedMonthDate = updated
    }

    func jumpToCurrentMonth() {
        selectedMonthDate = Date()
    }

    func updateAttendance(token: String?, userId: Int, day: String, status: String) async {
        guard let token, !token.isEmpty else {
            errorMessage = "Nejste přihlášeni."
            return
        }

        guard let userIndex = users.firstIndex(where: { $0.userId == userId }) else { return }
        let key = "\(userId)_\(day)"
        savingKey = key
        let previousEntry = users[userIndex].attendance[day]

        var updatedAttendance = users[userIndex].attendance
        updatedAttendance[day] = ManagerAttendanceEntry(
            status: status,
            note: previousEntry?.note,
            updatedAt: previousEntry?.updatedAt,
            updatedBy: previousEntry?.updatedBy,
            isDefault: false
        )
        users[userIndex] = ManagerAttendanceUser(
            userId: users[userIndex].userId,
            name: users[userIndex].name,
            firstname: users[userIndex].firstname,
            lastname: users[userIndex].lastname,
            username: users[userIndex].username,
            profileImage: users[userIndex].profileImage,
            attendance: updatedAttendance
        )

        do {
            try await service.updateAttendance(token: token, userId: userId, day: day, status: status)
            savingKey = nil
            saveAttendanceWidgetData(users: users)
        } catch {
            if let rollback = previousEntry {
                updatedAttendance[day] = rollback
            }
            users[userIndex] = ManagerAttendanceUser(
                userId: users[userIndex].userId,
                name: users[userIndex].name,
                firstname: users[userIndex].firstname,
                lastname: users[userIndex].lastname,
                username: users[userIndex].username,
                profileImage: users[userIndex].profileImage,
                attendance: updatedAttendance
            )
            savingKey = nil
            errorMessage = error.localizedDescription
        }
    }

    fileprivate func filteredUsers(search: String, filter: ManagerAttendanceFilter) -> [ManagerAttendanceUser] {
        let query = normalizedSearchText(search)
        return users
            .filter { user in
                switch filter {
                case .all:
                    return true
                case .presentToday:
                    return normalizedAttendanceStatus(attendanceStatus(for: user, day: todayKey)) == "P"
                case .absentToday:
                    return normalizedAttendanceStatus(attendanceStatus(for: user, day: todayKey)) != "P"
                }
            }
            .filter { user in
                guard !query.isEmpty else { return true }
                let haystack = searchableText(for: user)
                return query.allSatisfy { haystack.contains($0) }
            }
            .sorted { lhs, rhs in
                displayName(for: lhs).localizedCaseInsensitiveCompare(displayName(for: rhs)) == .orderedAscending
            }
    }

    func displayName(for user: ManagerAttendanceUser) -> String {
        if !user.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return user.name
        }
        let first = (user.firstname ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (user.lastname ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let full = "\(first) \(last)".trimmingCharacters(in: .whitespacesAndNewlines)
        if !full.isEmpty {
            return full
        }
        if let username = user.username, !username.isEmpty {
            return "@\(username)"
        }
        return "Uživatel #\(user.userId)"
    }

    func initials(for user: ManagerAttendanceUser) -> String {
        let first = (user.firstname ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (user.lastname ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let f = first.first, let l = last.first {
            return "\(String(f).uppercased())\(String(l).uppercased())"
        }
        if let f = first.first {
            return String(f).uppercased()
        }
        if let u = user.username?.first {
            return String(u).uppercased()
        }
        return "?"
    }

    func attendanceStatus(for user: ManagerAttendanceUser, day: String) -> String {
        user.attendance[day]?.status ?? "?"
    }

    func normalizedStatus(_ raw: String) -> String {
        normalizedAttendanceStatus(raw)
    }

    func statusCount(_ status: String, user: ManagerAttendanceUser) -> Int {
        days.reduce(into: 0) { partial, day in
            if normalizedAttendanceStatus(attendanceStatus(for: user, day: day)) == status {
                partial += 1
            }
        }
    }

    func teamStatusCount(_ status: String) -> Int {
        users.reduce(into: 0) { total, user in
            total += statusCount(status, user: user)
        }
    }

    func notesCount(for user: ManagerAttendanceUser) -> Int {
        days.filter { day in
            !(user.attendance[day]?.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }.count
    }

    func isToday(_ day: String) -> Bool {
        day == todayKey
    }

    private func searchableText(for user: ManagerAttendanceUser) -> String {
        let fullName = "\(user.firstname ?? "") \(user.lastname ?? "")"
        let pieces = [
            displayName(for: user),
            fullName,
            user.firstname ?? "",
            user.lastname ?? "",
            user.username ?? ""
        ]
        return normalizedSearchString(pieces.joined(separator: " "))
    }

    private func normalizedSearchText(_ text: String) -> [String] {
        normalizedSearchString(text)
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func normalizedSearchString(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func saveAttendanceWidgetData(users: [ManagerAttendanceUser]) {
        let todayKey = Self.dayKeyFormatter.string(from: Date())
        var present = 0
        var absentNames: [String] = []

        for user in users {
            let status = normalizedAttendanceStatus(user.attendance[todayKey]?.status ?? "")
            if status == "P" {
                present += 1
            } else {
                absentNames.append(displayName(for: user))
            }
        }

        WidgetDataStore.saveManagerAttendance(
            teamSize: users.count,
            presentToday: present,
            absentNames: Array(absentNames.prefix(6))
        )

        let openProblems = WidgetDataStore.managerOpenProblemsCount ?? 0
        ManagerTeamLiveActivityManager.update(
            openProblems: openProblems,
            teamSize: users.count,
            presentToday: present,
            latestProblemLabel: nil
        )
    }

    private func normalizedAttendanceStatus(_ raw: String) -> String {
        let status = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if status == "D" { return "V" }
        return status
    }

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let monthAPIFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM"
        return f
    }()

    static let monthTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.timeZone = .current
        f.dateFormat = "LLLL yyyy"
        return f
    }()
}

struct ManagerAttendanceView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel = ManagerAttendanceViewModel()
    @State private var selectedCell: AttendanceCellSelection?
    @State private var searchText = ""
    @State private var selectedFilter: ManagerAttendanceFilter = .all
    @State private var isLocationsSheetPresented = false

    private var filteredUsers: [ManagerAttendanceUser] {
        viewModel.filteredUsers(search: searchText, filter: selectedFilter)
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.users.isEmpty {
                    loadingView
                } else if let message = viewModel.errorMessage, viewModel.users.isEmpty {
                    errorView(message)
                } else if viewModel.users.isEmpty {
                    emptyTeamView
                } else {
                    mainContent
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Docházka")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ManagerAddReportToolbarButton()
                    Button {
                        isLocationsSheetPresented = true
                    } label: {
                        Image(systemName: "mappin.and.ellipse")
                    }
                    .accessibilityLabel("Lokality týmu")
                    ProfileBarButton()
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Hledat člena týmu")
            .refreshable {
                await viewModel.loadAttendance(token: authState.authToken)
            }
            .task {
                await viewModel.loadAttendance(token: authState.authToken)
            }
            .onChange(of: viewModel.selectedMonthDate) { _, _ in
                Task {
                    await viewModel.loadAttendance(token: authState.authToken)
                }
            }
            .confirmationDialog(
                "Změnit docházku",
                isPresented: Binding(
                    get: { selectedCell != nil },
                    set: { if !$0 { selectedCell = nil } }
                ),
                titleVisibility: .visible,
                presenting: selectedCell
            ) { selection in
                Button("Práce (P)") {
                    Task {
                        await viewModel.updateAttendance(
                            token: authState.authToken,
                            userId: selection.user.userId,
                            day: selection.day,
                            status: "P"
                        )
                    }
                }
                Button("Volno (V)") {
                    Task {
                        await viewModel.updateAttendance(
                            token: authState.authToken,
                            userId: selection.user.userId,
                            day: selection.day,
                            status: "V"
                        )
                    }
                }
                Button("Nemoc (N)") {
                    Task {
                        await viewModel.updateAttendance(
                            token: authState.authToken,
                            userId: selection.user.userId,
                            day: selection.day,
                            status: "N"
                        )
                    }
                }
                Button("Zrušit", role: .cancel) {}
            } message: { selection in
                Text("\(viewModel.displayName(for: selection.user)) · \(dialogDate(selection.day))")
            }
            .sheet(isPresented: $isLocationsSheetPresented) {
                ManagerLocationsSheetView()
                    .environmentObject(authState)
            }
        }
    }

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                monthNavigationCard
                summaryHeroCard
                statusLegend
                filterChips
                membersSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .overlay(alignment: .top) {
            if viewModel.isLoading {
                ProgressView()
                    .padding(10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Načítám docházku…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Nepodařilo se načíst docházku", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Zkusit znovu") {
                Task {
                    await viewModel.loadAttendance(token: authState.authToken)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var emptyTeamView: some View {
        ContentUnavailableView(
            "Žádní členové týmu",
            systemImage: "person.3",
            description: Text("Pro vybraný měsíc nejsou dostupná data.")
        )
    }

    private var monthNavigationCard: some View {
        HStack(spacing: 12) {
            monthStepButton(systemName: "chevron.left") {
                viewModel.moveMonth(by: -1)
            }

            VStack(spacing: 2) {
                Text(viewModel.monthTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                Text("\(viewModel.days.count) dní v přehledu")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            monthStepButton(systemName: "chevron.right") {
                viewModel.moveMonth(by: 1)
            }

            if !viewModel.isCurrentMonth {
                Button("Dnes") {
                    viewModel.jumpToCurrentMonth()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(cardBackground(tint: .blue))
    }

    private var summaryHeroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                presentTodayRing

                VStack(alignment: .leading, spacing: 10) {
                    Text("Dnešní přítomnost")
                        .font(.headline)
                    Text("\(viewModel.users.count) členů týmu")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 8) {
                        summaryStatRow(
                            title: "Dnes v práci",
                            value: viewModel.presentTodayCount,
                            tint: .green,
                            icon: "checkmark.circle.fill"
                        )
                        summaryStatRow(
                            title: "Dnes nepřítomni",
                            value: viewModel.absentTodayCount,
                            tint: .orange,
                            icon: "person.crop.circle.badge.minus"
                        )
                    }
                }
            }

            Divider().opacity(0.35)

            VStack(alignment: .leading, spacing: 10) {
                Text("Souhrn za \(viewModel.monthTitle.lowercased())")
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 8) {
                    monthMetricChip(
                        status: "P",
                        title: "Práce",
                        count: viewModel.teamStatusCount("P"),
                        color: .green
                    )
                    monthMetricChip(
                        status: "V",
                        title: "Volno",
                        count: viewModel.teamStatusCount("V"),
                        color: .blue
                    )
                    monthMetricChip(
                        status: "N",
                        title: "Nemoc",
                        count: viewModel.teamStatusCount("N"),
                        color: .red
                    )
                }
            }
        }
        .padding(16)
        .background(cardBackground(tint: .green))
    }

    private var presentTodayRing: some View {
        let rate = viewModel.presentTodayRate
        let percentage = Int((rate * 100).rounded())

        return ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 8)
            Circle()
                .trim(from: 0, to: rate)
                .stroke(
                    AngularGradient(
                        colors: [.green.opacity(0.7), .green],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(percentage)%")
                    .font(.title3.weight(.bold))
                Text("dnes")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 88, height: 88)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dnes v práci \(percentage) procent")
    }

    private func summaryStatRow(title: String, value: Int, tint: Color, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text("\(value)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tint.opacity(0.14), in: Capsule())
        }
    }

    private func monthMetricChip(status: String, title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(status)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.14), in: Circle())
            Text("\(count)")
                .font(.subheadline.weight(.bold))
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var statusLegend: some View {
        HStack(spacing: 12) {
            legendItem(status: "P", title: "Práce", color: .green)
            legendItem(status: "V", title: "Volno", color: .blue)
            legendItem(status: "N", title: "Nemoc", color: .red)
        }
        .padding(.horizontal, 4)
    }

    private func legendItem(status: String, title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(status)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ManagerAttendanceFilter.allCases) { filter in
                    filterChip(filter)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func filterChip(_ filter: ManagerAttendanceFilter) -> some View {
        let isSelected = selectedFilter == filter
        let count = count(for: filter)

        return Button {
            withAnimation(.snappy(duration: 0.22)) {
                selectedFilter = filter
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: filter.iconName)
                    .font(.caption.weight(.semibold))
                Text(filter.rawValue)
                    .font(.caption.weight(.semibold))
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.white.opacity(0.22) : Color.primary.opacity(0.08), in: Capsule())
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.accentColor)
                } else {
                    Capsule()
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        .overlay {
                            Capsule()
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func count(for filter: ManagerAttendanceFilter) -> Int {
        switch filter {
        case .all:
            return viewModel.users.count
        case .presentToday:
            return viewModel.presentTodayCount
        case .absentToday:
            return viewModel.absentTodayCount
        }
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Členové týmu")
                    .font(.headline)
                Spacer()
                Text("\(filteredUsers.count) z \(viewModel.users.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            if filteredUsers.isEmpty {
                ContentUnavailableView {
                    Label("Žádné výsledky", systemImage: "magnifyingglass")
                } description: {
                    Text("Zkuste upravit filtr nebo hledaný výraz.")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredUsers) { user in
                        memberCard(user)
                    }
                }
            }
        }
    }

    private func memberCard(_ user: ManagerAttendanceUser) -> some View {
        let notesCount = viewModel.notesCount(for: user)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                memberAvatar(user)

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.displayName(for: user))
                        .font(.headline)
                        .lineLimit(1)
                    if let username = user.username, !username.isEmpty {
                        Text("@\(username)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 6) {
                    statusBadge("P", count: viewModel.statusCount("P", user: user))
                    statusBadge("V", count: viewModel.statusCount("V", user: user))
                    statusBadge("N", count: viewModel.statusCount("N", user: user))
                }
            }

            userDaysRow(user)

            HStack(spacing: 12) {
                Label("\(viewModel.statusCount("P", user: user)) pracovních dnů", systemImage: "briefcase.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if notesCount > 0 {
                    Label("\(notesCount) poznámek", systemImage: "text.bubble.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(cardBackground(tint: statusColor(viewModel.normalizedStatus(viewModel.attendanceStatus(for: user, day: viewModel.todayKey)))))
    }

    private func memberAvatar(_ user: ManagerAttendanceUser) -> some View {
        let todayStatus = viewModel.normalizedStatus(viewModel.attendanceStatus(for: user, day: viewModel.todayKey))
        let tint = statusColor(todayStatus)

        return ZStack(alignment: .bottomTrailing) {
            Group {
                if let url = user.profileImageURL {
                    AuthenticatedProfileImageView(
                        url: url,
                        token: authState.authToken,
                        size: 46
                    )
                } else {
                    Circle()
                        .fill(tint.opacity(0.14))
                        .frame(width: 46, height: 46)
                        .overlay {
                            Text(viewModel.initials(for: user))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(tint)
                        }
                }
            }
            .overlay {
                Circle()
                    .stroke(tint.opacity(0.35), lineWidth: 2)
            }

            Text(todayStatus == "?" ? "?" : todayStatus)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 18, height: 18)
                .background(tint, in: Circle())
                .offset(x: 2, y: 2)
        }
    }

    private func userDaysRow(_ user: ManagerAttendanceUser) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.days, id: \.self) { day in
                    dayCell(user: user, day: day)
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 2)
        }
    }

    private func dayCell(user: ManagerAttendanceUser, day: String) -> some View {
        let entry = user.attendance[day]
        let status = viewModel.normalizedStatus(entry?.status ?? "?")
        let color = statusColor(status)
        let key = "\(user.userId)_\(day)"
        let isToday = viewModel.isToday(day)
        let hasNote = !(entry?.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        return VStack(spacing: 5) {
            Text(dayNumber(day))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isToday ? Color.accentColor : Color.primary)

            Text(weekdayShort(day))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(isToday ? Color.accentColor : Color.secondary)
                .textCase(.uppercase)

            Button {
                selectedCell = AttendanceCellSelection(user: user, day: day, currentStatus: status)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color.opacity(0.16))
                        .frame(width: 36, height: 36)
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(isToday ? Color.accentColor : color.opacity(0.35), lineWidth: isToday ? 2 : 1)
                        }

                    if viewModel.savingKey == key {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text(status)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(color)
                    }
                }
            }
            .buttonStyle(.plain)

            Image(systemName: hasNote ? "text.bubble.fill" : "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(hasNote ? Color.secondary : Color.clear)
                .frame(height: 8)
        }
        .frame(width: 40)
    }

    private func statusBadge(_ status: String, count: Int) -> some View {
        let color = statusColor(status)
        return HStack(spacing: 4) {
            Text(status)
                .font(.caption2.weight(.bold))
            Text("\(count)")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.14), in: Capsule())
    }

    private func monthStepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func cardBackground(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.14),
                                tint.opacity(0.05),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 3)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "P": return .green
        case "V": return .blue
        case "N": return .red
        default: return .secondary
        }
    }

    private func dayNumber(_ day: String) -> String {
        guard let date = Self.dayFormatter.date(from: day) else { return day }
        return Self.dayNumberFormatter.string(from: date)
    }

    private func weekdayShort(_ day: String) -> String {
        guard let date = Self.dayFormatter.date(from: day) else { return "" }
        return Self.weekdayShortFormatter.string(from: date)
    }

    private func dialogDate(_ day: String) -> String {
        guard let date = Self.dayFormatter.date(from: day) else { return day }
        return Self.dayDialogFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let dayNumberFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.timeZone = .current
        f.dateFormat = "d"
        return f
    }()

    private static let weekdayShortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.timeZone = .current
        f.dateFormat = "EEE"
        return f
    }()

    private static let dayDialogFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.timeZone = .current
        f.dateFormat = "dd.MM.yyyy"
        return f
    }()
}

private struct AttendanceCellSelection: Identifiable {
    let user: ManagerAttendanceUser
    let day: String
    let currentStatus: String
    var id: String { "\(user.userId)-\(day)" }
}

#Preview {
    ManagerAttendanceView()
        .environmentObject(AuthState())
}
