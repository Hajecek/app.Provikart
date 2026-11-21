//
//  CommissionLiveActivityAttributes.swift
//  Provikart
//
//  Live Activity obchodníka (role „user“). Musí zůstat identický s kopií v ProvikartWidget.
//

import ActivityKit
import Foundation

/// Co obchodník vidí na Lock Screenu a v Dynamic Island.
enum UserLiveActivityKind: String, Codable, Hashable, CaseIterable, Identifiable {
    case commission
    case performance
    case myDay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .commission: return "Provize"
        case .performance: return "Výkon"
        case .myDay: return "Můj den"
        }
    }

    var subtitle: String {
        switch self {
        case .commission: return "Provize za měsíc a postup k cíli"
        case .performance: return "Služby za měsíc proti vašemu cíli"
        case .myDay: return "Dnešní instalace a co čeká na dokončení"
        }
    }

    var symbolName: String {
        switch self {
        case .commission: return "creditcard.fill"
        case .performance: return "bolt.fill"
        case .myDay: return "calendar"
        }
    }
}

/// Živá aktivita obchodníka: provize, výkon nebo dnešní den.
struct CommissionLiveActivityAttributes: ActivityAttributes {
    /// Stav zobrazený v Live Activity (mění se při aktualizaci).
    struct ContentState: Codable, Hashable {
        /// Aktuální provize za měsíc
        var commission: Double
        /// Cíl provize (např. 100 000)
        var goal: Double
        /// Označení měsíce (např. „Březen 2025“)
        var monthLabel: String?
        /// Měna (např. „Kč“)
        var currency: String
        /// Skrýt částku (soukromí)
        var isHidden: Bool
        /// Počet dnešních instalací (volitelné – starší stavy pole nemají).
        var todayInstallations: Int? = nil
        /// Čas nejbližší dnešní instalace, např. „14:00“.
        var nextInstallationTime: String? = nil
        /// Název služby nejbližší dnešní instalace.
        var nextInstallationName: String? = nil
        /// Položky čekající na dokončení po termínu instalace.
        var pendingCompletions: Int? = nil
        /// Zvolená varianta (nil = provize).
        var kind: UserLiveActivityKind? = nil
        /// Služby za měsíc.
        var servicesCount: Int? = nil
        /// Cíl služeb za měsíc.
        var servicesGoal: Int? = nil

        var resolvedKind: UserLiveActivityKind { kind ?? .commission }
    }

    // Žádná neměnná data – vše je ve ContentState
}
