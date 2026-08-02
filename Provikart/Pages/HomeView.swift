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
    @State private var commission: CommissionResponse? = CommissionResponse.loadCached()
    @State private var commissionError: String?
    @State private var isLoadingCommission = false
    @State private var isCommissionHidden = WidgetDataStore.isCommissionHidden
    /// Cíl provize z API (null = použije se výchozí 100k).
    @State private var commissionGoal: Double? = WidgetDataStore.loadCommissionGoal()
    /// Cíl počtu služeb z API (null = výchozí 100).
    @State private var servicesGoal: Int?
    /// Počet položek po termínu instalace čekajících na dokončení. nil = nenačteno, 0 = žádné, >0 = zobrazit container.
    @State private var pendingCompletionCount: Int?
    /// Celkový počet služeb (order_items bez migrace). nil = nenačteno.
    @State private var servicesCount: Int?
    /// Počet záznamů z Karty vchodu za aktuální měsíc. nil = nenačteno.
    @State private var entryCardsCount: Int?
    /// Dealwars: celkový level hráče (hned z cache, pak API).
    @State private var dealwarsLevel: DealwarsLevelInfo? = DealwarsLevelInfo.loadCached()
    @State private var dealwarsRank: Int? = {
        guard UserDefaults.standard.object(forKey: "dealwars_rank_cache") != nil else { return nil }
        return UserDefaults.standard.integer(forKey: "dealwars_rank_cache")
    }()
    @State private var dealwarsXP: Double? = {
        guard let number = UserDefaults.standard.object(forKey: "dealwars_xp_cache") as? NSNumber else { return nil }
        return number.doubleValue
    }()
    @State private var luckyBoxStatus: LuckyBoxHomeStatus = .current()
    @State private var luckyBoxTick = Date()

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
                        DealwarsLevelDetailView(initialLevel: dealwarsLevel)
                            .environmentObject(authState)
                    } label: {
                        dealwarsLevelRow(dealwarsLevel)
                    }
                    .buttonStyle(.plain)
                    .navigationLinkIndicatorVisibility(.hidden)
                    .listRowBackground(dealwarsLevelBackground)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section {
                    NavigationLink {
                        LuckyBoxView()
                            .environmentObject(authState)
                    } label: {
                        luckyBoxRow
                    }
                    .buttonStyle(.plain)
                    .navigationLinkIndicatorVisibility(.hidden)
                    .listRowBackground(luckyBoxBackground)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }

                Section {
                    NavigationLink {
                        DealwarsView()
                            .environmentObject(authState)
                    } label: {
                        dealwarsRow
                    }
                    .buttonStyle(.plain)
                    .navigationLinkIndicatorVisibility(.hidden)
                    .listRowBackground(dealwarsBackground)
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
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
                        CalendarView()
                            .environmentObject(authState)
                            .environment(\.openAddSheet, openAddSheet)
                    } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("Kalendář")
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
                        CollectiblesCollectionView()
                            .environmentObject(authState)
                    } label: {
                        Image(systemName: "square.grid.2x2.fill")
                    }
                    .accessibilityLabel("Sbírka")
                    NavigationLink {
                        StatisticsView()
                            .environmentObject(authState)
                            .environment(\.openAddSheet, openAddSheet)
                    } label: {
                        Image(systemName: "chart.bar")
                    }
                    .accessibilityLabel("Statistiky")
                    ProfileBarButton()
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear {
                refreshLuckyBoxStatus()
            }
        }
        .task {
            // Obnov uložený cíl hned (z předchozího načtení), než stáhneme z API
            if commissionGoal == nil, let saved = WidgetDataStore.loadCommissionGoal() {
                commissionGoal = saved
            }
            refreshLuckyBoxStatus()
            // Dealwars + level + provize hned paralelně s ostatním.
            async let dealwars: Void = loadDealwarsSummary()
            async let goals: Void = loadGoals()
            async let commission: Void = loadCommission(silent: commission != nil)
            async let pending: Void = loadPendingCompletion()
            async let services: Void = loadServicesCount()
            async let entries: Void = loadEntryCardsCount()
            _ = await (dealwars, goals, commission, pending, services, entries)

            // Periodické obnovení na pozadí (každých 5 s) – silent, bez blikání.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { break }
                refreshLuckyBoxStatus()
                async let d: Void = loadDealwarsSummary()
                async let g: Void = loadGoals()
                async let c: Void = loadCommission(silent: true)
                async let p: Void = loadPendingCompletion()
                async let s: Void = loadServicesCount()
                async let e: Void = loadEntryCardsCount()
                _ = await (d, g, c, p, s, e)
            }
        }
        .refreshable {
            await loadGoals()
            await loadCommission(silent: true)
            await loadPendingCompletion()
            await loadServicesCount()
            await loadEntryCardsCount()
            await loadDealwarsSummary()
        }
    }

    // MARK: - Commission Row (iOS List style)

    private var luckyBoxRow: some View {
        let gold = Color(red: 1.0, green: 0.86, blue: 0.42)
        let orange = Color(red: 0.97, green: 0.58, blue: 0.12)
        let ready: Bool = {
            if case .ready = luckyBoxStatus { return true }
            return false
        }()

        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [gold.opacity(0.95), orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .shadow(color: orange.opacity(0.35), radius: 6, y: 2)
                Image(systemName: "gift.fill")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Lucky Box")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)

                switch luckyBoxStatus {
                case .ready:
                    Text("Připraveno k otevření")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(gold)
                case .opened(let countdown):
                    Text("Další zítra · \(countdown)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 0)

            if ready {
                Text("OTEVŘÍT")
                    .font(.caption2.weight(.heavy))
                    .tracking(0.6)
                    .foregroundStyle(Color(red: 0.22, green: 0.08, blue: 0.16))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [gold, orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            }

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.4))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            ready
                ? "Lucky Box, připraveno k otevření"
                : "Lucky Box, dnes už otevřeno"
        )
    }

    private var luckyBoxBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let gold = Color(red: 1.0, green: 0.86, blue: 0.42)
        let orange = Color(red: 0.97, green: 0.58, blue: 0.12)
        return ZStack {
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.28, blue: 0.38),
                            Color(red: 0.12, green: 0.18, blue: 0.28),
                            Color(red: 0.10, green: 0.12, blue: 0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            shape
                .stroke(
                    LinearGradient(
                        colors: [gold.opacity(0.45), orange.opacity(0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: orange.opacity(0.12), radius: 6, y: 2)
    }

    private func refreshLuckyBoxStatus() {
        luckyBoxTick = Date()
        luckyBoxStatus = .current(now: luckyBoxTick)
    }

    private func dealwarsLevelRow(_ level: DealwarsLevelInfo?) -> some View {
        let gold = Color(red: 1.0, green: 0.86, blue: 0.42)
        let orange = Color(red: 0.97, green: 0.58, blue: 0.12)
        let progress = level?.progressFraction ?? 0
        let pct = level.map { Int($0.levelProgressPct.rounded()) }

        return HStack(spacing: 12) {
            Text(level.map { "\($0.level)" } ?? "—")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(gold)
                .monospacedDigit()
                .frame(minWidth: 36, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text("Level")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.16))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [gold, orange],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(4, geo.size.width * progress))
                    }
                }
                .frame(height: 5)
            }

            Text(pct.map { "\($0) %" } ?? "—")
                .font(.caption.weight(.bold))
                .foregroundStyle(gold.opacity(0.9))
                .monospacedDigit()

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.4))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            level.map {
                "Level \($0.level), \(Int($0.levelProgressPct.rounded())) procent, \($0.pointsToNextLevel) do dalšího levelu"
            } ?? "Level se načítá"
        )
    }

    private var dealwarsLevelBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let gold = Color(red: 1.0, green: 0.86, blue: 0.42)
        let orange = Color(red: 0.97, green: 0.58, blue: 0.12)
        return ZStack {
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.42, green: 0.18, blue: 0.28),
                            Color(red: 0.28, green: 0.10, blue: 0.22)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            shape
                .stroke(gold.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: orange.opacity(0.12), radius: 4, y: 2)
    }

    private var dealwarsRow: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.98, green: 0.72, blue: 0.28).opacity(0.55),
                                Color(red: 0.97, green: 0.58, blue: 0.12).opacity(0.18)
                            ],
                            center: .topLeading,
                            startRadius: 2,
                            endRadius: 28
                        )
                    )
                    .frame(width: 52, height: 52)
                Circle()
                    .stroke(Color(red: 0.98, green: 0.69, blue: 0.23).opacity(0.45), lineWidth: 1)
                    .frame(width: 52, height: 52)
                Image(systemName: "trophy.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.86, blue: 0.42),
                                Color(red: 0.97, green: 0.58, blue: 0.12)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color(red: 0.97, green: 0.58, blue: 0.12).opacity(0.45), radius: 8, y: 2)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Dealwars")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    Text(dealwarsRank.map { "#\($0)" } ?? "—")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(red: 0.22, green: 0.08, blue: 0.16))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 1.0, green: 0.86, blue: 0.42),
                                            Color(red: 0.97, green: 0.62, blue: 0.18)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )

                    Text("Moje pořadí")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(pointsValueLabel)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text("XP")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(red: 0.98, green: 0.69, blue: 0.23))
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dealwars, pořadí \(dealwarsRank.map { String($0) } ?? "neznámé"), \(pointsLabel)")
    }

    private var dealwarsBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return ZStack {
            // Teplé oranžovo-jantarové pozadí (ne šedé)
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.72, green: 0.38, blue: 0.08),
                            Color(red: 0.52, green: 0.22, blue: 0.10),
                            Color(red: 0.36, green: 0.12, blue: 0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.78, blue: 0.28).opacity(0.35),
                            Color(red: 0.97, green: 0.55, blue: 0.12).opacity(0.12),
                            .clear
                        ],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                )

            shape
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.86, blue: 0.42).opacity(0.7),
                            Color(red: 0.97, green: 0.58, blue: 0.12).opacity(0.35),
                            Color(red: 0.30, green: 0.05, blue: 0.22).opacity(0.25)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        }
        .shadow(color: Color(red: 0.97, green: 0.58, blue: 0.12).opacity(0.22), radius: 10, y: 4)
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

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("Provize")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
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
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        Text(monthTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if let c = commission,
                           !isCommissionHidden,
                           let breakdownText = commissionBreakdownText(for: c) {
                            Text(breakdownText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        } else if let err = commissionError, commission == nil {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Group {
                        if let c = commission {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(isCommissionHidden ? "– – – –" : formatCommission(c.commission))
                                    .font(.system(.title, design: .rounded).weight(.bold))
                                    .foregroundStyle(.primary)
                                    .minimumScaleFactor(0.6)
                                    .lineLimit(1)
                                    .contentTransition(.numericText())
                                    .animation(.snappy(duration: 0.35), value: c.commission)
                                if !isCommissionHidden {
                                    Text(c.currency)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else if isLoadingCommission {
                            ProgressView()
                        } else {
                            Text("—")
                                .font(.system(.title, design: .rounded).weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

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
        if let c = commission {
            return "Provize za aktuální měsíc \(formatCommission(c.commission)) \(c.currency)"
        } else if isLoadingCommission {
            return "Provize za aktuální měsíc, načítám"
        } else if let err = commissionError {
            return "Provize za aktuální měsíc, chyba: \(err)"
        } else {
            return "Provize za aktuální měsíc"
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

    /// Načte provizi z API. Při `silent: true` (nebo když už máme cache) se nespouští skeleton.
    private func loadCommission(silent: Bool = false) async {
        let token = await MainActor.run { authState.authToken }
        guard let token else {
            await MainActor.run {
                commission = nil
                commissionError = "Pro zobrazení provize se přihlaste."
                CommissionResponse.clearCached()
            }
            return
        }

        let hasExisting = await MainActor.run { commission != nil }
        if !silent && !hasExisting {
            await MainActor.run {
                isLoadingCommission = true
                commissionError = nil
            }
        } else if !silent {
            await MainActor.run { commissionError = nil }
        }

        do {
            let response = try await commissionService.fetchCommission(token: token)
            await MainActor.run {
                let previous = commission
                let didChange = previous != response
                isLoadingCommission = false

                guard didChange else { return }

                withAnimation(.snappy(duration: 0.35)) {
                    commission = response
                }
                CommissionResponse.saveCached(response)
                WidgetDataStore.saveCommission(
                    response.commission,
                    currency: response.currency,
                    monthLabel: response.month_label
                )
                CommissionLiveActivityManager.update(
                    commission: response.commission,
                    currency: response.currency,
                    monthLabel: response.month_label,
                    goal: commissionGoal,
                    isHidden: isCommissionHidden
                )
                PhoneSessionManager.shared.sendCommissionUpdate(
                    commission: response.commission,
                    currency: response.currency,
                    monthLabel: response.month_label,
                    commissionGoal: commissionGoal
                )
            }
        } catch {
            await MainActor.run {
                // Při chybě necháme poslední známou částku (cache) – bez blikání.
                if !silent && commission == nil {
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
        "\(pointsValueLabel) XP"
    }

    private var pointsValueLabel: String {
        guard let dealwarsXP else { return "0" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = " "
        return formatter.string(from: NSNumber(value: dealwarsXP)) ?? "0"
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

    /// Načte moje pořadí, XP a level z Dealwars sezóny.
    private func loadDealwarsSummary() async {
        let token = await MainActor.run { authState.authToken }
        let currentUserId = await MainActor.run { authState.currentUser?.id }
        guard let token, !token.isEmpty, let currentUserId else {
            await MainActor.run {
                dealwarsRank = nil
                dealwarsXP = nil
                dealwarsLevel = nil
                DealwarsLevelInfo.clearCached()
                UserDefaults.standard.removeObject(forKey: "dealwars_rank_cache")
                UserDefaults.standard.removeObject(forKey: "dealwars_xp_cache")
            }
            return
        }

        do {
            let payload = try await dealwarsSeasonService.fetchSeason(token: token, season: nil, scope: "team")
            let mine = payload.leaderboard.first(where: { $0.userId == currentUserId })
            await MainActor.run {
                dealwarsRank = mine?.rank
                dealwarsXP = mine?.points
                if let myLevel = payload.myLevel {
                    dealwarsLevel = myLevel
                    DealwarsLevelInfo.saveCached(myLevel)
                }
                if let rank = mine?.rank {
                    UserDefaults.standard.set(rank, forKey: "dealwars_rank_cache")
                }
                if let xp = mine?.points {
                    UserDefaults.standard.set(xp, forKey: "dealwars_xp_cache")
                }
            }
        } catch {
            // Necháme poslední známé hodnoty (cache) – banner zůstane viditelný.
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

// Jednoduchý helper pro list spacing
private extension View {
    @ViewBuilder
    func homeListSectionSpacing() -> some View {
        if #available(iOS 17.0, *) {
            self.listSectionSpacing(8)
        } else {
            self
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AuthState())
}
