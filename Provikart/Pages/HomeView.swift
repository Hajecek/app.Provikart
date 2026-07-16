//
//  HomeView.swift
//  Provikart
//
//  Created by Michal Hájek on 03.07.2025.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.openAddSheet) private var openAddSheet
    @State private var commission: CommissionResponse?
    @State private var commissionError: String?
    @State private var isLoadingCommission = false
    @State private var isCommissionHidden = WidgetDataStore.isCommissionHidden
    /// Cíl provize z API (null = použije se výchozí 100k).
    @State private var commissionGoal: Double?
    /// Cíl počtu služeb z API (null = výchozí 100).
    @State private var servicesGoal: Int?
    /// Počet položek po termínu instalace čekajících na dokončení. nil = nenačteno, 0 = žádné, >0 = zobrazit container.
    @State private var pendingCompletionCount: Int?
    /// Celkový počet služeb (order_items bez migrace). nil = nenačteno.
    @State private var servicesCount: Int?
    /// Počet záznamů z Karty vchodu za aktuální měsíc. nil = nenačteno.
    @State private var entryCardsCount: Int?
    /// Dealwars: moje pořadí v aktuální sezoně.
    @State private var dealwarsRank: Int?
    /// Dealwars: moje XP v aktuální sezoně.
    @State private var dealwarsXP: Double?

    private let commissionService = CommissionService()
    private let userGoalsService = UserGoalsService()
    private let pendingCompletionService = OrderItemsPendingCompletionService()
    private let orderItemsCountService = OrderItemsCountService()
    private let entryCardsCountService = EntryCardsCountService()
    private let dealwarsSeasonService = DealwarsSeasonService()

    private var effectiveCommissionGoal: Double {
        commissionGoal ?? 100_000
    }

    private var effectiveServicesGoal: Double {
        Double(servicesGoal ?? 100)
    }

    var body: some View {
        NavigationStack {
            List {
                // Nejvyšší priorita: položky po termínu instalace – vždy úplně nahoře, výrazný design
                if (pendingCompletionCount ?? 0) > 0 {
                    Section {
                        NavigationLink {
                            PendingCompletionListView()
                                .environmentObject(authState)
                        } label: {
                            pendingCompletionRowContent
                        }
                        .listRowBackground(pendingCompletionBackground)
                        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                    } header: {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                            Text("Priorita – po termínu instalace")
                                .textCase(nil)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                        }
                    }
                    .listRowBackground(Color.clear)
                }

                // Přehledové karty
                Section {
                    NavigationLink {
                        DealwarsView()
                            .environmentObject(authState)
                    } label: {
                        dealwarsRow
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    commissionRow
                }

                Section {
                    servicesCountRow
                }

                Section {
                    entryCardsRow
                }
            }
            .homeListSectionSpacing()
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background {
                ZStack(alignment: .top) {
                    Color(uiColor: .systemGroupedBackground)

                    // Barvy loga v oblouku odshora dolů do ztracena
                    HomeTopArchGlow()
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle("Domů")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    NavigationLink {
                        StatisticsView()
                            .environmentObject(authState)
                            .environment(\.openAddSheet, openAddSheet)
                    } label: {
                        Image(systemName: "chart.bar")
                    }
                    NavigationLink {
                        UserLocationUpdateView()
                            .environmentObject(authState)
                    } label: {
                        Image(systemName: "mappin.and.ellipse")
                    }
                    NavigationLink {
                        UserAttendanceView()
                            .environmentObject(authState)
                    } label: {
                        Image(systemName: "person.badge.clock")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        DealwarsView()
                    } label: {
                        Image(systemName: "trophy")
                    }
                    ProfileBarButton()
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .task {
            // Obnov uložený cíl hned (z předchozího načtení), než stáhneme z API
            if let saved = WidgetDataStore.loadCommissionGoal() {
                commissionGoal = saved
            }
            await loadGoals()
            await loadCommission()
            await loadPendingCompletion()
            await loadServicesCount()
            await loadEntryCardsCount()
            await loadDealwarsSummary()
            // Periodické obnovení provize a nedokončených na pozadí (každých 5 s)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { break }
                await loadGoals()
                await loadCommission(silent: true)
                await loadPendingCompletion()
                await loadServicesCount()
                await loadEntryCardsCount()
                await loadDealwarsSummary()
            }
        }
        .refreshable {
            await loadGoals()
            await loadCommission()
            await loadPendingCompletion()
            await loadServicesCount()
            await loadEntryCardsCount()
            await loadDealwarsSummary()
        }
    }

    // MARK: - Commission Row (iOS List style)

    private var dealwarsRow: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.orange.opacity(0.24))
                    .frame(width: 44, height: 44)
                Image(systemName: "trophy.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Dealwars")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("Moje pořadí \(dealwarsRank.map { "#\($0)" } ?? "—")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(pointsLabel)
                .font(.title3.weight(.bold))
                .foregroundStyle(.orange)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
        .listRowBackground(dealwarsBackground)
        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
    }

    private var dealwarsBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        return ZStack {
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.33, green: 0.24, blue: 0.17),
                            Color(red: 0.24, green: 0.18, blue: 0.15),
                            Color(red: 0.18, green: 0.14, blue: 0.13)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            shape
                .fill(Color.black.opacity(0.08))
            shape
                .stroke(Color.orange.opacity(0.5), lineWidth: 1)
        }
    }

    private var commissionRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "creditcard.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28, alignment: .center)

                    Text(monthTitle)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Button {
                        let newHidden = !isCommissionHidden
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isCommissionHidden = newHidden
                        }
                        WidgetDataStore.setCommissionHidden(newHidden)
                        if let c = commission {
                            CommissionLiveActivityManager.update(
                                commission: c.commission,
                                currency: c.currency,
                                monthLabel: c.month_label,
                                goal: commissionGoal,
                                isHidden: newHidden
                            )
                        }
                    } label: {
                        Image(systemName: isCommissionHidden ? "eye.slash" : "eye")
                            .font(.body)
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                }

                Group {
                    if isLoadingCommission {
                        loadingSkeleton
                    } else if let err = commissionError {
                        errorRow(message: err)
                    } else if let c = commission {
                        valueRow(commission: c)
                    } else {
                        Text("Přihlaste se pro zobrazení provize.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let c = commission, !isCommissionHidden {
                    CommissionProgressBarView(
                        value: c.commission,
                        goal: effectiveCommissionGoal,
                        barHeight: 22,
                        scaleFontSize: 10
                    )
                }

            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityBannerLabel)
    }

    // MARK: - Services count row

    private var servicesCountRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "list.bullet.rectangle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28, alignment: .center)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Celkem služeb")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("Položky objednávek (bez migrací)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let count = servicesCount {
                        Text("\(count)")
                            .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                    } else {
                        ProgressView()
                    }
                }

                if let count = servicesCount {
                    CommissionProgressBarView(
                        value: Double(count),
                        goal: effectiveServicesGoal,
                        barHeight: 22,
                        scaleFontSize: 10
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(servicesCount != nil ? "Celkem \(servicesCount!) služeb" : "Načítám počet služeb")
    }

    // MARK: - Entry cards row

    private var entryCardsRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "door.left.hand.open")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28, alignment: .center)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Počet záznamů")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("Aktuální měsíc – cíl 200 záznamů")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let count = entryCardsCount {
                        Text("\(count)")
                            .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                    } else {
                        ProgressView()
                    }
                }

                if let count = entryCardsCount {
                    CommissionProgressBarView(
                        value: Double(count),
                        goal: 200,
                        barHeight: 22,
                        scaleFontSize: 10
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entryCardsCount != nil ? "Celkem \(entryCardsCount!) záznamů na Kartě vchodu" : "Načítám záznamy z Karty vchodu")
    }

    // MARK: - Pending completion (priorita – po termínu instalace)

    /// Výrazné pozadí sekce „po termínu“ – oranžový odstín, zaoblené rohy, rámeček po celém obvodu včetně rohů.
    private var pendingCompletionBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        return ZStack {
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0.12),
                            Color.orange.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            shape
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        }
    }

    private var pendingCompletionRowContent: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.orange.opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: "clock.badge.exclamationmark.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Položky po termínu instalace")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("\(pendingCompletionCount ?? 0) čeká na dokončení")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(pendingCompletionCount ?? 0)")
                .font(.title2.weight(.bold))
                .foregroundStyle(.orange)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pendingCompletionCount ?? 0) položek čeká na dokončení po termínu instalace")
    }

    private var monthTitle: String {
        if let apiMonth = commission?.month {
            let inputFormatter = DateFormatter()
            inputFormatter.dateFormat = "yyyy-MM"
            inputFormatter.locale = Locale(identifier: "cs_CZ")

            let outputFormatter = DateFormatter()
            outputFormatter.dateFormat = "LLLL yyyy"
            outputFormatter.locale = Locale(identifier: "cs_CZ")

            if let date = inputFormatter.date(from: apiMonth) {
                let formatted = outputFormatter.string(from: date)
                // První písmeno velké (březen -> Březen)
                return formatted.prefix(1).uppercased() + formatted.dropFirst()
            }
        }
        return "Aktuální měsíc"
    }

    private var accessibilityBannerLabel: String {
        if isLoadingCommission {
            return "Provize za aktuální měsíc, načítám"
        } else if let err = commissionError {
            return "Provize za aktuální měsíc, chyba: \(err)"
        } else if let c = commission {
            return "Provize za aktuální měsíc \(formatCommission(c.commission)) \(c.currency)"
        } else {
            return "Provize za aktuální měsíc"
        }
    }

    @ViewBuilder
    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [
                        Color.primary.opacity(0.08),
                        Color.primary.opacity(0.16),
                        Color.primary.opacity(0.08)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .frame(width: 140, height: 18)
                .redacted(reason: .placeholder)
                .shimmer()

            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.08))
                .frame(width: 100, height: 12)
                .redacted(reason: .placeholder)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func errorRow(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Button {
                Task { await loadCommission() }
            } label: {
                Text("Zkusit znovu")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func valueRow(commission c: CommissionResponse) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(isCommissionHidden ? "– – – –" : formatCommission(c.commission))
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .contentTransition(.numericText())

                if !isCommissionHidden {
                    Text(c.currency)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !isCommissionHidden, let breakdownText = commissionBreakdownText(for: c) {
                Text(breakdownText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func commissionBreakdownText(for response: CommissionResponse) -> String? {
        let entryCards = response.commission_entry_cards ?? 0
        let kpiCommission = response.commission_kpi ?? 0

        if entryCards > 0 && kpiCommission > 0 {
            return "z toho \(formatCommission(entryCards)) KV a \(formatCommission(kpiCommission)) KPI"
        }
        if entryCards > 0 {
            return "z toho \(formatCommission(entryCards)) KV"
        }
        if kpiCommission > 0 {
            return "z toho \(formatCommission(kpiCommission)) KPI"
        }
        return nil
    }

    // MARK: - Data Loading

    /// Načte cíle uživatele (provize, služby) z API.
    private func loadGoals() async {
        let token = await MainActor.run { authState.authToken }
        guard let token, !token.isEmpty else { return }
        do {
            let (commissionGoal, servicesGoal) = try await userGoalsService.fetchGoals(token: token)
            await MainActor.run {
                self.commissionGoal = commissionGoal
                self.servicesGoal = servicesGoal
                if let goal = commissionGoal {
                    WidgetDataStore.saveCommissionGoal(goal)
                }
            }
        } catch {
            // Cíle nejsou kritické – při chybě zůstane výchozí 100k
        }
    }

    /// Načte provizi z API. Při `silent: true` se nespouští loading stav – vhodné pro periodické obnovení na pozadí.
    private func loadCommission(silent: Bool = false) async {
        let token = await MainActor.run { authState.authToken }
        guard let token else {
            await MainActor.run {
                commission = nil
                commissionError = "Pro zobrazení provize se přihlaste."
            }
            return
        }
        if !silent {
            await MainActor.run {
                isLoadingCommission = true
                commissionError = nil
                commission = nil
            }
        }

        do {
            let response = try await commissionService.fetchCommission(token: token)
            // Načteme cíle společně s provizí (stejný token) – zaručí správný cíl pro graf
            let (goal, servicesGoal) = (try? await userGoalsService.fetchGoals(token: token)) ?? (nil, nil)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    commission = response
                    if let goal { commissionGoal = goal }
                    if let servicesGoal { self.servicesGoal = servicesGoal }
                }
                isLoadingCommission = false
                WidgetDataStore.saveCommission(response.commission, currency: response.currency, monthLabel: response.month_label)
                if let goal { WidgetDataStore.saveCommissionGoal(goal) }
                CommissionLiveActivityManager.update(
                    commission: response.commission,
                    currency: response.currency,
                    monthLabel: response.month_label,
                    goal: goal ?? commissionGoal,
                    isHidden: isCommissionHidden
                )
                PhoneSessionManager.shared.sendCommissionUpdate(
                    commission: response.commission,
                    currency: response.currency,
                    monthLabel: response.month_label,
                    commissionGoal: goal ?? commissionGoal
                )
            }
        } catch {
            await MainActor.run {
                if !silent {
                    commissionError = error.localizedDescription
                }
                isLoadingCommission = false
            }
        }
    }

    private func formatCommission(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private var pointsLabel: String {
        guard let dealwarsXP else { return "0 XP" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = " "
        let value = formatter.string(from: NSNumber(value: dealwarsXP)) ?? "0"
        return "\(value) XP"
    }

    /// Načte počet položek čekajících na dokončení. Při chybě nastaví 0 (container se nezobrazí).
    private func loadPendingCompletion() async {
        let token = await MainActor.run { authState.authToken }
        guard let token, !token.isEmpty else {
            await MainActor.run { pendingCompletionCount = nil }
            return
        }
        do {
            let count = try await pendingCompletionService.fetchPendingCount(token: token)
            await MainActor.run { pendingCompletionCount = count }
        } catch {
            await MainActor.run { pendingCompletionCount = 0 }
        }
    }

    /// Načte celkový počet služeb uživatele.
    private func loadServicesCount() async {
        let token = await MainActor.run { authState.authToken }
        guard let token, !token.isEmpty else {
            await MainActor.run { servicesCount = nil }
            return
        }
        do {
            let count = try await orderItemsCountService.fetchCount(token: token)
            await MainActor.run {
                servicesCount = count
                PhoneSessionManager.shared.sendServicesCountUpdate(count: count)
            }
        } catch {
            await MainActor.run { servicesCount = nil }
        }
    }

    /// Načte statistiku Karty vchodu (součet `entries_count` za aktuální měsíc).
    private func loadEntryCardsCount() async {
        let token = await MainActor.run { authState.authToken }
        guard let token, !token.isEmpty else {
            await MainActor.run { entryCardsCount = nil }
            return
        }
        do {
            let response = try await entryCardsCountService.fetchCount(token: token)
            await MainActor.run {
                entryCardsCount = response.entries_count
            }
        } catch {
            await MainActor.run { entryCardsCount = nil }
        }
    }

    /// Načte moje pořadí a XP z Dealwars sezóny.
    private func loadDealwarsSummary() async {
        let token = await MainActor.run { authState.authToken }
        let currentUserId = await MainActor.run { authState.currentUser?.id }
        guard let token, !token.isEmpty, let currentUserId else {
            await MainActor.run {
                dealwarsRank = nil
                dealwarsXP = nil
            }
            return
        }

        do {
            let payload = try await dealwarsSeasonService.fetchSeason(token: token, season: nil, scope: "team")
            let mine = payload.leaderboard.first(where: { $0.userId == currentUserId })
            await MainActor.run {
                dealwarsRank = mine?.rank
                dealwarsXP = mine?.points
            }
        } catch {
            await MainActor.run {
                dealwarsRank = nil
                dealwarsXP = nil
            }
        }
    }
}

/// Měkký oblouk v barvách loga (oranžová + zlatá + jemná fialová).
private struct HomeTopArchGlow: View {
    private let logoOrange = Color(red: 0.97, green: 0.58, blue: 0.12)
    private let logoGold = Color(red: 0.98, green: 0.69, blue: 0.23)
    private let logoPurple = Color(red: 0.30, green: 0.05, blue: 0.22)

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height: CGFloat = 380

            ZStack(alignment: .top) {
                LinearGradient(
                    stops: [
                        .init(color: logoOrange.opacity(0.30), location: 0),
                        .init(color: logoGold.opacity(0.18), location: 0.32),
                        .init(color: logoGold.opacity(0.08), location: 0.58),
                        .init(color: logoGold.opacity(0.02), location: 0.8),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                LinearGradient(
                    colors: [
                        logoPurple.opacity(0.12),
                        logoPurple.opacity(0.04),
                        .clear
                    ],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
            }
            .frame(width: width, height: height)
            .mask {
                // Oblouk + měkký alpha fade, ať okraj není ostrý
                HomeTopArchShape()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white, location: 0.45),
                                .init(color: .white.opacity(0.55), location: 0.72),
                                .init(color: .white.opacity(0.15), location: 0.9),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .frame(width: width, height: height, alignment: .top)
        }
        .frame(height: 380)
    }
}

/// Spodní hrana do oblouku (výraznější uprostřed, měkčí po stranách).
private struct HomeTopArchShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY * 0.58))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: rect.maxY * 0.58),
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

// Jednoduchý shimmer efekt pro skeleton (iOS 15+ fallback bez animace)
private extension View {
    @ViewBuilder
    func homeListSectionSpacing() -> some View {
        if #available(iOS 17.0, *) {
            self.listSectionSpacing(8)
        } else {
            self
        }
    }

    @ViewBuilder
    func shimmer(active: Bool = true, duration: Double = 1.2) -> some View {
        if #available(iOS 15.0, *), active {
            self
                .overlay {
                    GeometryReader { proxy in
                        let size = proxy.size
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        .white.opacity(0.6),
                                        .clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .rotationEffect(.degrees(20))
                            .offset(x: -size.width)
                            .frame(width: size.width * 1.5)
                            .mask(self)
                            .animation(.linear(duration: duration).repeatForever(autoreverses: false), value: UUID())
                    }
                }
        } else {
            self
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AuthState())
}
