//
//  NationalLocationsView.swift
//  Provikart
//
//  Nahlášené lokality pro národního manažera (web /admin/locations):
//  všichni obchodníci ze všech týmů (bez manažerů) a kdo má na daný den nahlášenou lokalitu.
//  Název lokality se národnímu manažerovi nezobrazuje (stejně jako na webu).
//

import SwiftUI

@MainActor
final class NationalLocationsViewModel: ObservableObject {
    struct Row: Identifiable {
        let member: NationalLocationMember
        let entry: NationalLocationEntry?

        var id: Int { member.id }

        var status: ManagerLocationReportStatus {
            guard let entry else { return .missing }
            if entry.isAbsent { return .absent(entry.attendanceStatus ?? "D") }
            return .reported
        }
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all, missing, reported, absent
        var id: String { rawValue }
    }

    struct TeamGroup: Identifiable {
        let name: String
        let rows: [Row]
        var id: String { name }
        var reported: Int { rows.filter { $0.status == .reported }.count }
    }

    @Published var date = Date()
    @Published var filter: Filter = .all
    @Published var searchText = ""
    @Published private(set) var rows: [Row] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let service = NationalManagerService()
    private var didLoad = false

    var reportedCount: Int { rows.filter { $0.status == .reported }.count }
    var missingCount: Int { rows.filter { $0.status == .missing }.count }
    var absentCount: Int { rows.filter { $0.status.isAbsent }.count }

    /// Podíl vyplněných z těch, kdo nejsou nepřítomní.
    var fillRate: Double {
        let expected = rows.count - absentCount
        guard expected > 0 else { return 0 }
        return Double(reportedCount) / Double(expected)
    }

    func count(_ filter: Filter) -> Int {
        switch filter {
        case .all: return rows.count
        case .missing: return missingCount
        case .reported: return reportedCount
        case .absent: return absentCount
        }
    }

    var groups: [TeamGroup] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let visible = rows.filter { row in
            switch filter {
            case .all: break
            case .missing: if row.status != .missing { return false }
            case .reported: if row.status != .reported { return false }
            case .absent: if !row.status.isAbsent { return false }
            }
            guard !q.isEmpty else { return true }
            return row.member.name.lowercased().contains(q) || row.member.teamName.lowercased().contains(q)
        }
        let grouped = Dictionary(grouping: visible) { $0.member.teamName.isEmpty ? "Bez týmu" : $0.member.teamName }
        return grouped
            .map { TeamGroup(name: $0.key, rows: $0.value) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    func loadIfNeeded(token: String?) async {
        guard !didLoad else { return }
        await load(token: token)
    }

    func load(token: String?) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await service.fetchLocations(
                token: token,
                managerId: nil,
                workDate: Self.dayFormatter.string(from: date)
            )
            let byUser = Dictionary(result.entries.map { ($0.userId, $0) }, uniquingKeysWith: { first, _ in first })
            rows = result.members
                .map { Row(member: $0, entry: byUser[$0.userId]) }
                .sorted {
                    if $0.status.sortPriority != $1.status.sortPriority {
                        return $0.status.sortPriority < $1.status.sortPriority
                    }
                    return $0.member.name.localizedCompare($1.member.name) == .orderedAscending
                }
            errorMessage = nil
            didLoad = true
        } catch {
            if (error as? URLError)?.code == .cancelled || error is CancellationError { return }
            errorMessage = error.localizedDescription
        }
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

struct NationalLocationsView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel = NationalLocationsViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nahlášené lokality")
                            .font(.largeTitle.weight(.bold))
                        Text("Kdo z obchodníků má nahlášenou lokalitu")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    dayControls
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    if !viewModel.rows.isEmpty {
                        summaryCard
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)

