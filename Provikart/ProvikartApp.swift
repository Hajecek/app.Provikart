//
//  ProvikartApp.swift
//  Provikart
//
//  Created by Michal Hájek on 03.07.2025.
//

import SwiftUI

@main
struct ProvikartApp: App {
    @StateObject private var authState = AuthState()
    @State private var showLaunchScreen = true
    @State private var showBiometricVerification = false
    @State private var backgroundedAt: Date?
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showLaunchScreen {
                    LaunchView(onFinish: { showLaunchScreen = false })
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
                if showBiometricVerification {
                    BiometricVerificationView(onSuccess: { showBiometricVerification = false })
                        .ignoresSafeArea()
                        .zIndex(3)
                }
            }
            .environmentObject(authState)
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .background:
                    backgroundedAt = Date()
                case .active:
                    if let at = backgroundedAt, Date().timeIntervalSince(at) >= 5 {
                        if authState.isLoggedIn {
                            showBiometricVerification = true
                        }
                    }
                    backgroundedAt = nil
                default:
                    break
                }
            }
        }
    }
}
