//
//  NationalLiveActivityAttributes.swift
//  ProvikartWidget
//
//  Live Activity národního manažera – denní přehled celé sítě.
//  Musí zůstat identický s kopií v Provikart.
//

import ActivityKit
import Foundation

enum NationalLiveActivityKind: String, Codable, Hashable, CaseIterable, Identifiable {
    case overview
    case reports
    case orders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Přehled sítě"
        case .reports: return "Hlášení obchodníků"
        case .orders: return "Objednávky ke kontrole"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: return "Hlášení, objednávky a lokality najednou"
        case .reports: return "Kolik obchodníků dnes nahlásilo lokalitu"
        case .orders: return "Vytvořené, otevřené a hotové objednávky"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: return "map.fill"
        case .reports: return "mappin.and.ellipse"
        case .orders: return "doc.text.magnifyingglass"
        }
    }
}

struct NationalLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Obchodníci, kteří dnes nahlásili lokalitu.
        var salesReported: Int
        /// Obchodníci, od kterých se dnes hlášení čeká (celkem minus nepřítomní).
        var salesExpected: Int
        /// Objednávky ke kontrole (vytvořené + otevřené).
        var ordersToCheck: Int
        /// Hotové prodejní lokality.
        var localitiesDone: Int
        /// Všechny prodejní lokality.
        var localitiesTotal: Int
        /// Lokality bez přiřazeného manažera.
        var unassignedLocalities: Int
        /// Datum pro zobrazení, např. „21. listopadu“.
        var dayLabel: String?
        /// Zvolená varianta (nil = přehled).
        var kind: NationalLiveActivityKind?
        /// Nepřítomní obchodníci.
        var salesAbsent: Int?
        var ordersCreated: Int?
        var ordersOpen: Int?
        var ordersCompleted: Int?

        var resolvedKind: NationalLiveActivityKind { kind ?? .overview }

        init(
            salesReported: Int = 0,
            salesExpected: Int = 0,
            ordersToCheck: Int = 0,
            localitiesDone: Int = 0,
            localitiesTotal: Int = 0,
            unassignedLocalities: Int = 0,
            dayLabel: String? = nil,
            kind: NationalLiveActivityKind? = nil,
            salesAbsent: Int? = nil,
            ordersCreated: Int? = nil,
            ordersOpen: Int? = nil,
            ordersCompleted: Int? = nil
        ) {
            self.salesReported = salesReported
            self.salesExpected = salesExpected
            self.ordersToCheck = ordersToCheck
            self.localitiesDone = localitiesDone
            self.localitiesTotal = localitiesTotal
            self.unassignedLocalities = unassignedLocalities
            self.dayLabel = dayLabel
            self.kind = kind
            self.salesAbsent = salesAbsent
            self.ordersCreated = ordersCreated
            self.ordersOpen = ordersOpen
            self.ordersCompleted = ordersCompleted
        }
    }
}
