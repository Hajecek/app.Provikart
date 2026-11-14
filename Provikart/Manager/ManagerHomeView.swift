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
    @Published var periodLabel = "Tento týden"
    @Published var period: ManagerOverviewPeriod = .week
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = ManagerOverviewService()
    private var loadGeneration = 0

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
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration else { return }
            isLoading = false
            if payload == nil {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct ManagerHomeView: View {
    @EnvironmentObject private var authState: AuthState
    @Binding var selectedTab: ManagerTabs
    @StateObject private var viewModel = ManagerHomeViewModel()
    @State private var selectedPersonID: ManagerHomePersonRoute?
    @State private var showTeamList = false
    @State private var showDealWars = false
    @State private var showLocations = false
    @State private var chartReveal: CGFloat = 0
    @Namespace private var periodAnimation
    @Environment(\.colorScheme) private var scheme

    private let brandGold = Color(red: 1.00, green: 0.70, blue: 0.20)

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
                Task { await viewModel.load(token: authState.authToken, silent: true) }
            }
            .onChange(of: progressSignature) { _, _ in
                playProgressDraw()
            }
            .navigationDestination(item: $selectedPersonID) { route in
                ManagerTeamProfileDetailView(profileID: route.id, preview: nil)
                    .environmentObject(authState)
            }
            .navigationDestination(isPresented: $showTeamList) {
                ManagerTeamProfilesView()
                    .environmentObject(authState)
            }
            .navigationDestination(isPresented: $showDealWars) {
                DealwarsView()
                    .environmentObject(authState)
            }
        }
    }

    private var homeList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                welcomeHeader
                periodSelector
                alertsBlock
                progressCard
                planCard
                servicesCard
                feeCard
                activityBento
                teamCarousel
                attentionCard
                dealWarsCard
                localitiesCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
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

    private var roleTitle: String {
        switch authState.currentUser?.role?.lowercased() {
        case "admin": return "Administrátor"
        case "manager": return "Manažer"
        case "user": return "Obchodník"
        default: return "Uživatel"
        }
    }

    private var welcomeHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(greetingText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(firstName)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            HStack(spacing: 8) {
                Label(roleTitle, systemImage: "person.crop.circle.badge.checkmark")
                    .foregroundStyle(svInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(svAccent, in: Capsule())

                if let data = viewModel.payload {
                    Label("\(data.memberCount) \(memberWord(data.memberCount)) v týmu", systemImage: "person.2.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption.weight(.semibold))
            .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
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
            svCard("Služby", icon: "ellipsis", onTap: { selectedTab = .performance }) {
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

                if !progress.compact && !progress.labels.isEmpty {
                    HStack(spacing: 14) {
                        progressLegend(progress.currentLabel, svCoral, dashed: false)
                        progressLegend(progress.previousLabel, .secondary, dashed: true)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                    progressChart(progress)
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

    @ViewBuilder
    private var planCard: some View {
        if let summary = viewModel.payload?.summary {
            let pct = summary.hasGoal ? max(0, min(100, summary.planPct ?? 0)) : 0
            let color = planColor(pct)
            svCard("Plán služeb", icon: "ellipsis", onTap: { selectedTab = .performance }) {
                HStack(spacing: 20) {
                    ZStack {
                        Circle().stroke(Color.primary.opacity(0.08), lineWidth: 14)
                        Circle()
                            .trim(from: 0, to: CGFloat(pct) / 100)
                            .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.snappy(duration: 0.5), value: pct)
                        if summary.hasGoal {
                            VStack(spacing: 2) {
                                Text("\(pct)%")
                                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                Text(summary.monthName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Není nastavený cíl")
                                .font(.footnote.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 14)
                        }
                    }
                    .frame(width: 124, height: 124)

                    VStack(alignment: .leading, spacing: 12) {
                        planFact("Hotovo", "\(viewModel.payload?.servicesMeta?.monthTotal ?? 0)")
                        planFact("Cíl", summary.hasGoal ? summary.teamGoalLabel : "—")
                        planFact("Predikce provize", summary.monthPrediction)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func planFact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }

    @ViewBuilder
    private var servicesCard: some View {
        if let slices = viewModel.payload?.servicesBreakdown, !slices.isEmpty {
            let total = viewModel.payload?.servicesMeta?.total ?? slices.reduce(0) { $0 + $1.count }
            let active = slices.filter { $0.count > 0 }.count
            svCard("Rozpad na služby", onTap: { selectedTab = .performance }) {
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
                }

                stackedServicesBar(slices)

                VStack(spacing: 12) {
                    ForEach(slices) { slice in
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
                        }
                        .opacity(slice.count > 0 ? 1 : 0.5)
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
        let peak = points.map { max($0.current ?? 0, $0.previous ?? 0) }.max() ?? 0
        let top = max(1, peak)
        let axisIndexes = progressAxisIndexes(count: points.count, today: progress.todayIndex)
        return Chart {
            ForEach(points) { point in
                if let value = point.previous {
                    LineMark(
                        x: .value("Den", point.index),
                        y: .value("Služby", value),
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
                        y: .value("Služby", value),
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
                        y: .value("Služby", value),
                        series: .value("Řada", "current")
                    )
                    .foregroundStyle(svCoral)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("Den", point.index),
                        y: .value("Služby", value)
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
                    if let number = value.as(Int.self) {
                        Text("\(number)")
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

    private func playProgressDraw() {
        chartReveal = 0
        withAnimation(.easeOut(duration: 1.05)) {
            chartReveal = 1
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

    @ViewBuilder
    private var activityBento: some View {
        if let activities = viewModel.payload?.activities, !activities.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Aktivita", trailing: "Otevřít výkon")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                    ForEach(activities.prefix(6)) { item in
                        Button {
                            bump()
                            selectedTab = .performance
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: activityIcon(item.label))
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(svCoral)
                                    Spacer()
                                    deltaChip(item.delta, up: item.up)
                                }
                                Text(item.value)
                                    .font(.system(.title2, design: .rounded).weight(.bold))
                                    .foregroundStyle(.primary)
                                Text(item.label)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                            .background(surface(radius: 18))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var teamCarousel: some View {
        if let people = viewModel.payload?.salespeople, !people.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    bump()
                    showTeamList = true
                } label: {
                    sectionTitle("Tým", trailing: "Zobrazit všechny")
                }
                .buttonStyle(.plain)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(people) { person in
                            Button {
                                bump()
                                selectedPersonID = ManagerHomePersonRoute(id: person.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    avatarView(url: person.avatarURL, initials: person.initials, size: 46)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(person.name)
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(person.commission)
                                            .font(.headline.weight(.bold).monospacedDigit())
                                            .foregroundStyle(svCoral)
                                        Text("\(person.services) služeb · \(person.planLabel)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(14)
                                .frame(width: 168, alignment: .leading)
                                .background(surface(tint: .purple, radius: 20))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }

    @ViewBuilder
    private var attentionCard: some View {
        if let people = viewModel.payload?.riskPeople, !people.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Vyžaduje pozornost")
                VStack(spacing: 0) {
                    ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                    Button {
                        bump()
                        selectedPersonID = ManagerHomePersonRoute(id: person.id)
                    } label: {
                        HStack(spacing: 12) {
                            avatarView(url: person.avatarURL, initials: person.initials, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(person.name)
                                    .foregroundStyle(.primary)
                                Text(person.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !person.metric.isEmpty {
                                Text(person.metric)
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(person.level == "risk" ? Color.red : Color.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        (person.level == "risk" ? Color.red : Color.orange).opacity(0.1),
                                        in: Capsule()
                                    )
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 11)
                    }
                    .buttonStyle(.plain)
                    if index < people.count - 1 {
                        Divider().padding(.leading, 48)
                    }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(surface(tint: .orange, radius: 22))
            }
        }
    }

    @ViewBuilder
    private var dealWarsCard: some View {
        if let leaders = viewModel.payload?.leaderboard, !leaders.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    bump()
                    showDealWars = true
                } label: {
                    sectionTitle("Deal Wars", trailing: "Celý žebříček")
                }
                .buttonStyle(.plain)

                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(leaders.prefix(3).enumerated()), id: \.element.id) { index, leader in
                        let displayed = leaders.count >= 3 ? [leaders[1], leaders[0], leaders[2]][index] : leader
                        Button {
                            bump()
                            selectedPersonID = ManagerHomePersonRoute(id: displayed.id)
                        } label: {
                            VStack(spacing: 8) {
                                ZStack(alignment: .topTrailing) {
                                    avatarView(
                                        url: displayed.avatarURL,
                                        initials: displayed.initials,
                                        size: displayed.place == 1 ? 58 : 46
                                    )
                                    Text("\(displayed.place)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                        .frame(width: 20, height: 20)
                                        .background(placeColor(displayed.place), in: Circle())
                                        .offset(x: 3, y: -3)
                                }
                                Text(displayed.name)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(displayed.amount)
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, displayed.place == 1 ? 16 : 12)
                            .background(Color.primary.opacity(displayed.place == 1 ? 0.055 : 0.025), in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(surface(tint: brandGold, radius: 22))
            }
        }
    }

    @ViewBuilder
    private var localitiesCard: some View {
        if let loc = viewModel.payload?.localities, loc.available {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Lokality", trailing: "Spravovat")
                Button {
                    bump()
                    selectedTab = .localities
                } label: {
                    HStack(spacing: 8) {
                        localityMetric("Celkem", loc.total, .primary)
                        localityMetric("Přiřazené", loc.assigned, .blue)
                        localityMetric("Volné", loc.unassigned, loc.unassigned > 0 ? .orange : .green)
                        localityMetric("Hotovo", loc.done, .green)
                    }
                    .padding(14)
                    .background(surface(tint: .teal, radius: 22))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sectionTitle(_ title: String, trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 2)
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

    private func localityMetric(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.headline.bold().monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
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

    private func deltaChip(_ text: String, up: Bool?, onDark: Bool = false) -> some View {
        let color: Color = {
            if up == true { return svGood }
            if up == false { return svBad }
            return .secondary
        }()
        return HStack(spacing: 3) {
            Image(systemName: up == true ? "arrow.up" : (up == false ? "arrow.down" : "minus"))
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(onDark ? Color.white : color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background((onDark ? Color.white : color).opacity(0.12), in: Capsule())
    }

    private func avatarView(url: URL?, initials: String, size: CGFloat) -> some View {
        Group {
            if let url {
                AuthenticatedProfileImageView(url: url, token: authState.authToken, size: size)
            } else {
                Text(initials)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Color.orange.gradient, in: Circle())
            }
        }
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

    private func activityIcon(_ label: String) -> String {
        let key = label.lowercased()
        if key.contains("navol") { return "phone.fill" }
        if key.contains("schůz") || key.contains("schuz") { return "person.2.fill" }
        if key.contains("prodej") { return "cart.fill" }
        if key.contains("objedn") { return "doc.text.fill" }
        if key.contains("služ") || key.contains("sluz") { return "wifi" }
        if key.contains("ček") || key.contains("cek") { return "clock.fill" }
        return "chart.bar.fill"
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

    private func placeColor(_ place: Int) -> Color {
        switch place {
        case 1: return .orange
        case 2: return .gray
        case 3: return Color(red: 0.72, green: 0.45, blue: 0.2)
        default: return .secondary
        }
    }

    private func memberWord(_ count: Int) -> String {
        if count == 1 { return "člen" }
        if count >= 2 && count <= 4 { return "členové" }
        return "členů"
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

private struct ManagerHomePersonRoute: Identifiable, Hashable {
    let id: Int
}
