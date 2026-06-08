//
//  ManagerTeamLiveActivityManager.swift
//  Provikart
//
//  Spouští, aktualizuje a ukončuje Live Activity pro manažera.
//

import ActivityKit
import Foundation

enum ManagerTeamLiveActivityManager {
    private static let liveActivityEnabledKey = "settings.liveActivity.enabled"
    private static let staleInterval: TimeInterval = 15 * 60

    static var isLiveActivityEnabled: Bool {
        UserDefaults.standard.object(forKey: liveActivityEnabledKey) as? Bool ?? true
    }

    static func update(
        openProblems: Int,
        teamSize: Int,
        presentToday: Int,
        latestProblemLabel: String?
    ) {
        guard isLiveActivityEnabled else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = ManagerTeamLiveActivityAttributes.ContentState(
            openProblems: openProblems,
            teamSize: teamSize,
            presentToday: presentToday,
            latestProblemLabel: latestProblemLabel
        )
        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(staleInterval),
            relevanceScore: 60
        )

        if let current = Activity<ManagerTeamLiveActivityAttributes>.activities.first {
            Task { await current.update(content) }
        } else {
            let attributes = ManagerTeamLiveActivityAttributes()
            do {
                _ = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
            } catch {
                print("[ManagerLiveActivity] Nepodařilo se spustit: \(error.localizedDescription)")
            }
        }
    }

    static func endAll() {
        for activity in Activity<ManagerTeamLiveActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
