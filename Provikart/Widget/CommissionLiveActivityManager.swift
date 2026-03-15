//
//  CommissionLiveActivityManager.swift
//  Provikart
//
//  Spouští, aktualizuje a ukončuje Live Activity „Provize – postup k cíli“.
//  Používá ActivityKit: lokální update + push token pro aktualizace ze serveru (i v pozadí).
//  Viz: https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications
//

import ActivityKit
import Foundation

enum CommissionLiveActivityManager {
    private static let defaultGoal: Double = 100_000
    /// Po této době systém považuje obsah za zastaralý (isStale); při příštím update se posune.
    private static let staleInterval: TimeInterval = 15 * 60 // 15 minut

    /// Spustí nebo aktualizuje Live Activity s aktuální provizí a cílem.
    /// Při prvním startu použije pushType: .token a token pošle na server – server pak může
    /// při změně provize poslat APNs Live Activity update (aktualizace i v pozadí).
    static func update(
        commission: Double,
        currency: String = "Kč",
        monthLabel: String?,
        goal: Double?,
        isHidden: Bool
    ) {
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
                let activity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: .token
                )
                startObservingPushToken(activity)
            } catch {
                print("[LiveActivity] Nepodařilo se spustit: \(error.localizedDescription)")
            }
        }
    }

    /// Sleduje push token a posílá ho na server. Server ho použije k odeslání APNs update při změně provize.
    private static func startObservingPushToken(_ activity: Activity<CommissionLiveActivityAttributes>) {
        Task {
            for await pushToken in activity.pushTokenUpdates {
                let hex = pushToken.reduce("") { $0 + String(format: "%02x", $1) }
                if let apiToken = WidgetDataStore.loadAuthToken() {
                    await LiveActivityPushTokenService.sendPushToken(apiToken: apiToken, pushTokenHex: hex)
                }
            }
        }
    }

    /// Ukončí všechny běžící Live Activity provize (např. po odhlášení).
    static func endAll() {
        for activity in Activity<CommissionLiveActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
