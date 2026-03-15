//
//  CommissionLiveActivityAttributes.swift
//  ProvikartWidget
//
//  Stejná definice jako v Provikart – nutná pro ActivityConfiguration v extension.
//

import ActivityKit
import Foundation

/// Živá aktivita zobrazující aktuální provizi a postup k měsíčnímu cíli.
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
    }

    // Žádná neměnná data – vše je ve ContentState
}
