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
                if scenePhase != .active {
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
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .background:
                    backgroundedAt = Date()
                case .inactive:
                    // Při návratu z pozadí (.inactive máme jen když backgroundedAt != nil) zobrazíme
                    // biometrické ověření hned, aby se neukázala domovská obrazovka.
                    if let at = backgroundedAt, Date().timeIntervalSince(at) >= 5, authState.isLoggedIn {
                        showBiometricVerification = true
                    }
                case .active:
                    backgroundedAt = nil
                default:
                    break
                }
            }
        }
    }
}
