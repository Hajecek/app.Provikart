//
//  ProvikartWidget.swift
//  ProvikartWidget
//
//  Widgety Provize a Reporty. Aktualizace dle dokumentace:
//  https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date
//  - Aplikace volá WidgetCenter.reloadTimelines(ofKind:) při změně dat (nečerpá budget).
//  - Provider vrací timeline s policy .after (min. ~5 min, typicky 15–60 min).
//  - Síťové požadavky v getTimeline s timeoutem, vždy jednou completion.
//

import WidgetKit
import SwiftUI

private let appGroupIdentifier = "group.com.hajecek.provikartApp"
/// Interval pro další reload – respektuje budget (~40–70 reloadů/24 h na widget).
private let timelineRefreshInterval: TimeInterval = 30 * 60 // 30 minut
private let networkRequestTimeout: TimeInterval = 10

private enum WidgetKeys {
    static let commission = "widget_commission"
    static let currency = "widget_currency"
    static let monthLabel = "widget_month_label"
    static let lastUpdated = "widget_last_updated"
    static let reportsIncompleteCount = "widget_reports_incomplete_count"
    static let authToken = "widget_auth_token"
    static let installations = "widget_installations"
    static let commissionHidden = "widget_commission_hidden"
}

// MARK: - Data

struct WidgetCommissionEntry: TimelineEntry {
    let date: Date
    let commission: Double?
    let currency: String
    let monthLabel: String?
    let hasData: Bool
    let isHidden: Bool
}

// MARK: - Timeline Provider

struct ProvikartWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetCommissionEntry {
        WidgetCommissionEntry(date: Date(), commission: 12_450, currency: "Kč", monthLabel: "Březen 2025", hasData: true, isHidden: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetCommissionEntry) -> Void) {
        completion(loadCachedEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetCommissionEntry>) -> Void) {
        let cached = loadCachedEntry()
        let nextReload = Date().addingTimeInterval(timelineRefreshInterval)

        guard let token = loadAuthToken() else {
            completion(Timeline(entries: [cached], policy: .after(Date().addingTimeInterval(60 * 60))))
            return
        }

        var didComplete = false
        let completeOnce: (Timeline<WidgetCommissionEntry>) -> Void = { timeline in
            guard !didComplete else { return }
            didComplete = true
            completion(timeline)
        }

        Task {
            let fresh = await fetchCommission(token: token)
            let entry = fresh ?? cached
            completeOnce(Timeline(entries: [entry], policy: .after(nextReload)))
        }

        Task {
            try? await Task.sleep(nanoseconds: UInt64((networkRequestTimeout + 1) * 1_000_000_000))
            completeOnce(Timeline(entries: [cached], policy: .after(nextReload)))
        }
    }

    private func loadAuthToken() -> String? {
        let suite = UserDefaults(suiteName: appGroupIdentifier)
        let token = suite?.string(forKey: WidgetKeys.authToken)
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    private func loadCachedEntry() -> WidgetCommissionEntry {
        let suite = UserDefaults(suiteName: appGroupIdentifier)
        let rawCommission = suite?.object(forKey: WidgetKeys.commission)
        let commission: Double? = (rawCommission as? NSNumber)?.doubleValue ?? rawCommission as? Double
        let currency = suite?.string(forKey: WidgetKeys.currency) ?? "Kč"
        let monthLabel = suite?.string(forKey: WidgetKeys.monthLabel)
        let hasData = suite?.object(forKey: WidgetKeys.commission) != nil
        let isHidden = suite?.bool(forKey: WidgetKeys.commissionHidden) ?? false
        return WidgetCommissionEntry(
            date: Date(),
            commission: commission,
            currency: currency,
            monthLabel: monthLabel,
            hasData: hasData,
            isHidden: isHidden
        )
    }

    private struct CommissionAPIResponse: Decodable {
        let success: Bool
        let month: String?
        let month_label: String?
        let commission: Double
        let currency: String
    }

    @MainActor
    private func saveCommissionToCache(_ resp: CommissionAPIResponse) {
        let suite = UserDefaults(suiteName: appGroupIdentifier)
        suite?.set(NSNumber(value: resp.commission), forKey: WidgetKeys.commission)
        suite?.set(resp.currency, forKey: WidgetKeys.currency)
        suite?.set(resp.month_label, forKey: WidgetKeys.monthLabel)
        suite?.set(Date(), forKey: WidgetKeys.lastUpdated)
    }

    private func fetchCommission(token: String) async -> WidgetCommissionEntry? {
        var comp = URLComponents(string: "https://provikart.cz/api/commission.php")
        comp?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = comp?.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = networkRequestTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(CommissionAPIResponse.self, from: data)
            guard decoded.success else { return nil }

            await MainActor.run { saveCommissionToCache(decoded) }

            let suite = UserDefaults(suiteName: appGroupIdentifier)
            let isHidden = suite?.bool(forKey: WidgetKeys.commissionHidden) ?? false
            return WidgetCommissionEntry(
                date: Date(),
                commission: decoded.commission,
                currency: decoded.currency,
                monthLabel: decoded.month_label,
                hasData: true,
                isHidden: isHidden
            )
        } catch {
            return nil
        }
    }
}

