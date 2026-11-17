//
//  ManagerHomeView.swift
//  Provikart
//
//  Manažerský Home – nativní přehled týmu.
//

import SwiftUI
import Charts
import UIKit

@MainActor
final class ManagerHomeViewModel: ObservableObject {
    @Published var payload: ManagerOverviewPayload?
    @Published var monthProgress: ManagerOverviewProgress?
    /// Zvýší se po každém úspěšném načtení – spouští překreslení grafů.
    @Published var revision = 0
    @Published var periodLabel = "Tento týden"
    @Published var period: ManagerOverviewPeriod = .week
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// Heatmapa složená z Výkonu, když ji přehled (API) zatím neposílá.
    @Published private var fallbackHeatmap: ManagerOverviewHeatmap?

    private let service = ManagerOverviewService()
    private let performanceService = ManagerTeamPerformanceService()
    private var loadGeneration = 0
    private var heatmapFetchedAt: Date?
    private var heatmapLoading = false

    /// Aktivita po dnech – z API, jinak z Výkonu týmu.
    var heatmap: ManagerOverviewHeatmap? {
        payload?.heatmap ?? fallbackHeatmap
    }

    func load(token: String?, silent: Bool = false) async {
        guard let token, !token.isEmpty else {
            errorMessage = "Nejste přihlášeni."
            return
        }
        loadGeneration += 1
        let generation = loadGeneration
        if !silent && payload == nil {
            isLoading = true
        }
        do {
            let (data, label) = try await service.fetchOverview(token: token, period: period)
            guard generation == loadGeneration else { return }
            payload = data
            periodLabel = label
            errorMessage = nil
            isLoading = false
            revision += 1
            if data.heatmap == nil {
                Task { await loadHeatmapFallback(token: token) }
            }
            if period == .month {
                monthProgress = data.progress
            } else {
                await loadMonthProgress(token: token, generation: generation)
            }
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration else { return }
            isLoading = false
            if payload == nil {
                errorMessage = error.localizedDescription
            } else {
                // Starý graf znovu ukázat, ať po chybě nezůstane schovaný.
                revision += 1
            }
        }
    }

    /// Kumulativní křivka služeb za celý měsíc – podklad pro graf plánu,
    /// nezávisle na zvoleném období.
    private func loadMonthProgress(token: String, generation: Int) async {
        guard let (data, _) = try? await service.fetchOverview(token: token, period: .month),
              generation == loadGeneration else { return }
        monthProgress = data.progress
    }

    /// Načte Výkon za měsíce, které heatmapa pokrývá (paralelně), a složí ji.
    /// Výsledek drží 5 minut, ať se při přepínání období nenačítá pořád dokola.
    private func loadHeatmapFallback(token: String) async {
        if heatmapLoading { return }
        if let fetched = heatmapFetchedAt, Date().timeIntervalSince(fetched) < 300, fallbackHeatmap != nil { return }
        heatmapLoading = true
        defer { heatmapLoading = false }

        let months = ManagerHeatmapBuilder.monthsToFetch()
        let service = performanceService
        let payloads = await withTaskGroup(of: ManagerTeamPerformancePayload?.self) { group in
            for month in months {
                group.addTask { try? await service.fetchPerformance(token: token, month: month) }
            }
            var out: [ManagerTeamPerformancePayload] = []
            for await payload in group {
                if let payload { out.append(payload) }
            }
            return out
        }
        guard !payloads.isEmpty else { return }
        fallbackHeatmap = ManagerHeatmapBuilder.build(from: payloads)
        heatmapFetchedAt = Date()
    }
}

