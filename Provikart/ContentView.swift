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

    var body: some View {
        Group {
            if networkMonitor.isOffline {
                OfflineView()
            } else {
                TabMenuView()
            }
        }
        .onAppear {
            if let username = authState.currentUser?.username {
                appLoginApprovalState.startPolling(username: username, token: authState.authToken, interval: 8)
            }
        }
        .onDisappear {
            appLoginApprovalState.stopPolling()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthState())
        .environmentObject(AppLoginApprovalState())
        .environmentObject(NetworkMonitor())
}
