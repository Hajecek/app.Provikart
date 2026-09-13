//
//  ManagerHomeView.swift
//  Provikart
//
//  Manažerský Home – nativní přehled týmu (jako webový dashboard).
//

import SwiftUI

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
    @EnvironmentObject private var reportIssueSheet: ManagerReportIssueSheetState
    @Binding var selectedTab: ManagerTabs
    @StateObject private var viewModel = ManagerHomeViewModel()
    @State private var selectedPersonID: ManagerHomePersonRoute?
    @State private var showTeamList = false
    @State private var showDealWars = false

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
                    dashboardScroll
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

    private var dashboardScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerBlock
                periodPicker
                alertsBlock
                kpiGrid
                commissionHero
                activitiesBlock
                quickActions
                riskBlock
                servicesBlock
                teamBlock
                dealWarsBlock
                localitiesBlock
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 28)
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

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greetingText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(firstName)
                .font(.largeTitle.bold())
                .foregroundStyle(.primary)
            if let data = viewModel.payload {
                Text("Tým · \(data.memberCount) \(memberWord(data.memberCount)) · \(viewModel.periodLabel)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var periodPicker: some View {
        Picker("Období", selection: $viewModel.period) {
            ForEach(ManagerOverviewPeriod.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Období přehledu")
    }

    @ViewBuilder
    private var alertsBlock: some View {
        if let alerts = viewModel.payload?.alerts, !alerts.isEmpty {
            VStack(spacing: 10) {
                ForEach(alerts) { alert in
                    Button {
                        handleAlert(alert)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: alertIcon(alert.tone))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(alertTint(alert.tone))
                                .frame(width: 28, height: 28)
                                .background(alertTint(alert.tone).opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(alert.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                if !alert.text.isEmpty {
                                    Text(alert.text)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            Spacer(minLength: 8)
                            Text(alert.actionLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tint)
                        }
                        .padding(14)
                        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var kpiGrid: some View {
        let kpis = viewModel.payload?.kpis ?? []
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(kpis.prefix(3)) { kpi in
                Button {
                    selectedTab = .performance
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: kpiIcon(kpi.key))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(kpiTint(kpi.tone))
                                .frame(width: 28, height: 28)
                                .background(kpiTint(kpi.tone).opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Spacer()
                            deltaChip(kpi.delta, up: kpi.up)
                        }
                        Text(kpi.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        Text(kpi.value)
                            .font(.headline.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
                    .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var commissionHero: some View {
        if let summary = viewModel.payload?.summary {
            Button {
                selectedTab = .performance
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Provize týmu")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(summary.totalCommission)
                                .font(.title.bold())
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                        deltaChip(summary.commissionDelta, up: summary.commissionDeltaUp)
                    }

                    if summary.hasGoal {
                        let pct = min(1, max(0, Double(summary.planPct ?? 0) / 100))
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: pct)
                                .tint(.orange)
                            HStack {
                                Text("\(summary.planPct ?? 0) % z cíle")
                                Spacer()
                                Text(summary.teamGoalLabel)
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 16) {
                        labeledStat("Měsíc zatím", summary.monthEarnedLabel)
                        labeledStat("Predikce", summary.monthPrediction)
                        labeledStat("Nejlepší", summary.bestName)
                    }
                }
                .padding(16)
                .background(cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rychlé akce")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                actionTile("Problémy", "exclamationmark.bubble.fill", .orange) { selectedTab = .problems }
                actionTile("Docházka", "person.badge.clock.fill", .blue) { selectedTab = .attendance }
                actionTile("Výkon", "chart.bar.fill", .green) { selectedTab = .performance }
                actionTile("Lokality", "building.2.fill", .teal) { selectedTab = .localities }
                actionTile("Tým", "person.3.fill", .purple) {
                    showTeamList = true
                }
                actionTile("Nahlásit", "plus.circle.fill", .pink) {
                    reportIssueSheet.isPresented = true
                }
            }
        }
    }

    @ViewBuilder
    private var activitiesBlock: some View {
        if let activities = viewModel.payload?.activities, !activities.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Aktivita")
                        .font(.headline)
                    Spacer()
                    Button("Výkon") { selectedTab = .performance }
                        .font(.subheadline.weight(.semibold))
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(activities.prefix(6)) { item in
                        Button {
                            selectedTab = .performance
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.label)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)
                                Text(item.value)
                                    .font(.headline.bold().monospacedDigit())
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                deltaChip(item.delta, up: item.up)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                            .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var riskBlock: some View {
        if let people = viewModel.payload?.riskPeople, !people.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Vyžaduje pozornost")
                    .font(.headline)
                VStack(spacing: 0) {
                    ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                        Button {
                            selectedPersonID = ManagerHomePersonRoute(id: person.id)
                        } label: {
                            HStack(spacing: 12) {
                                avatarView(url: person.avatarURL, initials: person.initials)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(person.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(person.reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if !person.detail.isEmpty {
                                        Text(person.detail)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer()
                                if !person.metric.isEmpty {
                                    Text(person.metric)
                                        .font(.caption.weight(.bold).monospacedDigit())
                                        .foregroundStyle(person.level == "risk" ? Color.red : Color.orange)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        if index < people.count - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
            }
            .padding(16)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    @ViewBuilder
    private var servicesBlock: some View {
        if let slices = viewModel.payload?.servicesBreakdown, !slices.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Mix služeb")
                        .font(.headline)
                    Spacer()
                    if let meta = viewModel.payload?.servicesMeta {
                        Text("\(meta.total)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                VStack(spacing: 8) {
                    ForEach(slices.prefix(5)) { slice in
                        Button {
                            selectedTab = .performance
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color(hex: slice.color))
                                    .frame(width: 8, height: 8)
                                Text(slice.label)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(slice.count)")
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.primary)
                                Text("\(slice.pct) %")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    @ViewBuilder
    private var teamBlock: some View {
        if let people = viewModel.payload?.salespeople, !people.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Tým")
                        .font(.headline)
                    Spacer()
                    Button("Všichni") { showTeamList = true }
                        .font(.subheadline.weight(.semibold))
                }
                VStack(spacing: 0) {
                    ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                        Button {
                            selectedPersonID = ManagerHomePersonRoute(id: person.id)
                        } label: {
                            HStack(spacing: 12) {
                                avatarView(url: person.avatarURL, initials: person.initials)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(person.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("\(person.services) služeb · plán \(person.planLabel)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(person.commission)
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.primary)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        if index < people.count - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
            }
            .padding(16)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    @ViewBuilder
    private var dealWarsBlock: some View {
        if let leaders = viewModel.payload?.leaderboard, !leaders.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    showDealWars = true
                } label: {
                    HStack {
                        Text("Deal Wars")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("Žebříček")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
                ForEach(leaders) { leader in
                    Button {
                        selectedPersonID = ManagerHomePersonRoute(id: leader.id)
                    } label: {
                        HStack(spacing: 12) {
                            Text("\(leader.place)")
                                .font(.headline.bold().monospacedDigit())
                                .foregroundStyle(placeColor(leader.place))
                                .frame(width: 22)
                            avatarView(url: leader.avatarURL, initials: leader.initials, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(leader.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if leader.xp > 0 {
                                    Text("\(leader.xp) XP")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(leader.amount)
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    @ViewBuilder
    private var localitiesBlock: some View {
        if let loc = viewModel.payload?.localities, loc.available {
            Button {
                selectedTab = .localities
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Lokality")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    HStack(spacing: 10) {
                        locStat("Celkem", loc.total, .primary)
                        locStat("Přiřazené", loc.assigned, .blue)
                        locStat("Volné", loc.unassigned, loc.unassigned > 0 ? .orange : .green)
                        locStat("Hotovo", loc.done, .green)
                    }
                }
                .padding(16)
                .background(cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var cardBackground: Color {
        Color(uiColor: .secondarySystemGroupedBackground)
    }

    private func actionTile(_ title: String, _ icon: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func labeledStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func locStat(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.headline.bold().monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func deltaChip(_ text: String, up: Bool?) -> some View {
        let color: Color = {
            if up == true { return .green }
            if up == false { return .red }
            return .secondary
        }()
        let icon = up == true ? "arrow.up" : (up == false ? "arrow.down" : "minus")
        return HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }

    private func avatarView(url: URL?, initials: String, size: CGFloat = 40) -> some View {
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
