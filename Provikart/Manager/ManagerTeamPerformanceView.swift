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
    @State private var compareRoute: ManagerPerformanceCompareRoute?
    @State private var searchText = ""
    @State private var selectedFilter: ManagerPerformanceFilter = .all
    @State private var isLocationsSheetPresented = false
    @State private var showSummary = false
    @State private var isLiveActivitySetupPresented = false
    @State private var daysScrollToken = UUID()
    @Namespace private var filterAnimation

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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ManagerToolbarLogo()
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showSummary = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("Souhrn výkonu")
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
            .sheet(item: $compareRoute) { route in
                ManagerPerformanceCompareView(
                    user: route.user,
                    displayName: viewModel.displayName(for: route.user),
                    monthDate: viewModel.selectedMonthDate,
                    isCurrentMonth: viewModel.isCurrentMonth,
                    todayKey: viewModel.todayKey,
                    token: authState.authToken
                )
            }
            .sheet(isPresented: $showSummary) {
                summarySheet
            }
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
            .sheet(isPresented: $isLiveActivitySetupPresented) {
                NavigationStack {
                    ManagerLiveActivitySetupView(showsCloseButton: true)
                        .environmentObject(authState)
                }
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
            LazyVStack(spacing: 16) {
                monthNavigationCard
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

    private var pageHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Výkon")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                Text("Přehled služeb vašeho týmu")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                isLiveActivitySetupPresented = true
            } label: {
                Image(systemName: "platter.filled.top.and.bottom.iphone")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.indigo)
                    .frame(width: 42, height: 42)
                    .background(Color.indigo.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zobrazit výkon na Lock Screenu")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
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
        HStack(spacing: 8) {
            monthStepButton(systemName: "chevron.left") {
                viewModel.moveMonth(by: -1)
            }

            VStack(spacing: 1) {
                Text(viewModel.monthTitle)
                    .font(.headline)
                Text(viewModel.isCurrentMonth ? "Aktuální měsíc" : "\(viewModel.days.count) dní")
                    .font(.caption2.weight(.medium))
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
                .font(.caption.weight(.bold))
                .foregroundStyle(SV.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(SV.accent, in: Capsule())
            }
        }
        .padding(8)
        .background(SVCardBackground(radius: 22))
    }

    private var summarySheet: some View {
        NavigationStack {
            ScrollView {
                summaryHeroCard
                    .padding(20)
            }
            .background { ManagerScreenBackground() }
            .navigationTitle("Souhrn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hotovo") { showSummary = false }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var summaryHeroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Souhrn")
                    .font(.headline)
                Spacer()
                Text(viewModel.monthTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                compactMetric(
                    title: "Dnes",
                    value: "\(viewModel.todayServicesCount)",
                    icon: "sun.max.fill",
                    color: SV.coral
                )
                compactMetric(
                    title: "Aktivní",
                    value: "\(viewModel.usersWithTodayPerformanceCount)/\(viewModel.users.count)",
                    icon: "person.fill.checkmark",
                    color: .green
                )
                compactMetric(
                    title: "Měsíc",
                    value: "\(viewModel.monthTotal)",
                    icon: "calendar",
                    color: .blue
                )
                compactMetric(
                    title: "Ruční",
                    value: "\(viewModel.manualEntriesCount)",
                    icon: "pencil",
                    color: .indigo
                )
            }
        }
        .padding(14)
        .background(compactSummaryBackground)
    }

    private func compactMetric(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var filterChips: some View {
        HStack(spacing: 4) {
            ForEach(ManagerPerformanceFilter.allCases) { filter in
                filterChip(filter)
            }
        }
        .padding(4)
        .background(SVCardBackground(radius: 22))
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
                Text(filter.rawValue)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isSelected ? SV.onPill.opacity(0.8) : .secondary)
            }
            .foregroundStyle(isSelected ? SV.onPill : Color.primary.opacity(0.84))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            .padding(.vertical, 9)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(SV.pill)
                        .matchedGeometryEffect(id: "performanceFilter", in: filterAnimation)
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
                    .font(.headline.weight(.semibold))
                Spacer()
                Text("\(filteredUsers.count) z \(viewModel.users.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            .padding(.horizontal, 2)

            if filteredUsers.isEmpty {
                ContentUnavailableView {
                    Label("Žádné výsledky", systemImage: "magnifyingglass")
                } description: {
                    Text("Zkuste upravit filtr nebo hledaný výraz.")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(filteredUsers) { user in
                        memberCard(user)
                    }
                }
            }
        }
    }

    private func memberCard(_ user: ManagerPerformanceUser) -> some View {
        let todayCount = viewModel.entry(for: user, day: viewModel.todayKey)?.servicesCount ?? 0
        let hasManual = viewModel.days.contains { viewModel.entry(for: user, day: $0)?.isManual == true }

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    compareRoute = ManagerPerformanceCompareRoute(user: user)
                } label: {
                HStack(alignment: .center, spacing: 12) {
                memberAvatar(user)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(viewModel.displayName(for: user))
                            .font(.headline.weight(.bold))
                            .lineLimit(1)
                        if hasManual {
                            // Ruční zápis jen jako malá ikonka místo štítku.
                            Image(systemName: "pencil.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(SV.sky)
                                .accessibilityLabel("Obsahuje ruční zápis")
                        }
                    }
                    if let username = user.username, !username.isEmpty {
                        Text("@\(username)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Zobrazí srovnání s minulým měsícem")

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(user.total)")
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .tracking(-1.2)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                    Text("služeb za měsíc")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            userDaysRow(user)
        }
        .padding(16)
        .background(memberCardBackground(active: todayCount > 0))
    }

    private func memberAvatar(_ user: ManagerPerformanceUser) -> some View {
        let todayCount = viewModel.entry(for: user, day: viewModel.todayKey)?.servicesCount ?? 0
        let tint: Color = todayCount > 0 ? SV.coral : .secondary

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
        let tint: Color = isManual ? .indigo : (count != nil && (count ?? 0) > 0 ? SV.coral : .secondary)

        return VStack(spacing: 4) {
            Text(weekdayShort(day))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isToday ? SV.coral : Color.secondary)
                .textCase(.uppercase)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                selectedCell = PerformanceCellSelection(user: user, day: day, entry: entry)
            } label: {
                VStack(spacing: 2) {
                    Text(dayNumber(day))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isToday ? SV.coral : Color.primary)
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
                .frame(width: 38, height: 44)
                .background(
                    isToday ? SV.coral.opacity(0.13) : tint.opacity(count == nil ? 0.055 : 0.12),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(isToday ? SV.coral : tint.opacity(0.25), lineWidth: isToday ? 1.5 : 1)
                }
            }
            .buttonStyle(.plain)

            Image(systemName: isManual ? "pencil.circle.fill" : "circle.fill")
                .font(.system(size: 7))
                .foregroundStyle(isManual ? Color.indigo : Color.clear)
                .frame(height: 8)
        }
        .frame(width: 42)
    }

    private func monthStepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.18)))
        }
        .buttonStyle(.plain)
    }

    private var compactSummaryBackground: some View {
        SVCardBackground(radius: 22, tint: SV.coral)
    }

    private func memberCardBackground(active: Bool) -> some View {
        SVCardBackground(radius: 24, tint: active ? SV.coral : .clear)
    }

    private func cardBackground(tint: Color) -> some View {
        SVCardBackground(radius: 22, tint: tint)
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
    /// Kategorie s rozbaleným rychlým výběrem čísla.
    @State private var expanded: PerformanceCategory?
    @State private var barReveal: CGFloat = 0

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

    private var isManual: Bool { selection.entry?.isManual == true }

    private var hasChangesFromAuto: Bool {
        guard let auto = autoBreakdown else {
            return currentBreakdown.total > 0 || isManual
        }
        return currentBreakdown != auto
    }

    private func word(_ n: Int) -> String {
        switch n {
        case 1: return "služba"
        case 2...4: return "služby"
        default: return "služeb"
        }
    }

    private func binding(_ category: PerformanceCategory) -> Binding<Int> {
        switch category {
        case .internet: return $internet
        case .postpaid: return $postpaid
        case .oneplay: return $oneplay
        case .family: return $family
        case .transfer: return $transfer
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    totalCard

                    if canEdit {
                        quickActions
                        VStack(spacing: 10) {
                            ForEach(PerformanceCategory.allCases) { category in
                                categoryRow(category)
                            }
                        }
                    } else {
                        readOnlyBreakdown
                        readOnlyNotice
                    }

                    if let errorMessage, !errorMessage.isEmpty {
                        errorBlock(errorMessage)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
            .background { ManagerScreenBackground() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(displayName)
                            .font(.subheadline.weight(.bold))
                            .lineLimit(1)
                        Text(formattedDate(selection.day))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít") { onCancel() }
                        .disabled(isSaving)
                }
                if canEdit && isManual {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button(role: .destructive) {
                                showClearConfirm = true
                            } label: {
                                Label("Smazat ruční přepis", systemImage: "arrow.uturn.backward")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .disabled(isSaving)
                    }
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
                withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.1)) { barReveal = 1 }
            }
        }
    }

    // MARK: - Celkem

    private var totalCard: some View {
        let total = currentBreakdown.total
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(total)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(total)))
                    .animation(.snappy(duration: 0.22), value: total)
                Text(word(total))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                statusChip
            }

            compositionBar

            if let auto = autoBreakdown {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Z objednávek: \(auto.total)")
                    if hasChangesFromAuto && auto.total != total {
                        Image(systemName: "arrow.right")
                        Text("ručně \(total)")
                            .fontWeight(.bold)
                            .foregroundStyle(Color.indigo)
                        let d = total - auto.total
                        Text(d > 0 ? "(+\(d))" : "(\(d))")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .animation(.snappy, value: total)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SVCardBackground(radius: 22))
    }

    private var statusChip: some View {
        let manual = isManual || hasChangesFromAuto
        return Label(manual ? "Ruční" : "Auto", systemImage: manual ? "pencil" : "bolt.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(manual ? Color.indigo : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background((manual ? Color.indigo : Color.secondary).opacity(0.12), in: Capsule())
            .animation(.snappy, value: manual)
    }

    /// Barevný pruh – podíl kategorií na celku.
    private var compositionBar: some View {
        let total = currentBreakdown.total
        let parts = PerformanceCategory.allCases.filter { value(for: $0, in: currentBreakdown) > 0 }
        return GeometryReader { geo in
            let gaps = CGFloat(max(0, parts.count - 1)) * 3
            let usable = max(0, geo.size.width - gaps) * barReveal
            HStack(spacing: 3) {
                ForEach(parts) { category in
                    Capsule()
                        .fill(category.tint.gradient)
                        .frame(width: total > 0 ? usable * CGFloat(value(for: category, in: currentBreakdown)) / CGFloat(total) : 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentBreakdown)
        }
        .frame(height: 10)
        .clipShape(Capsule())
    }

    // MARK: - Rychlé akce

    private var quickActions: some View {
        HStack(spacing: 8) {
            if let auto = autoBreakdown {
                quickButton("Podle objednávek", icon: "arrow.triangle.2.circlepath", disabled: currentBreakdown == auto) {
                    apply(auto)
                }
            }
            quickButton("Vynulovat", icon: "xmark.circle", disabled: currentBreakdown.total == 0) {
                apply(.init())
            }
            Spacer(minLength: 0)
        }
    }

    private func quickButton(_ title: String, icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.snappy(duration: 0.25)) { action() }
        } label: {
            Label(title, systemImage: icon)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled || isSaving)
        .opacity(disabled ? 0.4 : 1)
    }

    private func apply(_ breakdown: ManagerPerformanceBreakdown) {
        internet = breakdown.internet
        postpaid = breakdown.postpaid
        oneplay = breakdown.oneplay
        family = breakdown.family
        transfer = breakdown.transfer
    }

    // MARK: - Řádek kategorie

    private func categoryRow(_ category: PerformanceCategory) -> some View {
        let value = binding(category)
        let auto = autoBreakdown.map { self.value(for: category, in: $0) }
        let isOpen = expanded == category
        let changed = auto.map { $0 != value.wrappedValue } ?? (value.wrappedValue > 0)

        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        expanded = isOpen ? nil : category
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: category.iconName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(category.tint)
                            .frame(width: 40, height: 40)
                            .background(category.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            if let auto {
                                Text(changed ? "auto \(auto) · upraveno" : "auto \(auto)")
                                    .font(.caption)
                                    .foregroundStyle(changed ? Color.indigo : Color.secondary)
                            }
                        }
                        Spacer(minLength: 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                stepButton("minus", enabled: value.wrappedValue > 0) {
                    value.wrappedValue -= 1
                }

                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        expanded = isOpen ? nil : category
                    }
                } label: {
                    Text("\(value.wrappedValue)")
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(value.wrappedValue > 0 ? Color.primary : Color.secondary)
                        .frame(minWidth: 40, minHeight: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isOpen ? category.tint.opacity(0.16) : Color.clear)
                        )
                        .contentTransition(.numericText(value: Double(value.wrappedValue)))
                        .animation(.snappy(duration: 0.18), value: value.wrappedValue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(category.title): \(value.wrappedValue)")
                .accessibilityHint("Otevře rychlý výběr čísla")

                stepButton("plus", enabled: value.wrappedValue < 9999, tint: category.tint) {
                    value.wrappedValue += 1
                }
            }

            if isOpen {
                quickPicker(category, value: value, auto: auto)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(isOpen ? 0.06 : 0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isOpen ? category.tint.opacity(0.4) : Color.clear, lineWidth: 1)
        )
    }

    private func stepButton(_ icon: String, enabled: Bool, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: icon)
                .font(.body.weight(.bold))
                .frame(width: 40, height: 40)
                .foregroundStyle(enabled ? tint : Color.secondary.opacity(0.4))
                .background((tint == .primary ? Color.primary : tint).opacity(enabled ? 0.12 : 0.05), in: Circle())
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .disabled(!enabled || isSaving)
    }

    /// Rychlý výběr: čísla 0–10 jedním klepnutím (+ víc).
    private func quickPicker(_ category: PerformanceCategory, value: Binding<Int>, auto: Int?) -> some View {
        let upper = max(10, value.wrappedValue + 2)
        let numbers = Array(0...min(upper, 30))
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(numbers, id: \.self) { n in
                        let selected = n == value.wrappedValue
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.snappy(duration: 0.2)) {
                                value.wrappedValue = n
                            }
                        } label: {
                            VStack(spacing: 1) {
                                Text("\(n)")
                                    .font(.headline.monospacedDigit())
                                if n == auto {
                                    Circle().fill(Color.secondary).frame(width: 4, height: 4)
                                } else {
                                    Color.clear.frame(width: 4, height: 4)
                                }
                            }
                            .frame(width: 42, height: 46)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(selected ? category.tint : Color.primary.opacity(0.06))
                            )
                        }
                        .buttonStyle(.plain)
                        .id(n)
                    }
                }
                .padding(.horizontal, 2)
            }
            .onAppear {
                proxy.scrollTo(max(0, value.wrappedValue - 2), anchor: .leading)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if auto != nil {
                Text("• = z objednávek")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .offset(y: 14)
            }
        }
        .padding(.bottom, auto != nil ? 10 : 0)
    }

    // MARK: - Jen pro čtení

    private var readOnlyBreakdown: some View {
        VStack(spacing: 8) {
            ForEach(PerformanceCategory.allCases) { category in
                let count = value(for: category, in: currentBreakdown)
                HStack(spacing: 12) {
                    Image(systemName: category.iconName)
                        .foregroundStyle(category.tint)
                        .frame(width: 32, height: 32)
                        .background(category.tint.opacity(0.14), in: Circle())
                    Text(category.title).font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(count)").font(.headline.monospacedDigit())
                }
                .opacity(count > 0 ? 1 : 0.5)
            }
        }
        .padding(16)
        .background(SVCardBackground(radius: 20))
    }

    private var readOnlyNotice: some View {
        Label("Vlastní výkon nelze upravovat. Můžete zapisovat jen členům svého týmu.", systemImage: "lock.fill")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
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

    // MARK: - Uložení

    private var saveBar: some View {
        let total = currentBreakdown.total
        let unchanged = isManual
            ? currentBreakdown == (selection.entry?.breakdown ?? .init())
            : !hasChangesFromAuto
        return Button {
            Task { await onSave(currentBreakdown) }
        } label: {
            HStack(spacing: 10) {
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3.weight(.semibold))
                }
                Text(isSaving ? "Ukládám…" : "Uložit \(total) \(word(total))")
                    .font(.headline)
                    .contentTransition(.numericText(value: Double(total)))
                    .animation(.snappy, value: total)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .foregroundStyle(.white)
            .background(Color.accentColor.gradient, in: Capsule())
            .shadow(color: Color.accentColor.opacity(0.3), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .opacity(isSaving ? 0.75 : (unchanged ? 0.85 : 1))
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(LinearGradient(colors: [.clear, .black, .black], startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityLabel("Uložit výkon \(total) \(word(total))")
    }

    private func seedValues() {
        if let manual = selection.entry?.breakdown, isManual {
            apply(manual)
        } else if let auto = selection.entry?.autoBreakdown {
            apply(auto)
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
