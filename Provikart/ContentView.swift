//
//  ContentView.swift
//  Provikart
//
//  Created by Michal Hájek on 03.07.2025.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var authState: AuthState
    @EnvironmentObject private var appLoginApprovalState: AppLoginApprovalState
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @Environment(\.scenePhase) private var scenePhase
    private let authService = AuthService()
    private let commissionService = CommissionService()
    private let userGoalsService = UserGoalsService()

    var body: some View {
        Group {
            if networkMonitor.isOffline {
                OfflineView()
            } else if authState.authToken == nil {
                FreeEntryView()
            } else {
                TabMenuView()
            }
        }
        .task(priority: .background) {
            guard authState.isLoggedIn else { return }
            while !Task.isCancelled {
                let token = await MainActor.run { authState.authToken ?? "" }
                if token.isEmpty {
                    print("[Profil] Kontrola (každých 5 s): žádný token, přihlaste se")
                } else {
                    do {
                        if let user = try await authService.fetchCurrentUser(token: token) {
                            await MainActor.run {
                                authState.refreshCurrentUser(user)
                            }
                        } else {
                            print("[Profil] Kontrola (každých 5 s): server nevrátil uživatele (401 nebo prázdná odpověď)")
                        }
                    } catch {
                        print("[Profil] Kontrola (každých 5 s): chyba – \(error.localizedDescription)")
                    }
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        .onAppear {
            if let username = authState.currentUser?.username {
                appLoginApprovalState.startPolling(username: username, token: authState.authToken, interval: 2)
            }
        }
        .onDisappear {
            appLoginApprovalState.stopPolling()
        }
        .sheet(item: Binding(
            get: { appLoginApprovalState.presentedRequest },
            set: { newValue in
                if newValue == nil {
                    appLoginApprovalState.dismissedSheetByUser()
                }
            }
        ), onDismiss: {
            appLoginApprovalState.dismissedSheetByUser()
        }) { request in
            AppLoginApprovalSheetView(approvalState: appLoginApprovalState, request: request)
                .environmentObject(authState)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, authState.isLoggedIn, let token = authState.authToken, !token.isEmpty {
                Task { await refreshCommissionAndLiveActivity(token: token) }
            }
        }
    }

    /// Při návratu aplikace do popředí načte aktuální provizi a aktualizuje widget + Live Activity
    /// (např. po dokončení položky na hodinkách).
    private func refreshCommissionAndLiveActivity(token: String) async {
        do {
            let response = try await commissionService.fetchCommission(token: token)
            let (goal, _) = (try? await userGoalsService.fetchGoals(token: token)) ?? (nil, nil)
            await MainActor.run {
                WidgetDataStore.saveCommission(
                    response.commission,
                    currency: response.currency,
                    monthLabel: response.month_label
                )
                if let goal { WidgetDataStore.saveCommissionGoal(goal) }
                CommissionLiveActivityManager.update(
                    commission: response.commission,
                    currency: response.currency,
                    monthLabel: response.month_label,
                    goal: goal,
                    isHidden: WidgetDataStore.isCommissionHidden
                )
            }
        } catch {
            // Tiché selhání – provize se obnoví při otevření Domů
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthState())
        .environmentObject(AppLoginApprovalState())
        .environmentObject(NetworkMonitor())
}
