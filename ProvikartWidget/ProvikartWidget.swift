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
        let commission = suite?.object(forKey: "widget_commission") as? Double
        let currency = suite?.string(forKey: "widget_currency") ?? "Kč"
        let monthLabel = suite?.string(forKey: "widget_month_label")
        return WidgetCommissionEntry(
            date: Date(),
            commission: commission,
            currency: currency,
            monthLabel: monthLabel,
            hasData: commission != nil
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
            default:
                mediumView
            }
        }
        .containerBackground(for: .widget) {
            Color(uiColor: .secondarySystemGroupedBackground)
        }
        .widgetURL(URL(string: "provikart://"))
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
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
