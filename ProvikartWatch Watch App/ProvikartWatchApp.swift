//
//  ProvikartWatchApp.swift
//  ProvikartWatch Watch App
//
//  Vstupní bod Apple Watch aplikace.
//

import SwiftUI

@main
struct ProvikartWatch_Watch_AppApp: App {
    @StateObject private var sessionManager = WatchSessionManager.shared

    init() {
        WatchSessionManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView(sessionManager: sessionManager)
        }
    }
}
