//
//  NationalLocalitiesView.swift
//  Provikart
//
//  Prodejní lokality národního manažera (web /admin/dashboard):
//  filtr manažera, přiřazení, stavu a druhu, seznam lokalit s detailem.
//  Sdílené prvky: KPI karty, výběr manažera, avatar.
//

import SwiftUI

// MARK: - ViewModel

@MainActor
final class NationalLocalitiesViewModel: ObservableObject {
    @Published private(set) var items: [SalesLocalityItem] = []
    @Published private(set) var stats = NationalLocalityStats()
    @Published private(set) var facets = NationalLocalityFacets()
    @Published private(set) var managers: [NationalManagerOption] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published var errorMessage: String?
    @Published private(set) var hasMorePages = false

    @Published var searchText = ""
    @Published var managerId: Int?
    @Published var assignment: NationalManagerService.ManagerAssignment = .all
    @Published var doneFilter: Bool?
    @Published var kindFilter: String?

    private let service = NationalManagerService()
    private var page = 1
    private var loadTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var didLoad = false

    var selectedManager: NationalManagerOption? {
        managers.first { $0.id == managerId }
    }

    var hasActiveFilters: Bool {
        managerId != nil || assignment != .all || doneFilter != nil || kindFilter != nil
            || !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func loadIfNeeded(token: String?) async {
        guard !didLoad else { return }
        await load(token: token, reset: true)
    }

    func reload(token: String?) {
        loadTask?.cancel()
        loadTask = Task { await load(token: token, reset: true) }
    }

    func scheduleSearch(token: String?) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            reload(token: token)
        }
    }

    func clearFilters(token: String?) {
        managerId = nil
        assignment = .all
        doneFilter = nil
        kindFilter = nil
        reload(token: token)
    }

    func load(token: String?, reset: Bool) async {
        if reset {
            page = 1
            isLoading = true
        } else {
            guard hasMorePages, !isLoadingMore else { return }
            page += 1
            isLoadingMore = true
        }
        defer {
            isLoading = false
            isLoadingMore = false
        }

        let query = NationalManagerService.LocalitiesQuery(
            q: searchText,
            managerId: managerId,
            assignment: assignment,
            done: doneFilter,
            kind: kindFilter,
            page: page,
            limit: 50
        )
        do {
            let result = try await service.fetchLocalities(token: token, query: query)
            guard !Task.isCancelled else { return }
            if reset {
                items = result.items
            } else {
                let known = Set(items.map(\.id))
                items.append(contentsOf: result.items.filter { !known.contains($0.id) })
            }
            stats = result.stats
            facets = result.facets
            if !result.managers.isEmpty { managers = result.managers }
            if let p = result.pagination {
                hasMorePages = p.page < p.totalPages
            } else {
                hasMorePages = false
            }
            errorMessage = nil
            didLoad = true
        } catch {
            if (error as? URLError)?.code == .cancelled || error is CancellationError { return }
            if !reset { page = max(1, page - 1) }
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

struct NationalLocalitiesView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel = NationalLocalitiesViewModel()
    @State private var showManagerPicker = false

    var body: some View {
        NavigationStack {
            content
                .background { ManagerScreenBackground() }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        ManagerToolbarLogo()
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        filterMenu
                        ProfileBarButton()
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
                .searchable(text: $viewModel.searchText, prompt: "Hledat ROP, obec, ulici…")
                .onChange(of: viewModel.searchText) { _, _ in
                    viewModel.scheduleSearch(token: authState.authToken)
                }
                .task { await viewModel.loadIfNeeded(token: authState.authToken) }
                .refreshable { await viewModel.load(token: authState.authToken, reset: true) }
                .sheet(isPresented: $showManagerPicker) {
                    NationalManagerPickerSheet(
                        managers: viewModel.managers,
                        selectedId: viewModel.managerId,
                        token: authState.authToken,
                        onSelect: { id in
                            viewModel.managerId = id
                            if id != nil { viewModel.assignment = .all }
                            showManagerPicker = false
                            viewModel.reload(token: authState.authToken)
                        }
                    )
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            ProgressView("Načítám lokality…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let message = viewModel.errorMessage, viewModel.items.isEmpty {
            ContentUnavailableView {
                Label("Nepodařilo se načíst", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Zkusit znovu") { viewModel.reload(token: authState.authToken) }
                    .buttonStyle(.bordered)
            }
        } else {
            list
        }
    }

    private var list: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Prodejní lokality")
                        .font(.largeTitle.weight(.bold))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                activeFilterChips
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if viewModel.items.isEmpty {
                ContentUnavailableView(
                    "Žádné lokality",
                    systemImage: "building.2",
                    description: Text(viewModel.hasActiveFilters ? "Zkuste upravit filtry nebo hledání." : "Zatím tu nejsou žádné lokality.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.items) { item in
                    NavigationLink {
                        NationalLocalityDetailView(item: item)
                    } label: {
                        SalesLocalityListSummary(
                            item: item,
                            salesLabel: managerLabel(item),
                            salesMissing: (item.managerUserId ?? 0) == 0
                        )
                    }
                    .padding(16)
                    .background(SVCardBackground(radius: 24, tint: SalesLocalityListSummary.accent(for: item)))
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if viewModel.hasMorePages {
                    HStack {
                        Spacer()
                        if viewModel.isLoadingMore {
                            ProgressView()
                        } else {
                            Button("Načíst další") {
                                Task { await viewModel.load(token: authState.authToken, reset: false) }
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var subtitle: String {
        let total = viewModel.stats.total
        return "\(total.formatted()) \(total == 1 ? "lokalita" : (2...4).contains(total) ? "lokality" : "lokalit")" + (viewModel.hasActiveFilters ? " ve filtru" : "")
    }

    private func managerLabel(_ item: SalesLocalityItem) -> String {
        if let name = item.managerName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return "Bez manažera"
    }

    @ViewBuilder
    private var activeFilterChips: some View {
        if viewModel.managerId != nil || viewModel.assignment != .all || viewModel.doneFilter != nil || viewModel.kindFilter != nil {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let manager = viewModel.selectedManager {
                        SVChip(text: manager.name, icon: "person.fill", tint: SV.accent)
                    }
                    if viewModel.assignment == .unassigned {
                        SVChip(text: "Bez manažera", icon: "exclamationmark", tint: SV.coral)
                    } else if viewModel.assignment == .assigned {
                        SVChip(text: "Přiřazené", icon: "checkmark", tint: SV.good)
                    }
                    if let done = viewModel.doneFilter {
                        SVChip(text: done ? "Hotové" : "Nehotové", icon: done ? "checkmark.seal" : "clock", tint: SV.sky)
                    }
                    if let kind = viewModel.kindFilter {
                        SVChip(text: kind == "rd" ? "Rodinné domy" : "Bytové domy", icon: "house", tint: .secondary)
                    }
                    Button("Zrušit") { viewModel.clearFilters(token: authState.authToken) }
                        .font(.caption.weight(.bold))
                }
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Section("Manažer") {
                Button {
                    DispatchQueue.main.async { showManagerPicker = true }
                } label: {
                    Label(viewModel.selectedManager?.name ?? "Vybrat manažera", systemImage: "person.crop.circle")
                }
                Picker("Přiřazení", selection: Binding(
                    get: { viewModel.managerId == nil ? viewModel.assignment : .assigned },
                    set: { value in
                        viewModel.managerId = nil
                        viewModel.assignment = value
                        viewModel.reload(token: authState.authToken)
                    }
                )) {
                    Text("Vše (\(viewModel.facets.total))").tag(NationalManagerService.ManagerAssignment.all)
                    Text("Bez manažera (\(viewModel.facets.unassignedManager))").tag(NationalManagerService.ManagerAssignment.unassigned)
                    Text("Přiřazené (\(viewModel.facets.assignedManager))").tag(NationalManagerService.ManagerAssignment.assigned)
                }
                .pickerStyle(.inline)
            }
            Section("Stav") {
                Picker("Stav", selection: Binding(
                    get: { viewModel.doneFilter },
                    set: { viewModel.doneFilter = $0; viewModel.reload(token: authState.authToken) }
                )) {
                    Text("Vše").tag(Bool?.none)
                    Text("Nehotové (\(viewModel.facets.open))").tag(Bool?.some(false))
                    Text("Hotové (\(viewModel.facets.done))").tag(Bool?.some(true))
                }
                .pickerStyle(.inline)
            }
            Section("Druh") {
                Picker("Druh", selection: Binding(
                    get: { viewModel.kindFilter },
                    set: { viewModel.kindFilter = $0; viewModel.reload(token: authState.authToken) }
                )) {
                    Text("Vše").tag(String?.none)
                    Text("Bytové domy").tag(String?.some("standard"))
                    Text("Rodinné domy").tag(String?.some("rd"))
                }
                .pickerStyle(.inline)
            }
            if viewModel.hasActiveFilters {
                Section {
                    Button("Vymazat filtry", systemImage: "xmark") {
                        viewModel.clearFilters(token: authState.authToken)
                    }
                }
            }
        } label: {
            Image(systemName: viewModel.managerId != nil || viewModel.assignment != .all || viewModel.doneFilter != nil || viewModel.kindFilter != nil
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filtry")
    }
}

// MARK: - KPI

struct NationalKpiGrid: View {
    let stats: NationalLocalityStats

    private func pct(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1))) + " %"
    }

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                NationalKpiCard(
                    title: "HP",
                    value: stats.hp.formatted(),
                    subtitle: "domácností",
                    tint: SV.sky,
                    footer: hpFooter
                )
                NationalKpiCard(
                    title: "Fiber",
                    value: stats.fiberKs.formatted(),
                    subtitle: "přípojek",
                    tint: SV.lime
                )
            }
            GridRow {
                NationalKpiCard(
                    title: "Penetrace",
                    value: pct(stats.penetrationPct),
                    subtitle: "\(stats.fiberKs.formatted()) / \(stats.opened.formatted()) · Fiber / otevřeno",
                    tint: SV.accent,
                    progress: stats.penetrationPct / 100
                )
                NationalKpiCard(
                    title: "Otevřeno",
                    value: pct(stats.openedPct),
                    subtitle: "\(stats.opened.formatted()) / \(stats.hpCounted > 0 ? stats.hpCounted.formatted() : stats.hp.formatted()) · otevřeno / HP",
                    tint: SV.coral,
                    progress: stats.openedPct / 100
                )
            }
        }
    }

    private var hpFooter: String? {
        var parts: [String] = []
        if stats.hpClosed > 0 { parts.append("Zavřeno \(stats.hpClosed.formatted())") }
        if stats.hpNotTradable > 0 { parts.append("Neobch. \(stats.hpNotTradable.formatted())") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct NationalKpiCard: View {
    let title: String
    let value: String
    let subtitle: String
    let tint: Color
    var progress: Double? = nil
    var footer: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.heavy))
                .tracking(0.8)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let progress {
                ProgressView(value: min(1, max(0, progress)))
                    .tint(tint)
            }
            if let footer {
                Text(footer)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(14)
        .background(SVCardBackground(radius: 22, tint: tint))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Výběr manažera

struct NationalManagerPickerSheet: View {
    let managers: [NationalManagerOption]
    let selectedId: Int?
    let token: String?
    var allowsNone = true
    let onSelect: (Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [NationalManagerOption] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return managers }
        return managers.filter {
            $0.name.lowercased().contains(q) || ($0.team ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if allowsNone {
                    Button {
                        onSelect(nil)
                    } label: {
                        HStack {
                            Label("Všichni manažeři", systemImage: "person.3")
                            Spacer()
                            if selectedId == nil { Image(systemName: "checkmark").foregroundStyle(SV.accent) }
                        }
                    }
                    .foregroundStyle(.primary)
                }
                ForEach(filtered) { manager in
                    Button {
                        onSelect(manager.id)
                    } label: {
                        HStack(spacing: 12) {
                            NationalPersonAvatar(name: manager.name, profileImage: manager.profileImage, token: token)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(manager.name)
                                if let team = manager.team, !team.isEmpty {
                                    Text(team).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if selectedId == manager.id {
                                Image(systemName: "checkmark").foregroundStyle(SV.accent)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .searchable(text: $search, prompt: "Vyhledat manažera…")
            .navigationTitle("Manažer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct NationalPersonAvatar: View {
    let name: String
    let profileImage: String?
    let token: String?
    var size: CGFloat = 34

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let value = parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return value.isEmpty ? "?" : value
    }

    private var url: URL? {
        guard let file = profileImage?.trimmingCharacters(in: .whitespacesAndNewlines), !file.isEmpty else { return nil }
        if file.hasPrefix("http") { return URL(string: file) }
        var comp = URLComponents(string: "https://provikart.cz/auth/serve_image")
        comp?.queryItems = [URLQueryItem(name: "file", value: file)]
        return comp?.url
    }

    var body: some View {
        if let url {
            AuthenticatedProfileImageView(url: url, token: token, size: size)
        } else {
            Circle()
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: size, height: size)
                .overlay {
                    Text(initials)
                        .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
        }
    }
}

// MARK: - Detail lokality (jen pro čtení)

struct NationalLocalityDetailView: View {
    let item: SalesLocalityItem

    var body: some View {
        Form {
            Section {
                SalesLocalityDetailIdentity(item: item)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
            }

            Section("Přiřazení") {
                LabeledContent("Manažer", value: nonEmpty(item.managerName) ?? "Bez manažera")
                LabeledContent("Obchodník", value: nonEmpty(item.salesName) ?? "Bez obchodníka")
            }

            Section("Výkon") {
                LabeledContent("HP", value: item.hp.formatted())
                LabeledContent("Otevřeno", value: item.openedCount.formatted())
                LabeledContent("Fiber", value: item.fiberKs.formatted())
                if let pct = item.openedPct {
                    LabeledContent("Otevřeno %", value: pct.formatted(.number.precision(.fractionLength(0...1))) + " %")
                }
                if let pct = item.penetrationPct {
                    LabeledContent("Penetrace", value: pct.formatted(.number.precision(.fractionLength(0...1))) + " %")
                }
                LabeledContent("ND", value: item.ndCount.formatted())
                LabeledContent("D2D", value: item.d2d ? "Ano" : "Ne")
                LabeledContent("Hotovo", value: item.isDone ? "Ano" : "Ne")
            }

            Section("Lokalita") {
                row("ROP", item.ropId)
                row("RUIAN", item.ruian)
                row("Okres", item.okres)
                row("Obec", item.obec)
                row("Část obce", item.castObce)
                row("Ulice", item.ulice)
                row("Č.P.", item.cisloPopisne)
                row("Č.O.", item.cisloOrientacni)
                row("Komerce", item.komerceDateLabel)
            }

            if nonEmpty(item.majitel) != nil || nonEmpty(item.email) != nil || nonEmpty(item.telefon) != nil || nonEmpty(item.puvodce) != nil {
                Section("Kontakt") {
                    row("Původce", item.puvodce)
                    row("Majitel", item.majitel)
                    if let email = nonEmpty(item.email), let url = URL(string: "mailto:\(email)") {
                        LabeledContent("E‑mail") { Link(email, destination: url) }
                    }
                    if let phone = nonEmpty(item.telefon),
                       let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                        LabeledContent("Telefon") { Link(phone, destination: url) }
                    }
                }
            }

            if let note = nonEmpty(item.note) {
                Section("Poznámka") {
                    Text(note)
                }
            }
        }
        .navigationTitle(item.listTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String?) -> some View {
        if let value = nonEmpty(value) {
            LabeledContent(title, value: value)
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
        return v
    }
}
