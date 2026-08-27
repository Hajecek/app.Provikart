//
//  UserSalesLocalitiesView.swift
//  Provikart
//
//  Seznam přiřazených prodejních lokalit + úprava fiberů a otevřených dveří.
//

import SwiftUI
import Charts

enum SalesLocalityDoneFilter: String, CaseIterable, Identifiable {
    case all = "Vše"
    case open = "Rozpracované"
    case done = "Hotovo"

    var id: String { rawValue }

    var doneValue: Bool? {
        switch self {
        case .all: return nil
        case .open: return false
        case .done: return true
        }
    }
}

// MARK: - ViewModel

@MainActor
final class UserSalesLocalitiesViewModel: ObservableObject {
    @Published var items: [SalesLocalityItem] = []
    @Published var stats: SalesLocalityStats = .empty
    @Published var editableFields: [String] = []
    @Published var searchText = ""
    @Published var doneFilter: SalesLocalityDoneFilter = .all
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?

    private let service = UserSalesLocalitiesService()
    private var pagination = SalesLocalityPagination(page: 1, pageSize: 50, total: 0, totalPages: 1)
    private var loadGeneration = 0
    private var searchTask: Task<Void, Never>?

    var hasMorePages: Bool {
        pagination.page < pagination.totalPages
    }

    var canEditFiber: Bool { editableFields.contains("fiber_ks") || editableFields.isEmpty }
    var canEditOpened: Bool { editableFields.contains("opened_count") || editableFields.isEmpty }
    var canEditDone: Bool { editableFields.contains("is_done") || editableFields.isEmpty }
    var canEditClose: Bool {
        editableFields.contains("close")
            || editableFields.contains("closed")
            || editableFields.isEmpty
    }
    var canEditNote: Bool { editableFields.contains("note") }
    var canEditD2d: Bool { editableFields.contains("d2d") || editableFields.isEmpty }

    func scheduleSearchReload(token: String?) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await load(token: token, reset: true)
        }
    }

    func load(token: String?, reset: Bool = true) async {
        guard let token, !token.isEmpty else {
            items = []
            stats = .empty
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
                    page: page,
                    limit: 50
                )
            )
            guard generation == loadGeneration else { return }

            if reset {
                items = result.items
            } else {
                let existing = Set(items.map(\.id))
                items.append(contentsOf: result.items.filter { !existing.contains($0.id) })
            }
            stats = result.stats
            pagination = result.pagination
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
            throw UserSalesLocalitiesError.notAuthenticated
        }
        let result = try await service.updateLocality(token: token, id: id, fields: fields)
        if !result.editableFields.isEmpty {
            editableFields = result.editableFields
        }
        replaceItem(result.item)
        return result.item
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        return false
    }
}

// MARK: - Seznam

