//
//  LuckyBoxQuota.swift
//  Provikart
//
//  Denní Lucky Box + bonus a drop luck za včerejší usazený výkon.
//  Dnešní služby se započítají až zítra — zrušení po otevření bednu nezneužije.
//

import Foundation
import SwiftUI

enum LuckyBoxQuota {
    static let dailyFree = 1
    /// Včerejší služby → bonusové bedny dnes.
    /// 2–3 služby = 1 bonus, 5 = 2 bonusy, 7 = 3 bonusy.
    static let bonusThresholds = [2, 5, 7]
    static var maxChests: Int { dailyFree + bonusThresholds.count }

    static func earnedChests(settledServices: Int) -> Int {
        let bonus = bonusThresholds.filter { settledServices >= $0 }.count
        return min(maxChests, dailyFree + bonus)
    }

    static func nextBonus(services: Int) -> (need: Int, at: Int)? {
        guard let next = bonusThresholds.first(where: { services < $0 }) else { return nil }
        return (next - services, next)
    }

    /// Hint k dnešnímu výkonu — započítá se až zítra, pokud služby zůstanou.
    static func tomorrowHint(servicesToday: Int) -> String? {
        let bonusTomorrow = earnedChests(settledServices: servicesToday) - dailyFree
        if let next = nextBonus(services: servicesToday) {
            if servicesToday <= 0 {
                return "Zítra +1 bedna za \(next.at) \(servicesWord(next.at))"
            }
            if bonusTomorrow == 0 {
                return "Dnes \(servicesToday) · zítra +1 za \(next.need) \(servicesWord(next.need))"
            }
            return "Dnes \(servicesToday) · zítra \(bonusTomorrow) \(bonusWord(bonusTomorrow)), další za \(next.need) \(servicesWord(next.need))"
        }
        guard bonusTomorrow > 0 else { return nil }
        return "Dnes \(servicesToday) služeb · zítra \(bonusTomorrow) \(bonusWord(bonusTomorrow))"
    }

    static func luckMultiplier(settledServices: Int) -> Double {
        switch settledServices {
        case ...3: return 1.0
        case 4: return 1.12
        case 5...6: return 1.22
        default: return 1.35
        }
    }

    static func startingStars(settledServices: Int) -> Int {
        settledServices >= 7 ? 2 : 1
    }

    static func luckPercent(settledServices: Int) -> Int {
        let extra = luckMultiplier(settledServices: settledServices) - 1
        return max(0, Int((extra * 100).rounded()))
    }

    static func servicesWord(_ count: Int) -> String {
        switch count {
        case 1: return "službu"
        case 2...4: return "služby"
        default: return "služeb"
        }
    }

    static func chestsWord(_ count: Int) -> String {
        switch count {
        case 1: return "bedna"
        case 2...4: return "bedny"
        default: return "beden"
        }
    }

    static func bonusWord(_ count: Int) -> String {
        switch count {
        case 1: return "bonusová bedna"
        case 2...4: return "bonusové bedny"
        default: return "bonusových beden"
        }
    }

    static func services(in orders: [UserOrder], on date: Date) -> Int {
        let key = LuckyBoxLocalStore.todayKey(reference: date)
        return orders.reduce(0) { partial, order in
            guard matchesDay(order, dayKey: key) else { return partial }
            if isCancelled(order.statusDisplay) { return partial }
            let count = order.items.filter { item in
                let type = (item.item_type ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if type == "migrace" || type == "migration" { return false }
                return !isCancelled(item.statusDisplay)
            }.count
            return partial + count
        }
    }

    private static func isCancelled(_ raw: String) -> Bool {
        let status = raw.lowercased()
        return status.contains("cancel")
            || status.contains("storno")
            || status.contains("vrácen")
            || status.contains("vracen")
            || status.contains("returned")
    }

    private static func matchesDay(_ order: UserOrder, dayKey: String) -> Bool {
        let parts = dayKey.split(separator: "-")
        let dotted: String? = {
            guard parts.count == 3 else { return nil }
            return "\(parts[2]).\(parts[1]).\(parts[0])"
        }()
        let candidates = [order.order_date, order.created_at].compactMap { $0 }
        for raw in candidates {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix(dayKey) { return true }
            if let dotted, value.hasPrefix(dotted) { return true }
        }
        return false
    }
}

@MainActor
final class LuckyBoxQuotaState: ObservableObject {
    static let shared = LuckyBoxQuotaState()

    /// Včerejší služby, které pořád existují (usazený výkon).
    @Published private(set) var servicesYesterday = 0
    /// Dnešní živý počet — zítra z něj budou bedny a luck, pokud to nezruší.
    @Published private(set) var servicesToday = 0
    @Published private(set) var earned = LuckyBoxQuota.dailyFree
    @Published private(set) var opened = 0
    @Published private(set) var remaining = LuckyBoxQuota.dailyFree
    @Published private(set) var nextHint: String?
    @Published private(set) var luckMultiplier = 1.0
    @Published private(set) var luckPercent = 0
    @Published private(set) var startingStars = 1

    var tomorrowBonusCount: Int {
        max(0, LuckyBoxQuota.earnedChests(settledServices: servicesToday) - LuckyBoxQuota.dailyFree)
    }

    private var lastTotalServices: Int?
    private var lastOrdersFetchDay = ""

    private init() {
        applyLocalOpened()
        servicesYesterday = LuckyBoxLocalStore.cachedYesterdayServices
        servicesToday = LuckyBoxLocalStore.cachedTodayServices
        recompute()
    }

    func applyLocalOpened() {
        opened = LuckyBoxLocalStore.openedCountToday
        recompute()
    }

    func refresh(token: String?, totalServices: Int? = nil, forceOrders: Bool = false) async {
        applyLocalOpened()
        let day = LuckyBoxLocalStore.todayKey()
        let totalChanged = totalServices.map { $0 != lastTotalServices } ?? false
        let needOrders = forceOrders || lastOrdersFetchDay != day || totalChanged

        if needOrders, let token, !token.isEmpty {
            do {
                let orders = try await UserOrdersService().fetchOrders(token: token)
                let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                servicesYesterday = LuckyBoxQuota.services(in: orders, on: yesterday)
                servicesToday = LuckyBoxQuota.services(in: orders, on: Date())
                lastOrdersFetchDay = day
                if let totalServices {
                    lastTotalServices = totalServices
                }
                LuckyBoxLocalStore.savePerformance(yesterday: servicesYesterday, today: servicesToday)
            } catch {
                if lastOrdersFetchDay != day {
                    servicesYesterday = LuckyBoxLocalStore.cachedYesterdayServices
                    servicesToday = LuckyBoxLocalStore.cachedTodayServices
                }
            }
        } else if lastOrdersFetchDay != day {
            servicesYesterday = LuckyBoxLocalStore.cachedYesterdayServices
            servicesToday = LuckyBoxLocalStore.cachedTodayServices
        }

        recompute()
    }

    private func recompute() {
        earned = LuckyBoxQuota.earnedChests(settledServices: servicesYesterday)
        opened = LuckyBoxLocalStore.openedCountToday
        remaining = max(0, earned - opened)
        nextHint = LuckyBoxQuota.tomorrowHint(servicesToday: servicesToday)
        luckMultiplier = LuckyBoxQuota.luckMultiplier(settledServices: servicesYesterday)
        luckPercent = LuckyBoxQuota.luckPercent(settledServices: servicesYesterday)
        startingStars = LuckyBoxQuota.startingStars(settledServices: servicesYesterday)
    }
}
