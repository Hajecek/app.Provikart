//
//  ComplicationViews.swift
//  ProvikartWatch Watch App
//
//  WidgetKit komplikace pro ciferník hodinek – provize za aktuální měsíc.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct CommissionTimelineEntry: TimelineEntry {
    let date: Date
    let commission: Double?
    let currency: String
    let monthLabel: String?
    let isAuthenticated: Bool
}

// MARK: - Timeline Provider

struct CommissionTimelineProvider: TimelineProvider {
    private let appGroupIdentifier = "group.com.hajecek.provikartApp"

    func placeholder(in context: Context) -> CommissionTimelineEntry {
        CommissionTimelineEntry(
            date: Date(),
            commission: 12500,
            currency: "Kč",
            monthLabel: "Březen 2026",
            isAuthenticated: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CommissionTimelineEntry) -> Void) {
        let entry = loadFromAppGroup()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CommissionTimelineEntry>) -> Void) {
        let token = loadToken()
        guard let token, !token.isEmpty else {
            let entry = CommissionTimelineEntry(
                date: Date(),
                commission: nil,
                currency: "Kč",
                monthLabel: nil,
                isAuthenticated: false
            )
            let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60)))
            completion(timeline)
            return
        }

        Task {
            do {
                let response = try await WatchCommissionService().fetchCommission(token: token)
                saveToAppGroup(response)
                let entry = CommissionTimelineEntry(
                    date: Date(),
                    commission: response.commission,
                    currency: response.currency,
                    monthLabel: response.month_label,
                    isAuthenticated: true
                )
                let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60)))
                completion(timeline)
            } catch {
                let entry = loadFromAppGroup()
                let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
                completion(timeline)
            }
        }
    }

    private func loadToken() -> String? {
        if let token = UserDefaults(suiteName: appGroupIdentifier)?.string(forKey: "widget_auth_token"), !token.isEmpty {
            return token
        }
        return UserDefaults.standard.string(forKey: "Provikart.watchAuthToken")
    }

    private func loadFromAppGroup() -> CommissionTimelineEntry {
        let suite = UserDefaults(suiteName: appGroupIdentifier)
        let commission = suite?.object(forKey: "widget_commission") as? Double
        let currency = suite?.string(forKey: "widget_currency") ?? "Kč"
        let monthLabel = suite?.string(forKey: "widget_month_label")
        let hasToken = loadToken() != nil

        return CommissionTimelineEntry(
            date: Date(),
            commission: commission,
            currency: currency,
            monthLabel: monthLabel,
            isAuthenticated: hasToken
        )
    }

    private func saveToAppGroup(_ response: WatchCommissionResponse) {
        guard let suite = UserDefaults(suiteName: appGroupIdentifier) else { return }
        suite.set(NSNumber(value: response.commission), forKey: "widget_commission")
        suite.set(response.currency, forKey: "widget_currency")
        suite.set(response.month_label, forKey: "widget_month_label")
        suite.set(Date(), forKey: "widget_last_updated")
    }
}

// MARK: - Complication Views

struct CircularComplicationView: View {
    let entry: CommissionTimelineEntry

    var body: some View {
        if entry.isAuthenticated, let commission = entry.commission {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 10))
                    Text(shortCommission(commission))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.6)
                }
            }
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "creditcard")
                    .font(.system(size: 16))
            }
        }
    }

    private func shortCommission(_ value: Double) -> String {
        if value >= 1000 {
            let k = value / 1000.0
            return String(format: k == floor(k) ? "%.0fk" : "%.1fk", k)
        }
        return String(format: "%.0f", value)
    }
}

struct RectangularComplicationView: View {
    let entry: CommissionTimelineEntry

    var body: some View {
        if entry.isAuthenticated, let commission = entry.commission {
            HStack(spacing: 6) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 18))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Provize")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(formatCommission(commission))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)

                        Text(entry.currency)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "creditcard")
                    .font(.system(size: 18))

                Text("Přihlaste se\nna iPhonu")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
        }
    }

    private func formatCommission(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }
}

struct InlineComplicationView: View {
    let entry: CommissionTimelineEntry

    var body: some View {
        if entry.isAuthenticated, let commission = entry.commission {
            Text("Provize: \(formatCommission(commission)) \(entry.currency)")
        } else {
            Text("Provikart")
        }
    }

    private func formatCommission(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }
}

// MARK: - Widget Configuration

struct ComplicationEntryView: View {
    @Environment(\.widgetFamily) var widgetFamily
    let entry: CommissionTimelineEntry

    var body: some View {
        switch widgetFamily {
        case .accessoryCircular:
            CircularComplicationView(entry: entry)
        case .accessoryRectangular:
            RectangularComplicationView(entry: entry)
        case .accessoryInline:
            InlineComplicationView(entry: entry)
        default:
            CircularComplicationView(entry: entry)
        }
    }
}

struct ProvikartCommissionComplication: Widget {
    let kind = "ProvikartWatchCommission"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CommissionTimelineProvider()) { entry in
            if #available(watchOS 10.0, *) {
                ComplicationEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                ComplicationEntryView(entry: entry)
                    .padding()
            }
        }
        .configurationDisplayName("Provize")
        .description("Provize za aktuální měsíc")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

// MARK: - Widget Bundle

struct ProvikartWatchWidgets: WidgetBundle {
    var body: some Widget {
        ProvikartCommissionComplication()
    }
}