struct UserSalesLocalitiesView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel = UserSalesLocalitiesViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView("Načítám lokality…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = viewModel.errorMessage, viewModel.items.isEmpty {
                errorState(message)
            } else {
                listContent
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Moje lokality")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    UserSalesLocalitiesStatsView(viewModel: viewModel)
                        .environmentObject(authState)
                } label: {
                    Image(systemName: "chart.bar.fill")
                }
                .accessibilityLabel("Statistiky lokalit")
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Ulice, obec, majitel…")
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.scheduleSearchReload(token: authState.authToken)
        }
        .onChange(of: viewModel.doneFilter) { _, _ in
            Task { await viewModel.load(token: authState.authToken, reset: true) }
        }
        .refreshable {
            await viewModel.load(token: authState.authToken, reset: true)
        }
        .task {
            await viewModel.load(token: authState.authToken, reset: true)
        }
        .alert("Chyba", isPresented: Binding(
            get: { viewModel.errorMessage != nil && !viewModel.items.isEmpty },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var listContent: some View {
        List {
            Section {
                filterPicker
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if viewModel.items.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Žádné lokality",
                        systemImage: "building.2",
                        description: Text(
                            viewModel.searchText.isEmpty
                                ? "Nemáte přiřazené žádné lokality v tomto filtru."
                                : "Zkuste upravit hledání."
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.items) { item in
                    Section {
                        NavigationLink {
                            UserSalesLocalityDetailView(
                                item: item,
                                viewModel: viewModel
                            )
                            .environmentObject(authState)
                        } label: {
                            SalesLocalityRow(item: item)
                        }
                        .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                        .listRowBackground(SalesLocalityClosedStyle.rowBackground(isClosed: item.isClosed))
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
    }

    private var filterPicker: some View {
        Picker("Stav", selection: $viewModel.doneFilter) {
            ForEach(SalesLocalityDoneFilter.allCases) { filter in
                Text(filter.rawValue).tag(filter)
            }
        }
        .pickerStyle(.segmented)
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

// MARK: - Statistiky lokalit

private enum LocalityStatsPalette {
    static let orange = Color(red: 0.97, green: 0.58, blue: 0.12)
    static let gold = Color(red: 1.0, green: 0.78, blue: 0.32)
    static let teal = Color(red: 0.12, green: 0.62, blue: 0.72)
    static let mint = Color(red: 0.35, green: 0.82, blue: 0.78)
    static let green = Color(red: 0.22, green: 0.72, blue: 0.42)
}

private struct LocalityFunnelStep: Identifiable {
    let id: String
    let title: String
    let value: Int
    let color: Color
}

struct UserSalesLocalitiesStatsView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: UserSalesLocalitiesViewModel

    private var stats: SalesLocalityStats { viewModel.stats }

    private var doneRate: Double {
        guard stats.total > 0 else { return 0 }
        return Double(stats.done) / Double(stats.total)
    }

    private var remainingDoors: Int { max(0, stats.hp - stats.opened) }
    private var conversionFromOpened: Double {
        guard stats.opened > 0 else { return 0 }
        return min(1, Double(stats.fiberKs) / Double(stats.opened))
    }

    private var avgHp: Double {
        guard stats.total > 0 else { return 0 }
        return Double(stats.hp) / Double(stats.total)
    }

    private var funnelSteps: [LocalityFunnelStep] {
        [
            .init(id: "hp", title: "HP", value: stats.hp, color: .secondary),
            .init(id: "doors", title: "Dveře", value: stats.opened, color: LocalityStatsPalette.orange),
            .init(id: "fiber", title: "Fiber", value: stats.fiberKs, color: LocalityStatsPalette.teal)
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                heroCard
                kpiGrid
                ringsCard
                funnelCard
                statusCard
                insightsCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Statistiky")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await viewModel.load(token: authState.authToken, reset: true)
        }
        .task {
            await viewModel.load(token: authState.authToken, reset: true)
        }
    }

    // MARK: Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(filterCaption)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LocalityStatsPalette.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(LocalityStatsPalette.orange.opacity(0.14), in: Capsule())

                    Text("Výkon lokalit")
                        .font(.title2.weight(.bold))

                    Text("Souhrn otevřených dveří, penetrace a dokončenosti napříč přiřazenými lokalitami.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chart.xyaxis.line")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(LocalityStatsPalette.orange)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [LocalityStatsPalette.gold.opacity(0.45), LocalityStatsPalette.orange.opacity(0.18)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            }

            HStack(spacing: 0) {
                heroMetric(value: "\(stats.total)", label: "Lokalit")
                Divider().frame(height: 36)
                heroMetric(value: "\(stats.hp)", label: "HP")
                Divider().frame(height: 36)
                heroMetric(value: String(format: "%.0f %%", stats.penetrationPct), label: "Penetrace")
            }
            .padding(.vertical, 4)
        }
        .padding(18)
        .background(cardFill)
        .overlay(cardStroke)
    }

    private func heroMetric(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: KPI grid

    private var kpiGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            kpiTile(
                title: "Otevřené dveře",
                value: "\(stats.opened)",
                subtitle: "zbývá \(remainingDoors)",
                icon: "door.left.hand.open",
                tint: LocalityStatsPalette.orange
            )
            kpiTile(
                title: "Fiber",
                value: "\(stats.fiberKs)",
                subtitle: String(format: "%.1f %% z HP", stats.penetrationPct),
                icon: "cable.connector",
                tint: LocalityStatsPalette.teal
            )
            kpiTile(
                title: "Hotovo",
                value: "\(stats.done)",
                subtitle: String(format: "%.0f %% lokalit", doneRate * 100),
                icon: "checkmark.circle.fill",
                tint: LocalityStatsPalette.green
            )
            kpiTile(
                title: "Rozpracované",
                value: "\(stats.open)",
                subtitle: "průměr \(String(format: "%.1f", avgHp)) HP",
                icon: "circle.dashed",
                tint: Color.secondary
            )
        }
    }

    private func kpiTile(title: String, value: String, subtitle: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer()
            }
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .overlay(cardStroke)
    }

    // MARK: Rings

    private var ringsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Klíčové podíly", icon: "circle.circle")

            HStack(spacing: 12) {
                ringStat(
                    title: "Otevřeno",
                    percent: stats.openedPct,
                    detail: "\(stats.opened) z \(stats.hp)",
                    tint: LocalityStatsPalette.orange,
                    secondary: LocalityStatsPalette.gold
                )
                ringStat(
                    title: "Penetrace",
                    percent: stats.penetrationPct,
                    detail: "\(stats.fiberKs) z \(stats.hp)",
                    tint: LocalityStatsPalette.teal,
                    secondary: LocalityStatsPalette.mint
                )
                ringStat(
                    title: "Konverze",
                    percent: conversionFromOpened * 100,
                    detail: "fiber / dveře",
                    tint: LocalityStatsPalette.green,
                    secondary: LocalityStatsPalette.mint
                )
            }
        }
        .padding(18)
        .background(cardFill)
        .overlay(cardStroke)
    }

    private func ringStat(title: String, percent: Double, detail: String, tint: Color, secondary: Color) -> some View {
        let progress = min(1, max(0, percent / 100))
        return VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.12), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(colors: [secondary, tint, tint.opacity(0.7)], center: .center),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.snappy(duration: 0.35), value: progress)

                VStack(spacing: 1) {
                    Text(String(format: "%.0f", percent))
                        .font(.headline.weight(.bold))
                        .monospacedDigit()
                    Text("%")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 86, height: 86)

            Text(title)
                .font(.caption.weight(.bold))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Funnel / bars

    private var funnelCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Trychtýř výkonu", icon: "chart.bar.fill")

            Chart(funnelSteps) { step in
                BarMark(
                    x: .value("Hodnota", step.value),
                    y: .value("Metrika", step.title)
                )
                .foregroundStyle(step.color.gradient)
                .cornerRadius(8)
                .annotation(position: .trailing, alignment: .leading) {
                    Text("\(step.value)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.caption.weight(.semibold))
                }
            }
            .frame(height: 150)

            Text("Z \(stats.hp) HP je otevřeno \(stats.opened) dveří a prodáno \(stats.fiberKs) fiberů.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(cardFill)
        .overlay(cardStroke)
    }

    // MARK: Status

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Dokončenost lokalit", icon: "flag.checkered")

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.0f", doneRate * 100))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(LocalityStatsPalette.green)
                Text("%")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(LocalityStatsPalette.green.opacity(0.7))
                Spacer()
                Text("\(stats.done) z \(stats.total)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    HStack(spacing: 0) {
                        Capsule()
                            .fill(LocalityStatsPalette.green.gradient)
                            .frame(width: max(0, geo.size.width * doneRate))
                    }
                }
            }
            .frame(height: 12)

            HStack(spacing: 10) {
                statusPill(title: "Hotovo", value: stats.done, tint: LocalityStatsPalette.green)
                statusPill(title: "Aktivní", value: stats.open, tint: LocalityStatsPalette.orange)
            }
        }
        .padding(18)
        .background(cardFill)
        .overlay(cardStroke)
    }

    private func statusPill(title: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(value)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(maxWidth: .infinity)
    }

    // MARK: Insights

    private var insightsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Rychlé poznatky", icon: "lightbulb.fill")

            insightRow(
                icon: "door.left.hand.open",
                tint: LocalityStatsPalette.orange,
                text: remainingDoors > 0
                    ? "Zbývá otevřít ještě \(remainingDoors) dveří z celkového HP."
                    : "Všechny dostupné dveře v HP jsou už otevřené."
            )
            insightRow(
                icon: "cable.connector",
                tint: LocalityStatsPalette.teal,
                text: stats.opened > stats.fiberKs
                    ? "Z otevřených dveří jde ještě \(max(0, stats.opened - stats.fiberKs)) převést na fiber."
                    : "Penetrace drží tempo s otevřenými dveřmi."
            )
            insightRow(
                icon: "building.2.fill",
                tint: LocalityStatsPalette.green,
                text: stats.total > 0
                    ? "Na lokalitu připadá v průměru \(String(format: "%.1f", avgHp)) HP."
                    : "Zatím nemáte žádné lokality ve filtru."
            )
        }
        .padding(18)
        .background(cardFill)
        .overlay(cardStroke)
    }

    private func insightRow(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: Shared

    private var filterCaption: String {
        switch viewModel.doneFilter {
        case .all: return "Všechny lokality"
        case .open: return "Jen rozpracované"
        case .done: return "Jen hotové"
        }
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline.weight(.bold))
    }

    private var cardFill: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private var cardStroke: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
    }
}

