//
//  ManagerProblemsView.swift
//  Provikart
//
//  Manager varianta stránky Problémy.
//

import SwiftUI

@MainActor
final class ManagerProblemsViewModel: ObservableObject {
    @Published var reports: [UserReport] = []
    @Published var errorMessage: String?
    @Published var isLoading = false

    var getToken: (() -> String?)?
    private let service = ManagerReportsService()
    private let updateService = ReportUpdateService()
    private var pollingTask: Task<Void, Never>?

    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor in
            await loadReports(silent: false)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { break }
                await loadReports(silent: true)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
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
            reports.removeAll { $0.id == id }
            let incomplete = reports.filter { !$0.isCompleted }.count
            WidgetDataStore.saveReports(incompleteCount: incomplete)
        } catch {
            guard !isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    func loadReports(silent: Bool = false) async {
        guard let token = getToken?(), !token.isEmpty else {
            reports = []
            errorMessage = nil
            isLoading = false
            return
        }
        if !silent {
            errorMessage = nil
            isLoading = true
        }
        do {
            let fetched = try await service.fetchManagerReports(token: token)
            reports = fetched
            if !silent {
                isLoading = false
                errorMessage = nil
            }
            let incomplete = fetched.filter { !$0.isCompleted }.count
            WidgetDataStore.saveReports(incompleteCount: incomplete)
        } catch {
            if isCancellation(error) {
                if !silent {
                    isLoading = false
                }
                return
            }
            if !silent {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

struct ManagerProblemsView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel = ManagerProblemsViewModel()
    @State private var selectedFilter: TopFilter = .allActive
    @State private var selectedReport: UserReport?
    let refreshToken: UUID

    private var reports: [UserReport] {
        viewModel.reports
    }

    private enum TopFilter: String, CaseIterable, Identifiable {
        case allActive = "Vše aktivní"
        case created = "Vytvořeno"
        case open = "Otevřeno"

        var id: String { rawValue }
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

    private var visibleReports: [UserReport] {
        switch selectedFilter {
        case .allActive:
            return activeReportsSorted
        case .created:
            return activeReportsSorted.filter { normalizedStatus(for: $0) == .created }
        case .open:
            return activeReportsSorted.filter { normalizedStatus(for: $0) == .open }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.reports.isEmpty {
                    ProgressView("Načítám reporty…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let message = viewModel.errorMessage, viewModel.reports.isEmpty {
                    ContentUnavailableView(
                        "Nepodařilo se načíst reporty",
                        systemImage: "wifi.exclamationmark",
                        description: Text(message)
                    )
                } else if activeReportsSorted.isEmpty {
                    ContentUnavailableView(
                        "Žádné aktivní reporty",
                        systemImage: "checkmark.circle",
                        description: Text("Všechny reporty jsou momentálně dokončené.")
                    )
                } else {
                    List {
                        Section {
                            topFilterRow
                                .padding(.vertical, 4)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                        if visibleReports.isEmpty {
                            Section {
                                ContentUnavailableView(
                                    "Žádné položky ve filtru",
                                    systemImage: "line.3.horizontal.decrease.circle",
                                    description: Text("Zkuste přepnout filtr na jiný stav.")
                                )
                                .frame(maxWidth: .infinity)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        } else {
                            Section("Aktivní reporty") {
                                ForEach(visibleReports) { report in
                                    Button {
                                        selectedReport = report
                                    } label: {
                                        managerReportRow(report)
                                    }
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            Task { await viewModel.deleteReport(id: report.id) }
                                        } label: {
                                            Label("Smazat", systemImage: "trash")
                                        }
                                    }
                                    .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color(uiColor: .systemGroupedBackground))
                }
            }
            .navigationDestination(item: $selectedReport) { report in
                ManagerProblemDetailView(
                    report: report,
                    selectedReport: $selectedReport
                )
                .environmentObject(authState)
            }
            .navigationTitle("Provikart")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileBarButton()
                }
            }
            .refreshable {
                await viewModel.loadReports()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .onAppear {
                viewModel.getToken = { [authState] in authState.authToken }
                if authState.isLoggedIn {
                    viewModel.startPolling()
                }
            }
            .onChange(of: authState.isLoggedIn) { _, isLoggedIn in
                if isLoggedIn {
                    viewModel.startPolling()
                } else {
                    viewModel.stopPolling()
                    viewModel.reports = []
                }
            }
            .onChange(of: refreshToken) { _, _ in
                Task { await viewModel.loadReports() }
            }
            .onDisappear {
                viewModel.stopPolling()
            }
        }
    }

    private var topFilterRow: some View {
        HStack(spacing: 8) {
            ForEach(TopFilter.allCases) { filter in
                let isSelected = filter == selectedFilter
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedFilter = filter
                    }
                } label: {
                    Text(filter.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color(uiColor: .secondarySystemBackground))
                        )
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(isSelected ? Color.accentColor.opacity(0.55) : Color(uiColor: .separator).opacity(0.25), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }

    private func managerReportRow(_ report: UserReport) -> some View {
        let direction = reportDirectionLabel(for: report)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(report.order_number ?? "Objednávka bez čísla")
                    .font(.headline)
                Spacer()
                if let direction, !direction.isEmpty {
                    Text(direction)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .tertiarySystemBackground))
                    .clipShape(Capsule())
                }
            }

            HStack(spacing: 12) {
                if let created = report.created_at, !created.isEmpty {
                    Label(formatCzechDate(created), systemImage: "calendar")
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
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.2), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(leadingBorderColor(for: report))
                .frame(width: 5)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
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

    private func leadingBorderColor(for report: UserReport) -> Color {
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
                out.dateFormat = "d. M. yyyy HH:mm"
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
