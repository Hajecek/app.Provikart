//
//  ManagerLiveActivitySetupView.swift
//  Provikart
//
//  Výběr varianty a ruční start Live Activity pro manažera.
//

import ActivityKit
import SwiftUI

struct ManagerLiveActivitySetupView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("settings.liveActivity.enabled") private var liveActivityEnabled = true
    @AppStorage(ManagerTeamLiveActivityManager.kindKey) private var kindRaw = ManagerLiveActivityKind.todayServices.rawValue

    @State private var isRunning = false
    @State private var isSystemEnabled = true
    @State private var isBusy = false
    @State private var snapshot = ManagerTeamLiveActivityAttributes.ContentState()
    @State private var startError: String?
    @State private var showStartError = false

    var showsCloseButton = false

    private var selectedKind: ManagerLiveActivityKind {
        ManagerLiveActivityKind(rawValue: kindRaw) ?? .todayServices
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                intro
                statusCard
                variants
                actionButton
                systemHint
            }
            .padding(20)
            .padding(.bottom, 12)
        }
        .background { ManagerScreenBackground() }
        .navigationTitle("Lock Screen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít") { dismiss() }
                }
            }
        }
        .alert("Nepodařilo se spustit", isPresented: $showStartError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(startError ?? "Zkuste to znovu.")
        }
        .task {
            await bootstrap()
            for await _ in Activity<ManagerTeamLiveActivityAttributes>.activityUpdates {
                refreshStatus()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshStatus()
            }
        }
        .onChange(of: liveActivityEnabled) { _, enabled in
            if !enabled {
                ManagerTeamLiveActivityManager.endAll()
                refreshStatus()
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Live Activity")
                .font(.title2.bold())
            Text("Vyberte, co chcete vidět na Lock Screenu a v Dynamic Island, a spusťte to přímo odsud.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isRunning ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 10, height: 10)
                .shadow(color: isRunning ? .green.opacity(0.7) : .clear, radius: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(isRunning ? "Běží na Lock Screenu" : "Zatím neběží")
                    .font(.subheadline.weight(.semibold))
                Text(isRunning ? selectedKind.title : "Nic se nezobrazuje, dokud to nespustíte.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $liveActivityEnabled)
                .labelsHidden()
                .tint(.indigo)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var variants: some View {
        VStack(spacing: 12) {
            ForEach(ManagerLiveActivityKind.allCases) { kind in
                Button {
                    select(kind)
                } label: {
                    variantCard(kind)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func variantCard(_ kind: ManagerLiveActivityKind) -> some View {
        let selected = selectedKind == kind
        let accent: Color = kind == .todayServices
            ? Color(red: 0.14, green: 0.72, blue: 0.68)
            : Color(red: 0.45, green: 0.42, blue: 0.95)

        return HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                Image(systemName: kind.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(kind.title)
                    .font(.headline)
                Text(kind.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(previewValue(for: kind))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
            }

            Spacer(minLength: 8)

            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(selected ? accent : Color.secondary.opacity(0.35))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(selected ? accent : Color.clear, lineWidth: 2)
        )
    }

    private var actionButton: some View {
        Button {
            Task { await handlePrimaryAction() }
        } label: {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: primaryIcon)
                    Text(primaryTitle)
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .tint(isRunning ? .red : .indigo)
        .disabled(isBusy || (!isSystemEnabled && !isRunning))
        .padding(.top, 4)
    }

    @ViewBuilder
    private var systemHint: some View {
        if !isSystemEnabled {
            VStack(alignment: .leading, spacing: 10) {
                Text("Live Activities jsou v iOS vypnuté. Bez toho se Lock Screen nespustí.")
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
            Text("Čísla se obnovují, dokud máte aplikaci otevřenou. Po návratu do Provikartu se Lock Screen znovu aktualizuje.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var primaryTitle: String {
        if !isSystemEnabled { return "Nejdřív zapněte Live Activities" }
        return isRunning ? "Ukončit Live Activity" : "Zobrazit na Lock Screenu"
    }

    private var primaryIcon: String {
        if isRunning { return "stop.fill" }
        return "platter.filled.top.and.bottom.iphone"
    }

    private func previewValue(for kind: ManagerLiveActivityKind) -> String {
        switch kind {
        case .todayServices:
            return "\(snapshot.todayServices)"
        case .teamOverview:
            let team = max(snapshot.teamSize, snapshot.presentToday, 1)
            return "\(snapshot.presentToday)/\(team)  ·  \(snapshot.openProblems)"
        }
    }

    private func select(_ kind: ManagerLiveActivityKind) {
        kindRaw = kind.rawValue
        ManagerTeamLiveActivityManager.selectedKind = kind
        if isRunning {
            _ = ManagerTeamLiveActivityManager.start(kind: kind)
            refreshStatus()
        }
    }

    private func handlePrimaryAction() async {
        if isRunning {
            ManagerTeamLiveActivityManager.endAll()
            refreshStatus()
            return
        }
        await startActivity()
    }

    private func startActivity() async {
        isBusy = true
        defer { isBusy = false }

        liveActivityEnabled = true
        if let token = authState.authToken, !token.isEmpty {
            await ManagerWidgetRefresh.refreshAll(token: token)
        }

        if let error = ManagerTeamLiveActivityManager.start(kind: selectedKind) {
            startError = error
            showStartError = true
        }
        refreshStatus()
    }

    private func bootstrap() async {
        refreshStatus()
        if let token = authState.authToken, !token.isEmpty {
            await ManagerWidgetRefresh.refreshAll(token: token)
            refreshStatus()
        }
    }

    private func refreshStatus() {
        isRunning = ManagerTeamLiveActivityManager.isRunning
        isSystemEnabled = ManagerTeamLiveActivityManager.areSystemActivitiesEnabled
        snapshot = ManagerTeamLiveActivityManager.currentState(kind: selectedKind)
    }
}
