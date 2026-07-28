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
            } else {
                TabMenuView()
            }
        }
        .onAppear {
            enforceValidSessionOrLogout()
            if let username = authState.currentUser?.username {
                appLoginApprovalState.startPolling(username: username, token: authState.authToken, interval: 2)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .provikartAuthSessionInvalidated)) { _ in
            Task { @MainActor in
                authState.invalidateSessionDueToAuthFailure()
            }
        }
        .task(priority: .background) {
            guard authState.isLoggedIn else { return }
            while !Task.isCancelled {
                await validateSessionQuietly()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
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
                Task { await refreshWidgetsAndLiveActivity(token: token) }
            }
        }
        .onChange(of: authState.authToken) { _, token in
            if authState.isLoggedIn, token?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                authState.invalidateSessionDueToAuthFailure()
            }
        }
    }

    private func enforceValidSessionOrLogout() {
        let token = authState.authToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if authState.isLoggedIn, token.isEmpty {
            authState.invalidateSessionDueToAuthFailure()
        }
    }

    /// Periodická kontrola tokenu. Odhlásí jen při 401/Forbidden, ne při výpadku sítě.
    private func validateSessionQuietly() async {
        let token = await MainActor.run { authState.authToken ?? "" }
        if token.isEmpty {
            await MainActor.run { authState.invalidateSessionDueToAuthFailure() }
            return
        }
        do {
            if let user = try await authService.fetchCurrentUser(token: token) {
                await MainActor.run {
                    authState.refreshCurrentUser(user)
                }
            }
            // nil bez throw = AuthService už mohl invalidovat přes AuthSession; případně tiše přeskoč.
        } catch {
            // Síťová chyba – neodhlašovat.
            print("[Profil] Kontrola session: \(error.localizedDescription)")
        }
    }

    /// Při návratu aplikace do popředí aktualizuje widgety a Live Activity podle role.
    private func refreshWidgetsAndLiveActivity(token: String) async {
        if authState.currentRole == .manager {
            await ManagerWidgetRefresh.refreshAll(token: token)
            return
        }

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
