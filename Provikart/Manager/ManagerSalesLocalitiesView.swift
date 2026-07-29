//
//  ManagerSalesLocalitiesView.swift
//  Provikart
//
//  Prodejní lokality manažera – přehled, úpravy a přiřazení obchodníkům.
//

import SwiftUI

enum ManagerSalesAssignmentFilter: String, CaseIterable, Identifiable {
    case all = "Vše"
    case unassigned = "Bez obchodníka"
    case assigned = "Přiřazené"

    var id: String { rawValue }

    var apiFilter: ManagerSalesLocalitiesService.AssignmentFilter {
        switch self {
        case .all: return .all
        case .unassigned: return .unassigned
        case .assigned: return .assigned
        }
    }
}

// MARK: - ViewModel

@MainActor
final class ManagerSalesLocalitiesViewModel: ObservableObject {
    @Published var items: [SalesLocalityItem] = []
    @Published var stats: SalesLocalityStats = .empty
    @Published var facets: ManagerSalesLocalityFacets = .empty
    @Published var editableFields: [String] = []
    @Published var permissions: ManagerSalesLocalityPermissions = .default
    @Published var searchText = ""
    @Published var doneFilter: SalesLocalityDoneFilter = .all
    @Published var assignmentFilter: ManagerSalesAssignmentFilter = .all
    @Published var selectedSalesFilterId: Int? = nil
    @Published var teamMembers: [ManagerTeamMember] = []
    @Published var selectedIds: Set<Int> = []
    @Published var isSelectionMode = false
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var isAssigning = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?

    private let service = ManagerSalesLocalitiesService()
    private let teamService = ManagerTeamMembersService()
    private var pagination = SalesLocalityPagination(page: 1, pageSize: 50, total: 0, totalPages: 1)
    private var loadGeneration = 0
    private var searchTask: Task<Void, Never>?
    private var filterTask: Task<Void, Never>?

    var hasMorePages: Bool {
        pagination.page < pagination.totalPages
    }

    var canAssignSales: Bool {
        permissions.canAssignSales
            || editableFields.contains("sales_user_id")
            || editableFields.isEmpty
    }

    var canEditFiber: Bool { editableFields.contains("fiber_ks") || editableFields.isEmpty }
    var canEditOpened: Bool { editableFields.contains("opened_count") || editableFields.isEmpty }
    var canEditDone: Bool { editableFields.contains("is_done") || editableFields.isEmpty }
    var canEditNote: Bool { editableFields.contains("note") }
    var canEditMajitel: Bool { editableFields.contains("majitel") }
    var canEditEmail: Bool { editableFields.contains("email") }
    var canEditTelefon: Bool { editableFields.contains("telefon") }
    var canEditHp: Bool { editableFields.contains("hp") }
    var canEditD2d: Bool { editableFields.contains("d2d") }

    var salesMembers: [ManagerTeamMember] {
        teamMembers.filter {
            let role = ($0.role ?? "user").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return role.isEmpty || role == "user"
        }
        .sorted {
            Self.memberDisplayName($0).localizedCaseInsensitiveCompare(Self.memberDisplayName($1)) == .orderedAscending
        }
    }

