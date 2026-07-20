//
//  ManagerTeamPerformanceView.swift
//  Provikart
//
//  Manažerský přehled a úprava výkonu týmu.
//

import SwiftUI

private enum ManagerPerformanceFilter: String, CaseIterable, Identifiable {
    case all = "Všichni"
    case withToday = "Dnes mají výkon"
    case manual = "Ruční zápisy"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .all: return "person.3.fill"
        case .withToday: return "chart.bar.fill"
        case .manual: return "pencil.circle.fill"
        }
    }
}

private enum PerformanceCategory: String, CaseIterable, Identifiable {
    case internet
    case postpaid
    case oneplay
    case family
    case transfer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .internet: return "Internet"
        case .postpaid: return "Postpaid"
        case .oneplay: return "OnePlay"
        case .family: return "Family"
        case .transfer: return "Transfer"
        }
    }

    var iconName: String {
        switch self {
        case .internet: return "wifi"
        case .postpaid: return "iphone"
        case .oneplay: return "play.tv"
        case .family: return "person.3"
        case .transfer: return "arrow.left.arrow.right"
        }
    }

    var tint: Color {
        switch self {
        case .internet: return .blue
        case .postpaid: return .green
        case .oneplay: return .orange
        case .family: return .purple
        case .transfer: return .teal
        }
    }
}

@MainActor
final class ManagerTeamPerformanceViewModel: ObservableObject {
    @Published var users: [ManagerPerformanceUser] = []
    @Published var days: [String] = []
    @Published var todayDate: String = ""
    @Published var todayServicesCount: Int = 0
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedMonthDate: Date = Date()
    @Published var savingKey: String?
    @Published var isSaving = false

    private let service = ManagerTeamPerformanceService()

    var monthTitle: String {
        Self.monthTitleFormatter.string(from: selectedMonthDate).capitalized
    }

    var todayKey: String {
        if !todayDate.isEmpty { return todayDate }
        return Self.dayKeyFormatter.string(from: Date())
    }

    var isCurrentMonth: Bool {
        Calendar.current.isDate(selectedMonthDate, equalTo: Date(), toGranularity: .month)
    }

    var monthTotal: Int {
        users.reduce(0) { $0 + $1.total }
    }

    var usersWithTodayPerformanceCount: Int {
        users.filter { (entry(for: $0, day: todayKey)?.servicesCount ?? 0) > 0 }.count
    }

    var manualEntriesCount: Int {
        users.reduce(into: 0) { total, user in
            total += days.filter { entry(for: user, day: $0)?.isManual == true }.count
        }
    }

