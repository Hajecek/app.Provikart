//
//  ProvikartApp.swift
//  Provikart
//
//  Created by Michal Hájek on 03.07.2025.
//

import SwiftUI

private let onboardingCompletedKey = "Provikart.hasCompletedOnboarding"

@main
struct ProvikartApp: App {
    @StateObject private var authState = AuthState()
    @StateObject private var appLoginApprovalState = AppLoginApprovalState()
    @StateObject private var networkMonitor = NetworkMonitor()
    @AppStorage(onboardingCompletedKey) private var hasCompletedOnboarding = false
    @State private var showLaunchScreen = true
    @State private var showBiometricVerification = false
    @State private var hasVerifiedBiometricThisSession = false
    @State private var backgroundedAt: Date?
    @Environment(\.scenePhase) private var scenePhase

    private var shouldShowBiometricOverlay: Bool {
        guard authState.isLoggedIn else { return false }
        if showBiometricVerification { return true }
        if !showLaunchScreen, hasCompletedOnboarding, !hasVerifiedBiometricThisSession { return true }
        return false
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showLaunchScreen {
                    LaunchView(onFinish: { showLaunchScreen = false })
                } else if !hasCompletedOnboarding {
                    OnboardingView(onFinish: { hasCompletedOnboarding = true })
                } else if authState.isLoggedIn {
                    ContentView()
                } else {
                    LoginView()
                }
                // Pouze když je aplikace v pozadí (uživatel odešel / app switcher), ne při .inactive (ovládací centrum, notifikace).
                if scenePhase == .background {
                    PrivacyScreen()
                        .ignoresSafeArea()
                        .zIndex(2)
                }
                if shouldShowBiometricOverlay {
                    BiometricVerificationView(onSuccess: {
                        showBiometricVerification = false
                        hasVerifiedBiometricThisSession = true
                    })
                    .ignoresSafeArea()
                    .zIndex(3)
                }
            }
            .environmentObject(authState)
            .environmentObject(appLoginApprovalState)
            .environmentObject(networkMonitor)
            .sheet(item: Binding(
                get: { appLoginApprovalState.presentedRequest },
                set: { appLoginApprovalState.presentedRequest = $0 }
            )) { request in
                AppLoginApprovalSheetView(approvalState: appLoginApprovalState, request: request)
                    .environmentObject(authState)
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .background:
                    backgroundedAt = Date()
                    appLoginApprovalState.stopPolling()
                case .inactive:
                    if let at = backgroundedAt, Date().timeIntervalSince(at) >= 5, authState.isLoggedIn {
                        showBiometricVerification = true
                    }
                    appLoginApprovalState.stopPolling()
                case .active:
                    backgroundedAt = nil
                    if authState.isLoggedIn, !showLaunchScreen, hasCompletedOnboarding,
                       let username = authState.currentUser?.username {
                        appLoginApprovalState.startPolling(username: username, token: authState.authToken, interval: 8)
                    }
                default:
                    break
                }
            }
            .onAppear {
                if authState.isLoggedIn, !showLaunchScreen, hasCompletedOnboarding,
                   scenePhase == .active, let username = authState.currentUser?.username {
                    appLoginApprovalState.startPolling(username: username, token: authState.authToken, interval: 8)
                }
            }
        }
    }
}
