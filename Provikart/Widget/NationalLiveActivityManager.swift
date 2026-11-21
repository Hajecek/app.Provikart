//
//  NationalLiveActivityManager.swift
//  Provikart
//
//  Spouští, aktualizuje a ukončuje Live Activity národního manažera.
//  Data dodává přehled (NationalDashboardView) po každém načtení; poslední
//  snímek se ukládá, aby šla aktivita spustit i z Nastavení.
//  Varianta (Přehled / Hlášení / Objednávky) se volí v Nastavení → Live Activity.
//

import ActivityKit
import Foundation

@MainActor
enum NationalLiveActivityManager {
    private static let liveActivityEnabledKey = "settings.liveActivity.enabled"
    static let kindKey = "settings.nationalLiveActivity.kind"
    private static let snapshotKey = "settings.nationalLiveActivity.snapshot"
    private static let staleInterval: TimeInterval = 15 * 60

    static var isLiveActivityEnabled: Bool {
        UserDefaults.standard.object(forKey: liveActivityEnabledKey) as? Bool ?? true
    }

    static var selectedKind: NationalLiveActivityKind {
        get {
            let raw = UserDefaults.standard.string(forKey: kindKey) ?? NationalLiveActivityKind.overview.rawValue
            return NationalLiveActivityKind(rawValue: raw) ?? .overview
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: kindKey) }
    }

    static var isRunning: Bool {
        !Activity<NationalLiveActivityAttributes>.activities.isEmpty
    }

    /// Poslední známý stav (nebo nil, dokud se Přehled nenačetl).
    static func currentState(kind: NationalLiveActivityKind? = nil) -> NationalLiveActivityAttributes.ContentState? {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey),
              var state = try? JSONDecoder().decode(NationalLiveActivityAttributes.ContentState.self, from: data) else {
            return nil
        }
        state.kind = kind ?? selectedKind
        return state
    }

    /// Uloží snímek z Přehledu a spustí nebo aktualizuje Live Activity. Nové hodnoty
    /// pošle jen při změně (HIG: „Update a Live Activity only when new content is available“).
    static func update(_ state: NationalLiveActivityAttributes.ContentState) {
        var state = state
        state.dayLabel = state.dayLabel ?? displayDayFormatter.string(from: Date())
        state.kind = selectedKind
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: snapshotKey)
        }

        guard isLiveActivityEnabled else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let current = Activity<NationalLiveActivityAttributes>.activities.first,
           current.content.state == state {
            return
        }
        push(state)
    }

    /// Ruční start nebo přepnutí varianty z Nastavení. Vrací chybovou hlášku, nebo nil.
    @discardableResult
    static func start(kind: NationalLiveActivityKind) -> String? {
        selectedKind = kind
        UserDefaults.standard.set(true, forKey: liveActivityEnabledKey)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return "Live Activities jsou na iPhonu vypnuté. Zapněte je v Nastavení → Provikart."
        }
        guard let state = currentState(kind: kind) else {
            return "Nejdřív otevřete Přehled, ať má Live Activity co zobrazit."
        }
        return push(state)
    }

    static func endAll() {
        for activity in Activity<NationalLiveActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    static func clearSnapshot() {
        UserDefaults.standard.removeObject(forKey: snapshotKey)
    }

    @discardableResult
    private static func push(_ state: NationalLiveActivityAttributes.ContentState) -> String? {
        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(staleInterval),
            relevanceScore: 70
        )
        if let current = Activity<NationalLiveActivityAttributes>.activities.first {
            Task { await current.update(content) }
            return nil
        }
        do {
            _ = try Activity.request(
                attributes: NationalLiveActivityAttributes(),
                content: content,
                pushType: nil
            )
            return nil
        } catch {
            Log.widget.error("Live Activity národního manažera se nepodařilo spustit: \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
    }

    private static let displayDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.dateFormat = "d. MMMM"
        return formatter
    }()
}
