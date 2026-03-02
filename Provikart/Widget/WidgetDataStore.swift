//
//  WidgetDataStore.swift
//  Provikart
//
//  Sdílená data pro widget přes App Group.
//

import Foundation
import WidgetKit

/// Klíče pro UserDefaults v App Group – widget z nich čte.
enum WidgetDataStore {
    static let appGroupIdentifier = "group.com.hajecek.provikartApp"
    private static let widgetKindCommission = "ProvikartWidget"
    private static let widgetKindReports = "ProvikartReportsWidget"

    private static var suite: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    enum Keys {
        static let commission = "widget_commission"
        static let currency = "widget_currency"
        static let monthLabel = "widget_month_label"
        static let lastUpdated = "widget_last_updated"
        static let reportsIncompleteCount = "widget_reports_incomplete_count"
    }

    /// Uloží aktuální provizi pro widget. Volá se z hlavní aplikace po načtení provize.
    static func saveCommission(_ value: Double, currency: String, monthLabel: String?) {
        suite?.set(NSNumber(value: value), forKey: Keys.commission)
        suite?.set(currency, forKey: Keys.currency)
        suite?.set(monthLabel, forKey: Keys.monthLabel)
        suite?.set(Date(), forKey: Keys.lastUpdated)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKindCommission)
    }

    /// Smaže uloženou provizi (např. po odhlášení) a aktualizuje widget.
    static func clearCommission() {
        suite?.removeObject(forKey: Keys.commission)
        suite?.removeObject(forKey: Keys.currency)
        suite?.removeObject(forKey: Keys.monthLabel)
        suite?.removeObject(forKey: Keys.lastUpdated)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKindCommission)
    }

    /// Uloží počet nedokončených reportů pro widget Reporty. Volá se z ProblemsView po načtení.
    static func saveReports(incompleteCount: Int) {
        suite?.set(NSNumber(value: incompleteCount), forKey: Keys.reportsIncompleteCount)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKindReports)
    }

    /// Smaže data reportů (po odhlášení) a aktualizuje widget.
    static func clearReports() {
        suite?.removeObject(forKey: Keys.reportsIncompleteCount)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKindReports)
    }
}
