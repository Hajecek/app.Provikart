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
    /// Kind musí odpovídat řetězci v ProvikartWidget.swift
    private static let widgetKind = "ProvikartWidget"

    private static var suite: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    enum Keys {
        static let commission = "widget_commission"
        static let currency = "widget_currency"
        static let monthLabel = "widget_month_label"
        static let lastUpdated = "widget_last_updated"
    }

    /// Uloží aktuální provizi pro widget. Volá se z hlavní aplikace po načtení provize.
    /// Zároveň naplánuje okamžitou aktualizaci widgetu.
    static func saveCommission(_ value: Double, currency: String, monthLabel: String?) {
        suite?.set(value, forKey: Keys.commission)
        suite?.set(currency, forKey: Keys.currency)
        suite?.set(monthLabel, forKey: Keys.monthLabel)
        suite?.set(Date(), forKey: Keys.lastUpdated)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    /// Smaže uloženou provizi (např. po odhlášení) a aktualizuje widget.
    static func clearCommission() {
        suite?.removeObject(forKey: Keys.commission)
        suite?.removeObject(forKey: Keys.currency)
        suite?.removeObject(forKey: Keys.monthLabel)
        suite?.removeObject(forKey: Keys.lastUpdated)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}