// MARK: - Sdílný vzhled podle systémových widgetů

enum ProvikartActivityPalette {
    static let yellow = Color(red: 251.0 / 255, green: 191.0 / 255, blue: 79.0 / 255)
    static let ink = Color(red: 0.09, green: 0.08, blue: 0.06)
}

extension View {
    func homeWidgetBackground() -> some View {
        containerBackground(Color(uiColor: .systemBackground), for: .widget)
    }
}

struct WidgetAccessoryCircle<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            content()
        }
        .widgetAccentable()
    }
}

// MARK: - Views

struct ProvikartWidgetEntryView: View {
    var entry: WidgetCommissionEntry
    @Environment(\.widgetFamily) var family

    private func formatCommission(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallView
            case .systemMedium:
                mediumView
            case .accessoryCircular:
                accessoryCircularView
            case .accessoryRectangular:
                accessoryRectangularView
            case .accessoryInline:
                accessoryInlineView
            default:
                mediumView
            }
        }
        .homeWidgetBackground()
        .widgetURL(URL(string: "provikart://"))
    }

    private var accessoryCircularView: some View {
        WidgetAccessoryCircle {
            if entry.hasData, let value = entry.commission {
                Text(entry.isHidden ? "•••" : formatCommission(value))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .padding(6)
            } else {
                Image(systemName: "creditcard.fill")
                    .font(.title3.weight(.semibold))
            }
        }
    }

    // Zamykací obrazovka – obdélník
    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Provize", systemImage: "creditcard.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            if entry.hasData, let value = entry.commission {
                Text(entry.isHidden ? "– – – –" : (formatCommission(value) + " " + entry.currency))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.7)
            } else {
                Text("Přihlaste se")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // Zamykací obrazovka – jeden řádek
    private var accessoryInlineView: some View {
        if entry.hasData, let value = entry.commission {
            Text(entry.isHidden ? "Provize – – – –" : "Provize \(formatCommission(value)) \(entry.currency)")
                .font(.system(size: 14, weight: .medium))
        } else {
            Text("Provikart – přihlaste se")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Provize", systemImage: "creditcard.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .widgetAccentable()
            Spacer(minLength: 0)
            if entry.hasData, let value = entry.commission {
                Text(entry.isHidden ? "••••" : formatCommission(value))
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .widgetAccentable()
                Text(entry.isHidden ? "Skryto" : (entry.monthLabel ?? entry.currency))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Přihlaste se")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Provize za měsíc", systemImage: "creditcard.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .widgetAccentable()
            Spacer(minLength: 0)
            if entry.hasData, let value = entry.commission {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(entry.isHidden ? "••••" : formatCommission(value))
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .widgetAccentable()
                    if !entry.isHidden {
                        Text(entry.currency)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                if let label = entry.monthLabel, !label.isEmpty {
                    Text(label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Přihlaste se v aplikaci")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Widget

struct ProvikartWidget: Widget {
    let kind: String = "ProvikartWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProvikartWidgetProvider()) { entry in
            ProvikartWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Provize")
        .description("Aktuální měsíční provize z Provikart.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline
        ])
    }
}

// MARK: - Widget Reporty (nedokončené reporty)

struct WidgetReportsEntry: TimelineEntry {
    let date: Date
    let incompleteCount: Int?
    let hasData: Bool
}

struct ProvikartReportsWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetReportsEntry {
        WidgetReportsEntry(date: Date(), incompleteCount: 3, hasData: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetReportsEntry) -> Void) {
        completion(loadCachedEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetReportsEntry>) -> Void) {
        let cached = loadCachedEntry()
        let nextReload = Date().addingTimeInterval(timelineRefreshInterval)

        guard let token = loadAuthToken() else {
            completion(Timeline(entries: [cached], policy: .after(Date().addingTimeInterval(60 * 60))))
            return
        }

        var didComplete = false
        let completeOnce: (Timeline<WidgetReportsEntry>) -> Void = { timeline in
            guard !didComplete else { return }
            didComplete = true
            completion(timeline)
        }

        Task {
            let fresh = await fetchIncompleteReportsCount(token: token)
            let entry = fresh ?? cached
            completeOnce(Timeline(entries: [entry], policy: .after(nextReload)))
        }

        Task {
            try? await Task.sleep(nanoseconds: UInt64((networkRequestTimeout + 1) * 1_000_000_000))
            completeOnce(Timeline(entries: [cached], policy: .after(nextReload)))
        }
    }

    private func loadAuthToken() -> String? {
        let suite = UserDefaults(suiteName: appGroupIdentifier)
        let token = suite?.string(forKey: WidgetKeys.authToken)
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    private func loadCachedEntry() -> WidgetReportsEntry {
        let suite = UserDefaults(suiteName: appGroupIdentifier)
        let rawCount = suite?.object(forKey: WidgetKeys.reportsIncompleteCount)
        let count: Int? = (rawCount as? NSNumber)?.intValue ?? rawCount as? Int
        let hasData = suite?.object(forKey: WidgetKeys.reportsIncompleteCount) != nil
        return WidgetReportsEntry(
            date: Date(),
            incompleteCount: count,
            hasData: hasData
        )
    }

    private struct ReportsAPIResponse: Decodable {
        let success: Bool
        let reports: [Report]

        struct Report: Decodable {
            let status: String?
        }
    }

    @MainActor
    private func saveReportsToCache(incompleteCount: Int) {
        let suite = UserDefaults(suiteName: appGroupIdentifier)
        suite?.set(NSNumber(value: incompleteCount), forKey: WidgetKeys.reportsIncompleteCount)
        suite?.set(Date(), forKey: WidgetKeys.lastUpdated)
    }

    private func fetchIncompleteReportsCount(token: String) async -> WidgetReportsEntry? {
        var comp = URLComponents(string: "https://provikart.cz/api/user_reports.php")
        comp?.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "_", value: "\(Int(Date().timeIntervalSince1970))")
        ]
        guard let url = comp?.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = networkRequestTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(ReportsAPIResponse.self, from: data)
            guard decoded.success else { return nil }

            let incomplete = decoded.reports.filter { ($0.status ?? "").lowercased() != "completed" }.count
            await MainActor.run { saveReportsToCache(incompleteCount: incomplete) }

            return WidgetReportsEntry(date: Date(), incompleteCount: incomplete, hasData: true)
        } catch {
            return nil
        }
    }
}

struct ProvikartReportsWidgetEntryView: View {
    var entry: WidgetReportsEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                reportsSmallView
            case .systemMedium:
                reportsMediumView
            case .accessoryCircular:
                reportsAccessoryCircularView
            case .accessoryRectangular:
                reportsAccessoryRectangularView
            case .accessoryInline:
                reportsAccessoryInlineView
            default:
                reportsMediumView
            }
        }
        .homeWidgetBackground()
        .widgetURL(URL(string: "provikart://"))
    }

    private var reportsAccessoryCircularView: some View {
        WidgetAccessoryCircle {
            if entry.hasData, let count = entry.incompleteCount {
                Text("\(count)")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .minimumScaleFactor(0.5)
            } else {
                Image(systemName: "exclamationmark.bubble.fill")
                    .font(.title3.weight(.semibold))
            }
        }
    }

    // Zamykací obrazovka – obdélník
    private var reportsAccessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Reporty", systemImage: "exclamationmark.bubble.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            if entry.hasData, let count = entry.incompleteCount {
                Text(count == 1 ? "1 nedokončený report" : "\(count) nedokončených reportů")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            } else {
                Text("Přihlaste se")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // Zamykací obrazovka – jeden řádek
    private var reportsAccessoryInlineView: some View {
        if entry.hasData, let count = entry.incompleteCount {
            Text(count == 1 ? "1 nedokončený report" : "\(count) nedokončených reportů")
                .font(.system(size: 14, weight: .medium))
        } else {
            Text("Provikart – přihlaste se")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var reportsSmallView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Reporty", systemImage: "exclamationmark.bubble.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .widgetAccentable()
            Spacer(minLength: 0)
            if entry.hasData, let count = entry.incompleteCount {
                Text("\(count)")
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .widgetAccentable()
                Text(count == 1 ? "nedokončený" : "nedokončených")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Přihlaste se")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var reportsMediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Nedokončené reporty", systemImage: "exclamationmark.bubble.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .widgetAccentable()
            Spacer(minLength: 0)
            if entry.hasData, let count = entry.incompleteCount {
                Text("\(count)")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .widgetAccentable()
                Text(count == 1 ? "problém k vyřešení" : "problémů k vyřešení")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Přihlaste se v aplikaci")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct ProvikartReportsWidget: Widget {
    let kind: String = "ProvikartReportsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProvikartReportsWidgetProvider()) { entry in
            ProvikartReportsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Reporty")
        .description("Počet nedokončených reportů z Problémů.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline
        ])
    }
}

// MARK: - Widget Instalace (kalendář instalovaných služeb)

struct WidgetInstallationItem: Codable, Identifiable {
    let installation_date: String
    let installation_time: String?
    let item_name: String
    let order_display: String?  // z cache aplikace
    let order_number: String?  // z API
    let order_id: Int?         // z API (může přijít jako Int nebo String)

    enum CodingKeys: String, CodingKey {
        case installation_date, installation_time, item_name, order_display, order_number, order_id
        case installation_day
    }

    init(installation_date: String, installation_time: String?, item_name: String, order_display: String?, order_number: String?, order_id: Int?) {
        self.installation_date = installation_date
        self.installation_time = installation_time
        self.item_name = item_name
        self.order_display = order_display
        self.order_number = order_number
        self.order_id = order_id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fromDate = try? c.decodeIfPresent(String.self, forKey: .installation_date)
        let fromDay = try? c.decodeIfPresent(String.self, forKey: .installation_day)
        installation_date = (fromDate?.trimmingCharacters(in: .whitespaces).isEmpty == false ? fromDate : fromDay) ?? ""
        installation_time = try? c.decodeIfPresent(String.self, forKey: .installation_time)
        item_name = (try? c.decode(String.self, forKey: .item_name)) ?? ""
        order_display = try? c.decodeIfPresent(String.self, forKey: .order_display)
        order_number = try? c.decodeIfPresent(String.self, forKey: .order_number)
        if let i = try? c.decode(Int.self, forKey: .order_id) {
            order_id = i
        } else if let s = try? c.decode(String.self, forKey: .order_id), let i = Int(s) {
            order_id = i
        } else {
            order_id = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(installation_date, forKey: .installation_date)
        try c.encode(installation_time, forKey: .installation_time)
        try c.encode(item_name, forKey: .item_name)
        try c.encodeIfPresent(order_display, forKey: .order_display)
        try c.encodeIfPresent(order_number, forKey: .order_number)
        try c.encodeIfPresent(order_id, forKey: .order_id)
    }

    var displayOrder: String {
        if let d = order_display, !d.isEmpty { return d }
        if let n = order_number, !n.isEmpty { return n }
        return "\(order_id ?? 0)"
    }

    var id: String { "\(installation_date)-\(item_name)-\(displayOrder)" }
}

private func parseInstallationDate(_ raw: String) -> Date? {
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    let ddMMyyyy: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        f.locale = Locale(identifier: "cs_CZ")
        return f
    }()
    let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    return ddMMyyyy.date(from: trimmed) ?? yyyyMMdd.date(from: trimmed)
}

struct WidgetInstallationsEntry: TimelineEntry {
    let date: Date
    let items: [WidgetInstallationItem]
    let hasData: Bool
}

struct ProvikartInstallationsWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetInstallationsEntry {
        WidgetInstallationsEntry(date: Date(), items: [
            WidgetInstallationItem(installation_date: "2025-03-06", installation_time: "09:00", item_name: "Internet 100", order_display: "123", order_number: nil, order_id: nil),
            WidgetInstallationItem(installation_date: "2025-03-06", installation_time: "14:00", item_name: "Postpaid", order_display: "124", order_number: nil, order_id: nil),
        ], hasData: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetInstallationsEntry) -> Void) {
        completion(loadCachedEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetInstallationsEntry>) -> Void) {
        let cached = loadCachedEntry()
        let nextReload = Date().addingTimeInterval(timelineRefreshInterval)

        guard let token = loadAuthToken() else {
            completion(Timeline(entries: [cached], policy: .after(Date().addingTimeInterval(60 * 60))))
            return
        }

        var didComplete = false
        let completeOnce: (Timeline<WidgetInstallationsEntry>) -> Void = { timeline in
            guard !didComplete else { return }
            didComplete = true
            completion(timeline)
        }

        Task {
            let fresh = await fetchInstallations(token: token)
            let entry = fresh ?? cached
            completeOnce(Timeline(entries: [entry], policy: .after(nextReload)))
        }

        Task {
            try? await Task.sleep(nanoseconds: UInt64((networkRequestTimeout + 1) * 1_000_000_000))
            completeOnce(Timeline(entries: [cached], policy: .after(nextReload)))
        }
    }

    private func loadAuthToken() -> String? {
        let suite = UserDefaults(suiteName: appGroupIdentifier)
        let token = suite?.string(forKey: WidgetKeys.authToken)
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    private func loadCachedEntry() -> WidgetInstallationsEntry {
        let suite = UserDefaults(suiteName: appGroupIdentifier)
        guard let data = suite?.data(forKey: WidgetKeys.installations),
              let items = try? JSONDecoder().decode([WidgetInstallationItem].self, from: data) else {
            return WidgetInstallationsEntry(date: Date(), items: [], hasData: false)
        }
        return WidgetInstallationsEntry(date: Date(), items: items, hasData: true)
    }

    private struct InstallationsAPIResponse: Decodable {
        let success: Bool
        let items: [WidgetInstallationItem]?
    }

    private func fetchInstallations(token: String) async -> WidgetInstallationsEntry? {
        var comp = URLComponents(string: "https://provikart.cz/api/order_items_by_installation_date.php")
        comp?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = comp?.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = networkRequestTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(InstallationsAPIResponse.self, from: data)
            guard decoded.success, let items = decoded.items, !items.isEmpty else { return nil }
            return WidgetInstallationsEntry(date: Date(), items: items, hasData: true)
        } catch {
            return nil
        }
    }
}

struct ProvikartInstallationsWidgetEntryView: View {
    var entry: WidgetInstallationsEntry
    @Environment(\.widgetFamily) var family

    private static var czechCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "cs_CZ")
        return c
    }

    private var calendar: Calendar { Self.czechCalendar }
    private var now: Date { Date() }

    /// Všechny dny s instalacemi, seřazené od nejbližšího (dnes + budoucí první, pak minulé).
    private var itemsGroupedByDay: [(dayStart: Date, items: [WidgetInstallationItem])] {
        var byDay: [Date: [WidgetInstallationItem]] = [:]
        let todayStart = calendar.startOfDay(for: now)
        for item in entry.items {
            guard let d = parseInstallationDate(item.installation_date) else { continue }
            let start = calendar.startOfDay(for: d)
            byDay[start, default: []].append(item)
        }
        return byDay.keys.sorted().map { (dayStart: $0, items: byDay[$0]!.sorted { ($0.installation_time ?? "") < ($1.installation_time ?? "") }) }
    }

    /// Pouze dnes a budoucí dny – pro sekci „Nejbližší“.
    private var upcomingGroupedByDay: [(dayStart: Date, items: [WidgetInstallationItem])] {
        let todayStart = calendar.startOfDay(for: now)
        return itemsGroupedByDay.filter { $0.dayStart >= todayStart }
    }

    /// Pro zobrazení v widgetu: nejdřív nadcházející, pokud žádné tak aspoň první dny z celku.
    private var displayGroupedByDay: [(dayStart: Date, items: [WidgetInstallationItem])] {
        let upcoming = upcomingGroupedByDay
        if upcoming.isEmpty {
            return Array(itemsGroupedByDay.suffix(4))
        }
        return Array(upcoming.prefix(4))
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                installationsSmallView
            case .systemMedium:
                installationsMediumView
            case .accessoryRectangular:
                installationsAccessoryRectangularView
            case .accessoryInline:
                installationsAccessoryInlineView
            default:
                installationsMediumView
            }
        }
        .homeWidgetBackground()
        .widgetURL(URL(string: "provikart://calendar"))
    }

    private var installationsAccessoryInlineView: some View {
        let text: String
        if !entry.hasData {
            text = "Instalace – přihlaste se"
        } else if entry.items.isEmpty {
            text = "Dnes se nic neinstaluje"
        } else {
            let count = entry.items.count
            text = count == 1 ? "1 instalace" : "\(count) instalací"
        }
        return Text(text)
    }

    private var installationsAccessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Instalace", systemImage: "calendar")
                .font(.caption.weight(.semibold))
                .widgetAccentable()
            if !entry.hasData {
                Text("Přihlaste se")
                    .font(.caption)
            } else if entry.items.isEmpty {
                Text("Dnes se nic neinstaluje")
                    .font(.caption)
            } else {
                let total = entry.items.count
                Text(total == 1 ? "1 instalace v plánu" : "\(total) instalací v plánu")
                    .font(.headline)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var installationsSmallView: some View {
        let todayItems = itemsForDate(now)
        return VStack(alignment: .leading, spacing: 2) {
            Text(dayOfWeekString(now).capitalized)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.none)
            Text(dayOfMonthWithDot(now))
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .widgetAccentable()
            Spacer(minLength: 0)
            Text(countLabelForToday(count: todayItems.count))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var installationsMediumView: some View {
        let todayItems = itemsForDate(now)
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dayOfWeekString(now).capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(dayOfMonthWithDot(now))
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .widgetAccentable()
                Text(countLabelForToday(count: todayItems.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 8) {
                if !entry.hasData {
                    Text("Přihlaste se")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if todayItems.isEmpty {
                    Text("Dnes se nic neinstaluje")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(todayItems.prefix(4)) { item in
                        Text(installationNameAndTime(item))
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func dayLabelString(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "Dnes" }
        if calendar.isDateInTomorrow(date) { return "Zítra" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.dateFormat = "d. M."
        return f.string(from: date)
    }

    /// Název dne v týdnu (např. „Sobota“).
    private func dayOfWeekString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }

    /// Den v měsíci s tečkou (např. „07.“).
    private func dayOfMonthWithDot(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.dateFormat = "dd."
        return f.string(from: date)
    }

    /// Počet instalací na daný den.
    private func itemsForDate(_ date: Date) -> [WidgetInstallationItem] {
        let start = calendar.startOfDay(for: date)
        return itemsGroupedByDay.first(where: { calendar.isDate($0.dayStart, inSameDayAs: start) })?.items ?? []
    }

    /// Nápis pod datem vlevo: „Přihlaste se“, „0 instalací“, nebo „X instalace/instalací“.
    private func countLabelForToday(count: Int) -> String {
        if !entry.hasData {
            return "Přihlaste se"
        }
        if entry.items.isEmpty || count == 0 {
            return "0 instalací"
        }
        if count == 1 {
            return "1 instalace"
        }
        if count >= 2 && count <= 4 {
            return "\(count) instalace"
        }
        return "\(count) instalací"  // 5+
    }

    /// Statusová zpráva pro hlavní widget: přihlášení, „Dnes se nic neinstaluje“, nebo počet instalací.
    private func statusMessageForToday(count: Int) -> String {
        if !entry.hasData {
            return "Přihlaste se"
        }
        if entry.items.isEmpty || count == 0 {
            return "Dnes se nic neinstaluje"
        }
        if count == 1 {
            return "1 instalace"
        }
        if count >= 2 && count <= 4 {
            return "\(count) instalace"
        }
        return "\(count) instalací"  // 5+
    }

    private func installationLine(_ item: WidgetInstallationItem) -> String {
        var parts: [String] = [item.item_name]
        if let t = item.installation_time, !t.isEmpty { parts.append(t) }
        parts.append("Obj. \(item.displayOrder)")
        return parts.joined(separator: " · ")
    }

    /// Jen co se spouští a v kolik (název + čas). Čas z DB/API je už lokální HH:MM.
    private func installationNameAndTime(_ item: WidgetInstallationItem) -> String {
        guard let t = item.installation_time, !t.isEmpty else { return item.item_name }
        return "\(item.item_name) · \(t)"
    }
}

struct ProvikartInstallationsWidget: Widget {
    let kind: String = "ProvikartInstallationsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProvikartInstallationsWidgetProvider()) { entry in
            ProvikartInstallationsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Instalace")
        .description("Přehled, kdy se co spouští – datum a čas instalací.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryRectangular, .accessoryInline
        ])
    }
}