struct ManagerHomeView: View {
    @EnvironmentObject private var authState: AuthState
    @Binding var selectedTab: ManagerTabs
    @StateObject private var viewModel = ManagerHomeViewModel()
    @State private var heatmapDay: ManagerHeatmapDayRoute?
    @State private var showLocations = false
    @State private var chartReveal: CGFloat = 0
    /// Klíč (období + data) právě vykresleného grafu – mění identitu Chartu.
    @State private var drawnProgressKey = ""
    @State private var drawnPlanKey = ""
    @State private var planReveal: CGFloat = 0
    @State private var mixRoute: ManagerServicesMixRoute?
    @State private var showServicesStats = false
    @Namespace private var periodAnimation
    @Environment(\.colorScheme) private var scheme


    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.payload == nil {
                    ProgressView("Načítám přehled…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let message = viewModel.errorMessage, viewModel.payload == nil {
                    ContentUnavailableView {
                        Label("Přehled se nepodařilo načíst", systemImage: "chart.bar.xaxis")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Zkusit znovu") {
                            Task { await viewModel.load(token: authState.authToken) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    homeList
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
                    ManagerAddReportToolbarButton()
                    Button {
                        showLocations = true
                    } label: {
                        Image(systemName: "mappin.and.ellipse")
                    }
                    .accessibilityLabel("Lokality týmu")
                    ManagerNotificationsBellButton()
                    ProfileBarButton()
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(item: $heatmapDay) { route in
                let cell = viewModel.heatmap?.weeks.flatMap { $0 }.first { $0.date == route.date }
                ManagerHeatmapDayView(
                    date: route.date,
                    count: cell?.count ?? 0,
                    detail: viewModel.heatmap?.days[route.date],
                    tint: svCoral
                )
            }
            .sheet(isPresented: $showServicesStats) {
                ManagerServicesStatsView(
                    viewModel: viewModel,
                    onOpenPerformance: { selectedTab = .performance }
                )
            }
            .sheet(item: $mixRoute) { route in
                ManagerServicesMixDetailView(
                    slices: viewModel.payload?.servicesBreakdown ?? [],
                    detail: viewModel.payload?.mixDetail,
                    initialKey: route.key,
                    periodLabel: viewModel.periodLabel,
                    periodPhrase: periodPhrase,
                    onOpenPerformance: { selectedTab = .performance }
                )
            }
            .sheet(isPresented: $showLocations) {
                ManagerLocationsSheetView()
                    .environmentObject(authState)
            }
            .refreshable {
                await viewModel.load(token: authState.authToken, silent: true)
            }
            .task {
                await viewModel.load(token: authState.authToken)
            }
            .onChange(of: viewModel.period) { _, _ in
                hideProgressChart()
                Task { await viewModel.load(token: authState.authToken, silent: true) }
            }
            .onChange(of: viewModel.revision) { _, _ in
                redrawProgressIfNeeded()
            }
        }
    }

    private var homeList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    welcomeHeader
                    periodSelector
                }
                alertsBlock.homeCardAppear(0)
                progressCard
                    .contentShape(Rectangle())
                    .onTapGesture {
                        bump()
                        showServicesStats = true
                    }
                    .homeCardAppear(1)
                servicesCard.homeCardAppear(2)
                planCard.homeCardAppear(3)
                heatmapCard.homeCardAppear(4)
                feeCard.homeCardAppear(4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 36)
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Dobré ráno" }
        if hour < 18 { return "Dobré odpoledne" }
        return "Dobrý večer"
    }

    private var firstName: String {
        let raw = authState.currentUser?.firstname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !raw.isEmpty { return raw }
        let name = authState.currentUser?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.split(separator: " ").first.map(String.init) ?? "manažere"
    }

