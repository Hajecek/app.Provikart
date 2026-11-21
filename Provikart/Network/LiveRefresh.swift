//
//  LiveRefresh.swift
//  Provikart
//
//  „Realtime“ obnova obrazovek přes polling:
//  – běží jen když je scéna aktivní (v pozadí / pod ovládacím centrem se pauzuje),
//  – po návratu do popředí hned obnoví data a pokračuje v intervalu,
//  – ticky se nikdy nepřekrývají (další čeká na dokončení předchozího),
//  – při zmizení view (přepnutí tabu, zavření) se smyčka zruší.
//

import SwiftUI

extension View {
    /// Periodicky volá `action` (každých `seconds` s), dokud je view na obrazovce a app aktivní.
    ///
    /// První volání proběhne až po intervalu – úvodní načtení si řeší obrazovka sama (`.task`).
    /// Po návratu z pozadí se volá okamžitě. Změna `id` smyčku restartuje.
    func liveRefresh<ID: Equatable>(
        every seconds: Double,
        id: ID,
        _ action: @escaping @MainActor () async -> Void
    ) -> some View {
        modifier(LiveRefreshModifier(interval: seconds, id: id, action: action))
    }

    func liveRefresh(every seconds: Double, _ action: @escaping @MainActor () async -> Void) -> some View {
        liveRefresh(every: seconds, id: 0, action)
    }
}

private struct LiveRefreshModifier<ID: Equatable>: ViewModifier {
    let interval: Double
    let id: ID
    let action: @MainActor () async -> Void

    @Environment(\.scenePhase) private var scenePhase
    /// Smyčka už jednou běžela → další start znamená návrat do popředí = obnovit hned.
    @State private var hasRunBefore = false

    private struct Key: Equatable {
        let id: ID
        let isActive: Bool
    }

    func body(content: Content) -> some View {
        content.task(id: Key(id: id, isActive: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            if hasRunBefore {
                await action()
            }
            hasRunBefore = true
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await action()
            }
        }
        .onDisappear {
            // Při návratu na obrazovku úvodní načtení řeší její vlastní `.task`.
            hasRunBefore = false
        }
    }
}

/// Polling pro view-modely (badge, seznamy), které žijí mimo jedno konkrétní view.
/// Ticky se nepřekrývají; `stop()` zruší i právě běžící request.
@MainActor
final class LivePoller {
    private var task: Task<Void, Never>?
    private let name: String

    nonisolated init(name: String) {
        self.name = name
    }

    var isRunning: Bool { task != nil }

    /// Spustí polling. `immediately` = první tick hned (jinak až po intervalu).
    func start(every seconds: Double, immediately: Bool = true, _ tick: @escaping @MainActor () async -> Void) {
        task?.cancel()
        Log.realtime.debug("▶︎ \(self.name, privacy: .public) – polling každých \(seconds, format: .fixed(precision: 0), privacy: .public) s")
        task = Task { @MainActor [name] in
            if immediately { await tick() }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { break }
                await tick()
            }
            Log.realtime.debug("■ \(name, privacy: .public) – polling ukončen")
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