    var hasActiveFilters: Bool {
        doneFilter != .all
            || assignmentFilter != .all
            || selectedSalesFilterId != nil
            || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasActiveQuickFilters: Bool {
        doneFilter != .all || assignmentFilter != .all || selectedSalesFilterId != nil
    }

    var resultsCaption: String {
        let total = pagination.total
        if total == 0 { return "Žádné lokality" }
        if items.count >= total {
            return total == 1 ? "1 lokalita" : "\(total) lokalit"
        }
        return "\(items.count) z \(total)"
    }

    var selectedSalesMember: ManagerTeamMember? {
        guard let selectedSalesFilterId else { return nil }
        return salesMembers.first(where: { $0.id == selectedSalesFilterId })
    }

    func clearQuickFilters() {
        doneFilter = .all
        assignmentFilter = .all
        selectedSalesFilterId = nil
    }

    func setDoneFilter(_ filter: SalesLocalityDoneFilter) {
        doneFilter = filter
    }

    func setAssignmentFilter(_ filter: ManagerSalesAssignmentFilter) {
        assignmentFilter = filter
        if filter == .unassigned {
            selectedSalesFilterId = nil
        }
    }

    func setSalesFilter(_ id: Int?) {
        selectedSalesFilterId = id
        if id != nil {
            assignmentFilter = .assigned
        }
    }

    func scheduleSearchReload(token: String?) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await load(token: token, reset: true)
        }
    }

    func scheduleFilterReload(token: String?) {
        filterTask?.cancel()
        filterTask = Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            await load(token: token, reset: true)
        }
    }

    func loadTeamMembers(token: String?) async {
        guard let token, !token.isEmpty else { return }
        do {
            teamMembers = try await teamService.fetchMembers(token: token)
        } catch {
            // Picker může zůstat prázdný – seznam lokalit je prioritní.
        }
    }

    func load(token: String?, reset: Bool = true) async {
        guard let token, !token.isEmpty else {
            items = []
            stats = .empty
            facets = .empty
            errorMessage = "Nejste přihlášeni."
            return
        }

        loadGeneration += 1
        let generation = loadGeneration
        let page = reset ? 1 : pagination.page + 1

        if reset {
            isLoading = true
            errorMessage = nil
        } else {
            guard hasMorePages, !isLoadingMore else { return }
            isLoadingMore = true
        }

        do {
            let result = try await service.fetchLocalities(
                token: token,
                query: .init(
                    q: searchText,
                    done: doneFilter.doneValue,
                    assignment: assignmentFilter.apiFilter,
                    salesId: selectedSalesFilterId,
                    page: page,
                    limit: 50
                )
            )
            guard generation == loadGeneration else { return }

            if reset {
                items = result.items
                selectedIds = selectedIds.intersection(Set(result.items.map(\.id)))
            } else {
                let existing = Set(items.map(\.id))
                items.append(contentsOf: result.items.filter { !existing.contains($0.id) })
            }
            stats = result.stats
            facets = result.facets
            pagination = result.pagination
            permissions = result.permissions
            if !result.editableFields.isEmpty {
                editableFields = result.editableFields
            }
            isLoading = false
            isLoadingMore = false
        } catch {
            guard generation == loadGeneration else { return }
            isLoading = false
            isLoadingMore = false
            if Self.isCancellation(error) { return }
            if items.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    func replaceItem(_ item: SalesLocalityItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        }
    }

    func updateLocality(
        token: String?,
        id: Int,
        fields: SalesLocalityUpdateFields
    ) async throws -> SalesLocalityItem {
        guard let token, !token.isEmpty else {
            throw ManagerSalesLocalitiesError.notAuthenticated
        }
        let result = try await service.updateLocality(token: token, id: id, fields: fields)
        if !result.editableFields.isEmpty {
            editableFields = result.editableFields
        }
        replaceItem(result.item)
        infoMessage = "Uloženo."
        return result.item
    }

    func assignSelected(token: String?, salesUserId: Int?) async -> Bool {
        guard canAssignSales else { return false }
        let ids = Array(selectedIds)
        guard !ids.isEmpty else {
            errorMessage = "Vyberte alespoň jednu lokalitu."
            return false
        }
        guard let token, !token.isEmpty else {
            errorMessage = "Nejste přihlášeni."
            return false
        }

        isAssigning = true
        defer { isAssigning = false }

        do {
            let result = try await service.assignSales(
                token: token,
                localityIds: ids,
                salesUserId: salesUserId
            )
            infoMessage = result.message ?? (salesUserId == nil || salesUserId == 0
                ? "Odebráno: \(result.updated)."
                : "Přiřazeno: \(result.updated).")
            if !result.errors.isEmpty {
                errorMessage = result.errors.joined(separator: "\n")
            }
            selectedIds.removeAll()
            isSelectionMode = false
            await load(token: token, reset: true)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func toggleSelection(_ id: Int) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
            if selectedIds.isEmpty {
                isSelectionMode = false
            }
        } else {
            selectedIds.insert(id)
        }
    }

    func beginSelection(with id: Int) {
        isSelectionMode = true
        selectedIds = [id]
    }

    func exitSelectionMode() {
        isSelectionMode = false
        selectedIds.removeAll()
    }

    static func memberDisplayName(_ member: ManagerTeamMember) -> String {
        if let name = member.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        let parts = [member.firstname, member.lastname]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " ") }
        if let username = member.username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty {
            return username
        }
        return "Uživatel #\(member.id)"
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        return false
    }
}

// MARK: - Seznam

