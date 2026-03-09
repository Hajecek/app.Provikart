//
//  WidgetDataStore.swift
//  Provikart
//
//  Sdílená data pro widget přes App Group.
//  Při změně dat voláme WidgetCenter.reloadTimelines(ofKind:) – dle dokumentace
//  https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date
//  to nečerpá budget widgetu, když je aplikace v popředí.
//

import Foundation
import WidgetKit

/// Klíče pro UserDefaults v App Group – widget z nich čte.
enum WidgetDataStore {
    static let appGroupIdentifier = "group.com.hajecek.provikartApp"
    private static let widgetKindCommission = "ProvikartWidget"
    private static let widgetKindReports = "ProvikartReportsWidget"
    private static let widgetKindInstallations = "ProvikartInstallationsWidget"

    private static var suite: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    enum Keys {
        static let commission = "widget_commission"
        static let currency = "widget_currency"
        static let monthLabel = "widget_month_label"
        static let lastUpdated = "widget_last_updated"
        static let reportsIncompleteCount = "widget_reports_incomplete_count"
        static let authToken = "widget_auth_token"
        static let installations = "widget_installations"
        static let commissionHidden = "widget_commission_hidden"
    }

    /// Položka pro widget instalací (minimální payload pro App Group).
    private struct InstallationItemPayload: Encodable {
        let installation_date: String
        let installation_time: String?
        let item_name: String
        let order_display: String
    }

    /// Vrátí, zda je provize skrytá.
    static var isCommissionHidden: Bool {
        suite?.bool(forKey: Keys.commissionHidden) ?? false
    }

    /// Přepne viditelnost provize a aktualizuje widget.
    static func setCommissionHidden(_ hidden: Bool) {
        suite?.set(hidden, forKey: Keys.commissionHidden)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKindCommission)
    }

    /// Uloží token do App Group, aby si widget mohl data stáhnout i bez spuštění aplikace.
    static func saveAuthToken(_ token: String?) {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let t = trimmed, !t.isEmpty {
            suite?.set(t, forKey: Keys.authToken)
        } else {
            suite?.removeObject(forKey: Keys.authToken)
        }
    }

    static func clearAuthToken() {
        suite?.removeObject(forKey: Keys.authToken)
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

    /// Uloží položky instalací pro widget (kalendář). Volá se z CalendarView po načtení.
    static func saveInstallations(items: [OrderItemByInstallationDate]) {
        let payload = items.map { item in
            InstallationItemPayload(
                installation_date: item.installation_date,
                installation_time: item.installation_time,
                item_name: item.item_name,
                order_display: item.displayOrderNumber
            )
        }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        suite?.set(data, forKey: Keys.installations)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKindInstallations)
    }

    /// Smaže data instalací (po odhlášení) a aktualizuje widget.
    static func clearInstallations() {
        suite?.removeObject(forKey: Keys.installations)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKindInstallations)
    }
}
