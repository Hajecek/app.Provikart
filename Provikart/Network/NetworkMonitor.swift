//
//  NetworkMonitor.swift
//  Provikart
//
//  Sleduje dostupnost sítě v reálném čase pomocí NWPathMonitor.
//  Stav se aktualizuje okamžitě při změně (vypnutí Wi‑Fi, režim letadlo, ztráta signálu).
//

import Foundation
import Network
import SwiftUI

@MainActor
final class NetworkMonitor: ObservableObject {
    /// `true` když je zařízení offline (žádné připojení nebo nespolehlivá cesta).
    @Published private(set) var isOffline = false

    private let monitor = NWPathMonitor()

    init() {
        // Handler běží na .main, ale kompilátor nemůže zaručit hlavní actor – přepneme se explicitně.
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isOffline = (path.status != .satisfied)
            }
        }
        monitor.start(queue: .main)
    }

    deinit {
        monitor.cancel()
    }
}
