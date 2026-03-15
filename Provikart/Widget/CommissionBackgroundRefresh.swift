//
//  CommissionBackgroundRefresh.swift
//  Provikart
//
//  Naplánované obnovení provize v pozadí – aktualizuje widget a Live Activity,
//  i když je aplikace v pozadí. iOS spouští úlohu v intervalech určených systémem
//  (typicky cca 15+ minut).
//

import BackgroundTasks
import Foundation

private let commissionRefreshTaskId = "com.hajecek.provikartApp.commissionRefresh"
/// Preferovaný interval pro další refresh (systém může spustit později).
private let preferredRefreshInterval: TimeInterval = 15 * 60 // 15 minut

enum CommissionBackgroundRefresh {
    /// Zaregistruje handler úlohy. Volat při startu aplikace (např. z AppDelegate).
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: commissionRefreshTaskId,
            using: nil
        ) { task in
            handleRefresh(task: task as! BGAppRefreshTask)
        }
    }

    /// Naplánuje další běh úlohy (volat po startu a po dokončení předchozího běhu).
    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: commissionRefreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: preferredRefreshInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[CommissionRefresh] Naplánováno na \(request.earliestBeginDate?.description ?? "?")")
        } catch {
            print("[CommissionRefresh] Nepodařilo naplánovat: \(error.localizedDescription)")
        }
    }

    private static func handleRefresh(task: BGAppRefreshTask) {
        scheduleNext()
        let token = WidgetDataStore.loadAuthToken()
        guard let token, !token.isEmpty else {
            task.setTaskCompleted(success: true)
            return
        }
        Task {
            let success = await refreshCommission(token: token)
            await MainActor.run {
                task.setTaskCompleted(success: success)
            }
        }
    }

    private static func refreshCommission(token: String) async -> Bool {
        let commissionService = CommissionService()
        let userGoalsService = UserGoalsService()
        do {
            let response = try await commissionService.fetchCommission(token: token)
            let (goal, _) = (try? await userGoalsService.fetchGoals(token: token)) ?? (nil, nil)
            await MainActor.run {
                WidgetDataStore.saveCommission(
                    response.commission,
                    currency: response.currency,
                    monthLabel: response.month_label
                )
                if let goal { WidgetDataStore.saveCommissionGoal(goal) }
                CommissionLiveActivityManager.update(
                    commission: response.commission,
                    currency: response.currency,
                    monthLabel: response.month_label,
                    goal: goal,
                    isHidden: WidgetDataStore.isCommissionHidden
                )
            }
            return true
        } catch {
            return false
        }
    }
}