// MARK: - Řádek seznamu

private struct SalesLocalityRow: View {
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
        SalesLocalityStatusBadge(item: item)
    }

    private func metricProgressRow(
        title: String,
        value: Int,
        total: Int,
        percent: Double,
        progress: Double,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
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
}

// MARK: - Detail / editace

struct UserSalesLocalityDetailView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: UserSalesLocalitiesViewModel

    @State private var item: SalesLocalityItem
    @State private var fiberValue: Int
    @State private var openedValue: Int
    @State private var isDone: Bool
    @State private var isClosed: Bool
    @State private var d2d: Bool
    @State private var noteText: String
    @State private var syncStatus: SyncStatus = .idle
    @State private var debounceTask: Task<Void, Never>?
    @State private var savedResetTask: Task<Void, Never>?
    @State private var hasAppeared = false
    @State private var isApplyingRemote = false
    @State private var isSaveInFlight = false
    @State private var saveAgainWhenDone = false

    private enum SyncStatus: Equatable {
        case idle
        case saving
        case saved
    }

    init(item: SalesLocalityItem, viewModel: UserSalesLocalitiesViewModel) {
        self.viewModel = viewModel
        _item = State(initialValue: item)
        _fiberValue = State(initialValue: item.fiberKs)
        _openedValue = State(initialValue: item.openedCount)
        _isDone = State(initialValue: item.isDone)
        _isClosed = State(initialValue: item.isClosed)
        _d2d = State(initialValue: item.d2d)
        _noteText = State(initialValue: item.note ?? "")
    }

    var body: some View {
        Form {
            Section {
                LocalityVisitActionsCard(
                    opened: $openedValue,
                    fiber: $fiberValue,
                    isClosed: isClosed,
                    hp: max(item.hp, 0),
                    canEditOpened: viewModel.canEditOpened,
                    canEditFiber: viewModel.canEditFiber
                )
                .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                .listRowBackground(Color.clear)
            } footer: {
                Text(isClosed
                     ? "Lokalita je zavřená, otevřené dveře a fiber už nejde měnit."
                     : "Klepnutím přidáš otevřené dveře nebo fiber. Změny se ukládají automaticky.")
            }

            if viewModel.canEditClose {
                Section {
                    LocalityClosedToggle(isClosed: $isClosed)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        .listRowBackground(Color.clear)
                } footer: {
                    Text(isClosed
                         ? "Klepnutím lokalitu znovu otevřeš a odemkneš přidávání."
                         : "Zavřením se lokalita uzavře a zamkne se přidávání dveří i fiberu.")
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
                if let house = item.houseNumberLabel,
                   (item.cisloPopisne == nil || item.cisloPopisne?.isEmpty == true)
                    && (item.cisloOrientacni == nil || item.cisloOrientacni?.isEmpty == true) {
                    LabeledContent("Číslo", value: house)
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
                if let majitel = item.majitel, !majitel.isEmpty {
                    LabeledContent("Majitel", value: majitel)
                }
                if let telefon = item.telefon, !telefon.isEmpty {
                    LabeledContent("Telefon", value: telefon)
                }
                if let email = item.email, !email.isEmpty {
                    LabeledContent("E-mail", value: email)
                }
                LabeledContent("HP", value: "\(item.hp)")
                if let komerce = item.komerceDateLabel {
                    LabeledContent("Datum komerce", value: komerce)
                }
            } header: {
                Text("Lokalita")
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
        .onAppear { hasAppeared = true }
        .onChange(of: fiberValue) { _, _ in markDirtyAndDebounce(ms: 650) }
        .onChange(of: openedValue) { _, _ in markDirtyAndDebounce(ms: 650) }
        .onChange(of: isDone) { _, _ in markDirtyAndDebounce(ms: 300) }
        .onChange(of: isClosed) { _, _ in markDirtyAndDebounce(ms: 300) }
        .onChange(of: d2d) { _, _ in markDirtyAndDebounce(ms: 300) }
        .onChange(of: noteText) { _, _ in markDirtyAndDebounce(ms: 900) }
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

        // Už běží request – po něm uložíme aktuální stav ještě jednou.
        if isSaveInFlight {
            saveAgainWhenDone = true
            return
        }

        isSaveInFlight = true
        defer { isSaveInFlight = false }

        var shouldSaveAgain = false
        syncStatus = .saving

        let fields = pendingFields()
        let fiberSnapshot = fiberValue
        let openedSnapshot = openedValue
        let doneSnapshot = isDone
        let closedSnapshot = isClosed
        let d2dSnapshot = d2d
        let noteSnapshot = noteText

        do {
            let updated = try await viewModel.updateLocality(
                token: authState.authToken,
                id: item.id,
                fields: fields
            )
            applyRemote(
                updated,
                fiberSnapshot: fiberSnapshot,
                openedSnapshot: openedSnapshot,
                doneSnapshot: doneSnapshot,
                closedSnapshot: closedSnapshot,
                d2dSnapshot: d2dSnapshot,
                noteSnapshot: noteSnapshot
            )
            shouldSaveAgain = saveAgainWhenDone || hasPendingChanges
            saveAgainWhenDone = false
            if shouldSaveAgain {
                // Jedno follow-up uložení finálního stavu po rychlém klikání.
                let followUp = pendingFields()
                if followUp.hasChanges {
                    let followUpdated = try await viewModel.updateLocality(
                        token: authState.authToken,
                        id: item.id,
                        fields: followUp
                    )
                    applyRemote(
                        followUpdated,
                        fiberSnapshot: fiberValue,
                        openedSnapshot: openedValue,
                        doneSnapshot: isDone,
                        closedSnapshot: isClosed,
                        d2dSnapshot: d2d,
                        noteSnapshot: noteText
                    )
                }
            }
            showSavedThenIdle()
        } catch is CancellationError {
            syncStatus = .idle
        } catch let error as URLError where error.code == .cancelled {
            syncStatus = .idle
        } catch {
            // Jeden tichý retry, pak loading ukonči.
            do {
                try? await Task.sleep(nanoseconds: 450_000_000)
                let retryFields = pendingFields()
                guard retryFields.hasChanges else {
                    syncStatus = .idle
                    return
                }
                let updated = try await viewModel.updateLocality(
                    token: authState.authToken,
                    id: item.id,
                    fields: retryFields
                )
                applyRemote(
                    updated,
                    fiberSnapshot: fiberValue,
                    openedSnapshot: openedValue,
                    doneSnapshot: isDone,
                    closedSnapshot: isClosed,
                    d2dSnapshot: d2d,
                    noteSnapshot: noteText
                )
                showSavedThenIdle()
            } catch {
                syncStatus = .idle
            }
        }
    }

    private func applyRemote(
        _ updated: SalesLocalityItem,
        fiberSnapshot: Int,
        openedSnapshot: Int,
        doneSnapshot: Bool,
        closedSnapshot: Bool,
        d2dSnapshot: Bool,
        noteSnapshot: String
    ) {
        isApplyingRemote = true
        defer { isApplyingRemote = false }

        item = updated

        // Přepiš lokál jen pokud uživatel mezitím neklikal dál.
        if fiberValue == fiberSnapshot { fiberValue = updated.fiberKs }
        if openedValue == openedSnapshot { openedValue = updated.openedCount }
        if isDone == doneSnapshot { isDone = updated.isDone }
        if isClosed == closedSnapshot { isClosed = updated.isClosed }
        if d2d == d2dSnapshot { d2d = updated.d2d }
        if noteText == noteSnapshot { noteText = updated.note ?? "" }
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

        // Počítadla posílej vždy spolu – stabilnější vůči race na serveru.
        let fiberChanged = viewModel.canEditFiber && fiberValue != item.fiberKs
        let openedChanged = viewModel.canEditOpened && openedValue != item.openedCount
        if fiberChanged || openedChanged {
            if viewModel.canEditFiber { fields.fiberKs = max(0, fiberValue) }
            if viewModel.canEditOpened { fields.openedCount = max(0, openedValue) }
        }

        if viewModel.canEditDone, isDone != item.isDone {
            fields.isDone = isDone
        }
        if viewModel.canEditClose, isClosed != item.isClosed {
            fields.isClosed = isClosed
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
        return fields
    }
}

// MARK: - Stav lokality

enum SalesLocalityClosedStyle {
    static let tint = Color(red: 0.82, green: 0.26, blue: 0.28)

    @ViewBuilder
    static func rowBackground(isClosed: Bool) -> some View {
        ZStack {
            Color(uiColor: .secondarySystemGroupedBackground)
            if isClosed {
                tint.opacity(0.16)
            }
        }
    }
}

struct SalesLocalityStatusBadge: View {
    let item: SalesLocalityItem

    private var title: String {
        if item.isClosed { return "Zavřeno" }
        if item.isDone { return "Hotovo" }
        return "Aktivní"
    }

    private var tint: Color {
        if item.isClosed { return SalesLocalityClosedStyle.tint }
        if item.isDone { return .green }
        return .orange
    }

    var body: some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.16), in: Capsule())
    }
}

// MARK: - Akce na lokalitě (dveře / fiber)

private enum LocalityVisitPalette {
    static let doors = Color(red: 0.97, green: 0.58, blue: 0.12)
    static let doorsSoft = Color(red: 1.0, green: 0.78, blue: 0.32)
    static let fiber = Color(red: 0.12, green: 0.62, blue: 0.72)
    static let fiberSoft = Color(red: 0.35, green: 0.82, blue: 0.78)
    static let closed = Color(red: 0.82, green: 0.26, blue: 0.28)
}

private struct LocalityVisitTapStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

struct LocalityVisitActionsCard: View {
    @Binding var opened: Int
    @Binding var fiber: Int
    let isClosed: Bool
    let hp: Int
    var canEditOpened: Bool = true
    var canEditFiber: Bool = true

    @State private var openedPulse = 0
    @State private var fiberPulse = 0

    private var canIncreaseOpened: Bool { !isClosed && canEditOpened && opened < hp }
    private var canDecreaseOpened: Bool { !isClosed && canEditOpened && opened > 0 }
    private var canIncreaseFiber: Bool {
        guard !isClosed, canEditFiber else { return false }
        if fiber < opened { return true }
        return canEditOpened && opened < hp
    }
    private var canDecreaseFiber: Bool { !isClosed && canEditFiber && fiber > 0 }

    var body: some View {
        VStack(spacing: 10) {
            countRow(
                title: "Otevřené dveře",
                unitLabel: "dveří",
                icon: "door.left.hand.open",
                value: opened,
                tint: LocalityVisitPalette.doors,
                soft: LocalityVisitPalette.doorsSoft,
                pulse: openedPulse,
                canIncrease: canIncreaseOpened,
                canDecrease: canDecreaseOpened,
                increaseLabel: "Přidat otevřené dveře",
                decreaseLabel: "Odebrat otevřené dveře",
                onIncrease: incrementOpened,
                onDecrease: decrementOpened
            )
            countRow(
                title: "Fiber",
                unitLabel: "fiber",
                icon: "cable.connector",
                value: fiber,
                tint: LocalityVisitPalette.fiber,
                soft: LocalityVisitPalette.fiberSoft,
                pulse: fiberPulse,
                canIncrease: canIncreaseFiber,
                canDecrease: canDecreaseFiber,
                increaseLabel: "Přidat fiber",
                decreaseLabel: "Odebrat fiber",
                onIncrease: incrementFiber,
                onDecrease: decrementFiber
            )
        }
        .opacity(isClosed ? 0.55 : 1)
        .animation(.snappy(duration: 0.2), value: isClosed)
        .allowsHitTesting(!isClosed)
        .accessibilityElement(children: .contain)
        .accessibilityHint(isClosed ? "Lokalita je zavřená, hodnoty nelze měnit" : "")
    }

    private func countRow(
        title: String,
        unitLabel: String,
        icon: String,
        value: Int,
        tint: Color,
        soft: Color,
        pulse: Int,
        canIncrease: Bool,
        canDecrease: Bool,
        increaseLabel: String,
        decreaseLabel: String,
        onIncrease: @escaping () -> Void,
        onDecrease: @escaping () -> Void
    ) -> some View {
        let progress: Double = hp > 0 ? min(1, max(0, Double(value) / Double(hp))) : 0

        return VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: isClosed ? "lock.fill" : icon)
                    .font(.body.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(soft.opacity(0.4), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                    Text("\(value) z \(hp) \(unitLabel)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }

                Spacer(minLength: 8)

                Text(String(format: "%.0f %%", progress * 100))
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            HStack(spacing: 16) {
                stepButton(systemName: "minus", enabled: canDecrease, tint: tint, accessibility: decreaseLabel, action: onDecrease)

                Text("\(value)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText())
                    .scaleEffect(pulse > 0 ? 1.04 : 1)
                    .animation(.spring(response: 0.28, dampingFraction: 0.62), value: pulse)

                stepButton(systemName: "plus", enabled: canIncrease, tint: tint, accessibility: increaseLabel, action: onIncrease)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(tint.opacity(0.12))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [soft, tint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(value > 0 ? 8 : 0, geo.size.width * progress))
                }
                .animation(.snappy(duration: 0.24), value: value)
            }
            .frame(height: 8)
        }
        .padding(16)
        .background(rowBackground(tint: tint))
        .overlay { rowStroke(tint: tint, soft: soft) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue("\(value) z \(hp)")
    }

    private func rowBackground(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.14), tint.opacity(0.03), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .shadow(color: tint.opacity(0.1), radius: 10, y: 4)
    }

    private func rowStroke(tint: Color, soft: Color) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [soft.opacity(0.7), tint.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    private func stepButton(
        systemName: String,
        enabled: Bool,
        tint: Color,
        accessibility: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3.weight(.bold))
                .foregroundStyle(enabled ? Color.white : Color.secondary.opacity(0.4))
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: enabled
                                    ? [tint.opacity(0.92), tint]
                                    : [Color.primary.opacity(0.08), Color.primary.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .shadow(color: enabled ? tint.opacity(0.28) : .clear, radius: 6, y: 2)
        }
        .buttonStyle(LocalityVisitTapStyle())
        .disabled(!enabled)
        .accessibilityLabel(accessibility)
    }

    private func incrementOpened() {
        guard canIncreaseOpened else { return }
        opened += 1
        openedPulse += 1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func decrementOpened() {
        guard canDecreaseOpened else { return }
        opened -= 1
        if fiber > opened { fiber = opened }
        openedPulse += 1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func incrementFiber() {
        guard canIncreaseFiber else { return }
        if fiber >= opened, canEditOpened, opened < hp {
            opened += 1
            openedPulse += 1
        }
        fiber += 1
        fiberPulse += 1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func decrementFiber() {
        guard canDecreaseFiber else { return }
        fiber -= 1
        fiberPulse += 1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

struct LocalityClosedToggle: View {
    @Binding var isClosed: Bool

    var body: some View {
        Button {
            isClosed.toggle()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isClosed ? "lock.fill" : "door.left.hand.closed")
                    .font(.title3.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(isClosed ? Color.white.opacity(0.2) : LocalityVisitPalette.closed.opacity(0.16))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(isClosed ? "Zavřeno" : "Označit jako zavřené")
                        .font(.headline.weight(.bold))
                    Text(isClosed ? "Lokalita je uzavřená" : "Uzavře lokalitu a zamkne zápis")
                        .font(.caption)
                        .opacity(0.85)
                }

                Spacer(minLength: 8)

                Image(systemName: isClosed ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
            }
            .foregroundStyle(isClosed ? Color.white : LocalityVisitPalette.closed)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isClosed
                                ? [LocalityVisitPalette.closed.opacity(0.92), LocalityVisitPalette.closed]
                                : [LocalityVisitPalette.closed.opacity(0.1), LocalityVisitPalette.closed.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(LocalityVisitPalette.closed.opacity(isClosed ? 0 : 0.32), lineWidth: 1)
            }
            .shadow(color: LocalityVisitPalette.closed.opacity(isClosed ? 0.28 : 0.08), radius: 10, y: 4)
        }
        .buttonStyle(LocalityVisitTapStyle())
        .accessibilityLabel(isClosed ? "Lokalita je zavřená" : "Označit lokalitu jako zavřenou")
        .accessibilityAddTraits(isClosed ? .isSelected : [])
    }
}

#Preview {
    NavigationStack {
        UserSalesLocalitiesView()
            .environmentObject(AuthState())
    }
}
