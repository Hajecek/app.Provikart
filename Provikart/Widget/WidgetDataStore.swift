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
    private static let widgetKindManagerProblems = "ProvikartManagerProblemsWidget"
    private static let widgetKindManagerAttendance = "ProvikartManagerAttendanceWidget"
    private static let widgetKindManagerTeam = "ProvikartManagerTeamWidget"

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
        static let commissionGoal = "widget_commission_goal"
        static let userRole = "widget_user_role"
        static let managerOpenProblems = "widget_manager_open_problems"
        static let managerTeamSize = "widget_manager_team_size"
        static let managerPresentToday = "widget_manager_present_today"
        static let managerAbsentNames = "widget_manager_absent_names"
        static let managerProblemsPreview = "widget_manager_problems_preview"
    }

    /// Náhled otevřeného problému týmu pro widget.
    struct ManagerProblemPreview: Codable, Identifiable {
        let user_name: String?
        let order_number: String?
        let note: String?

        var id: String { "\(user_name ?? "")-\(order_number ?? "")-\(note ?? "")" }

        var displayLine: String {
            var parts: [String] = []
            if let name = user_name, !name.isEmpty { parts.append(name) }
            if let order = order_number, !order.isEmpty { parts.append("obj. \(order)") }
            if parts.isEmpty, let note, !note.isEmpty {
                let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                parts.append(String(trimmed.prefix(40)))
            }
            return parts.isEmpty ? "Otevřený problém" : parts.joined(separator: " · ")
        }
    }

    /// Uloží roli uživatele – widgety podle ní zobrazí jiný obsah.
    static func saveUserRole(_ role: UserRole) {
        suite?.set(role.rawValue, forKey: Keys.userRole)
        reloadManagerWidgetTimelines()
    }

    static var isManager: Bool {
        suite?.string(forKey: Keys.userRole) == UserRole.manager.rawValue
    }

    static var managerOpenProblemsCount: Int? {
        guard let raw = suite?.object(forKey: Keys.managerOpenProblems) else { return nil }
        return (raw as? NSNumber)?.intValue ?? raw as? Int
    }

    static var managerTeamSize: Int? {
        guard let raw = suite?.object(forKey: Keys.managerTeamSize) else { return nil }
        return (raw as? NSNumber)?.intValue ?? raw as? Int
    }

    static var managerPresentTodayCount: Int? {
        guard let raw = suite?.object(forKey: Keys.managerPresentToday) else { return nil }
        return (raw as? NSNumber)?.intValue ?? raw as? Int
    }

    static func clearUserRole() {
        suite?.removeObject(forKey: Keys.userRole)
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

    /// Načte token z App Group (pro background refresh a widget).
    static func loadAuthToken() -> String? {
        let token = suite?.string(forKey: Keys.authToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (token?.isEmpty == false) ? token : nil
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

    /// Načte uložený cíl provize z App Group (např. z předchozího načtení nebo z webu).
    static func loadCommissionGoal() -> Double? {
        guard let raw = suite?.object(forKey: Keys.commissionGoal) else { return nil }
        if let n = raw as? NSNumber { return n.doubleValue }
        return nil
    }

    /// Uloží cíl provize pro widget (z API user_goals). Volá se z HomeView po načtení cílů.
    static func saveCommissionGoal(_ goal: Double?) {
        if let g = goal {
            suite?.set(NSNumber(value: g), forKey: Keys.commissionGoal)
        } else {
            suite?.removeObject(forKey: Keys.commissionGoal)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKindCommission)
    }

    /// Smaže uloženou provizi (např. po odhlášení) a aktualizuje widget.
    static func clearCommission() {
        suite?.removeObject(forKey: Keys.commission)
        suite?.removeObject(forKey: Keys.currency)
        suite?.removeObject(forKey: Keys.monthLabel)
        suite?.removeObject(forKey: Keys.lastUpdated)
        suite?.removeObject(forKey: Keys.commissionGoal)
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

    /// Uloží přehled problémů týmu pro manažerské widgety.
    static func saveManagerProblems(openCount: Int, preview: [ManagerProblemPreview]) {
        suite?.set(NSNumber(value: openCount), forKey: Keys.managerOpenProblems)
        if let data = try? JSONEncoder().encode(preview) {
            suite?.set(data, forKey: Keys.managerProblemsPreview)
        } else {
            suite?.removeObject(forKey: Keys.managerProblemsPreview)
        }
        reloadManagerWidgetTimelines()
    }

    /// Uloží docházku týmu pro dnešní den.
    static func saveManagerAttendance(teamSize: Int, presentToday: Int, absentNames: [String]) {
        suite?.set(NSNumber(value: teamSize), forKey: Keys.managerTeamSize)
        suite?.set(NSNumber(value: presentToday), forKey: Keys.managerPresentToday)
        if let data = try? JSONEncoder().encode(absentNames) {
            suite?.set(data, forKey: Keys.managerAbsentNames)
        } else {
            suite?.removeObject(forKey: Keys.managerAbsentNames)
        }
        reloadManagerWidgetTimelines()
    }

    /// Smaže manažerská data widgetů (po odhlášení).
    static func clearManagerData() {
        suite?.removeObject(forKey: Keys.managerOpenProblems)
        suite?.removeObject(forKey: Keys.managerTeamSize)
        suite?.removeObject(forKey: Keys.managerPresentToday)
        suite?.removeObject(forKey: Keys.managerAbsentNames)
        suite?.removeObject(forKey: Keys.managerProblemsPreview)
        reloadManagerWidgetTimelines()
    }

    private static func reloadManagerWidgetTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKindManagerProblems)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKindManagerAttendance)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKindManagerTeam)
    }
}
