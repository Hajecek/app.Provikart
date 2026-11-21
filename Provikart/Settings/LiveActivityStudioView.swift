//
//  LiveActivityStudioView.swift
//  Provikart
//
//  Výběr Live Activity pro všechny role (obchodník, manažer, národní manažer).
//  Nahoře je živý náhled Dynamic Islandu – kreslí ho stejné pohledy jako
//  widget extension (Widget/Shared), takže náhled = skutečný vzhled.
//  Náhled se sám přepíná compact → rozbalený → minimal a při rozbalení
//  „dojede“ prstence, sloupky i čísla, jako při skutečné aktualizaci dat.
//

import ActivityKit
import SwiftUI

struct LiveActivityStudioView: View {
    enum Role {
        case user, manager, national
    }

    enum StageMode: String, CaseIterable, Identifiable {
        case compact, expanded, minimal, lockScreen
        var id: String { rawValue }
        var title: String {
            switch self {
            case .compact: return "Kompaktní"
            case .expanded: return "Rozbalený"
            case .minimal: return "Minimální"
            case .lockScreen: return "Zámek"
            }
        }
    }

    struct Option: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
        let symbol: String
        let tint: Color
    }

    let role: Role
    var showsCloseButton = false

    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("settings.liveActivity.enabled") private var liveActivityEnabled = true
    @AppStorage(CommissionLiveActivityManager.kindKey) private var userKindRaw = UserLiveActivityKind.commission.rawValue
    @AppStorage(ManagerTeamLiveActivityManager.kindKey) private var managerKindRaw = ManagerLiveActivityKind.todayServices.rawValue
    @AppStorage(NationalLiveActivityManager.kindKey) private var nationalKindRaw = NationalLiveActivityKind.overview.rawValue

    @State private var stageMode: StageMode = .compact
    @State private var isAutoPlaying = true
    @State private var isRevealed = true
    @State private var isRunning = false
    @State private var isSystemEnabled = true
    @State private var isBusy = false
    @State private var usesSampleData = false
    @State private var startError: String?
    @State private var refreshToken = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                stage
                modePicker
                statusCard
                optionsSection
                actionButton
                hint
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Live Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít") { dismiss() }
                }
            }
        }
        .alert("Nepodařilo se spustit", isPresented: Binding(
            get: { startError != nil },
            set: { if !$0 { startError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(startError ?? "")
        }
        .task { await bootstrap() }
        .task(id: selectedOptionID) { await autoplay() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshStatus() }
        }
        .onChange(of: liveActivityEnabled) { _, enabled in
            if !enabled {
                endAll()
                refreshStatus()
            }
        }
        .sensoryFeedback(.selection, trigger: selectedOptionID)
    }

    // MARK: - Náhled (iPhone)

    private var stage: some View {
        let tint = selectedOption.tint
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.16), Color(white: 0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    RadialGradient(
                        colors: [tint.opacity(0.45), .clear],
                        center: .bottomLeading,
                        startRadius: 10,
                        endRadius: 320
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
                    .animation(.smooth(duration: 0.8), value: selectedOptionID)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 44, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }

            homeGrid
                .padding(.top, 70)
                .opacity(stageMode == .lockScreen ? 0 : 1)
                .blur(radius: stageMode == .expanded ? 6 : 0)

            statusBar
                .padding(.horizontal, 26)
                .padding(.top, 20)
                .opacity(stageMode == .expanded ? 0 : 1)

            if stageMode == .lockScreen {
                lockScreenScene
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                island
                    .padding(.top, 11)
                    .padding(.horizontal, 10)
                    .transition(.opacity)
            }
        }
        .frame(height: stageMode == .lockScreen ? 400 : 300)
        .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
        .environment(\.colorScheme, .dark)
        .contentShape(Rectangle())
        .onTapGesture {
            isAutoPlaying = false
            withAnimation(.islandMorph) {
                stageMode = stageMode == .expanded ? .compact : .expanded
            }
            replayReveal()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Náhled Dynamic Islandu")
        .accessibilityHint("Klepnutím přepnete mezi kompaktním a rozbaleným zobrazením")
    }

    /// Jemná mřížka „ikon“, ať náhled působí jako domovská obrazovka.
    private var homeGrid: some View {
        let columns = Array(repeating: GridItem(.fixed(46), spacing: 22), count: 4)
        return LazyVGrid(columns: columns, spacing: 20) {
            ForEach(0..<12, id: \.self) { index in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(index % 5 == 0 ? 0.13 : 0.07))
                    .frame(width: 46, height: 46)
            }
        }
        .allowsHitTesting(false)
    }

    private var statusBar: some View {
        HStack {
            Text("9:41")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
            }
            .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var island: some View {
        switch stageMode {
        case .compact:
            HStack(spacing: 0) {
                selectedCompactLeading
                    .frame(minWidth: 26, alignment: .leading)
                Spacer(minLength: 0)
                cameraDot
                Spacer(minLength: 0)
                selectedCompactTrailing
                    .frame(minWidth: 26, alignment: .trailing)
            }
            .padding(.horizontal, 11)
            .frame(width: 196, height: 37)
            .background(Capsule(style: .continuous).fill(.black))
            .transition(.islandContent)
        case .minimal:
            HStack(spacing: 8) {
                Capsule(style: .continuous)
                    .fill(.black)
                    .frame(width: 126, height: 37)
                    .overlay { cameraDot }
                minimal
                    .frame(width: 37, height: 37)
                    .background(Circle().fill(.black))
            }
            .transition(.islandContent)
        case .expanded:
            VStack(spacing: 8) {
                HStack(alignment: .center) {
                    expandedLeading
                    Spacer(minLength: 8)
                    expandedTrailing
                }
                .frame(minHeight: 44)
                .overlay(alignment: .top) { cameraDot.padding(.top, 2) }
                expandedBottom
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 44, style: .continuous)
                    .fill(.black)
                    .shadow(color: selectedOption.tint.opacity(0.25), radius: 18, y: 6)
            )
            .transition(.islandContent)
        case .lockScreen:
            EmptyView()
        }
    }

    private var cameraDot: some View {
        Circle()
            .fill(Color(white: 0.08))
            .overlay(Circle().strokeBorder(Color(white: 0.18), lineWidth: 1.5))
            .frame(width: 11, height: 11)
    }

    private var lockScreenScene: some View {
        VStack(spacing: 2) {
            Text("pátek 21. listopadu")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.top, 48)
            Text("9:41")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
            Spacer(minLength: 0)
            // Stejný okraj a stejná maximální výška (~160 pt) jako na skutečném Lock Screenu –
            // co se nevejde, systém ořízne, takže to náhled ukáže taky.
            lockCard
                .islandLockCardPadding()
                .frame(maxHeight: 160, alignment: .top)
                .clipped()
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(IslandPalette.lockBackground.opacity(0.92))
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Přepínač prezentací

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Zobrazení", selection: Binding(
                get: { stageMode },
                set: { mode in
                    isAutoPlaying = false
                    withAnimation(.islandMorph) { stageMode = mode }
                    replayReveal()
                }
            )) {
                ForEach(StageMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 6) {
                Button {
                    isAutoPlaying.toggle()
                } label: {
                    Label(isAutoPlaying ? "Přehrává se" : "Přehrát ukázku",
                          systemImage: isAutoPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedOption.tint)
                .contentTransition(.symbolEffect(.replace))

                Spacer()

                if usesSampleData {
                    Text("Ukázková data")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Stav

    private var statusCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isRunning ? Color.green.opacity(0.18) : Color.secondary.opacity(0.12))
                    .frame(width: 34, height: 34)
                Circle()
                    .fill(isRunning ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 10, height: 10)
                    .shadow(color: isRunning ? .green.opacity(0.8) : .clear, radius: 5)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isRunning ? "Běží na Lock Screenu" : "Zatím neběží")
                    .font(.subheadline.weight(.semibold))
                Text(isRunning ? selectedOption.title : statusSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Toggle("Live Activity zapnutá", isOn: $liveActivityEnabled)
                .labelsHidden()
                .tint(selectedOption.tint)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var statusSubtitle: String {
        switch role {
        case .manager:
            return "Vyberte variantu a spusťte ji tlačítkem."
        case .user:
            return "Spustí se sama po načtení provize, nebo tlačítkem níže."
        case .national:
            return "Spustí se sama po načtení Přehledu, nebo tlačítkem níže."
        }
    }

    // MARK: - Varianty

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Co chcete sledovat")
                .font(.headline)
            ForEach(options) { option in
                Button {
                    select(option)
                } label: {
                    optionCard(option)
                }
                .buttonStyle(StudioCardButtonStyle())
            }
        }
    }

    private func optionCard(_ option: Option) -> some View {
        let selected = option.id == selectedOptionID
        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [option.tint, option.tint.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: option.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(IslandPalette.ink)
                    .symbolEffect(.bounce, value: selected)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 6) {
                Text(option.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(option.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                compactChip(for: option.id)
            }

            Spacer(minLength: 4)

            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(selected ? option.tint : Color.secondary.opacity(0.35))
                .contentTransition(.symbolEffect(.replace))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(selected ? option.tint : Color.clear, lineWidth: 2)
        )
        .animation(.spring(duration: 0.35, bounce: 0.3), value: selected)
    }

    /// Mini náhled kompaktního Islandu přímo v kartě varianty.
    private func compactChip(for id: String) -> some View {
        HStack(spacing: 0) {
            compactLeading(for: id)
            Spacer(minLength: 18)
            compactTrailing(for: id)
        }
        .padding(.horizontal, 10)
        .frame(width: 128, height: 28)
        .background(Capsule(style: .continuous).fill(.black))
        .environment(\.colorScheme, .dark)
        .scaleEffect(0.92, anchor: .leading)
        .allowsHitTesting(false)
    }

    // MARK: - Akce

    private var actionButton: some View {
        Button {
            Task { await handlePrimaryAction() }
        } label: {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: isRunning ? "stop.fill" : "platter.filled.top.and.bottom.iphone")
                    Text(primaryTitle).fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(isRunning ? .red : selectedOption.tint)
        .foregroundStyle(isRunning ? Color.white : IslandPalette.ink)
        .disabled(isBusy || (!isSystemEnabled && !isRunning))
    }

    private var primaryTitle: String {
        if !isSystemEnabled { return "Nejdřív zapněte Live Activities" }
        return isRunning ? "Ukončit Live Activity" : "Zobrazit na Lock Screenu"
    }

    @ViewBuilder
    private var hint: some View {
        if !isSystemEnabled {
            VStack(alignment: .leading, spacing: 10) {
                Text("Live Activities jsou v iOS vypnuté. Bez nich se Lock Screen ani Dynamic Island nezobrazí.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Otevřít Nastavení iPhonu") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            Text("Dynamic Island ukazuje data ve chvíli, kdy aplikaci nemáte otevřenou. Čísla se obnoví vždy, když se do Provikartu vrátíte. Klepnutím na náhled ho rozbalíte.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func select(_ option: Option) {
        guard option.id != selectedOptionID else { return }
        withAnimation(.spring(duration: 0.4, bounce: 0.25)) {
            switch role {
            case .user: userKindRaw = option.id
            case .manager: managerKindRaw = option.id
            case .national: nationalKindRaw = option.id
            }
        }
        if isRunning {
            _ = startSelected()
        }
        refreshStatus()
    }

    private func handlePrimaryAction() async {
        if isRunning {
            endAll()
            try? await Task.sleep(for: .milliseconds(300))
            refreshStatus()
            return
        }
        isBusy = true
        defer { isBusy = false }
        liveActivityEnabled = true
        if role == .manager, let token = authState.authToken, !token.isEmpty {
            await ManagerWidgetRefresh.refreshAll(token: token)
        }
        startError = startSelected()
        try? await Task.sleep(for: .milliseconds(300))
        refreshStatus()
    }

    private func startSelected() -> String? {
        switch role {
        case .user: return CommissionLiveActivityManager.start(kind: userKind)
        case .manager: return ManagerTeamLiveActivityManager.start(kind: managerKind)
        case .national: return NationalLiveActivityManager.start(kind: nationalKind)
        }
    }

    private func endAll() {
        switch role {
        case .user: CommissionLiveActivityManager.endAll()
        case .manager: ManagerTeamLiveActivityManager.endAll()
        case .national: NationalLiveActivityManager.endAll()
        }
    }

    private func bootstrap() async {
        refreshStatus()
        if role == .manager, let token = authState.authToken, !token.isEmpty {
            await ManagerWidgetRefresh.refreshAll(token: token)
            refreshStatus()
        }
    }

    private func refreshStatus() {
        isSystemEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        switch role {
        case .user:
            isRunning = CommissionLiveActivityManager.isRunning
            usesSampleData = WidgetDataStore.loadCommissionSnapshot() == nil
        case .manager:
            isRunning = ManagerTeamLiveActivityManager.isRunning
            let state = ManagerTeamLiveActivityManager.currentState()
            usesSampleData = state.teamSize == 0 && state.todayServices == 0 && state.monthServices == 0
        case .national:
            isRunning = NationalLiveActivityManager.isRunning
            usesSampleData = NationalLiveActivityManager.currentState() == nil
        }
        refreshToken += 1
    }

    /// Ukázka: compact → rozbalený (s „dojetím“ hodnot) → minimal → znovu.
    private func autoplay() async {
        replayReveal()
        let sequence: [(StageMode, Double)] = [(.compact, 2.0), (.expanded, 4.2), (.minimal, 1.8)]
        while !Task.isCancelled {
            for (mode, seconds) in sequence {
                guard isAutoPlaying else {
                    try? await Task.sleep(for: .milliseconds(400))
                    break
                }
                withAnimation(.islandMorph) { stageMode = mode }
                if mode == .expanded { replayReveal() }
                try? await Task.sleep(for: .seconds(seconds))
                if Task.isCancelled { return }
            }
        }
    }

    /// Nejdřív nulové hodnoty, pak skutečné – rozjedou se prstence, sloupky a číslice.
    private func replayReveal() {
        isRevealed = false
        Task {
            try? await Task.sleep(for: .milliseconds(220))
            isRevealed = true
        }
    }

    // MARK: - Data podle role

    private var userKind: UserLiveActivityKind { UserLiveActivityKind(rawValue: userKindRaw) ?? .commission }
    private var managerKind: ManagerLiveActivityKind { ManagerLiveActivityKind(rawValue: managerKindRaw) ?? .todayServices }
    private var nationalKind: NationalLiveActivityKind { NationalLiveActivityKind(rawValue: nationalKindRaw) ?? .overview }

    private var selectedOptionID: String {
        switch role {
        case .user: return userKind.rawValue
        case .manager: return managerKind.rawValue
        case .national: return nationalKind.rawValue
        }
    }

    private var options: [Option] {
        switch role {
        case .user:
            return UserLiveActivityKind.allCases.map {
                Option(id: $0.rawValue, title: $0.title, subtitle: $0.subtitle, symbol: $0.symbolName, tint: $0.islandTint)
            }
        case .manager:
            return ManagerLiveActivityKind.allCases.map {
                Option(id: $0.rawValue, title: $0.title, subtitle: $0.subtitle, symbol: $0.symbolName, tint: $0.islandTint)
            }
        case .national:
            return NationalLiveActivityKind.allCases.map {
                Option(id: $0.rawValue, title: $0.title, subtitle: $0.subtitle, symbol: $0.symbolName, tint: $0.islandTint)
            }
        }
    }

    private var selectedOption: Option {
        options.first { $0.id == selectedOptionID } ?? options[0]
    }

    private func userState(_ id: String, revealed: Bool = true) -> UserIslandState {
        let kind = UserLiveActivityKind(rawValue: id) ?? .commission
        let base: UserIslandState = usesSampleData ? .sample(kind: kind) : CommissionLiveActivityManager.currentState(kind: kind)
        return revealed ? base : base.zeroed()
    }

    private func managerState(_ id: String, revealed: Bool = true) -> ManagerIslandState {
        let kind = ManagerLiveActivityKind(rawValue: id) ?? .todayServices
        let base: ManagerIslandState = usesSampleData ? .sample(kind: kind) : ManagerTeamLiveActivityManager.currentState(kind: kind)
        return revealed ? base : base.zeroed()
    }

    private func nationalState(_ id: String, revealed: Bool = true) -> NationalIslandState {
        let kind = NationalLiveActivityKind(rawValue: id) ?? .overview
        let base: NationalIslandState = NationalLiveActivityManager.currentState(kind: kind) ?? .sample(kind: kind)
        return revealed ? base : base.zeroed()
    }

    // MARK: - Části Islandu pro vybranou variantu

    private var selectedCompactLeading: some View { compactLeading(for: selectedOptionID, revealed: isRevealed) }
    private var selectedCompactTrailing: some View { compactTrailing(for: selectedOptionID, revealed: isRevealed) }

    @ViewBuilder
    private func compactLeading(for id: String, revealed: Bool = true) -> some View {
        switch role {
        case .user: UserIslandCompactLeading(state: userState(id, revealed: revealed))
        case .manager: ManagerIslandCompactLeading(state: managerState(id, revealed: revealed))
        case .national: NationalIslandCompactLeading(state: nationalState(id, revealed: revealed))
        }
    }

    @ViewBuilder
    private func compactTrailing(for id: String, revealed: Bool = true) -> some View {
        switch role {
        case .user: UserIslandCompactTrailing(state: userState(id, revealed: revealed))
        case .manager: ManagerIslandCompactTrailing(state: managerState(id, revealed: revealed))
        case .national: NationalIslandCompactTrailing(state: nationalState(id, revealed: revealed))
        }
    }

    @ViewBuilder
    private var minimal: some View {
        switch role {
        case .user: UserIslandMinimal(state: userState(selectedOptionID, revealed: isRevealed))
        case .manager: ManagerIslandMinimal(state: managerState(selectedOptionID, revealed: isRevealed))
        case .national: NationalIslandMinimal(state: nationalState(selectedOptionID, revealed: isRevealed))
        }
    }

    @ViewBuilder
    private var expandedLeading: some View {
        switch role {
        case .user: UserIslandExpandedLeading(state: userState(selectedOptionID))
        case .manager: ManagerIslandExpandedLeading(state: managerState(selectedOptionID))
        case .national: NationalIslandExpandedLeading(state: nationalState(selectedOptionID))
        }
    }

    @ViewBuilder
    private var expandedTrailing: some View {
        switch role {
        case .user: UserIslandExpandedTrailing(state: userState(selectedOptionID, revealed: isRevealed))
        case .manager: ManagerIslandExpandedTrailing(state: managerState(selectedOptionID, revealed: isRevealed))
        case .national: NationalIslandExpandedTrailing(state: nationalState(selectedOptionID, revealed: isRevealed))
        }
    }

    @ViewBuilder
    private var expandedBottom: some View {
        switch role {
        case .user: UserIslandExpandedBottom(state: userState(selectedOptionID, revealed: isRevealed))
        case .manager: ManagerIslandExpandedBottom(state: managerState(selectedOptionID, revealed: isRevealed))
        case .national: NationalIslandExpandedBottom(state: nationalState(selectedOptionID, revealed: isRevealed))
        }
    }

    @ViewBuilder
    private var lockCard: some View {
        switch role {
        case .user: UserLockCard(state: userState(selectedOptionID, revealed: isRevealed), isStale: false)
        case .manager: ManagerLockCard(state: managerState(selectedOptionID, revealed: isRevealed), isStale: false)
        case .national: NationalLockCard(state: nationalState(selectedOptionID, revealed: isRevealed), isStale: false)
        }
    }
}

// MARK: - Pomocné

private struct StudioCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

private extension Animation {
    /// Morfování tvaru ostrova – stejně pružné jako systémové rozbalení.
    static let islandMorph = Animation.spring(response: 0.5, dampingFraction: 0.78)
}

private extension AnyTransition {
    static var islandContent: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.86, anchor: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.94, anchor: .top))
        )
    }
}

private extension CommissionLiveActivityAttributes.ContentState {
    func zeroed() -> Self {
        var copy = self
        copy.commission = 0
        copy.servicesCount = 0
        return copy
    }
}

private extension ManagerTeamLiveActivityAttributes.ContentState {
    func zeroed() -> Self {
        var copy = self
        copy.todayServices = 0
        copy.presentToday = 0
        copy.monthServices = 0
        copy.dailyServices = dailyServices.map { _ in 0 }
        return copy
    }
}

private extension NationalLiveActivityAttributes.ContentState {
    func zeroed() -> Self {
        var copy = self
        copy.salesReported = 0
        copy.localitiesDone = 0
        copy.ordersToCheck = 0
        copy.ordersCreated = 0
        copy.ordersOpen = 0
        copy.ordersCompleted = 0
        return copy
    }
}

#Preview("Manažer") {
    NavigationStack {
        LiveActivityStudioView(role: .manager)
            .environmentObject(AuthState())
    }
}
