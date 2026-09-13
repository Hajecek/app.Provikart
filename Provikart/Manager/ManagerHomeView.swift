//
//  ManagerHomeView.swift
//  Provikart
//
//  Manažerský Home – nativní přehled týmu.
//

import SwiftUI
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
    @Namespace private var periodAnimation

    private let brandOrange = Color(red: 0.93, green: 0.43, blue: 0.08)
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
                    ProvikartBrandLogoView(style: .large)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ManagerAddReportToolbarButton()
                    ManagerNotificationsBellButton()
                    ProfileBarButton()
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .refreshable {
                await viewModel.load(token: authState.authToken, silent: true)
            }
            .task {
                await viewModel.load(token: authState.authToken)
            }
            .onChange(of: viewModel.period) { _, _ in
                Task { await viewModel.load(token: authState.authToken, silent: true) }
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
                performanceHero
                activityBento
                servicesCard
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
                    .foregroundStyle(brandOrange)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(brandOrange.opacity(0.11), in: Capsule())

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
                        .foregroundStyle(viewModel.period == item ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if viewModel.period == item {
                                Capsule()
                                    .fill(brandOrange.gradient)
                                    .matchedGeometryEffect(id: "period", in: periodAnimation)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.thinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
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
    private var performanceHero: some View {
        if let summary = viewModel.payload?.summary {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Výsledky", trailing: viewModel.periodLabel)
                Button {
                    bump()
                    selectedTab = .performance
                } label: {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Provize týmu")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.72))
                                Text(summary.totalCommission)
                                    .font(.system(size: 31, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.65)
                                deltaChip(summary.commissionDelta, up: summary.commissionDeltaUp, onDark: true)
                            }
                            Spacer()
                            targetRing(summary)
                        }

                        if summary.hasGoal {
                            let pct = min(1, max(0, Double(summary.planPct ?? 0) / 100))
                            VStack(alignment: .leading, spacing: 6) {
                                ProgressView(value: pct)
                                    .tint(.white)
                                HStack {
                                    Text("\(summary.planPct ?? 0) % z cíle")
                                    Spacer()
                                    Text(summary.teamGoalLabel)
                                }
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.72))
                            }
                        }

                        HStack(spacing: 8) {
                            darkMetric("Měsíc", summary.monthEarnedLabel)
                            darkMetric("Predikce", summary.monthPrediction)
                            darkMetric("Nejlepší", summary.bestName)
                        }
                    }
                    .padding(18)
                    .background(heroBackground)
                }
                .buttonStyle(.plain)

                if let kpis = viewModel.payload?.kpis, !kpis.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(kpis.prefix(3)) { kpi in
                            kpiTile(kpi)
                        }
                    }
                }
            }
        }
    }

    private func targetRing(_ summary: ManagerOverviewSummary) -> some View {
        let value = min(1, max(0, Double(summary.planPct ?? 0) / 100))
        return ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: 7)
            Circle()
                .trim(from: 0, to: value)
                .stroke(.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(summary.hasGoal ? "\(summary.planPct ?? 0)" : "—")
                    .font(.headline.bold().monospacedDigit())
                Text("%")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
        }
        .frame(width: 68, height: 68)
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
                                        .foregroundStyle(brandOrange)
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
    private var servicesCard: some View {
        if let slices = viewModel.payload?.servicesBreakdown, !slices.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Mix služeb", trailing: viewModel.payload?.servicesMeta.map { "\($0.total) celkem" })
                VStack(spacing: 14) {
                    stackedServicesBar(slices)
                    ForEach(slices.prefix(5)) { slice in
                        Button {
                            bump()
                            selectedTab = .performance
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color(hex: slice.color))
                                    .frame(width: 9, height: 9)
                                Text(slice.label)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(slice.count)")
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.primary)
                                Text("\(slice.pct) %")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 42, alignment: .trailing)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                .background(surface(tint: .blue, radius: 22))
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
                                            .foregroundStyle(brandOrange)
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
                .font(.title3.bold())
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

    private func kpiTile(_ kpi: ManagerOverviewKPI) -> some View {
        Button {
            bump()
            selectedTab = .performance
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: kpiIcon(kpi.key))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(kpiTint(kpi.tone))
                    .frame(width: 28, height: 28)
                    .background(kpiTint(kpi.tone).opacity(0.12), in: Circle())
                Text(kpi.value)
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(kpi.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(surface(radius: 18))
        }
        .buttonStyle(.plain)
    }

    private func stackedServicesBar(_ slices: [ManagerOverviewServiceSlice]) -> some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(slices.prefix(5)) { slice in
                    Color(hex: slice.color)
                        .frame(width: max(3, proxy.size.width * CGFloat(slice.pct) / 100))
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 10)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }

    private func darkMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.62))
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
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

    private var heroBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.94, green: 0.47, blue: 0.08),
                        Color(red: 0.65, green: 0.20, blue: 0.07),
                        Color(red: 0.28, green: 0.08, blue: 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(.white.opacity(0.12))
            }
            .shadow(color: brandOrange.opacity(0.22), radius: 16, y: 7)
    }

    private func surface(tint: Color = .clear, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.09), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.055))
            }
            .shadow(color: .black.opacity(0.035), radius: 7, y: 3)
    }

    private func deltaChip(_ text: String, up: Bool?, onDark: Bool = false) -> some View {
        let color: Color = {
            if up == true { return .green }
            if up == false { return .red }
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

    private func kpiIcon(_ key: String) -> String {
        switch key {
        case "commissions": return "creditcard.fill"
        case "revenue": return "banknote.fill"
        case "completed": return "checkmark.circle.fill"
        default: return "chart.bar.fill"
        }
    }

    private func kpiTint(_ tone: String) -> Color {
        switch tone {
        case "green", "emerald": return .green
        case "orange": return .orange
        default: return .blue
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
