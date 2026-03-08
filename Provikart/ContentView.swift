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
    private let authService = AuthService()

    var body: some View {
        Group {
            if networkMonitor.isOffline {
                OfflineView()
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
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthState())
        .environmentObject(AppLoginApprovalState())
        .environmentObject(NetworkMonitor())
}