    /// Kompaktní přivítání – jeden řádek, ať nahoře zbude místo na obsah.
    /// Role je v Profilu, počet členů v sekci Tým.
    private var welcomeHeader: some View {
        (Text("\(greetingText), ").foregroundStyle(.secondary)
            + Text(firstName).foregroundStyle(.primary))
            .font(.system(.title3, design: .rounded).weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private var periodSelector: some View {
        HStack(spacing: 4) {
            ForEach(ManagerOverviewPeriod.allCases) { item in
                Button {
                    bump()
                    withAnimation(.snappy(duration: 0.28)) {
                        viewModel.period = item
                    }
                } label: {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(viewModel.period == item ? svOnPill : Color.primary.opacity(0.84))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if viewModel.period == item {
                                Capsule()
                                    .fill(svPill)
                                    .matchedGeometryEffect(id: "period", in: periodAnimation)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .background(glassFill, in: Capsule())
        .overlay(Capsule().strokeBorder(glassRim))
    }

    // MARK: - Karty ve stylu webového přehledu

    private var isDark: Bool { scheme == .dark }
    /// Paleta shodná s webovým přehledem (--sv-*).
    private var svCoral: Color { isDark ? Color(red: 1.00, green: 0.60, blue: 0.49) : Color(red: 0.95, green: 0.49, blue: 0.37) }
    private var svLime: Color { isDark ? Color(red: 0.80, green: 0.94, blue: 0.42) : Color(red: 0.66, green: 0.84, blue: 0.21) }
    private var svGood: Color { isDark ? Color(red: 0.72, green: 0.90, blue: 0.35) : Color(red: 0.24, green: 0.48, blue: 0.08) }
    private var svBad: Color { isDark ? Color(red: 1.00, green: 0.60, blue: 0.49) : Color(red: 0.72, green: 0.25, blue: 0.12) }
    private let svAccent = Color(red: 0.99, green: 0.745, blue: 0.19)
    private let svInk = Color(red: 0.075, green: 0.09, blue: 0.10)
    private var svPill: Color { isDark ? Color(red: 0.345, green: 0.37, blue: 0.365).opacity(0.74) : svInk }
    private var svOnPill: Color { isDark ? Color(red: 0.95, green: 0.96, blue: 0.94) : Color(red: 0.965, green: 0.97, blue: 0.95) }

    private var periodPhrase: String {
        switch viewModel.period {
        case .today: return "dnes"
        case .yesterday: return "včera"
        case .week: return "tento týden"
        case .month: return "tento měsíc"
        }
    }

    private func svCard<Content: View>(
        _ title: String,
        icon: String = "arrow.up.right",
        onTap: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.headline.weight(.semibold))
                Spacer(minLength: 8)
                if let onTap {
                    Button {
                        bump()
                        onTap()
                    } label: {
                        Image(systemName: icon)
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Otevřít \(title)")
                }
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface(radius: 24))
    }

    private func svChip(_ text: String, tone: String) -> some View {
        let color: Color = tone == "up" ? svLime : (tone == "down" ? svCoral : .secondary)
        let textColor: Color = tone == "up" ? svGood : (tone == "down" ? svBad : .secondary)
        let icon = tone == "up" ? "arrow.up" : (tone == "down" ? "arrow.down" : "minus")
        return HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .heavy))
            Text(text).font(.caption.weight(.bold))
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.16), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.32)))
    }

    private func svFacts(_ items: [(String, String)]) -> some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(spacing: 3) {
                    Text(item.0)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(item.1)
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var progressCard: some View {
        if let progress = viewModel.payload?.progress {
            svCard("Služby", icon: "chart.xyaxis.line", onTap: { showServicesStats = true }) {
                HStack(alignment: .bottom, spacing: 14) {
                    Text("\(progress.currentTotal)")
                        .font(.system(size: 62, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .tracking(-2)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    VStack(alignment: .leading, spacing: 6) {
                        if !progress.verdict.isEmpty {
                            svChip(progress.verdict, tone: progress.tone)
                        }
                        Text("služeb \(periodPhrase)")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 8)
                }

                if progress.compact, let daily = idealDailyPace {
                    let idealNow = Int(daily.rounded())
                    let diff = progress.currentTotal - idealNow
                    HStack(spacing: 8) {
                        Capsule()
                            .fill(svAccent)
                            .frame(width: 16, height: 3)
                        Text("Ideálně \(idealNow) služeb za den")
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Text(diff >= 0 ? "+\(diff)" : "\(diff)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(diff >= 0 ? svGood : svBad)
                    }
                    .font(.footnote.weight(.medium))
                }

                if !progress.compact && !progress.labels.isEmpty {
                    HStack(spacing: 14) {
                        progressLegend(progress.currentLabel, svCoral, dashed: false)
                        progressLegend(progress.previousLabel, .secondary, dashed: true)
                        if idealDailyPace != nil {
                            progressLegend("Ideální tempo", svAccent, dashed: true)
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                    progressChart(progress)
                        .id(drawnProgressKey)
                        .transaction { $0.animation = nil }
                        .frame(height: 190)
                        .mask(alignment: .leading) {
                            GeometryReader { geo in
                                Rectangle()
                                    .frame(width: max(0, geo.size.width * chartReveal))
                            }
                        }
                }

                if !progress.story.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(svCoral)
                        Text(progress.story)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func planColor(_ pct: Int) -> Color {
        let k = Double(max(0, min(100, pct))) / 100
        return Color(hue: (125 * k) / 360, saturation: 0.78 + 0.04 * k, brightness: 0.90)
    }

    private var daysLeftInMonth: Int {
        let cal = Calendar.current
        let now = Date()
        let days = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        return max(0, days - cal.component(.day, from: now))
    }

    /// Data pro graf plánu: skutečnost (kumulativně po dnech měsíce),
    /// ideální lineární tempo k cíli a odhad do konce měsíce.
    private var planCurve: ManagerPlanCurve? {
        guard let meta = viewModel.payload?.servicesMeta, meta.hasGoal else { return nil }
        let cal = Calendar.current
        let calendarDays = cal.range(of: .day, in: .month, for: Date())?.count ?? 30
        let progress = viewModel.monthProgress
        let series = progress?.current ?? []
        let days = max(1, series.isEmpty ? calendarDays : series.count)

        var actual: [ManagerPlanCurve.Point] = [.init(day: 0, value: 0)]
        var todayDay = min(days, cal.component(.day, from: Date()))
        if !series.isEmpty {
            let lastKnown = series.lastIndex(where: { $0 != nil }) ?? -1
            let today = progress?.todayIndex ?? lastKnown
            todayDay = max(0, min(days, today + 1))
            for (index, value) in series.enumerated() where index < todayDay {
                if let value { actual.append(.init(day: index + 1, value: Double(value))) }
            }
        }
        // Poslední bod skutečnosti srovnáme s měsíčním součtem z plánu.
        let doneNow = Double(meta.monthTotal)
        if let last = actual.last, last.day == todayDay {
            actual[actual.count - 1] = .init(day: todayDay, value: max(last.value, doneNow))
        } else if todayDay > 0 {
            actual.append(.init(day: todayDay, value: doneNow))
        }

        let goal = Double(meta.teamGoal)
        let ideal = (0...days).map { ManagerPlanCurve.Point(day: $0, value: goal * Double($0) / Double(days)) }

        var forecast: [ManagerPlanCurve.Point] = []
        if todayDay > 0 && todayDay < days {
            let predicted = meta.prediction.map(Double.init) ?? doneNow / Double(todayDay) * Double(days)
            forecast = [.init(day: todayDay, value: doneNow), .init(day: days, value: max(doneNow, predicted))]
        }

        return ManagerPlanCurve(
            days: days,
            todayDay: todayDay,
            goal: goal,
            done: doneNow,
            actual: actual,
            ideal: ideal,
            forecast: forecast
        )
    }

    private var planSignature: String {
        guard let curve = planCurve else { return "none" }
        return "\(curve.days)|\(curve.todayDay)|\(Int(curve.goal))|" + curve.actual.map { "\(Int($0.value))" }.joined(separator: ",")
    }

    private func playPlanDraw() {
        guard planSignature != drawnPlanKey || planReveal < 1 else { return }
        drawnPlanKey = planSignature
        resetThenAnimate(
            reset: { planReveal = 0 },
            animation: .spring(response: 1.1, dampingFraction: 0.86),
            to: { planReveal = 1 }
        )
    }

    /// Reset a animace musí proběhnout v různých snímcích, jinak je SwiftUI
    /// sloučí a graf se vůbec nepřekreslí.
    private func resetThenAnimate(reset: @escaping () -> Void, animation: Animation, to target: @escaping () -> Void) {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant, reset)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            withAnimation(animation, target)
        }
    }

    /// Ideální počet služeb za den = měsíční cíl / počet dní v měsíci.
    private var idealDailyPace: Double? {
        guard let meta = viewModel.payload?.servicesMeta, meta.hasGoal else { return nil }
        let days = Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30
        return Double(meta.teamGoal) / Double(max(1, days))
    }

    @ViewBuilder
    private var planCard: some View {
        if let meta = viewModel.payload?.servicesMeta {
            let title = meta.monthName.isEmpty ? "Plán služeb" : "Plán služeb · \(meta.monthName)"
            svCard(title, onTap: { selectedTab = .performance }) {
                if meta.hasGoal, let curve = planCurve {
                    planHeadline(meta, curve: curve)
                    planBar(curve)
                    planStatus(meta, curve: curve)

                    HStack(spacing: 14) {
                        progressLegend("Skutečnost", svCoral, dashed: false)
                        progressLegend("Ideální tempo", svAccent, dashed: true)
                        if !curve.forecast.isEmpty {
                            progressLegend("Odhad", .secondary, dashed: true)
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                    planChart(curve)
                        .id(drawnPlanKey)
                        .transaction { $0.animation = nil }
                        .frame(height: 176)
                        .mask(alignment: .leading) {
                            GeometryReader { geo in
                                Rectangle()
                                    .frame(width: max(0, geo.size.width * planReveal))
                            }
                        }

                    if !meta.categoryGoals.isEmpty {
                        planCategoryGoals(meta.categoryGoals, curve: curve)
                    }
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "target")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(svAccent)
                            .frame(width: 44, height: 44)
                            .background(svAccent.opacity(0.14), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cíl služeb zatím není nastavený")
                                .font(.subheadline.weight(.semibold))
                            Text("Hotovo tento měsíc: \(meta.monthTotal) služeb. Cíl nastavíš v přehledu na webu.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onAppear { playPlanDraw() }
            .onChange(of: planSignature) { _, _ in playPlanDraw() }
        }
    }

    /// „312 z 400 služeb · 78 %“
    private func planHeadline(_ meta: ManagerOverviewServicesMeta, curve: ManagerPlanCurve) -> some View {
        let pct = max(0, meta.planPct ?? Int((curve.done / max(1, curve.goal) * 100).rounded()))
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(meta.monthTotal)")
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .tracking(-1.5)
            Text("z \(meta.teamGoal) služeb")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text("\(Int((Double(pct) * planReveal).rounded())) %")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(planColor(pct))
                .contentTransition(.numericText(value: Double(pct) * planReveal))
        }
    }

    /// Pruh plnění: barva = hotovo, žlutá ryska = kde bychom ideálně měli být dnes.
    private func planBar(_ curve: ManagerPlanCurve) -> some View {
        let donePart = min(1, curve.done / max(1, curve.goal))
        let idealPart = min(1, curve.goal * Double(curve.todayDay) / Double(curve.days) / max(1, curve.goal))
        let idealNow = Int((curve.goal * Double(curve.todayDay) / Double(curve.days)).rounded())
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [svCoral.opacity(0.75), svCoral], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, geo.size.width * donePart * planReveal))
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(svAccent)
                        .frame(width: 3, height: 20)
                        .offset(x: max(0, min(geo.size.width - 3, geo.size.width * idealPart - 1.5)))
                        .opacity(planReveal)
                }
            }
            .frame(height: 14)

            HStack(spacing: 14) {
                planKey(svCoral, "Hotovo \(Int(curve.done))")
                planKey(svAccent, "Ideálně dnes \(idealNow)")
                Spacer(minLength: 0)
                Text("Cíl \(Int(curve.goal))")
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.semibold).monospacedDigit())
        }
    }

    private func planKey(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).foregroundStyle(.primary)
        }
    }

    /// Jedna jasná věta o stavu + co je potřeba udělat.
    private func planStatus(_ meta: ManagerOverviewServicesMeta, curve: ManagerPlanCurve) -> some View {
        let idealNow = curve.goal * Double(curve.todayDay) / Double(curve.days)
        let gap = Int((curve.done - idealNow).rounded())
        let reached = curve.done >= curve.goal
        let ahead = gap >= 0
        let tint = reached || ahead ? svGood : svBad
        let headline: String = {
            if reached { return "Cíl je splněný" }
            if gap == 0 { return "Přesně na ideálním tempu" }
            return ahead ? "Tým je o \(gap) služeb napřed" : "Tým je o \(-gap) služeb pozadu"
        }()
        let remaining = max(0, meta.remaining ?? (meta.teamGoal - meta.monthTotal))
        let detail: String = {
            if reached { return "Hotovo \(meta.monthTotal) z \(meta.teamGoal), skvělá práce." }
            let days = daysLeftInMonth
            if let needed = meta.neededDailyLabel, days > 0 {
                return "Do cíle chybí \(remaining). Stačí \(needed) služeb denně · zbývá \(days) \(dayWord(days))."
            }
            return "Do cíle chybí \(remaining) služeb."
        }()
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: reached ? "checkmark.seal.fill" : (ahead ? "hare.fill" : "tortoise.fill"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func planCategoryGoals(_ goals: [ManagerOverviewCategoryGoal], curve: ManagerPlanCurve) -> some View {
        let idealShare = min(1, Double(curve.todayDay) / Double(curve.days))
        return VStack(alignment: .leading, spacing: 10) {
            Text("Cíle podle služeb")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(goals) { cat in
                HStack(spacing: 10) {
                    Text(cat.label)
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                        .frame(width: 92, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.07))
                            Capsule()
                                .fill(planColor(cat.pct))
                                .frame(width: geo.size.width * CGFloat(max(0, min(100, cat.pct))) / 100 * planReveal)
                            Rectangle()
                                .fill(svAccent)
                                .frame(width: 2, height: 10)
                                .offset(x: max(0, geo.size.width * idealShare - 1))
                        }
                    }
                    .frame(height: 6)
                    Text("\(cat.done)/\(cat.goal)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .frame(minWidth: 46, alignment: .trailing)
                }
            }
        }
        .padding(.top, 4)
    }

    private func dayWord(_ count: Int) -> String {
        if count == 1 { return "den" }
        if count >= 2 && count <= 4 { return "dny" }
        return "dní"
    }

    private func planChart(_ curve: ManagerPlanCurve) -> some View {
        let peak = max(curve.goal, curve.actual.map(\.value).max() ?? 0, curve.forecast.map(\.value).max() ?? 0)
        let top = max(1, peak * 1.08)
        let idealToday = curve.goal * Double(curve.todayDay) / Double(curve.days)
        let ticks = Array(Set([1, 10, 20, curve.days].filter { $0 <= curve.days })).sorted()
        return Chart {
            ForEach(curve.ideal) { point in
                LineMark(
                    x: .value("Den", point.day),
                    y: .value("Služby", point.value),
                    series: .value("Řada", "ideal")
                )
                .foregroundStyle(svAccent)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 5]))
            }
            ForEach(curve.forecast) { point in
                LineMark(
                    x: .value("Den", point.day),
                    y: .value("Služby", point.value),
                    series: .value("Řada", "forecast")
                )
                .foregroundStyle(Color.secondary.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 4]))
            }
            ForEach(curve.actual) { point in
                AreaMark(
                    x: .value("Den", point.day),
                    y: .value("Služby", point.value),
                    series: .value("Řada", "actual")
                )
                .foregroundStyle(
                    LinearGradient(colors: [svCoral.opacity(0.26), svCoral.opacity(0.02)], startPoint: .top, endPoint: .bottom)
                )
                .interpolationMethod(.monotone)
                LineMark(
                    x: .value("Den", point.day),
                    y: .value("Služby", point.value),
                    series: .value("Řada", "actual")
                )
                .foregroundStyle(svCoral)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            }
            RuleMark(y: .value("Cíl", curve.goal))
                .foregroundStyle(svAccent.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .annotation(position: .top, alignment: .leading, spacing: 2) {
                    Text("Cíl \(Int(curve.goal))")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            if curve.todayDay > 0 {
                RuleMark(x: .value("Den", curve.todayDay))
                    .foregroundStyle(Color.primary.opacity(0.18))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(x: .value("Den", curve.todayDay), y: .value("Služby", idealToday))
                    .foregroundStyle(svAccent)
                    .symbolSize(46)
                PointMark(x: .value("Den", curve.todayDay), y: .value("Služby", curve.done))
                    .foregroundStyle(svCoral)
                    .symbolSize(70)
                    .annotation(position: .top, spacing: 4) {
                        Text("\(Int(curve.done))")
                            .font(.caption2.weight(.heavy).monospacedDigit())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(svCoral.opacity(0.18), in: Capsule())
                    }
            }
        }
        .chartYScale(domain: 0...top)
        .chartXScale(domain: 0...curve.days)
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                AxisValueLabel {
                    if let day = value.as(Int.self) {
                        Text("\(day).")
                            .font(.caption2.weight(.semibold))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text("\(Int(number))")
                            .font(.caption2.monospacedDigit())
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot.padding(.top, 14)
        }
    }

    @ViewBuilder
    private var servicesCard: some View {
        if let slices = viewModel.payload?.servicesBreakdown, !slices.isEmpty {
            let total = viewModel.payload?.servicesMeta?.total ?? slices.reduce(0) { $0 + $1.count }
            let active = slices.filter { $0.count > 0 }.count
            svCard("Rozpad na služby", onTap: { mixRoute = ManagerServicesMixRoute(key: nil) }) {
                Button {
                    bump()
                    mixRoute = ManagerServicesMixRoute(key: nil)
                } label: {
                HStack(alignment: .bottom, spacing: 12) {
                    Text("\(total)")
                        .font(.system(size: 46, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .tracking(-1.5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("služeb \(periodPhrase)")
                            .font(.footnote.weight(.medium))
                        Text("\(active)/\(slices.count) kategorií aktivních")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 4)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                stackedServicesBar(slices)

                VStack(spacing: 12) {
                    ForEach(slices) { slice in
                        Button {
                            bump()
                            mixRoute = ManagerServicesMixRoute(key: slice.key)
                        } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color(hex: slice.color))
                                .frame(width: 9, height: 9)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(slice.label)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.primary.opacity(0.07))
                                        Capsule()
                                            .fill(Color(hex: slice.color))
                                            .frame(width: geo.size.width * CGFloat(max(0, min(100, slice.pct))) / 100)
                                    }
                                }
                                .frame(height: 4)
                            }
                            Text("\(slice.count)")
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .frame(minWidth: 24, alignment: .trailing)
                            Text(slice.delta)
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(slice.deltaUp == true ? svGood : (slice.deltaUp == false ? svBad : Color.secondary))
                                .frame(minWidth: 34, alignment: .trailing)
                            Text("\(slice.pct)%")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 38, alignment: .trailing)
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .opacity(slice.count > 0 ? 1 : 0.5)
                        .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Aktivita po dnech – heatmapa jako na webu.
    @ViewBuilder
    private var heatmapCard: some View {
        if let heat = viewModel.heatmap, !heat.weeks.isEmpty {
            svCard("Aktivita po dnech") {
                Text("\(heat.total) služeb · \(heat.weeks.count) týdnů")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, -8)
                if heat.total == 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Zatím žádné služby")
                            .font(.subheadline.weight(.semibold))
                        Text("Jakmile tým začne dělat služby, uvidíš tady, ve kterých dnech.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ManagerActivityHeatmapGrid(heatmap: heat, tint: svCoral) { cell in
                        heatmapDay = ManagerHeatmapDayRoute(date: cell.date)
                    }
                    HStack(alignment: .center, spacing: 8) {
                        if !heat.bestWeekday.isEmpty {
                            (Text("Nejsilnější den: ") + Text(heat.bestWeekday).bold()
                                + Text(" · ⌀ \(String(format: "%.1f", heat.bestWeekdayAvg).replacingOccurrences(of: ".", with: ","))"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 4)
                        ManagerHeatmapLegend(tint: svCoral)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var feeCard: some View {
        if let summary = viewModel.payload?.summary {
            let kpis = viewModel.payload?.kpis ?? []
            let revenue = kpis.first(where: { $0.key == "revenue" })?.value ?? "—"
            let completed = kpis.first(where: { $0.key == "completed" })?.value ?? "—"
            let tone = summary.commissionDeltaUp == true ? "up" : (summary.commissionDeltaUp == false ? "down" : "flat")
            svCard("Provize", onTap: { selectedTab = .performance }) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(summary.totalCommission)
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .tracking(-1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    svChip(summary.commissionDelta, tone: tone)
                }
                Text("vyděláno \(periodPhrase) · \(viewModel.periodLabel)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Divider().opacity(0.5)
                svFacts([
                    ("Hodnota objednávek", revenue),
                    ("Dokončené", completed),
                    ("Nejlepší", summary.bestName)
                ])
            }
        }
    }

    private func progressLegend(_ title: String, _ color: Color, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            Capsule()
                .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [4, 3] : []))
                .frame(width: 16, height: 3)
                .background(Capsule().fill(dashed ? .clear : color))
            Text(title)
                .lineLimit(1)
        }
    }

    private func progressChart(_ progress: ManagerOverviewProgress) -> some View {
        let points = progress.points
        let daily = idealDailyPace
        let ideal: [ManagerPlanCurve.Point] = daily.map { pace in
            points.map { ManagerPlanCurve.Point(day: $0.index, value: pace * Double($0.index + 1)) }
        } ?? []
        let peak = points.map { max($0.current ?? 0, $0.previous ?? 0) }.max() ?? 0
        let top = max(1, max(Double(peak), ideal.last?.value ?? 0) * 1.05)
        let axisIndexes = progressAxisIndexes(count: points.count, today: progress.todayIndex)
        return Chart {
            ForEach(ideal) { point in
                LineMark(
                    x: .value("Den", point.day),
                    y: .value("Služby", point.value),
                    series: .value("Řada", "ideal")
                )
                .foregroundStyle(svAccent)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 5]))
            }
            ForEach(points) { point in
                if let value = point.previous {
                    LineMark(
                        x: .value("Den", point.index),
                        y: .value("Služby", Double(value)),
                        series: .value("Řada", "previous")
                    )
                    .foregroundStyle(Color.secondary.opacity(0.9))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .interpolationMethod(.catmullRom)
                }
            }
            ForEach(points) { point in
                if let value = point.current {
                    AreaMark(
                        x: .value("Den", point.index),
                        y: .value("Služby", Double(value)),
                        series: .value("Řada", "current")
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [svCoral.opacity(0.22), svCoral.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                    LineMark(
                        x: .value("Den", point.index),
                        y: .value("Služby", Double(value)),
                        series: .value("Řada", "current")
                    )
                    .foregroundStyle(svCoral)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("Den", point.index),
                        y: .value("Služby", Double(value))
                    )
                    .foregroundStyle(svCoral)
                    .symbolSize(42)
                }
            }
            if let today = progress.todayIndex, points.indices.contains(today) {
                RuleMark(x: .value("Den", today))
                    .foregroundStyle(svCoral.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYScale(domain: 0...Double(top))
        .chartXScale(domain: 0...Double(max(0, points.count - 1)))
        .chartXAxis {
            AxisMarks(values: axisIndexes) { value in
                AxisValueLabel {
                    if let index = value.as(Int.self), points.indices.contains(index) {
                        Text(points[index].label)
                            .font(.caption2.weight(.semibold))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text("\(Int(number))")
                            .font(.caption2.monospacedDigit())
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot.padding(.top, 6)
        }
    }

    private func progressAxisIndexes(count: Int, today: Int?) -> [Int] {
        guard count > 0 else { return [] }
        if count <= 8 {
            return Array(0..<count)
        }
        let step = max(1, Int((Double(count) / 6).rounded(.up)))
        var indexes = Set(stride(from: 0, to: count, by: step))
        indexes.insert(0)
        indexes.insert(count - 1)
        if let today, today >= 0, today < count {
            indexes.insert(today)
        }
        return indexes.sorted()
    }

    private var progressSignature: String {
        guard let progress = viewModel.payload?.progress else { return "" }
        let current = progress.current.map { $0.map(String.init) ?? "n" }.joined(separator: ",")
        let previous = progress.previous.map { $0.map(String.init) ?? "n" }.joined(separator: ",")
        return progress.labels.joined(separator: ",") + "|" + current + "|" + previous
    }

    /// Po načtení nových dat: nový klíč = nový Chart, vykreslený zleva doprava.
    private func redrawProgressIfNeeded() {
        let key = "\(viewModel.period.rawValue)|" + progressSignature
        if key != drawnProgressKey || chartReveal < 1 {
            drawnProgressKey = key
            resetThenAnimate(
                reset: { chartReveal = 0 },
                animation: .easeOut(duration: 0.95),
                to: { chartReveal = 1 }
            )
        }
    }

    /// Při přepnutí období starý graf rychle schovat, dokud nedorazí nová data.
    private func hideProgressChart() {
        withAnimation(.easeOut(duration: 0.18)) {
            chartReveal = 0
        }
    }

    private func progressTone(_ tone: String) -> Color {
        switch tone {
        case "up": return .green
        case "down": return .red
        default: return .secondary
        }
    }

    @ViewBuilder
    private var alertsBlock: some View {
        if let alerts = viewModel.payload?.alerts, !alerts.isEmpty {
            VStack(spacing: 10) {
                ForEach(alerts) { alert in
                    Button {
                        bump()
                        handleAlert(alert)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: alertIcon(alert.tone))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(alertTint(alert.tone))
                                .frame(width: 38, height: 38)
                                .background(alertTint(alert.tone).opacity(0.14), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(alert.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if !alert.text.isEmpty {
                                    Text(alert.text)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .background(surface(tint: alertTint(alert.tone), radius: 18))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func stackedServicesBar(_ slices: [ManagerOverviewServiceSlice]) -> some View {
        let parts = slices.filter { $0.count > 0 }
        let total = parts.reduce(0) { $0 + $1.count }
        return GeometryReader { proxy in
            let gaps = CGFloat(max(0, parts.count - 1)) * 3
            let usable = max(0, proxy.size.width - gaps)
            HStack(spacing: 3) {
                if total <= 0 {
                    Capsule().fill(Color.primary.opacity(0.08))
                } else {
                    ForEach(parts) { slice in
                        Capsule()
                            .fill(Color(hex: slice.color))
                            .frame(width: usable * CGFloat(slice.count) / CGFloat(total))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 12)
        .clipShape(Capsule())
        .background(Color.primary.opacity(0.06), in: Capsule())
    }

    private var glassFill: Color {
        isDark ? Color(red: 0.078, green: 0.09, blue: 0.09).opacity(0.46) : Color.white.opacity(0.50)
    }

    private var glassRim: Color {
        isDark ? Color.white.opacity(0.15) : Color.white.opacity(0.72)
    }

    private func surface(tint: Color = .clear, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(glassFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.07), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(glassRim)
            }
            .shadow(color: .black.opacity(isDark ? 0.35 : 0.10), radius: 18, y: 10)
    }

    private func bump() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func handleAlert(_ alert: ManagerOverviewAlert) {
        switch alert.action {
        case "localities", "locations":
            selectedTab = .localities
        case "problems":
            selectedTab = .problems
        default:
            break
        }
    }

    private func alertIcon(_ tone: String) -> String {
        switch tone {
        case "info", "tasks": return "checklist"
        default: return "exclamationmark.triangle.fill"
        }
    }

    private func alertTint(_ tone: String) -> Color {
        switch tone {
        case "info", "tasks": return .blue
        default: return .orange
        }
    }

}

private extension Color {
    init(hex: String) {
        var raw = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if raw.count == 3 {
            raw = raw.map { "\($0)\($0)" }.joined()
        }
        var value: UInt64 = 0
        Scanner(string: raw).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

/// Křivka plánu služeb: osa X = den v měsíci (0 = začátek), osa Y = kumulativní počet služeb.
struct ManagerPlanCurve {
    struct Point: Identifiable {
        var id: Int { day }
        let day: Int
        let value: Double
    }

    let days: Int
    let todayDay: Int
    let goal: Double
    let done: Double
    let actual: [Point]
    let ideal: [Point]
    let forecast: [Point]
}

/// Jemný nájezd karty při prvním zobrazení (fade + posun zdola).
private struct HomeCardAppear: ViewModifier {
    let order: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 18)
            .onAppear {
                guard !shown else { return }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.85).delay(Double(min(order, 6)) * 0.06)) {
                    shown = true
                }
            }
    }
}

private extension View {
    func homeCardAppear(_ order: Int) -> some View {
        modifier(HomeCardAppear(order: order))
    }
}