                        filterPicker
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }

                if viewModel.isLoading && viewModel.rows.isEmpty {
                    ProgressView("Načítám…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .listRowBackground(Color.clear)
                } else if let message = viewModel.errorMessage, viewModel.rows.isEmpty {
                    ContentUnavailableView {
                        Label("Nepodařilo se načíst", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Zkusit znovu") { Task { await viewModel.load(token: authState.authToken) } }
                            .buttonStyle(.bordered)
                    }
                    .listRowBackground(Color.clear)
                } else if viewModel.rows.isEmpty {
                    ContentUnavailableView(
                        "Žádní obchodníci",
                        systemImage: "person.3",
                        description: Text("V týmech zatím nejsou žádní obchodníci.")
                    )
                    .listRowBackground(Color.clear)
                } else if viewModel.groups.isEmpty {
                    ContentUnavailableView(
                        "Nic nenalezeno",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("V tomto filtru nikdo není.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(viewModel.groups) { group in
                        Section {
                            ForEach(group.rows) { row in
                                memberRow(row)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            }
                        } header: {
                            HStack {
                                Text(group.name)
                                Spacer()
                                Text("\(group.reported)/\(group.rows.count)")
                                    .monospacedDigit()
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background { ManagerScreenBackground() }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ManagerToolbarLogo() }
                ToolbarItem(placement: .topBarTrailing) { ProfileBarButton() }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .searchable(text: $viewModel.searchText, prompt: "Obchodník nebo tým")
            .task { await viewModel.loadIfNeeded(token: authState.authToken) }
            .refreshable { await viewModel.load(token: authState.authToken) }
            .onChange(of: viewModel.date) { _, _ in
                Task { await viewModel.load(token: authState.authToken) }
            }
        }
    }

    // MARK: - Den

    private var isToday: Bool { Calendar.current.isDateInToday(viewModel.date) }

    private var dayControls: some View {
        HStack(spacing: 10) {
            Button { shiftDay(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(SVCardBackground(radius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Předchozí den")

            DatePicker("Den", selection: $viewModel.date, in: ...Date(), displayedComponents: .date)
                .labelsHidden()
                .frame(maxWidth: .infinity)

            Button { shiftDay(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(SVCardBackground(radius: 14))
            }
            .buttonStyle(.plain)
            .disabled(isToday)
            .opacity(isToday ? 0.4 : 1)
            .accessibilityLabel("Další den")
        }
    }

    private func shiftDay(_ delta: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: delta, to: viewModel.date) else { return }
        viewModel.date = min(next, Date())
    }

    // MARK: - Souhrn

    private var summaryCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(SV.good.opacity(0.18), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: viewModel.fillRate)
                    .stroke(SV.good, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((viewModel.fillRate * 100).rounded())) %")
                    .font(.subheadline.weight(.bold).monospacedDigit())
            }
            .frame(width: 70, height: 70)
            .animation(.easeOut(duration: 0.4), value: viewModel.fillRate)

            VStack(alignment: .leading, spacing: 6) {
                statLine("Vyplněno", viewModel.reportedCount, SV.good)
                statLine("Nezadáno", viewModel.missingCount, SV.accent)
                statLine("Nepřítomni", viewModel.absentCount, SV.sky)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(SVCardBackground(radius: 22))
    }

    private func statLine(_ title: String, _ value: Int, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }

    private var filterPicker: some View {
        Picker("Filtr", selection: $viewModel.filter) {
            ForEach(NationalLocationsViewModel.Filter.allCases) { f in
                Text("\(label(f)) \(viewModel.count(f))").tag(f)
            }
        }
        .pickerStyle(.segmented)
    }

    private func label(_ filter: NationalLocationsViewModel.Filter) -> String {
        switch filter {
        case .all: return "Vše"
        case .missing: return "Nezadáno"
        case .reported: return "Vyplněno"
        case .absent: return "Pryč"
        }
    }

    // MARK: - Řádek

    private func memberRow(_ row: NationalLocationsViewModel.Row) -> some View {
        let status = row.status
        return HStack(spacing: 12) {
            NationalPersonAvatar(name: row.member.name, profileImage: row.member.profileImage, token: authState.authToken, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.member.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(status.subtitle)
                    if status == .reported, let time = row.entry?.arrivalTime, !time.isEmpty {
                        Text("· příchod \(time)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            SVChip(text: status.badgeText, icon: status.iconName, tint: status.tint)
        }
        .padding(12)
        .background(SVCardBackground(radius: 20, tint: status.tint))
        .accessibilityElement(children: .combine)
    }
}