    func loadPerformance(token: String?) async {
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
            let payload = try await service.fetchPerformance(token: token, month: month)
            users = payload.users
            days = payload.days
            todayDate = payload.todayDate
            todayServicesCount = payload.todayServicesCount
            isLoading = false
        } catch {
            isLoading = false
            guard !Self.isCancellation(error) else { return }
            if users.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    func moveMonth(by offset: Int) {
        guard let updated = Calendar.current.date(byAdding: .month, value: offset, to: selectedMonthDate) else { return }
        selectedMonthDate = updated
    }

    func jumpToCurrentMonth() {
        selectedMonthDate = Date()
    }

    func savePerformance(
        token: String?,
        userId: Int,
        day: String,
        breakdown: ManagerPerformanceBreakdown,
        clear: Bool
    ) async -> Bool {
        guard let token, !token.isEmpty else {
            errorMessage = "Nejste přihlášeni."
            return false
        }

        guard let userIndex = users.firstIndex(where: { $0.userId == userId }) else { return false }
        let key = "\(userId)_\(day)"
        savingKey = key
        isSaving = true
        errorMessage = nil

        let previousUser = users[userIndex]
        let previousEntry = previousUser.performance[day]

        // Optimistická aktualizace
        applyLocalUpdate(
            userIndex: userIndex,
            day: day,
            servicesCount: clear ? (previousEntry?.autoBreakdown?.total) : breakdown.total,
            isManual: !clear,
            breakdown: clear ? nil : breakdown,
            autoBreakdown: previousEntry?.autoBreakdown
        )

        do {
            let result = try await service.updatePerformance(
                token: token,
                userId: userId,
                workDate: day,
                breakdown: clear ? nil : breakdown,
                clear: clear
            )
            applyLocalUpdate(
                userIndex: userIndex,
                day: day,
                servicesCount: result.servicesCount,
                isManual: result.isManual,
                breakdown: result.breakdown,
                autoBreakdown: result.autoBreakdown ?? previousEntry?.autoBreakdown
            )
            if day == todayKey {
                todayServicesCount = users.reduce(0) { partial, user in
                    partial + (user.performance[todayKey]?.servicesCount ?? 0)
                }
            }
            savingKey = nil
            isSaving = false
            return true
        } catch {
            users[userIndex] = previousUser
            savingKey = nil
            isSaving = false
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func applyLocalUpdate(
        userIndex: Int,
        day: String,
        servicesCount: Int?,
        isManual: Bool,
        breakdown: ManagerPerformanceBreakdown?,
        autoBreakdown: ManagerPerformanceBreakdown?
    ) {
        let user = users[userIndex]
        var performance = user.performance
        let previous = performance[day]
        performance[day] = ManagerPerformanceDayEntry(
            attendanceStatus: previous?.attendanceStatus ?? "P",
            attendanceIsDefault: previous?.attendanceIsDefault ?? true,
            servicesCount: servicesCount,
            updatedAt: previous?.updatedAt,
            isManual: isManual,
            breakdown: breakdown,
            autoBreakdown: autoBreakdown
        )
        let newTotal = days.reduce(0) { partial, dateKey in
            partial + (performance[dateKey]?.servicesCount ?? 0)
        }
        users[userIndex] = ManagerPerformanceUser(
            userId: user.userId,
            name: user.name,
            firstname: user.firstname,
            lastname: user.lastname,
            username: user.username,
            profileImage: user.profileImage,
            profileImageURL: user.profileImageURL,
            total: newTotal,
            performance: performance
        )
    }

    func entry(for user: ManagerPerformanceUser, day: String) -> ManagerPerformanceDayEntry? {
        user.performance[day]
    }

    fileprivate func filteredUsers(search: String, filter: ManagerPerformanceFilter) -> [ManagerPerformanceUser] {
        let query = normalizedSearchText(search)
        return users
            .filter { user in
                switch filter {
                case .all:
                    return true
                case .withToday:
                    return (entry(for: user, day: todayKey)?.servicesCount ?? 0) > 0
                case .manual:
                    return days.contains { entry(for: user, day: $0)?.isManual == true }
                }
            }
            .filter { user in
                guard !query.isEmpty else { return true }
                let haystack = searchableText(for: user)
                return query.allSatisfy { haystack.contains($0) }
            }
            .sorted { lhs, rhs in
                if lhs.total != rhs.total {
                    return lhs.total > rhs.total
                }
                return displayName(for: lhs).localizedCaseInsensitiveCompare(displayName(for: rhs)) == .orderedAscending
            }
    }

    func displayName(for user: ManagerPerformanceUser) -> String {
        if !user.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return user.name
        }
        let first = (user.firstname ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (user.lastname ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let full = "\(first) \(last)".trimmingCharacters(in: .whitespacesAndNewlines)
        if !full.isEmpty { return full }
        if let username = user.username, !username.isEmpty { return "@\(username)" }
        return "Uživatel #\(user.userId)"
    }

    func initials(for user: ManagerPerformanceUser) -> String {
        let first = (user.firstname ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (user.lastname ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let f = first.first, let l = last.first {
            return "\(String(f).uppercased())\(String(l).uppercased())"
        }
        if let f = first.first { return String(f).uppercased() }
        if let u = user.username?.first { return String(u).uppercased() }
        return "?"
    }

    func isToday(_ day: String) -> Bool {
        day == todayKey
    }

    func canEdit(userId: Int, viewerId: Int?) -> Bool {
        guard let viewerId else { return false }
        return userId != viewerId
    }

    private func searchableText(for user: ManagerPerformanceUser) -> String {
        let pieces = [
            displayName(for: user),
            "\(user.firstname ?? "") \(user.lastname ?? "")",
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

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        return false
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

struct ManagerTeamPerformanceView: View {
    @EnvironmentObject private var authState: AuthState
    @EnvironmentObject private var performanceBadge: ManagerPerformanceBadgeState
    @StateObject private var viewModel = ManagerTeamPerformanceViewModel()
    @State private var selectedCell: PerformanceCellSelection?
    @State private var searchText = ""
    @State private var selectedFilter: ManagerPerformanceFilter = .all
    @State private var isLocationsSheetPresented = false
    @State private var daysScrollToken = UUID()

    private var filteredUsers: [ManagerPerformanceUser] {
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
            .background { ManagerScreenBackground() }
            .navigationTitle("Výkon týmu")
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
                    ManagerNotificationsBellButton()
                    ProfileBarButton()
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Hledat člena týmu")
            .refreshable {
                await viewModel.loadPerformance(token: authState.authToken)
                performanceBadge.update(todayServicesCount: viewModel.todayServicesCount)
                daysScrollToken = UUID()
            }
            .task {
                await viewModel.loadPerformance(token: authState.authToken)
                performanceBadge.update(todayServicesCount: viewModel.todayServicesCount)
                daysScrollToken = UUID()
            }
            .onChange(of: viewModel.selectedMonthDate) { _, _ in
                Task {
                    await viewModel.loadPerformance(token: authState.authToken)
                    performanceBadge.update(todayServicesCount: viewModel.todayServicesCount)
                    daysScrollToken = UUID()
                }
            }
            .onChange(of: viewModel.todayServicesCount) { _, newValue in
                performanceBadge.update(todayServicesCount: newValue)
            }
            .sheet(item: $selectedCell) { selection in
                PerformanceEditSheet(
                    selection: selection,
                    displayName: viewModel.displayName(for: selection.user),
                    canEdit: viewModel.canEdit(userId: selection.user.userId, viewerId: authState.currentUser?.id),
                    isSaving: viewModel.isSaving,
                    errorMessage: viewModel.errorMessage,
                    onSave: { breakdown in
                        let ok = await viewModel.savePerformance(
                            token: authState.authToken,
                            userId: selection.user.userId,
                            day: selection.day,
                            breakdown: breakdown,
                            clear: false
                        )
                        if ok { selectedCell = nil }
                    },
                    onClear: {
                        let ok = await viewModel.savePerformance(
                            token: authState.authToken,
                            userId: selection.user.userId,
                            day: selection.day,
                            breakdown: .init(),
                            clear: true
                        )
                        if ok { selectedCell = nil }
                    },
                    onCancel: { selectedCell = nil }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isLocationsSheetPresented) {
                ManagerLocationsSheetView()
                    .environmentObject(authState)
            }
            .alert(
                "Chyba",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil && selectedCell == nil && !viewModel.users.isEmpty },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                monthNavigationCard
                summaryHeroCard
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
            Text("Načítám výkon týmu…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Nepodařilo se načíst výkon", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Zkusit znovu") {
                Task {
                    await viewModel.loadPerformance(token: authState.authToken)
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
                todayRing

                VStack(alignment: .leading, spacing: 10) {
                    Text("Dnešní výkon týmu")
                        .font(.headline)
                    Text("\(viewModel.users.count) členů týmu")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 8) {
                        summaryStatRow(
                            title: "Služby dnes",
                            value: viewModel.todayServicesCount,
                            tint: .orange,
                            icon: "chart.bar.fill"
                        )
                        summaryStatRow(
                            title: "Členů s výkonem",
                            value: viewModel.usersWithTodayPerformanceCount,
                            tint: .green,
                            icon: "person.fill.checkmark"
                        )
                    }
                }
            }

            Divider().opacity(0.35)

            HStack(spacing: 8) {
                monthMetricChip(
                    title: "Měsíc celkem",
                    value: "\(viewModel.monthTotal)",
                    color: .orange
                )
                monthMetricChip(
                    title: "Ruční zápisy",
                    value: "\(viewModel.manualEntriesCount)",
                    color: .indigo
                )
                monthMetricChip(
                    title: "Průměr / člen",
                    value: viewModel.users.isEmpty
                        ? "0"
                        : String(format: "%.1f", Double(viewModel.monthTotal) / Double(viewModel.users.count)),
                    color: .teal
                )
            }
        }
        .padding(16)
        .background(cardBackground(tint: .orange))
    }

    private var todayRing: some View {
        let count = viewModel.todayServicesCount
        return ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 8)
            Circle()
                .trim(from: 0, to: min(CGFloat(count) / 20.0, 1))
                .stroke(
                    AngularGradient(
                        colors: [.orange.opacity(0.7), .orange],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(count)")
                    .font(.title3.weight(.bold))
                Text("dnes")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 88, height: 88)
        .accessibilityLabel("Dnes \(count) služeb")
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
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tint.opacity(0.14), in: Capsule())
        }
    }

    private func monthMetricChip(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.subheadline.weight(.bold))
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ManagerPerformanceFilter.allCases) { filter in
                    filterChip(filter)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func filterChip(_ filter: ManagerPerformanceFilter) -> some View {
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
                    Capsule().fill(Color.accentColor)
                } else {
                    Capsule()
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        .overlay {
                            Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func count(for filter: ManagerPerformanceFilter) -> Int {
        switch filter {
        case .all:
            return viewModel.users.count
        case .withToday:
            return viewModel.usersWithTodayPerformanceCount
        case .manual:
            return viewModel.users.filter { user in
                viewModel.days.contains { viewModel.entry(for: user, day: $0)?.isManual == true }
            }.count
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

    private func memberCard(_ user: ManagerPerformanceUser) -> some View {
        let todayCount = viewModel.entry(for: user, day: viewModel.todayKey)?.servicesCount ?? 0

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

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(user.total)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.orange)
                    Text("za měsíc")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            userDaysRow(user)

            HStack(spacing: 12) {
                Label("Dnes \(todayCount)", systemImage: "sun.max.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if viewModel.days.contains(where: { viewModel.entry(for: user, day: $0)?.isManual == true }) {
                    Label("Ruční zápis", systemImage: "pencil")
                        .font(.caption)
                        .foregroundStyle(.indigo)
                }
            }
        }
        .padding(16)
        .background(cardBackground(tint: todayCount > 0 ? .orange : .secondary))
    }

    private func memberAvatar(_ user: ManagerPerformanceUser) -> some View {
        let todayCount = viewModel.entry(for: user, day: viewModel.todayKey)?.servicesCount ?? 0
        let tint: Color = todayCount > 0 ? .orange : .secondary

        return ZStack(alignment: .bottomTrailing) {
            Group {
                if let urlString = user.profileImageURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !urlString.isEmpty,
                   let url = URL(string: urlString) {
                    AuthenticatedProfileImageView(url: url, token: authState.authToken, size: 46)
                } else if let name = user.profileImage?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !name.isEmpty {
                    let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
                    let url = URL(string: "https://provikart.cz/auth/serve_image?file=\(encoded)")
                    if let url {
                        AuthenticatedProfileImageView(url: url, token: authState.authToken, size: 46)
                    } else {
                        initialsAvatar(user, tint: tint)
                    }
                } else {
                    initialsAvatar(user, tint: tint)
                }
            }
            .overlay {
                Circle().stroke(tint.opacity(0.35), lineWidth: 2)
            }

            Text(todayCount > 0 ? "\(min(todayCount, 99))" : "–")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(tint, in: Circle())
                .offset(x: 2, y: 2)
        }
    }

    private func initialsAvatar(_ user: ManagerPerformanceUser, tint: Color) -> some View {
        Circle()
            .fill(tint.opacity(0.14))
            .frame(width: 46, height: 46)
            .overlay {
                Text(viewModel.initials(for: user))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)
            }
    }

    private func userDaysRow(_ user: ManagerPerformanceUser) -> some View {
        let todayKey = viewModel.todayKey
        let shouldScrollToToday = viewModel.isCurrentMonth && viewModel.days.contains(todayKey)

        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.days, id: \.self) { day in
                        dayCell(user: user, day: day)
                            .id(day)
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 2)
            }
            .onAppear {
                guard shouldScrollToToday else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(todayKey, anchor: .leading)
                }
            }
            .onChange(of: daysScrollToken) { _, _ in
                guard shouldScrollToToday else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(todayKey, anchor: .leading)
                }
            }
        }
    }

    private func dayCell(user: ManagerPerformanceUser, day: String) -> some View {
        let entry = viewModel.entry(for: user, day: day)
        let count = entry?.servicesCount
        let isManual = entry?.isManual == true
        let isToday = viewModel.isToday(day)
        let key = "\(user.userId)_\(day)"
        let tint: Color = isManual ? .indigo : (count != nil && (count ?? 0) > 0 ? .orange : .secondary)

        return VStack(spacing: 5) {
            Text(dayNumber(day))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isToday ? Color.accentColor : Color.primary)

            Text(weekdayShort(day))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(isToday ? Color.accentColor : Color.secondary)
                .textCase(.uppercase)

            Button {
                selectedCell = PerformanceCellSelection(user: user, day: day, entry: entry)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(count == nil ? 0.08 : 0.16))
                        .frame(width: 36, height: 36)
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(isToday ? Color.accentColor : tint.opacity(0.35), lineWidth: isToday ? 2 : 1)
                        }

                    if viewModel.savingKey == key {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else if let count {
                        Text("\(count)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(tint)
                    } else {
                        Text("–")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.secondary.opacity(0.5))
                    }
                }
            }
            .buttonStyle(.plain)

            Image(systemName: isManual ? "pencil.circle.fill" : "circle.fill")
                .font(.system(size: 7))
                .foregroundStyle(isManual ? Color.indigo : Color.clear)
                .frame(height: 8)
        }
        .frame(width: 40)
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
                            colors: [tint.opacity(0.14), tint.opacity(0.05), .clear],
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

    private func dayNumber(_ day: String) -> String {
        guard let date = Self.dayFormatter.date(from: day) else { return day }
        return Self.dayNumberFormatter.string(from: date)
    }

    private func weekdayShort(_ day: String) -> String {
        guard let date = Self.dayFormatter.date(from: day) else { return "" }
        return Self.weekdayShortFormatter.string(from: date)
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
}

// MARK: - Edit sheet

private struct PerformanceCellSelection: Identifiable {
    let user: ManagerPerformanceUser
    let day: String
    let entry: ManagerPerformanceDayEntry?
    var id: String { "\(user.userId)-\(day)" }
}

private struct PerformanceEditSheet: View {
    let selection: PerformanceCellSelection
    let displayName: String
    let canEdit: Bool
    let isSaving: Bool
    let errorMessage: String?
    let onSave: (ManagerPerformanceBreakdown) async -> Void
    let onClear: () async -> Void
    let onCancel: () -> Void

    @State private var internet: Int = 0
    @State private var postpaid: Int = 0
    @State private var oneplay: Int = 0
    @State private var family: Int = 0
    @State private var transfer: Int = 0
    @State private var showClearConfirm = false

    private var currentBreakdown: ManagerPerformanceBreakdown {
        ManagerPerformanceBreakdown(
            internet: internet,
            postpaid: postpaid,
            oneplay: oneplay,
            family: family,
            transfer: transfer
        )
    }

    private var autoBreakdown: ManagerPerformanceBreakdown? {
        selection.entry?.autoBreakdown
    }

    private var hasChangesFromAuto: Bool {
        guard let auto = autoBreakdown else {
            return currentBreakdown.total > 0 || selection.entry?.isManual == true
        }
        return currentBreakdown != auto
    }

    private var servicesWord: String {
        let n = currentBreakdown.total
        switch n {
        case 1: return "služba"
        case 2...4: return "služby"
        default: return "služeb"
        }
    }

    private var bindingForCategory: (PerformanceCategory) -> Binding<Int> {
        { category in
            switch category {
            case .internet: return $internet
            case .postpaid: return $postpaid
            case .oneplay: return $oneplay
            case .family: return $family
            case .transfer: return $transfer
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    headerBlock

                    if let auto = autoBreakdown, auto.total > 0 {
                        autoBlock(auto)
                    }

                    if canEdit {
                        editBlock
                    } else {
                        readOnlyNotice
                    }

                    if let errorMessage, !errorMessage.isEmpty {
                        errorBlock(errorMessage)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Úprava výkonu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít") { onCancel() }
                        .disabled(isSaving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if canEdit {
                    saveBar
                }
            }
            .confirmationDialog(
                "Smazat ruční přepis?",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Smazat a vrátit auto výpočet", role: .destructive) {
                    Task { await onClear() }
                }
                Button("Zrušit", role: .cancel) {}
            } message: {
                Text("Výkon se vrátí na automatický výpočet z objednávek.")
            }
            .onAppear {
                seedValues()
            }
        }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(displayName)
                .font(.title2.weight(.bold))
                .lineLimit(2)

            Text(formattedDate(selection.day))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Image(systemName: selection.entry?.isManual == true
                      ? "pencil.circle.fill"
                      : "arrow.triangle.2.circlepath")
                    .font(.body.weight(.semibold))
                Text(selection.entry?.isManual == true
                      ? "Ruční přepis aktivní"
                      : "Automatický výpočet z objednávek")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(selection.entry?.isManual == true ? Color.indigo : Color.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (selection.entry?.isManual == true ? Color.indigo : Color.secondary).opacity(0.1),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sheetCardBackground)
    }

    private func autoBlock(_ auto: ManagerPerformanceBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Automatický výkon")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(PerformanceCategory.allCases) { cat in
                    let count = value(for: cat, in: auto)
                    if count > 0 {
                        HStack(spacing: 10) {
                            Image(systemName: cat.iconName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(cat.tint)
                                .frame(width: 28, height: 28)
                                .background(cat.tint.opacity(0.14), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cat.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(count)")
                                    .font(.title3.weight(.bold))
                                    .monospacedDigit()
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }

            HStack {
                Text("Celkem auto")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(auto.total)")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sheetCardBackground)
    }

    private var editBlock: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ruční zápis")
                    .font(.headline)
                Text("Nastavte počet služeb pro tento den.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 14) {
                ForEach(PerformanceCategory.allCases) { category in
                    categoryEditor(category, value: bindingForCategory(category))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sheetCardBackground)
    }

    private var readOnlyNotice: some View {
        Text("Vlastní výkon nelze upravovat. Můžete zapisovat jen členům svého týmu.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(sheetCardBackground)
    }

    private func errorBlock(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func categoryEditor(_ category: PerformanceCategory, value: Binding<Int>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: category.iconName)
                .font(.body.weight(.semibold))
                .foregroundStyle(category.tint)
                .frame(width: 44, height: 44)
                .background(category.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(category.title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button {
                    if value.wrappedValue > 0 {
                        value.wrappedValue -= 1
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.body.weight(.bold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(value.wrappedValue > 0 ? Color.primary : Color.secondary.opacity(0.4))
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(value.wrappedValue <= 0 || isSaving)

                Text("\(value.wrappedValue)")
                    .font(.title2.weight(.bold).monospacedDigit())
                    .frame(minWidth: 36)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.18), value: value.wrappedValue)

                Button {
                    if value.wrappedValue < 9999 {
                        value.wrappedValue += 1
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.bold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(Color.accentColor)
                        .background(Color.accentColor.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(value.wrappedValue >= 9999 || isSaving)
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var saveBar: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Celkem k uložení")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(currentBreakdown.total)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.2), value: currentBreakdown.total)
                        Text(servicesWord)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                if let auto = autoBreakdown, hasChangesFromAuto {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Auto")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("\(auto.total)")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .strikethrough(currentBreakdown.total != auto.total)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            Button {
                Task { await onSave(currentBreakdown) }
            } label: {
                HStack(spacing: 10) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.regular)
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3.weight(.semibold))
                    }
                    Text(isSaving ? "Ukládám…" : "Uložit výkon")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .foregroundStyle(.white)
                .background(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.82)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .shadow(color: Color.accentColor.opacity(0.3), radius: 12, x: 0, y: 5)
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
            .opacity(isSaving ? 0.75 : 1)
            .accessibilityLabel("Uložit výkon \(currentBreakdown.total) \(servicesWord)")

            if selection.entry?.isManual == true {
                Button {
                    showClearConfirm = true
                } label: {
                    Label("Smazat ruční přepis", systemImage: "arrow.uturn.backward")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.red)
                        .background(
                            Color.red.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    Divider()
                }
        }
    }

    private var sheetCardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            }
    }

    private func seedValues() {
        if let manual = selection.entry?.breakdown, selection.entry?.isManual == true {
            internet = manual.internet
            postpaid = manual.postpaid
            oneplay = manual.oneplay
            family = manual.family
            transfer = manual.transfer
        } else if let auto = selection.entry?.autoBreakdown {
            internet = auto.internet
            postpaid = auto.postpaid
            oneplay = auto.oneplay
            family = auto.family
            transfer = auto.transfer
        }
    }

    private func value(for category: PerformanceCategory, in breakdown: ManagerPerformanceBreakdown) -> Int {
        switch category {
        case .internet: return breakdown.internet
        case .postpaid: return breakdown.postpaid
        case .oneplay: return breakdown.oneplay
        case .family: return breakdown.family
        case .transfer: return breakdown.transfer
        }
    }

    private func formattedDate(_ day: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: day) else { return day }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.dateFormat = "EEEE d. M. yyyy"
        return formatter.string(from: date).capitalized
    }
}

#Preview {
    ManagerTeamPerformanceView()
        .environmentObject(AuthState())
        .environmentObject(ManagerPerformanceBadgeState())
}
