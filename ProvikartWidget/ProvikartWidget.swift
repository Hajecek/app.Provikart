//
//  ProvikartWidget.swift
//  ProvikartWidget
//
//  Widget zobrazující aktuální měsíční provizi z App Group.
//

import WidgetKit
import SwiftUI

private let appGroupIdentifier = "group.com.hajecek.provikartApp"

// MARK: - Data

struct WidgetCommissionEntry: TimelineEntry {
    let date: Date
    let commission: Double?
    let currency: String
    let monthLabel: String?
    let hasData: Bool
}

// MARK: - Timeline Provider

struct ProvikartWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetCommissionEntry {
        WidgetCommissionEntry(date: Date(), commission: 12_450, currency: "Kč", monthLabel: "Březen 2025", hasData: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetCommissionEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetCommissionEntry>) -> Void) {
        let entry = loadEntry()
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func loadEntry() -> WidgetCommissionEntry {
        let suite = UserDefaults(suiteName: appGroupIdentifier)
        let rawCommission = suite?.object(forKey: "widget_commission")
        let commission: Double? = (rawCommission as? NSNumber)?.doubleValue ?? rawCommission as? Double
        let currency = suite?.string(forKey: "widget_currency") ?? "Kč"
        let monthLabel = suite?.string(forKey: "widget_month_label")
        let hasData = suite?.object(forKey: "widget_commission") != nil
        return WidgetCommissionEntry(
            date: Date(),
            commission: commission,
            currency: currency,
            monthLabel: monthLabel,
            hasData: hasData
        )
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
        .containerBackground(for: .widget) {
            Color(uiColor: .secondarySystemGroupedBackground)
        }
        .widgetURL(URL(string: "provikart://"))
    }

    // Zamykací obrazovka – kruh (jen číslo)
    private var accessoryCircularView: some View {
        ZStack {
            if entry.hasData, let value = entry.commission {
                VStack(spacing: 0) {
                    Text(formatCommission(value))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(entry.currency)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 20, weight: .medium))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Zamykací obrazovka – obdélník
    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Provize", systemImage: "creditcard.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            if entry.hasData, let value = entry.commission {
                Text(formatCommission(value) + " " + entry.currency)
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
            Text("Provize \(formatCommission(value)) \(entry.currency)")
                .font(.system(size: 14, weight: .medium))
        } else {
            Text("Provikart – přihlaste se")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // Malý widget – styl jako nativní iOS (Peněženka, Akcie)
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("PROVIZE")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            Spacer(minLength: 8)
            if entry.hasData, let value = entry.commission {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(formatCommission(value))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(entry.currency)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Přihlaste se")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(16)
    }

    // Střední widget – čistý dvousloupcový layout
    private var mediumView: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Provize za měsíc")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                if let label = entry.monthLabel, !label.isEmpty {
                    Text(label)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 12)
            if entry.hasData, let value = entry.commission {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatCommission(value))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(entry.currency)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Přihlaste se")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
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
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetReportsEntry>) -> Void) {
        let entry = loadEntry()
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func loadEntry() -> WidgetReportsEntry {
        let suite = UserDefaults(suiteName: appGroupIdentifier)
        let rawCount = suite?.object(forKey: "widget_reports_incomplete_count")
        let count: Int? = (rawCount as? NSNumber)?.intValue ?? rawCount as? Int
        let hasData = suite?.object(forKey: "widget_reports_incomplete_count") != nil
        return WidgetReportsEntry(
            date: Date(),
            incompleteCount: count,
            hasData: hasData
        )
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
        .containerBackground(for: .widget) {
            Color(uiColor: .secondarySystemGroupedBackground)
        }
        .widgetURL(URL(string: "provikart://"))
    }

    // Zamykací obrazovka – kruh (jen číslo)
    private var reportsAccessoryCircularView: some View {
        ZStack {
            if entry.hasData, let count = entry.incompleteCount {
                Text("\(count)")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
            } else {
                Image(systemName: "exclamationmark.bubble.fill")
                    .font(.system(size: 20, weight: .medium))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("REPORTY")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            Spacer(minLength: 8)
            if entry.hasData, let count = entry.incompleteCount {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(count)")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(count == 1 ? "nedokončený" : "nedokončených")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("Přihlaste se")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(16)
    }

    private var reportsMediumView: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Nedokončené reporty")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text("Problémy k vyřešení")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 12)
            if entry.hasData, let count = entry.incompleteCount {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(count)")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(count == 1 ? "report" : "reportů")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Přihlaste se")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
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
