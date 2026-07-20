//
//  ManagerProblemsView.swift
//  Provikart
//
//  Manager varianta stránky Problémy.
//

import SwiftUI

private struct DeleteReportRequest: Identifiable, Equatable {
    let id: Int
    let title: String
}

@MainActor
final class ManagerProblemsViewModel: ObservableObject {
    @Published private(set) var reportsByFilter: [ManagerReportsFilter: [UserReport]] = [:]
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var selectedCategories: Set<ManagerReportsFilter> = [.regular]
    @Published var deferredSalesCount = 0
    @Published var incompleteOrdersCount = 0
    @Published var termSelectionCount = 0
    @Published var regularReportsCount = 0

    private(set) var isRefreshPaused = false

    var getToken: (() -> String?)?
    private let service = ManagerReportsService()
    private let updateService = ReportUpdateService()
    private var pollingTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0

    /// Reporty pro aktuálně vybrané filtry (okamžitě z cache).
    var reports: [UserReport] {
        Self.mergedReports(from: reportsByFilter, categories: selectedCategories)
    }

    /// True, když máme v cache data pro všechny vybrané kategorie.
    var hasCacheForSelection: Bool {
        selectedCategories.allSatisfy { reportsByFilter[$0] != nil }
    }

    func clearReports() {
        reportsByFilter = [:]
    }

    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor in
            // Načti všechny kategorie najednou → přepínání filtrů je pak okamžité.
            await loadReports(silent: false, categories: Set(ManagerReportsFilter.allCases))
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { break }
                await loadReports(silent: true, categories: selectedCategories)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        loadTask?.cancel()
        loadTask = nil
    }

    func categoryCount(for category: ManagerReportsFilter) -> Int {
        switch category {
        case .regular: return regularReportsCount
        case .incompleteOrders: return incompleteOrdersCount
        case .deferredSales: return deferredSalesCount
        case .termSelection: return termSelectionCount
        }
    }

    func isCategorySelected(_ category: ManagerReportsFilter) -> Bool {
        selectedCategories.contains(category)
    }

    func toggleCategory(_ category: ManagerReportsFilter) {
        if selectedCategories.contains(category) {
            guard selectedCategories.count > 1 else { return }
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }

        let selection = selectedCategories
        let missing = selection.filter { reportsByFilter[$0] == nil }

        if missing.isEmpty {
            // Cache hit — seznam se přepne hned, na pozadí tiše obnovíme.
            Task { await loadReports(silent: true, categories: selection) }
        } else if isLoading {
            // Probíhá prefetch všech kategorií — počkáme na něj, UI se přepne z cache.
            return
        } else {
            Task { await loadReports(silent: false, categories: Set(missing)) }
        }
    }

    func pauseRefresh() {
        isRefreshPaused = true
    }

    func resumeRefresh() {
        isRefreshPaused = false
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        return false
    }

    /// Smaže report na serveru a při úspěchu ho odebere ze seznamu.
    func deleteReport(id: Int) async {
        guard let token = getToken?(), !token.isEmpty else {
            errorMessage = "Nejste přihlášeni."
            return
        }
        do {
            try await updateService.deleteManagerReport(id: id, token: token)
            errorMessage = nil
            var next = reportsByFilter
            for key in next.keys {
                next[key]?.removeAll { $0.id == id }
            }
            reportsByFilter = next
            if let regular = reportsByFilter[.regular] {
                regularReportsCount = regular.filter {
                    !$0.isCompleted && $0.managerReportsFilter == .regular
                }.count
            }
            saveManagerWidgetData(from: reports)
        } catch {
            guard !isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func saveManagerWidgetData(from reports: [UserReport]) {
        let open = reports.filter { !$0.isCompleted }
        let preview = open.prefix(5).map {
            WidgetDataStore.ManagerProblemPreview(
                user_name: $0.user_name,
                order_number: $0.order_number,
                note: $0.note
            )
        }
        WidgetDataStore.saveManagerProblems(openCount: open.count, preview: Array(preview))
        let teamSize = WidgetDataStore.managerTeamSize ?? 0
        let presentToday = WidgetDataStore.managerPresentTodayCount ?? 0
        ManagerTeamLiveActivityManager.update(
            openProblems: open.count,
            teamSize: teamSize,
            presentToday: presentToday,
            latestProblemLabel: preview.first?.displayLine
        )
    }

    func loadReports(silent: Bool = false, categories: Set<ManagerReportsFilter>? = nil) async {
        let activeCategories = categories ?? selectedCategories
        guard !activeCategories.isEmpty else { return }

        if silent && (isRefreshPaused || isLoading) { return }

        guard let token = getToken?(), !token.isEmpty else {
            clearReports()
            errorMessage = nil
            isLoading = false
            return
        }

        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        let categoriesToFetch = activeCategories

        if !silent {
            errorMessage = nil
            isLoading = true
        }

        let task = Task { @MainActor in
            do {
                let result = try await service.fetchManagerReports(token: token, filters: categoriesToFetch)
                guard generation == loadGeneration, !Task.isCancelled else { return }

                var next = reportsByFilter
                for (filter, items) in result.reportsByFilter {
                    next[filter] = items
                }
                reportsByFilter = next

                deferredSalesCount = result.deferredSalesCount
                incompleteOrdersCount = result.incompleteOrdersCount
                termSelectionCount = result.termSelectionCount
                if let regular = next[.regular] {
                    regularReportsCount = regular.filter {
                        !$0.isCompleted && $0.managerReportsFilter == .regular
                    }.count
                }

                if !silent {
                    isLoading = false
                    errorMessage = nil
                }
                saveManagerWidgetData(from: reports)
            } catch {
                guard generation == loadGeneration else { return }
                if isCancellation(error) {
                    if !silent { isLoading = false }
                    return
                }
                if !silent {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
        loadTask = task
        await task.value
    }

    private static func mergedReports(
        from cache: [ManagerReportsFilter: [UserReport]],
        categories: Set<ManagerReportsFilter>
    ) -> [UserReport] {
        guard categories.allSatisfy({ cache[$0] != nil }) else { return [] }

        var merged: [UserReport] = []
        var seen = Set<Int>()
        for category in ManagerReportsFilter.allCases where categories.contains(category) {
            for report in cache[category] ?? [] where seen.insert(report.id).inserted {
                merged.append(report)
            }
        }
        return merged.sorted { lhs, rhs in
            let lDate = parseReportDate(lhs.created_at)
            let rDate = parseReportDate(rhs.created_at)
            switch (lDate, rDate) {
            case let (l?, r?): return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.id > rhs.id
            }
        }
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

struct ManagerProblemsView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel = ManagerProblemsViewModel()
    @State private var selectedReport: UserReport?
    @State private var deleteRequest: DeleteReportRequest?
    @State private var isLocationsSheetPresented = false
    let refreshToken: UUID

    private var reports: [UserReport] {
        viewModel.reports
    }

    init(refreshToken: UUID = UUID()) {
        self.refreshToken = refreshToken
    }

    private enum ManagerReportStatus: String {
        case created
        case open
        case completed
        case unknown
    }

    private func normalizedStatus(for report: UserReport) -> ManagerReportStatus {
        switch (report.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "created":
            return .created
        case "open":
            return .open
        case "completed":
            return .completed
        default:
            return .unknown
        }
    }

    /// Aktivní reporty: created + open, seřazené od nejnovějšího vytvoření.
    private var activeReportsSorted: [UserReport] {
        let active = reports.filter {
            let status = normalizedStatus(for: $0)
            return status == .created || status == .open
        }
        return active.sorted {
            let lhs = parseServerDate($0.created_at)
            let rhs = parseServerDate($1.created_at)
            switch (lhs, rhs) {
            case let (l?, r?):
                return l > r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return ($0.id > $1.id)
            }
        }
    }

    private var createdReports: [UserReport] {
        activeReportsSorted.filter { normalizedStatus(for: $0) == .created }
    }

    private var openReports: [UserReport] {
        activeReportsSorted.filter { normalizedStatus(for: $0) == .open }
    }

    var body: some View {
        NavigationStack {
            stackContent
        }
    }

    private var stackContent: some View {
        mainContent
            .modifier(ManagerProblemsNavigationModifier(
                selectedReport: $selectedReport,
                isLocationsSheetPresented: $isLocationsSheetPresented,
                authState: authState
            ))
            .modifier(ManagerProblemsLifecycleModifier(
                viewModel: viewModel,
                authState: authState,
                refreshToken: refreshToken
            ))
            .modifier(DeleteReportConfirmationModifier(
                deleteRequest: $deleteRequest,
                viewModel: viewModel
            ))
    }

    @ViewBuilder
    private var mainContent: some View {
        if let message = viewModel.errorMessage, !viewModel.hasCacheForSelection, !viewModel.isLoading {
            ContentUnavailableView(
                "Nepodařilo se načíst reporty",
                systemImage: "wifi.exclamationmark",
                description: Text(message)
            )
        } else {
            reportsList
        }
    }

    private var reportsList: some View {
        List {
            Section {
                topFilterRow
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            reportSections
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background {
            managerHomeBackground
        }
    }

    private var managerHomeBackground: some View {
        ManagerScreenBackground()
    }

    @ViewBuilder
    private var reportSections: some View {
        if viewModel.isLoading && !viewModel.hasCacheForSelection {
            Section {
                HStack {
                    Spacer()
                    ProgressView("Načítám reporty…")
                    Spacer()
                }
                .padding(.vertical, 24)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        } else if activeReportsSorted.isEmpty {
            Section {
                ContentUnavailableView(
                    emptyCategoryTitle,
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text(emptyCategoryDescription)
                )
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        } else {
            if !createdReports.isEmpty {
                Section {
                    ForEach(createdReports) { report in
                        reportRowButton(report)
                    }
                } header: {
                    reportsSectionHeader(
                        title: "Nové",
                        subtitle: "Čekají na vaši reakci",
                        count: createdReports.count,
                        tint: .orange,
                        icon: "sparkles"
                    )
                }
            }

            if !openReports.isEmpty {
                Section {
                    ForEach(openReports) { report in
                        reportRowButton(report)
                    }
                } header: {
                    reportsSectionHeader(
                        title: "Probíhající",
                        subtitle: "Již se řeší",
                        count: openReports.count,
                        tint: .yellow,
                        icon: "arrow.triangle.2.circlepath"
                    )
                }
            }
        }
    }

    private var emptyCategoryTitle: String {
        if viewModel.selectedCategories.count > 1 {
            return "Žádné aktivní reporty"
        }
        if let only = viewModel.selectedCategories.first {
            switch only {
            case .regular:
                return "Žádné aktivní reporty"
            case .incompleteOrders:
                return "Žádné nedokončené objednávky"
            case .deferredSales:
                return "Žádné odložené prodeje"
            case .termSelection:
                return "Žádné problémy s termínem"
            }
        }
        return "Žádné aktivní reporty"
    }

    private var emptyCategoryDescription: String {
        if viewModel.selectedCategories.count > 1 {
            return "Ve vybraných kategoriích nejsou žádné otevřené reporty."
        }
        if let only = viewModel.selectedCategories.first {
            switch only {
            case .regular:
                return "Všechny běžné reporty jsou momentálně dokončené."
            case .incompleteOrders:
                return "V této kategorii nejsou žádné otevřené nedokončené objednávky."
            case .deferredSales:
                return "V této kategorii nejsou žádné otevřené odložené prodeje."
            case .termSelection:
                return "V této kategorii nejsou žádné otevřené problémy s výběrem termínu."
            }
        }
        return "Vyberte alespoň jednu kategorii."
    }

    private var topFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ManagerReportsFilter.allCases) { category in
                    iosFilterChip(category)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
    }

    private func iosFilterChip(_ category: ManagerReportsFilter) -> some View {
        let isSelected = viewModel.isCategorySelected(category)
        let count = viewModel.categoryCount(for: category)

        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                viewModel.toggleCategory(category)
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: category.icon)
                    .font(.subheadline.weight(.medium))
                    .symbolRenderingMode(.hierarchical)

                Text(category.title)
                    .font(.subheadline.weight(.semibold))

                Text("\(count)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(isSelected ? Color.white.opacity(0.22) : Color.primary.opacity(0.08))
                    .clipShape(Capsule())
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background {
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color(uiColor: .quaternarySystemFill))
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityLabel("\(category.title), \(countLabel(count))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func countLabel(_ count: Int) -> String {
        switch count {
        case 0: return "Žádné aktivní"
        case 1: return "1 aktivní"
        case 2...4: return "\(count) aktivní"
        default: return "\(count) aktivních"
        }
    }

    @ViewBuilder
    private func reportRowButton(_ report: UserReport) -> some View {
        Button {
            selectedReport = report
        } label: {
            managerReportRow(report)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                deleteRequest = DeleteReportRequest(
                    id: report.id,
                    title: report.managerListTitle
                )
            } label: {
                Label("Smazat", systemImage: "trash")
            }
            .tint(.red)
        }
        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func reportsSectionHeader(
        title: String,
        subtitle: String,
        count: Int,
        tint: Color,
        icon: String
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.14))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .textCase(nil)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .textCase(nil)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(uiColor: .tertiarySystemBackground))
                .clipShape(Capsule())
        }
        .padding(.leading, 4)
    }

    private func categoryTint(_ category: ManagerReportsFilter) -> Color {
        switch category {
        case .regular: return .orange
        case .incompleteOrders: return .red
        case .deferredSales: return .purple
        case .termSelection: return .blue
        }
    }

    private func managerReportRow(_ report: UserReport) -> some View {
        let direction = reportDirectionLabel(for: report)
        let status = normalizedStatus(for: report)
        let title = report.managerListTitle
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: rowIcon(for: report))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(leadingBorderColor(for: report))
                    .frame(width: 32, height: 32)
                    .background(leadingBorderColor(for: report).opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if let direction, !direction.isEmpty {
                        Text(direction)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let badge = report.managerIssueTypeBadge,
                              !report.is_deferred_sale_issue {
                        Text(badge)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(leadingBorderColor(for: report))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    statusBadge(for: status)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                }
                .padding(.top, 2)
            }

            HStack(spacing: 6) {
                if let created = report.created_at, !created.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                        Text(formatCzechDate(created))
                    }
                    .lineLimit(1)
                    if let date = parseServerDate(created) {
                        Text("• \(date.formatted(.relative(presentation: .named).locale(Locale(identifier: "cs_CZ"))))")
                            .lineLimit(1)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    leadingBorderColor(for: report).opacity(0.16),
                                    leadingBorderColor(for: report).opacity(0.06),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.16), lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .shadow(color: .black.opacity(0.025), radius: 6, x: 0, y: 2)
    }

    private func statusBadge(for status: ManagerReportStatus) -> some View {
        let color: Color = {
            switch status {
            case .created: return .orange
            case .open: return .yellow
            case .completed: return .green
            case .unknown: return .gray
            }
        }()

        let label: String = {
            switch status {
            case .created: return "Nové"
            case .open: return "Probíhá"
            case .completed: return "Hotovo"
            case .unknown: return "Neznámé"
            }
        }()

        return Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
            .accessibilityLabel("Stav: \(label)")
    }

    private func reportDirectionLabel(for report: UserReport) -> String? {
        let prefix = report.created_by_manager == true ? "Pro: " : "Od: "
        if let fullName = report.user_name?.trimmingCharacters(in: .whitespacesAndNewlines), !fullName.isEmpty {
            return "\(prefix)\(fullName)"
        }
        if let username = report.username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty {
            return "\(prefix)@\(username)"
        }
        return nil
    }

    private func rowIcon(for report: UserReport) -> String {
        if report.is_deferred_sale_issue {
            return "clock.arrow.circlepath"
        }
        if report.is_incomplete_order_issue {
            return "cart.badge.minus"
        }
        if report.is_term_selection_issue {
            return "calendar.badge.exclamationmark"
        }
        if report.created_by_manager == true {
            return "person.2.badge.gearshape.fill"
        }
        return "person.crop.circle.badge.exclamationmark"
    }

    private func leadingBorderColor(for report: UserReport) -> Color {
        if report.is_deferred_sale_issue {
            return .purple
        }
        if report.is_incomplete_order_issue {
            return .red
        }
        if report.is_term_selection_issue {
            return .blue
        }
        if report.created_by_manager == true {
            return .blue
        }
        switch normalizedStatus(for: report) {
        case .created:
            return .orange
        case .open:
            return .yellow
        case .completed, .unknown:
            return .gray
        }
    }

    private func formatCzechDate(_ raw: String) -> String {
        let inputFormats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd"
        ]

        let inFormatter = DateFormatter()
        inFormatter.locale = Locale(identifier: "en_US_POSIX")
        inFormatter.timeZone = .current

        for format in inputFormats {
            inFormatter.dateFormat = format
            if let date = inFormatter.date(from: raw) {
                let out = DateFormatter()
                out.locale = Locale(identifier: "cs_CZ")
                out.timeZone = .current
                out.dateFormat = "dd.MM.yyyy '•' HH:mm"
                return out.string(from: date)
            }
        }
        return raw
    }

    private func parseServerDate(_ raw: String?) -> Date? {
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

private struct ManagerProblemsNavigationModifier: ViewModifier {
    @Binding var selectedReport: UserReport?
    @Binding var isLocationsSheetPresented: Bool
    let authState: AuthState

    func body(content: Content) -> some View {
        content
            .navigationDestination(item: $selectedReport) { report in
                ManagerProblemDetailView(
                    report: report,
                    selectedReport: $selectedReport
                )
                .environmentObject(authState)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ProvikartBrandLogoView(style: .large)
                }
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
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $isLocationsSheetPresented) {
                ManagerLocationsSheetView()
                    .environmentObject(authState)
            }
    }
}

private struct ManagerProblemsLifecycleModifier: ViewModifier {
    @ObservedObject var viewModel: ManagerProblemsViewModel
    @ObservedObject var authState: AuthState
    let refreshToken: UUID

    func body(content: Content) -> some View {
        content
            .refreshable {
                await viewModel.loadReports(categories: Set(ManagerReportsFilter.allCases))
            }
            .background {
                ManagerScreenBackground()
            }
            .onAppear {
                viewModel.getToken = { [authState] in authState.authToken }
                if authState.isLoggedIn {
                    viewModel.startPolling()
                }
            }
            .onChange(of: refreshToken) { _, _ in
                Task { await viewModel.loadReports(categories: viewModel.selectedCategories) }
            }
            .onChange(of: authState.isLoggedIn) { _, isLoggedIn in
                if isLoggedIn {
                    viewModel.startPolling()
                } else {
                    viewModel.stopPolling()
                    viewModel.clearReports()
                }
            }
            .onDisappear {
                viewModel.stopPolling()
            }
    }
}

private struct DeleteReportConfirmationModifier: ViewModifier {
    @Binding var deleteRequest: DeleteReportRequest?
    @ObservedObject var viewModel: ManagerProblemsViewModel

    func body(content: Content) -> some View {
        content
            .alert(
                "Smazat report?",
                isPresented: Binding(
                    get: { deleteRequest != nil },
                    set: { isPresented in
                        if !isPresented {
                            deleteRequest = nil
                        }
                    }
                )
            ) {
                Button("Smazat", role: .destructive) {
                    if let request = deleteRequest {
                        Task { await viewModel.deleteReport(id: request.id) }
                    }
                    deleteRequest = nil
                }
                Button("Zrušit", role: .cancel) {
                    deleteRequest = nil
                }
            } message: {
                Text(alertMessage)
            }
            .onChange(of: deleteRequest) { oldValue, newValue in
                if newValue != nil {
                    viewModel.pauseRefresh()
                } else if oldValue != nil {
                    viewModel.resumeRefresh()
                }
            }
    }

    private var alertMessage: String {
        guard let request = deleteRequest else {
            return "Report bude trvale odstraněn. Tuto akci nelze vrátit."
        }
        return "Report „\(request.title)“ bude trvale odstraněn. Tuto akci nelze vrátit."
    }
}

