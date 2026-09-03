//
//  ManagerTeamLiveActivityManager.swift
//  Provikart
//
//  Spouští, aktualizuje a ukončuje Live Activity pro manažera.
//  Start je vždy z akce uživatele; tichý refresh jen aktualizuje běžící aktivitu.
//

import ActivityKit
import Foundation

@MainActor
enum ManagerTeamLiveActivityManager {
    private static let liveActivityEnabledKey = "settings.liveActivity.enabled"
    static let kindKey = "settings.managerLiveActivity.kind"
    private static let staleInterval: TimeInterval = 15 * 60

    static var isLiveActivityEnabled: Bool {
        UserDefaults.standard.object(forKey: liveActivityEnabledKey) as? Bool ?? true
    }

    static var selectedKind: ManagerLiveActivityKind {
        get {
            let raw = UserDefaults.standard.string(forKey: kindKey) ?? ManagerLiveActivityKind.todayServices.rawValue
            return ManagerLiveActivityKind(rawValue: raw) ?? .todayServices
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: kindKey)
        }
    }

    static var isRunning: Bool {
        !Activity<ManagerTeamLiveActivityAttributes>.activities.isEmpty
    }

    static var areSystemActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    static func currentState(kind: ManagerLiveActivityKind? = nil) -> ManagerTeamLiveActivityAttributes.ContentState {
        ManagerTeamLiveActivityAttributes.ContentState(
            kind: kind ?? selectedKind,
            todayServices: WidgetDataStore.managerTodayServicesCount,
            openProblems: WidgetDataStore.managerOpenProblemsCount ?? 0,
            teamSize: WidgetDataStore.managerTeamSize ?? 0,
            presentToday: WidgetDataStore.managerPresentTodayCount ?? 0,
            latestProblemLabel: WidgetDataStore.managerLatestProblemLabel,
            dayLabel: displayDayFormatter.string(from: Date())
        )
    }

    /// Uživatelský start nebo přepnutí varianty. Zapne i přepínač v Nastavení.
    @discardableResult
    static func start(kind: ManagerLiveActivityKind) -> String? {
        selectedKind = kind
        UserDefaults.standard.set(true, forKey: liveActivityEnabledKey)

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return "Live Activities jsou na iPhonu vypnuté. Zapněte je v Nastavení → Provikart."
        }

        let content = makeContent(for: currentState(kind: kind))

        if let current = Activity<ManagerTeamLiveActivityAttributes>.activities.first {
            Task { await current.update(content) }
            return nil
        }

        do {
            _ = try Activity.request(
                attributes: ManagerTeamLiveActivityAttributes(),
                content: content,
                pushType: nil
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Tichá aktualizace jen pokud už Live Activity běží.
    static func refreshRunning() {
        guard isLiveActivityEnabled else { return }
        guard isRunning else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let content = makeContent(for: currentState())
        for activity in Activity<ManagerTeamLiveActivityAttributes>.activities {
            Task { await activity.update(content) }
        }
    }

    static func endAll() {
        for activity in Activity<ManagerTeamLiveActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private static func makeContent(
        for state: ManagerTeamLiveActivityAttributes.ContentState
    ) -> ActivityContent<ManagerTeamLiveActivityAttributes.ContentState> {
        ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(staleInterval),
            relevanceScore: state.kind == .todayServices ? 80 : 70
        )
    }

    private static let displayDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.dateFormat = "d. MMMM"
        return formatter
    }()
}