struct ManagerSalesLocalitiesView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel = ManagerSalesLocalitiesViewModel()
    @State private var isLocationsSheetPresented = false
    @State private var showAssignPicker = false
    @State private var showSalesFilterSheet = false

    var body: some View {
        NavigationStack {
            rootContent
                .background { ManagerScreenBackground() }
                .navigationTitle("Lokality")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .searchable(text: $viewModel.searchText, prompt: "Ulice, obec, majitel…")
                .modifier(ManagerSalesLocalitiesLifecycleModifier(viewModel: viewModel, authToken: authState.authToken))
                .sheet(isPresented: $isLocationsSheetPresented) {
                    ManagerLocationsSheetView()
                        .environmentObject(authState)
                }
                .sheet(isPresented: $showAssignPicker) {
                    assignPickerSheet
                }
                .sheet(isPresented: $showSalesFilterSheet) {
                    ManagerSalesFilterSheet(
                        members: viewModel.salesMembers,
                        selectedId: viewModel.selectedSalesFilterId,
                        authToken: authState.authToken,
                        onSelect: { id in
                            viewModel.setSalesFilter(id)
                            showSalesFilterSheet = false
                        },
                        onClear: {
                            viewModel.setSalesFilter(nil)
                            showSalesFilterSheet = false
                        },
                        onCancel: { showSalesFilterSheet = false }
                    )
                }
                .alert("Chyba", isPresented: errorAlertBinding) {
                    Button("OK") { viewModel.errorMessage = nil }
                } message: {
                    Text(viewModel.errorMessage ?? "")
                }
                .alert("Hotovo", isPresented: infoAlertBinding) {
                    Button("OK") { viewModel.infoMessage = nil }
                } message: {
                    Text(viewModel.infoMessage ?? "")
                }
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            ProgressView("Načítám lokality…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let message = viewModel.errorMessage, viewModel.items.isEmpty {
            errorState(message)
        } else {
            listContent
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            if viewModel.isSelectionMode {
                Button("Zrušit") {
                    withAnimation(.snappy(duration: 0.25)) {
                        viewModel.exitSelectionMode()
                    }
                }
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if viewModel.isSelectionMode {
                Button {
                    showAssignPicker = true
                } label: {
                    if viewModel.isAssigning {
                        ProgressView()
                    } else {
                        Text("Přiřadit (\(viewModel.selectedIds.count))")
                    }
                }
                .disabled(viewModel.selectedIds.isEmpty || viewModel.isAssigning || !viewModel.canAssignSales)
            } else {
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
    }

    private var assignPickerSheet: some View {
        ManagerSalesAssignPickerSheet(
            members: viewModel.salesMembers,
            selectedId: nil,
            authToken: authState.authToken,
            isAssigning: viewModel.isAssigning,
            onConfirm: { salesId in
                Task {
                    let ok = await viewModel.assignSelected(
                        token: authState.authToken,
                        salesUserId: salesId
                    )
                    if ok {
                        showAssignPicker = false
                    }
                }
            },
            onCancel: {
                showAssignPicker = false
            }
        )
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil && !viewModel.items.isEmpty },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    private var infoAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.infoMessage != nil },
            set: { if !$0 { viewModel.infoMessage = nil } }
        )
    }

    private var listContent: some View {
        List {
            filtersSection

            if viewModel.items.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Žádné lokality",
                        systemImage: "building.2",
                        description: Text(
                            viewModel.hasActiveFilters
                                ? "Zkuste upravit filtry nebo hledání."
                                : "Nemáte zatím žádné lokality."
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.items) { item in
                    Section {
                        localityListRow(item)
                            .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                    }
                }

                if viewModel.hasMorePages {
                    Section {
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
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(12)
        .animation(.default, value: viewModel.isSelectionMode)
    }

    private var filtersSection: some View {
        Section {
            Picker(
                "Stav",
                selection: Binding(
                    get: { viewModel.doneFilter },
                    set: { viewModel.setDoneFilter($0) }
                )
            ) {
                ForEach(SalesLocalityDoneFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            .listRowSeparator(.hidden)

            Picker(
                "Přiřazení",
                selection: Binding(
                    get: { viewModel.assignmentFilter },
                    set: { newValue in
                        viewModel.setAssignmentFilter(newValue)
                        if newValue != .assigned {
                            viewModel.setSalesFilter(nil)
                        }
                    }
                )
            ) {
                Text("Vše").tag(ManagerSalesAssignmentFilter.all)
                Text("Bez obchodníka (\(viewModel.facets.unassignedSales))")
                    .tag(ManagerSalesAssignmentFilter.unassigned)
                Text("Přiřazené (\(viewModel.facets.assignedSales))")
                    .tag(ManagerSalesAssignmentFilter.assigned)
            }

            if viewModel.assignmentFilter != .unassigned {
                Button {
                    showSalesFilterSheet = true
                } label: {
                    HStack(spacing: 12) {
                        if let member = viewModel.selectedSalesMember {
                            ManagerSalesMemberAvatar(member: member, token: authState.authToken, size: 28)
                        } else {
                            Image(systemName: "person.crop.circle")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                        }

                        Text("Obchodník")
                            .foregroundStyle(.primary)

                        Spacer(minLength: 8)

                        Text(salesFilterValueLabel)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            HStack {
                Text("Filtry")
                Spacer()
                if viewModel.hasActiveQuickFilters {
                    Button("Vymazat") {
                        viewModel.clearQuickFilters()
                    }
                    .font(.footnote)
                    .textCase(nil)
                }
            }
        } footer: {
            Text(filtersFooterText)
        }
    }

    private var salesFilterValueLabel: String {
        if let member = viewModel.selectedSalesMember {
            return ManagerSalesLocalitiesViewModel.memberDisplayName(member)
        }
        return viewModel.assignmentFilter == .assigned ? "Kdokoli" : "Všichni"
    }

    private var filtersFooterText: String {
        var parts: [String] = [viewModel.resultsCaption]
        if viewModel.doneFilter == .all {
            parts.append("rozpracované \(viewModel.facets.open) · hotovo \(viewModel.facets.done)")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func localityListRow(_ item: SalesLocalityItem) -> some View {
        let isSelected = viewModel.selectedIds.contains(item.id)

        if viewModel.isSelectionMode {
            Button {
                viewModel.toggleSelection(item.id)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .padding(.top, 2)
                        .accessibilityHidden(true)

                    ManagerSalesLocalityRow(item: item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.addressTitle)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityHint("Klepnutím přepnete výběr")
        } else {
            NavigationLink {
                ManagerSalesLocalityDetailView(item: item, viewModel: viewModel)
                    .environmentObject(authState)
            } label: {
                ManagerSalesLocalityRow(item: item)
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45)
                    .onEnded { _ in
                        guard viewModel.canAssignSales else { return }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        viewModel.beginSelection(with: item.id)
                    }
            )
            .accessibilityHint(viewModel.canAssignSales ? "Podržením vyberete pro přiřazení" : "")
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Zkusit znovu") {
                Task { await viewModel.load(token: authState.authToken, reset: true) }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ManagerSalesLocalitiesLifecycleModifier: ViewModifier {
    @ObservedObject var viewModel: ManagerSalesLocalitiesViewModel
    let authToken: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: viewModel.searchText) { _, _ in
                viewModel.scheduleSearchReload(token: authToken)
            }
            .onChange(of: viewModel.doneFilter) { _, _ in
                viewModel.scheduleFilterReload(token: authToken)
            }
            .onChange(of: viewModel.assignmentFilter) { _, _ in
                viewModel.scheduleFilterReload(token: authToken)
            }
            .onChange(of: viewModel.selectedSalesFilterId) { _, _ in
                viewModel.scheduleFilterReload(token: authToken)
            }
            .refreshable {
                await viewModel.load(token: authToken, reset: true)
            }
            .task {
                await viewModel.loadTeamMembers(token: authToken)
                await viewModel.load(token: authToken, reset: true)
            }
    }
}

// MARK: - Sheet filtru obchodníka

private struct ManagerSalesMemberAvatar: View {
    let member: ManagerTeamMember
    let token: String?
    var size: CGFloat = 36

    var body: some View {
        Group {
            if let url = member.profileImageURL {
                AuthenticatedProfileImageView(url: url, token: token, size: size)
            } else {
                Circle()
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(width: size, height: size)
                    .overlay {
                        Text(member.initials)
                            .font(.system(size: size * 0.34, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct ManagerSalesMemberPickRow: View {
    let member: ManagerTeamMember
    let token: String?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            ManagerSalesMemberAvatar(member: member, token: token, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName)
                    .foregroundStyle(.primary)
                if let username = member.username?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !username.isEmpty {
                    Text("@\(username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct ManagerSalesFilterSheet: View {
    let members: [ManagerTeamMember]
    let selectedId: Int?
    let authToken: String?
    let onSelect: (Int) -> Void
    let onClear: () -> Void
    let onCancel: () -> Void

    @State private var query = ""

    private var filteredMembers: [ManagerTeamMember] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return members }
        return members.filter {
            $0.displayName.lowercased().contains(trimmed)
                || ($0.username?.lowercased().contains(trimmed) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onClear()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.3.fill")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .frame(width: 36, height: 36)
                                .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                            Text("Všichni obchodníci")
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedId == nil {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    if members.isEmpty {
                        Text("Žádní členové týmu.")
                            .foregroundStyle(.secondary)
                    } else if filteredMembers.isEmpty {
                        Text("Nikdo neodpovídá hledání.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredMembers) { member in
                            Button {
                                onSelect(member.id)
                            } label: {
                                ManagerSalesMemberPickRow(
                                    member: member,
                                    token: authToken,
                                    isSelected: selectedId == member.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Tým")
                }
            }
            .navigationTitle("Filtrovat obchodníka")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Hledat v týmu")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít", action: onCancel)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Řádek

private struct ManagerSalesLocalityRow: View {
    let item: SalesLocalityItem

    private var streetLine: String {
        let street = item.ulice?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if street.isEmpty { return "Bez názvu ulice" }
        return street
    }

    private var cityLine: String? {
        var parts: [String] = []
        if let cast = item.castObce?.trimmingCharacters(in: .whitespacesAndNewlines), !cast.isEmpty,
           cast.caseInsensitiveCompare(item.obec ?? "") != .orderedSame {
            parts.append(cast)
        }
        if let obec = item.obec?.trimmingCharacters(in: .whitespacesAndNewlines), !obec.isEmpty {
            parts.append(obec)
        }
        if let okres = item.okres?.trimmingCharacters(in: .whitespacesAndNewlines), !okres.isEmpty,
           okres.caseInsensitiveCompare(item.obec ?? "") != .orderedSame {
            parts.append(okres)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var houseNumberSuffix: String? {
        if let popisne = item.cisloPopisne?.trimmingCharacters(in: .whitespacesAndNewlines), !popisne.isEmpty {
            if let orientacni = item.cisloOrientacni?.trimmingCharacters(in: .whitespacesAndNewlines), !orientacni.isEmpty {
                return "č.p. \(popisne)/\(orientacni)"
            }
            return "č.p. \(popisne)"
        }
        if let orientacni = item.cisloOrientacni?.trimmingCharacters(in: .whitespacesAndNewlines), !orientacni.isEmpty {
            return "č.o. \(orientacni)"
        }
        if let house = item.houseNumberLabel {
            return "č.p. \(house)"
        }
        return nil
    }

    private var salesLabel: String {
        if let name = item.salesName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return "Bez obchodníka"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(streetLine)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)

                        if let houseNumberSuffix {
                            Text("|")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.tertiary)

                            Text(houseNumberSuffix)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    if let cityLine {
                        Text(cityLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                        Text(salesLabel)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(item.salesUserId == nil || item.salesUserId == 0 ? Color.orange : Color.secondary)
                }

                Spacer(minLength: 8)
                statusBadge
            }

            VStack(spacing: 6) {
                metricProgressRow(
                    title: "Dveře",
                    value: item.openedCount,
                    total: item.hp,
                    percent: item.computedOpenedPct,
                    progress: item.openedProgress,
                    tint: Color(red: 0.97, green: 0.58, blue: 0.12)
                )
                metricProgressRow(
                    title: "Penetrace",
                    value: item.fiberKs,
                    total: item.hp,
                    percent: item.computedPenetrationPct,
                    progress: item.fiberProgress,
                    tint: Color(red: 0.12, green: 0.62, blue: 0.72)
                )
            }
        }
        .padding(.vertical, 2)
    }

    private var statusBadge: some View {
        Text(item.isDone ? "Hotovo" : "Aktivní")
            .font(.caption2.weight(.bold))
            .foregroundStyle(item.isDone ? Color.green : Color.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                (item.isDone ? Color.green : Color.orange).opacity(0.14),
                in: Capsule()
            )
    }

    private func metricProgressRow(
        title: String,
        value: Int,
        total: Int,
        percent: Double,
        progress: Double,
        tint: Color
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(tint.opacity(0.12))
                    Capsule()
                        .fill(tint.opacity(0.85))
                        .frame(width: max(3, geo.size.width * progress))
                }
            }
            .frame(height: 4)

            Text("\(value)/\(total)")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Text(String(format: "%.0f%%", percent))
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .frame(minWidth: 28, alignment: .trailing)
        }
    }
}

// MARK: - Picker přiřazení

private enum ManagerSalesAssignTarget: Hashable {
    case unassign
    case member(Int)
}

private struct ManagerSalesAssignPickerSheet: View {
    let members: [ManagerTeamMember]
    @State private var target: ManagerSalesAssignTarget?
    let authToken: String?
    let isAssigning: Bool
    let onConfirm: (Int?) -> Void
    let onCancel: () -> Void

    init(
        members: [ManagerTeamMember],
        selectedId: Int?,
        authToken: String?,
        isAssigning: Bool,
        onConfirm: @escaping (Int?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.members = members
        self.authToken = authToken
        self.isAssigning = isAssigning
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        if let selectedId, selectedId > 0 {
            _target = State(initialValue: .member(selectedId))
        } else {
            _target = State(initialValue: nil)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        target = .unassign
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.minus")
                                .font(.body)
                                .foregroundStyle(.red)
                                .frame(width: 36, height: 36)
                                .background(Color.red.opacity(0.12), in: Circle())
                            Text("Odebrat obchodníka")
                                .foregroundStyle(.red)
                            Spacer()
                            if target == .unassign {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("Obchodníci") {
                    if members.isEmpty {
                        Text("Žádní členové týmu.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(members) { member in
                            Button {
                                target = .member(member.id)
                            } label: {
                                ManagerSalesMemberPickRow(
                                    member: member,
                                    token: authToken,
                                    isSelected: target == .member(member.id)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Přiřadit obchodníka")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Uložit") {
                        switch target {
                        case .unassign:
                            onConfirm(nil)
                        case .member(let id):
                            onConfirm(id)
                        case .none:
                            break
                        }
                    }
                    .disabled(isAssigning || target == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Detail

struct ManagerSalesLocalityDetailView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: ManagerSalesLocalitiesViewModel

    @State private var item: SalesLocalityItem
    @State private var fiberValue: Int
    @State private var openedValue: Int
    @State private var hpValue: Int
    @State private var isDone: Bool
    @State private var d2d: Bool
    @State private var noteText: String
    @State private var majitelText: String
    @State private var emailText: String
    @State private var telefonText: String
    @State private var salesUserId: Int?
    @State private var syncStatus: SyncStatus = .idle
    @State private var debounceTask: Task<Void, Never>?
    @State private var savedResetTask: Task<Void, Never>?
    @State private var hasAppeared = false
    @State private var isApplyingRemote = false
    @State private var isSaveInFlight = false
    @State private var saveAgainWhenDone = false
    @State private var showAssignSheet = false

    private enum SyncStatus: Equatable {
        case idle
        case saving
        case saved
    }

    init(item: SalesLocalityItem, viewModel: ManagerSalesLocalitiesViewModel) {
        self.viewModel = viewModel
        _item = State(initialValue: item)
        _fiberValue = State(initialValue: item.fiberKs)
        _openedValue = State(initialValue: item.openedCount)
        _hpValue = State(initialValue: item.hp)
        _isDone = State(initialValue: item.isDone)
        _d2d = State(initialValue: item.d2d)
        _noteText = State(initialValue: item.note ?? "")
        _majitelText = State(initialValue: item.majitel ?? "")
        _emailText = State(initialValue: item.email ?? "")
        _telefonText = State(initialValue: item.telefon ?? "")
        _salesUserId = State(initialValue: item.salesUserId.flatMap { $0 > 0 ? $0 : nil })
    }

    private var maxOpened: Int { max(hpValue, 0) }
    private var maxFiber: Int {
        max(0, min(maxOpened == 0 ? hpValue : openedValue, hpValue > 0 ? hpValue : openedValue))
    }

    private var assignedMemberName: String {
        if let salesUserId,
           let member = viewModel.salesMembers.first(where: { $0.id == salesUserId }) {
            return ManagerSalesLocalitiesViewModel.memberDisplayName(member)
        }
        if let name = item.salesName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return "Bez obchodníka"
    }

    var body: some View {
        Form {
            Section {
                if viewModel.canEditOpened {
                    PenetrationCounterCard(
                        title: "Otevřené dveře",
                        unitLabel: "dveří",
                        icon: "door.left.hand.open",
                        theme: .doors,
                        value: $openedValue,
                        total: max(hpValue, 1),
                        range: 0...max(maxOpened, openedValue),
                        onChange: { newOpened in
                            if fiberValue > newOpened {
                                fiberValue = newOpened
                            }
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 6, trailing: 12))
                    .listRowBackground(Color.clear)
                } else {
                    LabeledContent("Otevřené dveře", value: "\(item.openedCount)")
                }

                if viewModel.canEditFiber {
                    PenetrationCounterCard(
                        title: "Penetrace",
                        unitLabel: "fiber",
                        icon: "cable.connector",
                        theme: .fiber,
                        value: $fiberValue,
                        total: max(hpValue, 1),
                        range: 0...max(maxFiber, fiberValue)
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 10, trailing: 12))
                    .listRowBackground(Color.clear)
                } else {
                    LabeledContent("Penetrace", value: "\(item.fiberKs)")
                }
            } footer: {
                Text("Změny se ukládají automaticky.")
            }

            if viewModel.canAssignSales {
                Section("Obchodník") {
                    Button {
                        showAssignSheet = true
                    } label: {
                        HStack(spacing: 12) {
                            if let member = viewModel.salesMembers.first(where: { $0.id == salesUserId }) {
                                ManagerSalesMemberAvatar(member: member, token: authState.authToken, size: 32)
                            } else {
                                Image(systemName: "person.crop.circle")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32, height: 32)
                            }
                            Text(assignedMemberName)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } else if let name = item.salesName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                Section("Obchodník") {
                    LabeledContent("Přiřazeno", value: name)
                }
            }

            Section {
                if let ulice = item.ulice, !ulice.isEmpty {
                    LabeledContent("Ulice", value: ulice)
                }
                if let popisne = item.cisloPopisne, !popisne.isEmpty {
                    LabeledContent("Číslo popisné", value: popisne)
                }
                if let orientacni = item.cisloOrientacni, !orientacni.isEmpty {
                    LabeledContent("Číslo orientační", value: orientacni)
                }
                if let cast = item.castObce, !cast.isEmpty {
                    LabeledContent("Část obce", value: cast)
                }
                if let obec = item.obec, !obec.isEmpty {
                    LabeledContent("Obec", value: obec)
                }
                if let okres = item.okres, !okres.isEmpty {
                    LabeledContent("Okres", value: okres)
                }
                if viewModel.canEditHp {
                    Stepper(value: $hpValue, in: 0...9999) {
                        LabeledContent("HP", value: "\(hpValue)")
                    }
                } else {
                    LabeledContent("HP", value: "\(item.hp)")
                }
            } header: {
                Text("Lokalita")
            }

            if viewModel.canEditMajitel || viewModel.canEditTelefon || viewModel.canEditEmail {
                Section("Kontakt") {
                    if viewModel.canEditMajitel {
                        TextField("Majitel", text: $majitelText)
                    } else if let majitel = item.majitel?.trimmingCharacters(in: .whitespacesAndNewlines), !majitel.isEmpty {
                        LabeledContent("Majitel", value: majitel)
                    }
                    if viewModel.canEditTelefon {
                        TextField("Telefon", text: $telefonText)
                            .keyboardType(.phonePad)
                    } else if let telefon = item.telefon?.trimmingCharacters(in: .whitespacesAndNewlines), !telefon.isEmpty {
                        LabeledContent("Telefon", value: telefon)
                    }
                    if viewModel.canEditEmail {
                        TextField("E-mail", text: $emailText)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                    } else if let email = item.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
                        LabeledContent("E-mail", value: email)
                    }
                }
            }

            if viewModel.canEditDone {
                Section {
                    Toggle(isOn: $isDone) {
                        Label("Hotovo", systemImage: "checkmark.circle.fill")
                    }
                    .tint(.green)
                }
            }

            if viewModel.canEditD2d {
                Section {
                    Toggle(isOn: $d2d) {
                        Label("D2D", systemImage: "figure.walk")
                    }
                }
            }

            if viewModel.canEditNote {
                Section("Poznámka") {
                    TextField("Volitelná poznámka", text: $noteText, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
        }
        .navigationTitle("Detail lokality")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                syncStatusView
            }
        }
        .sheet(isPresented: $showAssignSheet) {
            ManagerSalesAssignPickerSheet(
                members: viewModel.salesMembers,
                selectedId: salesUserId,
                authToken: authState.authToken,
                isAssigning: false,
                onConfirm: { newId in
                    salesUserId = newId
                    showAssignSheet = false
                    markDirtyAndDebounce(ms: 200)
                },
                onCancel: { showAssignSheet = false }
            )
        }
        .onAppear { hasAppeared = true }
        .onChange(of: fiberValue) { _, _ in markDirtyAndDebounce(ms: 650) }
        .onChange(of: openedValue) { _, _ in markDirtyAndDebounce(ms: 650) }
        .onChange(of: hpValue) { _, _ in
            if openedValue > hpValue { openedValue = hpValue }
            if fiberValue > openedValue { fiberValue = openedValue }
            markDirtyAndDebounce(ms: 650)
        }
        .onChange(of: isDone) { _, _ in markDirtyAndDebounce(ms: 300) }
        .onChange(of: d2d) { _, _ in markDirtyAndDebounce(ms: 300) }
        .onChange(of: noteText) { _, _ in markDirtyAndDebounce(ms: 900) }
        .onChange(of: majitelText) { _, _ in markDirtyAndDebounce(ms: 900) }
        .onChange(of: emailText) { _, _ in markDirtyAndDebounce(ms: 900) }
        .onChange(of: telefonText) { _, _ in markDirtyAndDebounce(ms: 900) }
        .onDisappear {
            debounceTask?.cancel()
            Task { await saveNow() }
        }
    }

    @ViewBuilder
    private var syncStatusView: some View {
        switch syncStatus {
        case .idle:
            EmptyView()
        case .saving:
            ProgressView()
                .accessibilityLabel("Ukládám")
        case .saved:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Uloženo")
        }
    }

    private func markDirtyAndDebounce(ms: UInt64) {
        guard hasAppeared, !isApplyingRemote else { return }
        guard hasPendingChanges else { return }

        debounceTask?.cancel()
        savedResetTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: ms * 1_000_000)
            guard !Task.isCancelled else { return }
            await saveNow()
        }
    }

    private var hasPendingChanges: Bool {
        pendingFields().hasChanges
    }

    private func saveNow() async {
        guard hasPendingChanges else {
            if syncStatus == .saving { syncStatus = .idle }
            return
        }
        if isSaveInFlight {
            saveAgainWhenDone = true
            return
        }

        isSaveInFlight = true
        defer { isSaveInFlight = false }

        syncStatus = .saving
        let fields = pendingFields()

        do {
            let updated = try await viewModel.updateLocality(
                token: authState.authToken,
                id: item.id,
                fields: fields
            )
            applyRemote(updated)
            if saveAgainWhenDone || hasPendingChanges {
                saveAgainWhenDone = false
                let followUp = pendingFields()
                if followUp.hasChanges {
                    let followUpdated = try await viewModel.updateLocality(
                        token: authState.authToken,
                        id: item.id,
                        fields: followUp
                    )
                    applyRemote(followUpdated)
                }
            }
            showSavedThenIdle()
        } catch is CancellationError {
            syncStatus = .idle
        } catch let error as URLError where error.code == .cancelled {
            syncStatus = .idle
        } catch {
            syncStatus = .idle
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func applyRemote(_ updated: SalesLocalityItem) {
        isApplyingRemote = true
        defer { isApplyingRemote = false }

        item = updated
        fiberValue = updated.fiberKs
        openedValue = updated.openedCount
        hpValue = updated.hp
        isDone = updated.isDone
        d2d = updated.d2d
        noteText = updated.note ?? ""
        majitelText = updated.majitel ?? ""
        emailText = updated.email ?? ""
        telefonText = updated.telefon ?? ""
        salesUserId = updated.salesUserId.flatMap { $0 > 0 ? $0 : nil }
    }

    private func showSavedThenIdle() {
        syncStatus = .saved
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        savedResetTask?.cancel()
        savedResetTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            if syncStatus == .saved {
                syncStatus = .idle
            }
        }
    }

    private func pendingFields() -> SalesLocalityUpdateFields {
        var fields = SalesLocalityUpdateFields()

        let fiberChanged = viewModel.canEditFiber && fiberValue != item.fiberKs
        let openedChanged = viewModel.canEditOpened && openedValue != item.openedCount
        if fiberChanged || openedChanged {
            if viewModel.canEditFiber { fields.fiberKs = max(0, fiberValue) }
            if viewModel.canEditOpened { fields.openedCount = max(0, openedValue) }
        }

        if viewModel.canEditHp, hpValue != item.hp {
            fields.hp = max(0, hpValue)
        }
        if viewModel.canEditDone, isDone != item.isDone {
            fields.isDone = isDone
        }
        if viewModel.canEditD2d, d2d != item.d2d {
            fields.d2d = d2d
        }
        if viewModel.canEditNote {
            let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != (item.note ?? "") {
                fields.note = trimmed
            }
        }
        if viewModel.canEditMajitel {
            let trimmed = majitelText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != (item.majitel ?? "") {
                fields.majitel = trimmed
            }
        }
        if viewModel.canEditEmail {
            let trimmed = emailText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != (item.email ?? "") {
                fields.email = trimmed
            }
        }
        if viewModel.canEditTelefon {
            let trimmed = telefonText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != (item.telefon ?? "") {
                fields.telefon = trimmed
            }
        }
        if viewModel.canAssignSales {
            let current = item.salesUserId.flatMap { $0 > 0 ? $0 : nil }
            if salesUserId != current {
                fields.salesUserId = salesUserId ?? 0
            }
        }
        return fields
    }
}
