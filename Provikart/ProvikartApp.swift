//
//  ProvikartApp.swift
//  Provikart
//
//  Created by Michal Hájek on 03.07.2025.
//

import SwiftUI

@main
struct ProvikartApp: App {
    @State private var showLaunchScreen = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showLaunchScreen {
                    LaunchView(onFinish: { showLaunchScreen = false })
                } else {
                    ContentView()
                }
                if scenePhase != .active {
                    PrivacyScreen()
                        .ignoresSafeArea()
                        .zIndex(1)
                }
            }
        }
    }
}
