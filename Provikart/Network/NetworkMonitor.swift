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
    private let queue = DispatchQueue(label: "com.provikart.networkmonitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let offline = (path.status != .satisfied)
            DispatchQueue.main.async {
                self?.isOffline = offline
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
