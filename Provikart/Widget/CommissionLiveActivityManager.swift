//
//  CommissionLiveActivityManager.swift
//  Provikart
//
//  Spouští, aktualizuje a ukončuje Live Activity „Provize – postup k cíli“.
//

import ActivityKit
import Foundation

enum CommissionLiveActivityManager {
    private static let defaultGoal: Double = 100_000
    private static let liveActivityEnabledKey = "settings.liveActivity.enabled"
    /// Po této době systém považuje obsah za zastaralý (isStale); při příštím update se posune.
    private static let staleInterval: TimeInterval = 15 * 60 // 15 minut

    /// Zda má uživatel v Nastavení povolenou Live Activity (výchozí true).
    static var isLiveActivityEnabled: Bool {
        UserDefaults.standard.object(forKey: liveActivityEnabledKey) as? Bool ?? true
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
        let effectiveGoal = goal ?? defaultGoal
        let state = CommissionLiveActivityAttributes.ContentState(
            commission: commission,
            goal: effectiveGoal,
            monthLabel: monthLabel,
            currency: currency,
            isHidden: isHidden
        )
        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(staleInterval),
            relevanceScore: 50
        )
        if let current = Activity<CommissionLiveActivityAttributes>.activities.first {
            Task { await current.update(content) }
        } else {
            let attributes = CommissionLiveActivityAttributes()
            do {
                _ = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
            } catch {
                print("[LiveActivity] Nepodařilo se spustit: \(error.localizedDescription)")
            }
        }
    }

    /// Ukončí všechny běžící Live Activity provize (např. po odhlášení nebo vypnutí v Nastavení).
    static func endAll() {
        for activity in Activity<CommissionLiveActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
