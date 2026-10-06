//
//  CommissionLiveActivityView.swift
//  ProvikartWidget
//
//  Zobrazení Live Activity – provize a postup k cíli (Lock Screen, Dynamic Island).
//

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Zámek a malá rodina

struct CommissionLiveActivityBannerView: View {
    @Environment(\.activityFamily) private var family
    let context: ActivityViewContext<CommissionLiveActivityAttributes>
    let state: CommissionLiveActivityAttributes.ContentState

    private func formatCommission(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    private func scaleLabel(_ value: Double) -> String {
        if value >= 1000 {
            let k = value / 1000.0
            return k == floor(k) ? "\(Int(k))k" : String(format: "%.1fk", k)
        }
        return String(format: "%.0f", value)
    }

    private var progress: Double {
        guard state.goal > 0 else { return 0 }
        return min(state.commission / state.goal, 1.0)
    }

    var body: some View {
        Group {
            if family == .small {
                watchCard
            } else {
                lockCard
            }
        }
        .widgetURL(URL(string: "provikart://"))
    }

    private var watchCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "creditcard.fill")
                .font(.caption.weight(.bold))
            Text("Provize")
                .font(.caption.weight(.bold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(amountText)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
        .foregroundStyle(ProvikartActivityPalette.ink)
    }

    private var lockCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "creditcard.fill")
                    .font(.subheadline.weight(.bold))
                Text("Provize za měsíc")
                    .font(.subheadline.weight(.bold))
                if let label = state.monthLabel, !label.isEmpty {
                    Text("· \(label)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ProvikartActivityPalette.ink.opacity(0.62))
                }
                Spacer()
            }

            if state.isHidden {
                Text("– – – –")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatCommission(state.commission))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text(state.currency)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ProvikartActivityPalette.ink.opacity(0.62))
                }
            }

            ProgressView(value: progress)
                .tint(ProvikartActivityPalette.ink)

            HStack {
                Text("0")
                Spacer()
                Text(scaleLabel(state.goal / 2))
                Spacer()
                Text(scaleLabel(state.goal))
            }
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(ProvikartActivityPalette.ink.opacity(0.62))
        }
        .padding(16)
        .foregroundStyle(ProvikartActivityPalette.ink)
        .activityBackgroundTint(ProvikartActivityPalette.yellow)
        .accessibilityElement(children: .combine)
    }

    private var amountText: String {
        if state.isHidden { return "••••" }
        return formatCommission(state.commission) + " " + state.currency
    }
}

// MARK: - Widget (Live Activity)

struct CommissionLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CommissionLiveActivityAttributes.self) { context in
            CommissionLiveActivityBannerView(context: context, state: context.state)
        } dynamicIsland: { context in
            let state = context.state
            let progress = state.goal > 0 ? min(state.commission / state.goal, 1.0) : 0.0
            let percent = state.isHidden ? "–" : "\(Int(progress * 100))%"
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "creditcard.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ProvikartActivityPalette.yellow)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(percent)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ProvikartActivityPalette.yellow)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("Provize")
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let label = state.monthLabel, !label.isEmpty {
                            Text(label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                        }
                        ProgressView(value: progress)
                            .tint(ProvikartActivityPalette.yellow)
                    }
                }
            } compactLeading: {
                Image(systemName: "creditcard.fill")
                    .foregroundStyle(ProvikartActivityPalette.yellow)
            } compactTrailing: {
                Text("100%")
                    .monospacedDigit()
                    .hidden()
                    .overlay(alignment: .trailing) {
                        Text(percent)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(ProvikartActivityPalette.yellow)
                    .lineLimit(1)
            } minimal: {
                Image(systemName: "creditcard.fill")
                    .foregroundStyle(ProvikartActivityPalette.yellow)
            }
            .widgetURL(URL(string: "provikart://"))
            .keylineTint(ProvikartActivityPalette.yellow)
        }
        .supplementalActivityFamilies([.small])
    }
}
