//
//  CommissionLiveActivityManager.swift
//  Provikart
//
//  Spouští, aktualizuje a ukončuje Live Activity obchodníka.
//  Varianta (Provize / Výkon / Můj den) se volí v Nastavení → Live Activity.
//

import ActivityKit
import Foundation

enum CommissionLiveActivityManager {
    private static let defaultGoal: Double = 100_000
    private static let liveActivityEnabledKey = "settings.liveActivity.enabled"
    static let kindKey = "settings.userLiveActivity.kind"
    /// Po této době systém považuje obsah za zastaralý (isStale); při příštím update se posune.
    private static let staleInterval: TimeInterval = 15 * 60 // 15 minut

    /// Zda má uživatel v Nastavení povolenou Live Activity (výchozí true).
    static var isLiveActivityEnabled: Bool {
        UserDefaults.standard.object(forKey: liveActivityEnabledKey) as? Bool ?? true
    }

    static var selectedKind: UserLiveActivityKind {
        get {
            let raw = UserDefaults.standard.string(forKey: kindKey) ?? UserLiveActivityKind.commission.rawValue
            return UserLiveActivityKind(rawValue: raw) ?? .commission
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: kindKey) }
    }

    static var isRunning: Bool {
        !Activity<CommissionLiveActivityAttributes>.activities.isEmpty
    }

    /// Aktuální stav sestavený z dat uložených v App Group.
    static func currentState(kind: UserLiveActivityKind? = nil) -> CommissionLiveActivityAttributes.ContentState {
        let snapshot = WidgetDataStore.loadCommissionSnapshot()
        var state = CommissionLiveActivityAttributes.ContentState(
            commission: snapshot?.commission ?? 0,
            goal: WidgetDataStore.loadCommissionGoal() ?? defaultGoal,
            monthLabel: snapshot?.monthLabel,
            currency: snapshot?.currency ?? "Kč",
            isHidden: WidgetDataStore.isCommissionHidden
        )
        state.kind = kind ?? selectedKind
        applyDailyExtras(to: &state)
        return state
    }

    /// Spustí nebo aktualizuje Live Activity s aktuální provizí a cílem.
    /// Ničím se nevolá, pokud je v Nastavení Live Activity vypnutá.
    static func update(
        commission: Double,
        currency: String = "Kč",
        monthLabel: String?,
        goal: Double?,
        isHidden: Bool
    ) {
        guard isLiveActivityEnabled else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        var state = currentState()
        state.commission = commission
        state.currency = currency
        state.monthLabel = monthLabel
        state.goal = goal ?? WidgetDataStore.loadCommissionGoal() ?? defaultGoal
        state.isHidden = isHidden
        push(state)
    }

    /// Ruční start nebo přepnutí varianty z Nastavení. Vrací chybovou hlášku, nebo nil.
    @discardableResult
    static func start(kind: UserLiveActivityKind) -> String? {
        selectedKind = kind
        UserDefaults.standard.set(true, forKey: liveActivityEnabledKey)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return "Live Activities jsou na iPhonu vypnuté. Zapněte je v Nastavení → Provikart."
        }
        var state = currentState(kind: kind)
        if let running = Activity<CommissionLiveActivityAttributes>.activities.first?.content.state,
           WidgetDataStore.loadCommissionSnapshot() == nil {
            state.commission = running.commission
            state.currency = running.currency
            state.monthLabel = running.monthLabel
        }
        return push(state)
    }

    /// Doplní do běžící aktivity čerstvá data (instalace, k dokončení, služby).
    /// Nic nespouští a nic neposílá, pokud se nic nezměnilo.
    static func refreshRunning() {
        guard isLiveActivityEnabled else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        for activity in Activity<CommissionLiveActivityAttributes>.activities {
            var state = activity.content.state
            applyDailyExtras(to: &state)
            guard state != activity.content.state else { continue }
            let content = makeContent(state)
            Task { await activity.update(content) }
        }
    }

    /// Ukončí všechny běžící Live Activity provize (např. po odhlášení nebo vypnutí v Nastavení).
    static func endAll() {
        for activity in Activity<CommissionLiveActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    @discardableResult
    private static func push(_ state: CommissionLiveActivityAttributes.ContentState) -> String? {
        let content = makeContent(state)
        if let current = Activity<CommissionLiveActivityAttributes>.activities.first {
            Task { await current.update(content) }
            return nil
        }
        do {
            _ = try Activity.request(
                attributes: CommissionLiveActivityAttributes(),
                content: content,
                pushType: nil
            )
            return nil
        } catch {
            Log.widget.error("Live Activity se nepodařilo spustit: \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
    }

    private static func applyDailyExtras(to state: inout CommissionLiveActivityAttributes.ContentState) {
        let today = WidgetDataStore.todayInstallationsSummary()
        state.todayInstallations = today.count
        state.nextInstallationTime = today.nextTime
        state.nextInstallationName = today.nextName
        state.pendingCompletions = WidgetDataStore.pendingCompletionsCount
        state.servicesCount = WidgetDataStore.userServicesCount ?? state.servicesCount
        state.servicesGoal = WidgetDataStore.userServicesGoal ?? state.servicesGoal
    }

    private static func makeContent(
        _ state: CommissionLiveActivityAttributes.ContentState
    ) -> ActivityContent<CommissionLiveActivityAttributes.ContentState> {
        ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(staleInterval),
            relevanceScore: 50
        )
    }
}
