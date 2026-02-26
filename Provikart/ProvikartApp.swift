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

    var body: some Scene {
        WindowGroup {
            if showLaunchScreen {
                LaunchView(onFinish: { showLaunchScreen = false })
            } else {
                ContentView()
            }
        }
    }
}
