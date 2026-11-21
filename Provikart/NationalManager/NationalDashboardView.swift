//
//  NationalDashboardView.swift
//  Provikart
//
//  Přehled národního manažera: jen statistiky a to důležité –
//  KPI lokalit, dnešní nahlášení obchodníků, objednávky ke kontrole, stav lokalit.
//  Seznam lokalit je ve vlastní záložce.
//

import SwiftUI

@MainActor
final class NationalDashboardViewModel: ObservableObject {
    @Published private(set) var stats = NationalLocalityStats()
    @Published private(set) var facets = NationalLocalityFacets()
    @Published private(set) var salesTotal = 0
    @Published private(set) var salesReported = 0
    @Published private(set) var salesAbsent = 0
    @Published private(set) var ordersCreated = 0
    @Published private(set) var ordersOpen = 0
    @Published private(set) var ordersCompleted = 0
    @Published private(set) var isLoading = false
    @Published private(set) var didLoad = false
    @Published var errorMessage: String?

    private let service = NationalManagerService()

    var salesMissing: Int { max(0, salesTotal - salesReported - salesAbsent) }

    var fillRate: Double {
        let expected = salesTotal - salesAbsent
        guard expected > 0 else { return 0 }
        return Double(salesReported) / Double(expected)
    }

    func loadIfNeeded(token: String?) async {
        guard !didLoad else { return }
        await load(token: token)
    }

    func load(token: String?) async {
        isLoading = true
        defer { isLoading = false }

        async let localities = service.fetchLocalities(
            token: token,
            query: NationalManagerService.LocalitiesQuery(page: 1, limit: 1)
        )
        async let locations = service.fetchLocations(
            token: token,
            managerId: nil,
            workDate: NationalLocationsViewModel.dayFormatter.string(from: Date())
        )
        async let orders = service.fetchIncompleteOrders(token: token)

        var firstError: Error?

        do {
            let result = try await localities
            stats = result.stats
            facets = result.facets
        } catch { firstError = firstError ?? error }

        do {
            let result = try await locations
            let byUser = Dictionary(result.entries.map { ($0.userId, $0) }, uniquingKeysWith: { first, _ in first })
            salesTotal = result.members.count
            salesAbsent = result.members.filter { byUser[$0.userId]?.isAbsent == true }.count
            salesReported = result.members.filter { byUser[$0.userId].map { !$0.isAbsent } ?? false }.count
        } catch { firstError = firstError ?? error }

        do {
            let items = try await orders
            ordersCreated = items.filter { $0.status == .created }.count
            ordersOpen = items.filter { $0.status == .open }.count
            ordersCompleted = items.filter { $0.status == .completed }.count
        } catch { firstError = firstError ?? error }

        if let firstError {
            if (firstError as? URLError)?.code == .cancelled || firstError is CancellationError { return }
            errorMessage = firstError.localizedDescription
        } else {
            errorMessage = nil
            updateLiveActivity()
        }
        didLoad = true
    }

    /// Promítne přehled do Live Activity (Lock Screen + Dynamic Island).
    private func updateLiveActivity() {
        NationalLiveActivityManager.update(
            NationalLiveActivityAttributes.ContentState(
                salesReported: salesReported,
                salesExpected: max(salesTotal - salesAbsent, 0),
                ordersToCheck: ordersCreated + ordersOpen,
                localitiesDone: facets.done,
                localitiesTotal: facets.total,
                unassignedLocalities: facets.unassignedManager,
                salesAbsent: salesAbsent,
                ordersCreated: ordersCreated,
                ordersOpen: ordersOpen,
                ordersCompleted: ordersCompleted
            )
        )
    }
}

struct NationalDashboardView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel = NationalDashboardViewModel()
    /// Přepnutí na jinou záložku (z karet přehledu).
    var openTab: (NationalManagerTabs) -> Void = { _ in }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Přehled")
                            .font(.largeTitle.weight(.bold))
                        Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "cs_CZ"))))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)

                    if let message = viewModel.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(SV.bad)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(SVCardBackground(radius: 16, tint: SV.bad))
                    }

                    if !viewModel.didLoad && viewModel.isLoading {
                        ProgressView("Načítám přehled…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    } else {
                        NationalHpOverviewCard(stats: viewModel.stats, facets: viewModel.facets) {
                            openTab(.localities)
                        }

                        sectionTitle("Dnes")
                        todayCard
                        ordersCard

                        sectionTitle("Lokality")
                        localitiesCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background { ManagerScreenBackground() }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ManagerToolbarLogo() }
                ToolbarItem(placement: .topBarTrailing) { ProfileBarButton() }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .task { await viewModel.loadIfNeeded(token: authState.authToken) }
            .refreshable { await viewModel.load(token: authState.authToken) }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.heavy))
            .tracking(0.8)
            .foregroundStyle(.secondary)
            .padding(.top, 6)
    }

    // MARK: - Nahlášené lokality dnes

    private var todayCard: some View {
        Button { openTab(.locations) } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(SV.good.opacity(0.18), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: viewModel.fillRate)
                        .stroke(SV.good, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int((viewModel.fillRate * 100).rounded())) %")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                }
                .frame(width: 66, height: 66)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Nahlášené lokality")
                        .font(.headline)
                    Text("\(viewModel.salesReported) z \(viewModel.salesTotal) obchodníků")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        if viewModel.salesMissing > 0 {
                            SVChip(text: "Nezadáno \(viewModel.salesMissing)", icon: "exclamationmark", tint: SV.accent)
                        }
                        if viewModel.salesAbsent > 0 {
                            SVChip(text: "Pryč \(viewModel.salesAbsent)", icon: "calendar", tint: SV.sky)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(SVCardBackground(radius: 22, tint: SV.good))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Objednávky ke kontrole

    private var ordersCard: some View {
        Button { openTab(.orders) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Objednávky ke kontrole")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 10) {
                    miniStat("Vytvořeno", viewModel.ordersCreated, NationalIncompleteOrder.Status.created.tint)
                    miniStat("Otevřeno", viewModel.ordersOpen, NationalIncompleteOrder.Status.open.tint)
                    miniStat("Hotovo", viewModel.ordersCompleted, NationalIncompleteOrder.Status.completed.tint)
                }
            }
            .padding(16)
            .background(SVCardBackground(radius: 22, tint: SV.accent))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stav lokalit

    private var localitiesCard: some View {
        Button { openTab(.localities) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(viewModel.stats.total.formatted()) lokalit")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 10) {
                    miniStat("Hotové", viewModel.facets.done, SV.good)
                    miniStat("Nehotové", viewModel.facets.open, SV.sky)
                    if let closed = viewModel.facets.closed {
                        miniStat("Zavřené", closed, SV.coral)
                    }
                    miniStat("Bez manažera", viewModel.facets.unassignedManager, SV.accent)
                }
                if viewModel.facets.total > 0 {
                    let doneShare = Double(viewModel.facets.done) / Double(viewModel.facets.total)
                    ProgressView(value: min(1, max(0, doneShare))) {
                        Text("Hotovo \(Int((doneShare * 100).rounded())) %")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tint(SV.good)
                }
            }
            .padding(16)
            .background(SVCardBackground(radius: 22, tint: SV.sky))
        }
        .buttonStyle(.plain)
    }

    private func miniStat(_ title: String, _ value: Int, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.formatted())
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
